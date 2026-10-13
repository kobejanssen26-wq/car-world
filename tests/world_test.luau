local W = require("./shared/WorldData")
local fails = 0
local function check(c, m) if not c then fails += 1; print("FAIL: " .. m) end end
local t0 = os.clock()
W.buildRoads()
print(string.format("buildRoads %.2fs", os.clock() - t0))

for _, road in W.Roads do
	local s = W.roadSamples(road.id)
	local maxG, len = 0, 0
	for i = 2, #s do
		local dx, dz = s[i].x - s[i-1].x, s[i].z - s[i-1].z
		local run = math.sqrt(dx*dx + dz*dz)
		len += run
		maxG = math.max(maxG, math.abs(s[i].y - s[i-1].y) / run)
	end
	print(string.format("%-12s samples=%3d len=%5.0f maxGrade=%.3f (limit %.2f) start y=%.1f end y=%.1f", road.id, #s, len, maxG, road.maxGrade, s[1].y, s[#s].y))
	check(maxG <= road.maxGrade * 1.02, road.id .. " grade within limit")
end

-- terrain follows the road
for _, road in W.Roads do
	local s = W.roadSamples(road.id)
	local worst = 0
	for i = 3, #s - 2, 5 do
		if s[i].carve then worst = math.max(worst, math.abs(W.heightAt(s[i].x, s[i].z) - s[i].y)) end
	end
	check(worst < 2.5, road.id .. " terrain matches road elevation (worst " .. worst .. ")")
end
-- bridge: ravine is deep below deck; tunnel: terrain well above road
local br = W.Bridges[1]
check(W.heightAt(br.x, br.z) < br.roadY - 15, "ravine below bridge deck: " .. (br.roadY - W.heightAt(br.x, br.z)))
local tu = W.Tunnels[1]
local tr = nil
for _, s in W.roadSamples("pass") do if (s.x-tu.x)^2+(s.z-tu.z)^2 < 40 then tr = s end end
check(W.heightAt(tu.x, tu.z) > tr.y + 18, "mound above tunnel: " .. (W.heightAt(tu.x, tu.z) - tr.y))
-- max slope of free terrain per biome (sampled)
local maxSlope = 0
local t1 = os.clock()
local n = 0
for x = -740, 740, 16 do for z = -740, 740, 16 do
	if x*x+z*z < 700*700 then
		n += 1
		local h = W.heightAt(x, z)
		maxSlope = math.max(maxSlope, math.abs(W.heightAt(x+4, z) - h)/4, math.abs(W.heightAt(x, z+4) - h)/4)
	end
end end
print(string.format("sampled %d points in %.2fs, max slope %.2f", n, os.clock() - t1, maxSlope))
local hub = W.heightAt(0, 0)
print("hub height", hub, "biome", W.biomeAt(0,0).name, "frost", W.biomeAt(470,-470).name, W.heightAt(470,-470))
check(hub > -5 and hub < 40, "hub height sane")

-- ===== sites + pads =====
local Sites = { List = require("./sites_data") }
check(#Sites.List >= 30, "parsed sites: " .. #Sites.List)
W.makePads(Sites.List)
-- terrain must still match the road after pads are applied (no floating / buried roads)
for _, road in W.Roads do
	local worst, at = 0, nil
	for _, s in W.roadSamples(road.id) do
		if s.carve then
			local d = math.abs(W.heightAt(s.x, s.z) - s.y)
			if d > worst then worst, at = d, s end
		end
	end
	if worst > 2.5 then print(string.format("  road %s mismatch %.1f at (%.0f,%.0f)", road.id, worst, at.x, at.z)) end
	check(worst < 3, road.id .. " road/terrain mismatch with pads " .. worst)
end
-- sites inside playable circle, not on a road, pads flat
for _, s in Sites.List do
	local r = math.sqrt(s.x*s.x + s.z*s.z)
	check(r < 700, s.id .. " inside play radius (" .. math.floor(r) .. ")")
	if s.id ~= "hub" then
		local clear = W.roadClearance(s.x, s.z)
		check(clear > 8, s.id .. " clear of road (" .. math.floor(clear) .. ")")
	end
	local pr = W.PadRadius[s.kind]
	local mx = 0
	for a = 0, 5 do
		local ang = a / 6 * math.pi * 2
		mx = math.max(mx, math.abs(W.heightAt(s.x + math.cos(ang) * pr * 0.8, s.z + math.sin(ang) * pr * 0.8) - s.y))
	end
	check(mx < (s.kind == "Outpost" and 6.5 or 1.5), s.id .. " pad flat (dev " .. string.format("%.1f", mx) .. ")")
end
print(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
if fails > 0 then error("tests failed") end
