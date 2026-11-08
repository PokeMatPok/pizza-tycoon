--!strict
-- Economy: the single server-side gate for all money movement.
-- Every credit/debit goes through Transact so balances can never drift
-- and the client always learns about changes via StateChanged.

local Players = game:GetService("Players")

local Economy = {}

local Config, Net
local DataManager

function Economy.Init(ctx)
	ctx.Services.Economy = Economy
	Config = ctx.Config
	Net = ctx.Net
	DataManager = ctx.Services.DataManager
end

function Economy.GetCash(player: Player): number
	local data = DataManager.Get(player)
	return data and data.cash or 0
end

-- Central transaction. `reason` is used for the transaction log.
-- Returns success, newBalance.
function Economy.Transact(player: Player, delta: number, reason: string): (boolean, number)
	local data = DataManager.Get(player)
	if not data then
		return false, 0
	end
	-- Integral money only; reject nonsense inputs outright.
	if delta ~= delta or delta == math.huge or delta == -math.huge then
		return false, data.cash
	end
	local newCash = data.cash + delta
	if delta < 0 and newCash < 0 then
		return false, data.cash
	end
	data.cash = math.floor(newCash + 0.5)
	DataManager.MarkDirty(player)
	Economy.PushState(player)
	return true, data.cash
end

-- Convenience: spend if affordable (atomic check + debit).
function Economy.Spend(player: Player, amount: number, reason: string): boolean
	if amount < 0 then
		return false
	end
	local data = DataManager.Get(player)
	if not data or data.cash < amount then
		return false
	end
	return (Economy.Transact(player, -amount, reason))
end

function Economy.Earn(player: Player, amount: number, reason: string): boolean
	if amount <= 0 then
		return false
	end
	return (Economy.Transact(player, amount, reason))
end

-- Serialize everything the client needs to render HUD.
function Economy.Serialize(player: Player)
	local data = DataManager.Get(player)
	if not data then
		return nil
	end
	return {
		cash = data.cash,
		totalRevenue = data.totalRevenue,
		totalPizzasSold = data.totalPizzasSold,
		themeId = data.themeId,
		expansions = data.expansions,
		ingredients = table.clone(data.ingredients),
		readyPizzas = data.readyPizzas,
		upgrades = table.clone(data.upgrades),
		staff = table.clone(data.staff),
		unlockedRecipes = table.clone(data.unlockedRecipes),
		activeRecipe = data.activeRecipe,
	}
end

function Economy.PushState(player: Player)
	local state = Economy.Serialize(player)
	if state then
		Net.StateChanged:FireClient(player, state)
	end
end

function Economy.Start(_ctx)
	-- Push state whenever a player's character is ready so the HUD
	-- has data even after a death/respawn.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.delay(1, function()
				Economy.PushState(player)
			end)
		end)
	end)
	for _, player in Players:GetPlayers() do
		Economy.PushState(player)
	end
end

return Economy
