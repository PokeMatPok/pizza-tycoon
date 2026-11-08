--!strict
-- CityMap: builds the open world: ground, districts, road grid with
-- sidewalks, crosswalks, street lamps and traffic lights, low-poly
-- buildings per district style, parked cars, bus stops, hydrants,
-- bins, food carts, plazas with district signs, and the spawn plaza
-- with a fountain. Also serves map data to Traffic/Pedestrians
-- (road + sidewalk loops), handles minimap fast travel and broadcasts
-- CityState (traffic level, plot owners, blips).

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
	-- The grand outer ring (road) + two big cross loops, so cars also
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
	local RoadsX = Config.City.RoadsX
	local RoadsZ = Config.City.RoadsZ

	-- Road slabs. Vertical roads sit a hair above horizontal ones so
	-- overlapping intersections don't z-fight.
	for _, x in RoadsX do
		ModelFactory.basePart({
			Name = "Road",
			Size = Vector3.new(rh * 2, 0.2, half * 2),
			Color = Color3.fromRGB(52, 52, 56),
			Material = Enum.Material.Asphalt,
			CFrame = CFrame.new(x, 0.6, 0),
			Parent = world,
		})
	end
	for _, z in RoadsZ do
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
	for _, x in RoadsX do
		for z = -half + 14, half - 14, 14 do
			if not nearAny(z, RoadsZ, rh + 8) then
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
	for _, z in RoadsZ do
		for x = -half + 14, half - 14, 14 do
			if not nearAny(x, RoadsX, rh + 8) then
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
	for _, x in RoadsX do
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
	for _, z in RoadsZ do
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

	-- Zebra crosswalks at every intersection: two crossings per road
	-- arm, 4 stripes each.
	local stripeOffsets = { -5.4, -1.8, 1.8, 5.4 }
	for _, ix in RoadsX do
		for _, iz in RoadsZ do
			-- Crossings over the vertical road (north & south arms):
			-- stripes run along Z, spread across X.
			for _, arm in { -1, 1 } do
				for _, off in stripeOffsets do
					ModelFactory.basePart({
						Name = "Crosswalk",
						Size = Vector3.new(2.2, 0.2, 5),
						Color = Color3.fromRGB(225, 225, 225),
						Material = Enum.Material.SmoothPlastic,
						CanCollide = false,
						CFrame = CFrame.new(ix + off, 0.75, iz + arm * (rh + 3)),
						Parent = world,
					})
				end
			end
			-- Crossings over the horizontal road (east & west arms):
			-- stripes run along X, spread across Z.
			for _, arm in { -1, 1 } do
				for _, off in stripeOffsets do
					ModelFactory.basePart({
						Name = "Crosswalk",
						Size = Vector3.new(5, 0.2, 2.2),
						Color = Color3.fromRGB(225, 225, 225),
						Material = Enum.Material.SmoothPlastic,
						CanCollide = false,
						CFrame = CFrame.new(ix + arm * (rh + 3), 0.74, iz + off),
						Parent = world,
					})
				end
			end
		end
	end

	-- Street lamps along roads, arm reaching over the road.
	for _, x in RoadsX do
		for z = -half + 30, half - 30, 44 do
			if not nearAny(z, RoadsZ, rh + 10) then
				local lx = x + rh + sw / 2
				ModelFactory.lamp(world, CFrame.lookAt(Vector3.new(lx, 0.9, z), Vector3.new(x, 0.9, z)))
			end
		end
	end
	for _, z in RoadsZ do
		for x = -half + 30, half - 30, 44 do
			if not nearAny(x, RoadsX, rh + 10) then
				local lz = z + rh + sw / 2
				ModelFactory.lamp(world, CFrame.lookAt(Vector3.new(x, 0.9, lz), Vector3.new(x, 0.9, z)))
			end
		end
	end

	-- Traffic lights at the inner intersections (two masts on diagonal
	-- corners, heads facing the crossing).
	for _, ix in { RoadsX[2], RoadsX[3] } do
		for _, iz in RoadsZ do
			for _, corner in { { 12, 12 }, { -12, -12 } } do
				local px, pz = ix + corner[1], iz + corner[2]
				ModelFactory.trafficLight(world, CFrame.lookAt(Vector3.new(px, 0.9, pz), Vector3.new(ix, 0.9, iz)))
			end
			-- Hydrant and trash bin fill the other two corners.
			ModelFactory.hydrant(world, CFrame.new(ix + 12, 0.9, iz - 12))
			ModelFactory.trashBin(world, CFrame.new(ix - 12, 0.9, iz + 12))
		end
	end

	-- Parked cars along the curbs (static dressing).
	local parked = {
		{ 7, -150, 0 }, { -7, -90, 180 }, { 7, 90, 180 }, { -7, 150, 0 },
		{ 103, -150, 0 }, { 117, 150, 180 },
		{ -213, -100, 0 }, { -227, 100, 180 },
		{ -150, 7, 90 }, { -60, -7, -90 }, { 60, 7, 90 }, { 150, -7, -90 },
		{ -150, 213, 90 }, { 60, 227, -90 },
	}
	local parkedColors = {
		Color3.fromRGB(200, 60, 50), Color3.fromRGB(70, 110, 200), Color3.fromRGB(230, 220, 210),
		Color3.fromRGB(40, 40, 45), Color3.fromRGB(90, 180, 120), Color3.fromRGB(220, 160, 40),
	}
	for i, spot in parked do
		local color = parkedColors[(i % #parkedColors) + 1]
		ModelFactory.car(color, world, CFrame.new(spot[1], 0.7, spot[2]) * CFrame.Angles(0, math.rad(spot[3]), 0))
	end

	-- Bus stops on sidewalks facing their road.
	ModelFactory.busStop(world, CFrame.lookAt(Vector3.new(12.5, 0.9, 60), Vector3.new(0, 0.9, 60)))
	ModelFactory.busStop(world, CFrame.lookAt(Vector3.new(-12.5, 0.9, -90), Vector3.new(0, 0.9, -90)))
	ModelFactory.busStop(world, CFrame.lookAt(Vector3.new(60, 0.9, -12.5), Vector3.new(60, 0.9, 0)))
	ModelFactory.busStop(world, CFrame.lookAt(Vector3.new(-60, 0.9, 12.5), Vector3.new(-60, 0.9, 0)))
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
				table.insert(reserved, { theme.position.X, theme.position.Z, 62 })
			end
		end
		table.insert(reserved, { district.zone.X, district.zone.Z, 26 })
		table.insert(reserved, { district.plaza.X, district.plaza.Z, 24 })

		-- Fill the block with a jittered grid of buildings + greenery.
		-- Real scale: buildings are large relative to the 5-stud avatar,
		-- and dense enough that you can't see through a block to the
		-- parallel streets: main buildings nearly fill their cell, and a
		-- second infill pass drops mid-size buildings between the columns.
		local margin = Config.City.RoadHalf + Config.City.SidewalkWidth + 2
		local x0, x1 = r.x0 + margin, r.x1 - margin
		local z0, z1 = r.z0 + margin, r.z1 - margin
		local cell = if district.style == "downtown" then 66 elseif district.style == "industrial" then 60 else 56
		local treeChance = if district.style == "suburbs" then 0.45 elseif district.style == "waterfront" then 0.12 else 0.2

		local style = district.style

		local function mainSize(): (number, number)
			if style == "downtown" then
				return rng:NextNumber(40, 52), rng:NextNumber(34, 46)
			elseif style == "industrial" then
				return rng:NextNumber(40, 48), rng:NextNumber(30, 40)
			elseif style == "oldtown" then
				return rng:NextNumber(34, 42), rng:NextNumber(28, 36)
			elseif style == "suburbs" then
				return rng:NextNumber(30, 38), rng:NextNumber(26, 32)
			end
			return rng:NextNumber(26, 34), rng:NextNumber(22, 28)
		end

		local function infillSize(): (number, number)
			if style == "downtown" then
				return rng:NextNumber(18, 28), rng:NextNumber(16, 26)
			elseif style == "industrial" then
				return rng:NextNumber(26, 36), rng:NextNumber(22, 30)
			elseif style == "oldtown" then
				return rng:NextNumber(16, 26), rng:NextNumber(14, 22)
			elseif style == "suburbs" then
				return rng:NextNumber(16, 24), rng:NextNumber(14, 20)
			end
			return rng:NextNumber(12, 20), rng:NextNumber(10, 16)
		end

		-- Placed rects (buildings, trees) so infill never merges into
		-- something already standing.
		local placed: { { number } } = {}
		local function overlapsPlaced(cx: number, cz: number, hx: number, hz: number): boolean
			for _, p in placed do
				if math.abs(cx - p[1]) < hx + p[3] and math.abs(cz - p[2]) < hz + p[4] then
					return true
				end
			end
			return false
		end

		local function placeTree(cx: number, cz: number)
			if style == "waterfront" then
				ModelFactory.palm(world, CFrame.new(cx, 0.1, cz), rng)
			else
				ModelFactory.tree(world, CFrame.new(cx, 0.1, cz), rng)
			end
			table.insert(placed, { cx, cz, 5, 5 })
		end

		-- Main grid pass.
		for gx = x0 + 14, x1 - 14, cell do
			for gz = z0 + 14, z1 - 14, cell do
				local w, d = mainSize()
				-- Jitter, clamped so the building stays inside the block.
				local cx = math.clamp(gx + rng:NextNumber(-5, 5), x0 + w / 2 + 1, x1 - w / 2 - 1)
				local cz = math.clamp(gz + rng:NextNumber(-5, 5), z0 + d / 2 + 1, z1 - d / 2 - 1)
				if not overlapsReserved(cx, cz, w / 2 + 2, d / 2 + 2, reserved) then
					if rng:NextNumber() < treeChance then
						placeTree(cx, cz)
					else
						ModelFactory.building(style, world, CFrame.new(cx, 0.1, cz), w, d, rng)
						table.insert(placed, { cx, cz, w / 2 + 2, d / 2 + 2 })
					end
				end
			end
		end

		-- Infill pass: mid-size buildings between the grid columns.
		local infillChance = if style == "suburbs" then 0.5 elseif style == "industrial" then 0.65 else 0.85
		for gx = x0 + 14 + cell / 2, x1 - 14, cell do
			for gz = z0 + 14 + cell / 2, z1 - 14, cell do
				local w, d = infillSize()
				local cx = math.clamp(gx + rng:NextNumber(-4, 4), x0 + w / 2 + 1, x1 - w / 2 - 1)
				local cz = math.clamp(gz + rng:NextNumber(-4, 4), z0 + d / 2 + 1, z1 - d / 2 - 1)
				if not overlapsReserved(cx, cz, w / 2 + 2, d / 2 + 2, reserved)
					and not overlapsPlaced(cx, cz, w / 2 + 3, d / 2 + 3) then
					if rng:NextNumber() < infillChance then
						ModelFactory.building(style, world, CFrame.new(cx, 0.1, cz), w, d, rng)
						table.insert(placed, { cx, cz, w / 2 + 2, d / 2 + 2 })
					elseif rng:NextNumber() < treeChance then
						placeTree(cx, cz)
					end
				end
			end
		end

		-- Plaza: district name sign + benches + a patio set.
		local _, plazaSign = ModelFactory.infoSign(world, CFrame.new(district.plaza + Vector3.new(0, 4, 0)), Vector2.new(260, 70))
		plazaSign.Text = ("%s\n%s"):format(district.name, district.tagline)
		ModelFactory.bench(world, CFrame.new(district.plaza + Vector3.new(8, 0.5, 4)))
		ModelFactory.bench(world, CFrame.new(district.plaza + Vector3.new(-8, 0.5, 4)) * CFrame.Angles(0, math.rad(180), 0))
		ModelFactory.tableSet(world, CFrame.new(district.plaza + Vector3.new(10, 0.5, -8)), district.mapColor)
		ModelFactory.umbrella(world, CFrame.new(district.plaza + Vector3.new(10, 0.5, -8)), district.mapColor)
		if district.style == "oldtown" or district.style == "waterfront" then
			ModelFactory.foodCart(world, CFrame.new(district.plaza + Vector3.new(-14, 0.5, 10)) * CFrame.Angles(0, math.rad(90), 0), district.mapColor)
		end
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

	-- A small plaza south of spawn: fountain, patio tables, food cart.
	ModelFactory.fountain(world, CFrame.new(16, 0.1, -50))
	ModelFactory.tableSet(world, CFrame.new(30, 0.1, -44), Color3.fromRGB(240, 150, 60))
	ModelFactory.umbrella(world, CFrame.new(30, 0.1, -44), Color3.fromRGB(240, 150, 60))
	ModelFactory.tableSet(world, CFrame.new(2, 0.1, -66), Color3.fromRGB(240, 150, 60))
	ModelFactory.umbrella(world, CFrame.new(2, 0.1, -66), Color3.fromRGB(240, 150, 60))
	ModelFactory.foodCart(world, CFrame.new(34, 0.1, -30) * CFrame.Angles(0, math.rad(180), 0), Color3.fromRGB(240, 150, 60))
	ModelFactory.bench(world, CFrame.new(4, 0.1, -50) * CFrame.Angles(0, math.rad(90), 0))
	ModelFactory.bench(world, CFrame.new(28, 0.1, -56) * CFrame.Angles(0, math.rad(270), 0))
end

function CityMap.Init(ctx)
	ctx.Services.CityMap = CityMap
	Config = ctx.Config
	Net = ctx.Net
	ModelFactory = ctx.Services.ModelFactory

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
