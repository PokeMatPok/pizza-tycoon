--!strict
-- UIController: cash HUD, active event banner, announcements, leaderboard.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIController = {}

local Net, Config

local player = Players.LocalPlayer
local gui: ScreenGui
local cashLabel: TextLabel
local statsLabel: TextLabel
local announceLabel: TextLabel
local boardFrame: Frame

local function label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
	l.TextScaled = true
	for k, v in props do
		if k ~= "Parent" then
			(l :: any)[k] = v
		end
	end
	l.Parent = props.Parent
	return l
end

function UIController.Init(ctx)
	Net = ctx.Net
	Config = ctx.Config

	local playerGui = player:WaitForChild("PlayerGui")
	gui = Instance.new("ScreenGui")
	gui.Name = "PizzaTycoonHUD"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	-- Cash HUD (top center).
	local cashBox = Instance.new("Frame")
	cashBox.Size = UDim2.fromOffset(260, 54)
	cashBox.Position = UDim2.new(0.5, -130, 0, 12)
	cashBox.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	cashBox.BackgroundTransparency = 0.15
	cashBox.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = cashBox

	cashLabel = label({
		Size = UDim2.fromScale(0.55, 1),
		Position = UDim2.fromScale(0, 0),
		Text = "$0",
		TextColor3 = Color3.fromRGB(130, 255, 130),
		Parent = cashBox,
	})
	statsLabel = label({
		Size = UDim2.fromScale(0.45, 1),
		Position = UDim2.fromScale(0.55, 0),
		Text = "0 sold",
		TextColor3 = Color3.fromRGB(230, 230, 230),
		Parent = cashBox,
	})

	-- Announcement banner (top, below cash).
	announceLabel = Instance.new("TextLabel")
	announceLabel.Size = UDim2.new(0.7, 0, 0, 32)
	announceLabel.Position = UDim2.new(0.15, 0, 0, 72)
	announceLabel.BackgroundTransparency = 1
	announceLabel.Font = Enum.Font.GothamBold
	announceLabel.TextScaled = true
	announceLabel.Text = ""
	announceLabel.TextColor3 = Color3.new(1, 1, 1)
	announceLabel.TextStrokeTransparency = 0.2
	announceLabel.TextTransparency = 1
	announceLabel.Parent = gui

	-- Leaderboard (right side).
	boardFrame = Instance.new("Frame")
	boardFrame.Size = UDim2.fromOffset(230, 260)
	boardFrame.Position = UDim2.new(1, -246, 0, 12)
	boardFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	boardFrame.BackgroundTransparency = 0.15
	boardFrame.Parent = gui
	local boardCorner = Instance.new("UICorner")
	boardCorner.CornerRadius = UDim.new(0, 10)
	boardCorner.Parent = boardFrame
	local boardLayout = Instance.new("UIListLayout")
	boardLayout.Padding = UDim.new(0, 4)
	boardLayout.Parent = boardFrame
	label({
		Size = UDim2.new(1, 0, 0, 34),
		Text = "Top Pizzerias (revenue)",
		TextColor3 = Color3.fromRGB(255, 200, 90),
		Parent = boardFrame,
	})

	-- State sync.
	Net.StateChanged.OnClientEvent:Connect(function(state)
		UIController.OnState(state)
	end)

	Net.Announce.OnClientEvent:Connect(function(text, color)
		UIController.Announce(text, color)
	end)

	Net.LeaderboardUpdate.OnClientEvent:Connect(function(payload)
		UIController.OnLeaderboard(payload.entries)
	end)

	Net.ZoneUpdate.OnClientEvent:Connect(function(payload)
		local names = {}
		for _, payout in payload.payouts do
			table.insert(names, ("%s: $%d"):format(payout.name, payout.amount))
		end
		UIController.Announce(
			("%s paid out $%d! %s"):format(payload.zoneName, payload.pot, if #names > 0 then table.concat(names, ", ") else ""),
			Color3.fromRGB(150, 255, 150)
		)
	end)
end

function UIController.OnState(state)
	cashLabel.Text = "$" .. tostring(state.cash)
	statsLabel.Text = ("%d sold | %d ready"):format(state.totalPizzasSold, state.readyPizzas)
end

local announceToken = 0

function UIController.Announce(text, color)
	announceToken += 1
	local token = announceToken
	announceLabel.Text = text
	announceLabel.TextColor3 = color or Color3.new(1, 1, 1)
	announceLabel.TextTransparency = 0
	task.delay(4, function()
		if announceToken == token then
			TweenService:Create(announceLabel, TweenInfo.new(1), { TextTransparency = 1 }):Play()
		end
	end)
end

function UIController.OnLeaderboard(entries)
	for _, child in boardFrame:GetChildren() do
		if child:IsA("TextLabel") and child.Name == "Entry" then
			child:Destroy()
		end
	end
	for rank, entry in entries do
		local entryLabel = Instance.new("TextLabel")
		entryLabel.Name = "Entry"
		entryLabel.Size = UDim2.new(1, 0, 0, 22)
		entryLabel.BackgroundTransparency = 1
		entryLabel.Font = Enum.Font.Gotham
		entryLabel.TextScaled = true
		entryLabel.TextColor3 = if rank == 1 then Color3.fromRGB(255, 210, 90) else Color3.fromRGB(235, 235, 235)
		entryLabel.Text = ("#%d %s - $%d"):format(rank, entry.name, entry.revenue)
		entryLabel.Parent = boardFrame
	end
end

return UIController
