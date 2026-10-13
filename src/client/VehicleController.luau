-- Client-side vehicle physics for the car the local player drives (the client owns the vehicle's physics
-- while seated, which is standard Roblox network ownership). Four ray-cast suspension "wheels" apply:
--   * spring + damper forces (ride height, bump absorption - from the Suspension part)
--   * lateral tyre grip limited by a friction budget (grip x surface x suspension quality)
--   * drive force from the Engine/Transmission stats with a top-speed falloff curve
--   * braking, rolling resistance, hill-holding and roll/pitch damping
-- All tuning numbers come from model attributes written by the server from the installed parts.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local VehicleStats = require(Shared.VehicleStats)
local Tire = require(Shared.Tire)

local VehicleController = {}
local player = Players.LocalPlayer

local GRAVITY = 196.2

local conn: RBXScriptConnection? = nil
local current = nil
VehicleController.onChanged = Instance.new("BindableEvent") -- fires (model | nil)

local function wheelLayout(model)
	local mx, mz, my = model:GetAttribute("MountX"), model:GetAttribute("MountZ"), model:GetAttribute("MountY")
	return {
		{ pos = Vector3.new(-mx, my, -mz), front = true },
		{ pos = Vector3.new(mx, my, -mz), front = true },
		{ pos = Vector3.new(-mx, my, mz), front = false },
		{ pos = Vector3.new(mx, my, mz), front = false },
	}
end

local function rotate(v: Vector3, axis: Vector3, angle: number): Vector3
	return CFrame.fromAxisAngle(axis, angle):VectorToWorldSpace(v)
end

local function detach()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	current = nil
	VehicleController.onChanged:Fire(nil)
end

local function attach(seat: VehicleSeat)
	local model = seat.Parent :: Model
	local body = model.PrimaryPart
	if not body then
		return
	end
	detach()

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local function refreshFilter()
		local list = { model }
		if player.Character then
			table.insert(list, player.Character)
		end
		params.FilterDescendantsInstances = list
	end
	refreshFilter()

	local wheels = wheelLayout(model)
	local steerAngle = 0
	current = { model = model, body = body }
	VehicleController.onChanged:Fire(model)

	conn = RunService.PreSimulation:Connect(function(dt)
		if not body.Parent or body.Anchored then
			return
		end
		dt = math.min(dt, 1 / 30)

		-- stats (static attributes; cheap lookups)
		local accel = model:GetAttribute("Accel")
		local topSpeed = model:GetAttribute("TopSpeed")
		local grip = model:GetAttribute("Grip")
		local brake = model:GetAttribute("Brake")
		local offroad = model:GetAttribute("Offroad")
		local quality = model:GetAttribute("Quality")
		local damp = model:GetAttribute("Damp")
		local radius = model:GetAttribute("WheelRadius")
		local free = model:GetAttribute("SuspFree")
		local rest = model:GetAttribute("SuspRest")
		if not (accel and topSpeed and grip and free and rest) then
			return
		end

		-- live state
		local health, maxHealth = model:GetAttribute("Health") or 0, model:GetAttribute("MaxHealth") or 1
		local disabled = model:GetAttribute("Disabled") == true
		local health01 = math.clamp(health / maxHealth, 0, 1)
		local damage = health01 >= 0.3 and 1 or (0.5 + health01 / 0.6) -- badly damaged engines lose up to half their power

		local throttle = disabled and 0 or seat.ThrottleFloat
		local steerInput = seat.SteerFloat

		local mass = body.AssemblyMass
		local cf = body.CFrame
		local up, look, right = cf.UpVector, cf.LookVector, cf.RightVector
		local vel = body.AssemblyLinearVelocity
		local forwardSpeed = vel:Dot(look)

		-- speed-sensitive steering with smoothing
		local steerTarget = Tire.steerTarget(steerInput, forwardSpeed, topSpeed)
		steerAngle += (steerTarget - steerAngle) * math.min(1, dt * 9)

		local k = (mass * GRAVITY / 4) / (free - rest)
		local c = 2 * damp * math.sqrt(k * mass / 4)
		local grounded = 0

		for _, w in wheels do
			local origin = cf:PointToWorldSpace(w.pos)
			local hit = Workspace:Raycast(origin, -up * (free + radius), params)
			if hit then
				grounded += 1
				local extension = math.clamp(hit.Distance - radius, 0, free)
				local compression = free - extension
				local pointVel = body:GetVelocityAtPosition(origin)
				local springForce = math.clamp(k * compression - c * pointVel:Dot(up), 0, mass * GRAVITY * 2.5)

				-- tyre basis on the ground plane (front wheels steer; +steer = turn right = rotate clockwise)
				local n = hit.Normal
				local fwd = look
				if w.front then
					fwd = rotate(look, up, -steerAngle)
				end
				fwd = (fwd - n * fwd:Dot(n))
				if fwd.Magnitude < 0.01 then
					continue
				end
				fwd = fwd.Unit
				local side = fwd:Cross(n)

				local contactVel = body:GetVelocityAtPosition(hit.Position)
				local vLong, vLat = contactVel:Dot(fwd), contactVel:Dot(side)

				local surface = VehicleStats.roughnessOf(hit.Material.Name)
				local mu = grip * VehicleStats.surfaceGripFactor(offroad, quality, surface)
				local long, lat = Tire.impulses({
					throttle = throttle, vLong = vLong, vLat = vLat, load = springForce, mu = mu, wheelMass = mass / 4,
					accel = accel, topSpeed = topSpeed, brake = brake, damage = damage, dt = dt,
				})

				-- apply: springs at the mount, tyre forces at the wheel's plan position at centre-of-mass height
				body:ApplyImpulseAtPosition(up * springForce * dt, origin)
				local plan = origin - up * (origin - cf.Position):Dot(up)
				body:ApplyImpulseAtPosition(fwd * long + side * lat, plan)
			end
		end

		-- keep roll/pitch calm while on the ground (yaw stays free for steering)
		if grounded > 0 then
			local w = body.AssemblyAngularVelocity
			local damping = (look * w:Dot(look) + right * w:Dot(right)) * mass * 14 * math.min(1, 5 * dt)
			body:ApplyAngularImpulse(-damping)
		end
	end)

	-- stop when the player leaves the seat or the vehicle is removed
	local seatConn
	seatConn = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil then
			seatConn:Disconnect()
			if current and current.model == model then
				detach()
			end
		end
	end)
	model.Destroying:Once(function()
		if current and current.model == model then
			detach()
		end
	end)
end

function VehicleController.start()
	local function onCharacter(char: Model)
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		local function check()
			local seat = hum.SeatPart
			if seat and seat:IsA("VehicleSeat") and seat.Parent and seat.Parent:GetAttribute("OwnerUserId") == player.UserId then
				attach(seat)
			elseif current then
				detach()
			end
		end
		hum:GetPropertyChangedSignal("SeatPart"):Connect(check)
		check()
	end
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

function VehicleController.getModel(): Model?
	return current and current.model
end

return VehicleController
