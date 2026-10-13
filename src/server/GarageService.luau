-- Handles every client request from the garage UI. The client only *asks*; this module validates
-- ownership, distance, rate limits and payload types, then mutates the profile through Shared.Profile.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Profile = require(Shared.Profile)
local Remotes = require(Shared.Remotes)
local VehicleStats = require(Shared.VehicleStats)
local Sessions = require(script.Parent.Sessions)
local SiteBuilder = require(script.Parent.SiteBuilder)
local VehicleService = require(script.Parent.VehicleService)

local GarageService = {}

local buckets: { [Player]: { tokens: number, t: number } } = {}
local towCooldown: { [Player]: number } = {}

local function allow(player: Player): boolean
	local b = buckets[player]
	local now = os.clock()
	if not b then
		b = { tokens = Config.RemoteRatePerSecond, t = now }
		buckets[player] = b
	end
	b.tokens = math.min(Config.RemoteRatePerSecond, b.tokens + (now - b.t) * Config.RemoteRatePerSecond)
	b.t = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Nearest service point (garage / depot) to a position, and its distance.
local function nearestService(pos: Vector3)
	local best, bd = nil, math.huge
	for _, s in SiteBuilder.services do
		local d = (s.pos - pos).Magnitude
		if d < bd then
			best, bd = s, d
		end
	end
	return best, bd
end

local function nearService(player: Player)
	local root = rootOf(player)
	if not root then
		return nil
	end
	local s, d = nearestService(root.Position)
	if s and d <= Config.ServiceRange then
		return s
	end
	return nil
end

-- Find a free spot on the pad (other players' parked cars may already be there).
local function freeSpawnCF(base: CFrame): CFrame
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { Workspace:FindFirstChild("Vehicles") :: Instance }
	local offsets = { 0, 18, -18, 36, -36, 54 }
	for _, off in offsets do
		local cf = base * CFrame.new(off, 0, 0)
		if #Workspace:GetPartBoundsInBox(cf, Vector3.new(10, 6, 18), overlap) == 0 then
			return cf
		end
	end
	return base * CFrame.new(0, 12, 0)
end

local function str(v, maxLen: number): string?
	if type(v) == "string" and #v <= maxLen then
		return v
	end
	return nil
end

local Actions = {}

function Actions.CreateVehicle(player, profile, payload)
	local name = str(payload.name, 24) or ""
	return Profile.createVehicle(profile, (name:gsub("[^%w _%-']", "")))
end

function Actions.DeleteVehicle(player, profile, payload)
	local vid = str(payload.vehicleId, 16)
	if not vid then
		return false, "Bad request"
	end
	if profile.active == vid then
		VehicleService.despawn(player)
	end
	return Profile.deleteVehicle(profile, vid)
end

function Actions.Install(player, profile, payload)
	local vid, uid = str(payload.vehicleId, 16), str(payload.uid, 16)
	if not vid or not uid then
		return false, "Bad request"
	end
	if profile.active == vid then
		VehicleService.despawn(player) -- can't rebuild a car that is out on the road
	end
	return Profile.install(profile, vid, uid)
end

function Actions.Uninstall(player, profile, payload)
	local vid, slot = str(payload.vehicleId, 16), str(payload.slot, 16)
	if not vid or not slot then
		return false, "Bad request"
	end
	if profile.active == vid then
		VehicleService.despawn(player)
	end
	return Profile.uninstall(profile, vid, slot)
end

function Actions.Buy(player, profile, payload)
	local id = str(payload.itemId, 32)
	if not id then
		return false, "Bad request"
	end
	return Profile.buy(profile, id)
end

function Actions.Sell(player, profile, payload)
	local uid = str(payload.uid, 16)
	if not uid then
		return false, "Bad request"
	end
	return Profile.sell(profile, uid)
end

function Actions.Refuel(player, profile, payload)
	local vid = str(payload.vehicleId, 16)
	if not vid then
		return false, "Bad request"
	end
	local ok, err = Profile.refuel(profile, vid, nil)
	if ok then
		VehicleService.refresh(player)
	end
	return ok, err
end

function Actions.Repair(player, profile, payload)
	local vid = str(payload.vehicleId, 16)
	if not vid then
		return false, "Bad request"
	end
	local ok, err = Profile.repair(profile, vid)
	if ok then
		VehicleService.refresh(player)
	end
	return ok, err
end

function Actions.Spawn(player, profile, payload, service)
	local vid = str(payload.vehicleId, 16)
	local record = vid and Profile.findVehicle(profile, vid)
	if not record then
		return false, "No such vehicle"
	end
	local stats = VehicleStats.compute(record.slots)
	if not stats.complete then
		return false, "Vehicle is missing parts: " .. table.concat(stats.missing, ", ")
	end
	local model = VehicleService.spawn(player, record, freeSpawnCF(service.spawnCF))
	if not model then
		return false, "Could not spawn vehicle"
	end
	profile.active = record.id
	return true
end

function Actions.Despawn(player, profile)
	VehicleService.despawn(player)
	profile.active = nil
	return true
end

-- Actions that do not need to stand at a garage:
local NoServiceNeeded = { Flip = true, Tow = true }

function Actions.Flip(player)
	return VehicleService.flip(player)
end

-- Emergency tow: bring the active vehicle to the nearest service point for a small fee (or free if broke).
function Actions.Tow(player, profile)
	local entry = VehicleService.getActive(player)
	if not entry then
		return false, "No vehicle in the world"
	end
	if os.clock() - (towCooldown[player] or -1000) < Config.TowCooldown then
		return false, "Tow truck is busy, try again shortly"
	end
	local service = nearestService(entry.body.Position)
	if not service then
		return false, "No garage available"
	end
	towCooldown[player] = os.clock()
	local fee = math.min(profile.money, Config.TowCost)
	profile.money -= fee
	local record = entry.record
	VehicleService.spawn(player, record, freeSpawnCF(service.spawnCF))
	profile.active = record.id
	Sessions.notify(player, ("Towed to %s (fee $%d)."):format(service.name, fee), "info")
	return true
end

function GarageService.init()
	local rf = Remotes.get("GarageAction") :: RemoteFunction
	rf.OnServerInvoke = function(player: Player, action, payload)
		if not allow(player) then
			return { ok = false, msg = "Slow down" }
		end
		local profile = Sessions.profile(player)
		if not profile then
			return { ok = false, msg = "Data not loaded" }
		end
		local handler = type(action) == "string" and Actions[action]
		if not handler or type(payload) ~= "table" and payload ~= nil then
			return { ok = false, msg = "Bad request" }
		end
		payload = payload or {}
		local service = nil
		if not NoServiceNeeded[action] then
			service = nearService(player)
			if not service then
				return { ok = false, msg = "Go to a garage first" }
			end
		end
		local ok, result, msg = pcall(handler, player, profile, payload, service)
		if not ok then
			warn("[CarWorld] GarageAction error: " .. tostring(result))
			return { ok = false, msg = "Server error" }
		end
		Sessions.push(player)
		-- handlers return (ok, err) or (ok, vehicleId) from createVehicle
		if result == true then
			return { ok = true }
		elseif result == false then
			return { ok = false, msg = msg }
		end
		return { ok = result }
	end
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
		towCooldown[p] = nil
	end)
end

return GarageService
