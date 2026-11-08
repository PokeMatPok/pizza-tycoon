--!strict
-- OrderSystem: AI customers walk to your counter, buy one pizza of the
-- active recipe (paying its price * marketing price multiplier * event
-- multiplier), or leave grumpy if you have no stock. Spawn rate scales
-- with marketing tier, expansions and active events.

local OrderSystem = {}

local Config, Net
local DataManager, Economy, PlotManager, ModelFactory, EventManager

local currentEvent

local SHIRT_COLORS = {
	Color3.fromRGB(200, 60, 60),
	Color3.fromRGB(60, 120, 200),
	Color3.fromRGB(90, 180, 90),
	Color3.fromRGB(200, 160, 40),
	Color3.fromRGB(160, 90, 180),
}

local function spawnRatePerSec(data): number
	local rate = (Config.CustomerBaseRatePerMin / 60)
		* Config.MarketingTiers[data.upgrades.marketing].customerMult
		* (1 + 0.10 * data.expansions)
	if currentEvent then
		rate *= currentEvent.customerMult
	end
	return rate
end

local function customerSalePrice(data): number
	local recipe = Config.Recipes[data.activeRecipe]
	local price = recipe.price * Config.MarketingTiers[data.upgrades.marketing].priceMult
	if currentEvent then
		price *= currentEvent.priceMult
	end
	return math.floor(price + 0.5)
end

local function recipeColorFor(data): Color3
	local recipe = Config.Recipes[data.activeRecipe]
	return if recipe then recipe.color else Color3.fromRGB(230, 180, 90)
end

local function recipeToppingFor(data): Color3
	local recipe = Config.Recipes[data.activeRecipe]
	return if recipe then recipe.toppingColor else Color3.fromRGB(220, 60, 40)
end

local function serveCustomer(player: Player, state, data)
	local recipe = Config.Recipes[data.activeRecipe]
	if not recipe or data.readyPizzas < 1 then
		return false
	end
	local price = customerSalePrice(data)
	DataManager.Mutate(player, function(d)
		d.readyPizzas -= 1
		d.totalPizzasSold += 1
		d.totalRevenue += price
	end)
	Economy.Earn(player, price, "sale:" .. data.activeRecipe)
	-- Floating +$ text at the counter for the owner.
	Net.CashFloat:FireClient(player, {
		position = PlotManager.LocalToWorld(state, PlotManager.Points.COUNTER + Vector3.new(0, 2, 0)).Position,
		amount = price,
	})
	return true
end

local function spawnCustomer(player: Player, state, data)
	local from = PlotManager.LocalToWorld(state, PlotManager.Points.STREET)
	local atCounter = PlotManager.LocalToWorld(state, PlotManager.Points.COUNTER + Vector3.new(0, 0, 3))
	local shirt = SHIRT_COLORS[math.random(#SHIRT_COLORS)]
	local customer = ModelFactory.customer(shirt, state.model, from * CFrame.Angles(0, math.rad(180), 0))
	ModelFactory.tweenModel(customer, atCounter, 2.5)
	task.delay(2.6, function()
		if not customer.Parent or not state.model.Parent then
			if customer then
				customer:Destroy()
			end
			return
		end
		local ok = false
		if state.owner == player and player.Parent then
			local freshData = DataManager.Get(player)
			if freshData then
				ok = serveCustomer(player, state, freshData)
			end
		end
		if ok then
			local pizza = ModelFactory.pizza(recipeColorFor(data), recipeToppingFor(data), state.model, atCounter * CFrame.new(0, 1.4, 0) * CFrame.Angles(0, math.rad(90), 0))
			ModelFactory.tweenModel(customer, from, 2.5)
			task.delay(0.8, function()
				if pizza and pizza.Parent then
					pizza:Destroy()
				end
			end)
		else
			ModelFactory.tweenModel(customer, from, 2.5)
			Net.Announce:FireClient(player, "A customer left: no ready pizzas!", Color3.fromRGB(255, 200, 100))
		end
		task.delay(2.6, function()
			if customer and customer.Parent then
				customer:Destroy()
			end
		end)
	end)
end

-- Fractional spawn accumulator so low rates still produce customers.
local accumulators: { [Player]: number } = {}

function OrderSystem.Init(ctx)
	ctx.Services.OrderSystem = OrderSystem
	Config = ctx.Config
	Net = ctx.Net
	DataManager = ctx.Services.DataManager
	Economy = ctx.Services.Economy
	PlotManager = ctx.Services.PlotManager
	ModelFactory = ctx.Services.ModelFactory
	EventManager = ctx.Services.EventManager
end

function OrderSystem.Start(ctx)
	-- Re-resolve here: services may register after this module's Init ran.
	EventManager = ctx.Services.EventManager
	task.spawn(function()
		while true do
			task.wait(1)
			currentEvent = EventManager.GetCurrent()
			for _, player in game:GetService("Players"):GetPlayers() do
				local state = PlotManager.GetPlot(player)
				local data = DataManager.Get(player)
				if state and data and state.owner == player then
					accumulators[player] = (accumulators[player] or 0) + spawnRatePerSec(data)
					while accumulators[player] >= 1 do
						accumulators[player] -= 1
						local ok, err = pcall(spawnCustomer, player, state, data)
						if not ok then
							warn("[PizzaTycoon] customer spawn failed: " .. tostring(err))
						end
					end
				end
			end
		end
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		accumulators[player] = nil
	end)
end

return OrderSystem
