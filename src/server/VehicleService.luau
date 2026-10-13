-- Builds vehicle models from installed parts, enforces ownership, simulates fuel and damage.
--
-- Ownership / anti-dupe design:
--   * A vehicle in the world is only a *view* of a record in the owner's profile. The record is the truth.
--   * Each player can have exactly one vehicle in the world; spawning another removes the first.
--   * Only the owner can occupy the driver seat (others are ejected); passengers may use the passenger seat.
--   * Vehicles are anchored ("parked") whenever nobody is driving, so they cannot be pushed away or stolen.
--   * Nothing a client sends can create parts or vehicles - the only entry points are GarageService actions.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Parts = require(Shared.Parts)
local Rarity = require(Shared.Rarity)
local VehicleStats = require(Shared.VehicleStats)
local Sessions = require(script.Parent.Sessions)

local VehicleService = {}

local C = Color3.fromRGB
local active: { [Player]: any } = {} -- [player] = { model, body, driverSeat, record, stats, ... }
local flipCooldown: { [Player]: number } = {}

local vehiclesFolder = Instance.new("Folder")
vehiclesFolder.Name = "Vehicles"
vehiclesFolder.Parent = Workspace

local PAINT = {
	Common = C(138, 84, 54),
	Uncommon = C(110, 122, 138),
	Rare = C(45, 100, 190),
	Legendary = C(24, 24, 28),
}

local function part(model, name, size, cf, color, mat, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.Massless = true
	if extra then
		for k, v in extra do
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

-- Geometry constants shared with the client physics (published as model attributes).
local BODY_SIZE = Vector3.new(8, 1.4, 15)
local MOUNT_X, MOUNT_Z = 4.2, 5.2

function VehicleService.suspension(stats)
	local free = 2.0 * stats.travel
	return free, free * 0.6 -- fully extended length, length at rest
end

local function build(player: Player, record, stats, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = player.Name .. "_Car"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local chassisPart = Parts.ById[record.slots.Chassis]
	local paint = PAINT[chassisPart.rarity]
	local free, rest = VehicleService.suspension(stats)
	local r = stats.wheelRadius
	local clearance = rest + r + 0.7 -- body centre above the ground when parked

	local body = part(model, "Body", BODY_SIZE, cf * CFrame.new(0, clearance, 0), paint, Enum.Material.Metal, {
		CanCollide = true,
		Massless = false,
		CustomPhysicalProperties = PhysicalProperties.new(stats.mass / (BODY_SIZE.X * BODY_SIZE.Y * BODY_SIZE.Z), 0.3, 0, 1, 1),
	})
	model.PrimaryPart = body
	local o = body.CFrame
	local function rel(size, offset: CFrame, color, mat, extra)
		local p = part(model, "Detail", size, o * offset, color, mat, extra)
		weld(body, p)
		return p
	end

	-- cabin & hood
	local glass = C(40, 55, 70)
	rel(Vector3.new(7.4, 0.5, 5), CFrame.new(0, 0.95, -5), paint, Enum.Material.Metal) -- hood
	rel(Vector3.new(7, 3.2, 6.2), CFrame.new(0, 2.3, 1.2), glass, Enum.Material.Glass, { Transparency = 0.25 })
	rel(Vector3.new(7.2, 0.5, 6.4), CFrame.new(0, 4, 1.2), paint, Enum.Material.Metal) -- roof
	rel(Vector3.new(7.6, 1.6, 0.6), CFrame.new(0, 0.3, 7.2), C(40, 40, 44), Enum.Material.Metal) -- rear bumper
	rel(Vector3.new(7.6, 1.2, 0.6), CFrame.new(0, 0.1, -7.4), C(40, 40, 44), Enum.Material.Metal) -- front bumper
	for _, s in { -1, 1 } do
		rel(Vector3.new(1.4, 0.8, 0.3), CFrame.new(s * 2.8, 0.7, -7.55), C(255, 245, 200), Enum.Material.Neon)
		rel(Vector3.new(1.2, 0.7, 0.3), CFrame.new(s * 3, 0.7, 7.55), C(255, 40, 40), Enum.Material.Neon)
	end

	-- visible upgrades: exhausts by engine tier, spoiler on legendary chassis / slicks, bull bar with armor
	local engine = Parts.ById[record.slots.Engine]
	for i = 1, Rarity.rank(engine.rarity) do
		rel(Vector3.new(0.7, 0.7, 1.6), CFrame.new(-2.2 + (i - 1) * 1.1, -0.6, 7.8), C(200, 200, 205), Enum.Material.Metal)
	end
	if chassisPart.rarity == "Legendary" or record.slots.Wheels == "wheels_slick" then
		rel(Vector3.new(7.8, 0.4, 1.8), CFrame.new(0, 3, 7), C(255, 140, 20), Enum.Material.Metal)
		for _, s in { -1, 1 } do
			rel(Vector3.new(0.4, 1.6, 0.6), CFrame.new(s * 3.2, 2.2, 7), C(30, 30, 30), Enum.Material.Metal)
		end
	end
	if record.slots.Armor then
		local ar = Parts.ById[record.slots.Armor]
		local ac = ({ Common = C(90, 90, 90), Uncommon = C(70, 120, 70), Rare = C(60, 100, 170), Legendary = C(255, 150, 30) })[ar.rarity]
		rel(Vector3.new(7.8, 1.6, 0.8), CFrame.new(0, 0.2, -8), ac, Enum.Material.DiamondPlate)
		if Rarity.rank(ar.rarity) >= 3 then
			for _, s in { -1, 1 } do
				rel(Vector3.new(0.5, 0.5, 6.4), CFrame.new(s * 3.3, 4.5, 1.2), ac, Enum.Material.DiamondPlate)
			end
		end
	end

	-- wheels (visual only; the client drives the car with ray-cast suspension)
	local wheelPart = Parts.ById[record.slots.Wheels]
	local tyreWidth = ({ wheels_bald = 1.3, wheels_street = 1.5, wheels_at = 1.9, wheels_slick = 2.2 })[wheelPart.id] or 1.5
	local rimColor = Rarity.color3(wheelPart.rarity)
	local wheels = {}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local pos = Vector3.new(sx * (MOUNT_X + 0.2), -0.7 - rest, sz * MOUNT_Z)
			local w = part(model, "Wheel", Vector3.new(tyreWidth, r * 2, r * 2), o * CFrame.new(pos), C(28, 28, 30), Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder })
			weld(body, w)
			local rim = part(model, "Rim", Vector3.new(tyreWidth + 0.05, r * 1.1, r * 1.1), o * CFrame.new(pos), rimColor, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
			weld(body, rim)
			table.insert(wheels, w)
		end
	end

	-- seats
	local driver = Instance.new("VehicleSeat")
	driver.Name = "DriverSeat"
	driver.Size = Vector3.new(2.4, 0.8, 2.4)
	driver.CFrame = o * CFrame.new(-1.8, 1.4, 0.5)
	driver.Color = C(30, 30, 34)
	driver.Massless = true
	driver.MaxSpeed = 0
	driver.Torque = 0
	driver.TurnSpeed = 0
	driver.HeadsUpDisplay = false
	driver.Parent = model
	weld(body, driver)
	local passenger = Instance.new("Seat")
	passenger.Name = "PassengerSeat"
	passenger.Size = Vector3.new(2.4, 0.8, 2.4)
	passenger.CFrame = o * CFrame.new(1.8, 1.4, 0.5)
	passenger.Color = C(30, 30, 34)
	passenger.Massless = true
	passenger.Parent = model
	weld(body, passenger)

	-- nameplate so players can show off their rigs
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Size = UDim2.fromOffset(220, 44)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.MaxDistance = 140
	gui.Adornee = body
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Rarity.color3(chassisPart.rarity)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = ("%s's %s  [%s]"):format(player.DisplayName, record.name, VehicleStats.tierLabel(stats.tierScore))
	label.Parent = gui
	gui.Parent = body

	-- attributes consumed by the client physics + HUD
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("VehicleId", record.id)
	local attr = {
		Accel = stats.accel, TopSpeed = stats.topSpeed, Grip = stats.grip, Brake = stats.brake,
		Offroad = stats.offroad, Quality = stats.quality, Damp = stats.damp, WheelRadius = r,
		SuspFree = free, SuspRest = rest, MountX = MOUNT_X, MountZ = MOUNT_Z, MountY = -0.7,
		MaxFuel = stats.fuelCapacity, MaxHealth = stats.durability,
	}
	for k, v in attr do
		model:SetAttribute(k, v)
	end
	return model, body, driver, passenger, wheels
end

local function writeLiveAttributes(entry)
	local rec = entry.record
	entry.model:SetAttribute("Fuel", math.floor(rec.fuel * 10) / 10)
	entry.model:SetAttribute("Health", math.floor(rec.health))
	entry.model:SetAttribute("Disabled", rec.fuel <= 0.01 or rec.health <= 0)
end

-- Park: snap to the ground level & yaw only, then anchor.
local function park(entry)
	local body: BasePart = entry.body
	if not body.Parent then
		return
	end
	body.AssemblyLinearVelocity = Vector3.zero
	body.AssemblyAngularVelocity = Vector3.zero
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { entry.model }
	local hit = Workspace:Raycast(body.Position, Vector3.new(0, -40, 0), params)
	if hit then
		local _, yaw, _ = body.CFrame:ToOrientation()
		body.CFrame = CFrame.new(hit.Position + Vector3.new(0, entry.clearance, 0)) * CFrame.Angles(0, yaw, 0)
	end
	body.Anchored = true
end

function VehicleService.getActive(player: Player)
	return active[player]
end

function VehicleService.despawn(player: Player)
	local entry = active[player]
	if not entry then
		return
	end
	active[player] = nil
	entry.model:Destroy()
	local profile = Sessions.profile(player)
	if profile and profile.active == entry.record.id then
		profile.active = nil
	end
	Sessions.push(player)
end

function VehicleService.spawn(player: Player, record, cf: CFrame)
	VehicleService.despawn(player)
	local stats = VehicleStats.compute(record.slots)
	if not stats.complete then
		return nil
	end
	local model, body, driver, passenger = build(player, record, stats, cf)
	local _, rest = VehicleService.suspension(stats)
	local entry = {
		model = model, body = body, driver = driver, passenger = passenger,
		record = record, stats = stats, owner = player,
		clearance = rest + stats.wheelRadius + 0.7,
		prevSpeed = 0, fastTicks = 0, lastOutOfFuelNotice = 0,
	}
	active[player] = entry
	writeLiveAttributes(entry)
	body.Anchored = true -- parked until the owner sits in it
	model.Parent = vehiclesFolder
	park(entry) -- snap onto the ground at the spawn pad

	driver:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = driver.Occupant
		if occ then
			local who = Players:GetPlayerFromCharacter(occ.Parent)
			if who ~= player then
				-- not the owner: throw them out
				occ.Sit = false
				occ.Jump = true
				if who then
					Sessions.notify(who, "This is " .. player.DisplayName .. "'s vehicle.", "warn")
				end
				return
			end
			body.Anchored = false
			entry.prevSpeed = 0
			pcall(function()
				body:SetNetworkOwner(player)
			end)
		else
			park(entry)
		end
	end)
	-- Enter prompt (walking onto the seat also works): owner drives, anyone else rides as passenger.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Get in"
	prompt.ObjectText = player.DisplayName .. "'s " .. record.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	prompt.Triggered:Connect(function(who)
		local hum = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or hum.SeatPart then
			return
		end
		if who == player then
			driver:Sit(hum)
		elseif not passenger.Occupant then
			passenger:Sit(hum)
		end
	end)

	Sessions.push(player)
	return model
end

-- Re-sync live attributes after the garage changed fuel / health.
function VehicleService.refresh(player: Player)
	local entry = active[player]
	if entry then
		writeLiveAttributes(entry)
	end
end

function VehicleService.flip(player: Player): (boolean, string?)
	local entry = active[player]
	if not entry then
		return false, "No vehicle in the world"
	end
	if os.clock() - (flipCooldown[player] or 0) < 4 then
		return false, "Wait a moment"
	end
	flipCooldown[player] = os.clock()
	local body: BasePart = entry.body
	local wasAnchored = body.Anchored
	body.Anchored = true
	local _, yaw, _ = body.CFrame:ToOrientation()
	body.CFrame = CFrame.new(body.Position + Vector3.new(0, 6, 0)) * CFrame.Angles(0, yaw, 0)
	body.AssemblyLinearVelocity = Vector3.zero
	body.AssemblyAngularVelocity = Vector3.zero
	task.wait(0.1)
	if body.Parent and not wasAnchored and entry.driver.Occupant then
		body.Anchored = false
		pcall(function()
			body:SetNetworkOwner(player)
		end)
	end
	return true
end

-- Fuel use, collision damage and sanity checks, 4 times per second.
local accum = 0
RunService.Heartbeat:Connect(function(dt)
	accum += dt
	if accum < 0.25 then
		return
	end
	local step = accum
	accum = 0
	for player, entry in active do
		local body: BasePart = entry.body
		if not body.Parent then
			continue
		end
		local driverHumanoid = entry.driver.Occupant
		if driverHumanoid and not body.Anchored then
			local rec, stats = entry.record, entry.stats
			local vel = body.AssemblyLinearVelocity
			local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			local throttle = math.max(math.abs(entry.driver.Throttle), speed > 3 and 0.25 or 0)

			-- fuel
			if rec.fuel > 0 and rec.health > 0 then
				rec.fuel = math.max(0, rec.fuel - VehicleStats.fuelRate(stats, throttle) * step)
				if rec.fuel <= 0 and os.clock() - entry.lastOutOfFuelNotice > 5 then
					entry.lastOutOfFuelNotice = os.clock()
					Sessions.notify(player, "Out of fuel! Refuel at a garage, or use Tow from the garage menu.", "warn")
				end
			end

			-- collision damage: deceleration beyond what the brakes can explain
			local drop = entry.prevSpeed - speed
			local explained = stats.brake * step * 1.25 + 14
			if drop > explained then
				local dmg = (drop - explained) * 1.2
				rec.health = math.max(0, rec.health - dmg)
				if rec.health <= 0 then
					Sessions.notify(player, "Your car is wrecked! Repair it at a garage (or Tow).", "warn")
				end
			end
			entry.prevSpeed = speed

			-- speed sanity (a launched/falling car has low horizontal speed; hacked speed does not)
			if speed > stats.topSpeed * 1.7 + 50 then
				entry.fastTicks += 1
				if entry.fastTicks >= 6 then
					warn(("[CarWorld] %s exceeded plausible speed (%.0f > %.0f); vehicle removed."):format(player.Name, speed, stats.topSpeed))
					VehicleService.despawn(player)
					continue
				end
			else
				entry.fastTicks = 0
			end
			writeLiveAttributes(entry)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	VehicleService.despawn(player)
	flipCooldown[player] = nil
end)

return VehicleService
