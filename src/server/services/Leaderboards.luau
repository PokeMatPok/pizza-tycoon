--!strict
-- Leaderboards: in-memory top-10 by total revenue, broadcast to all
-- clients every 30 seconds, plus an all-time OrderedDataStore that
-- updates every 5 minutes and on leave.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Leaderboards = {}

local Config, Net, DataManager
local orderedStore

function Leaderboards.Init(ctx)
	ctx.Services.Leaderboards = Leaderboards
	Config = ctx.Config
	Net = ctx.Net
	DataManager = ctx.Services.DataManager
	orderedStore = DataStoreService:GetOrderedDataStore("PizzaTycoonRevenue_v1")
end

local function broadcastTop()
	local entries = {}
	for _, player in Players:GetPlayers() do
		local data = DataManager.Get(player)
		if data then
			table.insert(entries, { name = player.Name, revenue = data.totalRevenue, pizzas = data.totalPizzasSold })
		end
	end
	table.sort(entries, function(a, b)
		return a.revenue > b.revenue
	end)
	while #entries > 10 do
		table.remove(entries)
	end
	Net.LeaderboardUpdate:FireAllClients({ entries = entries })
end

local function pushOrdered()
	for _, player in Players:GetPlayers() do
		local data = DataManager.Get(player)
		if data and data.totalRevenue > 0 then
			task.spawn(function()
				pcall(function()
					orderedStore:SetAsync(tostring(player.UserId), data.totalRevenue)
				end)
			end)
		end
	end
end

function Leaderboards.Start(_ctx)
	Players.PlayerRemoving:Connect(function(player)
		local data = DataManager.Get(player)
		if data and data.totalRevenue > 0 then
			pcall(function()
				orderedStore:SetAsync(tostring(player.UserId), data.totalRevenue)
			end)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(30)
			local ok, err = pcall(broadcastTop)
			if not ok then
				warn("[PizzaTycoon] leaderboard broadcast failed: " .. tostring(err))
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(300)
			pcall(pushOrdered)
		end
	end)
end

return Leaderboards
