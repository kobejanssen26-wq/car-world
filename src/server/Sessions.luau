-- Holds each player's authoritative profile and pushes state snapshots to the owning client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Sites = require(script.Parent.Sites)

local Sessions = {}

local profiles: { [Player]: any } = {}
local pending: { [Player]: boolean } = {}
local stateRemote: RemoteEvent? = nil

function Sessions.add(player: Player, profile)
	profiles[player] = profile
	profile.discovered["hub"] = true
end

function Sessions.remove(player: Player)
	profiles[player] = nil
	pending[player] = nil
end

function Sessions.profile(player: Player)
	return profiles[player]
end

function Sessions.all()
	return profiles
end

function Sessions.snapshot(player: Player)
	local p = profiles[player]
	if not p then
		return nil
	end
	local items = {}
	for uid, id in p.items do
		table.insert(items, { uid = uid, id = id })
	end
	table.sort(items, function(a, b)
		return tonumber(a.uid) < tonumber(b.uid)
	end)
	local vehicles = {}
	for _, v in p.vehicles do
		table.insert(vehicles, { id = v.id, name = v.name, slots = v.slots, fuel = v.fuel, health = v.health })
	end
	local discovered = {}
	for id in p.discovered do
		local s = Sites.ById[id]
		if s then
			table.insert(discovered, { id = s.id, name = s.name, kind = s.kind, x = s.x, z = s.z, tier = s.tier, service = s.service == true })
		end
	end
	return {
		money = p.money,
		items = items,
		vehicles = vehicles,
		active = p.active,
		discovered = discovered,
		maxItems = Config.MaxItems,
		maxVehicles = Config.MaxVehicles,
	}
end

-- Coalesces multiple mutations in one frame into a single remote call.
function Sessions.push(player: Player)
	if pending[player] or not profiles[player] then
		return
	end
	pending[player] = true
	task.defer(function()
		pending[player] = nil
		if player.Parent and profiles[player] then
			if not stateRemote then
				stateRemote = Remotes.get("State")
			end
			(stateRemote :: RemoteEvent):FireClient(player, Sessions.snapshot(player))
		end
	end)
end

function Sessions.notify(player: Player, text: string, kind: string?)
	Remotes.get("Notify"):FireClient(player, text, kind or "info")
end

return Sessions
