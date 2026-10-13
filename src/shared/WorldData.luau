-- Pure world math: biomes, roads, features and the terrain height function.
-- The server builds terrain from this; the client reads biomes/roads for the map and ambience.
local WorldData = {}

WorldData.PLAY_RADIUS = 740 -- beyond this a mountain wall rises
WorldData.WALL_RADIUS = 800 -- terrain is generated out to here

-- rgb is the map colour; surface/subsurface are Enum.Material names.
WorldData.Biomes = {
	{ id = "valley", name = "Rustwood Valley", cx = 0, cz = 0, r = 340, base = 10, amp = 7, scale = 220, shape = "rolling", seed = 11,
		surface = "Grass", rgb = { 110, 160, 80 }, fog = { 190, 205, 220 }, density = 0.25 },
	{ id = "forest", name = "Pinewood Forest", cx = 0, cz = -480, r = 300, base = 18, amp = 24, scale = 130, shape = "rolling", seed = 23,
		surface = "LeafyGrass", rgb = { 50, 110, 60 }, fog = { 150, 175, 160 }, density = 0.42 },
	{ id = "flats", name = "Iron Flats", cx = -480, cz = 130, r = 300, base = 8, amp = 4, scale = 300, shape = "rolling", seed = 37,
		surface = "Ground", rgb = { 130, 125, 120 }, fog = { 170, 165, 160 }, density = 0.45 },
	{ id = "mesa", name = "Redrock Mesa", cx = 150, cz = 520, r = 300, base = 14, amp = 38, scale = 95, shape = "mesa", seed = 41,
		surface = "Sand", rgb = { 205, 150, 90 }, fog = { 230, 190, 150 }, density = 0.3 },
	{ id = "highcrest", name = "Highcrest Mountains", cx = 520, cz = -90, r = 330, base = 50, amp = 120, scale = 230, shape = "ridged", seed = 53,
		surface = "Rock", rgb = { 120, 115, 125 }, fog = { 175, 185, 205 }, density = 0.35 },
	{ id = "frost", name = "Frostpeak", cx = 470, cz = -470, r = 250, base = 90, amp = 130, scale = 210, shape = "ridged", seed = 67,
		surface = "Snow", rgb = { 230, 238, 245 }, fog = { 215, 225, 240 }, density = 0.5 },
}

-- Roads are Catmull-Rom splines through waypoints. maxGrade = rise/run limit.
-- Steeper maxGrade => needs a stronger car (see VehicleStats.climbDeg).
WorldData.Roads = {
	{ id = "junction", name = "Junction Road", surface = "asphalt", width = 22, maxGrade = 0.05,
		pts = { { -46, 6 }, { -150, 30 }, { -300, 80 }, { -420, 110 }, { -470, 130 } } },
	{ id = "pinewood", name = "Pinewood Road", surface = "asphalt", width = 20, maxGrade = 0.08,
		pts = { { -2, -46 }, { -5, -150 }, { -30, -300 }, { -10, -420 }, { 0, -470 } } },
	{ id = "logging", name = "Logging Track", surface = "dirt", width = 14, maxGrade = 0.12,
		pts = { { 0, -470 }, { 70, -500 }, { 140, -520 } } },
	{ id = "cabin", name = "Cabin Trail", surface = "dirt", width = 12, maxGrade = 0.14,
		pts = { { 0, -470 }, { -60, -520 }, { -120, -560 } } },
	{ id = "mesa", name = "Mesa Road", surface = "dirt", width = 16, maxGrade = 0.12,
		pts = { { 8, 46 }, { 40, 150 }, { 100, 300 }, { 130, 420 }, { 150, 500 } } },
	{ id = "highcrest", name = "Highcrest Road", surface = "asphalt", width = 20, maxGrade = 0.12,
		pts = { { 46, -4 }, { 150, -30 }, { 300, -60 }, { 420, -100 }, { 470, -150 } } },
	{ id = "pass", name = "Summit Pass", surface = "asphalt", width = 16, maxGrade = 0.30,
		pts = { { 470, -150 }, { 505, -172 }, { 530, -190 }, { 565, -206 }, { 600, -220 }, { 640, -230 } } },
	{ id = "quarry", name = "Quarry Spur", surface = "dirt", width = 14, maxGrade = 0.22,
		pts = { { 420, -100 }, { 480, -30 }, { 560, 60 } } },
	{ id = "frost", name = "Frost Road", surface = "dirt", width = 14, maxGrade = 0.38,
		pts = { { 470, -150 }, { 440, -250 }, { 455, -350 }, { 470, -470 } } },
}

-- Bridge over a ravine; tunnel through a mound. Both sit on a road waypoint.
WorldData.Bridges = { { x = 530, z = -190, half = 28, ravineHalfLen = 70, depth = 30 } }
WorldData.Tunnels = { { x = 600, z = -220, half = 42, moundR = 85, moundH = 52 } }

local floor, sqrt, abs, clamp, noise = math.floor, math.sqrt, math.abs, math.clamp, math.noise

local function smoothstep(a, b, x)
	local t = clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function fbm(x, z, seed, scale)
	local sum, amp, freq, norm = 0, 1, 1 / scale, 0
	for _ = 1, 4 do
		sum += amp * noise(x * freq + seed * 3.7, z * freq + seed * 1.3, seed * 0.37)
		norm += amp
		amp *= 0.5
		freq *= 2.03
	end
	return sum / norm
end

local function biomeHeight(b, x, z)
	local n = fbm(x, z, b.seed, b.scale)
	if b.shape == "rolling" then
		return b.base + b.amp * n * 1.6
	elseif b.shape == "mesa" then
		local t = smoothstep(-0.04, 0.04, n)
		return b.base + b.amp * (0.35 * n * 2 + t)
	else -- ridged
		local r = clamp(1 - abs(fbm(x, z, b.seed + 5, b.scale)) * 2.2, 0, 1)
		return b.base + b.amp * (r * r + 0.2 * n)
	end
end

local function biomeWeights(x, z)
	local best, bestW, total, out = nil, -1, 0, {}
	for i, b in WorldData.Biomes do
		local dx, dz = x - b.cx, z - b.cz
		local d = sqrt(dx * dx + dz * dz)
		local w = math.max(0, 1 - d / (b.r * 1.3)) ^ 2.5 + 1e-5
		out[i] = w
		total += w
		if w > bestW then
			bestW, best = w, b
		end
	end
	return out, total, best
end

-- Raw biome-blended height (no roads, features, pads, wall).
function WorldData.baseHeight(x, z)
	local ws, total = biomeWeights(x, z)
	local h = 0
	for i, b in WorldData.Biomes do
		if ws[i] > 2e-5 then -- biomes whose influence has fully faded are skipped (exact, not an approximation)
			h += ws[i] / total * biomeHeight(b, x, z)
		end
	end
	return h
end

function WorldData.biomeAt(x, z)
	local _, _, best = biomeWeights(x, z)
	return best
end

function WorldData.hubY()
	return WorldData.baseHeight(0, 0)
end

-- ===== Roads =====
local STEP = 8
local CELL = 32
local roadSamples = {} -- list of samples {x,z,y,road,i,carve}
local grid = {}
local pads = {}
WorldData.RoadRuntime = {} -- road.id -> list of samples (for the world builder)

local function cellKey(cx, cz)
	return cx * 8192 + cz
end

local function catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	local function c(a, b, c_, d)
		return 0.5 * ((2 * b) + (-a + c_) * t + (2 * a - 5 * b + 4 * c_ - d) * t2 + (-a + 3 * b - 3 * c_ + d) * t3)
	end
	return c(p0[1], p1[1], p2[1], p3[1]), c(p0[2], p1[2], p2[2], p3[2])
end

local function resample(road)
	local pts = road.pts
	local dense = {}
	for i = 1, #pts - 1 do
		local p0 = pts[math.max(1, i - 1)]
		local p1, p2 = pts[i], pts[i + 1]
		local p3 = pts[math.min(#pts, i + 2)]
		for s = 0, 19 do
			local x, z = catmull(p0, p1, p2, p3, s / 20)
			table.insert(dense, { x, z })
		end
	end
	table.insert(dense, { pts[#pts][1], pts[#pts][2] })
	local out = { dense[1] }
	local acc = 0
	for i = 2, #dense do
		local a, b = dense[i - 1], dense[i]
		local seg = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local remaining = seg
		local ax, az = a[1], a[2]
		while acc + remaining >= STEP do
			local need = STEP - acc
			local f = need / remaining
			ax, az = ax + (b[1] - ax) * f, az + (b[2] - az) * f
			table.insert(out, { ax, az })
			remaining -= need
			acc = 0
		end
		acc += remaining
	end
	return out
end

local function inList(list, x, z, rangeKey)
	for _, f in list do
		local dx, dz = x - f.x, z - f.z
		if dx * dx + dz * dz <= f[rangeKey] * f[rangeKey] then
			return f
		end
	end
	return nil
end

function WorldData.buildRoads()
	table.clear(roadSamples)
	table.clear(grid)
	for _, road in WorldData.Roads do
		local pts = resample(road)
		local samples = {}
		for i, p in pts do
			samples[i] = { x = p[1], z = p[2], y = WorldData.baseHeight(p[1], p[2]), road = road, i = i }
		end
		-- smooth the elevation profile
		for _ = 1, 3 do
			local ys = {}
			for i = 1, #samples do
				local sum, n = 0, 0
				for j = math.max(1, i - 6), math.min(#samples, i + 6) do
					sum += samples[j].y
					n += 1
				end
				ys[i] = sum / n
			end
			for i = 1, #samples do
				samples[i].y = ys[i]
			end
		end
		-- pin ends that join an already built road so junctions share one elevation
		for _, idx in { 1, #samples } do
			local e = samples[idx]
			if e.x * e.x + e.z * e.z < 3600 then
				e.y, e.pinned = WorldData.hubY(), true -- roads leaving the hub plaza all start at plaza height
			end
			for _, other in roadSamples do
				if (other.x - e.x) ^ 2 + (other.z - e.z) ^ 2 < 36 then
					e.y, e.pinned = other.y, true
					break
				end
			end
		end
		-- grade limit (forward then backward) so the road never exceeds road.maxGrade
		local maxD = road.maxGrade * STEP
		for i = 2, #samples do
			if not samples[i].pinned then
				samples[i].y = clamp(samples[i].y, samples[i - 1].y - maxD, samples[i - 1].y + maxD)
			end
		end
		for i = #samples - 1, 1, -1 do
			if not samples[i].pinned then
				samples[i].y = clamp(samples[i].y, samples[i + 1].y - maxD, samples[i + 1].y + maxD)
			end
		end
		for i, s in samples do
			local a, b = samples[math.max(1, i - 1)], samples[math.min(#samples, i + 1)]
			local tx, tz = b.x - a.x, b.z - a.z
			local len = sqrt(tx * tx + tz * tz)
			s.tx, s.tz = tx / len, tz / len
			s.bridge = inList(WorldData.Bridges, s.x, s.z, "half") ~= nil
			s.tunnel = inList(WorldData.Tunnels, s.x, s.z, "half") ~= nil
			s.carve = not (s.bridge or s.tunnel)
			table.insert(roadSamples, s)
			if s.carve then
				local k = cellKey(floor(s.x / CELL), floor(s.z / CELL))
				grid[k] = grid[k] or {}
				table.insert(grid[k], s)
			end
		end
		WorldData.RoadRuntime[road.id] = samples
	end
	-- orient ravines perpendicular to the road at each bridge
	for _, br in WorldData.Bridges do
		local best, bd = nil, math.huge
		for _, s in roadSamples do
			local d = (s.x - br.x) ^ 2 + (s.z - br.z) ^ 2
			if d < bd then
				bd, best = d, s
			end
		end
		br.tx, br.tz = best.tx, best.tz
		br.roadY = best.y
	end
end

-- Closest point on any (carving) road: returns y, distance, halfWidth or nil.
local function nearestRoad(x, z, maxDist)
	local cx, cz = floor(x / CELL), floor(z / CELL)
	local reach = math.ceil(maxDist / CELL)
	local bestD, bestY, bestW = math.huge, nil, nil
	for gx = cx - reach, cx + reach do
		for gz = cz - reach, cz + reach do
			local list = grid[cellKey(gx, gz)]
			if list then
				for _, s in list do
					local dx, dz = x - s.x, z - s.z
					local d2 = dx * dx + dz * dz
					if d2 < (bestD + STEP) * (bestD + STEP) then
						-- distance to the road centre line (round cap beyond the sample's reach)
						local along = dx * s.tx + dz * s.tz
						local d
						if abs(along) <= STEP * 0.5 then
							local px, pz = dx - s.tx * along, dz - s.tz * along
							d = sqrt(px * px + pz * pz)
						else
							d = sqrt(d2)
						end
						if d < bestD then
							bestD = d
							bestY = s.y
							bestW = s.road.width / 2
						end
					end
				end
			end
		end
	end
	if bestY then
		return bestY, bestD, bestW
	end
	return nil
end

-- ===== Features =====
local function featureHeight(x, z, h)
	for _, t in WorldData.Tunnels do
		local dx, dz = x - t.x, z - t.z
		local d = sqrt(dx * dx + dz * dz)
		if d < t.moundR then
			local f = 1 - d / t.moundR
			h += t.moundH * f * f * (3 - 2 * f)
		end
	end
	for _, br in WorldData.Bridges do
		if br.tx then
			local dx, dz = x - br.x, z - br.z
			local across = dx * br.tx + dz * br.tz -- along the road = across the ravine
			local along = -dx * br.tz + dz * br.tx -- along the ravine
			local w = br.half * 0.85
			local f = (1 - smoothstep(w * 0.55, w, abs(across))) * (1 - smoothstep(br.ravineHalfLen * 0.7, br.ravineHalfLen, abs(along)))
			if f > 0 then
				h -= br.depth * f
			end
		end
	end
	return h
end

function WorldData.setPads(list)
	pads = list
end

-- Flat building pads per site kind (radius in studs).
WorldData.PadRadius = { Hub = 70, Outpost = 34, Garage = 24, Barn = 26, Warehouse = 32, Scrapyard = 36, Wreck = 10, Cache = 16 }

-- Assigns site.y and installs one flat pad per site. Call after buildRoads().
function WorldData.makePads(siteList)
	local list = {}
	pads = {}
	for _, site in siteList do
		site.y = WorldData.heightAt(site.x, site.z)
		if site.id == "hub" then
			site.y = WorldData.hubY()
		else
			-- sit level with a nearby road so the pad and the road blend instead of fighting
			local best, bd = nil, 90 * 90
			for _, rs in roadSamples do
				local d2 = (rs.x - site.x) ^ 2 + (rs.z - site.z) ^ 2
				if rs.carve and d2 < bd then
					bd, best = d2, rs
				end
			end
			if best then
				site.y = best.y
			end
		end
		table.insert(list, { x = site.x, z = site.z, r = WorldData.PadRadius[site.kind] or 20, y = site.y })
	end
	pads = list
	return list
end

-- Distance from (x,z) to the nearest road edge (huge if no road within 48 studs).
function WorldData.roadClearance(x, z)
	local _, d, w = nearestRoad(x, z, 48)
	if d then
		return d - w
	end
	return math.huge
end

function WorldData.heightAt(x, z)
	local h = WorldData.baseHeight(x, z)
	h = featureHeight(x, z, h)
	for _, p in pads do
		local dx, dz = x - p.x, z - p.z
		local d2 = dx * dx + dz * dz
		local outer = p.r + 18
		if d2 < outer * outer then
			local w = 1 - smoothstep(p.r, outer, sqrt(d2))
			h += (p.y - h) * w
		end
	end
	local ry, rd, rw = nearestRoad(x, z, 48)
	if ry then
		local w = 1 - smoothstep(rw + 3, rw + 26, rd)
		h += (ry - h) * w
	end
	-- mountain wall closing the playable circle
	local d = sqrt(x * x + z * z)
	if d > WorldData.PLAY_RADIUS then
		local f = (d - WorldData.PLAY_RADIUS) / 60
		h += 300 * f * f
	end
	return h
end

-- Height *without* pads: used to place pads so they sit at the natural/road elevation.
function WorldData.heightNoPads(x, z)
	local saved = pads
	pads = {}
	local h = WorldData.heightAt(x, z)
	pads = saved
	return h
end

-- Elevation of the road centre line at a sample (for building road parts/bridges).
function WorldData.roadSamples(roadId)
	return WorldData.RoadRuntime[roadId]
end

return WorldData
