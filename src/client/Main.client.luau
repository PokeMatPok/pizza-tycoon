--!nonstrict
-- Client entry point: builds the HUD, announcement banner, leaderboard,
-- and hooks up the floating-cash effect.
--
-- Paste-tolerant: finds the "controllers" folder wherever you put it
-- (child of Main, sibling of Main, any capitalization).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Client = script

local modules = {
	"controllers/UIController",
	"controllers/EffectsController",
	"controllers/CityMapController",
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

-- Resolve one path segment against a script AND its parent (folder).
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
	Controllers = {},
}

local loaded = {}
for _, path in modules do
	local node = resolvePath(Client, path)
	if node and node:IsA("ModuleScript") then
		local mod = require(node)
		table.insert(loaded, mod)
	else
		warn(("[PizzaTycoon] Client could not load %s"):format(if node then path .. " (not a ModuleScript)" else path))
	end
end

for _, mod in loaded do
	mod.Init(ctx)
	table.insert(ctx.Controllers, mod)
end

for _, mod in ctx.Controllers do
	if mod.Start then
		task.spawn(mod.Start, ctx)
	end
end

print("[PizzaTycoon] Client started with", #ctx.Controllers, "controllers")
