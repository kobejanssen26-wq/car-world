-- Creates (server) / fetches (client) every RemoteEvent & RemoteFunction under ReplicatedStorage.Remotes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

-- Server -> client events
local EVENTS = { "State", "Notify", "Loot", "OpenGarage", "Discovered" }
-- Client -> server requests (always validated server-side)
local FUNCTIONS = { "GarageAction" }

function Remotes.create()
	assert(RunService:IsServer())
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in EVENTS do
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = folder
	end
	for _, name in FUNCTIONS do
		local f = Instance.new("RemoteFunction")
		f.Name = name
		f.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

function Remotes.get(name: string)
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	return folder:WaitForChild(name)
end

return Remotes
