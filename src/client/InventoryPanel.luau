-- Inventory: browse parts by rarity, inspect details. (Selling/installing happens at a garage.)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Parts = require(Shared.Parts)
local Rarity = require(Shared.Rarity)
local Profile = require(Shared.Profile)
local UIKit = require(script.Parent.UIKit)
local State = require(script.Parent.State)

local T = UIKit.theme
local InventoryPanel = {}

local frame, listFrame, detail, countLabel
local selected: string? = nil

local function renderDetail()
	UIKit.clear(detail)
	local item = nil
	for _, it in State.data.items do
		if it.uid == selected then
			item = it
		end
	end
	if not item then
		UIKit.label({ Size = UDim2.new(1, 0, 0, 40), Text = "Select a part to see its details.", TextColor3 = T.dim, Parent = detail })
		return
	end
	local p = Parts.ById[item.id]
	UIKit.label({ Size = UDim2.new(1, 0, 0, 28), Text = p.name, TextSize = 22, Font = Enum.Font.GothamBlack, TextColor3 = Rarity.color3(p.rarity), LayoutOrder = 1, Parent = detail })
	UIKit.label({ Size = UDim2.new(1, 0, 0, 20), Text = ("%s  ·  %s"):format(p.rarity, Parts.SlotLabels[p.slot]), TextColor3 = T.dim, LayoutOrder = 2, Parent = detail })
	UIKit.label({ Size = UDim2.new(1, 0, 0, 44), Text = p.desc, LayoutOrder = 3, Parent = detail })
	UIKit.label({ Size = UDim2.new(1, 0, 0, 44), Text = UIKit.partStatsText(p), TextColor3 = T.accent, LayoutOrder = 4, Parent = detail })
	UIKit.label({ Size = UDim2.new(1, 0, 0, 20), Text = ("Sells for $%d at a garage"):format(Profile.sellPrice(p.id)), TextColor3 = T.good, LayoutOrder = 5, Parent = detail })
end

local function render()
	UIKit.clear(listFrame)
	countLabel.Text = ("%d / %d parts"):format(#State.data.items, State.data.maxItems)
	local sorted = table.clone(State.data.items)
	table.sort(sorted, function(a, b)
		local pa, pb = Parts.ById[a.id], Parts.ById[b.id]
		local ra, rb = Rarity.rank(pa.rarity), Rarity.rank(pb.rarity)
		if ra ~= rb then
			return ra > rb
		end
		return pa.name < pb.name
	end)
	for i, it in sorted do
		local p = Parts.ById[it.id]
		local row = UIKit.button({
			Size = UDim2.new(1, -8, 0, 34), LayoutOrder = i, Text = "", BackgroundColor3 = it.uid == selected and T.panel2 or T.panel, Parent = listFrame,
		}, function()
			selected = it.uid
			render()
		end)
		UIKit.new("Frame", { Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = Rarity.color3(p.rarity), BorderSizePixel = 0, Parent = row })
		UIKit.label({ Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(14, 0), Text = ("%s  ·  %s"):format(p.name, Parts.SlotLabels[p.slot]), TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = Rarity.color3(p.rarity), Parent = row })
	end
	if #sorted == 0 then
		UIKit.label({ Size = UDim2.new(1, 0, 0, 60), Text = "Your bag is empty.\nSearch crates, barns and wrecks to find parts!", TextColor3 = T.dim, Parent = listFrame })
	end
	renderDetail()
end

function InventoryPanel.create(gui: ScreenGui)
	frame = UIKit.panel(gui, "Inventory", UDim2.new(0, 640, 0, 420), function()
		frame.Visible = false
	end)
	local content = frame:FindFirstChildWhichIsA("Frame")
	listFrame = UIKit.scroll({ Size = UDim2.new(0.5, -20, 1, -44), Position = UDim2.fromOffset(12, 6), Parent = content })
	UIKit.list(listFrame, 4)
	detail = UIKit.new("Frame", { Size = UDim2.new(0.5, -20, 1, -44), Position = UDim2.new(0.5, 8, 0, 6), BackgroundColor3 = T.panel, Parent = content }, { UIKit.corner(8), UIKit.padding(12) })
	UIKit.list(detail, 4)
	countLabel = UIKit.label({ Size = UDim2.new(1, -24, 0, 24), Position = UDim2.new(0, 12, 1, -30), Text = "", TextColor3 = T.dim, Parent = content })
	State.changed.Event:Connect(function()
		if frame.Visible then
			render()
		end
	end)
	return frame
end

function InventoryPanel.toggle()
	frame.Visible = not frame.Visible
	if frame.Visible then
		render()
	end
end

function InventoryPanel.hide()
	frame.Visible = false
end

return InventoryPanel
