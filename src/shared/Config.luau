--!strict
-- Pizza Tycoon: central game balance configuration.
-- All tuning lives here. Server code reads this; never mutate at runtime.

export type Theme = {
	id: string,
	name: string,
	baseCost: number,
	baseColor: Color3,
	accentColor: Color3,
	position: Vector3, -- plot center, ground level
	facing: number, -- yaw in degrees
	maxExpansions: number,
}

export type Recipe = {
	id: string,
	name: string,
	price: number,
	unlockCost: number,
	ingredients: { [string]: number },
	color: Color3,
	toppingColor: Color3,
}

export type Shipment = {
	id: string,
	name: string,
	cost: number,
	delay: number, -- seconds until crates arrive
	items: { [string]: number },
}

local Config = {}

Config.StartingCash = 500
Config.AutosaveInterval = 120
Config.ProductionTick = 1 -- seconds, master simulation tick
Config.ReadyPizzaCap = 50

Config.IngredientColors = {
	flour = Color3.fromRGB(240, 230, 200),
	cheese = Color3.fromRGB(255, 200, 60),
	tomato = Color3.fromRGB(220, 60, 40),
	pepperoni = Color3.fromRGB(180, 60, 40),
	mushroom = Color3.fromRGB(180, 160, 130),
	pineapple = Color3.fromRGB(255, 230, 80),
}

Config.IngredientNames = {
	flour = "Flour",
	cheese = "Cheese",
	tomato = "Tomato",
	pepperoni = "Pepperoni",
	mushroom = "Mushroom",
	pineapple = "Pineapple",
}

Config.Shipments = {
	basic = {
		id = "basic", name = "Basic Supplies",
		cost = 60, delay = 12,
		items = { flour = 10, cheese = 6, tomato = 6 },
	},
	top = {
		id = "top", name = "Topping Supplies",
		cost = 110, delay = 20,
		items = { pepperoni = 10, mushroom = 8, pineapple = 6 },
	},
	bulk = {
		id = "bulk", name = "Bulk Shipment",
		cost = 260, delay = 35,
		items = { flour = 30, cheese = 20, tomato = 20, pepperoni = 10, mushroom = 8, pineapple = 6 },
	},
}

-- Recipes: what your ovens bake. Unlock better recipes to raise sale price.
Config.Recipes = {
	margherita = {
		id = "margherita", name = "Margherita",
		price = 12, unlockCost = 0,
		ingredients = { flour = 1, cheese = 1, tomato = 1 },
		color = Color3.fromRGB(235, 180, 90),
		toppingColor = Color3.fromRGB(220, 60, 40),
	},
	pepperoni = {
		id = "pepperoni", name = "Pepperoni",
		price = 18, unlockCost = 150,
		ingredients = { flour = 1, cheese = 1, tomato = 1, pepperoni = 1 },
		color = Color3.fromRGB(225, 160, 80),
		toppingColor = Color3.fromRGB(170, 50, 35),
	},
	veggie = {
		id = "veggie", name = "Veggie Feast",
		price = 22, unlockCost = 300,
		ingredients = { flour = 1, cheese = 1, tomato = 1, mushroom = 1 },
		color = Color3.fromRGB(225, 175, 95),
		toppingColor = Color3.fromRGB(160, 140, 110),
	},
	hawaiian = {
		id = "hawaiian", name = "Hawaiian",
		price = 26, unlockCost = 500,
		ingredients = { flour = 1, cheese = 1, tomato = 1, pineapple = 1 },
		color = Color3.fromRGB(230, 185, 100),
		toppingColor = Color3.fromRGB(255, 225, 80),
	},
	meatfeast = {
		id = "meatfeast", name = "Meat Feast",
		price = 34, unlockCost = 900,
		ingredients = { flour = 1, cheese = 2, tomato = 1, pepperoni = 2, mushroom = 1 },
		color = Color3.fromRGB(215, 150, 75),
		toppingColor = Color3.fromRGB(150, 45, 30),
	},
}
Config.DefaultRecipe = "margherita"

-- Upgrade tiers. Index = tier number. Tier 0 = not owned (ovens only).
Config.OvenTiers = {
	[1] = { name = "Stone Oven", cost = 100, pizzasPerMin = 2 },
	[2] = { name = "Deck Oven", cost = 400, pizzasPerMin = 5 },
	[3] = { name = "Conveyor Oven", cost = 1200, pizzasPerMin = 11 },
	[4] = { name = "Mega Smart Oven", cost = 3500, pizzasPerMin = 24 },
}

Config.WarehouseTiers = {
	[1] = { name = "Small Shed", cost = 0, capacity = 60 },
	[2] = { name = "Warehouse", cost = 250, capacity = 160 },
	[3] = { name = "Cold Storage", cost = 800, capacity = 400 },
	[4] = { name = "Silo Complex", cost = 2200, capacity = 1000 },
}

Config.MarketingTiers = {
	[1] = { name = "Word of Mouth", cost = 0, customerMult = 1, priceMult = 1 },
	[2] = { name = "Flyers", cost = 180, customerMult = 1.4, priceMult = 1.05 },
	[3] = { name = "Radio Spots", cost = 600, customerMult = 1.9, priceMult = 1.12 },
	[4] = { name = "TV Campaign", cost = 1800, customerMult = 2.6, priceMult = 1.25 },
}

Config.SecurityTiers = {
	[1] = { name = "No Security", cost = 0, theftChanceMult = 1 },
	[2] = { name = "Guard Dog", cost = 150, theftChanceMult = 0.5 },
	[3] = { name = "Night Guard", cost = 500, theftChanceMult = 0.2 },
	[4] = { name = "Laser Grid", cost = 1500, theftChanceMult = 0.02 },
}

Config.Staff = {
	chef = {
		name = "Chef", cost = 200, upkeepPerMin = 2, max = 4,
		speedMultPer = 0.35, -- production rate multiplier per chef
	},
	driver = {
		name = "Driver", cost = 150, upkeepPerMin = 1, max = 4,
		-- each driver lets one van shipment be in transit at a time
	},
}

-- Plot themes. Each player owns one plot in one theme.
Config.Plots = {
	{
		id = "alley", name = "Neapolitan Alley",
		baseCost = 250,
		baseColor = Color3.fromRGB(120, 80, 60),
		accentColor = Color3.fromRGB(230, 180, 100),
		position = Vector3.new(120, 0.5, 0),
		facing = -90,
		maxExpansions = 3,
	},
	{
		id = "neon", name = "Neon Slice Downtown",
		baseCost = 250,
		baseColor = Color3.fromRGB(50, 50, 70),
		accentColor = Color3.fromRGB(90, 220, 255),
		position = Vector3.new(0, 0.5, 130),
		facing = 180,
		maxExpansions = 3,
	},
	{
		id = "harbor", name = "Harborside Bazaar",
		baseCost = 250,
		baseColor = Color3.fromRGB(60, 100, 90),
		accentColor = Color3.fromRGB(255, 160, 60),
		position = Vector3.new(-120, 0.5, 0),
		facing = 90,
		maxExpansions = 3,
	},
}

Config.ExpansionCosts = { 400, 1200, 3000 }

-- Shared competitive delivery zones (world positions, payout pot per cycle).
Config.Zones = {
	{
		id = "downtown", name = "Downtown District",
		position = Vector3.new(0, 0.5, -60),
		color = Color3.fromRGB(255, 210, 80),
		demand = 400, -- pot per payout cycle (before events)
	},
	{
		id = "stadium", name = "Stadium Quarter",
		position = Vector3.new(60, 0.5, 60),
		color = Color3.fromRGB(120, 220, 120),
		demand = 650,
	},
	{
		id = "airport", name = "Airport Hub",
		position = Vector3.new(-60, 0.5, 60),
		color = Color3.fromRGB(140, 190, 255),
		demand = 1000,
	},
}

Config.ZonePayoutInterval = 60
Config.VanShipmentSize = 10 -- ready pizzas per van shipment
Config.VanTransitTime = 15

Config.Heist = {
	cost = 250, -- cost to send a heist crew at a rival
	stealAmount = 8, -- ingredient units stolen on success
	failPenalty = 150, -- paid to the victim when the heist fails
	baseSuccessChance = 0.6,
	securityPenaltyPerTier = 0.15,
}

Config.Theft = {
	baseChancePerMin = 0.25, -- chance roll each minute per warehouse
	stealAmount = 6,
}

Config.CustomerBaseRatePerMin = 6 -- customers per minute at marketing tier 1, full appeal

Config.Events = {
	rushhour = {
		id = "rushhour", name = "Rush Hour!",
		duration = 90,
		customerMult = 2.2,
		priceMult = 1,
		zoneMult = 1,
		theftMult = 1,
		announce = "Lunch rush! Customers are flooding the city.",
	},
	festival = {
		id = "festival", name = "Pizza Festival",
		duration = 120,
		customerMult = 1.4,
		priceMult = 1.25,
		zoneMult = 2,
		theftMult = 1,
		announce = "Pizza Festival! Zone payouts and prices are up.",
	},
	thiefhour = {
		id = "thiefhour", name = "Thief Hour",
		duration = 90,
		customerMult = 0.7,
		priceMult = 1,
		zoneMult = 1,
		theftMult = 3.5,
		announce = "Thief Hour! Watch your warehouses.",
	},
	boom = {
		id = "boom", name = "Economic Boom",
		duration = 120,
		customerMult = 1.3,
		priceMult = 1.5,
		zoneMult = 1.5,
		theftMult = 1,
		announce = "Economic boom! Everything sells at a premium.",
	},
}

Config.EventMinInterval = 150
Config.EventMaxInterval = 300

function Config.GetRecipe(id: string): Recipe?
	return Config.Recipes[id]
end

function Config.GetShipment(id: string): Shipment?
	return Config.Shipments[id]
end

return Config
