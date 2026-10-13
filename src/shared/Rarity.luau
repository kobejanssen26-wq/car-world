-- Rarity tiers: colours, ordering and drop weights per location tier.
local Rarity = {}

Rarity.Order = { "Common", "Uncommon", "Rare", "Legendary" }

Rarity.Info = {
	Common = { rank = 1, rgb = { 190, 190, 190 } },
	Uncommon = { rank = 2, rgb = { 90, 200, 90 } },
	Rare = { rank = 3, rgb = { 70, 140, 255 } },
	Legendary = { rank = 4, rgb = { 255, 150, 30 } },
}

-- Drop weights {Common, Uncommon, Rare, Legendary} by location tier (1 = starter area, 4 = endgame).
Rarity.WeightsByTier = {
	[1] = { 80, 18, 2, 0 },
	[2] = { 50, 37, 12, 1 },
	[3] = { 22, 40, 33, 5 },
	[4] = { 6, 26, 48, 20 },
}

function Rarity.rank(name: string): number
	return Rarity.Info[name].rank
end

function Rarity.color3(name: string): Color3
	local c = Rarity.Info[name].rgb
	return Color3.fromRGB(c[1], c[2], c[3])
end

return Rarity
