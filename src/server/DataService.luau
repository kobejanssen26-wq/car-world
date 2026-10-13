-- DataStore persistence with session locking, retries and data-loss protection.
--  * Profiles are only saved if they were successfully loaded (no overwriting real data with defaults).
--  * UpdateAsync + a session lock prevent two servers writing the same profile.
--  * Failures retry with exponential backoff; if loading ultimately fails the player is kicked rather than
--    given a blank profile.
--  * In Studio without API access an in-memory fallback is used (clearly warned about).
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Profile = require(Shared.Profile)

local DataService = {}

local STORE_NAME = "CarWorld_Profiles_v1"
local LOCK_TIMEOUT = 120 -- seconds before another server's lock is considered dead
local MAX_ATTEMPTS = 5

local store = nil
local offline = false -- true when DataStores are unavailable in Studio
local memory = {} -- offline fallback
local loaded = {} -- [player] = profile that is safe to save

local function keyFor(player: Player)
	return "Player_" .. player.UserId
end

local function getStore()
	if offline then
		return nil
	end
	if not store then
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(STORE_NAME)
		end)
		if ok then
			store = result
		else
			if RunService:IsStudio() then
				warn("[CarWorld] DataStore unavailable in Studio - progress will NOT be saved. Enable 'Enable Studio Access to API Services'.")
				offline = true
				return nil
			end
			error(result)
		end
	end
	return store
end

-- Retry a DataStore call with exponential backoff. Returns (ok, result).
local function withRetry(fn)
	local lastErr
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if RunService:IsStudio() and tostring(result):find("StudioAccessToApisNotAllowed") then
			warn("[CarWorld] DataStore API access disabled in Studio - using in-memory profiles (nothing will persist).")
			offline = true
			return false, "offline"
		end
		warn(("[CarWorld] DataStore attempt %d/%d failed: %s"):format(attempt, MAX_ATTEMPTS, tostring(result)))
		task.wait(2 ^ attempt * 0.5)
	end
	return false, lastErr
end

-- Returns a profile table, or nil + reason. Never returns a blank profile for a failed load.
function DataService.load(player: Player)
	local ds = getStore()
	if not ds then
		local p = Profile.reconcile(memory[player.UserId])
		loaded[player] = p
		return p
	end
	local key = keyFor(player)
	for attempt = 1, 6 do
		local lockedByOther = false
		local ok, data = withRetry(function()
			return ds:UpdateAsync(key, function(old)
				old = old or {}
				local lock = old.lock
				if lock and lock.jobId ~= game.JobId and os.time() - lock.t < LOCK_TIMEOUT then
					lockedByOther = true
					return nil -- cancel the write
				end
				old.lock = { jobId = game.JobId, t = os.time() }
				return old
			end)
		end)
		if offline then
			local p = Profile.reconcile(nil)
			loaded[player] = p
			return p
		end
		if not ok then
			return nil, "DataStore error: " .. tostring(data)
		end
		if lockedByOther then
			-- the previous server is probably still saving on leave; wait for it to release
			task.wait(5)
		else
			local p = Profile.reconcile(data and data.data)
			loaded[player] = p
			return p
		end
	end
	return nil, "Your data is still in use by another server. Please rejoin in a minute."
end

-- Save a loaded profile. release = true clears the session lock (leaving the game).
function DataService.save(player: Player, profile, release: boolean?)
	if loaded[player] ~= profile then
		return false -- never save a profile we did not load
	end
	local ds = getStore()
	if not ds then
		memory[player.UserId] = profile
		return true
	end
	local snapshot = profile
	local ok, err = withRetry(function()
		return ds:UpdateAsync(keyFor(player), function(old)
			old = old or {}
			local lock = old.lock
			if lock and lock.jobId ~= game.JobId and os.time() - lock.t < LOCK_TIMEOUT then
				return nil -- another server owns this profile now; do not clobber it
			end
			old.data = snapshot
			old.lock = if release then nil else { jobId = game.JobId, t = os.time() }
			return old
		end)
	end)
	if not ok and not offline then
		warn("[CarWorld] Save failed for " .. player.Name .. ": " .. tostring(err))
	end
	return ok
end

function DataService.release(player: Player)
	loaded[player] = nil
end

return DataService
