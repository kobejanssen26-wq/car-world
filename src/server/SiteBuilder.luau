-- Procedural buildings and searchable containers for every site in Sites.
-- All geometry is plain Parts so it streams in/out with StreamingEnabled.
local CollectionService = game:GetService("CollectionService")

local SiteBuilder = {}

SiteBuilder.containers = {} -- [containerId] = { part, siteId, kind, tier, rolls, hidden, fixed }
SiteBuilder.services = {} -- array of { siteId, name, pos = Vector3, spawnCF = CFrame, terminal = Part }
SiteBuilder.spawnLocation = nil

local PAD_RADIUS = { Hub = 70, Outpost = 34, Garage = 24, Barn = 26, Warehouse = 32, Scrapyard = 36, Wreck = 10, Cache = 16 }
function SiteBuilder.padRadius(kind: string): number
	return PAD_RADIUS[kind] or 20
end

local LOOT_KIND = { Hub = "Garage", Outpost = "Garage", Garage = "Garage", Barn = "Barn", Warehouse = "Warehouse", Scrapyard = "Scrapyard", Wreck = "Wreck", Cache = "Cache" }

local C = Color3.fromRGB
local rng = Random.new(1337)

local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
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

local function cyl(parent, name, diameter, length, cf, color, material)
	-- upright cylinder: Roblox cylinders run along X, so rotate onto Y
	return mk(parent, name, Vector3.new(length, diameter, diameter), cf * CFrame.Angles(0, 0, math.pi / 2), color, material, { Shape = Enum.PartType.Cylinder })
end

local function sign(parent: Instance, text: string, size: Vector3, cf: CFrame, bg: Color3)
	local p = mk(parent, "Sign", size, cf, bg, Enum.Material.Metal, { CanCollide = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextScaled = true
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = C(255, 255, 255)
	l.Parent = gui
	return p
end

-- ===== containers =====
local function addContainer(ctx, localCF: CFrame, size: Vector3, label: string, color: Color3, rollsOverride: number?)
	ctx.count += 1
	local site = ctx.site
	local id = site.id .. "_" .. ctx.count
	local p = mk(ctx.folder, "Container_" .. id, size, ctx.origin * localCF, color, Enum.Material.Metal)
	p:SetAttribute("ContainerId", id)
	CollectionService:AddTag(p, "Container")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Search"
	prompt.ObjectText = label
	prompt.HoldDuration = 1.2
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	SiteBuilder.containers[id] = {
		part = p,
		siteId = site.id,
		kind = LOOT_KIND[site.kind] or "Garage",
		tier = site.tier,
		rolls = rollsOverride or (site.fixed and 2) or 2,
		hidden = site.hidden == true,
		fixed = site.fixed and site.fixed[ctx.count],
	}
	return p
end

local function addNote(ctx, localCF: CFrame, text: string)
	local p = mk(ctx.folder, "Note", Vector3.new(1.2, 0.15, 1.6), ctx.origin * localCF, C(235, 225, 190), Enum.Material.Fabric, { CanCollide = false })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Read"
	prompt.ObjectText = "Note"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	prompt.Triggered:Connect(function(player)
		SiteBuilder.noteRead(player, text)
	end)
end
SiteBuilder.noteRead = function(_player, _text) end -- replaced by Main

-- ===== generic shed (garage / barn / warehouse) =====
local function shed(ctx, w: number, d: number, h: number, wallColor: Color3, roofColor: Color3, gabled: boolean, wallMat: Enum.Material, doorW: number)
	local f, o = ctx.folder, ctx.origin
	local floorY = 0.25
	mk(f, "Floor", Vector3.new(w + 2, 0.5, d + 2), o * CFrame.new(0, floorY - 0.25, 0), C(110, 110, 112), Enum.Material.Concrete)
	-- deep foundation so the building never floats when its pad blends into a sloped road
	mk(f, "Foundation", Vector3.new(w + 1.5, 9, d + 1.5), o * CFrame.new(0, -4.5, 0), C(95, 95, 98), Enum.Material.Concrete)
	-- back + side walls
	mk(f, "WallBack", Vector3.new(w, h, 0.8), o * CFrame.new(0, h / 2 + 0.5, d / 2), wallColor, wallMat)
	mk(f, "WallL", Vector3.new(0.8, h, d), o * CFrame.new(-w / 2, h / 2 + 0.5, 0), wallColor, wallMat)
	mk(f, "WallR", Vector3.new(0.8, h, d), o * CFrame.new(w / 2, h / 2 + 0.5, 0), wallColor, wallMat)
	-- front wall with a door gap
	local side = (w - doorW) / 2
	mk(f, "FrontL", Vector3.new(side, h, 0.8), o * CFrame.new(-(doorW / 2 + side / 2), h / 2 + 0.5, -d / 2), wallColor, wallMat)
	mk(f, "FrontR", Vector3.new(side, h, 0.8), o * CFrame.new(doorW / 2 + side / 2, h / 2 + 0.5, -d / 2), wallColor, wallMat)
	mk(f, "Header", Vector3.new(doorW, h * 0.25, 0.8), o * CFrame.new(0, h * 0.875 + 0.5, -d / 2), wallColor, wallMat)
	if gabled then
		local theta = math.rad(25)
		local slabLen = (w / 2) / math.cos(theta) + 1.2
		local rise = (w / 2) * math.tan(theta)
		mk(f, "RoofL", Vector3.new(slabLen, 0.7, d + 2), o * CFrame.new(-w / 4, h + 0.5 + rise / 2, 0) * CFrame.Angles(0, 0, theta), roofColor, Enum.Material.Metal)
		mk(f, "RoofR", Vector3.new(slabLen, 0.7, d + 2), o * CFrame.new(w / 4, h + 0.5 + rise / 2, 0) * CFrame.Angles(0, 0, -theta), roofColor, Enum.Material.Metal)
		-- gable end fill so the front/back are not open triangles
		return rise
	else
		mk(f, "Roof", Vector3.new(w + 2, 0.8, d + 2), o * CFrame.new(0, h + 0.9, 0), roofColor, Enum.Material.Concrete)
		return 0
	end
end

local function lamp(ctx, localPos: Vector3, brightness: number)
	local p = mk(ctx.folder, "Lamp", Vector3.new(0.8, 0.3, 0.8), ctx.origin * CFrame.new(localPos), C(255, 240, 200), Enum.Material.Neon, { CanCollide = false })
	local l = Instance.new("PointLight")
	l.Range = 24
	l.Brightness = brightness
	l.Color = C(255, 225, 170)
	l.Parent = p
end

local function drum(ctx, x, z, color)
	cyl(ctx.folder, "Drum", 2.4, 3.2, ctx.origin * CFrame.new(x, 1.8, z), color or C(150, 60, 40), Enum.Material.Metal)
end

local function tyreStack(ctx, x, z, n)
	for i = 1, n do
		cyl(ctx.folder, "Tyre", 3, 1.1, ctx.origin * CFrame.new(x, 0.7 + (i - 1) * 1.1, z), C(30, 30, 32), Enum.Material.Rubber)
	end
end

-- ===== builders =====
local B = {}

function B.Garage(ctx)
	shed(ctx, 22, 18, 10, C(165, 165, 160), C(90, 90, 95), false, Enum.Material.Concrete, 12)
	sign(ctx.folder, ctx.site.name:upper(), Vector3.new(14, 2.5, 0.4), ctx.origin * CFrame.new(0, 12.8, -9.7) * CFrame.Angles(0, math.pi, 0), C(40, 60, 110))
	lamp(ctx, Vector3.new(0, 10, 0), 1.2)
	addContainer(ctx, CFrame.new(-7, 1.8, 7.3), Vector3.new(5, 3.4, 2.2), "Tool Chest", C(190, 40, 35))
	addContainer(ctx, CFrame.new(1, 1.8, 7.3), Vector3.new(5, 3.4, 2.2), "Parts Shelf", C(60, 90, 140))
	addContainer(ctx, CFrame.new(8, 1.6, 6.8), Vector3.new(3.5, 3, 3.5), "Engine Crate", C(120, 95, 60))
	drum(ctx, -9, -4)
	drum(ctx, -9, -1.5, C(60, 90, 160))
	tyreStack(ctx, 9, -3, 4)
	mk(ctx.folder, "Workbench", Vector3.new(7, 0.4, 2.2), ctx.origin * CFrame.new(-1, 3, -6.5), C(130, 100, 70), Enum.Material.Wood)
end

function B.Barn(ctx)
	local rise = shed(ctx, 24, 24, 12, C(150, 40, 35), C(70, 55, 50), true, Enum.Material.WoodPlanks, 12)
	-- white trim X on the doors
	mk(ctx.folder, "Trim", Vector3.new(12, 0.8, 0.5), ctx.origin * CFrame.new(0, 12.5, -12.2), C(235, 235, 230), Enum.Material.Wood)
	lamp(ctx, Vector3.new(0, 11, 2), 0.9)
	addContainer(ctx, CFrame.new(-8, 1.7, 9.2), Vector3.new(5, 3.2, 3), "Hay Bale Stack", C(215, 190, 90))
	addContainer(ctx, CFrame.new(0, 1.8, 10.2), Vector3.new(4.5, 3.4, 2.2), "Old Cabinet", C(110, 80, 55))
	addContainer(ctx, CFrame.new(8, 1.6, 9), Vector3.new(4, 3, 3), "Feed Locker", C(90, 100, 90))
	for i = 1, 4 do
		mk(ctx.folder, "Bale", Vector3.new(3.2, 2.2, 2.2), ctx.origin * CFrame.new(-9 + i * 1.5, 1.4, -4 + (i % 2) * 2.2), C(220, 195, 95), Enum.Material.Fabric)
	end
	-- silo
	cyl(ctx.folder, "Silo", 8, 22, ctx.origin * CFrame.new(18, 11, 6), C(175, 175, 170), Enum.Material.Metal)
	mk(ctx.folder, "SiloTop", Vector3.new(8.4, 1.5, 8.4), ctx.origin * CFrame.new(18, 22.5, 6), C(120, 120, 120), Enum.Material.Metal, { Shape = Enum.PartType.Ball })
	return rise
end

function B.Warehouse(ctx)
	shed(ctx, 34, 26, 14, C(120, 125, 130), C(80, 85, 90), false, Enum.Material.CorrugatedMetal, 18)
	sign(ctx.folder, ctx.site.name:upper(), Vector3.new(18, 3, 0.4), ctx.origin * CFrame.new(0, 17, -13.7) * CFrame.Angles(0, math.pi, 0), C(180, 120, 30))
	lamp(ctx, Vector3.new(-8, 13, 0), 1.2)
	lamp(ctx, Vector3.new(8, 13, 0), 1.2)
	local colors = { C(190, 60, 40), C(60, 110, 160), C(200, 160, 40), C(80, 130, 90) }
	local labels = { "Pallet Crate", "Shelf Unit", "Shipping Crate", "Locker" }
	for i = 1, 4 do
		local x = -12 + (i - 1) * 8
		mk(ctx.folder, "Shelf", Vector3.new(6, 6, 1.2), ctx.origin * CFrame.new(x, 3.5, 11.5), C(70, 75, 85), Enum.Material.Metal)
		addContainer(ctx, CFrame.new(x, 1.8, 9.6), Vector3.new(5, 3.4, 2.6), labels[i], colors[i])
	end
	for i = 1, 5 do
		mk(ctx.folder, "Crate", Vector3.new(3, 3, 3), ctx.origin * CFrame.new(-14 + i * 2.2, 2, -4 + (i % 3) * 2.5), C(150, 115, 70), Enum.Material.Wood)
	end
	tyreStack(ctx, 14, -2, 6)
end

function B.Scrapyard(ctx)
	local f, o = ctx.folder, ctx.origin
	local w, d = 44, 36
	-- corrugated fence with a gate gap at the front
	for _, s in { 1, -1 } do
		mk(f, "FenceSide", Vector3.new(0.5, 6, d), o * CFrame.new(s * w / 2, 3.2, 0), C(120, 90, 70), Enum.Material.CorrugatedMetal)
	end
	mk(f, "FenceBack", Vector3.new(w, 6, 0.5), o * CFrame.new(0, 3.2, d / 2), C(120, 90, 70), Enum.Material.CorrugatedMetal)
	mk(f, "FenceFrontL", Vector3.new(w / 2 - 5, 6, 0.5), o * CFrame.new(-(w / 4 + 2.5), 3.2, -d / 2), C(120, 90, 70), Enum.Material.CorrugatedMetal)
	mk(f, "FenceFrontR", Vector3.new(w / 2 - 5, 6, 0.5), o * CFrame.new(w / 4 + 2.5, 3.2, -d / 2), C(120, 90, 70), Enum.Material.CorrugatedMetal)
	sign(f, ctx.site.name:upper(), Vector3.new(16, 3, 0.4), o * CFrame.new(0, 9, -d / 2) * CFrame.Angles(0, math.pi, 0), C(150, 50, 40))
	-- stacked wrecks
	local rust = { C(140, 70, 40), C(110, 90, 75), C(90, 95, 100), C(150, 130, 60) }
	for i = 1, 8 do
		local px = -w / 2 + 6 + (i % 4) * 11 + rng:NextNumber(-1.5, 1.5)
		local pz = (i <= 4) and 8 or 0
		pz += rng:NextNumber(-2, 2)
		for level = 0, rng:NextInteger(1, 3) do
			mk(f, "Wreck", Vector3.new(6.5, 1.8, 13), o * CFrame.new(px, 1.2 + level * 2.1, pz) * CFrame.Angles(0, math.rad(rng:NextInteger(-12, 12)), math.rad(rng:NextInteger(-4, 4))), rust[rng:NextInteger(1, #rust)], Enum.Material.CorrugatedMetal)
		end
	end
	-- crane
	mk(f, "CraneL", Vector3.new(1.4, 20, 1.4), o * CFrame.new(-16, 10, -10), C(210, 170, 40), Enum.Material.Metal)
	mk(f, "CraneR", Vector3.new(1.4, 20, 1.4), o * CFrame.new(16, 10, -10), C(210, 170, 40), Enum.Material.Metal)
	mk(f, "CraneBeam", Vector3.new(34, 1.6, 1.6), o * CFrame.new(0, 20.5, -10), C(210, 170, 40), Enum.Material.Metal)
	local labels = { "Trunk Of A Wreck", "Dented Toolbox", "Rusty Locker", "Engine Block Pile" }
	local pos = { Vector3.new(-14, 1.6, 14), Vector3.new(-3, 1.6, 15), Vector3.new(9, 1.6, 14), Vector3.new(16, 1.6, -4) }
	for i = 1, (ctx.site.containers or 4) do
		addContainer(ctx, CFrame.new(pos[i]), Vector3.new(4.5, 3, 3), labels[i], i % 2 == 0 and C(80, 80, 85) or C(160, 60, 40))
	end
end

function B.Wreck(ctx)
	local f, o = ctx.folder, ctx.origin
	local tilt = CFrame.Angles(math.rad(rng:NextInteger(-6, 6)), 0, math.rad(rng:NextInteger(8, 16)))
	local col = C(120 + rng:NextInteger(-30, 30), 70, 50)
	mk(f, "Body", Vector3.new(7, 1.8, 14), o * CFrame.new(0, 2.2, 0) * tilt, col, Enum.Material.CorrugatedMetal)
	mk(f, "Cabin", Vector3.new(6, 2, 6), o * CFrame.new(0, 3.9, 0.5) * tilt, C(60, 70, 75), Enum.Material.Metal)
	mk(f, "Hood", Vector3.new(6.6, 0.4, 4.5), o * CFrame.new(0, 4.5, -5.5) * CFrame.Angles(math.rad(-50), 0, 0), col, Enum.Material.CorrugatedMetal)
	cyl(f, "Wheel", 3, 1.2, o * CFrame.new(5.5, 1.5, -4) * CFrame.Angles(0, 0, math.pi / 2), C(35, 35, 38), Enum.Material.Rubber)
	cyl(f, "Wheel", 3, 1.2, o * CFrame.new(-3.4, 2.7, 4.6) * tilt * CFrame.Angles(0, 0, math.pi / 2), C(35, 35, 38), Enum.Material.Rubber)
	addContainer(ctx, CFrame.new(0, 3.3, 7.4) * tilt, Vector3.new(5.5, 1.8, 1.6), "Car Trunk", col:Lerp(C(0, 0, 0), 0.2), 3)
end

function B.Cache(ctx)
	local f, o = ctx.folder, ctx.origin
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		local r = 6 + rng:NextNumber(-1, 1)
		local s = rng:NextNumber(4, 7)
		mk(f, "Rock", Vector3.new(s, s * 0.9, s), o * CFrame.new(math.cos(a) * r, s * 0.35, math.sin(a) * r) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0), C(95, 95, 100), Enum.Material.Slate)
	end
	mk(f, "Hatch", Vector3.new(6, 0.6, 6), o * CFrame.new(0, 0.5, 0), C(55, 60, 55), Enum.Material.Metal)
	addContainer(ctx, CFrame.new(0, 1.7, 0), Vector3.new(4, 2.4, 3), "Hidden Stash", C(70, 90, 70), 3)
	addContainer(ctx, CFrame.new(3.5, 1.1, 3), Vector3.new(3, 1.6, 2), "Footlocker", C(110, 70, 40), 2)
end

local function fuelPump(ctx, x, z)
	mk(ctx.folder, "Pump", Vector3.new(1.6, 4.5, 1.6), ctx.origin * CFrame.new(x, 2.5, z), C(200, 50, 40), Enum.Material.Metal)
	mk(ctx.folder, "PumpScreen", Vector3.new(1.2, 0.8, 0.1), ctx.origin * CFrame.new(x, 3.6, z - 0.85), C(60, 255, 120), Enum.Material.Neon, { CanCollide = false })
end

-- Garage terminal + vehicle pad + service point registration.
local function serviceBay(ctx, termLocal: CFrame, padLocal: CFrame)
	local o = ctx.origin
	local term = mk(ctx.folder, "GarageTerminal", Vector3.new(3, 5, 2), o * termLocal, C(35, 40, 55), Enum.Material.Metal)
	mk(ctx.folder, "TerminalScreen", Vector3.new(2.4, 1.8, 0.1), o * termLocal * CFrame.new(0, 0.6, -1.05), C(80, 220, 255), Enum.Material.Neon, { CanCollide = false })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open Garage"
	prompt.ObjectText = ctx.site.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = term
	prompt.Triggered:Connect(function(player)
		SiteBuilder.terminalUsed(player)
	end)
	local pad = mk(ctx.folder, "VehiclePad", Vector3.new(14, 0.4, 20), o * padLocal, C(60, 60, 64), Enum.Material.Concrete, { CanCollide = true })
	for _, z in { -7, 0, 7 } do
		mk(ctx.folder, "PadLine", Vector3.new(0.5, 0.1, 4), o * padLocal * CFrame.new(0, 0.25, z), C(240, 200, 40), Enum.Material.SmoothPlastic, { CanCollide = false })
	end
	table.insert(SiteBuilder.services, {
		siteId = ctx.site.id,
		name = ctx.site.name,
		pos = term.Position,
		spawnCF = pad.CFrame * CFrame.new(0, 3.5, 0),
	})
end
SiteBuilder.terminalUsed = function(_player) end -- replaced by Main

function B.Outpost(ctx)
	B.Garage(ctx)
	fuelPump(ctx, 18, -8)
	fuelPump(ctx, 18, -3)
	mk(ctx.folder, "Canopy", Vector3.new(8, 0.6, 14), ctx.origin * CFrame.new(18, 8, -5.5), C(210, 60, 45), Enum.Material.Metal)
	for _, z in { -11, 0 } do
		mk(ctx.folder, "CanopyPost", Vector3.new(0.7, 8, 0.7), ctx.origin * CFrame.new(21.5, 4, z), C(220, 220, 220), Enum.Material.Metal)
	end
	serviceBay(ctx, CFrame.new(-16, 2.5, -2) * CFrame.Angles(0, math.rad(90), 0), CFrame.new(-4, 0.2, -24))
end

function B.Hub(ctx)
	local f, o = ctx.folder, ctx.origin
	-- plaza
	cyl(f, "Plaza", 90, 0.6, o * CFrame.new(0, 0, 0), C(150, 148, 140), Enum.Material.Concrete)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.4, 10)
	spawn.CFrame = o * CFrame.new(0, 0.5, 6)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = f
	SiteBuilder.spawnLocation = spawn
	-- main garage in the NW corner
	local garageCtx = { site = ctx.site, folder = f, origin = o * CFrame.new(-42, 0, -42) * CFrame.Angles(0, math.rad(45), 0), count = 0 }
	B.Garage(garageCtx)
	ctx.count = garageCtx.count
	-- gas station SE
	local gs = o * CFrame.new(40, 0, 38) * CFrame.Angles(0, math.rad(225), 0)
	local gctx = { site = ctx.site, folder = f, origin = gs, count = 0 }
	for _, x in { -3, 3 } do
		fuelPump(gctx, x, 0)
	end
	mk(f, "Canopy", Vector3.new(14, 0.6, 9), gs * CFrame.new(0, 8, 0), C(210, 60, 45), Enum.Material.Metal)
	for _, p in { Vector3.new(-6, 4, -3.5), Vector3.new(6, 4, -3.5), Vector3.new(-6, 4, 3.5), Vector3.new(6, 4, 3.5) } do
		mk(f, "CanopyPost", Vector3.new(0.7, 8, 0.7), gs * CFrame.new(p), C(220, 220, 220), Enum.Material.Metal)
	end
	-- billboard + diner
	sign(f, "DUSTY JUNCTION", Vector3.new(20, 5, 0.6), o * CFrame.new(40, 9, -40) * CFrame.Angles(0, math.rad(-45) + math.pi, 0), C(30, 80, 60))
	mk(f, "BillboardPost", Vector3.new(1, 8, 1), o * CFrame.new(40, 4, -40), C(80, 70, 60), Enum.Material.Wood)
	mk(f, "Diner", Vector3.new(14, 5, 10), o * CFrame.new(-44, 2.7, 38), C(200, 200, 190), Enum.Material.Metal)
	-- service bay on the plaza
	serviceBay({ site = ctx.site, folder = f, origin = o }, CFrame.new(-14, 2.5, -20) * CFrame.Angles(0, math.rad(20), 0), CFrame.new(10, 0.5, -24) * CFrame.Angles(0, math.rad(90), 0))
end

-- Builds one site. site.y is the flattened pad elevation.
function SiteBuilder.build(site, parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Site_" .. site.id
	folder.Parent = parent
	local origin = CFrame.new(site.x, site.y, site.z) * CFrame.Angles(0, math.rad(site.yaw or 0), 0)
	local ctx = { site = site, folder = folder, origin = origin, count = 0 }
	local builder = B[site.kind]
	if not builder then
		warn("No builder for site kind " .. tostring(site.kind))
		return
	end
	builder(ctx)
	if site.story then
		for i, text in site.story do
			addNote(ctx, CFrame.new(-2 + i * 2, 0.4, -4), text)
		end
	end
end

return SiteBuilder
