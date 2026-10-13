-- Server-authoritative container searching. The client only triggers a ProximityPrompt; everything else
-- (distance, cooldown, loot roll, inventory space, granting) happens here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Loot = require(Shared.Loot)
local Profile = require(Shared.Profile)
local Remotes = require(Shared.Remotes)
local Sessions = require(script.Parent.Sessions)
local SiteBuilder = require(script.Parent.SiteBuilder)

local LootService = {}

local rng = Random.new()
local busy: { [Player]: { [string]: boolean } } = {}

local function describeWait(seconds: number): string
	if seconds >= 120 then
		return ("%d min"):format(math.ceil(seconds / 60))
	end
	return ("%d s"):format(math.ceil(seconds))
end

function LootService.search(player: Player, containerId: string)
	local profile = Sessions.profile(player)
	local c = SiteBuilder.containers[containerId]
	if not profile or not c then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return
	end
	if (root.Position - c.part.Position).Magnitude > Config.SearchRange + 8 then
		return -- too far; prompt distance is only a client-side check
	end
	busy[player] = busy[player] or {}
	if busy[player][containerId] then
		return
	end
	busy[player][containerId] = true

	local now = os.time()
	local last = profile.looted[containerId]
	local cooldown = c.fixed and math.huge or Config.ContainerRespawn
	if last and now - last < cooldown then
		if c.fixed then
			Sessions.notify(player, "Already emptied.", "info")
		else
			Sessions.notify(player, "Already searched. Check back in " .. describeWait(cooldown - (now - last)) .. ".", "info")
		end
		busy[player][containerId] = nil
		return
	end

	-- roll first (no side effects), grant only if everything fits
	local items, cash
	if c.fixed then
		items = {}
		for _, id in c.fixed do
			if type(id) == "string" then
				table.insert(items, id)
			end
		end
		cash = c.fixed.cash or 0
	else
		items, cash = Loot.roll(c, rng)
	end
	if Profile.itemCount(profile) + #items > Config.MaxItems then
		Sessions.notify(player, "Inventory full! Sell or install something first.", "warn")
		busy[player][containerId] = nil
		return
	end

	profile.looted[containerId] = now
	profile.stats.searches += 1
	for _, id in items do
		Profile.addItem(profile, id)
	end
	profile.money += cash
	profile.stats.found += #items
	Remotes.get("Loot"):FireClient(player, items, cash, c.part:FindFirstChildOfClass("ProximityPrompt").ObjectText)
	Sessions.push(player)
	busy[player][containerId] = nil
end

function LootService.init()
	for id, c in SiteBuilder.containers do
		local prompt = c.part:FindFirstChildOfClass("ProximityPrompt")
		prompt.Triggered:Connect(function(player)
			LootService.search(player, id)
		end)
	end
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		busy[p] = nil
	end)
end

return LootService
