-- Always-on HUD: cash, toasts, loot popups, biome banner, waypoint compass, vehicle gauges and quick buttons.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Parts = require(Shared.Parts)
local Rarity = require(Shared.Rarity)
local UIKit = require(script.Parent.UIKit)
local State = require(script.Parent.State)

local Hud = {}
local T = UIKit.theme
local player = Players.LocalPlayer

Hud.gui = nil :: ScreenGui?
Hud.callbacks = { inventory = function() end, map = function() end, flip = function() end, tow = function() end, garage = function() end }
Hud.currentVehicle = nil :: Model? -- set by VehicleController

local moneyLabel, toastFrame, lootFrame, banner, compass, compassArrow, compassText
local gauges, flipBtn, towBtn

local TOAST_COLORS = { info = T.text, warn = T.accent, story = Color3.fromRGB(190, 220, 255), good = T.good }

function Hud.toast(text: string, kind: string?)
	local isStory = kind == "story"
	local lbl = UIKit.new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = T.bg, BackgroundTransparency = 0.15,
		TextColor3 = TOAST_COLORS[kind or "info"] or T.text, Font = isStory and Enum.Font.Cartoon or Enum.Font.GothamMedium,
		TextSize = isStory and 18 or 16, TextWrapped = true, Text = text, Parent = toastFrame,
	}, { UIKit.corner(8), UIKit.padding(8) })
	task.delay(isStory and 9 or 4.5, function()
		if lbl.Parent then
			TweenService:Create(lbl, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			task.wait(0.45)
			lbl:Destroy()
		end
	end)
end

function Hud.banner(text: string)
	banner.Text = text
	banner.TextTransparency = 1
	banner.TextStrokeTransparency = 1
	TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 0, TextStrokeTransparency = 0.5 }):Play()
	task.delay(3.2, function()
		if banner.Text == text then
			TweenService:Create(banner, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

function Hud.loot(items: { string }, cash: number, label: string)
	local card = UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = T.bg, BackgroundTransparency = 0.1, Parent = lootFrame,
	}, { UIKit.corner(10), UIKit.stroke(T.accent, 2, 0.4), UIKit.padding(10) })
	UIKit.list(card, 3)
	UIKit.label({ Size = UDim2.new(1, 0, 0, 22), Text = "Searched: " .. label, Font = Enum.Font.GothamBold, TextSize = 17, LayoutOrder = 0, Parent = card })
	local any = false
	for i, id in items do
		any = true
		local p = Parts.ById[id]
		UIKit.label({
			Size = UDim2.new(1, 0, 0, 22), Text = ("%s  [%s]  (%s)"):format(p.name, p.rarity, Parts.SlotLabels[p.slot]),
			TextColor3 = Rarity.color3(p.rarity), Font = Enum.Font.GothamBold, TextSize = 16, LayoutOrder = i, Parent = card,
		})
	end
	if cash > 0 then
		UIKit.label({ Size = UDim2.new(1, 0, 0, 20), Text = "+$" .. cash, TextColor3 = T.good, LayoutOrder = 98, Parent = card })
	end
	if not any then
		UIKit.label({ Size = UDim2.new(1, 0, 0, 20), Text = "No parts this time.", TextColor3 = T.dim, LayoutOrder = 99, Parent = card })
	end
	task.delay(6, function()
		if card.Parent then
			card:Destroy()
		end
	end)
end

local function gauge(parent, y, labelText, color)
	UIKit.label({ Size = UDim2.new(0, 60, 0, 16), Position = UDim2.fromOffset(0, y), Text = labelText, TextSize = 13, TextColor3 = T.dim, Parent = parent })
	local back = UIKit.new("Frame", {
		Size = UDim2.new(1, -64, 0, 10), Position = UDim2.fromOffset(64, y + 3), BackgroundColor3 = T.panel2, Parent = parent,
	}, { UIKit.corner(5) })
	local fill = UIKit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, Parent = back }, { UIKit.corner(5) })
	return fill
end

function Hud.create(): ScreenGui
	local gui = UIKit.new("ScreenGui", {
		Name = "CarWorldUI", ResetOnSpawn = false, IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui"),
	})
	Hud.gui = gui
	local touch = UIKit.isTouch()
	local btnSize = touch and 58 or 46

	-- cash
	moneyLabel = UIKit.label({
		Size = UDim2.fromOffset(170, 36), Position = UDim2.fromOffset(12, 8), Text = "$0", TextSize = 24,
		Font = Enum.Font.GothamBlack, TextColor3 = T.good, BackgroundTransparency = 0.25, BackgroundColor3 = T.bg,
		TextXAlignment = Enum.TextXAlignment.Center, Parent = gui,
	}, { UIKit.corner(8) })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = moneyLabel })

	-- quick buttons (left edge)
	local buttons = UIKit.new("Frame", {
		Position = UDim2.new(0, 12, 0.5, -btnSize * 1.5), Size = UDim2.fromOffset(btnSize, btnSize * 3 + 12), BackgroundTransparency = 1, Parent = gui,
	})
	UIKit.list(buttons, 6)
	local function quick(text, order, cb)
		return UIKit.button({ Size = UDim2.fromOffset(btnSize, btnSize), Text = text, TextSize = touch and 14 or 13, LayoutOrder = order, TextWrapped = true, Parent = buttons }, cb)
	end
	quick(touch and "BAG" or "BAG\n[I]", 1, function() Hud.callbacks.inventory() end)
	quick(touch and "MAP" or "MAP\n[M]", 2, function() Hud.callbacks.map() end)
	flipBtn = quick(touch and "FLIP" or "FLIP\n[R]", 3, function() Hud.callbacks.flip() end)
	towBtn = UIKit.button({
		Size = UDim2.fromOffset(btnSize, btnSize), Position = UDim2.new(0, 12, 0.5, btnSize * 1.5 + 14), Text = "TOW", TextSize = 13,
		BackgroundColor3 = T.bad, TextColor3 = Color3.new(1, 1, 1), Parent = gui,
	}, function() Hud.callbacks.tow() end)
	flipBtn.Visible, towBtn.Visible = false, false

	-- toasts (top right) and loot cards (bottom centre-right)
	toastFrame = UIKit.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(330, 400), BackgroundTransparency = 1, Parent = gui })
	UIKit.list(toastFrame, 6)
	lootFrame = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -120), Size = UDim2.fromOffset(360, 260), BackgroundTransparency = 1, Parent = gui })
	UIKit.new("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 6), Parent = lootFrame })

	banner = UIKit.label({
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(600, 50),
		Text = "", TextSize = 34, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeColor3 = Color3.new(0, 0, 0), TextTransparency = 1, Parent = gui,
	})

	-- waypoint compass (top centre)
	compass = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(300, 44),
		BackgroundColor3 = T.bg, BackgroundTransparency = 0.25, Visible = false, Parent = gui,
	}, { UIKit.corner(10) })
	compassArrow = UIKit.label({ Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(4, 2), Text = "▲", TextSize = 30, TextColor3 = T.accent, TextXAlignment = Enum.TextXAlignment.Center, Parent = compass })
	compassText = UIKit.label({ Size = UDim2.new(1, -52, 1, 0), Position = UDim2.fromOffset(48, 0), Text = "", TextSize = 16, Parent = compass })

	-- vehicle gauges (bottom centre)
	local g = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, touch and -150 or -16), Size = UDim2.fromOffset(280, 112),
		BackgroundColor3 = T.bg, BackgroundTransparency = 0.2, Visible = false, Parent = gui,
	}, { UIKit.corner(12), UIKit.padding(10) })
	local speed = UIKit.label({ Size = UDim2.new(1, 0, 0, 40), Text = "0 km/h", TextSize = 32, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center, Parent = g })
	local fuelFill = gauge(g, 48, "FUEL", T.accent)
	local hpFill = gauge(g, 68, "HEALTH", T.good)
	local warn = UIKit.label({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 86), Text = "", TextSize = 13, TextColor3 = T.bad, TextXAlignment = Enum.TextXAlignment.Center, Parent = g })
	gauges = { frame = g, speed = speed, fuel = fuelFill, hp = hpFill, warn = warn }

	-- state-driven
	local function refreshState()
		moneyLabel.Text = "$" .. tostring(State.data.money)
		local has = State.data.active ~= nil
		flipBtn.Visible, towBtn.Visible = has, has
	end
	State.changed.Event:Connect(refreshState)
	refreshState()

	RunService.RenderStepped:Connect(function()
		-- compass
		local wp = State.waypoint
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if wp and root then
			compass.Visible = true
			local dir = Vector3.new(wp.x - root.Position.X, 0, wp.z - root.Position.Z)
			local cam = Workspace.CurrentCamera.CFrame.LookVector
			cam = Vector3.new(cam.X, 0, cam.Z)
			if dir.Magnitude > 1 and cam.Magnitude > 0.01 then
				cam = cam.Unit
				local a = math.atan2(cam:Cross(dir.Unit).Y, cam:Dot(dir.Unit))
				compassArrow.Rotation = -math.deg(a)
			end
			compassText.Text = ("%s\n%d studs"):format(wp.name, dir.Magnitude)
			if dir.Magnitude < 25 then
				State.setWaypoint(nil)
			end
		else
			compass.Visible = false
		end
		-- vehicle gauges
		local model = Hud.currentVehicle
		if model and model.Parent and model.PrimaryPart then
			gauges.frame.Visible = true
			local v = model.PrimaryPart.AssemblyLinearVelocity
			gauges.speed.Text = ("%d km/h"):format(math.floor(Vector3.new(v.X, 0, v.Z).Magnitude + 0.5))
			local maxFuel, maxHp = model:GetAttribute("MaxFuel") or 1, model:GetAttribute("MaxHealth") or 1
			local f = math.clamp((model:GetAttribute("Fuel") or 0) / maxFuel, 0, 1)
			local h = math.clamp((model:GetAttribute("Health") or 0) / maxHp, 0, 1)
			gauges.fuel.Size = UDim2.fromScale(f, 1)
			gauges.hp.Size = UDim2.fromScale(h, 1)
			gauges.hp.BackgroundColor3 = h > 0.5 and T.good or (h > 0.25 and T.accent or T.bad)
			if (model:GetAttribute("Health") or 0) <= 0 then
				gauges.warn.Text = "WRECKED - repair at a garage or TOW"
			elseif (model:GetAttribute("Fuel") or 0) <= 0.01 then
				gauges.warn.Text = "OUT OF FUEL - refuel at a garage or TOW"
			elseif f < 0.15 then
				gauges.warn.Text = "Low fuel"
			else
				gauges.warn.Text = ""
			end
		else
			gauges.frame.Visible = false
		end
	end)
	return gui
end

return Hud
