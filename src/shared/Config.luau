-- Central balance / tuning values shared by client and server.
local Config = {
	StartMoney = 150,
	MaxItems = 60,
	MaxVehicles = 3,
	SellFactor = 0.5, -- sell price = value * SellFactor
	BuyFactor = 1.6, -- shop price = value * BuyFactor (shop only stocks Common parts)
	FuelPrice = 1.5, -- per litre
	RepairPrice = 0.35, -- per hp
	TowCost = 25,
	TowCooldown = 45,
	ContainerRespawn = 15 * 60, -- seconds before a searched container can be looted again
	SearchRange = 14, -- studs from container to player (server re-checks with slack)
	ServiceRange = 40, -- studs from a service point (garage, depot...) for garage actions
	DiscoverRange = 55,
	VehicleStartFuelFraction = 0.4,
	AutosaveInterval = 60,
	RemoteRatePerSecond = 10,
}
return Config
