--!strict
-- Pizza Tycoon: central game balance configuration.
-- All tuning lives here. Server code reads this; never mutate at runtime.

export type District = {
	id: string,
	name: string,
	tagline: string,
	rect: { x0: number, x1: number, z0: number, z1: number },
	mapColor: Color3,
	groundColor: Color3,
	costMult: number,
	customerMult: number,
	priceMult: number,
	zoneDemand: number,
	theftMult: number,
	pedMult: number,
	carMult: number,
	style: string,
	zone: Vector3, -- delivery zone pad position
	plaza: Vector3, -- teleport / gathering spot
}

export type Theme = {
	id: string,
	name: string,
	district: string, -- district id this plot lives in
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

-- ============================= City =============================

-- The open world: roads along the given center lines (x = north-south
-- roads, z = east-west roads), districts filling the blocks between them.
Config.City = {
	WorldHalf = 230,
	RoadHalf = 10,
	SidewalkWidth = 4,
	RoadsX = { -220, 0, 110, 220 },
	RoadsZ = { -220, 0, 220 },
	Traffic = {
		Period = 480, -- seconds for a full quiet -> busy -> quiet wave
		MinLevel = 0.2,
		MaxCars = 22,
		CarSpeed = 24, -- studs/sec
		LaneOffset = 5, -- right-hand lane offset from road center line
		SpawnRadius = 170,
		DespawnRadius = 210,
		UpdateHz = 12, -- NPC position replication rate
	},
	Peds = {
		MaxPeds = 26,
		WalkSpeed = 7,
		IdleChance = 0.2, -- chance per waypoint to pause briefly
		SpawnRadius = 130,
		DespawnRadius = 170,
	},
}

-- Districts: each is a themed city block with gameplay traits. One
-- buyable restaurant plot and one shared delivery zone live in each.
Config.City.Districts = {
	downtown = {
		id = "downtown", name = "Skyline Heights",
		tagline = "Glass towers, suits and deep pockets.",
		rect = { x0 = -220, x1 = 0, z0 = -220, z1 = 0 },
		mapColor = Color3.fromRGB(115, 155, 225),
		groundColor = Color3.fromRGB(110, 110, 122),
		costMult = 2.2, customerMult = 0.9, priceMult = 1.5,
		zoneDemand = 900, theftMult = 0.8,
		pedMult = 1.0, carMult = 1.4,
		style = "downtown",
		zone = Vector3.new(-160, 0.5, -160),
		plaza = Vector3.new(-160, 0.5, -130),
	},
	oldtown = {
		id = "oldtown", name = "Trattoria Quarter",
		tagline = "Cobbled streets, brick facades, old-world charm.",
		rect = { x0 = 0, x1 = 220, z0 = -220, z1 = 0 },
		mapColor = Color3.fromRGB(200, 130, 95),
		groundColor = Color3.fromRGB(125, 105, 90),
		costMult = 1.4, customerMult = 1.1, priceMult = 1.2,
		zoneDemand = 650, theftMult = 1.0,
		pedMult = 1.2, carMult = 0.8,
		style = "oldtown",
		zone = Vector3.new(160, 0.5, -160),
		plaza = Vector3.new(160, 0.5, -130),
	},
	suburbs = {
		id = "suburbs", name = "Maple Suburbs",
		tagline = "Quiet streets, lawns and hungry families.",
		rect = { x0 = -220, x1 = 0, z0 = 0, z1 = 220 },
		mapColor = Color3.fromRGB(130, 190, 120),
		groundColor = Color3.fromRGB(95, 140, 85),
		costMult = 1.0, customerMult = 1.0, priceMult = 1.0,
		zoneDemand = 500, theftMult = 0.7,
		pedMult = 0.9, carMult = 0.9,
		style = "suburbs",
		zone = Vector3.new(-160, 0.5, 160),
		plaza = Vector3.new(-160, 0.5, 130),
	},
	industrial = {
		id = "industrial", name = "Foundry Flats",
		tagline = "Cheap rents, hard workers, sticky fingers.",
		rect = { x0 = 0, x1 = 110, z0 = 0, z1 = 220 },
		mapColor = Color3.fromRGB(150, 145, 135),
		groundColor = Color3.fromRGB(105, 100, 95),
		costMult = 0.7, customerMult = 1.25, priceMult = 0.8,
		zoneDemand = 400, theftMult = 1.8,
		pedMult = 0.7, carMult = 0.6,
		style = "industrial",
		zone = Vector3.new(55, 0.5, 160),
		plaza = Vector3.new(55, 0.5, 130),
	},
	waterfront = {
		id = "waterfront", name = "Marina Bay",
		tagline = "Sea breeze, tourists and long lines.",
		rect = { x0 = 110, x1 = 220, z0 = 0, z1 = 220 },
		mapColor = Color3.fromRGB(110, 205, 205),
		groundColor = Color3.fromRGB(215, 195, 150),
		costMult = 1.7, customerMult = 1.3, priceMult = 1.35,
		zoneDemand = 800, theftMult = 1.0,
		pedMult = 1.1, carMult = 0.8,
		style = "waterfront",
		zone = Vector3.new(165, 0.5, 160),
		plaza = Vector3.new(165, 0.5, 130),
	},
}

function Config.GetDistrict(id: string): District?
	return Config.City.Districts[id]
end

-- Plot themes: one restaurant plot per district.
Config.Plots = {
	{
		id = "neon", name = "Neon Slice",
		district = "downtown",
		baseCost = 550,
		baseColor = Color3.fromRGB(70, 72, 92),
		accentColor = Color3.fromRGB(90, 220, 255),
		position = Vector3.new(-120, 0.5, -60),
		facing = 180,
		maxExpansions = 3,
	},
	{
		id = "nonna", name = "Nonna's Trattoria",
		district = "oldtown",
		baseCost = 350,
		baseColor = Color3.fromRGB(140, 105, 85),
		accentColor = Color3.fromRGB(235, 120, 70),
		position = Vector3.new(120, 0.5, -60),
		facing = 180,
		maxExpansions = 3,
	},
	{
		id = "family", name = "Family Slice",
		district = "suburbs",
		baseCost = 250,
		baseColor = Color3.fromRGB(100, 110, 90),
		accentColor = Color3.fromRGB(120, 220, 110),
		position = Vector3.new(-120, 0.5, 60),
		facing = 0,
		maxExpansions = 3,
	},
	{
		id = "steel", name = "Steel Crust",
		district = "industrial",
		baseCost = 175,
		baseColor = Color3.fromRGB(85, 85, 88),
		accentColor = Color3.fromRGB(255, 150, 50),
		position = Vector3.new(55, 0.5, 60),
		facing = 0,
		maxExpansions = 3,
	},
	{
		id = "surf", name = "Surf & Slice",
		district = "waterfront",
		baseCost = 425,
		baseColor = Color3.fromRGB(200, 180, 140),
		accentColor = Color3.fromRGB(60, 220, 215),
		position = Vector3.new(165, 0.5, 60),
		facing = 0,
		maxExpansions = 3,
	},
}

Config.ExpansionCosts = { 400, 1200, 3000 }

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
		carMult = 1.6,
		pedMult = 1.5,
		announce = "Lunch rush! Customers are flooding the city.",
	},
	festival = {
		id = "festival", name = "Pizza Festival",
		duration = 120,
		customerMult = 1.4,
		priceMult = 1.25,
		zoneMult = 2,
		theftMult = 1,
		carMult = 1.1,
		pedMult = 1.6,
		announce = "Pizza Festival! Zone payouts and prices are up.",
	},
	thiefhour = {
		id = "thiefhour", name = "Thief Hour",
		duration = 90,
		customerMult = 0.7,
		priceMult = 1,
		zoneMult = 1,
		theftMult = 3.5,
		carMult = 0.6,
		pedMult = 0.5,
		announce = "Thief Hour! Watch your warehouses.",
	},
	boom = {
		id = "boom", name = "Economic Boom",
		duration = 120,
		customerMult = 1.3,
		priceMult = 1.5,
		zoneMult = 1.5,
		theftMult = 1,
		carMult = 1.2,
		pedMult = 1.1,
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
