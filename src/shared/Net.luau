--!strict
-- Lightweight typed remote access. All remotes are created on the server
-- once at startup; clients wait for them.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local remoteNames = {
	-- RemoteEvents (server -> client)
	"StateChanged", -- full player state snapshot
	"Announce", -- {text, color?}
	"CashFloat", -- {position, amount} floating +$ effect
	"LeaderboardUpdate", -- {entries = {{name, revenue}}}
	"ZoneUpdate", -- {zoneId, contributions = {{playerName, amount}}}
	"CityState", -- minimap data: traffic level, plot owners, player blips
	-- RemoteEvents (client -> server)
	"TeleportRequest", -- districtId: fast travel from the city map
}

local folder: Folder

if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in remoteNames do
		local existing = folder:FindFirstChild(name)
		if not existing then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

setmetatable(Net, {
	__index = function(_self, name)
		assert(typeof(name) == "string", "remote name must be a string")
		return folder:FindFirstChild(name) or folder:WaitForChild(name)
	end,
})

return Net
