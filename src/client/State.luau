-- Client-side mirror of the server snapshot, plus local-only UI state (waypoint).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local State = {}

State.data = {
	money = 0, items = {}, vehicles = {}, active = nil, discovered = {}, maxItems = 60, maxVehicles = 3,
}
State.waypoint = nil -- { x, z, name }
State.changed = Instance.new("BindableEvent")
State.waypointChanged = Instance.new("BindableEvent")

function State.init()
	Remotes.get("State").OnClientEvent:Connect(function(snapshot)
		State.data = snapshot
		State.changed:Fire()
	end)
end

function State.vehicle(id: string?)
	if not id then
		return nil
	end
	for _, v in State.data.vehicles do
		if v.id == id then
			return v
		end
	end
	return nil
end

function State.setWaypoint(x: number?, z: number?, name: string?)
	State.waypoint = x and { x = x, z = z, name = name or "Waypoint" } or nil
	State.waypointChanged:Fire()
end

-- Calls a garage action; returns ok, message.
function State.action(action: string, payload: { [string]: any }?): (boolean, string?)
	local ok, res = pcall(function()
		return Remotes.get("GarageAction"):InvokeServer(action, payload or {})
	end)
	if not ok then
		return false, "Request failed"
	end
	return res.ok == true, res.msg
end

return State
