local Parts = require("./shared/Parts")
local VS = require("./shared/VehicleStats")

local fails = 0
local function check(cond, msg) if not cond then fails += 1; print("FAIL: " .. msg) end end

local starter = { Chassis="chassis_rust", Engine="eng_i4_junk", Transmission="trans_3sp", Wheels="wheels_bald", Suspension="susp_worn", Battery="batt_lead", FuelTank="tank_rust" }
local mid = { Chassis="chassis_steel", Engine="eng_v6", Transmission="trans_crawler", Wheels="wheels_at", Suspension="susp_leaf", Battery="batt_agm", FuelTank="tank_steel" }
local top = { Chassis="chassis_carbon", Engine="eng_v8_tt", Transmission="trans_dct", Wheels="wheels_at", Suspension="susp_air", Battery="batt_li", FuelTank="tank_avia", Armor="armor_ceramic" }
local bad = { Chassis="chassis_rust", Engine="eng_v8_tt", Transmission="trans_3sp", Wheels="wheels_bald", Suspension="susp_worn", Battery="batt_lead", FuelTank="tank_rust" }

for name, s in { starter=starter, mid=mid, top=top, bad=bad } do
	local r = VS.compute(s)
	print(string.format("%-8s complete=%s mass=%d power=%d accel=%.1f top=%.1f grip=%.2f brake=%.0f hp=%d fuel=%dL range=%.0f climb=%.1fdeg rough=%.2f tier=%s battLimited=%s",
		name, tostring(r.complete), r.mass, r.power, r.accel, r.topSpeed, r.grip, r.brake, r.durability, r.fuelCapacity, r.range, r.climbDeg, r.roughTerrain, VS.tierLabel(r.tierScore), tostring(r.batteryLimited)))
end

local a, b, c = VS.compute(starter), VS.compute(mid), VS.compute(top)
check(a.complete and b.complete and c.complete, "complete")
check(a.accel > 18 and a.accel < 30, "starter accel in 18..30")
check(b.accel > a.accel * 1.5, "mid much faster than starter")
check(c.accel > b.accel and c.topSpeed > b.topSpeed, "top beats mid")
check(c.topSpeed < 150, "top speed sane")
check(VS.compute(bad).batteryLimited, "weak battery limits big engine")
check(VS.compute(bad).power == 110, "battery caps power")
check(#VS.compute({ Engine="eng_v6" }).missing == 6, "missing slots counted")
check(not VS.compute({ Engine="eng_v6" }).complete, "incomplete")
-- tyres: AT tyres keep more grip on dirt than slicks
check(VS.surfaceGripFactor(0.95, 0.4, 0.5) > VS.surfaceGripFactor(0, 0.4, 0.5), "AT beats slicks on dirt")
check(VS.surfaceGripFactor(0.95, 1, 0) == 1, "full grip on asphalt")
-- trade-off: slicks best on road
local slick = VS.compute({ Chassis="chassis_rust", Engine="eng_i4_junk", Transmission="trans_3sp", Wheels="wheels_slick", Suspension="susp_worn", Battery="batt_lead", FuelTank="tank_rust" })
check(slick.brake > a.brake and slick.roughTerrain < VS.compute({ Chassis="chassis_rust", Engine="eng_i4_junk", Transmission="trans_3sp", Wheels="wheels_at", Suspension="susp_worn", Battery="batt_lead", FuelTank="tank_rust" }).roughTerrain, "slicks: brake up, rough terrain down")
-- engine fuel trade-off
check(VS.compute({ Chassis="chassis_rust", Engine="eng_v8", Transmission="trans_3sp", Wheels="wheels_bald", Suspension="susp_worn", Battery="batt_hd", FuelTank="tank_rust" }).range < a.range, "V8 shorter range than I4 on same tank")
-- every part valid
for _, p in Parts.List do check(Parts.ById[p.id] == p and Parts.Required[p.slot] ~= nil or p.slot == "Armor", "part " .. p.id) end
print(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
if fails > 0 then error("tests failed") end
