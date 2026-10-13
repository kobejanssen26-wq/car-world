-- Catalogue of every car part in the game. Pure data; used by server (validation, loot)
-- and client (UI). Item ids are the only thing ever stored in player data.
local Parts = {}

Parts.Slots = { "Chassis", "Engine", "Transmission", "Wheels", "Suspension", "Battery", "FuelTank", "Armor" }

Parts.Required = {
	Chassis = true,
	Engine = true,
	Transmission = true,
	Wheels = true,
	Suspension = true,
	Battery = true,
	FuelTank = true,
}

Parts.SlotLabels = {
	Chassis = "Chassis",
	Engine = "Engine",
	Transmission = "Transmission",
	Wheels = "Wheels & Tires",
	Suspension = "Suspension",
	Battery = "Battery",
	FuelTank = "Fuel Tank",
	Armor = "Armor (optional)",
}

Parts.List = {}
Parts.ById = {}
Parts.BySlot = {}
for _, slot in Parts.Slots do
	Parts.BySlot[slot] = {}
end

local function add(slot: string, id: string, name: string, rarity: string, value: number, desc: string, stats)
	local part = {
		id = id,
		slot = slot,
		name = name,
		rarity = rarity,
		value = value,
		desc = desc,
		stats = stats,
	}
	table.insert(Parts.List, part)
	table.insert(Parts.BySlot[slot], part)
	Parts.ById[id] = part
end

-- mass is in "kg-ish" units, power in kW-ish units (see VehicleStats for the formulas).
-- CHASSIS: mass, hp
add("Chassis", "chassis_rust", "Rusty Ladder Frame", "Common", 45, "Heavy and tired, but it holds together. Mostly.", { mass = 500, hp = 120 })
add("Chassis", "chassis_steel", "Steel Box Frame", "Uncommon", 190, "Solid welded steel. Tough, if not light.", { mass = 560, hp = 230 })
add("Chassis", "chassis_alloy", "Alloy Space Frame", "Rare", 640, "Aluminium lattice. Strong and much lighter.", { mass = 430, hp = 310 })
add("Chassis", "chassis_carbon", "Carbon Monocoque", "Legendary", 2600, "Race-grade tub. Feather light, brutally strong.", { mass = 320, hp = 390 })

-- ENGINES: power, fuelUse (relative), mass
add("Engine", "eng_i4_junk", "Salvaged Inline-4", "Common", 55, "Coughs, smokes, runs. Frugal.", { power = 90, fuelUse = 1.0, mass = 180 })
add("Engine", "eng_v6", "Sport V6", "Uncommon", 230, "Smooth 3.0L V6 with real pull.", { power = 160, fuelUse = 1.4, mass = 230 })
add("Engine", "eng_v8", "Muscle V8", "Rare", 720, "Thunderous. Thirsty. Needs a strong battery.", { power = 280, fuelUse = 2.0, mass = 330 })
add("Engine", "eng_v8_tt", "Twin-Turbo V8", "Legendary", 2900, "Hand-built monster. Needs a lithium pack to wake up.", { power = 450, fuelUse = 2.4, mass = 300 })

-- TRANSMISSIONS: torque (hill pull), top (top speed multiplier), eff (drivetrain efficiency), mass
add("Transmission", "trans_3sp", "Worn 3-Speed", "Common", 40, "Slips a little. Gets the job done.", { torque = 1.0, top = 1.0, eff = 0.80, mass = 80 })
add("Transmission", "trans_crawler", "Crawler Gearbox", "Uncommon", 210, "Very low gearing: great on hills, slow on flats.", { torque = 1.35, top = 0.85, eff = 0.85, mass = 110 })
add("Transmission", "trans_sport6", "Sport 6-Speed", "Rare", 680, "Close-ratio box with a tall top gear.", { torque = 1.05, top = 1.15, eff = 0.92, mass = 100 })
add("Transmission", "trans_dct", "Dual-Clutch Gearbox", "Legendary", 2500, "Instant shifts, nearly lossless.", { torque = 1.2, top = 1.25, eff = 0.97, mass = 90 })

-- WHEELS (set of 4): grip, offroad (0 = slicks, 1 = mud terrain), mass (all four), radius
add("Wheels", "wheels_bald", "Bald Tires", "Common", 45, "Slippery on everything, awful off-road.", { grip = 0.75, offroad = 0.15, mass = 90, radius = 1.5 })
add("Wheels", "wheels_street", "Street Tires", "Uncommon", 180, "Good tarmac grip, mediocre in dirt.", { grip = 0.95, offroad = 0.30, mass = 100, radius = 1.55 })
add("Wheels", "wheels_at", "All-Terrain Tires", "Rare", 600, "Chunky tread that bites on dirt, mud and snow.", { grip = 1.0, offroad = 0.95, mass = 120, radius = 1.8 })
add("Wheels", "wheels_slick", "Racing Slicks", "Legendary", 2400, "Unbelievable tarmac grip. Hopeless off the road.", { grip = 1.3, offroad = 0.0, mass = 95, radius = 1.6 })

-- SUSPENSION: travel (ride height / bump absorption), damp (damping ratio), quality (rough terrain handling), mass
add("Suspension", "susp_worn", "Worn Springs", "Common", 40, "Bouncy and low. Bottoms out on bumps.", { travel = 0.9, damp = 0.25, quality = 0.10, mass = 60 })
add("Suspension", "susp_leaf", "Heavy Leaf Springs", "Uncommon", 170, "Stiff truck suspension with a bit more clearance.", { travel = 1.1, damp = 0.40, quality = 0.40, mass = 90 })
add("Suspension", "susp_rally", "Rally Coilovers", "Rare", 620, "Long-travel dampers. Smooths rough tracks.", { travel = 1.5, damp = 0.50, quality = 0.75, mass = 80 })
add("Suspension", "susp_air", "Adaptive Air Suspension", "Legendary", 2300, "Self-levelling long-travel air struts.", { travel = 1.8, damp = 0.60, quality = 1.0, mass = 85 })

-- BATTERY: supports (max engine power it can feed), mass
add("Battery", "batt_lead", "Tired Lead Battery", "Common", 35, "Barely turns over a small engine.", { supports = 110, mass = 25 })
add("Battery", "batt_agm", "AGM Battery", "Uncommon", 160, "Reliable power for mid-size engines.", { supports = 190, mass = 30 })
add("Battery", "batt_hd", "Heavy-Duty Cell", "Rare", 540, "Feeds a V8 without complaint.", { supports = 320, mass = 35 })
add("Battery", "batt_li", "Lithium Pack", "Legendary", 2200, "Enough punch for anything with an engine.", { supports = 520, mass = 40 })

-- FUEL TANKS: capacity (litres), mass
add("FuelTank", "tank_rust", "Rusty Jerry Tank", "Common", 35, "Small and a little leaky-looking.", { capacity = 30, mass = 30 })
add("FuelTank", "tank_steel", "Steel Tank", "Uncommon", 150, "A proper tank. 50 litres.", { capacity = 50, mass = 40 })
add("FuelTank", "tank_lr", "Long-Range Tank", "Rare", 500, "80 litres for expeditions.", { capacity = 80, mass = 55 })
add("FuelTank", "tank_avia", "Aviation Fuel Cell", "Legendary", 2000, "140 litres in a bladder cell.", { capacity = 140, mass = 70 })

-- ARMOR (optional): hp, mass
add("Armor", "armor_bumper", "Bent Bumper", "Common", 40, "Better than nothing.", { hp = 40, mass = 40 })
add("Armor", "armor_skid", "Skid Plate", "Uncommon", 175, "Protects the underside from rocks.", { hp = 90, mass = 70 })
add("Armor", "armor_cage", "Roll Cage", "Rare", 580, "Serious protection, serious weight.", { hp = 160, mass = 120 })
add("Armor", "armor_ceramic", "Ceramic Plating", "Legendary", 2500, "Military-grade, surprisingly light.", { hp = 260, mass = 110 })

return Parts
