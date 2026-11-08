--!strict
-- AdminService: server-side executor for the admin panel. The client
-- hides the panel from everyone, but security lives HERE: every command
-- re-checks Config.AdminUserIds before running, so a modified client
-- (or any other player firing the remote) gets silently ignored.

local Players = game:GetService("Players")

local AdminService = {}

local Config, Net
local DataManager, Economy, PlotManager, EventManager, CityMap

local WHITE = Color3.fromRGB(240, 240, 240)
local GOOD = Color3.fromRGB(120, 255, 160)
local BAD = Color3.fromRGB(255, 120, 120)

local function isAdmin(player: Player): boolean
	return table.find(Config.AdminUserIds, player.UserId) ~= nil
end

local function announce(player: Player, text: string, color: Color3?)
	Net.Announce:FireClient(player, text, color or WHITE)
end

local function num(value: any): number
	return math.floor(tonumber(value) or 0)
end

-- Snapshot of everything the panel displays. Always derived from real
-- session data, so the client can never drift out of sync.
local function snapshot(player: Player)
	local data = DataManager.Get(player)
	if not data then
		return nil
	end
	local event = EventManager.GetCurrent()
	local plot = PlotManager.GetPlot(player)
	return {
		cash = data.cash,
		readyPizzas = data.readyPizzas,
		upgrades = table.clone(data.upgrades),
		staff = table.clone(data.staff),
		expansions = data.expansions,
		unlockedCount = #data.unlockedRecipes,
		activeRecipe = data.activeRecipe,
		currentEvent = if event then event.id else nil,
		plotTheme = if plot then plot.theme.id else nil,
		maxExpansions = if plot then plot.theme.maxExpansions else 3,
	}
end

local function reply(player: Player)
	local snap = snapshot(player)
	if snap then
		Net.AdminState:FireClient(player, snap)
	end
	local plot = PlotManager.GetPlot(player)
	if plot then
		PlotManager.Refresh(player, plot)
	end
end

local handlers: { [string]: (player: Player, args: any) -> () } = {}

handlers.get_status = function(_player, _args) end -- reply() sends the snapshot

-- ===== Economy =====

handlers.set_cash = function(player, args)
	local target = math.max(0, num(args.amount))
	local delta = target - Economy.GetCash(player)
	if delta ~= 0 then
		Economy.Transact(player, delta, "admin:set_cash")
	end
	announce(player, ("Cash set to $%d"):format(target), GOOD)
end

handlers.add_cash = function(player, args)
	local amount = num(args.amount)
	if amount ~= 0 then
		Economy.Transact(player, amount, "admin:add_cash")
	end
	announce(player, ("%+$%d"):format(amount), GOOD)
end

handlers.give_ingredients = function(player, args)
	local amount = math.max(0, num(args.amount))
	DataManager.Mutate(player, function(d)
		local cap = Config.WarehouseTiers[d.upgrades.warehouse].capacity
		for ingredient in Config.IngredientColors do
			d.ingredients[ingredient] = math.min(cap, (d.ingredients[ingredient] or 0) + amount)
		end
	end)
	Economy.PushState(player)
	announce(player, ("+%d of every ingredient"):format(amount), GOOD)
end

handlers.set_ready = function(player, args)
	local amount = math.clamp(num(args.amount), 0, Config.ReadyPizzaCap)
	DataManager.Mutate(player, function(d)
		d.readyPizzas = amount
	end)
	Economy.PushState(player)
	announce(player, ("Ready pizzas set to %d"):format(amount), GOOD)
end

handlers.unlock_all = function(player)
	DataManager.Mutate(player, function(d)
		for id in Config.Recipes do
			if not table.find(d.unlockedRecipes, id) then
				table.insert(d.unlockedRecipes, id)
			end
		end
	end)
	Economy.PushState(player)
	announce(player, "All recipes unlocked", GOOD)
end

-- ===== Progression =====

handlers.set_upgrade = function(player, args)
	local kind = tostring(args.kind)
	local tiers
	if kind == "oven" then
		tiers = Config.OvenTiers
	elseif kind == "warehouse" then
		tiers = Config.WarehouseTiers
	elseif kind == "marketing" then
		tiers = Config.MarketingTiers
	elseif kind == "security" then
		tiers = Config.SecurityTiers
	else
		return
	end
	local minTier = if kind == "oven" then 0 else 1
	local tier = math.clamp(num(args.tier), minTier, #tiers)
	DataManager.Mutate(player, function(d)
		(d.upgrades :: any)[kind] = tier
	end)
	Economy.PushState(player)
	local tierData = tiers[tier]
	announce(player, ("%s set to %s"):format(kind, if tierData then tierData.name else tostring(tier)), GOOD)
end

handlers.set_staff = function(player, args)
	local kind = tostring(args.kind)
	local staffConfig = (Config.Staff :: any)[kind]
	if not staffConfig then
		return
	end
	local count = math.clamp(num(args.count), 0, staffConfig.max)
	DataManager.Mutate(player, function(d)
		(d.staff :: any)[kind] = count
	end)
	Economy.PushState(player)
	announce(player, ("%s set to %d"):format(kind, count), GOOD)
end

-- Set owned expansions directly, recoloring pads to match (reducing
-- also removes the decor a pad gained when it was bought normally).
handlers.set_expansions = function(player, args)
	local plot = PlotManager.GetPlot(player)
	if not plot then
		announce(player, "Claim a plot first", BAD)
		return
	end
	local count = math.clamp(num(args.count), 0, plot.theme.maxExpansions)
	DataManager.Mutate(player, function(d)
		d.expansions = count
	end)
	for _, child in plot.model:GetChildren() do
		if child.Name == "ExpansionDecor" then
			child:Destroy()
		end
	end
	for i, pad in plot.expansionPads do
		if i <= count then
			pad.Color = plot.theme.baseColor
			pad.Material = Enum.Material.Concrete
			local decor = Instance.new("Part")
			decor.Name = "ExpansionDecor"
			decor.Anchored = true
			decor.CanCollide = true
			decor.TopSurface = Enum.SurfaceType.Smooth
			decor.BottomSurface = Enum.SurfaceType.Smooth
			decor.Size = Vector3.new(4, 6, 4)
			decor.Color = plot.theme.accentColor
			decor.Material = Enum.Material.Neon
			decor.CFrame = pad.CFrame * CFrame.new(5, 3, 5)
			decor.Parent = plot.model
		end
		local prompt = plot.prompts["expand_" .. i]
		if prompt then
			prompt.Enabled = i > count and i == count + 1
		end
	end
	Economy.PushState(player)
	announce(player, ("Expansions set to %d"):format(count), GOOD)
end

-- ===== Events =====

handlers.trigger_event = function(player, args)
	local id = tostring(args.id)
	local event = Config.Events[id]
	if not event then
		announce(player, "Unknown event: " .. id, BAD)
		return
	end
	if not EventManager.ForceStart(id) then
		announce(player, "Could not start event", BAD)
	end
	-- startEvent already announces city-wide.
end

handlers.clear_event = function(player)
	EventManager.Clear()
end

-- ===== Teleport =====

handlers.teleport = function(player, args)
	local id = tostring(args.districtId)
	local target = CityMap.TeleportCFrame(id)
	local district = Config.City.Districts[id]
	if not target or not district then
		announce(player, "Unknown district", BAD)
		return
	end
	local character = player.Character
	if not character then
		return
	end
	character:PivotTo(target)
	announce(player, "Teleported to " .. district.name, district.mapColor)
end

-- ===== Data =====

handlers.save_now = function(player)
	if DataManager.SaveNow(player) then
		announce(player, "Data saved", GOOD)
	else
		announce(player, "Save failed (is API access on?)", BAD)
	end
end

handlers.wipe_data = function(player)
	PlotManager.Release(player)
	DataManager.Wipe(player)
	Economy.PushState(player)
	announce(player, "Your data has been wiped. Fresh start!", GOOD)
end

handlers.release_plot = function(player)
	if PlotManager.Release(player) then
		announce(player, "Plot released", GOOD)
	else
		announce(player, "No plot to release", BAD)
	end
end

function AdminService.Init(ctx)
	ctx.Services.AdminService = AdminService
	Config = ctx.Config
	Net = ctx.Net
	DataManager = ctx.Services.DataManager
	Economy = ctx.Services.Economy
	PlotManager = ctx.Services.PlotManager
	EventManager = ctx.Services.EventManager
	CityMap = ctx.Services.CityMap

	Net.AdminCommand.OnServerEvent:Connect(function(player, cmd, args)
		if not isAdmin(player) then
			return -- silently ignore non-admins
		end
		if typeof(cmd) ~= "string" then
			return
		end
		local handler = handlers[cmd]
		if not handler then
			announce(player, "Unknown command: " .. cmd, BAD)
			reply(player)
			return
		end
		local ok, err = pcall(handler, player, if typeof(args) == "table" then args else {})
		if not ok then
			warn("[PizzaTycoon] admin command failed (" .. cmd .. "): " .. tostring(err))
			announce(player, "Command failed: " .. cmd, BAD)
		end
		reply(player)
	end)
end

function AdminService.Start(_ctx)
	-- Push an initial snapshot to any admin already in the game.
	for _, player in Players:GetPlayers() do
		if isAdmin(player) then
			reply(player)
		end
	end
end

return AdminService
