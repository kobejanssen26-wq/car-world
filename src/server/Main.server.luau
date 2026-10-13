-- Entry point: boots remotes, lighting, world, services, and handles the player lifecycle.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

Players.CharacterAutoLoads = false
Remotes.create()

local DataService = require(script.Parent.DataService)
local Sessions = require(script.Parent.Sessions)
local Sites = require(script.Parent.Sites)
local SiteBuilder = require(script.Parent.SiteBuilder)
local WorldBuilder = require(script.Parent.WorldBuilder)
local LootService = require(script.Parent.LootService)
local GarageService = require(script.Parent.GarageService)
local VehicleService = require(script.Parent.VehicleService)

-- ===== lighting / atmosphere (client tints fog per biome) =====
Lighting.ClockTime = 15.5
Lighting.Brightness = 2.4
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.6
Lighting.GlobalShadows = true
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.3
atmosphere.Offset = 0.25
atmosphere.Color = Color3.fromRGB(190, 205, 220)
atmosphere.Decay = Color3.fromRGB(230, 200, 170)
atmosphere.Glare = 0.2
atmosphere.Haze = 1.2
atmosphere.Parent = Lighting
local cc = Instance.new("ColorCorrectionEffect")
cc.Saturation = 0.12
cc.Contrast = 0.08
cc.Parent = Lighting
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.25
bloom.Parent = Lighting

-- ===== world =====
SiteBuilder.noteRead = function(player, text)
	Sessions.notify(player, text, "story")
end
SiteBuilder.terminalUsed = function(player)
	Remotes.get("OpenGarage"):FireClient(player)
end
WorldBuilder.build()
LootService.init()
GarageService.init()

-- ===== discovery (walk near a place to put it on your map) =====
local discoverAccum = 0
RunService.Heartbeat:Connect(function(dt)
	discoverAccum += dt
	if discoverAccum < 1 then
		return
	end
	discoverAccum = 0
	for player, profile in Sessions.all() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local p = root.Position
			for _, site in Sites.List do
				if not profile.discovered[site.id] then
					local range = site.hidden and 40 or Config.DiscoverRange
					local dx, dz = p.X - site.x, p.Z - site.z
					if dx * dx + dz * dz < range * range then
						profile.discovered[site.id] = true
						Remotes.get("Discovered"):FireClient(player, site.name, site.hidden == true)
						Sessions.push(player)
					end
				end
			end
		end
	end
end)

-- ===== player lifecycle =====
local function spawnCharacter(player: Player)
	if not WorldBuilder.isHubReady then
		WorldBuilder.hubReady.Event:Wait()
	end
	if player.Parent then
		player:LoadCharacter()
	end
end

local function onCharacterAdded(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if hum then
		hum.Died:Connect(function()
			task.wait(3)
			if player.Parent and Sessions.profile(player) then
				player:LoadCharacter()
			end
		end)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	local profile, err = DataService.load(player)
	if not profile then
		player:Kick(err or "Could not load your data. Please rejoin.")
		return
	end
	if not player.Parent then
		DataService.save(player, profile, true)
		DataService.release(player)
		return
	end
	profile.active = nil -- vehicles never persist as spawned
	Sessions.add(player, profile)
	Sessions.push(player)
	spawnCharacter(player)
end

local function saveAndRelease(player: Player)
	local profile = Sessions.profile(player)
	VehicleService.despawn(player) -- writes final fuel/health into the record (already live in the profile)
	if profile then
		DataService.save(player, profile, true)
	end
	Sessions.remove(player)
	DataService.release(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end
Players.PlayerRemoving:Connect(saveAndRelease)

-- periodic autosave, staggered to respect DataStore budgets
task.spawn(function()
	while true do
		task.wait(Config.AutosaveInterval)
		for player, profile in Sessions.all() do
			task.spawn(DataService.save, player, profile, false)
			task.wait(0.5)
		end
	end
end)

-- on shutdown, save everyone in parallel and wait for completion
game:BindToClose(function()
	if RunService:IsStudio() then
		task.wait(1)
	end
	local pending = 0
	for player, profile in Sessions.all() do
		pending += 1
		task.spawn(function()
			DataService.save(player, profile, true)
			pending -= 1
		end)
	end
	local t = os.clock()
	while pending > 0 and os.clock() - t < 25 do
		task.wait(0.2)
	end
end)
