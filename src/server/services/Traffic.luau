--!strict
-- Traffic: low-poly cars driving the road grid. Cars spawn only near
-- players (visibility culling) and despawn when nobody is nearby.
-- Density rises and falls in a slow wave over time (rush hours) and is
-- boosted by city events. Movement is server-side at a capped update
-- rate to keep replication cheap.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Traffic = {}

local Config, Net
local CityMap, ModelFactory, EventManager

type Car = {
	model: Model,
	loop: any,
	dir: number, -- 1 = clockwise, -1 = counter-clockwise
	t: number, -- distance along the loop perimeter
	speed: number,
}

local cars: { Car } = {}
local level = 0.5
local currentEvent

local CAR_COLORS = {
	Color3.fromRGB(220, 70, 60),
	Color3.fromRGB(60, 110, 200),
	Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(40, 40, 45),
	Color3.fromRGB(90, 160, 90),
	Color3.fromRGB(230, 170, 40),
	Color3.fromRGB(150, 150, 160),
	Color3.fromRGB(120, 80, 160),
}

-- Map a perimeter distance to a position + heading on a rect loop.
local function loopPoint(l, dist: number): (Vector3, Vector3)
	local W = l.x1 - l.x0
	local H = l.z1 - l.z0
	local t = dist % l.perim
	if t < 0 then
		t += l.perim
	end
	if t < W then
		return Vector3.new(l.x0 + t, 0, l.z0), Vector3.new(1, 0, 0)
	elseif t < W + H then
		return Vector3.new(l.x1, 0, l.z0 + (t - W)), Vector3.new(0, 0, 1)
	elseif t < 2 * W + H then
		return Vector3.new(l.x1 - (t - W - H), 0, l.z1), Vector3.new(-1, 0, 0)
	else
		return Vector3.new(l.x0, 0, l.z1 - (t - 2 * W - H)), Vector3.new(0, 0, -1)
	end
end

function Traffic.GetLevel(): number
	return level
end

local function nearestPlayerDistance(pos: Vector3): number
	local best = math.huge
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (root.Position - pos).Magnitude
			if d < best then
				best = d
			end
		end
	end
	return best
end

local rng = Random.new()

local function spawnCar()
	local loops = CityMap.GetRoadLoops()
	local players = Players:GetPlayers()
	if #players == 0 or #loops == 0 then
		return
	end
	local player = players[rng:NextInteger(1, #players)]
	local spawnR = Config.City.Traffic.SpawnRadius
	for _ = 1, 8 do
		local loop = loops[rng:NextInteger(1, #loops)]
		local t = rng:NextNumber(0, loop.perim)
		local dir = if rng:NextNumber() < 0.5 then 1 else -1
		local pos, heading = loopPoint(loop, dir == 1 and t or loop.perim - t)
		local district = CityMap.GetDistrictAt(pos)
		-- Some districts are calmer than others.
		if district and rng:NextNumber() > district.carMult * 0.6 then
			continue
		end
		if nearestPlayerDistance(pos) > spawnR then
			continue
		end
		local right = Vector3.new(-heading.Z, 0, heading.X)
		local cf = CFrame.lookAt(pos + right * Config.City.Traffic.LaneOffset + Vector3.new(0, 0.7, 0), pos + right * Config.City.Traffic.LaneOffset + heading)
		local model = ModelFactory.car(CAR_COLORS[rng:NextInteger(1, #CAR_COLORS)], workspace.PizzaTycoonWorld, cf)
		table.insert(cars, {
			model = model,
			loop = loop,
			dir = dir,
			t = t,
			speed = Config.City.Traffic.CarSpeed * rng:NextNumber(0.85, 1.15),
		})
		return
	end
end

local function despawnFarCars()
	local despawnR = Config.City.Traffic.DespawnRadius
	for i = #cars, 1, -1 do
		local car = cars[i]
		local pos = car.model:GetPivot().Position
		if nearestPlayerDistance(pos) > despawnR then
			car.model:Destroy()
			table.remove(cars, i)
		end
	end
end

function Traffic.Init(ctx)
	ctx.Services.Traffic = Traffic
	Config = ctx.Config
	Net = ctx.Net
	CityMap = ctx.Services.CityMap
	ModelFactory = ctx.Services.ModelFactory
	EventManager = ctx.Services.EventManager
end

function Traffic.Start(ctx)
	EventManager = ctx.Services.EventManager

	-- Density wave: quiet <-> busy over the configured period, nudged by
	-- the active city event.
	task.spawn(function()
		while true do
			task.wait(1)
			local t = os.clock() / Config.City.Traffic.Period
			local wave = 0.5 - 0.5 * math.cos(2 * math.pi * t)
			local eventMult = if currentEvent and currentEvent.carMult then currentEvent.carMult else 1
			level = math.clamp((Config.City.Traffic.MinLevel + (1 - Config.City.Traffic.MinLevel) * wave) * eventMult, 0, 1)
			currentEvent = EventManager.GetCurrent()
		end
	end)

	-- Spawn/despawn management.
	task.spawn(function()
		while true do
			task.wait(1.5)
			local target = math.floor(level * Config.City.Traffic.MaxCars + 0.5)
			despawnFarCars()
			if #cars < target then
				spawnCar()
			elseif #cars > target + 3 then
				local car = table.remove(cars, #cars)
				car.model:Destroy()
			end
		end
	end)

	-- Movement stepping at a capped rate.
	local step = 1 / Config.City.Traffic.UpdateHz
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < step then
			return
		end
		local d = acc
		acc = 0
		for _, car in cars do
			car.t = (car.t + car.dir * car.speed * d) % car.loop.perim
			local pos, heading = loopPoint(car.loop, if car.dir == 1 then car.t else car.loop.perim - car.t)
			local right = Vector3.new(-heading.Z, 0, heading.X)
			local lane = right * Config.City.Traffic.LaneOffset
			-- Ground point on the road surface (top = y 0.7). The car
			-- model's pivot is its body center, 1.6 studs above the
			-- ground-contact frame, so lift the pivot target accordingly.
			local world = pos + lane + Vector3.new(0, 0.7, 0)
			if car.model.Parent then
				car.model:PivotTo(CFrame.lookAt(world, world + heading) * CFrame.new(0, 1.6, 0))
			end
		end
	end)
end

return Traffic
