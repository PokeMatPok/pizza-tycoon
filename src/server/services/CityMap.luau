--!strict
-- CityMap: builds the open world: ground, districts, road grid with
-- sidewalks and street lamps, low-poly buildings per district style,
-- plazas with district signs, and the spawn. Also serves map data to
-- Traffic/Pedestrians (road + sidewalk loops), handles minimap fast
-- travel and broadcasts CityState (traffic level, plot owners, blips).

local Players = game:GetService("Players")

local CityMap = {}

local Config, Net
local ModelFactory, PlotManager, Traffic

export type RectLoop = {
	x0: number, z0: number, x1: number, z1: number,
	perim: number,
}

CityMap.World = nil :: Model?

-- ===================== Loop helpers =====================

local function makeLoop(x0: number, z0: number, x1: number, z1: number): RectLoop
	return { x0 = x0, z0 = z0, x1 = x1, z1 = z1, perim = 2 * ((x1 - x0) + (z1 - z0)) }
end

-- Block loops: rectangles following the road center lines around each
-- city block (used by Traffic, offset to the right-hand lane there).
local roadLoops: { RectLoop } = {}
-- Sidewalk loops: rectangles inset into each block (used by Pedestrians).
local sidewalkLoops: { RectLoop } = {}
local loopsBuilt = false

local function buildLoops()
	if loopsBuilt then
		return
	end
	loopsBuilt = true
	local RoadsX = Config.City.RoadsX
	local RoadsZ = Config.City.RoadsZ
	for i = 1, #RoadsX - 1 do
		for j = 1, #RoadsZ - 1 do
			table.insert(roadLoops, makeLoop(RoadsX[i], RoadsZ[j], RoadsX[i + 1], RoadsZ[j + 1]))
			local inset = Config.City.RoadHalf + Config.City.SidewalkWidth / 2
			table.insert(sidewalkLoops, makeLoop(RoadsX[i] + inset, RoadsZ[j] + inset, RoadsX[i + 1] - inset, RoadsZ[j + 1] - inset))
		end
	end
	-- The grand outer ring (road) + one big cross loop, so cars also
	-- travel across the whole city instead of circling single blocks.
	table.insert(roadLoops, makeLoop(RoadsX[1], RoadsZ[1], RoadsX[#RoadsX], RoadsZ[#RoadsZ]))
	table.insert(roadLoops, makeLoop(RoadsX[1], RoadsZ[1], RoadsX[#RoadsX], RoadsZ[2]))
	table.insert(roadLoops, makeLoop(RoadsX[2], RoadsZ[2], RoadsX[#RoadsX], RoadsZ[#RoadsZ]))
end

function CityMap.GetRoadLoops(): { RectLoop }
	buildLoops()
	return roadLoops
end

function CityMap.GetSidewalkLoops(): { RectLoop }
	buildLoops()
	return sidewalkLoops
end

function CityMap.GetDistrictAt(position: Vector3)
	for _, district in Config.City.Districts do
		local r = district.rect
		if position.X >= r.x0 and position.X <= r.x1 and position.Z >= r.z0 and position.Z <= r.z1 then
			return district
		end
	end
	return nil
end

function CityMap.TeleportCFrame(districtId: string): CFrame?
	local district = Config.City.Districts[districtId]
	if not district then
		return nil
	end
	return CFrame.new(district.plaza + Vector3.new(0, 6, 0))
end

-- ===================== World construction =====================

local function buildGround(world: Model)
	local half = Config.City.WorldHalf
	ModelFactory.basePart({
		Name = "Ground",
		Size = Vector3.new(half * 2, 1, half * 2),
		Color = Color3.fromRGB(88, 128, 78),
		Material = Enum.Material.Grass,
		CFrame = CFrame.new(0, -0.5, 0),
		Parent = world,
	})
	-- Tinted ground patch per district (between the roads).
	for _, district in Config.City.Districts do
		local r = district.rect
		local m = Config.City.RoadHalf + Config.City.SidewalkWidth
		ModelFactory.basePart({
			Name = "Ground_" .. district.id,
			Size = Vector3.new(r.x1 - r.x0 - m * 2, 0.1, r.z1 - r.z0 - m * 2),
			Color = district.groundColor,
			Material = if district.style == "waterfront" then Enum.Material.Sand else Enum.Material.Grass,
			CanCollide = false,
			CFrame = CFrame.new((r.x0 + r.x1) / 2, 0.05, (r.z0 + r.z1) / 2),
			Parent = world,
		})
	end
end

local function buildRoads(world: Model)
	local half = Config.City.WorldHalf
	local rh = Config.City.RoadHalf
	local sw = Config.City.SidewalkWidth

	-- Road slabs. Vertical roads sit a hair above horizontal ones so
	-- overlapping intersections don't z-fight.
	for i, x in Config.City.RoadsX do
		ModelFactory.basePart({
			Name = "Road",
			Size = Vector3.new(rh * 2, 0.2, half * 2),
			Color = Color3.fromRGB(52, 52, 56),
			Material = Enum.Material.Asphalt,
			CFrame = CFrame.new(x, 0.6, 0),
			Parent = world,
		})
	end
	for j, z in Config.City.RoadsZ do
		ModelFactory.basePart({
			Name = "Road",
			Size = Vector3.new(half * 2, 0.2, rh * 2),
			Color = Color3.fromRGB(50, 50, 54),
			Material = Enum.Material.Asphalt,
			CFrame = CFrame.new(0, 0.55, z),
			Parent = world,
		})
	end

	-- Center line dashes (skip near intersections).
	local function nearAny(t: number, lines: { number }, thresh: number): boolean
		for _, v in lines do
			if math.abs(t - v) < thresh then
				return true
			end
		end
		return false
	end
	for _, x in Config.City.RoadsX do
		for z = -half + 14, half - 14, 14 do
			if not nearAny(z, Config.City.RoadsZ, rh + 8) then
				ModelFactory.basePart({
					Name = "Dash",
					Size = Vector3.new(0.35, 0.22, 4),
					Color = Color3.fromRGB(230, 200, 80),
					Material = Enum.Material.SmoothPlastic,
					CanCollide = false,
					CFrame = CFrame.new(x, 0.72, z),
					Parent = world,
				})
			end
		end
	end
	for _, z in Config.City.RoadsZ do
		for x = -half + 14, half - 14, 14 do
			if not nearAny(x, Config.City.RoadsX, rh + 8) then
				ModelFactory.basePart({
					Name = "Dash",
					Size = Vector3.new(4, 0.22, 0.35),
					Color = Color3.fromRGB(230, 200, 80),
					Material = Enum.Material.SmoothPlastic,
					CanCollide = false,
					CFrame = CFrame.new(x, 0.71, z),
					Parent = world,
				})
			end
		end
	end

	-- Sidewalks flanking every road, with curb height.
	for _, x in Config.City.RoadsX do
		for _, side in { -1, 1 } do
			ModelFactory.basePart({
				Name = "Sidewalk",
				Size = Vector3.new(sw, 0.4, half * 2),
				Color = Color3.fromRGB(165, 165, 168),
				Material = Enum.Material.Concrete,
				CFrame = CFrame.new(x + side * (rh + sw / 2), 0.7, 0),
				Parent = world,
			})
		end
	end
	for _, z in Config.City.RoadsZ do
		for _, side in { -1, 1 } do
			ModelFactory.basePart({
				Name = "Sidewalk",
				Size = Vector3.new(half * 2, 0.4, sw),
				Color = Color3.fromRGB(165, 165, 168),
				Material = Enum.Material.Concrete,
				CFrame = CFrame.new(0, 0.65, z + side * (rh + sw / 2)),
				Parent = world,
			})
		end
	end

	-- Street lamps along roads (skip near intersections).
	for _, x in Config.City.RoadsX do
		for z = -half + 30, half - 30, 44 do
			if not nearAny(z, Config.City.RoadsZ, rh + 10) then
				ModelFactory.lamp(world, CFrame.new(x + rh + sw / 2, 0.9, z))
			end
		end
	end
	for _, z in Config.City.RoadsZ do
		for x = -half + 30, half - 30, 44 do
			if not nearAny(x, Config.City.RoadsX, rh + 10) then
				ModelFactory.lamp(world, CFrame.new(x, 0.9, z + rh + sw / 2))
			end
		end
	end
end

-- Does `rect` (x/z center + half extents) overlap any of the reserved
-- circles (center + radius)? Used to keep buildings off lots and plazas.
local function overlapsReserved(cx: number, cz: number, hx: number, hz: number, reserved: { { number } }): boolean
	for _, r in reserved do
		local rx, rz, rr = r[1], r[2], r[3]
		if math.abs(cx - rx) < hx + rr and math.abs(cz - rz) < hz + rr then
			return true
		end
	end
	return false
end

local function buildDistrictBuildings(world: Model)
	for _, district in Config.City.Districts do
		local r = district.rect
		local rng = Random.new(district.id:len() * 17 + math.floor((r.x0 + r.z0) / 3) + 42)

		-- Reserved areas: restaurant lot, zone pad, plaza.
		local reserved: { { number } } = {}
		for _, theme in Config.Plots do
			if theme.district == district.id then
				table.insert(reserved, { theme.position.X, theme.position.Z, 52 })
			end
		end
		table.insert(reserved, { district.zone.X, district.zone.Z, 22 })
		table.insert(reserved, { district.plaza.X, district.plaza.Z, 18 })

		-- Fill the block with a jittered grid of buildings + greenery.
		local margin = Config.City.RoadHalf + Config.City.SidewalkWidth + 2
		local x0, x1 = r.x0 + margin, r.x1 - margin
		local z0, z1 = r.z0 + margin, r.z1 - margin
		local cell = if district.style == "downtown" then 48 else 42
		local treeChance = if district.style == "suburbs" then 0.55 elseif district.style == "waterfront" then 0.1 else 0.3

		for gx = x0 + 10, x1 - 10, cell do
			for gz = z0 + 10, z1 - 10, cell do
				local cx = gx + rng:NextNumber(-4, 4)
				local cz = gz + rng:NextNumber(-4, 4)
				if not overlapsReserved(cx, cz, 20, 20, reserved) then
					if rng:NextNumber() < treeChance then
						if district.style == "waterfront" then
							ModelFactory.palm(world, CFrame.new(cx, 0.55, cz), rng)
						else
							ModelFactory.tree(world, CFrame.new(cx, 0.55, cz), rng)
						end
					else
						local w = if district.style == "industrial" then rng:NextNumber(26, 34) else rng:NextNumber(18, 26)
						local d = if district.style == "industrial" then rng:NextNumber(22, 30) else rng:NextNumber(18, 26)
						ModelFactory.building(district.style, world, CFrame.new(cx, 0.55, cz), w, d, rng)
					end
				end
			end
		end

		-- Plaza: district name sign + benches.
		local _, plazaSign = ModelFactory.infoSign(world, CFrame.new(district.plaza + Vector3.new(0, 4, 0)), Vector2.new(260, 70))
		plazaSign.Text = ("%s\n%s"):format(district.name, district.tagline)
		ModelFactory.bench(world, CFrame.new(district.plaza + Vector3.new(8, 0, 4)))
		ModelFactory.bench(world, CFrame.new(district.plaza + Vector3.new(-8, 0, 4)) * CFrame.Angles(0, math.rad(180), 0))
	end
end

local function buildSpawn(world: Model)
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Size = Vector3.new(14, 1, 14)
	spawnLocation.CFrame = CFrame.new(16, 0.9, -16)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Parent = world
	local _, sign = ModelFactory.infoSign(world, CFrame.new(16, 4, -26), Vector2.new(280, 60))
	sign.Text = "Pizza Tycoon City\nPick a district and start your empire!"
end

function CityMap.Init(ctx)
	ctx.Services.CityMap = CityMap
	Config = ctx.Config
	Net = ctx.Net

	local world = Instance.new("Model")
	world.Name = "PizzaTycoonWorld"
	CityMap.World = world

	buildGround(world)
	buildRoads(world)
	buildDistrictBuildings(world)
	buildSpawn(world)

	world.Parent = workspace
end

-- ===================== Runtime: teleports & map state =====================

function CityMap.Start(ctx)
	PlotManager = ctx.Services.PlotManager
	Traffic = ctx.Services.Traffic

	-- Fast travel from the city map.
	Net.TeleportRequest.OnServerEvent:Connect(function(player, districtId)
		if typeof(districtId) ~= "string" then
			return
		end
		local target = CityMap.TeleportCFrame(districtId)
		if not target then
			return
		end
		local character = player.Character
		if not character then
			return
		end
		character:PivotTo(target)
		local district = Config.City.Districts[districtId]
		Net.Announce:FireClient(player, ("Welcome to %s!"):format(district.name), district.mapColor)
	end)

	-- Broadcast minimap state every 2 seconds.
	task.spawn(function()
		while true do
			task.wait(2)
			local ok, err = pcall(function()
				local traffic = Traffic and Traffic.GetLevel() or 0.5
				local plots = if PlotManager then PlotManager.GetPlotsSummary() else {}
				local blips = {}
				for _, p in Players:GetPlayers() do
					local character = p.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					if root then
						table.insert(blips, { name = p.Name, x = root.Position.X, z = root.Position.Z })
					end
				end
				Net.CityState:FireAllClients({ traffic = traffic, plots = plots, players = blips })
			end)
			if not ok then
				warn("[PizzaTycoon] city state broadcast failed: " .. tostring(err))
			end
		end
	end)
end

return CityMap
