--!strict
-- EventManager: rotates random city-wide events (rush hour, festival,
-- thief hour, boom) that scale customer rates, prices, zone pots and
-- theft. The single active event is exposed to all other services.

local EventManager = {}

local Config, Net

local current: any = nil

local function pickRandomEvent()
	local keys = {}
	for id in Config.Events do
		table.insert(keys, id)
	end
	local id = keys[math.random(#keys)]
	return Config.Events[id]
end

local function startEvent(event)
	current = event
	Net.Announce:FireAllClients("EVENT: " .. event.name .. " - " .. event.announce, Color3.fromRGB(255, 230, 120))
end

local function endEvent(event)
	if current == event then
		current = nil
	end
	Net.Announce:FireAllClients("Event over: " .. event.name, Color3.fromRGB(180, 180, 180))
end

function EventManager.GetCurrent()
	return current
end

function EventManager.Init(ctx)
	ctx.Services.EventManager = EventManager
	Config = ctx.Config
	Net = ctx.Net
end

function EventManager.Start(_ctx)
	task.spawn(function()
		-- Stagger the first event so players can settle in.
		task.wait(90)
		while true do
			local event = pickRandomEvent()
			startEvent(event)
			task.wait(event.duration)
			endEvent(event)
			local cooldown = Config.EventMinInterval + math.random() * (Config.EventMaxInterval - Config.EventMinInterval)
			task.wait(cooldown)
		end
	end)
end

return EventManager
