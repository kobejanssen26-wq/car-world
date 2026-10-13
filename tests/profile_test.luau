-- Random shim for plain Luau (Roblox provides the real one)
Random = { new = function(seed) math.randomseed(seed); return { NextNumber = function() return math.random() end, NextInteger = function(_, a, b) return math.random(a, b) end } end }
local P = require("./shared/Profile")
local Loot = require("./shared/Loot")
local Parts = require("./shared/Parts")
local VS = require("./shared/VehicleStats")
local fails = 0
local function check(c, m) if not c then fails += 1; print("FAIL: " .. m) end end

local p = P.new()
local ok, vid = P.createVehicle(p, "Test")
check(ok and vid == "v1", "create vehicle")
local ids = { "chassis_rust","eng_i4_junk","trans_3sp","wheels_bald","susp_worn","batt_lead","tank_rust" }
local uids = {}
for _, id in ids do uids[id] = P.addItem(p, id) end
for i, id in ids do
	local ok2 = P.install(p, "v1", uids[id])
	check(ok2, "install " .. id)
	check(p.items[uids[id]] == nil, "item consumed " .. id)
	local c = VS.compute(p.vehicles[1].slots)
	check(c.complete == (i == #ids), "complete only after last part (" .. i .. ")")
end
local v = p.vehicles[1]
check(v.fuel == 12 and v.health == 120, "fuel/health initialised: " .. v.fuel .. "/" .. v.health)
check(P.itemCount(p) == 0, "inventory empty after install")
-- cannot install the same uid twice (dupe protection)
check(not P.install(p, "v1", uids["eng_i4_junk"]), "no reinstall of consumed uid")
-- swap: new engine returns old one
local u = P.addItem(p, "eng_v6")
check(P.install(p, "v1", u), "swap engine")
check(P.itemCount(p) == 1 and p.items[next(p.items)] == "eng_i4_junk", "old engine returned")
-- uninstall -> incomplete resets fuel
check(P.uninstall(p, "v1", "Engine"), "uninstall")
check(v.fuel == 0 and v.health == 0, "incomplete vehicle has no fuel/health")
-- economy
p.money = 100
check(not P.buy(p, "eng_v6"), "uncommon not sold in shop")
check(P.buy(p, "tank_rust") and p.money == 100 - math.ceil(35 * 1.6), "buy common")
p.money = 0
check(not P.buy(p, "tank_rust"), "can't buy without money")
local uid = next(p.items)
local before = P.itemCount(p)
check(P.sell(p, uid) and P.itemCount(p) == before - 1 and p.money > 0, "sell")
check(not P.sell(p, uid), "no double sell")
-- inventory cap
local q = P.new()
for i = 1, 60 do assert(P.addItem(q, "chassis_rust")) end
check(P.addItem(q, "chassis_rust") == nil, "inventory cap")
-- vehicle cap
for i = 1, 3 do P.createVehicle(q, nil) end
check(not P.createVehicle(q, nil), "vehicle cap")
-- delete returns parts, rejects when full
local r = P.new(); P.createVehicle(r, "x"); P.install(r, "v1", P.addItem(r, "chassis_rust"))
check(P.deleteVehicle(r, "v1") and P.itemCount(r) == 1, "delete vehicle returns parts")
-- refuel / repair
local s = P.new(); P.createVehicle(s, "x")
for _, id in ids do P.install(s, "v1", P.addItem(s, id)) end
s.money = 1000; s.vehicles[1].fuel = 0; s.vehicles[1].health = 20
check(P.refuel(s, "v1") and s.vehicles[1].fuel == 30 and s.money == 1000 - 45, "refuel full")
check(P.repair(s, "v1") and s.vehicles[1].health == 120, "repair")
-- reconcile sanitises hostile/corrupt data
local rec = P.reconcile({ money = -5, items = { ["3"] = "nonexistent", ["4"] = "eng_v6" }, vehicles = { { id = "v9", slots = { Engine = "chassis_rust", Chassis = "chassis_rust" } } }, discovered = { a = true, b = 5 } })
check(rec.money == P.new().money, "negative money rejected")
check(rec.items["3"] == nil and rec.items["4"] == "eng_v6" and rec.nextUid >= 5, "item sanitised")
check(rec.vehicles[1].slots.Engine == nil and rec.vehicles[1].slots.Chassis == "chassis_rust", "slot mismatch dropped")
check(rec.discovered.a and not rec.discovered.b, "discovered sanitised")
check(P.reconcile(nil).money == 150, "nil -> default")
-- loot distribution
local rng = Random.new(42)
local counts = { Common = 0, Uncommon = 0, Rare = 0, Legendary = 0 }
for tier = 1, 4 do
	local c = { Common = 0, Uncommon = 0, Rare = 0, Legendary = 0 }
	for i = 1, 4000 do
		local items = Loot.roll({ kind = "Garage", tier = tier, rolls = 2 }, rng)
		for _, id in items do c[Parts.ById[id].rarity] += 1 end
	end
	print(string.format("tier %d: C=%d U=%d R=%d L=%d", tier, c.Common, c.Uncommon, c.Rare, c.Legendary))
	if tier == 1 then check(c.Legendary == 0 and c.Common > c.Uncommon, "tier1 has no legendary") end
	if tier == 4 then check(c.Legendary > c.Common * 0.5 or c.Rare > c.Common, "tier4 rich") end
end
local hidden = Loot.roll({ kind = "Cache", tier = 1, rolls = 2, hidden = true }, rng)
check(#hidden >= 1 and Parts.ById[hidden[1]].rarity ~= "Common", "hidden stash holds rare+")
print(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
if fails > 0 then error("tests failed") end
