--!strict
-- CityMapController: the CITY MAP button on the right edge opens a live
-- city map: color-coded districts, roads, delivery zones, restaurant
-- plots, your dot and other players' blips. Click a district for its
-- traits and zone pot, then fast travel. Styled like a modern web app
-- panel: header bar, traffic pill, hover states, hero-banded sidebar
-- card and a clear primary CTA.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CityMapController = {}

local Net, Config
local player = Players.LocalPlayer

-- Design tokens (same system as UIController).
local COLOR = {
	surface = Color3.fromRGB(19, 19, 26),
	surfaceHi = Color3.fromRGB(26, 26, 35),
	mapBg = Color3.fromRGB(16, 16, 22),
	road = Color3.fromRGB(56, 56, 64),
	text = Color3.fromRGB(245, 245, 247),
	muted = Color3.fromRGB(154, 158, 168),
	accent = Color3.fromRGB(245, 158, 11),
	accent2 = Color3.fromRGB(239, 68, 68),
	blue = Color3.fromRGB(96, 165, 250),
	green = Color3.fromRGB(74, 222, 128),
	amber = Color3.fromRGB(250, 204, 21),
	red = Color3.fromRGB(248, 113, 113),
	gold = Color3.fromRGB(250, 204, 21),
}

local MAP_PX = 380
local HALF = 0
local SCALE = 0

local panel: Frame
local mapFrame: Frame
local heroBand: Frame
local infoName: TextLabel
local infoTagline: TextLabel
local statList: Frame
local ownerLabel: TextLabel
local teleportButton: TextButton
local trafficDot: Frame
local trafficLabel: TextLabel
local playerDot: Frame
local blipFolder: Frame
local iconFolder: Frame

local selectedDistrict: string? = nil
local plotOwners: { { any } } = {}
local otherBlips: { { any } } = {}

local function mk(class: string, props: { [string]: any }): Instance
	local inst = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function round(inst: Instance, radius: UDim)
	mk("UICorner", { CornerRadius = radius, Parent = inst })
end

local function stroke(inst: Instance, color: Color3, transparency: number, thickness: number?)
	mk("UIStroke", {
		Color = color,
		Transparency = transparency,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
end

local function worldToPx(x: number, z: number): (number, number)
	return (x + HALF) * SCALE, (z + HALF) * SCALE
end

local function trafficWordFor(level: number): string
	if level < 0.33 then
		return "Quiet"
	elseif level < 0.66 then
		return "Normal"
	end
	return "Busy"
end

local function trafficColor(level: number): Color3
	if level < 0.33 then
		return COLOR.green
	elseif level < 0.66 then
		return COLOR.amber
	end
	return COLOR.red
end

local function theftWord(mult: number): string
	if mult <= 0.75 then
		return "Low"
	elseif mult <= 1.25 then
		return "Normal"
	end
	return "High"
end

local function theftColor(mult: number): Color3
	if mult <= 0.75 then
		return COLOR.green
	elseif mult <= 1.25 then
		return COLOR.amber
	end
	return COLOR.red
end

local function pct(mult: number): string
	local v = math.floor((mult - 1) * 100 + 0.5)
	if v > 0 then
		return "+" .. v .. "%"
	elseif v < 0 then
		return v .. "%"
	end
	return "+0%"
end

-- ======================= Info sidebar =======================

local function ownerOf(districtId: string): { any }?
	for _, entry in plotOwners do
		if entry.district == districtId then
			return entry
		end
	end
	return nil
end

local function entryPrice(district)
	for _, theme in Config.Plots do
		if theme.district == district.id then
			return theme.baseCost
		end
	end
	return 0
end

local function statRow(labelText: string, valueText: string, valueColor: Color3?)
	local row = mk("Frame", {
		Name = "StatRow",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Parent = statList,
	})
	mk("TextLabel", {
		Size = UDim2.fromScale(0.55, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = COLOR.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = labelText,
		Parent = row,
	})
	mk("TextLabel", {
		Size = UDim2.fromScale(0.45, 1),
		Position = UDim2.fromScale(0.55, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = valueColor or COLOR.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = valueText,
		Parent = row,
	})
	return row
end

local function showDistrictInfo(districtId: string?)
	selectedDistrict = districtId
	for _, child in statList:GetChildren() do
		if child.Name == "StatRow" then
			child:Destroy()
		end
	end
	if not districtId then
		heroBand.BackgroundColor3 = COLOR.accent
		infoName.Text = "Explore the city"
		infoTagline.Text = "Five districts, five markets."
		statRow("Legend", "see below", COLOR.muted)
		ownerLabel.Text = "Click a district on the map to compare traits, prices and zone payouts."
		teleportButton.Visible = false
		return
	end
	local district = Config.City.Districts[districtId]
	heroBand.BackgroundColor3 = district.mapColor
	infoName.Text = district.name
	infoTagline.Text = district.tagline
	statRow("Plot cost", ("x%.1f"):format(district.costMult))
	statRow("Sale prices", pct(district.priceMult), if district.priceMult > 1 then COLOR.green else COLOR.red)
	statRow("Foot traffic", pct(district.customerMult), if district.customerMult > 1 then COLOR.green else COLOR.muted)
	statRow("Theft risk", theftWord(district.theftMult), theftColor(district.theftMult))
	statRow("Zone pot", ("$%d / %ds"):format(district.zoneDemand, Config.ZonePayoutInterval), COLOR.gold)
	local entry = ownerOf(districtId)
	if entry and entry.ownerName then
		ownerLabel.Text = ("%s\nOwned by %s"):format(entry.themeName, entry.ownerName)
	elseif entry then
		ownerLabel.Text = ("%s\nFor sale: $%d"):format(entry.themeName, entryPrice(district))
	else
		ownerLabel.Text = ""
	end
	teleportButton.Visible = true
end

-- ======================= Panel construction =======================

local function buildPanel(gui: ScreenGui)
	panel = mk("Frame", {
		Name = "CityPanel",
		Size = UDim2.fromOffset(696, 506),
		Position = UDim2.new(0.5, -348, 0.5, -253),
		BackgroundColor3 = COLOR.surface,
		BackgroundTransparency = 0.04,
		Visible = false,
		Parent = gui,
	})
	round(panel, UDim.new(0, 16))
	stroke(panel, Color3.new(1, 1, 1), 0.92)

	-- Header bar.
	mk("TextLabel", {
		Size = UDim2.fromOffset(300, 24),
		Position = UDim2.fromOffset(20, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		TextColor3 = COLOR.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "City Map",
		Parent = panel,
	})
	mk("TextLabel", {
		Size = UDim2.fromOffset(300, 16),
		Position = UDim2.fromOffset(20, 42),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = COLOR.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "districts, shops, zones and players",
		Parent = panel,
	})

	-- Traffic pill (right side of the header).
	local trafficPill = mk("Frame", {
		Name = "TrafficPill",
		Size = UDim2.fromOffset(118, 30),
		Position = UDim2.new(1, -174, 0, 18),
		BackgroundColor3 = COLOR.surfaceHi,
		BorderSizePixel = 0,
		Parent = panel,
	})
	round(trafficPill, UDim.new(1, 0))
	stroke(trafficPill, Color3.new(1, 1, 1), 0.9)
	trafficDot = mk("Frame", {
		Size = UDim2.fromOffset(8, 8),
		Position = UDim2.fromOffset(12, 11),
		BackgroundColor3 = COLOR.amber,
		BorderSizePixel = 0,
		Parent = trafficPill,
	})
	round(trafficDot, UDim.new(1, 0))
	trafficLabel = mk("TextLabel", {
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.fromOffset(26, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = COLOR.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Traffic: -",
		Parent = trafficPill,
	})

	-- Round close button with hover.
	local close = mk("TextButton", {
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.new(1, -54, 0, 15),
		BackgroundColor3 = COLOR.surfaceHi,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = COLOR.muted,
		Text = "X",
		Parent = panel,
	})
	round(close, UDim.new(1, 0))
	stroke(close, Color3.new(1, 1, 1), 0.9)
	close.MouseEnter:Connect(function()
		TweenService:Create(close, TweenInfo.new(0.15), { BackgroundColor3 = COLOR.red }):Play()
	end)
	close.MouseLeave:Connect(function()
		TweenService:Create(close, TweenInfo.new(0.15), { BackgroundColor3 = COLOR.surfaceHi }):Play()
	end)
	close.MouseButton1Click:Connect(function()
		panel.Visible = false
	end)

	-- ======================= Minimap card =======================
	mapFrame = mk("Frame", {
		Name = "MapCard",
		Size = UDim2.fromOffset(404, 404),
		Position = UDim2.fromOffset(16, 78),
		BackgroundColor3 = COLOR.mapBg,
		BorderSizePixel = 0,
		Parent = panel,
	})
	round(mapFrame, UDim.new(0, 12))
	stroke(mapFrame, Color3.new(1, 1, 1), 0.94)

	local mapInner = mk("Frame", {
		Name = "Inner",
		Size = UDim2.fromOffset(MAP_PX, MAP_PX),
		Position = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = mapFrame,
	})

	-- District blocks with hover + selection states.
	for id, district in Config.City.Districts do
		local x0, y0 = worldToPx(district.rect.x0, district.rect.z0)
		local x1, y1 = worldToPx(district.rect.x1, district.rect.z1)
		local districtBtn = mk("TextButton", {
			Name = "District_" .. id,
			Position = UDim2.fromOffset(x0, y0),
			Size = UDim2.fromOffset(x1 - x0, y1 - y0),
			BackgroundColor3 = district.mapColor,
			BackgroundTransparency = 0.18,
			AutoButtonColor = false,
			Font = Enum.Font.Gotham,
			Text = "",
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = mapInner,
		})
		round(districtBtn, UDim.new(0, 10))
		mk("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -5),
			Size = UDim2.new(1, -10, 0, 13),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeColor3 = Color3.fromRGB(20, 20, 20),
			TextStrokeTransparency = 0.35,
			Text = district.name,
			Parent = districtBtn,
		})
		local selectStroke = mk("UIStroke", {
			Name = "SelectStroke",
			Color = Color3.new(1, 1, 1),
			Thickness = 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = districtBtn,
		})
		districtBtn.MouseEnter:Connect(function()
			if selectedDistrict ~= id then
				TweenService:Create(districtBtn, TweenInfo.new(0.12), { BackgroundTransparency = 0.05 }):Play()
			end
		end)
		districtBtn.MouseLeave:Connect(function()
			if selectedDistrict ~= id then
				TweenService:Create(districtBtn, TweenInfo.new(0.12), { BackgroundTransparency = 0.18 }):Play()
			end
		end)
		districtBtn.MouseButton1Click:Connect(function()
			for _, child in mapInner:GetChildren() do
				local s = child:FindFirstChild("SelectStroke")
				if s then
					(s :: UIStroke).Thickness = 0
				end
			end
			if selectedDistrict == id then
				showDistrictInfo(nil)
			else
				selectStroke.Thickness = 3
				showDistrictInfo(id)
			end
		end)
	end

	-- Roads.
	for _, x in Config.City.RoadsX do
		local mx, _ = worldToPx(x, 0)
		mk("Frame", {
			Name = "Road",
			Position = UDim2.fromOffset(mx - Config.City.RoadHalf * SCALE, 0),
			Size = UDim2.fromOffset(Config.City.RoadHalf * 2 * SCALE, MAP_PX),
			BackgroundColor3 = COLOR.road,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = mapInner,
		})
	end
	for _, z in Config.City.RoadsZ do
		local _, my = worldToPx(0, z)
		mk("Frame", {
			Name = "Road",
			Position = UDim2.fromOffset(0, my - Config.City.RoadHalf * SCALE),
			Size = UDim2.fromOffset(MAP_PX, Config.City.RoadHalf * 2 * SCALE),
			BackgroundColor3 = COLOR.road,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = mapInner,
		})
	end

	-- Markers layer.
	iconFolder = mk("Frame", {
		Name = "Icons",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = mapInner,
	})
	blipFolder = mk("Frame", {
		Name = "Blips",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = mapInner,
	})

	-- Delivery zone ($) and restaurant (P) markers.
	for _, district in Config.City.Districts do
		local zx, zy = worldToPx(district.zone.X, district.zone.Z)
		local zoneDot = mk("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(zx, zy),
			Size = UDim2.fromOffset(17, 17),
			BackgroundColor3 = Color3.fromRGB(255, 220, 90),
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = Color3.fromRGB(60, 50, 0),
			Text = "$",
			ZIndex = 4,
			Parent = iconFolder,
		})
		round(zoneDot, UDim.new(1, 0))
	end
	for _, theme in Config.Plots do
		local px, py = worldToPx(theme.position.X, theme.position.Z)
		local plotDot = mk("TextLabel", {
			Name = "Plot_" .. theme.id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(px, py),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = theme.accentColor,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeColor3 = Color3.fromRGB(30, 30, 30),
			TextStrokeTransparency = 0.3,
			Text = "P",
			ZIndex = 4,
			Parent = iconFolder,
		})
		round(plotDot, UDim.new(1, 0))
	end

	-- Your dot (live position).
	playerDot = mk("Frame", {
		Name = "Me",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 6,
		Parent = blipFolder,
	})
	round(playerDot, UDim.new(1, 0))
	stroke(playerDot, Color3.fromRGB(40, 40, 40), 0, 2)

	-- Legend row under the map card.
	mk("TextLabel", {
		Size = UDim2.fromOffset(404, 16),
		Position = UDim2.fromOffset(16, 486),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = COLOR.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "P  restaurant      $  delivery zone      white dot  you",
		Parent = panel,
	})

	-- ======================= Sidebar card =======================
	local infoPanel = mk("Frame", {
		Name = "Info",
		Size = UDim2.fromOffset(248, 404),
		Position = UDim2.fromOffset(432, 78),
		BackgroundColor3 = COLOR.surfaceHi,
		BorderSizePixel = 0,
		Parent = panel,
	})
	round(infoPanel, UDim.new(0, 12))
	stroke(infoPanel, Color3.new(1, 1, 1), 0.94)
	-- Clip the hero band to the rounded top corners.
	infoPanel.ClipsDescendants = true

	heroBand = mk("Frame", {
		Name = "HeroBand",
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = COLOR.accent,
		BorderSizePixel = 0,
		Parent = infoPanel,
	})

	infoName = mk("TextLabel", {
		Size = UDim2.new(1, -32, 0, 22),
		Position = UDim2.fromOffset(16, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = COLOR.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "Explore the city",
		Parent = infoPanel,
	})
	infoTagline = mk("TextLabel", {
		Size = UDim2.new(1, -32, 0, 30),
		Position = UDim2.fromOffset(16, 44),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = COLOR.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = "",
		Parent = infoPanel,
	})

	-- Stat rows (rebuilt by showDistrictInfo).
	statList = mk("Frame", {
		Name = "Stats",
		Size = UDim2.new(1, -32, 0, 120),
		Position = UDim2.fromOffset(16, 82),
		BackgroundTransparency = 1,
		Parent = infoPanel,
	})
	mk("UIListLayout", { Padding = UDim.new(0, 6), Parent = statList })

	ownerLabel = mk("TextLabel", {
		Size = UDim2.new(1, -32, 0, 44),
		Position = UDim2.fromOffset(16, 210),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = COLOR.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = "",
		Parent = infoPanel,
	})

	-- Teleport CTA pinned to the sidebar bottom.
	teleportButton = mk("TextButton", {
		Size = UDim2.new(1, -32, 0, 44),
		Position = UDim2.new(0.5, 0, 1, -60),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = COLOR.accent,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(30, 20, 5),
		Text = "Fast Travel",
		Visible = false,
		Parent = infoPanel,
	})
	round(teleportButton, UDim.new(0, 10))
	local ctaGradient = mk("UIGradient", {
		Rotation = 45,
		Color = ColorSequence.new(COLOR.accent, Color3.fromRGB(251, 146, 60)),
		Parent = teleportButton,
	})
	teleportButton.MouseEnter:Connect(function()
		TweenService:Create(teleportButton, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(255, 180, 60) }):Play()
	end)
	teleportButton.MouseLeave:Connect(function()
		TweenService:Create(teleportButton, TweenInfo.new(0.15), { BackgroundColor3 = COLOR.accent }):Play()
	end)
	teleportButton.MouseButton1Click:Connect(function()
		if selectedDistrict then
			Net.TeleportRequest:FireServer(selectedDistrict)
			panel.Visible = false
		end
	end)
end

local function buildButton(gui: ScreenGui)
	local button = mk("TextButton", {
		Name = "CityButton",
		Size = UDim2.fromOffset(252, 48),
		Position = UDim2.new(1, -268, 0, 348),
		BackgroundColor3 = COLOR.surface,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.Gotham,
		Text = "",
		Parent = gui,
	})
	round(button, UDim.new(0, 14))
	stroke(button, Color3.new(1, 1, 1), 0.92)

	-- Mini-map icon: tiny rounded square with two district blocks.
	local icon = mk("Frame", {
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromOffset(10, 10),
		BackgroundColor3 = COLOR.surfaceHi,
		BorderSizePixel = 0,
		Parent = button,
	})
	round(icon, UDim.new(0, 8))
	mk("Frame", {
		Size = UDim2.fromOffset(9, 9),
		Position = UDim2.fromOffset(5, 5),
		BackgroundColor3 = Color3.fromRGB(115, 155, 225),
		BorderSizePixel = 0,
		Parent = icon,
	})
	mk("Frame", {
		Size = UDim2.fromOffset(9, 9),
		Position = UDim2.fromOffset(15, 14),
		BackgroundColor3 = Color3.fromRGB(130, 190, 120),
		BorderSizePixel = 0,
		Parent = icon,
	})

	mk("TextLabel", {
		Size = UDim2.new(1, -58, 1, 0),
		Position = UDim2.fromOffset(46, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = COLOR.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "City Map",
		Parent = button,
	})
	mk("TextLabel", {
		Size = UDim2.fromOffset(20, 48),
		Position = UDim2.new(1, -30, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = COLOR.muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = ">",
		Parent = button,
	})
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.15), { BackgroundColor3 = COLOR.surfaceHi }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.15), { BackgroundColor3 = COLOR.surface }):Play()
	end)
	button.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

-- ======================= Runtime updates =======================

local function refreshBlips()
	for _, child in blipFolder:GetChildren() do
		if child.Name:sub(1, 7) == "Player_" then
			child:Destroy()
		end
	end
	for _, blip in otherBlips do
		if blip.name ~= player.Name then
			local bx, by = worldToPx(blip.x, blip.z)
			local dot = mk("Frame", {
				Name = "Player_" .. blip.name,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(bx, by),
				Size = UDim2.fromOffset(8, 8),
				BackgroundColor3 = Color3.fromRGB(255, 120, 120),
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = blipFolder,
			})
			round(dot, UDim.new(1, 0))
		end
	end
end

function CityMapController.Init(ctx)
	Net = ctx.Net
	Config = ctx.Config

	HALF = Config.City.WorldHalf + 10
	SCALE = MAP_PX / (2 * HALF)

	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("PizzaTycoonHUD")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "PizzaTycoonHUD"
		gui.ResetOnSpawn = false
		gui.Parent = playerGui
	end

	buildPanel(gui :: ScreenGui)
	buildButton(gui :: ScreenGui)
	showDistrictInfo(nil)

	Net.CityState.OnClientEvent:Connect(function(payload)
		trafficLabel.Text = "Traffic: " .. trafficWordFor(payload.traffic)
		trafficDot.BackgroundColor3 = trafficColor(payload.traffic)
		plotOwners = payload.plots or {}
		otherBlips = payload.players or {}
		refreshBlips()
		-- Live-update the sidebar if a district is selected.
		if selectedDistrict then
			showDistrictInfo(selectedDistrict)
		end
	end)

	-- Own dot follows the character every frame.
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local mx, my = worldToPx(root.Position.X, root.Position.Z)
			playerDot.Position = UDim2.fromOffset(mx, my)
		end
	end)
end

return CityMapController
