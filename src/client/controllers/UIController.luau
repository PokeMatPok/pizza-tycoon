--!strict
-- UIController: cash HUD, announcements (toast), leaderboard.
-- Web-standard styling: dark surface tokens, 14px card radii,
-- hairline strokes, a clear type hierarchy and smooth tweens.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIController = {}

local Net, Config

local player = Players.LocalPlayer

-- ===================== Design tokens =====================
local COLOR = {
	surface = Color3.fromRGB(19, 19, 26), -- panel background
	surfaceHi = Color3.fromRGB(26, 26, 35), -- hover / row highlight
	text = Color3.fromRGB(245, 245, 247),
	muted = Color3.fromRGB(154, 158, 168),
	money = Color3.fromRGB(74, 222, 128),
	accent = Color3.fromRGB(245, 158, 11),
	accent2 = Color3.fromRGB(239, 68, 68),
	gold = Color3.fromRGB(250, 204, 21),
	silver = Color3.fromRGB(203, 213, 225),
	bronze = Color3.fromRGB(217, 119, 6),
}
local RADIUS_CARD = UDim.new(0, 14)
local RADIUS_PILL = UDim.new(1, 0)

local gui: ScreenGui
local cashLabel: TextLabel
local statsLabel: TextLabel
local toast: Frame
local toastBar: Frame
local toastLabel: TextLabel
local boardFrame: Frame
local boardList: Frame

-- Rounded card with hairline stroke, like a web surface component.
local function card(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor = COLOR.surface
	f.BackgroundTransparency = 0.06
	f.BorderSizePixel = 0
	for k, v in props do
		if k ~= "Parent" then
			(f :: any)[k] = v
		end
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = RADIUS_CARD
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.92
	stroke.Parent = f
	f.Parent = props.Parent
	return f
end

local function textLabel(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextColor3 = COLOR.text
	l.TextSize = 14
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
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
	gui.IgnoreGuiInset = false
	gui.Parent = playerGui

	-- ============ Cash card (top center) ============
	local cashCard = card({
		Name = "CashCard",
		Size = UDim2.fromOffset(330, 64),
		Position = UDim2.new(0.5, -165, 0, 14),
		Parent = gui,
	})
	-- Accent icon chip.
	local icon = Instance.new("Frame")
	icon.Size = UDim2.fromOffset(38, 38)
	icon.Position = UDim2.fromOffset(13, 13)
	icon.BackgroundColor3 = COLOR.accent
	icon.BorderSizePixel = 0
	icon.Parent = cashCard
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = RADIUS_PILL
	iconCorner.Parent = icon
	local iconGradient = Instance.new("UIGradient")
	iconGradient.Rotation = 45
	iconGradient.Color = ColorSequence.new(COLOR.accent, COLOR.accent2)
	iconGradient.Parent = icon
	textLabel({
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		Text = "$",
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = icon,
	})
	-- Cash amount + stats, stacked like a web stat card.
	cashLabel = textLabel({
		Name = "Cash",
		Size = UDim2.new(1, -70, 0, 30),
		Position = UDim2.fromOffset(62, 10),
		Text = "$0",
		Font = Enum.Font.GothamBold,
		TextSize = 24,
		TextColor3 = COLOR.money,
		Parent = cashCard,
	})
	statsLabel = textLabel({
		Name = "Stats",
		Size = UDim2.new(1, -70, 0, 16),
		Position = UDim2.fromOffset(62, 39),
		Text = "0 sold  ·  0 ready",
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = COLOR.muted,
		Parent = cashCard,
	})

	-- ============ Announcement toast ============
	toast = card({
		Name = "Toast",
		Size = UDim2.new(0.6, 0, 0, 40),
		Position = UDim2.new(0.2, 0, 0, 92),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local toastCorner = toast:FindFirstChildOfClass("UICorner")
	if toastCorner then
		toastCorner.CornerRadius = RADIUS_PILL
	end
	toastBar = Instance.new("Frame")
	toastBar.Size = UDim2.fromOffset(5, 22)
	toastBar.Position = UDim2.fromOffset(14, 9)
	toastBar.BackgroundColor3 = COLOR.accent
	toastBar.BorderSizePixel = 0
	toastBar.Parent = toast
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = RADIUS_PILL
	barCorner.Parent = toastBar
	toastLabel = textLabel({
		Name = "Text",
		Size = UDim2.new(1, -40, 1, 0),
		Position = UDim2.fromOffset(32, 0),
		Text = "",
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextColor3 = COLOR.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		Parent = toast,
	})

	-- ============ Leaderboard card (right side) ============
	local boardCard = card({
		Name = "Leaderboard",
		Size = UDim2.fromOffset(252, 320),
		Position = UDim2.new(1, -268, 0, 14),
		Parent = gui,
	})
	textLabel({
		Name = "Title",
		Size = UDim2.new(1, -32, 0, 20),
		Position = UDim2.fromOffset(16, 14),
		Text = "Leaderboard",
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		Parent = boardCard,
	})
	textLabel({
		Name = "Caption",
		Size = UDim2.new(1, -32, 0, 14),
		Position = UDim2.fromOffset(16, 35),
		Text = "pizzerias by revenue",
		TextSize = 12,
		TextColor3 = COLOR.muted,
		Parent = boardCard,
	})
	local rule = Instance.new("Frame")
	rule.Size = UDim2.new(1, -32, 0, 1)
	rule.Position = UDim2.fromOffset(16, 58)
	rule.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	rule.BackgroundTransparency = 0.94
	rule.BorderSizePixel = 0
	rule.Parent = boardCard
	boardFrame = boardCard
	boardList = Instance.new("Frame")
	boardList.Name = "List"
	boardList.Size = UDim2.new(1, -32, 1, -70)
	boardList.Position = UDim2.fromOffset(16, 66)
	boardList.BackgroundTransparency = 1
	boardList.Parent = boardCard
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = boardList

	-- ============ State sync ============
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
	-- Count-up tween on the cash number, like a web dashboard counter.
	local target = tonumber(state.cash) or 0
	local shown = tonumber((cashLabel.Text:gsub("[%$%,]", "")), 10) or 0
	if target ~= shown then
		local number = Instance.new("NumberValue")
		number.Value = shown
		local conn = number.Changed:Connect(function(v)
			cashLabel.Text = "$" .. tostring(math.floor(v + 0.5))
		end)
		local tween = TweenService:Create(number, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })
		tween.Completed:Connect(function()
			conn:Disconnect()
			number:Destroy()
			cashLabel.Text = "$" .. tostring(target)
		end)
		tween:Play()
	end
	statsLabel.Text = ("%d sold  ·  %d ready"):format(state.totalPizzasSold, state.readyPizzas)
end

local announceToken = 0

function UIController.Announce(text, color)
	announceToken += 1
	local token = announceToken
	toastLabel.Text = text
	toastLabel.TextColor3 = color or COLOR.text
	toastBar.BackgroundColor3 = color or COLOR.accent
	toastLabel.TextTransparency = 0
	toast.BackgroundTransparency = 0.06
	for _, stroke in toast:GetChildren() do
		if stroke:IsA("UIStroke") then
			stroke.Transparency = 0.92
		end
	end
	toastBar.BackgroundTransparency = 0
	-- Slide down + fade in.
	toast.Position = UDim2.new(0.2, 0, 0, 82)
	TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0.2, 0, 0, 92) }):Play()
	task.delay(4, function()
		if announceToken == token then
			local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(toastLabel, info, { TextTransparency = 1 }):Play()
			TweenService:Create(toast, info, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(toastBar, info, { BackgroundTransparency = 1 }):Play()
			for _, stroke in toast:GetChildren() do
				if stroke:IsA("UIStroke") then
					TweenService:Create(stroke, info, { Transparency = 1 }):Play()
				end
			end
		end
	end)
end

function UIController.OnLeaderboard(entries)
	for _, child in boardList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for rank, entry in entries do
		local row = Instance.new("Frame")
		row.Name = "Entry"
		row.Size = UDim2.new(1, 0, 0, 26)
		row.BackgroundTransparency = 1
		row.Parent = boardList

		-- Rank chip (gold / silver / bronze for the podium).
		local chip = Instance.new("Frame")
		chip.Size = UDim2.fromOffset(22, 22)
		chip.Position = UDim2.fromOffset(0, 2)
		chip.BackgroundColor3 = if rank == 1 then COLOR.gold elseif rank == 2 then COLOR.silver elseif rank == 3 then COLOR.bronze else COLOR.surfaceHi
		chip.BorderSizePixel = 0
		chip.Parent = row
		local chipCorner = Instance.new("UICorner")
		chipCorner.CornerRadius = RADIUS_PILL
		chipCorner.Parent = chip
		textLabel({
			Size = UDim2.fromScale(1, 1),
			Text = tostring(rank),
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = if rank <= 3 then Color3.fromRGB(30, 30, 30) else COLOR.muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = chip,
		})

		textLabel({
			Size = UDim2.new(1, -100, 1, 0),
			Position = UDim2.fromOffset(30, 0),
			Text = entry.name,
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
		textLabel({
			Size = UDim2.fromOffset(70, 1),
			Position = UDim2.new(1, -70, 0, 0),
			Text = "$" .. tostring(entry.revenue),
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = if rank == 1 then COLOR.gold else COLOR.money,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
	end
end

return UIController
