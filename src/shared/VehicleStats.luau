-- Pure functions turning installed parts into performance numbers.
-- Used by the server (vehicle build, fuel, damage), the client (physics, UI previews) and tests.
local Parts = require(script.Parent.Parts)
local Rarity = require(script.Parent.Rarity)

local VehicleStats = {}

local ACCEL_K = 330 -- studs/s^2 per (power * torque * eff / mass)
local ACCEL_REF = 24 -- starter-car acceleration; anchors the compression curve
local GRAVITY = 196.2

-- Surface roughness 0..1 by Enum.Material name (used for tyre/suspension grip penalties).
VehicleStats.SurfaceRoughness = {
	Asphalt = 0, Concrete = 0, Pavement = 0, Brick = 0.05, Plastic = 0, Metal = 0,
	Grass = 0.35, LeafyGrass = 0.35, Ground = 0.45, Mud = 0.75, Sand = 0.5, Sandstone = 0.5,
	Rock = 0.5, Slate = 0.5, Basalt = 0.55, Snow = 0.6, Ice = 0.7, Glacier = 0.7, Wood = 0.1, WoodPlanks = 0.1,
}

function VehicleStats.roughnessOf(materialName: string): number
	return VehicleStats.SurfaceRoughness[materialName] or 0.4
end

-- Grip multiplier (before tyre grip) for a surface: tyres with high `offroad` and good suspension lose less.
function VehicleStats.surfaceGripFactor(wheelOffroad: number, suspQuality: number, roughness: number): number
	local tyrePenalty = roughness * 0.6 * (1 - wheelOffroad)
	local suspPenalty = roughness * 0.25 * (1 - suspQuality)
	return math.max(0.2, 1 - tyrePenalty - suspPenalty)
end

function VehicleStats.missingSlots(slots): { string }
	local missing = {}
	for _, slot in Parts.Slots do
		if Parts.Required[slot] then
			local id = slots[slot]
			if not id or not Parts.ById[id] then
				table.insert(missing, slot)
			end
		end
	end
	return missing
end

-- slots: { [slotName] = itemId }
function VehicleStats.compute(slots)
	local function get(slot)
		local id = slots[slot]
		local part = id and Parts.ById[id]
		if part and part.slot == slot then
			return part.stats, part
		end
		return nil, nil
	end

	local chassis = get("Chassis")
	local engine = get("Engine")
	local trans = get("Transmission")
	local wheels = get("Wheels")
	local susp = get("Suspension")
	local battery = get("Battery")
	local tank = get("FuelTank")
	local armor = get("Armor")

	local missing = VehicleStats.missingSlots(slots)
	local complete = #missing == 0

	local mass = 0
	local rankSum, rankCount = 0, 0
	for _, slot in Parts.Slots do
		local s, part = get(slot)
		if s then
			mass += s.mass
			rankSum += Rarity.rank(part.rarity)
			rankCount += 1
		end
	end

	local out = {
		complete = complete,
		missing = missing,
		mass = mass,
		power = 0,
		batteryLimited = false,
		accel = 0,
		topSpeed = 0,
		grip = 0,
		brake = 0,
		durability = 0,
		fuelCapacity = 0,
		fuelUse = 0,
		range = 0,
		offroad = 0,
		roughTerrain = 0,
		climbDeg = 0,
		travel = 1,
		damp = 0.3,
		quality = 0,
		wheelRadius = 1.5,
		tierScore = rankCount > 0 and rankSum / rankCount or 0,
		filled = rankCount,
	}
	if armor then
		out.durability += armor.hp
	end
	if chassis then
		out.durability += chassis.hp
	end
	if tank then
		out.fuelCapacity = tank.capacity
	end
	if wheels then
		out.grip = wheels.grip
		out.offroad = wheels.offroad
		out.wheelRadius = wheels.radius
		out.brake = wheels.grip * 100
	end
	if susp then
		out.travel = susp.travel
		out.damp = susp.damp
		out.quality = susp.quality
	end
	if wheels and susp then
		-- how much of its dry-road grip the car keeps on a "typical" rough surface (roughness 0.5)
		out.roughTerrain = VehicleStats.surfaceGripFactor(wheels.offroad, susp.quality, 0.5)
	end

	if not complete then
		return out
	end

	local power = math.min(engine.power, battery.supports)
	out.power = power
	out.batteryLimited = engine.power > battery.supports
	-- raw power-to-weight, compressed above the starter level so late-game cars stay controllable
	local rawAccel = ACCEL_K * power * trans.torque * trans.eff / mass
	out.accel = ACCEL_REF * (rawAccel / ACCEL_REF) ^ 0.8
	out.topSpeed = (25 + 4.2 * math.sqrt(power * trans.eff)) * trans.top
	out.fuelUse = engine.fuelUse * math.sqrt(mass / 1000)
	-- range at ~60% throttle cruising at 70% of top speed
	local lps = out.fuelUse * (0.03 + 0.27 * 0.6)
	out.range = out.fuelCapacity / lps * out.topSpeed * 0.7

	local powerSin = math.clamp(out.accel / GRAVITY, 0, 1)
	local tractionTan = out.grip * out.roughTerrain
	out.climbDeg = math.min(math.deg(math.asin(powerSin)), math.deg(math.atan(tractionTan)))
	return out
end

-- Fuel drain in litres/second at a given throttle magnitude (0..1).
function VehicleStats.fuelRate(stats, throttle: number): number
	return stats.fuelUse * (0.03 + 0.27 * math.clamp(throttle, 0, 1))
end

function VehicleStats.tierLabel(score: number): string
	if score >= 3.5 then
		return "Legend"
	elseif score >= 2.7 then
		return "Pro"
	elseif score >= 1.8 then
		return "Tuned"
	end
	return "Junker"
end

-- Value of a loadout, used for tow fees etc.
function VehicleStats.value(slots): number
	local total = 0
	for _, slot in Parts.Slots do
		local part = slots[slot] and Parts.ById[slots[slot]]
		if part then
			total += part.value
		end
	end
	return total
end

return VehicleStats
