--!strict
-- Production: the simulation heart. Each owned plot ticks once per second:
-- ovens consume ingredients and bake ready pizzas (rate scaled by tier,
-- chefs and expansions), staff upkeep drains cash, and warehouse thieves
-- occasionally steal ingredients (countered by security).

local Production = {}

local Config, Net
local DataManager, Economy, PlotManager, ModelFactory, EventManager

local currentEvent -- active event table or nil

local function expansionSpeedMult(data): number
	return 1 + 0.15 * data.expansions
end

local function bakeRatePerSec(data): number
	local ovenTier = Config.OvenTiers[data.upgrades.oven]
	if not ovenTier then
		return 0
	end
	local chefMult = 1 + Config.Staff.chef.speedMultPer * data.staff.chef
	return (ovenTier.pizzasPerMin / 60) * chefMult * expansionSpeedMult(data)
end

local function hasIngredients(data, recipe): boolean
	for ing, needed in recipe.ingredients do
		if (data.ingredients[ing] or 0) < needed then
			return false
		end
	end
	return true
end

local function tickOven(player: Player, state, data)
	if data.readyPizzas >= Config.ReadyPizzaCap then
		return
	end
	local recipe = Config.Recipes[data.activeRecipe]
	if not recipe or not hasIngredients(data, recipe) then
		return
	end
	local perSec = bakeRatePerSec(data)
	if perSec <= 0 then
		return
	end
	local baked = perSec * Config.ProductionTick
	-- Visual: a pizza pops out of the oven mouth and slides to the counter.
	local from = PlotManager.LocalToWorld(state, PlotManager.Points.OVEN + Vector3.new(0, 3, 3))
	local to = PlotManager.LocalToWorld(state, PlotManager.Points.COUNTER)
	local pizza = ModelFactory.pizza(recipe.color, recipe.toppingColor, state.model, from * CFrame.Angles(0, math.rad(90), 0))
	ModelFactory.tweenModel(pizza, to * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, math.rad(90), 0), 1.5)
	task.delay(1.5, function()
		if pizza and pizza.Parent then
			pizza:Destroy()
		end
		DataManager.Mutate(player, function(d)
			d.readyPizzas = math.min(Config.ReadyPizzaCap, d.readyPizzas + baked)
		end)
	end)
	DataManager.Mutate(player, function(d)
		for ing, needed in recipe.ingredients do
			local scaled = needed * perSec * Config.ProductionTick
			-- Fractional consumption: floor at 0, never negative.
			d.ingredients[ing] = math.max(0, (d.ingredients[ing] or 0) - scaled)
		end
	end)
end

local function tickUpkeep(player: Player, data)
	local perMin = Config.Staff.chef.upkeepPerMin * data.staff.chef
		+ Config.Staff.driver.upkeepPerMin * data.staff.driver
	if perMin <= 0 then
		return
	end
	local perTick = perMin / 60 * Config.ProductionTick
	local balance = Economy.GetCash(player)
	if balance < perTick then
		-- Staff strike (no production bonus) instead of negative balance.
		return
	end
	Economy.Transact(player, -perTick, "upkeep")
end

local function tickTheft(player: Player, state, data)
	if data.upgrades.security >= 4 then
		return
	end
	local chance = Config.Theft.baseChancePerMin * Config.ProductionTick / 60
	chance *= Config.SecurityTiers[data.upgrades.security].theftChanceMult
	if currentEvent then
		chance *= currentEvent.theftMult
	end
	if math.random() > chance then
		return
	end
	local pool = {}
	for ing, n in data.ingredients do
		if n > 0 then
			table.insert(pool, ing)
		end
	end
	if #pool == 0 then
		return
	end
	local ing = pool[math.random(#pool)]
	DataManager.Mutate(player, function(d)
		d.ingredients[ing] = math.max(0, (d.ingredients[ing] or 0) - Config.Theft.stealAmount)
	end)
	-- Visual: shadowy customer flees the warehouse.
	local spy = ModelFactory.customer(Color3.fromRGB(30, 30, 35), state.model, PlotManager.LocalToWorld(state, PlotManager.Points.WAREHOUSE))
	ModelFactory.tweenModel(spy, PlotManager.LocalToWorld(state, PlotManager.Points.STREET), 2)
	task.delay(2.2, function()
		if spy and spy.Parent then
			spy:Destroy()
		end
	end)
	Net.Announce:FireClient(player, ("Thieves stole %d %s!"):format(Config.Theft.stealAmount, Config.IngredientNames[ing]), Color3.fromRGB(255, 90, 90))
end

function Production.Init(ctx)
	ctx.Services.Production = Production
	Config = ctx.Config
	Net = ctx.Net
	DataManager = ctx.Services.DataManager
	Economy = ctx.Services.Economy
	PlotManager = ctx.Services.PlotManager
	ModelFactory = ctx.Services.ModelFactory
end

function Production.Start(ctx)
	local EventManager = ctx.Services.EventManager

	task.spawn(function()
		while true do
			task.wait(Config.ProductionTick)
			currentEvent = EventManager.GetCurrent()
			for _, player in game:GetService("Players"):GetPlayers() do
				local state = PlotManager.GetPlot(player)
				local data = DataManager.Get(player)
				if state and data and state.owner == player then
					local ok, err = pcall(function()
						tickOven(player, state, data)
						tickUpkeep(player, data)
						tickTheft(player, state, data)
					end)
					if not ok then
						warn("[PizzaTycoon] production tick failed: " .. tostring(err))
					end
				end
			end
		end
	end)
end

return Production
