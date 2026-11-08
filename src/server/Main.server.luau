--!nonstrict
-- Bootstrap: requires all services, builds the shared context, then runs
-- Init (wiring) and Start (runtime loops) phases in deterministic order.
--
-- Paste-tolerant: finds the "services" folder wherever you put it
-- (child of Main, sibling of Main, any capitalization).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script

local servicesToLoad = {
	"services/ModelFactory",
	"services/DataManager",
	"services/Economy",
	"services/CityMap",
	"services/PlotManager",
	"services/Production",
	"services/OrderSystem",
	"services/DeliveryZones",
	"services/Pedestrians",
	"services/Traffic",
	"services/EventManager",
	"services/Leaderboards",
}

-- Case-insensitive child lookup on an instance.
local function findChildCI(parent: Instance, name: string): Instance?
	local direct = parent:FindFirstChild(name)
	if direct then
		return direct
	end
	local lower = string.lower(name)
	for _, child in parent:GetChildren() do
		if string.lower(child.Name) == lower then
			return child
		end
	end
	return nil
end

-- Resolve one path segment against a script AND its parent (folder), so
-- both "Main contains services" and "services sits next to Main" work.
local function resolveSegment(from: Instance, name: string): Instance?
	local inScript = findChildCI(from, name)
	if inScript then
		return inScript
	end
	if from.Parent then
		local inParent = findChildCI(from.Parent, name)
		if inParent then
			return inParent
		end
	end
	return nil
end

-- Resolve "a/b/c" style paths starting from the given root.
local function resolvePath(root: Instance, path: string): Instance?
	local node = root
	for _, segment in string.split(path, "/") do
		local nextNode = resolveSegment(node, segment)
		if not nextNode then
			return nil, ("%s (missing under %s)"):format(segment, node:GetFullName())
		end
		node = nextNode
	end
	return node
end

local ctx = {
	Config = require(ReplicatedStorage.Shared.Config),
	Net = require(ReplicatedStorage.Shared.Net),
	Services = {},
}

local modules = {}
local missing = {}
for _, path in servicesToLoad do
	local node = resolvePath(Server, path)
	if node and node:IsA("ModuleScript") then
		local mod = require(node)
		table.insert(modules, mod)
		-- Uniform registration: every module is available in ctx.Services
		-- under its script name (modules without an Init, like ModelFactory,
		-- rely on this instead of self-registering).
		ctx.Services[node.Name] = mod
	else
		table.insert(missing, if node then path .. " (not a ModuleScript)" else path)
	end
end

if #missing > 0 then
	warn("[PizzaTycoon] Could not load: " .. table.concat(missing, ", "))
	warn("[PizzaTycoon] Expected structure: Server folder containing Main (Script) + 'services' folder with 12 ModuleScripts (ModelFactory, DataManager, Economy, CityMap, PlotManager, Production, OrderSystem, DeliveryZones, Pedestrians, Traffic, EventManager, Leaderboards).")
end

-- Phase 1: Init. Services register themselves in ctx.Services and may
-- reference other services through ctx.Services (deferred), never via
-- direct requires.
for _, mod in modules do
	if mod.Init then
		mod.Init(ctx)
	end
end

-- Phase 2: Start. All cross-service references are guaranteed to exist now.
for _, mod in modules do
	if mod.Start then
		task.spawn(function()
			local ok, err = pcall(mod.Start, ctx)
			if not ok then
				warn(("[PizzaTycoon] Start failed: %s"):format(tostring(err)))
			end
		end)
	end
end

print("[PizzaTycoon] Server started with", #modules, "services")
