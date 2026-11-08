--!strict
-- DataManager: per-player persistent state with DataStore-backed saving,
-- retries, a session lock, and autosave. Player data shape is versioned
-- with `schemaVersion` for future migrations.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local DataManager = {}

local Config
local store

export type PlayerData = {
	schemaVersion: number,
	cash: number,
	totalRevenue: number,
	totalPizzasSold: number,
	themeId: string?,
	expansions: number,
	ingredients: { [string]: number },
	readyPizzas: number,
	upgrades: { oven: number, warehouse: number, marketing: number, security: number },
	staff: { chef: number, driver: number },
	unlockedRecipes: { string },
	activeRecipe: string,
}

local SCHEMA_VERSION = 1

local sessions: { [Player]: PlayerData } = {}
local dirty: { [Player]: boolean } = {}

local function newData(): PlayerData
	return {
		schemaVersion = SCHEMA_VERSION,
		cash = Config.StartingCash,
		totalRevenue = 0,
		totalPizzasSold = 0,
		themeId = nil,
		expansions = 0,
		ingredients = {},
		readyPizzas = 0,
		upgrades = { oven = 0, warehouse = 1, marketing = 1, security = 1 },
		staff = { chef = 0, driver = 0 },
		unlockedRecipes = { "margherita" },
		activeRecipe = Config.DefaultRecipe,
	}
end

local function keyFor(player: Player): string
	return "p_" .. player.UserId
end

local function clone(t: PlayerData): PlayerData
	local copy = table.clone(t)
	copy.upgrades = table.clone(t.upgrades)
	copy.staff = table.clone(t.staff)
	copy.ingredients = table.clone(t.ingredients)
	copy.unlockedRecipes = table.clone(t.unlockedRecipes)
	return copy
end

local function loadData(player: Player): PlayerData?
	local key = keyFor(player)
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return store:GetAsync(key)
		end)
		if ok then
			if result == nil then
				return newData()
			end
			-- Basic migration / repair pass.
			local data = newData()
			for k, v in result :: any do
				(data :: any)[k] = v
			end
			if type(data.cash) ~= "number" then
				data.cash = Config.StartingCash
			end
			if type(data.upgrades) ~= "table" then
				data.upgrades = { oven = 0, warehouse = 1, marketing = 1, security = 1 }
			end
			if type(data.staff) ~= "table" then
				data.staff = { chef = 0, driver = 0 }
			end
			if type(data.ingredients) ~= "table" then
				data.ingredients = {}
			end
			if type(data.unlockedRecipes) ~= "table" or #data.unlockedRecipes == 0 then
				data.unlockedRecipes = { "margherita" }
			end
			if not Config.Recipes[data.activeRecipe] then
				data.activeRecipe = Config.DefaultRecipe
			end
			return data
		else
			warn(("[PizzaTycoon] load attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(result)))
			task.wait(attempt * 2)
		end
	end
	return nil
end

local function saveData(player: Player): boolean
	local data = sessions[player]
	if not data then
		return false
	end
	local key = keyFor(player)
	local snapshot = clone(data)
	local jobId = game.JobId
	if jobId == "" then
		jobId = "studio"
	end
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				-- session lock: refuse to overwrite if another server saved
				-- more recently than our lock heartbeat would allow.
				if old and old.__lock and old.__lock ~= jobId then
					return nil -- abort write
				end
				local merged = snapshot
				merged.__lock = jobId
				return merged
			end)
		end)
		if ok then
			dirty[player] = false
			return true
		else
			warn(("[PizzaTycoon] save attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(err)))
			task.wait(attempt * 2)
		end
	end
	return false
end

function DataManager.Init(ctx)
	ctx.Services.DataManager = DataManager
	Config = ctx.Config
	store = DataStoreService:GetDataStore("PizzaTycoonPlayerData_v1")

	for _, player in Players:GetPlayers() do
		if not sessions[player] then
			local data = loadData(player)
			sessions[player] = data or newData()
		end
	end

	Players.PlayerAdded:Connect(function(player)
		local data = loadData(player)
		if not data then
			-- Never let a failed load corrupt play: use fresh data and flag.
			data = newData()
			warn("[PizzaTycoon] load failed, using fresh data for " .. player.Name)
		end
		sessions[player] = data
		dirty[player] = false
	end)

	Players.PlayerRemoving:Connect(function(player)
		if sessions[player] then
			saveData(player)
			sessions[player] = nil
			dirty[player] = nil
		end
	end)

	-- Autosave loop.
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in sessions do
				if dirty[player] then
					task.spawn(saveData, player)
				end
			end
		end
	end)

	-- Save everything when the server shuts down.
	game:BindToClose(function()
		for player in sessions do
			saveData(player)
		end
	end)
end

function DataManager.Get(player: Player): PlayerData?
	return sessions[player]
end

-- Direct field mutation helper. Marks the session dirty for autosave.
function DataManager.Mutate(player: Player, fn: (data: PlayerData) -> ()): boolean
	local data = sessions[player]
	if not data then
		return false
	end
	fn(data)
	dirty[player] = true
	return true
end

function DataManager.MarkDirty(player: Player)
	dirty[player] = true
end

function DataManager.SaveNow(player: Player): boolean
	return saveData(player)
end

-- Admin wipe: remove the player's stored entry entirely and hand them a
-- fresh session (identical to a brand-new player). Synchronous so the
-- admin panel can confirm afterwards.
function DataManager.Wipe(player: Player): boolean
	local key = keyFor(player)
	local ok = pcall(function()
		store:RemoveAsync(key)
	end)
	if not ok then
		warn("[PizzaTycoon] wipe failed for " .. player.Name)
	end
	sessions[player] = newData()
	dirty[player] = false
	return ok
end

return DataManager
