-- Planar (top-down) simulation of the car using the *same* tyre model as the in-game controller.
-- It cannot test Roblox's 3D solver, but it proves the force model is stable, reaches the stat top speed,
-- brakes, corners within grip limits, and that part stats change behaviour.
local VS = require("./shared/VehicleStats")
local Tire = require("./shared/Tire")

local fails = 0
local function check(c, m) if not c then fails += 1; print("FAIL: " .. m) end end
local G = 196.2

local function sim(slots, opts)
	local stats = VS.compute(slots)
	local mass = stats.mass + 80 -- + driver
	local Iz = mass * (8 * 8 + 15 * 15) / 12
	local s = { x = 0, y = 0, psi = 0, vx = opts.v0 or 0, vy = 0, w = 0, steer = 0 }
	if opts.v0 then s.vx, s.vy = opts.v0, 0 end
	local dt = 1 / 60
	local wheels = { { a = 5.2, b = -4.2, front = true }, { a = 5.2, b = 4.2, front = true }, { a = -5.2, b = -4.2 }, { a = -5.2, b = 4.2 } }
	local mu0 = stats.grip * (opts.surfaceFactor or 1)
	local log = { maxSlip = 0, maxW = 0, unstable = false }
	local t, dist = 0, 0
	local stopT = nil
	while t < opts.duration do
		local throttle, steerIn = opts.throttle(t), opts.steer(t)
		local f = { math.cos(s.psi), math.sin(s.psi) }
		local r = { math.sin(s.psi), -math.cos(s.psi) } -- right (clockwise from forward)
		local vLongBody = s.vx * f[1] + s.vy * f[2]
		local target = Tire.steerTarget(steerIn, vLongBody, stats.topSpeed)
		s.steer += (target - s.steer) * math.min(1, dt * 9)
		local Jx, Jy, Jt = 0, 0, 0
		for _, w in wheels do
			local ang = w.front and -s.steer or 0 -- right turn = clockwise
			local c, sn = math.cos(ang), math.sin(ang)
			local wf = { f[1] * c - f[2] * sn, f[1] * sn + f[2] * c }
			local ws = { wf[2], -wf[1] } -- right of wheel forward
			local rx, ry = f[1] * w.a + r[1] * w.b, f[2] * w.a + r[2] * w.b
			local px = s.vx + (-s.w * ry)
			local py = s.vy + (s.w * rx)
			local vLong, vLat = px * wf[1] + py * wf[2], px * ws[1] + py * ws[2]
			local long, lat = Tire.impulses({
				throttle = throttle, vLong = vLong, vLat = vLat, load = mass * G / 4, mu = mu0, wheelMass = mass / 4,
				accel = stats.accel, topSpeed = stats.topSpeed, brake = stats.brake, damage = 1, dt = dt,
			})
			local ix, iy = wf[1] * long + ws[1] * lat, wf[2] * long + ws[2] * lat
			Jx += ix; Jy += iy
			Jt += rx * iy - ry * ix
			log.maxSlip = math.max(log.maxSlip, math.abs(vLat))
		end
		s.vx += Jx / mass; s.vy += Jy / mass; s.w += Jt / Iz
		s.x += s.vx * dt; s.y += s.vy * dt; s.psi += s.w * dt
		dist += math.sqrt(s.vx ^ 2 + s.vy ^ 2) * dt
		log.maxW = math.max(log.maxW, math.abs(s.w))
		if s.vx ~= s.vx or math.abs(s.w) > 20 then log.unstable = true; break end
		if opts.stopBelow and not stopT and math.sqrt(s.vx ^ 2 + s.vy ^ 2) < opts.stopBelow then stopT = t; log.stopDist = dist end
		t += dt
	end
	log.speed = math.sqrt(s.vx ^ 2 + s.vy ^ 2)
	log.w = s.w
	log.dist = dist
	log.stopT = stopT
	log.stats = stats
	log.psi = s.psi
	log.x, log.y = s.x, s.y
	return log
end

local starter = { Chassis="chassis_rust", Engine="eng_i4_junk", Transmission="trans_3sp", Wheels="wheels_bald", Suspension="susp_worn", Battery="batt_lead", FuelTank="tank_rust" }
local pro = { Chassis="chassis_alloy", Engine="eng_v8", Transmission="trans_sport6", Wheels="wheels_street", Suspension="susp_rally", Battery="batt_hd", FuelTank="tank_lr" }
local legend = { Chassis="chassis_carbon", Engine="eng_v8_tt", Transmission="trans_dct", Wheels="wheels_slick", Suspension="susp_air", Battery="batt_li", FuelTank="tank_avia" }
local const = function(v) return function() return v end end

for name, slots in { starter = starter, pro = pro, legend = legend } do
	local st = VS.compute(slots)
	-- 1. flat out
	local a = sim(slots, { duration = 40, throttle = const(1), steer = const(0) })
	print(string.format("%-7s full throttle 40s: speed %.1f / stat top %.1f (%.0f%%)  accel stat %.1f", name, a.speed, st.topSpeed, a.speed / st.topSpeed * 100, st.accel))
	check(not a.unstable, name .. " stable at full throttle")
	check(a.speed > st.topSpeed * 0.88 and a.speed < st.topSpeed * 1.02, name .. " reaches ~top speed")
	-- straight line stays straight
	check(math.abs(a.y) < 1 and math.abs(a.psi) < 0.01, name .. " drives straight")
	-- 2. steady corner at 40 studs/s
	local c = sim(slots, { duration = 6, v0 = 40, throttle = const(0.25), steer = const(1) })
	print(string.format("%-7s corner @40: yaw rate %.2f rad/s  slip %.1f  speed %.1f", name, c.w, c.maxSlip, c.speed))
	check(not c.unstable, name .. " stable in corner")
	check(c.w < -0.1, name .. " turns right when steering right (negative yaw)")
	-- 3. brake from 50
	local b = sim(slots, { duration = 12, v0 = 50, throttle = const(-1), steer = const(0), stopBelow = 1 })
	local expected = 50 * 50 / (2 * st.brake)
	print(string.format("%-7s brake 50->0 in %.2fs / %.1f studs (ideal %.1f)", name, b.stopT or -1, b.stopDist or -1, expected))
	check(b.stopT ~= nil and b.stopDist ~= nil and b.stopDist < expected * 1.6, name .. " brakes in reasonable distance")
	-- 4. hard steer at top speed must not spin out
	local h = sim(slots, { duration = 8, v0 = st.topSpeed * 0.9, throttle = const(1), steer = const(1) })
	check(not h.unstable and h.maxW < 6, name .. " no violent spin at speed (max yaw rate " .. string.format("%.2f", h.maxW) .. ")")
	-- 5. coast to stop slowly, parks
	local r = sim(slots, { duration = 60, v0 = 30, throttle = const(0), steer = const(0) })
	check(r.speed < 1, name .. " coasts to rest (" .. string.format("%.2f", r.speed) .. ")")
end

-- Trade-offs visible in the model:
local sSlick = sim(legend, { duration = 6, v0 = 40, throttle = const(0.25), steer = const(1), surfaceFactor = 1 })
local dirtFactor = VS.surfaceGripFactor(0.0, 1.0, 0.5)
local sSlickDirt = sim(legend, { duration = 6, v0 = 40, throttle = const(0.25), steer = const(1), surfaceFactor = dirtFactor })
print(string.format("slicks: yaw rate on road %.2f vs dirt %.2f (grip x%.2f)", sSlick.w, sSlickDirt.w, dirtFactor))
check(math.abs(sSlickDirt.w) < math.abs(sSlick.w) + 1e-6, "slicks corner worse in dirt")
local heavy = VS.compute(pro).accel
check(sim(pro, { duration = 3, throttle = const(1), steer = const(0) }).speed > sim(starter, { duration = 3, throttle = const(1), steer = const(0) }).speed, "better engine accelerates faster")

print(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
if fails > 0 then error("tests failed") end
