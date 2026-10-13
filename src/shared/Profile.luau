-- Pure player-profile logic: default data, schema reconcile and every inventory / garage mutation.
-- The server runs these on the authoritative profile; tests run them on plain tables.
-- Every mutator returns (ok: boolean, errorMessage: string?) and never leaves the profile half-modified.
local Parts = require(script.Parent.Parts)
local Config = require(script.Parent.Config)
local VehicleStats = require(script.Parent.VehicleStats)

local Profile = {}

Profile.VERSION = 1

function Profile.new()
	return {
		version = Profile.VERSION,
		money = Config.StartMoney,
		nextUid = 1,
		nextVid = 1,
		items = {}, -- ["<uid>"] = itemId
		vehicles = {}, -- array of { id, name, slots, fuel, health }
		active = nil, -- vehicle id currently spawned in the world (not persisted as spawned)
		discovered = {}, -- [siteId] = true
		looted = {}, -- [containerId] = os.time() when last searched
		stats = { searches = 0, found = 0 },
	}
end

-- Fill in missing fields and drop invalid data after loading from the DataStore.
function Profile.reconcile(raw)
	local p = Profile.new()
	if type(raw) ~= "table" then
		return p
	end
	if type(raw.money) == "number" and raw.money >= 0 then
		p.money = math.floor(raw.money)
	end
	if type(raw.nextUid) == "number" then
		p.nextUid = math.max(1, math.floor(raw.nextUid))
	end
	if type(raw.nextVid) == "number" then
		p.nextVid = math.max(1, math.floor(raw.nextVid))
	end
	if type(raw.items) == "table" then
		for uid, id in raw.items do
			if type(uid) == "string" and type(id) == "string" and Parts.ById[id] then
				p.items[uid] = id
				p.nextUid = math.max(p.nextUid, (tonumber(uid) or 0) + 1)
			end
		end
	end
	if type(raw.vehicles) == "table" then
		for _, v in raw.vehicles do
			if type(v) == "table" and type(v.id) == "string" and #p.vehicles < Config.MaxVehicles then
				local slots = {}
				if type(v.slots) == "table" then
					for slot, id in v.slots do
						if Parts.ById[id] and Parts.ById[id].slot == slot then
							slots[slot] = id
						end
					end
				end
				table.insert(p.vehicles, {
					id = v.id,
					name = type(v.name) == "string" and string.sub(v.name, 1, 24) or "Car",
					slots = slots,
					fuel = type(v.fuel) == "number" and math.max(0, v.fuel) or 0,
					health = type(v.health) == "number" and math.max(0, v.health) or 0,
				})
			end
		end
	end
	if type(raw.discovered) == "table" then
		for id, v in raw.discovered do
			if type(id) == "string" and v == true then
				p.discovered[id] = true
			end
		end
	end
	if type(raw.looted) == "table" then
		for id, t in raw.looted do
			if type(id) == "string" and type(t) == "number" then
				p.looted[id] = t
			end
		end
	end
	if type(raw.stats) == "table" then
		p.stats.searches = type(raw.stats.searches) == "number" and raw.stats.searches or 0
		p.stats.found = type(raw.stats.found) == "number" and raw.stats.found or 0
	end
	p.version = Profile.VERSION
	return p
end

-- ===== inventory =====
function Profile.itemCount(p): number
	local n = 0
	for _ in p.items do
		n += 1
	end
	return n
end

function Profile.addItem(p, itemId: string): (string?, string?)
	if not Parts.ById[itemId] then
		return nil, "Unknown item"
	end
	if Profile.itemCount(p) >= Config.MaxItems then
		return nil, "Inventory full"
	end
	local uid = tostring(p.nextUid)
	p.nextUid += 1
	p.items[uid] = itemId
	return uid
end

function Profile.removeItem(p, uid: string): string?
	local id = p.items[uid]
	if id then
		p.items[uid] = nil
	end
	return id
end

-- ===== vehicles =====
function Profile.findVehicle(p, vid: string)
	for i, v in p.vehicles do
		if v.id == vid then
			return v, i
		end
	end
	return nil
end

function Profile.createVehicle(p, name: string?)
	if #p.vehicles >= Config.MaxVehicles then
		return false, "Vehicle slots full"
	end
	local id = "v" .. p.nextVid
	p.nextVid += 1
	local n = type(name) == "string" and string.sub(name, 1, 24) or ""
	if n == "" then
		n = "Project " .. (#p.vehicles + 1)
	end
	table.insert(p.vehicles, { id = id, name = n, slots = {}, fuel = 0, health = 0 })
	return true, id
end

function Profile.deleteVehicle(p, vid: string)
	local v, index = Profile.findVehicle(p, vid)
	if not v then
		return false, "No such vehicle"
	end
	local count = 0
	for _ in v.slots do
		count += 1
	end
	if Profile.itemCount(p) + count > Config.MaxItems then
		return false, "Not enough inventory space to take the parts back"
	end
	for _, id in v.slots do
		Profile.addItem(p, id)
	end
	table.remove(p.vehicles, index)
	if p.active == vid then
		p.active = nil
	end
	return true
end

local function refit(v, oldStats)
	local new = VehicleStats.compute(v.slots)
	if not new.complete then
		v.fuel, v.health = 0, 0
		return
	end
	if not oldStats or not oldStats.complete then
		v.fuel = new.fuelCapacity * Config.VehicleStartFuelFraction
		v.health = new.durability
	else
		v.fuel = math.min(v.fuel, new.fuelCapacity)
		local frac = oldStats.durability > 0 and v.health / oldStats.durability or 1
		v.health = math.clamp(frac * new.durability, 0, new.durability)
	end
end

-- Move an item from the inventory into a vehicle slot (swapping out whatever was there).
function Profile.install(p, vid: string, uid: string)
	local v = Profile.findVehicle(p, vid)
	if not v then
		return false, "No such vehicle"
	end
	local itemId = p.items[uid]
	if not itemId then
		return false, "You don't have that item"
	end
	local part = Parts.ById[itemId]
	local old = VehicleStats.compute(v.slots)
	local previous = v.slots[part.slot]
	p.items[uid] = nil
	v.slots[part.slot] = itemId
	if previous then
		-- inventory count is unchanged by a swap (one in, one out) so this cannot fail on capacity
		Profile.addItem(p, previous)
	end
	refit(v, old)
	return true
end

function Profile.uninstall(p, vid: string, slot: string)
	local v = Profile.findVehicle(p, vid)
	if not v then
		return false, "No such vehicle"
	end
	if type(slot) ~= "string" or not Parts.BySlot[slot] then
		return false, "Bad slot"
	end
	local id = v.slots[slot]
	if not id then
		return false, "Nothing installed there"
	end
	if Profile.itemCount(p) >= Config.MaxItems then
		return false, "Inventory full"
	end
	local old = VehicleStats.compute(v.slots)
	v.slots[slot] = nil
	Profile.addItem(p, id)
	refit(v, old)
	return true
end

-- ===== economy =====
function Profile.buyPrice(itemId: string): number
	return math.ceil(Parts.ById[itemId].value * Config.BuyFactor)
end

function Profile.sellPrice(itemId: string): number
	return math.floor(Parts.ById[itemId].value * Config.SellFactor)
end

-- The shop only ever stocks Common parts, so rarer parts must be found in the world.
function Profile.buy(p, itemId: string)
	local part = Parts.ById[itemId]
	if not part or part.rarity ~= "Common" then
		return false, "Not for sale"
	end
	local price = Profile.buyPrice(itemId)
	if p.money < price then
		return false, "Not enough cash"
	end
	if Profile.itemCount(p) >= Config.MaxItems then
		return false, "Inventory full"
	end
	p.money -= price
	Profile.addItem(p, itemId)
	return true
end

function Profile.sell(p, uid: string)
	local id = p.items[uid]
	if not id then
		return false, "You don't have that item"
	end
	p.items[uid] = nil
	p.money += Profile.sellPrice(id)
	return true
end

function Profile.refuel(p, vid: string, litres: number?)
	local v = Profile.findVehicle(p, vid)
	if not v then
		return false, "No such vehicle"
	end
	local stats = VehicleStats.compute(v.slots)
	if not stats.complete then
		return false, "Vehicle is incomplete"
	end
	local missing = stats.fuelCapacity - v.fuel
	local want = math.min(missing, type(litres) == "number" and litres or missing)
	if want < 0.5 then
		return false, "Tank is already full"
	end
	local afford = math.floor(p.money / Config.FuelPrice)
	local amount = math.min(want, afford)
	if amount < 0.5 then
		return false, "Not enough cash"
	end
	p.money -= math.ceil(amount * Config.FuelPrice)
	v.fuel = math.min(stats.fuelCapacity, v.fuel + amount)
	return true
end

function Profile.repair(p, vid: string)
	local v = Profile.findVehicle(p, vid)
	if not v then
		return false, "No such vehicle"
	end
	local stats = VehicleStats.compute(v.slots)
	if not stats.complete then
		return false, "Vehicle is incomplete"
	end
	local missing = stats.durability - v.health
	if missing < 1 then
		return false, "Nothing to repair"
	end
	local cost = math.ceil(missing * Config.RepairPrice)
	if p.money < cost then
		-- partial repair with whatever the player can afford
		local hp = math.floor(p.money / Config.RepairPrice)
		if hp < 1 then
			return false, "Not enough cash"
		end
		p.money -= math.ceil(hp * Config.RepairPrice)
		v.health = math.min(stats.durability, v.health + hp)
		return true
	end
	p.money -= cost
	v.health = stats.durability
	return true
end

return Profile
