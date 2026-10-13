-- Client entry point: builds the UI, wires remotes, keybinds and the vehicle controller.
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)
local InventoryPanel = require(script.Parent.InventoryPanel)
local GaragePanel = require(script.Parent.GaragePanel)
local MapPanel = require(script.Parent.MapPanel)
local Ambience = require(script.Parent.Ambience)
local VehicleController = require(script.Parent.VehicleController)

local player = Players.LocalPlayer

State.init()
local gui = Hud.create()

-- scale the whole UI for small screens (phones / tablets)
local scale = Instance.new("UIScale")
scale.Parent = gui
local function updateScale()
	local cam = Workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min(v.X / 1280, v.Y / 760), 0.55, 1.15)
end
updateScale()
Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

InventoryPanel.create(gui)
GaragePanel.create(gui, Hud.toast)
MapPanel.create(gui)

local function closeAll(except: string?)
	if except ~= "inv" then InventoryPanel.hide() end
	if except ~= "map" then MapPanel.hide() end
	if except ~= "garage" then GaragePanel.hide() end
end

Hud.callbacks.inventory = function()
	closeAll("inv")
	InventoryPanel.toggle()
end
Hud.callbacks.map = function()
	closeAll("map")
	MapPanel.toggle()
end
Hud.callbacks.flip = function()
	local ok, msg = State.action("Flip")
	if not ok and msg then Hud.toast(msg, "warn") end
end
Hud.callbacks.tow = function()
	local ok, msg = State.action("Tow")
	if not ok and msg then Hud.toast(msg, "warn") end
end

-- keybinds (desktop); touch players use the on-screen buttons
ContextActionService:BindAction("CW_Inventory", function(_, state)
	if state == Enum.UserInputState.Begin then Hud.callbacks.inventory() end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.I)
ContextActionService:BindAction("CW_Map", function(_, state)
	if state == Enum.UserInputState.Begin then Hud.callbacks.map() end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.M)
ContextActionService:BindAction("CW_Flip", function(_, state)
	if state == Enum.UserInputState.Begin and State.data.active then Hud.callbacks.flip() end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.R)

-- server events
Remotes.get("Notify").OnClientEvent:Connect(function(text, kind)
	Hud.toast(text, kind)
end)
Remotes.get("Loot").OnClientEvent:Connect(function(items, cash, label)
	Hud.loot(items, cash, label)
end)
Remotes.get("OpenGarage").OnClientEvent:Connect(function()
	closeAll("garage")
	GaragePanel.open()
end)
Remotes.get("Discovered").OnClientEvent:Connect(function(name, hidden)
	Hud.toast((hidden and "Secret found: " or "Discovered: ") .. name, "good")
end)

-- close the garage when walking away from it
task.spawn(function()
	while true do
		task.wait(1)
		if GaragePanel.isOpen() then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local near = false
			if root then
				for _, s in State.data.discovered do
					if s.service and (Vector3.new(s.x, root.Position.Y, s.z) - root.Position).Magnitude < 90 then
						near = true
					end
				end
			end
			if not near then
				GaragePanel.hide()
			end
		end
	end
end)

VehicleController.start()
VehicleController.onChanged.Event:Connect(function(model)
	Hud.currentVehicle = model
end)

Ambience.start(function(biome)
	MapPanel.visitedBiomes[biome.id] = true
	Hud.banner(biome.name)
end)
