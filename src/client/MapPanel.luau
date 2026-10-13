-- Fog-of-war world map: biomes and roads appear once you have been there, discovered locations are
-- markers, tap/click anywhere to drop a waypoint (shown as a compass at the top of the screen).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local WorldData = require(Shared.WorldData)
local UIKit = require(script.Parent.UIKit)
local State = require(script.Parent.State)

local T = UIKit.theme
local MapPanel = {}
local player = Players.LocalPlayer

local WORLD = WorldData.WALL_RADIUS * 2
local frame, canvas, layer, sideList, playerMarker, vehicleMarker, wpMarker
local CANVAS = 560
MapPanel.visitedBiomes = {} :: { [string]: boolean }

local function toCanvas(x: number, z: number): UDim2
	return UDim2.fromOffset((x / WORLD + 0.5) * CANVAS, (z / WORLD + 0.5) * CANVAS)
end

local function revealedBiomes()
	local set = table.clone(MapPanel.visitedBiomes)
	for _, s in State.data.discovered do
		local b = WorldData.biomeAt(s.x, s.z)
		set[b.id] = true
	end
	return set
end

local KIND_COLOR = {
	Hub = T.accent, Outpost = T.accent, Garage = Color3.fromRGB(120, 190, 255), Barn = Color3.fromRGB(230, 110, 90),
	Warehouse = Color3.fromRGB(190, 190, 200), Scrapyard = Color3.fromRGB(200, 150, 90), Wreck = Color3.fromRGB(230, 200, 90),
	Cache = Color3.fromRGB(210, 120, 255),
}

local function line(parent, x1, z1, x2, z2, color, thickness)
	local a, b = toCanvas(x1, z1), toCanvas(x2, z2)
	local dx, dy = b.X.Offset - a.X.Offset, b.Y.Offset - a.Y.Offset
	local len = math.sqrt(dx * dx + dy * dy)
	UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(len, thickness),
		Position = UDim2.fromOffset((a.X.Offset + b.X.Offset) / 2, (a.Y.Offset + b.Y.Offset) / 2),
		Rotation = math.deg(math.atan2(dy, dx)), BackgroundColor3 = color, BorderSizePixel = 0, Parent = parent,
	})
end

local function render()
	UIKit.clear(layer)
	local revealed = revealedBiomes()
	for _, b in WorldData.Biomes do
		if revealed[b.id] then
			local d = b.r * 2 / WORLD * CANVAS
			UIKit.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = toCanvas(b.cx, b.cz), Size = UDim2.fromOffset(d, d),
				BackgroundColor3 = Color3.fromRGB(b.rgb[1], b.rgb[2], b.rgb[3]), BackgroundTransparency = 0.45, BorderSizePixel = 0, Parent = layer,
			}, { UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
			UIKit.label({
				AnchorPoint = Vector2.new(0.5, 0.5), Position = toCanvas(b.cx, b.cz + b.r * 0.55), Size = UDim2.fromOffset(160, 20),
				Text = b.name:upper(), TextSize = 12, TextColor3 = Color3.new(1, 1, 1), TextTransparency = 0.25, TextXAlignment = Enum.TextXAlignment.Center, Parent = layer,
			})
		end
	end
	for _, road in WorldData.Roads do
		for i = 1, #road.pts - 1 do
			local a, b = road.pts[i], road.pts[i + 1]
			if revealed[WorldData.biomeAt(a[1], a[2]).id] or revealed[WorldData.biomeAt(b[1], b[2]).id] then
				line(layer, a[1], a[2], b[1], b[2], road.surface == "asphalt" and Color3.fromRGB(70, 70, 76) or Color3.fromRGB(150, 120, 80), 4)
			end
		end
	end
	-- markers
	for _, s in State.data.discovered do
		local col = KIND_COLOR[s.kind] or T.text
		local m = UIKit.new("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = toCanvas(s.x, s.z), Size = UDim2.fromOffset(s.service and 18 or 13, s.service and 18 or 13),
			BackgroundColor3 = col, Text = "", ZIndex = 5, Parent = layer,
		}, { UIKit.new("UICorner", { CornerRadius = UDim.new(s.service and 0.2 or 0.5, 0) }), UIKit.stroke(Color3.new(0, 0, 0), 1.5) })
		m.Activated:Connect(function()
			State.setWaypoint(s.x, s.z, s.name)
		end)
		UIKit.label({
			AnchorPoint = Vector2.new(0.5, 0), Position = toCanvas(s.x, s.z) + UDim2.fromOffset(0, 9), Size = UDim2.fromOffset(120, 14),
			Text = s.name, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3, ZIndex = 5, Parent = layer,
		})
	end
	-- side list
	UIKit.clear(sideList)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local entries = table.clone(State.data.discovered)
	table.sort(entries, function(a, b)
		if not root then
			return a.name < b.name
		end
		local da = (a.x - root.Position.X) ^ 2 + (a.z - root.Position.Z) ^ 2
		local db = (b.x - root.Position.X) ^ 2 + (b.z - root.Position.Z) ^ 2
		return da < db
	end)
	for i, s in entries do
		local dist = root and math.floor(math.sqrt((s.x - root.Position.X) ^ 2 + (s.z - root.Position.Z) ^ 2)) or 0
		UIKit.button({
			Size = UDim2.new(1, -8, 0, 36), LayoutOrder = i, BackgroundColor3 = T.panel, TextColor3 = T.text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
			Text = ("  %s%s\n  %d studs"):format(s.name, s.service and "  ⛽🔧" or "", dist), Parent = sideList,
		}, function()
			State.setWaypoint(s.x, s.z, s.name)
		end)
	end
	UIKit.label({ Size = UDim2.new(1, -8, 0, 40), LayoutOrder = 999, Text = "Tap the map to place a custom waypoint.\nHidden places only show up once you find them.", TextSize = 12, TextColor3 = T.dim, Parent = sideList })

	playerMarker = UIKit.label({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(24, 24), Text = "▲", TextSize = 22, TextColor3 = Color3.fromRGB(80, 255, 120), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0, ZIndex = 8, Parent = layer })
	vehicleMarker = UIKit.label({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(24, 24), Text = "■", TextSize = 18, TextColor3 = T.accent, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0, ZIndex = 7, Visible = false, Parent = layer })
	wpMarker = UIKit.label({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(24, 24), Text = "◆", TextSize = 24, TextColor3 = Color3.fromRGB(255, 80, 200), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0, ZIndex = 9, Visible = false, Parent = layer })
end

function MapPanel.create(gui: ScreenGui)
	frame = UIKit.panel(gui, "World Map", UDim2.new(0, CANVAS + 260, 0, CANVAS + 64), function()
		frame.Visible = false
	end)
	local content = frame:FindFirstChildWhichIsA("Frame")
	canvas = UIKit.new("Frame", {
		Position = UDim2.fromOffset(12, 4), Size = UDim2.fromOffset(CANVAS, CANVAS), BackgroundColor3 = Color3.fromRGB(14, 16, 20), ClipsDescendants = true, Parent = content,
	}, { UIKit.corner(8), UIKit.stroke(T.panel2, 2) })
	layer = UIKit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = canvas })
	-- clicking empty map sets a waypoint
	canvas.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local rel = (Vector2.new(input.Position.X, input.Position.Y) - canvas.AbsolutePosition) / canvas.AbsoluteSize
			local x, z = (rel.X - 0.5) * WORLD, (rel.Y - 0.5) * WORLD
			State.setWaypoint(x, z, "Waypoint")
		end
	end)
	sideList = UIKit.scroll({ Position = UDim2.new(0, CANVAS + 24, 0, 4), Size = UDim2.new(0, 220, 0, CANVAS), Parent = content })
	UIKit.list(sideList, 4)

	State.changed.Event:Connect(function()
		if frame.Visible then
			render()
		end
	end)
	RunService.RenderStepped:Connect(function()
		if not frame.Visible or not playerMarker or not playerMarker.Parent then
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			playerMarker.Position = toCanvas(root.Position.X, root.Position.Z)
			local look = root.CFrame.LookVector
			playerMarker.Rotation = math.deg(math.atan2(look.X, -look.Z))
		end
		local car = Workspace:FindFirstChild("Vehicles") and Workspace.Vehicles:FindFirstChild(player.Name .. "_Car")
		if car and car.PrimaryPart then
			vehicleMarker.Visible = true
			vehicleMarker.Position = toCanvas(car.PrimaryPart.Position.X, car.PrimaryPart.Position.Z)
		else
			vehicleMarker.Visible = false
		end
		local wp = State.waypoint
		wpMarker.Visible = wp ~= nil
		if wp then
			wpMarker.Position = toCanvas(wp.x, wp.z)
		end
	end)
	return frame
end

function MapPanel.toggle()
	frame.Visible = not frame.Visible
	if frame.Visible then
		render()
	end
end

function MapPanel.hide()
	frame.Visible = false
end

return MapPanel
