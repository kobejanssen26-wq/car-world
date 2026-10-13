-- Pure tyre model used by the client vehicle controller (and by the physics tests).
-- Given the state of one wheel it returns the longitudinal and lateral *impulses* to apply this step.
local Tire = {}

Tire.MAX_STEER = math.rad(34)
Tire.LATERAL_GAIN = 0.85

-- Smoothly steered wheel angle (radians, +ve = right) that shrinks with speed so the car stays stable.
function Tire.steerTarget(steerInput: number, forwardSpeed: number, topSpeed: number): number
	return steerInput * Tire.MAX_STEER * (1 - 0.72 * math.clamp(math.abs(forwardSpeed) / topSpeed, 0, 1))
end

function Tire.dragDecel(vLong: number): number
	return 2 + 0.0008 * vLong * vLong
end

-- p: { throttle, vLong, vLat, load (spring force N), mu, wheelMass, accel, topSpeed, brake, damage, dt }
-- returns longImpulse, latImpulse
function Tire.impulses(p)
	local dt, wheelMass, vLong, throttle = p.dt, p.wheelMass, p.vLong, p.throttle
	local maxImpulse = p.mu * p.load * dt -- friction budget for this step

	local lat = -p.vLat * wheelMass * Tire.LATERAL_GAIN

	local long = 0
	if throttle * vLong < -2 then
		-- pedal opposes motion: brake (never reverse the velocity within one step)
		long = -math.sign(vLong) * math.min(p.brake * wheelMass * math.abs(throttle) * dt, math.abs(vLong) * wheelMass)
	elseif throttle ~= 0 then
		local fraction = math.clamp(vLong * math.sign(throttle) / p.topSpeed, 0, 1.2)
		local curve = math.clamp(1 - fraction ^ 3, 0, 1) -- drive force fades out approaching top speed
		local reverseScale = throttle < 0 and 0.55 or 1
		if throttle < 0 and vLong < -p.topSpeed * 0.35 then
			curve = 0
		end
		long = throttle * p.accel * p.damage * reverseScale * curve * wheelMass * dt
	end

	-- rolling resistance + aero drag; when stopped, hold the car on slopes with static friction
	if math.abs(throttle) < 0.05 then
		local resist = (math.abs(vLong) < 4) and maxImpulse * 0.95 or Tire.dragDecel(vLong) * wheelMass * dt
		long += math.clamp(-vLong * wheelMass, -resist, resist)
	else
		long -= math.sign(vLong) * Tire.dragDecel(vLong) * wheelMass * dt
	end

	-- friction circle: total tyre impulse cannot exceed the grip budget
	local mag = math.sqrt(long * long + lat * lat)
	if mag > maxImpulse and mag > 0 then
		local s = maxImpulse / mag
		long, lat = long * s, lat * s
	end
	return long, lat
end

return Tire
