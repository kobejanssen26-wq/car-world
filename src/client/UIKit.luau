-- Tiny UI toolkit: themed instance factory + helpers shared by all panels.
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Parts = require(Shared.Parts)
local Rarity = require(Shared.Rarity)

local UIKit = {}

UIKit.theme = {
	bg = Color3.fromRGB(22, 24, 30),
	panel = Color3.fromRGB(32, 35, 44),
	panel2 = Color3.fromRGB(42, 46, 58),
	accent = Color3.fromRGB(255, 170, 40),
	good = Color3.fromRGB(90, 200, 110),
	bad = Color3.fromRGB(235, 80, 70),
	text = Color3.fromRGB(240, 240, 245),
	dim = Color3.fromRGB(150, 155, 170),
}

function UIKit.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- UIKit.new("Frame", { Size = ..., Parent = ... }, { children })
function UIKit.new(class: string, props: { [string]: any }?, children: { Instance }?)
	local inst = Instance.new(class)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UIKit.corner(r: number?)
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, r or 8) })
end

function UIKit.stroke(color: Color3?, thickness: number?, transparency: number?)
	return UIKit.new("UIStroke", { Color = color or UIKit.theme.panel2, Thickness = thickness or 1.5, Transparency = transparency or 0 })
end

function UIKit.padding(px: number)
	return UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, px), PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px), PaddingRight = UDim.new(0, px),
	})
end

function UIKit.label(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or UIKit.theme.text
	props.Font = props.Font or Enum.Font.GothamMedium
	props.TextSize = props.TextSize or 16
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextWrapped = if props.TextWrapped == nil then true else props.TextWrapped
	return UIKit.new("TextLabel", props)
end

function UIKit.button(props, onClick: (() -> ())?)
	props.BackgroundColor3 = props.BackgroundColor3 or UIKit.theme.accent
	props.TextColor3 = props.TextColor3 or Color3.fromRGB(25, 25, 25)
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextSize = props.TextSize or 16
	props.AutoButtonColor = true
	local b = UIKit.new("TextButton", props, { UIKit.corner(6) })
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

function UIKit.list(parent: Instance, padding: number?, horizontal: boolean?)
	return UIKit.new("UIListLayout", {
		Padding = UDim.new(0, padding or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		Parent = parent,
	})
end

function UIKit.clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") and not c:IsA("UIGridLayout") then
			c:Destroy()
		end
	end
end

function UIKit.scroll(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.BorderSizePixel = 0
	props.ScrollBarThickness = props.ScrollBarThickness or 6
	props.AutomaticCanvasSize = Enum.AutomaticSize.Y
	props.CanvasSize = UDim2.new()
	return UIKit.new("ScrollingFrame", props)
end

-- Panel with title bar and close button. Returns frame, content.
function UIKit.panel(gui: ScreenGui, title: string, size: UDim2, onClose: () -> ())
	local frame = UIKit.new("Frame", {
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = UIKit.theme.bg,
		Visible = false,
		Parent = gui,
	}, { UIKit.corner(12), UIKit.stroke(UIKit.theme.accent, 2, 0.5) })
	UIKit.label({
		Size = UDim2.new(1, -60, 0, 40), Position = UDim2.fromOffset(16, 0),
		Text = title, TextSize = 22, Font = Enum.Font.GothamBlack, Parent = frame,
	})
	UIKit.button({
		Size = UDim2.fromOffset(36, 30), Position = UDim2.new(1, -44, 0, 6),
		Text = "X", BackgroundColor3 = UIKit.theme.bad, TextColor3 = Color3.new(1, 1, 1), Parent = frame,
	}, onClose)
	local content = UIKit.new("Frame", {
		Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44),
		BackgroundTransparency = 1, Parent = frame,
	})
	return frame, content
end

-- ===== part presentation =====
local function f1(n: number): string
	return string.format("%.1f", n)
end

function UIKit.partStatsText(part): string
	local s = part.stats
	local slot = part.slot
	if slot == "Chassis" then
		return ("Weight %d  ·  Durability %d"):format(s.mass, s.hp)
	elseif slot == "Engine" then
		return ("Power %d  ·  Fuel use ×%s  ·  Weight %d"):format(s.power, f1(s.fuelUse), s.mass)
	elseif slot == "Transmission" then
		return ("Hill torque ×%.2f  ·  Top speed ×%.2f  ·  Efficiency %d%%"):format(s.torque, s.top, s.eff * 100)
	elseif slot == "Wheels" then
		return ("Grip %.2f  ·  Off-road %d%%  ·  Tire radius %.1f"):format(s.grip, s.offroad * 100, s.radius)
	elseif slot == "Suspension" then
		return ("Travel ×%.1f  ·  Rough-road handling %d%%"):format(s.travel, s.quality * 100)
	elseif slot == "Battery" then
		return ("Supports engines up to %d power"):format(s.supports)
	elseif slot == "FuelTank" then
		return ("Capacity %d L  ·  Weight %d"):format(s.capacity, s.mass)
	elseif slot == "Armor" then
		return ("Durability +%d  ·  Weight %d"):format(s.hp, s.mass)
	end
	return ""
end

function UIKit.rarityColor(id: string): Color3
	local p = Parts.ById[id]
	return p and Rarity.color3(p.rarity) or UIKit.theme.text
end

return UIKit
