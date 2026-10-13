-- Every explorable location. kind selects the building generator in WorldBuilder.
--   service = true  -> has a garage terminal / fuel / repair (a "service point")
--   hidden  = true  -> not shown anywhere until a player gets close (reward: better loot)
--   story   = notes the player can read at the site (environmental storytelling + hints)
--   fixed   = guaranteed loot per container index (used by the tutorial scrapyard only)
-- tier 1..4 drives loot rarity (see Rarity.WeightsByTier) and roughly matches terrain difficulty.
local Sites = {}

Sites.List = {
	-- ===== Rustwood Valley (tier 1) =====
	{ id = "hub", name = "Dusty Junction", kind = "Hub", x = 0, z = 0, yaw = 0, tier = 1, service = true,
		story = { "WELCOME TO DUSTY JUNCTION. Pop. 12. Garage open to all. Old Joe's yard is just west - he leaves the gate unlocked." } },
	{ id = "joes_yard", name = "Old Joe's Yard", kind = "Scrapyard", x = -75, z = -50, yaw = 20, tier = 1, containers = 4,
		fixed = {
			{ "chassis_rust", "wheels_bald" },
			{ "eng_i4_junk", "trans_3sp" },
			{ "batt_lead", "tank_rust" },
			{ "susp_worn", cash = 60 },
		},
		story = { "Joe's note: 'Take what you need, kid. Frame, engine, wheels - the lot. Build yourself something that runs, then go see the world.'" } },
	{ id = "roadside_wreck", name = "Roadside Wreck", kind = "Wreck", x = 135, z = 45, yaw = 70, tier = 1 },
	{ id = "hay_barn", name = "Hay Barn", kind = "Barn", x = -60, z = 165, yaw = 200, tier = 1, containers = 3,
		story = { "Faded sign: 'Fuel in the tank? Check the barn before the diner closes.'" } },
	{ id = "farm_workshop", name = "Farm Workshop", kind = "Garage", x = 95, z = -135, yaw = 150, tier = 1, containers = 3 },
	{ id = "fishermans_shed", name = "Fisherman's Shed", kind = "Cache", x = -210, z = -125, yaw = 10, tier = 1, hidden = true,
		story = { "Scratched on the door: 'Best catch of my life was under the floorboards.'" } },

	-- ===== Pinewood Forest (tier 2) =====
	{ id = "logging_camp", name = "Logging Camp", kind = "Outpost", x = -48, z = -452, yaw = 0, tier = 2, service = true, containers = 2,
		story = { "Foreman's board: 'Cabin Trail is closed. Ranger left something there... don't ask.'" } },
	{ id = "hollow_barn", name = "Hollow Barn", kind = "Barn", x = -175, z = -425, yaw = 80, tier = 2, containers = 3 },
	{ id = "pine_wreck", name = "Pine Wreck", kind = "Wreck", x = 115, z = -385, yaw = 300, tier = 2 },
	{ id = "mill_warehouse", name = "Sawmill Warehouse", kind = "Warehouse", x = 150, z = -525, yaw = 90, tier = 2, containers = 4 },
	{ id = "ranger_cabin", name = "Ranger's Cabin", kind = "Cache", x = -150, z = -585, yaw = 45, tier = 2, hidden = true,
		story = { "Ranger's log: 'Bridge on Summit Pass is out of the way, but the crates in the tunnel mound are worth the drive.'" } },

	-- ===== Iron Flats (tier 2) =====
	{ id = "iron_depot", name = "Iron Flats Depot", kind = "Outpost", x = -505, z = 175, yaw = 270, tier = 2, service = true, containers = 2,
		story = { "Dispatch: 'All trucks running dry. Only fuel for 300 miles is at the Dune Outpost to the south.'" } },
	{ id = "smelter", name = "Smelter Warehouse", kind = "Warehouse", x = -565, z = 35, yaw = 0, tier = 2, containers = 4 },
	{ id = "central_scrap", name = "Central Scrapyard", kind = "Scrapyard", x = -425, z = 225, yaw = 330, tier = 2, containers = 4 },
	{ id = "pump_house", name = "Pump House", kind = "Garage", x = -385, z = -30, yaw = 180, tier = 2, containers = 3 },
	{ id = "rail_wreck", name = "Rail Wreck", kind = "Wreck", x = -600, z = 235, yaw = 110, tier = 2 },
	{ id = "collapsed_bunker", name = "Collapsed Bunker", kind = "Cache", x = -645, z = -60, yaw = 90, tier = 3, hidden = true,
		story = { "Stencilled: 'CIVIL DEFENCE. Stock rotated 1989.' Somebody kept the good stuff." } },

	-- ===== Redrock Mesa (tier 3) =====
	{ id = "dune_outpost", name = "Dune Outpost", kind = "Outpost", x = 200, z = 505, yaw = 180, tier = 3, service = true, containers = 2,
		story = { "Painted on tin: 'LAST FUEL BEFORE THE MESA. Big tyres or big regrets.'" } },
	{ id = "oil_warehouse", name = "Oilfield Warehouse", kind = "Warehouse", x = 265, z = 565, yaw = 30, tier = 3, containers = 4 },
	{ id = "canyon_wreck", name = "Canyon Wreck", kind = "Wreck", x = 60, z = 620, yaw = 250, tier = 3 },
	{ id = "prospector_barn", name = "Prospector's Barn", kind = "Barn", x = -60, z = 545, yaw = 60, tier = 3, containers = 3 },
	{ id = "cave_stash", name = "Sunken Cave Stash", kind = "Cache", x = 235, z = 615, yaw = 0, tier = 3, hidden = true,
		story = { "Map scrap: 'X marks the cave. South-east of the derricks.'" } },

	-- ===== Highcrest Mountains (tier 3-4) =====
	{ id = "switchback_garage", name = "Switchback Garage", kind = "Outpost", x = 420, z = -170, yaw = 20, tier = 3, service = true, containers = 3,
		story = { "Mechanic's whiteboard: 'Summit Pass = 17 degrees. Weak engines stall. Don't say we didn't warn you.'" } },
	{ id = "quarry_yard", name = "Quarry Scrapyard", kind = "Scrapyard", x = 600, z = 85, yaw = 200, tier = 3, containers = 4 },
	{ id = "radio_station", name = "Summit Radio Station", kind = "Warehouse", x = 640, z = -245, yaw = 270, tier = 4, containers = 4,
		story = { "Radio log: 'Frostpeak road splits off at the Switchback. Snow tyres? What snow tyres.'" } },
	{ id = "ravine_wreck", name = "Ravine Wreck", kind = "Wreck", x = 520, z = -230, yaw = 15, tier = 3 },
	{ id = "tunnel_stash", name = "Tunnel Stash", kind = "Cache", x = 640, z = -180, yaw = 300, tier = 4, hidden = true,
		story = { "Smuggler's tag: 'Beside the tunnel mouth. Never found.'" } },

	-- ===== Frostpeak (tier 4) =====
	{ id = "frost_lodge", name = "Frostpeak Lodge", kind = "Outpost", x = 505, z = -480, yaw = 90, tier = 4, service = true, containers = 3,
		story = { "Guest book: 'Reached the lodge in an all-terrain rig. Worth every part.'" } },
	{ id = "glacier_hangar", name = "Glacier Hangar", kind = "Warehouse", x = 515, z = -420, yaw = 200, tier = 4, containers = 4 },
	{ id = "rally_crash", name = "Crashed Rally Car", kind = "Wreck", x = 385, z = -385, yaw = 330, tier = 4 },
	{ id = "peak_vault", name = "Peak Vault", kind = "Cache", x = 400, z = -560, yaw = 0, tier = 4, hidden = true,
		story = { "Engraved: 'Whoever builds the best car keeps what is inside.'" } },
}

Sites.ById = {}
for _, s in Sites.List do
	Sites.ById[s.id] = s
end

return Sites
