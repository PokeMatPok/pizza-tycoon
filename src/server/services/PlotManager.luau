--!strict
-- PlotManager: builds the district lots, owns all ProximityPrompt-driven
-- interactions (buy shipments, upgrades, staff, recipes, expansions,
-- heists), keeps prompt labels/signs in sync with player data, and
-- handles claim/release lifecycle. The restaurant is a real low-poly
-- building (hall, storefront, awning, rooftop sign) built on claim.

local Players = game:GetService("Players")

local PlotManager = {}

local Config, Net
local Economy, DataManager, ModelFactory, CityMap

export type PlotState = {
	theme: any,
	owner: Player?,
	model: Model,
	platform: Part,
	building: Model?,
	counter: Model,
	oven: Model,
	warehouse: Part,
	vanPad: Part,
	expansionPads: { Part },
	signs: { [string]: TextLabel },
	prompts: { [string]: ProximityPrompt },
}

local plots: { { state: PlotState } } = {}
local playerPlots: { [Player]: PlotState } = {}

local function yawCf(theme): CFrame
	return CFrame.new(theme.position) * CFrame.Angles(0, math.rad(theme.facing), 0)
end

-- Convert a local offset into world space for a theme.
local function toWorld(theme, offset: Vector3, y: number?): CFrame
	return yawCf(theme) * CFrame.new(offset.X, y or offset.Y, offset.Z)
end

-- Lot layout (local space; front/street is -Z, lot center is 0,0).
-- Real scale: the platform is 84x114 studs; the restaurant hall
-- (W64 x D44, 18-stud walls) occupies z -50..-6, the work yard z 8..54.
-- Y = 1.3 is the walking surface (platform top = 1.25).
local STREET = Vector3.new(0, 1.3, -58)
local COUNTER = Vector3.new(0, 1.3, -42)
local OVEN = Vector3.new(-20, 1.3, -18)
local WAREHOUSE = Vector3.new(20, 1.3, -18)
local VAN_PAD = Vector3.new(0, 1.3, 26)
local DOOR = Vector3.new(0, 1.3, -47)
local EXPANSION_OFFSETS = {
	Vector3.new(-28, 1.3, 30),
	Vector3.new(28, 1.3, 30),
	Vector3.new(0, 1.3, 44),
}

local function localCf(theme, offset: Vector3): CFrame
	return toWorld(theme, offset)
end

-- Build the static (unclaimed) lot: platform + FOR SALE sign + claim prompt.
local function buildBasePlot(theme, parent): PlotState
	local model = Instance.new("Model")
	model.Name = "Plot_" .. theme.id

	local platform = ModelFactory.basePart({
		Name = "Platform",
		Size = Vector3.new(84, 0.5, 114),
		Color = Color3.fromRGB(120, 120, 124),
		Material = Enum.Material.Concrete,
		CFrame = yawCf(theme) * CFrame.new(0, 1.0, -3),
		Parent = model,
	})
	-- Pale stripe marking the building footprint on the empty lot.
	ModelFactory.basePart({
		Name = "Footprint",
		Size = Vector3.new(66, 0.1, 46),
		Color = theme.baseColor,
		Material = Enum.Material.Concrete,
		CanCollide = false,
		CFrame = yawCf(theme) * CFrame.new(0, 1.3, -28),
		Parent = model,
	})

	local state: PlotState = {
		theme = theme,
		owner = nil,
		model = model,
		platform = platform,
		building = nil,
		counter = nil :: any,
		oven = nil :: any,
		warehouse = nil :: any,
		vanPad = nil :: any,
		expansionPads = {},
		signs = {},
		prompts = {},
	}

	-- FOR SALE sign + claim prompt at the street edge.
	local signPart, signText = ModelFactory.infoSign(model, toWorld(theme, STREET, 4))
	local district = Config.City.Districts[theme.district]
	signText.Text = ("%s\nFOR SALE: $%d\n(%s)"):format(theme.name, theme.baseCost, district.name)
	state.signs.theme = signText

	local claimPrompt = ModelFactory.prompt(
		signPart,
		("Buy Restaurant ($%d)"):format(theme.baseCost),
		theme.name,
		1
	)
	claimPrompt.Triggered:Connect(function(player)
		PlotManager.Claim(player, state)
	end)
	state.prompts.claim = claimPrompt

	model.Parent = parent
	return state
end

-- Build the owned restaurant on a claimed lot.
local function buildShop(state: PlotState, parent)
	local theme = state.theme
	local model = state.model

	-- The restaurant building hall: front faces the street (-Z).
	-- Built at foundation level 1.0 so the floor surface = platform top +0.05.
	state.building = ModelFactory.restaurantBuilding(theme.accentColor, theme.baseColor, theme.name, model, toWorld(theme, Vector3.new(0, 1.0, -28)))

	-- Street-facing counter just inside the storefront (top at y 5.4).
	state.counter = ModelFactory.counter(theme.accentColor, model, toWorld(theme, COUNTER, 5.4))

	-- Ready pizza stock sign at the counter.
	local _, stockSign = ModelFactory.infoSign(model, toWorld(theme, Vector3.new(9, 0, -40), 7))
	state.signs.stock = stockSign

	-- Oven inside the west wing.
	state.oven = ModelFactory.oven(theme.accentColor, model, localCf(theme, OVEN))
	local _, ovenSign = ModelFactory.infoSign(model, toWorld(theme, OVEN + Vector3.new(0, 0, 5), 8.5))
	state.signs.oven = ovenSign

	-- Warehouse: storage pad where crates land (east wing interior).
	state.warehouse = ModelFactory.basePart({
		Name = "Warehouse",
		Size = Vector3.new(16, 0.4, 16),
		Color = Color3.fromRGB(70, 55, 40),
		Material = Enum.Material.WoodPlanks,
		CFrame = localCf(theme, WAREHOUSE),
		Parent = model,
	})
	local _, whSign = ModelFactory.infoSign(model, toWorld(theme, WAREHOUSE + Vector3.new(0, 0, 7), 5), Vector2.new(300, 90))
	state.signs.warehouse = whSign

	-- Van pad: where the delivery van parks between runs.
	state.vanPad = ModelFactory.basePart({
		Name = "VanPad",
		Size = Vector3.new(18, 0.4, 12),
		Color = Color3.fromRGB(50, 50, 55),
		Material = Enum.Material.Concrete,
		CFrame = localCf(theme, VAN_PAD),
		Parent = model,
	})
	local _, vanSign = ModelFactory.infoSign(model, toWorld(theme, VAN_PAD + Vector3.new(0, 0, -8), 4))
	state.signs.van = vanSign

	-- Expansion pads around the work yard.
	for i, offset in EXPANSION_OFFSETS do
		local pad = ModelFactory.basePart({
			Name = "ExpansionPad" .. i,
			Size = Vector3.new(18, 0.4, 18),
			Color = Color3.fromRGB(60, 60, 60),
			Material = Enum.Material.Slate,
			CFrame = localCf(theme, offset),
			Parent = model,
		})
		table.insert(state.expansionPads, pad)
	end

	-- Patio seating in front of the storefront, under the awning.
	for _, side in { -1, 1 } do
		local spot = toWorld(theme, STREET + Vector3.new(side * 14, 0, 3), 1.3)
		ModelFactory.tableSet(model, spot, theme.accentColor)
		ModelFactory.umbrella(model, spot, theme.accentColor)
	end

	PlotManager.WireInteractions(state)
end

-- All per-plot purchase prompts. Labels are refreshed by Refresh.
function PlotManager.WireInteractions(state: PlotState)
	local function ownedPrompt(name: string, part: BasePart, action: string, object: string, handler)
		local prompt = ModelFactory.prompt(part, action, object, 0.35)
		prompt.Triggered:Connect(function(player)
			if player ~= state.owner then
				return
			end
			local ok, err = pcall(handler, player)
			if not ok then
				warn("[PizzaTycoon] prompt handler error: " .. tostring(err))
			end
		end)
		state.prompts[name] = prompt
		return prompt
	end

	-- Shipments (three tiers) at the warehouse.
	for id, shipment in Config.Shipments do
		ownedPrompt("shipment_" .. id, state.warehouse, shipment.name .. " ($" .. shipment.cost .. ")", "Order Shipment", function(player)
			PlotManager.OrderShipment(player, state, id)
		end)
	end

	-- Upgrades.
	ownedPrompt("upgrade_oven", state.oven.PrimaryPart :: BasePart, "Upgrade Oven", "Oven", function(player)
		PlotManager.Upgrade(player, state, "oven")
	end)
	ownedPrompt("upgrade_warehouse", state.warehouse, "Upgrade Warehouse", "Warehouse", function(player)
		PlotManager.Upgrade(player, state, "warehouse")
	end)
	ownedPrompt("upgrade_marketing", state.counter.PrimaryPart :: BasePart, "Upgrade Marketing", "Marketing", function(player)
		PlotManager.Upgrade(player, state, "marketing")
	end)
	ownedPrompt("upgrade_security", state.warehouse, "Upgrade Security", "Security", function(player)
		PlotManager.Upgrade(player, state, "security")
	end)

	-- Staff.
	ownedPrompt("hire_chef", state.oven.PrimaryPart :: BasePart, "Hire Chef", "Staff", function(player)
		PlotManager.Hire(player, state, "chef")
	end)
	ownedPrompt("hire_driver", state.vanPad, "Hire Driver", "Staff", function(player)
		PlotManager.Hire(player, state, "driver")
	end)

	-- Recipes: unlock prompt + cycle active recipe prompt.
	ownedPrompt("recipes_board", state.counter.PrimaryPart :: BasePart, "Switch Recipe", "Recipe Board", function(player)
		PlotManager.CycleRecipe(player, state)
	end)
	for id, recipe in Config.Recipes do
		local prompt = ownedPrompt("unlock_" .. id, state.counter.PrimaryPart :: BasePart, ("Unlock %s"):format(recipe.name), "Recipes", function(player)
			PlotManager.UnlockRecipe(player, state, id)
		end)
		prompt.ObjectText = "Recipes"
		prompt.ActionText = ("Unlock %s ($%d)"):format(recipe.name, recipe.unlockCost)
	end

	-- Expansions.
	for i, pad in state.expansionPads do
		ownedPrompt("expand_" .. i, pad, "Expand Plot", "Expansion", function(player)
			PlotManager.Expand(player, state)
		end)
	end

	-- Heist prompt at the warehouse: usable by NON-owners against this plot.
	local heistPrompt = ModelFactory.prompt(state.warehouse, "Send Heist Crew", "Sabotage", 1)
	heistPrompt.Triggered:Connect(function(player)
		if player == state.owner then
			return
		end
		PlotManager.Heist(player, state)
	end)
	state.prompts.heist = heistPrompt
end

-- ============================= Actions =============================

local function themeColor(state: PlotState): Color3
	return state.theme.accentColor
end

function PlotManager.Claim(player: Player, state: PlotState)
	if state.owner ~= nil then
		return
	end
	if playerPlots[player] then
		return -- one plot per player
	end
	if not Economy.Spend(player, state.theme.baseCost, "plot:" .. state.theme.id) then
		return
	end
	state.owner = player
	playerPlots[player] = state
	DataManager.Mutate(player, function(data)
		data.themeId = state.theme.id
	end)
	buildShop(state, state.model.Parent)
	-- Hide the claim prompt once owned.
	local claimPrompt = state.prompts.claim :: ProximityPrompt
	claimPrompt.Enabled = false
	local district = Config.City.Districts[state.theme.district]
	Net.Announce:FireClient(player, ("Welcome to %s in %s!"):format(state.theme.name, district.name), themeColor(state))
	PlotManager.Refresh(player, state)
end

function PlotManager.OrderShipment(player: Player, state: PlotState, shipmentId: string)
	local shipment = Config.Shipments[shipmentId]
	if not shipment or state.owner ~= player then
		return
	end
	local data = DataManager.Get(player)
	if not data then
		return
	end
	-- Capacity check against warehouse tier.
	local capacity = Config.WarehouseTiers[data.upgrades.warehouse].capacity
	local current = 0
	for _, n in data.ingredients do
		current += n
	end
	local incoming = 0
	for _, n in shipment.items do
		incoming += n
	end
	if current + incoming > capacity then
		Net.Announce:FireClient(player, "Warehouse too full for that shipment! Upgrade it.", Color3.fromRGB(255, 100, 100))
		return
	end
	if not Economy.Spend(player, shipment.cost, "shipment:" .. shipmentId) then
		return
	end
	task.delay(shipment.delay, function()
		if state.owner ~= player then
			return -- owner left; shipment was time-limited
		end
		PlotManager.DeliverShipment(player, state, shipment)
	end)
end

function PlotManager.DeliverShipment(player: Player, state: PlotState, shipment)
	local data = DataManager.Get(player)
	if not data or state.owner ~= player then
		return
	end
	-- Visual: crates land on the warehouse pad, then are removed.
	local theme = state.theme
	local crateModel = ModelFactory.crate(
		Config.IngredientColors.flour,
		shipment.name,
		state.model,
		toWorld(theme, WAREHOUSE, 30)
	)
	ModelFactory.tweenModel(
		crateModel,
		toWorld(theme, WAREHOUSE, 3.0),
		1.2
	)
	task.delay(3, function()
		if crateModel and crateModel.Parent then
			crateModel:Destroy()
		end
	end)
	DataManager.Mutate(player, function(d)
		-- Clamp to current warehouse capacity in case it changed mid-transit.
		local capacity = Config.WarehouseTiers[d.upgrades.warehouse].capacity
		local currentTotal = 0
		for _, n in d.ingredients do
			currentTotal += n
		end
		for ing, n in shipment.items do
			local room = capacity - currentTotal
			if room <= 0 then
				break
			end
			local added = math.min(room, n)
			d.ingredients[ing] = (d.ingredients[ing] or 0) + added
			currentTotal += added
		end
	end)
	Net.Announce:FireClient(player, shipment.name .. " delivered!", themeColor(state))
	PlotManager.Refresh(player, state)
end

function PlotManager.Upgrade(player: Player, state: PlotState, kind: string)
	local tiers = if kind == "oven" then Config.OvenTiers
		elseif kind == "warehouse" then Config.WarehouseTiers
		elseif kind == "marketing" then Config.MarketingTiers
		else Config.SecurityTiers
	local data = DataManager.Get(player)
	if not data or state.owner ~= player then
		return
	end
	local current = (data.upgrades :: any)[kind]
	local nextTier = tiers[current + 1]
	if not nextTier then
		Net.Announce:FireClient(player, "Already at max tier!", Color3.fromRGB(255, 200, 100))
		return
	end
	if not Economy.Spend(player, nextTier.cost, "upgrade:" .. kind .. ":" .. current + 1) then
		return
	end
	DataManager.Mutate(player, function(d)
		(d.upgrades :: any)[kind] = current + 1
	end)
	if kind == "oven" then
		-- Rebuild oven visual with fancier glow. Build the NEW oven first and
		-- move the prompts over, because destroying the old oven would lock
		-- the prompts' Parent (they'd be destroyed with it) and re-parenting
		-- a destroyed prompt throws. The oven builder takes a GROUND frame.
		local cf = localCf(state.theme, OVEN)
		local oldOven = state.oven
		state.oven = ModelFactory.oven(themeColor(state), state.model, cf)
		state.prompts.upgrade_oven.Parent = state.oven.PrimaryPart
		state.prompts.hire_chef.Parent = state.oven.PrimaryPart
		oldOven:Destroy()
	end
	Net.Announce:FireClient(player, nextTier.name .. " installed!", themeColor(state))
	PlotManager.Refresh(player, state)
end

function PlotManager.Hire(player: Player, state: PlotState, kind: string)
	local def = Config.Staff[kind]
	local data = DataManager.Get(player)
	if not data or state.owner ~= player then
		return
	end
	if (data.staff :: any)[kind] >= def.max then
		Net.Announce:FireClient(player, "Max " .. def.name .. "s hired!", Color3.fromRGB(255, 200, 100))
		return
	end
	if not Economy.Spend(player, def.cost, "hire:" .. kind) then
		return
	end
	DataManager.Mutate(player, function(d)
		(d.staff :: any)[kind] += 1
	end)
	Net.Announce:FireClient(player, def.name .. " hired!", themeColor(state))
	PlotManager.Refresh(player, state)
end

function PlotManager.UnlockRecipe(player: Player, state: PlotState, recipeId: string)
	local recipe = Config.Recipes[recipeId]
	local data = DataManager.Get(player)
	if not recipe or not data or state.owner ~= player then
		return
	end
	if table.find(data.unlockedRecipes, recipeId) then
		return
	end
	if not Economy.Spend(player, recipe.unlockCost, "recipe:" .. recipeId) then
		return
	end
	DataManager.Mutate(player, function(d)
		table.insert(d.unlockedRecipes, recipeId)
		d.activeRecipe = recipeId
	end)
	Net.Announce:FireClient(player, recipe.name .. " recipe unlocked and set active!", themeColor(state))
	PlotManager.Refresh(player, state)
end

function PlotManager.CycleRecipe(player: Player, state: PlotState)
	local data = DataManager.Get(player)
	if not data or state.owner ~= player then
		return
	end
	local unlocked = data.unlockedRecipes
	if #unlocked < 2 then
		return
	end
	local index = table.find(unlocked, data.activeRecipe) or 1
	local nextId = unlocked[(index % #unlocked) + 1]
	DataManager.Mutate(player, function(d)
		d.activeRecipe = nextId
	end)
	Net.Announce:FireClient(player, "Now baking: " .. Config.Recipes[nextId].name, themeColor(state))
	PlotManager.Refresh(player, state)
end

function PlotManager.Expand(player: Player, state: PlotState)
	local data = DataManager.Get(player)
	if not data or state.owner ~= player then
		return
	end
	if data.expansions >= state.theme.maxExpansions then
		return
	end
	local cost = Config.ExpansionCosts[data.expansions + 1]
	if not Economy.Spend(player, cost, "expand:" .. data.expansions + 1) then
		return
	end
	local padIndex = data.expansions + 1
	local pad = state.expansionPads[padIndex]
	DataManager.Mutate(player, function(d)
		d.expansions += 1
	end)
	if pad then
		pad.Color = state.theme.baseColor
		pad.Material = Enum.Material.Concrete
		ModelFactory.basePart({
			Name = "ExpansionDecor",
			Size = Vector3.new(4, 6, 4),
			Color = state.theme.accentColor,
			Material = Enum.Material.Neon,
			CFrame = pad.CFrame * CFrame.new(5, 3, 5),
			Parent = state.model,
		})
		local prompt = state.prompts["expand_" .. padIndex]
		if prompt then
			prompt.Enabled = false
		end
	end
	Net.Announce:FireClient(player, "Plot expanded! +15% oven speed, +10% customers.", themeColor(state))
	PlotManager.Refresh(player, state)
end

function PlotManager.Heist(player: Player, state: PlotState)
	local victim = state.owner
	if not victim or victim == player then
		return
	end
	local victimData = DataManager.Get(victim)
	local thiefData = DataManager.Get(player)
	if not victimData or not thiefData then
		return
	end
	local def = Config.Heist
	if not Economy.Spend(player, def.cost, "heist") then
		return
	end
	local successChance = math.max(
		0.1,
		def.baseSuccessChance - (victimData.upgrades.security - 1) * def.securityPenaltyPerTier
	)
	local theme = state.theme
	-- The crew walks in through the storefront, then to the warehouse.
	-- Pedestrian builders take GROUND frames; walk paths use PIVOT
	-- frames (ground + 3 studs, torso height of the R6 avatar).
	local spy = ModelFactory.customer(Color3.fromRGB(40, 40, 45), state.model, toWorld(theme, STREET))
	spy.Name = "HeistCrew"
	ModelFactory.walkPath(spy, {
		PlotManager.PedWorld(state, DOOR),
		PlotManager.PedWorld(state, WAREHOUSE),
	}, 9)
	task.delay(6, function()
		if spy and spy.Parent then
			-- Flee back out through the door.
			ModelFactory.walkPath(spy, {
				PlotManager.PedWorld(state, DOOR),
				PlotManager.PedWorld(state, STREET),
			}, 14)
			task.delay(4, function()
				if spy and spy.Parent then
					spy:Destroy()
				end
			end)
		end
		local victimStillHere = state.owner == victim and victim.Parent ~= nil
		if not victimStillHere then
			return
		end
		if math.random() < successChance then
			local stolen = {}
			DataManager.Mutate(victim, function(d)
				local pool = {}
				for ing, n in d.ingredients do
					if n > 0 then
						table.insert(pool, ing)
					end
				end
				if #pool > 0 then
					local ing = pool[math.random(#pool)]
					local amount = math.min(d.ingredients[ing], def.stealAmount)
					d.ingredients[ing] -= amount
					table.insert(stolen, { ing = ing, amount = amount })
				end
			end)
			if #stolen > 0 then
				local s = stolen[1]
				Net.Announce:FireClient(player, ("Heist succeeded! Stole %d %s from %s."):format(s.amount, Config.IngredientNames[s.ing], victim.Name), Color3.fromRGB(120, 255, 120))
				Net.Announce:FireClient(victim, ("%s stole %d %s from your warehouse!"):format(player.Name, s.amount, Config.IngredientNames[s.ing]), Color3.fromRGB(255, 90, 90))
				PlotManager.Refresh(victim, state)
			else
				Net.Announce:FireClient(player, "Heist crew found an empty warehouse.", Color3.fromRGB(255, 200, 100))
			end
		else
			-- Failed: pay the victim a penalty.
			Economy.Transact(victim, def.failPenalty, "heist_fail_compensation")
			Net.Announce:FireClient(player, "Heist failed! Security caught your crew.", Color3.fromRGB(255, 90, 90))
			Net.Announce:FireClient(victim, ("%s tried to rob you and paid you $%d!"):format(player.Name, def.failPenalty), Color3.fromRGB(120, 255, 120))
		end
	end)
end

-- ========================== Sync & refresh ==========================

-- Refresh all prompt labels and signs to match the owner's data.
function PlotManager.Refresh(player: Player, state: PlotState)
	if state.owner ~= player then
		return
	end
	local data = DataManager.Get(player)
	if not data then
		return
	end
	local theme = state.theme
	local P = state.prompts

	-- Shipments.
	for id, shipment in Config.Shipments do
		local prompt = P["shipment_" .. id]
		if prompt then
			prompt.ActionText = ("%s ($%d, %ds)"):format(shipment.name, shipment.cost, shipment.delay)
		end
	end

	-- Upgrades: label shows next tier + cost, or maxed.
	local function upgradeLabel(kind, tiers)
		local prompt = P["upgrade_" .. kind]
		if not prompt then
			return
		end
		local current = (data.upgrades :: any)[kind]
		local nextTier = tiers[current + 1]
		if nextTier then
			prompt.ActionText = ("%s -> %s ($%d)"):format(kind:gsub("^%l", string.upper), nextTier.name, nextTier.cost)
			prompt.Enabled = true
		else
			prompt.ActionText = kind:gsub("^%l", string.upper) .. " MAX"
			prompt.Enabled = false
		end
	end
	upgradeLabel("oven", Config.OvenTiers)
	upgradeLabel("warehouse", Config.WarehouseTiers)
	upgradeLabel("marketing", Config.MarketingTiers)
	upgradeLabel("security", Config.SecurityTiers)

	-- Staff.
	local chefPrompt = P.hire_chef
	if chefPrompt then
		local def = Config.Staff.chef
		if data.staff.chef >= def.max then
			chefPrompt.ActionText = "Chefs MAX"
			chefPrompt.Enabled = false
		else
			chefPrompt.ActionText = ("Hire Chef ($%d) [%d/%d]"):format(def.cost, data.staff.chef, def.max)
			chefPrompt.Enabled = true
		end
	end
	local driverPrompt = P.hire_driver
	if driverPrompt then
		local def = Config.Staff.driver
		if data.staff.driver >= def.max then
			driverPrompt.ActionText = "Drivers MAX"
			driverPrompt.Enabled = false
		else
			driverPrompt.ActionText = ("Hire Driver ($%d) [%d/%d]"):format(def.cost, data.staff.driver, def.max)
			driverPrompt.Enabled = true
		end
	end

	-- Recipes.
	local boardPrompt = P.recipes_board
	if boardPrompt then
		if #data.unlockedRecipes > 1 then
			boardPrompt.ActionText = "Bake: " .. Config.Recipes[data.activeRecipe].name .. " (switch)"
			boardPrompt.Enabled = true
		else
			boardPrompt.ActionText = "Only Margherita unlocked"
			boardPrompt.Enabled = false
		end
	end
	for id, recipe in Config.Recipes do
		local prompt = P["unlock_" .. id]
		if prompt then
			if table.find(data.unlockedRecipes, id) then
				prompt.Enabled = false
			else
				prompt.ActionText = ("Unlock %s ($%d)"):format(recipe.name, recipe.unlockCost)
				prompt.Enabled = true
			end
		end
	end

	-- Expansions.
	for i in state.expansionPads do
		local prompt = P["expand_" .. i]
		if prompt then
			if data.expansions >= i then
				prompt.Enabled = false
			else
				local cost = Config.ExpansionCosts[data.expansions + 1]
				prompt.ActionText = ("Expand Plot ($%d)"):format(cost)
				prompt.Enabled = data.expansions == i - 1
			end
		end
	end

	-- Heist prompt is for rivals: visible while the plot is owned.
	if P.heist then
		(P.heist :: ProximityPrompt).Enabled = state.owner ~= nil
	end

	-- Signs.
	local district = Config.City.Districts[theme.district]
	local capacity = Config.WarehouseTiers[data.upgrades.warehouse].capacity
	local current = 0
	for _, n in data.ingredients do
		current += n
	end
	state.signs.warehouse.Text = ("%s: %d/%d\nChefs: %d  Drivers: %d  Security: %s"):format(
		"Warehouse", current, capacity, data.staff.chef, data.staff.driver,
		Config.SecurityTiers[data.upgrades.security].name
	)
	state.signs.stock.Text = ("Ready: %d pizzas\nBaking: %s"):format(data.readyPizzas, Config.Recipes[data.activeRecipe].name)
	local ovenTier = Config.OvenTiers[data.upgrades.oven]
	state.signs.oven.Text = ovenTier
		and ("Oven: %s\nMarketing: %s"):format(ovenTier.name, Config.MarketingTiers[data.upgrades.marketing].name)
		or "No oven yet!"
	state.signs.van.Text = ("Van ready: %d pizzas\nDeliver to %s!"):format(data.readyPizzas, district.name)
	state.signs.theme.Text = ("%s\nOwner: %s"):format(theme.name, player.Name)
end

function PlotManager.GetPlot(player: Player): PlotState?
	return playerPlots[player]
end

function PlotManager.GetPlotByTheme(themeId: string): PlotState?
	for _, entry in plots do
		if entry.state.theme.id == themeId then
			return entry.state
		end
	end
	return nil
end

function PlotManager.LocalToWorld(state: PlotState, offset: Vector3): CFrame
	return toWorld(state.theme, offset)
end

-- Pivot CFrame (torso center) of an R6 avatar standing at a lot point.
-- Avatar builders take ground frames; tweens/PivotTo move the pivot.
function PlotManager.PedWorld(state: PlotState, offset: Vector3): CFrame
	return toWorld(state.theme, offset) * CFrame.new(0, 3, 0)
end

-- Minimap data: one entry per plot (district + owner name).
function PlotManager.GetPlotsSummary(): { { any } }
	local out = {}
	for _, entry in plots do
		local state = entry.state
		table.insert(out, {
			district = state.theme.district,
			themeId = state.theme.id,
			themeName = state.theme.name,
			ownerName = if state.owner then state.owner.Name else nil,
		})
	end
	return out
end

-- Useful anchor points for other services.
PlotManager.Points = {
	STREET = STREET, COUNTER = COUNTER, OVEN = OVEN, WAREHOUSE = WAREHOUSE,
	VAN_PAD = VAN_PAD, DOOR = DOOR,
}

function PlotManager.Init(ctx)
	ctx.Services.PlotManager = PlotManager
	Config = ctx.Config
	Net = ctx.Net
	Economy = ctx.Services.Economy
	DataManager = ctx.Services.DataManager
	ModelFactory = ctx.Services.ModelFactory
	CityMap = ctx.Services.CityMap

	local world = CityMap.World

	for _, theme in Config.Plots do
		local state = buildBasePlot(theme, world)
		table.insert(plots, { state = state, theme = theme })
	end

	-- Release plots when owners leave.
	Players.PlayerRemoving:Connect(function(player)
		local state = playerPlots[player]
		if state then
			playerPlots[player] = nil
			PlotManager.ResetPlot(state)
		end
	end)
end

function PlotManager.ResetPlot(state: PlotState)
	-- Tear the owned plot down and restore the base claimable lot.
	state.model:Destroy()
	local entry
	for _, e in plots do
		if e.state == state then
			entry = e
			break
		end
	end
	if entry then
		local parent = CityMap.World
		entry.state = buildBasePlot(entry.theme, parent)
	end
end

-- Admin: release the player's plot (if any) back to a claimable lot.
-- Clearing playerPlots here matters: without it the "one plot per
-- player" check would block the player from claiming again.
function PlotManager.Release(player: Player)
	local state = playerPlots[player]
	if not state then
		return false
	end
	playerPlots[player] = nil
	PlotManager.ResetPlot(state)
	return true
end

function PlotManager.Start(_ctx)
	-- Periodically refresh signs of online owners (cheap, small N).
	task.spawn(function()
		while true do
			task.wait(5)
			for player, state in playerPlots do
				if player.Parent then
					local ok, err = pcall(PlotManager.Refresh, player, state)
					if not ok then
						warn("[PizzaTycoon] refresh failed: " .. tostring(err))
					end
				end
			end
		end
	end)
end

return PlotManager
