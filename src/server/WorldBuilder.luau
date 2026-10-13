-- Builds the whole world at server start: voxel terrain (chunked, hub first), roads, bridge, tunnel,
-- biome props, landmarks and every site. Everything is generated from WorldData so the client map matches.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldData = require(Shared.WorldData)
local Sites = require(script.Parent.Sites)
local SiteBuilder = require(script.Parent.SiteBuilder)

local WorldBuilder = {}
WorldBuilder.hubReady = Instance.new("BindableEvent")
WorldBuilder.isHubReady = false
WorldBuilder.isDone = false

local RES = 4
local CHUNK = 64
local N = CHUNK / RES
local Y_MIN = -24
local C = Color3.fromRGB

-- ===== terrain =====
local SUB = { Grass = "Ground", LeafyGrass = "Ground", Ground = "Rock", Sand = "Sandstone", Rock = "Slate", Snow = "Glacier" }

local function surfaceMaterial(biome, h, slope)
	if slope > 1.3 then
		return biome.id == "frost" and "Glacier" or "Rock"
	end
	if biome.id == "highcrest" then
		if h < 70 then return "Grass" end
		if h > 170 then return "Snow" end
		return slope > 0.7 and "Slate" or "Rock"
	elseif biome.id == "frost" then
		return slope > 0.9 and "Rock" or "Snow"
	elseif biome.id == "mesa" then
		return (math.floor(h / 5) % 2 == 0) and "Sandstone" or "Sand"
	end
	return biome.surface
end

local function buildChunk(cx: number, cz: number)
	local x0, z0 = cx * CHUNK, cz * CHUNK
	local H = table.create(N + 2)
	local maxH = -math.huge
	for i = 0, N + 1 do
		local col = table.create(N + 2)
		for k = 0, N + 1 do
			local h = WorldData.heightAt(x0 + (i - 0.5) * RES, z0 + (k - 0.5) * RES)
			col[k] = h
			if i >= 1 and i <= N and k >= 1 and k <= N and h > maxH then
				maxH = h
			end
		end
		H[i] = col
	end
	local yTop = math.ceil((maxH + RES) / RES) * RES
	local ny = (yTop - Y_MIN) / RES
	local mats, occ = table.create(N), table.create(N)
	for i = 1, N do
		local mx, ox = table.create(ny), table.create(ny)
		for j = 1, ny do
			mx[j] = table.create(N)
			ox[j] = table.create(N)
		end
		mats[i], occ[i] = mx, ox
	end
	for i = 1, N do
		for k = 1, N do
			local h = H[i][k]
			local slope = math.max(math.abs(H[i + 1][k] - H[i - 1][k]), math.abs(H[i][k + 1] - H[i][k - 1])) / (2 * RES)
			local biome = WorldData.biomeAt(x0 + (i - 0.5) * RES, z0 + (k - 0.5) * RES)
			local top = surfaceMaterial(biome, h, slope)
			local topEnum = Enum.Material[top]
			local subEnum = Enum.Material[SUB[top] or "Rock"]
			for j = 1, ny do
				local yb = Y_MIN + (j - 1) * RES
				local o = math.clamp((h - yb) / RES, 0, 1)
				if o <= 0 then
					mats[i][j][k] = Enum.Material.Air
					occ[i][j][k] = 0
				else
					occ[i][j][k] = o
					mats[i][j][k] = (h - (yb + RES) < 5) and topEnum or subEnum
				end
			end
		end
	end
	local region = Region3.new(Vector3.new(x0, Y_MIN, z0), Vector3.new(x0 + CHUNK, yTop, z0 + CHUNK))
	Workspace.Terrain:WriteVoxels(region, RES, mats, occ)
end

local function buildTerrain()
	local list = {}
	local r = WorldData.WALL_RADIUS
	local lo, hi = -math.ceil(r / CHUNK), math.ceil(r / CHUNK) - 1
	for cx = lo, hi do
		for cz = lo, hi do
			local mx, mz = (cx + 0.5) * CHUNK, (cz + 0.5) * CHUNK
			if math.sqrt(mx * mx + mz * mz) < r + CHUNK then
				table.insert(list, { cx = cx, cz = cz, d = math.sqrt(mx * mx + mz * mz) })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	local hubChunks = 0
	for _, c in list do
		if c.d < 160 then
			hubChunks += 1
		end
	end
	for i, c in list do
		buildChunk(c.cx, c.cz)
		if i == hubChunks and not WorldBuilder.isHubReady then
			WorldBuilder.isHubReady = true
			WorldBuilder.hubReady:Fire()
		end
		if i % 3 == 0 then
			task.wait()
		end
	end
end

-- ===== roads =====
local function part(parent, name, size, cf, color, mat, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in extra do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function buildRoads(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Roads"
	folder.Parent = parent
	local THICK = 1.2
	local carveQueue = {}
	for _, road in WorldData.Roads do
		local samples = WorldData.roadSamples(road.id)
		local asphalt = road.surface == "asphalt"
		for i = 1, #samples - 1 do
			local a, b = samples[i], samples[i + 1]
			local pa = Vector3.new(a.x, a.y + 0.3, a.z)
			local pb = Vector3.new(b.x, b.y + 0.3, b.z)
			local mid = (pa + pb) / 2
			local len = (pb - pa).Magnitude
			local color = asphalt and C(58, 58, 62) or C(120, 98, 72)
			local mat = asphalt and Enum.Material.Asphalt or Enum.Material.Ground
			if a.bridge then
				color, mat = C(120, 120, 124), Enum.Material.Concrete
			end
			local base = CFrame.lookAt(mid, pb)
			part(folder, "Road", Vector3.new(road.width, THICK, len + 1.6), base * CFrame.new(0, -THICK / 2, 0), color, mat)
			if asphalt and i % 2 == 0 and not a.tunnel then
				part(folder, "Dash", Vector3.new(0.5, 0.1, len * 0.55), base * CFrame.new(0, 0.05, 0), C(235, 220, 90), Enum.Material.SmoothPlastic, { CanCollide = false })
			end
			if a.bridge then
				for _, side in { -1, 1 } do
					part(folder, "Rail", Vector3.new(0.6, 1.6, len + 0.2), base * CFrame.new(side * (road.width / 2 - 0.3), 0.9, 0), C(170, 170, 175), Enum.Material.Metal)
				end
				if i % 3 == 0 then
					local groundY = WorldData.heightAt(a.x, a.z)
					local hgt = math.max(2, a.y - groundY)
					part(folder, "Pillar", Vector3.new(3.5, hgt, 3.5), CFrame.new(a.x, a.y - hgt / 2 - 0.6, a.z), C(130, 130, 134), Enum.Material.Concrete)
				end
			end
			if a.tunnel then
				table.insert(carveQueue, { cf = base * CFrame.new(0, 5.8, 0), size = Vector3.new(road.width + 6, 11.5, len + 2) })
				if i % 3 == 0 then
					local lamp = part(folder, "TunnelLight", Vector3.new(1, 0.3, 1), base * CFrame.new(0, 10.4, 0), C(255, 240, 200), Enum.Material.Neon, { CanCollide = false })
					local l = Instance.new("PointLight")
					l.Range = 26
					l.Brightness = 1.4
					l.Color = C(255, 225, 170)
					l.Parent = lamp
				end
				-- portal frames at the entrance / exit
				local prev, nxt = samples[i - 1], samples[i + 2]
				if (prev and not prev.tunnel) or (nxt and not nxt.tunnel) then
					for _, side in { -1, 1 } do
						part(folder, "PortalPost", Vector3.new(2.2, 12, 2.2), base * CFrame.new(side * (road.width / 2 + 1.5), 5.4, 0), C(150, 150, 152), Enum.Material.Concrete)
					end
					part(folder, "PortalLintel", Vector3.new(road.width + 6, 2.2, 3), base * CFrame.new(0, 12.2, 0), C(150, 150, 152), Enum.Material.Concrete)
				end
			end
		end
	end
	return carveQueue
end

-- ===== props =====
local function cylinderV(parent, name, diameter, height, pos, color, mat)
	return part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), color, mat, { Shape = Enum.PartType.Cylinder })
end

local function pine(parent, pos: Vector3, scale: number, snow: boolean)
	local trunkH = 7 * scale
	cylinderV(parent, "Trunk", 1.6 * scale, trunkH, pos + Vector3.new(0, trunkH / 2, 0), C(90, 62, 40), Enum.Material.Wood)
	local leaf = snow and C(225, 235, 240) or C(38, 92, 52)
	for t = 1, 3 do
		local d = (10 - t * 2.6) * scale
		cylinderV(parent, "Needles", d, 3.2 * scale, pos + Vector3.new(0, trunkH * 0.6 + t * 3 * scale, 0), leaf, Enum.Material.Grass)
	end
end

local function boulder(parent, pos: Vector3, scale: number, color: Color3, rng)
	part(parent, "Boulder", Vector3.new(scale * 1.2, scale, scale * 1.1), CFrame.new(pos + Vector3.new(0, scale * 0.25, 0)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0), color, Enum.Material.Slate, { Shape = Enum.PartType.Ball })
end

local function cactus(parent, pos: Vector3, scale: number)
	part(parent, "Cactus", Vector3.new(1.6 * scale, 6 * scale, 1.6 * scale), CFrame.new(pos + Vector3.new(0, 3 * scale, 0)), C(70, 130, 70), Enum.Material.Grass)
	part(parent, "CactusArm", Vector3.new(3 * scale, 1.2 * scale, 1.2 * scale), CFrame.new(pos + Vector3.new(1.6 * scale, 3.6 * scale, 0)), C(70, 130, 70), Enum.Material.Grass)
end

-- density per 16x16 cell
local DENSITY = {
	valley = { tree = 0.05, rock = 0.02 },
	forest = { tree = 0.55, rock = 0.04 },
	flats = { tree = 0, rock = 0.03 },
	mesa = { tree = 0.03, rock = 0.08 },
	highcrest = { tree = 0.07, rock = 0.12 },
	frost = { tree = 0.06, rock = 0.1 },
}

local function buildProps(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Props"
	folder.Parent = parent
	local rng = Random.new(2024)
	local CELL = 16
	local R = WorldData.PLAY_RADIUS - 15
	local count = 0
	for gx = -R // CELL, R // CELL do
		for gz = -R // CELL, R // CELL do
			local x = gx * CELL + rng:NextNumber(0, CELL)
			local z = gz * CELL + rng:NextNumber(0, CELL)
			if x * x + z * z < R * R then
				local biome = WorldData.biomeAt(x, z)
				local dens = DENSITY[biome.id]
				local roll = rng:NextNumber()
				local kind = nil
				if roll < dens.tree then
					kind = "tree"
				elseif roll < dens.tree + dens.rock then
					kind = "rock"
				end
				if kind and WorldData.roadClearance(x, z) > 7 then
					local clearOfSites = true
					for _, s in Sites.List do
						local r = (WorldData.PadRadius[s.kind] or 20) + 6
						if (x - s.x) ^ 2 + (z - s.z) ^ 2 < r * r then
							clearOfSites = false
							break
						end
					end
					local h = WorldData.heightAt(x, z)
					local slope = math.abs(WorldData.heightAt(x + 3, z) - h) / 3
					if clearOfSites and slope < 1.0 and h < 230 then
						local pos = Vector3.new(x, h - 0.3, z)
						count += 1
						if kind == "tree" then
							if biome.id == "mesa" then
								cactus(folder, pos, rng:NextNumber(0.8, 1.4))
							else
								pine(folder, pos, rng:NextNumber(0.8, 1.6), biome.id == "frost" or h > 175)
							end
						else
							local col = biome.id == "mesa" and C(170, 95, 60) or (biome.id == "frost" and C(200, 210, 220) or C(105, 105, 110))
							boulder(folder, pos, rng:NextNumber(3, 9), col, rng)
						end
					end
				end
			end
		end
		if gx % 8 == 0 then
			task.wait()
		end
	end
	return count
end

-- ===== landmarks (visible from far away so players can navigate without waypoints) =====
local function buildLandmarks(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Landmarks"
	folder.Parent = parent
	local function at(x, z)
		return Vector3.new(x, WorldData.heightAt(x, z), z)
	end
	-- Smelter chimney with red beacon (Iron Flats)
	local p = at(-590, 15)
	cylinderV(folder, "Chimney", 9, 70, p + Vector3.new(0, 35, 0), C(120, 70, 60), Enum.Material.Brick)
	local beacon = part(folder, "Beacon", Vector3.new(3, 3, 3), CFrame.new(p + Vector3.new(0, 72, 0)), C(255, 40, 40), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	local l = Instance.new("PointLight")
	l.Color = C(255, 60, 60)
	l.Range = 40
	l.Parent = beacon
	-- Water tower (Dusty Junction)
	p = at(70, -60)
	for _, o in { Vector3.new(-4, 0, -4), Vector3.new(4, 0, -4), Vector3.new(-4, 0, 4), Vector3.new(4, 0, 4) } do
		part(folder, "TowerLeg", Vector3.new(1, 26, 1), CFrame.new(p + o + Vector3.new(0, 13, 0)), C(130, 130, 135), Enum.Material.Metal)
	end
	cylinderV(folder, "WaterTank", 14, 12, p + Vector3.new(0, 32, 0), C(165, 80, 60), Enum.Material.Metal)
	-- Radio mast (Summit)
	p = at(655, -262)
	part(folder, "Mast", Vector3.new(2, 90, 2), CFrame.new(p + Vector3.new(0, 45, 0)), C(200, 200, 205), Enum.Material.Metal)
	local top = part(folder, "MastLight", Vector3.new(2, 2, 2), CFrame.new(p + Vector3.new(0, 91, 0)), C(255, 40, 40), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	local l2 = Instance.new("PointLight")
	l2.Color = C(255, 60, 60)
	l2.Range = 40
	l2.Parent = top
	-- Oil derricks (Mesa)
	for _, xz in { { 285, 600 }, { 245, 520 }, { 320, 545 } } do
		p = at(xz[1], xz[2])
		part(folder, "DerrickA", Vector3.new(1, 40, 1), CFrame.new(p + Vector3.new(-3, 19, 0)) * CFrame.Angles(0, 0, math.rad(8)), C(150, 70, 40), Enum.Material.Metal)
		part(folder, "DerrickB", Vector3.new(1, 40, 1), CFrame.new(p + Vector3.new(3, 19, 0)) * CFrame.Angles(0, 0, math.rad(-8)), C(150, 70, 40), Enum.Material.Metal)
		part(folder, "PumpBeam", Vector3.new(16, 1.4, 1.4), CFrame.new(p + Vector3.new(0, 8, 4)) * CFrame.Angles(0, 0, math.rad(10)), C(40, 40, 45), Enum.Material.Metal)
	end
	-- Natural arch (Mesa)
	p = at(95, 595)
	part(folder, "ArchL", Vector3.new(9, 28, 9), CFrame.new(p + Vector3.new(-12, 12, 0)), C(185, 100, 60), Enum.Material.Sandstone)
	part(folder, "ArchR", Vector3.new(9, 28, 9), CFrame.new(p + Vector3.new(12, 12, 0)), C(185, 100, 60), Enum.Material.Sandstone)
	part(folder, "ArchTop", Vector3.new(36, 8, 10), CFrame.new(p + Vector3.new(0, 27, 0)), C(185, 100, 60), Enum.Material.Sandstone)
	-- Great Pine (Pinewood)
	p = at(60, -310)
	cylinderV(folder, "GreatPineTrunk", 10, 75, p + Vector3.new(0, 37, 0), C(100, 70, 45), Enum.Material.Wood)
	cylinderV(folder, "GreatPineTop", 40, 14, p + Vector3.new(0, 82, 0), C(35, 90, 50), Enum.Material.Grass)
	-- Frostpeak aurora beacon
	p = at(455, -430)
	part(folder, "IceSpire", Vector3.new(6, 60, 6), CFrame.new(p + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0.5, 0.05), C(150, 220, 255), Enum.Material.Ice, { Transparency = 0.2 })
end

-- ===== orchestration =====
function WorldBuilder.build()
	WorldData.buildRoads()
	WorldData.makePads(Sites.List)

	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = Workspace

	-- sites first (small), so hub buildings exist as soon as the hub terrain is ready
	local siteFolder = Instance.new("Folder")
	siteFolder.Name = "Sites"
	siteFolder.Parent = world
	for _, site in Sites.List do
		SiteBuilder.build(site, siteFolder)
	end

	local carve = buildRoads(world)
	task.spawn(function()
		buildTerrain()
		-- tunnels are carved after every terrain chunk is written so nothing overwrites them
		for _, c in carve do
			Workspace.Terrain:FillBlock(c.cf, c.size, Enum.Material.Air)
		end
		buildLandmarks(world)
		local n = buildProps(world)
		WorldBuilder.isDone = true
		print(("[CarWorld] World complete (%d props, %d containers)"):format(n, (function()
			local c = 0
			for _ in SiteBuilder.containers do c += 1 end
			return c
		end)()))
	end)
end

return WorldBuilder
