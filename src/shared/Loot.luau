-- Pure loot generation. The server calls roll() with its own Random; tests call it with seeds.
local Parts = require(script.Parent.Parts)
local Rarity = require(script.Parent.Rarity)

local Loot = {}

-- Slot weights by container kind (which part categories turn up where).
Loot.SlotBias = {
	Barn = { Chassis = 3, Wheels = 2, FuelTank = 3, Battery = 2, Suspension = 2, Engine = 1, Transmission = 1, Armor = 1 },
	Garage = { Engine = 3, Transmission = 3, Suspension = 2, Battery = 2, Wheels = 1, Chassis = 1, FuelTank = 1, Armor = 1 },
	Scrapyard = { Chassis = 3, Wheels = 3, Armor = 2, Engine = 1, Transmission = 1, Suspension = 2, Battery = 1, FuelTank = 2 },
	Warehouse = { Engine = 2, Transmission = 2, Wheels = 3, Battery = 2, FuelTank = 2, Suspension = 2, Armor = 2, Chassis = 1 },
	Wreck = { Wheels = 2, Chassis = 3, Armor = 3, Engine = 1, Transmission = 1, Suspension = 1, Battery = 1, FuelTank = 1 },
	Cache = { Engine = 2, Transmission = 2, Wheels = 2, Suspension = 2, Battery = 2, FuelTank = 2, Chassis = 2, Armor = 2 },
}

local function weightedPick(rng, entries: { [string]: number }, order: { string })
	local total = 0
	for _, k in order do
		total += entries[k] or 0
	end
	local r = rng:NextNumber() * total
	for _, k in order do
		r -= entries[k] or 0
		if r <= 0 then
			return k
		end
	end
	return order[#order]
end

local function rollRarity(rng, tier: number)
	local w = Rarity.WeightsByTier[math.clamp(tier, 1, 4)]
	local r = rng:NextNumber() * (w[1] + w[2] + w[3] + w[4])
	for i = 1, 4 do
		r -= w[i]
		if r <= 0 then
			return Rarity.Order[i]
		end
	end
	return "Common"
end

local PartsBySlotRarity = {}
for _, p in Parts.List do
	PartsBySlotRarity[p.slot] = PartsBySlotRarity[p.slot] or {}
	PartsBySlotRarity[p.slot][p.rarity] = PartsBySlotRarity[p.slot][p.rarity] or {}
	table.insert(PartsBySlotRarity[p.slot][p.rarity], p.id)
end

-- container = { kind, tier, rolls, hidden }
-- returns { itemIds }, cash
function Loot.roll(container, rng)
	local bias = Loot.SlotBias[container.kind] or Loot.SlotBias.Cache
	local tier = container.tier + (container.hidden and 1 or 0)
	local items = {}
	local rolls = container.rolls or 2
	for i = 1, rolls do
		if rng:NextNumber() < 0.2 and not (container.hidden and i == 1) then
			continue -- came up empty
		end
		local rarity = rollRarity(rng, tier)
		if container.hidden and i == 1 and Rarity.rank(rarity) < 3 then
			rarity = "Rare" -- hidden stashes always hold something worth the trip
		end
		local slot = weightedPick(rng, bias, Parts.Slots)
		local pool = PartsBySlotRarity[slot][rarity]
		table.insert(items, pool[rng:NextInteger(1, #pool)])
	end
	local cash = rng:NextInteger(3, 12 + math.floor(18 * container.tier ^ 1.5))
	return items, cash
end

return Loot
