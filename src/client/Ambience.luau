-- Per-biome atmosphere tint + "entering <biome>" banner. Distinct fog colours make regions recognisable.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local WorldData = require(Shared.WorldData)

local Ambience = {}
local player = Players.LocalPlayer

function Ambience.start(onBiome: (any) -> ())
	local current = nil
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.5 then
			return
		end
		acc = 0
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		local biome = WorldData.biomeAt(root.Position.X, root.Position.Z)
		if biome ~= current then
			current = biome
			onBiome(biome)
			local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
			if atmo then
				TweenService:Create(atmo, TweenInfo.new(4), {
					Color = Color3.fromRGB(biome.fog[1], biome.fog[2], biome.fog[3]),
					Density = biome.density,
				}):Play()
			end
		end
	end)
end

return Ambience
