--!strict
-- Pedestrians: blocky NPCs strolling the sidewalks. Like cars, they only
-- exist near players and despawn when nobody is around. Density follows
-- the same slow rush-hour wave (scaled per district and event), and
-- walkers occasionally pause to look around. Clothing matches district
-- style: suits downtown, workers in Foundry Flats, tourists at the bay.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Pedestrians = {}

local Config, Net
local CityMap, ModelFactory, EventManager

type Ped = {
	model: Model,
	loop: any,
	dir: number,
	t: number,
	speed: number,
	pause: number, -- seconds remaining paused
}

local peds: { Ped } = {}
local level = 0.5
local currentEvent

local SKINS = {
	Color3.fromRGB(255, 205, 160),
	Color3.fromRGB(235, 190, 150),
	Color3.fromRGB(200, 150, 110),
	Color3.fromRGB(160, 110, 75),
}

local PANTS = {
	Color3.fromRGB(45, 45, 60),
	Color3.fromRGB(70, 70, 80),
	Color3.fromRGB(90, 70, 55),
	Color3.fromRGB(35, 60, 90),
}

local SHIRTS = {
	downtown = { Color3.fromRGB(40, 40, 48), Color3.fromRGB(60, 70, 110), Color3.fromRGB(200, 200, 205), Color3.fromRGB(120, 60, 70) },
	oldtown = { Color3.fromRGB(180, 90, 70), Color3.fromRGB(150, 120, 90), Color3.fromRGB(100, 130, 170), Color3.fromRGB(200, 170, 90) },
	suburbs = { Color3.fromRGB(120, 170, 210), Color3.fromRGB(210, 130, 150), Color3.fromRGB(130, 200, 140), Color3.fromRGB(230, 210, 140) },
	industrial = { Color3.fromRGB(230, 140, 40), Color3.fromRGB(200, 200, 60), Color3.fromRGB(120, 70, 50), Color3.fromRGB(90, 95, 100) },
	waterfront = { Color3.fromRGB(255, 120, 90), Color3.fromRGB(80, 200, 190), Color3.fromRGB(255, 200, 90), Color3.fromRGB(150, 190, 240) },
}

local rng = Random.new()

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

local function spawnPed()
	local loops = CityMap.GetSidewalkLoops()
	local players = Players:GetPlayers()
	if #players == 0 or #loops == 0 then
		return
	end
	local player = players[rng:NextInteger(1, #players)]
	local spawnR = Config.City.Peds.SpawnRadius
	for _ = 1, 8 do
		local loop = loops[rng:NextInteger(1, #loops)]
		local t = rng:NextNumber(0, loop.perim)
		local dir = if rng:NextNumber() < 0.5 then 1 else -1
		local pos, heading = loopPoint(loop, if dir == 1 then t else loop.perim - t)
		local district = CityMap.GetDistrictAt(pos)
		if district and rng:NextNumber() > district.pedMult * 0.6 then
			continue
		end
		if nearestPlayerDistance(pos) > spawnR then
			continue
		end
		local style = if district then district.style else "suburbs"
		local shirts = SHIRTS[style] or SHIRTS.suburbs
		local cf = CFrame.lookAt(pos + Vector3.new(0, 0.9, 0), pos + heading + Vector3.new(0, 0.9, 0))
		local model = ModelFactory.pedestrian(
			shirts[rng:NextInteger(1, #shirts)],
			PANTS[rng:NextInteger(1, #PANTS)],
			SKINS[rng:NextInteger(1, #SKINS)],
			workspace.PizzaTycoonWorld,
			cf
		)
		table.insert(peds, {
			model = model,
			loop = loop,
			dir = dir,
			t = t,
			speed = Config.City.Peds.WalkSpeed * rng:NextNumber(0.8, 1.25),
			pause = 0,
		})
		return
	end
end

local function despawnFarPeds()
	local despawnR = Config.City.Peds.DespawnRadius
	for i = #peds, 1, -1 do
		local ped = peds[i]
		if nearestPlayerDistance(ped.model:GetPivot().Position) > despawnR then
			ped.model:Destroy()
			table.remove(peds, i)
		end
	end
end

function Pedestrians.GetLevel(): number
	return level
end

function Pedestrians.Init(ctx)
	ctx.Services.Pedestrians = Pedestrians
	Config = ctx.Config
	Net = ctx.Net
	CityMap = ctx.Services.CityMap
	ModelFactory = ctx.Services.ModelFactory
	EventManager = ctx.Services.EventManager
end

function Pedestrians.Start(ctx)
	EventManager = ctx.Services.EventManager

	task.spawn(function()
		while true do
			task.wait(1)
			local t = os.clock() / Config.City.Traffic.Period
			local wave = 0.5 - 0.5 * math.cos(2 * math.pi * t)
			local eventMult = if currentEvent and currentEvent.pedMult then currentEvent.pedMult else 1
			level = math.clamp((Config.City.Traffic.MinLevel + (1 - Config.City.Traffic.MinLevel) * wave) * eventMult, 0, 1)
			currentEvent = EventManager.GetCurrent()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1.5)
			local target = math.floor(level * Config.City.Peds.MaxPeds + 0.5)
			despawnFarPeds()
			if #peds < target then
				spawnPed()
			elseif #peds > target + 3 then
				local ped = table.remove(peds, #peds)
				ped.model:Destroy()
			end
		end
	end)

	local step = 1 / Config.City.Traffic.UpdateHz
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < step then
			return
		end
		local d = acc
		acc = 0
		for _, ped in peds do
			if ped.pause > 0 then
				ped.pause -= d
				continue
			end
			ped.t = (ped.t + ped.dir * ped.speed * d) % ped.loop.perim
			if rng:NextNumber() < Config.City.Peds.IdleChance * d then
				ped.pause = rng:NextNumber(0.8, 2.5)
			end
			local pos, heading = loopPoint(ped.loop, if ped.dir == 1 then ped.t else ped.loop.perim - ped.t)
			local world = pos + Vector3.new(0, 0.9, 0)
			if ped.model.Parent then
				ped.model:PivotTo(CFrame.lookAt(world, world + heading))
			end
		end
	end)
end

return Pedestrians
