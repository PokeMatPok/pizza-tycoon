--!strict
-- DeliveryZones: one shared competitive delivery zone per city district.
-- Each zone pad has a "send van" prompt for every plot owner (10 ready
-- pizzas + a free driver). Every payout cycle, the zone pot is split by
-- each player's contribution share of van shipments delivered during the
-- cycle. Pot size = district wealth (zoneDemand), boosted by events.

local DeliveryZones = {}

local Config, Net
local DataManager, Economy, PlotManager, ModelFactory, EventManager, CityMap
type ZoneState = {
	cfg: any,
	pad: Model,
	sign: TextLabel,
	contributions: { [Player]: number },
	inTransit: { [Player]: number }, -- shipments in flight per player in this zone
}

local zones: { ZoneState } = {}

local function totalContribution(zone: ZoneState): number
	local total = 0
	for _, amount in zone.contributions do
		total += amount
	end
	return total
end

function refreshSign(zone: ZoneState)
	local top = "none"
	local topAmount = -1
	for player, amount in zone.contributions do
		if amount > topAmount and player.Parent then
			topAmount = amount
			top = player.Name
		end
	end
	zone.sign.Text = ("%s\nPot: $%d / %ds cycle\nLeader: %s (%d boxes)"):format(
		zone.cfg.name, zone.cfg.zoneDemand, Config.ZonePayoutInterval, top, if topAmount >= 0 then topAmount else 0
	)
end

local function payoutCycle(zone: ZoneState)
	local total = totalContribution(zone)
	if total < Config.VanShipmentSize then
		-- Nobody delivered enough this cycle: reset contributions.
		zone.contributions = {}
		refreshSign(zone)
		return
	end
	local pot = zone.cfg.zoneDemand
	local event = EventManager.GetCurrent()
	if event then
		pot *= event.zoneMult
	end
	local payouts = {}
	for player, amount in zone.contributions do
		if player.Parent then
			local share = math.floor((amount / total) * pot + 0.5)
			if share > 0 then
				Economy.Earn(player, share, "zone:" .. zone.cfg.id)
				table.insert(payouts, { name = player.Name, amount = share })
			end
		end
	end
	Net.ZoneUpdate:FireAllClients({
		zoneId = zone.cfg.id,
		zoneName = zone.cfg.name,
		pot = pot,
		payouts = payouts,
	})
	for player in zone.contributions do
		Net.Announce:FireClient(player, ("%s paid out! Check your cash."):format(zone.cfg.name), zone.cfg.mapColor)
	end
	zone.contributions = {}
	refreshSign(zone)
end

local function sendVan(player: Player, zone: ZoneState)
	local state = PlotManager.GetPlot(player)
	local data = DataManager.Get(player)
	if not state or not data or state.owner ~= player then
		return
	end
	if data.readyPizzas < Config.VanShipmentSize then
		Net.Announce:FireClient(player, ("Need %d ready pizzas for a van shipment!"):format(Config.VanShipmentSize), Color3.fromRGB(255, 200, 100))
		return
	end
	-- A driver is locked per in-flight shipment across ALL zones:
	local inFlight = 0
	for _, z in zones do
		inFlight += (z.inTransit[player] or 0)
	end
	if data.staff.driver < 1 or inFlight >= data.staff.driver then
		Net.Announce:FireClient(player, "No free drivers! Hire drivers at your van pad.", Color3.fromRGB(255, 200, 100))
		return
	end
	DataManager.Mutate(player, function(d)
		d.readyPizzas -= Config.VanShipmentSize
	end)
	zone.inTransit[player] = (zone.inTransit[player] or 0) + 1
	-- Visual: van drives from plot pad to the zone and back.
	-- The van builder takes a GROUND frame; the model pivot (body) sits
	-- 3.7 studs above it, so tween targets must be lifted to pivot height.
	local van = ModelFactory.van(zone.cfg.mapColor, state.model, PlotManager.LocalToWorld(state, PlotManager.Points.VAN_PAD))
	local zoneCf = zone.pad:GetPivot() * CFrame.new(0, 3.7, 12)
	task.spawn(function()
		local tween1 = ModelFactory.tweenModel(van, zoneCf, Config.VanTransitTime)
		tween1.Completed:Wait()
		if van.Parent then
			van:Destroy()
		end
		if state.owner == player and player.Parent then
			zone.contributions[player] = (zone.contributions[player] or 0) + Config.VanShipmentSize
			zone.inTransit[player] -= 1
			refreshSign(zone)
			Net.Announce:FireClient(player, ("Van delivered %d pizzas to %s!"):format(Config.VanShipmentSize, zone.cfg.name), zone.cfg.mapColor)
		else
			zone.inTransit[player] -= 1
		end
	end)
end

function DeliveryZones.Init(ctx)
	ctx.Services.DeliveryZones = DeliveryZones
	Config = ctx.Config
	Net = ctx.Net
	DataManager = ctx.Services.DataManager
	Economy = ctx.Services.Economy
	PlotManager = ctx.Services.PlotManager
	ModelFactory = ctx.Services.ModelFactory
	EventManager = ctx.Services.EventManager
	CityMap = ctx.Services.CityMap

	local world = CityMap.World
	for _, district in Config.City.Districts do
		local pad = ModelFactory.zonePad(district.mapColor, world, CFrame.new(district.zone + Vector3.new(0, 0.4, 0)))
		local _, sign = ModelFactory.infoSign(world, CFrame.new(district.zone + Vector3.new(0, 0, -13)), Vector2.new(320, 90))
		local zone: ZoneState = {
			cfg = district,
			pad = pad,
			sign = sign,
			contributions = {},
			inTransit = {},
		}
		local prompt = ModelFactory.prompt(pad.PrimaryPart :: BasePart, ("Send Van (%d pizzas)"):format(Config.VanShipmentSize), district.name, 0.5)
		prompt.Triggered:Connect(function(player)
			local ok, err = pcall(sendVan, player, zone)
			if not ok then
				warn("[PizzaTycoon] van send failed: " .. tostring(err))
			end
		end)
		table.insert(zones, zone)
		refreshSign(zone)
	end
end

function DeliveryZones.Start(ctx)
	EventManager = ctx.Services.EventManager
	task.spawn(function()
		while true do
			task.wait(Config.ZonePayoutInterval)
			for _, zone in zones do
				local ok, err = pcall(payoutCycle, zone)
				if not ok then
					warn("[PizzaTycoon] payout failed: " .. tostring(err))
				end
			end
		end
	end)
end

return DeliveryZones
