-- Garage UI: assemble vehicles from found parts, see live stat previews, spawn / refuel / repair, shop and sell.
-- Purely a view: every button just sends a GarageAction request; the server validates and answers with a new State.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Parts = require(Shared.Parts)
local Rarity = require(Shared.Rarity)
local Config = require(Shared.Config)
local Profile = require(Shared.Profile)
local VehicleStats = require(Shared.VehicleStats)
local UIKit = require(script.Parent.UIKit)
local State = require(script.Parent.State)

local T = UIKit.theme
local GaragePanel = {}

local frame, body
local tab = "Build"
local selectedVehicle: string? = nil
local selectedSlot = "Engine"
local previewId: string? = nil -- part id being hovered/selected in the candidate list
local toast: (string, string?) -> () = function() end

local STAT_ROWS = {
	{ key = "accel", label = "Acceleration", max = 160, fmt = "%.0f" },
	{ key = "topSpeed", label = "Top speed", max = 150, fmt = "%.0f" },
	{ key = "grip", label = "Road grip", max = 1.4, fmt = "%.2f" },
	{ key = "roughTerrain", label = "Rough-road grip", max = 1, fmt = "%.2f" },
	{ key = "brake", label = "Braking", max = 190, fmt = "%.0f" },
	{ key = "durability", label = "Durability", max = 700, fmt = "%.0f" },
	{ key = "range", label = "Fuel range", max = 30000, fmt = "%.0f" },
	{ key = "climbDeg", label = "Max climb (deg)", max = 45, fmt = "%.0f" },
	{ key = "mass", label = "Weight", max = 1500, fmt = "%.0f", lowerBetter = true },
}

local function act(action: string, payload: { [string]: any }?)
	local ok, msg = State.action(action, payload)
	if not ok and msg then
		toast(msg, "warn")
	end
	return ok
end

local selectNewest = false

local function currentVehicle()
	if selectNewest and #State.data.vehicles > 0 then
		selectNewest = false
		selectedVehicle = State.data.vehicles[#State.data.vehicles].id
	end
	local v = State.vehicle(selectedVehicle)
	if not v then
		v = State.data.vehicles[1]
		selectedVehicle = v and v.id or nil
	end
	return v
end

local function statsWith(v, slot: string?, partId: string?)
	local slots = table.clone(v.slots)
	if slot and partId then
		slots[slot] = partId
	end
	return VehicleStats.compute(slots)
end

local function row(parent, height)
	return UIKit.new("Frame", { Size = UDim2.new(1, -8, 0, height), BackgroundColor3 = T.panel, Parent = parent }, { UIKit.corner(6) })
end

-- ===== Build tab =====
local function renderStats(parent, v)
	local cur = VehicleStats.compute(v.slots)
	local prev = previewId and statsWith(v, Parts.ById[previewId].slot, previewId) or nil
	for i, r in STAT_ROWS do
		local y = (i - 1) * 34
		UIKit.label({ Size = UDim2.new(0.6, 0, 0, 16), Position = UDim2.fromOffset(0, y), Text = r.label, TextSize = 13, TextColor3 = T.dim, Parent = parent })
		local value = cur[r.key]
		local show = cur.complete or r.key == "mass" or r.key == "grip" or r.key == "durability" or r.key == "roughTerrain"
		local text = show and r.fmt:format(value) or "-"
		local back = UIKit.new("Frame", { Size = UDim2.new(1, 0, 0, 8), Position = UDim2.fromOffset(0, y + 20), BackgroundColor3 = T.panel2, Parent = parent }, { UIKit.corner(4) })
		UIKit.new("Frame", { Size = UDim2.fromScale(math.clamp(value / r.max, 0, 1), 1), BackgroundColor3 = T.text, Parent = back }, { UIKit.corner(4) })
		local valueText = text
		if prev then
			local pv = prev[r.key]
			local better = if r.lowerBetter then pv < value else pv > value
			local same = math.abs(pv - value) < 1e-6
			local col = same and T.dim or (better and T.good or T.bad)
			UIKit.new("Frame", { Size = UDim2.fromScale(math.clamp(pv / r.max, 0, 1), 1), BackgroundColor3 = col, BackgroundTransparency = 0.35, ZIndex = 2, Parent = back }, { UIKit.corner(4) })
			valueText = ("%s → %s"):format(text, prev.complete and r.fmt:format(pv) or "-")
			UIKit.label({ Size = UDim2.new(0.4, 0, 0, 16), Position = UDim2.new(0.6, 0, 0, y), Text = valueText, TextSize = 13, TextColor3 = col, TextXAlignment = Enum.TextXAlignment.Right, Parent = parent })
		else
			UIKit.label({ Size = UDim2.new(0.4, 0, 0, 16), Position = UDim2.new(0.6, 0, 0, y), Text = valueText, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, Parent = parent })
		end
	end
	if cur.batteryLimited then
		UIKit.label({ Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, #STAT_ROWS * 34), Text = "⚠ Battery can't fully power this engine — a bigger battery unlocks its full output.", TextSize = 12, TextColor3 = T.accent, Parent = parent })
	end
end

local function renderBuild()
	local data = State.data
	local v = currentVehicle()

	-- vehicle tabs
	local tabs = UIKit.new("Frame", { Size = UDim2.new(1, -16, 0, 34), Position = UDim2.fromOffset(8, 40), BackgroundTransparency = 1, Parent = body })
	UIKit.list(tabs, 6, true)
	for i, veh in data.vehicles do
		UIKit.button({
			Size = UDim2.fromOffset(150, 32), Text = veh.name .. (veh.id == data.active and " ●" or ""), TextSize = 14, LayoutOrder = i,
			BackgroundColor3 = veh.id == (v and v.id) and T.accent or T.panel2, TextColor3 = veh.id == (v and v.id) and Color3.new(0, 0, 0) or T.text, Parent = tabs,
		}, function()
			selectedVehicle, previewId = veh.id, nil
			GaragePanel.render()
		end)
	end
	if #data.vehicles < data.maxVehicles then
		UIKit.button({ Size = UDim2.fromOffset(150, 32), Text = "+ New vehicle", TextSize = 14, LayoutOrder = 99, BackgroundColor3 = T.good, Parent = tabs }, function()
			selectNewest = true
			if not act("CreateVehicle", { name = "" }) then
				selectNewest = false
			end
		end)
	end
	if not v then
		UIKit.label({ Size = UDim2.new(1, -40, 0, 80), Position = UDim2.fromOffset(20, 100), Text = "Create a vehicle project, then install the parts you find in the world.\nOld Joe's Yard (west of this junction) has everything for a starter car.", TextSize = 18, TextColor3 = T.dim, Parent = body })
		return
	end

	local cur = VehicleStats.compute(v.slots)
	local filled = 0
	local reqCount = 0
	for slot in Parts.Required do
		reqCount += 1
		if v.slots[slot] then
			filled += 1
		end
	end

	-- left: slots
	local left = UIKit.new("Frame", { Size = UDim2.new(0, 290, 1, -90), Position = UDim2.fromOffset(8, 82), BackgroundTransparency = 1, Parent = body })
	UIKit.label({ Size = UDim2.new(1, 0, 0, 20), Text = ("Assembly: %d / %d required parts"):format(filled, reqCount) .. (cur.complete and "  ✔ READY" or ""), TextSize = 15, Font = Enum.Font.GothamBold, TextColor3 = cur.complete and T.good or T.accent, Parent = left })
	local prog = UIKit.new("Frame", { Size = UDim2.new(1, 0, 0, 8), Position = UDim2.fromOffset(0, 24), BackgroundColor3 = T.panel2, Parent = left }, { UIKit.corner(4) })
	UIKit.new("Frame", { Size = UDim2.fromScale(filled / reqCount, 1), BackgroundColor3 = cur.complete and T.good or T.accent, Parent = prog }, { UIKit.corner(4) })
	local slotList = UIKit.scroll({ Size = UDim2.new(1, 0, 1, -40), Position = UDim2.fromOffset(0, 38), Parent = left })
	UIKit.list(slotList, 4)
	for i, slot in Parts.Slots do
		local id = v.slots[slot]
		local part = id and Parts.ById[id]
		local r = UIKit.button({
			Size = UDim2.new(1, -8, 0, 44), LayoutOrder = i, Text = "", AutoButtonColor = true,
			BackgroundColor3 = slot == selectedSlot and T.panel2 or T.panel, Parent = slotList,
		}, function()
			selectedSlot, previewId = slot, nil
			GaragePanel.render()
		end)
		UIKit.new("Frame", { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = part and Rarity.color3(part.rarity) or (Parts.Required[slot] and T.bad or T.dim), BorderSizePixel = 0, Parent = r })
		UIKit.label({ Size = UDim2.new(1, -50, 0, 18), Position = UDim2.fromOffset(12, 4), Text = Parts.SlotLabels[slot], TextSize = 12, TextColor3 = T.dim, Parent = r })
		UIKit.label({
			Size = UDim2.new(1, -50, 0, 20), Position = UDim2.fromOffset(12, 20),
			Text = part and part.name or (Parts.Required[slot] and "MISSING" or "— none —"), TextSize = 15, Font = Enum.Font.GothamBold,
			TextColor3 = part and Rarity.color3(part.rarity) or (Parts.Required[slot] and T.bad or T.dim), TextTruncate = Enum.TextTruncate.AtEnd, Parent = r,
		})
		if part then
			UIKit.button({ Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -36, 0, 7), Text = "✕", BackgroundColor3 = T.panel2, TextColor3 = T.text, TextSize = 14, Parent = r }, function()
				act("Uninstall", { vehicleId = v.id, slot = slot })
			end)
		end
	end

	-- middle: candidate parts from the inventory for the selected slot
	local mid = UIKit.new("Frame", { Size = UDim2.new(0, 300, 1, -90), Position = UDim2.fromOffset(306, 82), BackgroundTransparency = 1, Parent = body })
	UIKit.label({ Size = UDim2.new(1, 0, 0, 22), Text = "Your " .. Parts.SlotLabels[selectedSlot] .. " parts", TextSize = 16, Font = Enum.Font.GothamBold, Parent = mid })
	local cand = UIKit.scroll({ Size = UDim2.new(1, 0, 1, -28), Position = UDim2.fromOffset(0, 28), Parent = mid })
	UIKit.list(cand, 4)
	local count = 0
	for _, it in data.items do
		local p = Parts.ById[it.id]
		if p.slot == selectedSlot then
			count += 1
			local r = row(cand, 66)
			r.LayoutOrder = count
			r.BackgroundColor3 = (previewId == p.id) and T.panel2 or T.panel
			UIKit.new("Frame", { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = Rarity.color3(p.rarity), BorderSizePixel = 0, Parent = r })
			UIKit.label({ Size = UDim2.new(1, -90, 0, 20), Position = UDim2.fromOffset(12, 4), Text = p.name, TextSize = 15, Font = Enum.Font.GothamBold, TextColor3 = Rarity.color3(p.rarity), TextTruncate = Enum.TextTruncate.AtEnd, Parent = r })
			UIKit.label({ Size = UDim2.new(1, -90, 0, 38), Position = UDim2.fromOffset(12, 24), Text = UIKit.partStatsText(p), TextSize = 12, TextColor3 = T.dim, Parent = r })
			UIKit.button({ Size = UDim2.fromOffset(70, 26), Position = UDim2.new(1, -76, 0, 6), Text = "Compare", TextSize = 12, BackgroundColor3 = T.panel2, TextColor3 = T.text, Parent = r }, function()
				previewId = if previewId == p.id then nil else p.id
				GaragePanel.render()
			end)
			UIKit.button({ Size = UDim2.fromOffset(70, 26), Position = UDim2.new(1, -76, 0, 34), Text = "Install", TextSize = 13, BackgroundColor3 = T.good, Parent = r }, function()
				previewId = nil
				act("Install", { vehicleId = v.id, uid = it.uid })
			end)
			r.MouseEnter:Connect(function()
				if previewId ~= p.id and not UIKit.isTouch() then
					previewId = p.id
					GaragePanel.render()
				end
			end)
		end
	end
	if count == 0 then
		UIKit.label({ Size = UDim2.new(1, 0, 0, 60), Text = "No spare " .. Parts.SlotLabels[selectedSlot] .. " in your bag.\nSearch the world or buy a basic one in the Shop tab.", TextSize = 14, TextColor3 = T.dim, Parent = cand })
	end

	-- right: stats + actions
	local right = UIKit.new("Frame", { Size = UDim2.new(0, 250, 1, -90), Position = UDim2.new(1, -258, 0, 82), BackgroundTransparency = 1, Parent = body })
	local statsFrame = UIKit.new("Frame", { Size = UDim2.new(1, 0, 0, #STAT_ROWS * 34 + 36), BackgroundTransparency = 1, Parent = right })
	renderStats(statsFrame, v)
	local buttons = UIKit.new("Frame", { Size = UDim2.new(1, 0, 0, 150), Position = UDim2.new(0, 0, 1, -150), BackgroundTransparency = 1, Parent = right })
	UIKit.new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 32), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = buttons })
	local isActive = data.active == v.id
	local btn = function(text, color, enabled, cb)
		local b = UIKit.button({ Text = text, TextSize = 13, BackgroundColor3 = enabled and color or T.panel2, TextColor3 = enabled and Color3.new(0, 0, 0) or T.dim, Parent = buttons }, function()
			if enabled then
				cb()
			end
		end)
		return b
	end
	local fuelNeed = cur.complete and math.max(0, cur.fuelCapacity - v.fuel) or 0
	local repairNeed = cur.complete and math.max(0, cur.durability - v.health) or 0
	btn(isActive and "Recall here" or "Drive it", T.accent, cur.complete, function()
		act("Spawn", { vehicleId = v.id })
	end)
	btn(("Refuel $%d"):format(math.ceil(fuelNeed * Config.FuelPrice)), T.accent, fuelNeed >= 0.5, function()
		act("Refuel", { vehicleId = v.id })
	end)
	btn(("Repair $%d"):format(math.ceil(repairNeed * Config.RepairPrice)), T.accent, repairNeed >= 1, function()
		act("Repair", { vehicleId = v.id })
	end)
	btn("Park / hide", T.panel2, isActive, function()
		act("Despawn", {})
	end)
	local del = btn("Scrap project", T.bad, true, function()
		act("DeleteVehicle", { vehicleId = v.id })
		selectedVehicle = nil
	end)
	del.TextColor3 = Color3.new(1, 1, 1)
	if cur.complete then
		UIKit.label({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 1, -190), Text = ("Fuel %d / %d L  ·  Health %d / %d"):format(v.fuel, cur.fuelCapacity, v.health, cur.durability), TextSize = 13, TextColor3 = T.dim, Parent = right })
	end
end

-- ===== Shop / Sell tabs =====
local function renderShop()
	local list = UIKit.scroll({ Size = UDim2.new(1, -24, 1, -90), Position = UDim2.fromOffset(12, 84), Parent = body })
	UIKit.list(list, 4)
	UIKit.label({ Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 44), Text = "The garage only stocks basic Common parts at a markup. Better parts must be found out in the world.", TextSize = 14, TextColor3 = T.dim, Parent = body })
	local i = 0
	for _, slot in Parts.Slots do
		for _, p in Parts.BySlot[slot] do
			if p.rarity == "Common" then
				i += 1
				local r = row(list, 48)
				r.LayoutOrder = i
				UIKit.new("Frame", { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = Rarity.color3(p.rarity), BorderSizePixel = 0, Parent = r })
				UIKit.label({ Size = UDim2.new(0.5, 0, 0, 22), Position = UDim2.fromOffset(12, 3), Text = p.name .. "  (" .. Parts.SlotLabels[slot] .. ")", TextSize = 15, Font = Enum.Font.GothamBold, Parent = r })
				UIKit.label({ Size = UDim2.new(0.6, 0, 0, 20), Position = UDim2.fromOffset(12, 25), Text = UIKit.partStatsText(p), TextSize = 12, TextColor3 = T.dim, Parent = r })
				UIKit.button({ Size = UDim2.fromOffset(100, 32), Position = UDim2.new(1, -108, 0, 8), Text = "Buy $" .. Profile.buyPrice(p.id), TextSize = 14, BackgroundColor3 = State.data.money >= Profile.buyPrice(p.id) and T.good or T.panel2, Parent = r }, function()
					act("Buy", { itemId = p.id })
				end)
			end
		end
	end
end

local function renderSell()
	local list = UIKit.scroll({ Size = UDim2.new(1, -24, 1, -90), Position = UDim2.fromOffset(12, 84), Parent = body })
	UIKit.list(list, 4)
	UIKit.label({ Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 44), Text = "Sell spare parts for cash. Installed parts can't be sold — remove them first.", TextSize = 14, TextColor3 = T.dim, Parent = body })
	local items = table.clone(State.data.items)
	table.sort(items, function(a, b)
		local pa, pb = Parts.ById[a.id], Parts.ById[b.id]
		return Rarity.rank(pa.rarity) > Rarity.rank(pb.rarity)
	end)
	for i, it in items do
		local p = Parts.ById[it.id]
		local r = row(list, 40)
		r.LayoutOrder = i
		UIKit.new("Frame", { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = Rarity.color3(p.rarity), BorderSizePixel = 0, Parent = r })
		UIKit.label({ Size = UDim2.new(0.7, 0, 1, 0), Position = UDim2.fromOffset(12, 0), Text = ("%s  ·  %s  ·  %s"):format(p.name, p.rarity, Parts.SlotLabels[p.slot]), TextSize = 15, TextColor3 = Rarity.color3(p.rarity), Parent = r })
		UIKit.button({ Size = UDim2.fromOffset(100, 28), Position = UDim2.new(1, -108, 0, 6), Text = "Sell $" .. Profile.sellPrice(p.id), TextSize = 14, Parent = r }, function()
			act("Sell", { uid = it.uid })
		end)
	end
	if #items == 0 then
		UIKit.label({ Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 90), Text = "Nothing to sell.", TextColor3 = T.dim, Parent = body })
	end
end

function GaragePanel.render()
	if not frame or not frame.Visible then
		return
	end
	UIKit.clear(body)
	-- tabs
	local tabs = UIKit.new("Frame", { Size = UDim2.new(1, -16, 0, 34), Position = UDim2.fromOffset(8, 4), BackgroundTransparency = 1, Parent = body })
	UIKit.list(tabs, 6, true)
	for i, name in { "Build", "Shop", "Sell" } do
		UIKit.button({
			Size = UDim2.fromOffset(110, 32), Text = name, LayoutOrder = i, TextSize = 15,
			BackgroundColor3 = tab == name and T.accent or T.panel2, TextColor3 = tab == name and Color3.new(0, 0, 0) or T.text, Parent = tabs,
		}, function()
			tab, previewId = name, nil
			GaragePanel.render()
		end)
	end
	if tab == "Build" then
		-- vehicle tabs live one row below the main tabs
		renderBuild()
	elseif tab == "Shop" then
		renderShop()
	else
		renderSell()
	end
end

function GaragePanel.create(gui: ScreenGui, toastFn: (string, string?) -> ())
	toast = toastFn
	local content
	frame, content = UIKit.panel(gui, "Garage", UDim2.new(0, 920, 0, 580), function()
		frame.Visible = false
	end)
	body = content
	State.changed.Event:Connect(function()
		GaragePanel.render()
	end)
	return frame
end

function GaragePanel.open()
	frame.Visible = true
	GaragePanel.render()
end

function GaragePanel.hide()
	frame.Visible = false
end

function GaragePanel.isOpen(): boolean
	return frame ~= nil and frame.Visible
end

return GaragePanel
