--!strict
-- CityMapController: the CITY button on the right edge opens a live city
-- map: color-coded districts, roads, delivery zones, restaurant plots,
-- your dot and other players' blips. Click a district for its traits and
-- zone pot, then fast travel. Traffic readout shows the current rush
-- level. All layout data comes from shared Config.City.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CityMapController = {}

local Net, Config
local player = Players.LocalPlayer

local MAP_PX = 380
local HALF = 0
local SCALE = 0

local panel: Frame
local mapFrame: Frame
local infoName: TextLabel
local infoBody: TextLabel
local teleportButton: TextButton
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

local function worldToPx(x: number, z: number): (number, number)
	return (x + HALF) * SCALE, (z + HALF) * SCALE
end

local function trafficWord(level: number): string
	if level < 0.33 then
		return "Quiet"
	elseif level < 0.66 then
		return "Normal"
	end
	return "Busy"
end

local function theftWord(mult: number): string
	if mult <= 0.75 then
		return "Low"
	elseif mult <= 1.25 then
		return "Normal"
	end
	return "High"
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

-- ======================= Info panel =======================

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

local function showDistrictInfo(districtId: string?)
	selectedDistrict = districtId
	if not districtId then
		infoName.Text = "City Map"
		infoBody.Text = "Click a district to see\nits traits and payouts.\n\nGreen dots: your shop\n$ marks: delivery zones"
		teleportButton.Visible = false
		return
	end
	local district = Config.City.Districts[districtId]
	infoName.Text = district.name
	infoName.TextColor3 = Color3.new(1, 1, 1)
	local lines = {
		district.tagline,
		"",
		("Plot prices: x%.1f"):format(district.costMult),
		("Sale prices: %s"):format(pct(district.priceMult)),
		("Foot traffic: %s"):format(pct(district.customerMult)),
		("Theft risk: %s"):format(theftWord(district.theftMult)),
		"",
		("Zone pot: $%d / %ds"):format(district.zoneDemand, Config.ZonePayoutInterval),
	}
	local entry = ownerOf(districtId)
	if entry and entry.ownerName then
		table.insert(lines, "\n" .. entry.themeName .. ": " .. entry.ownerName)
	elseif entry then
		table.insert(lines, ("\nRestaurant: for sale ($%d)"):format(entryPrice(district)))
	end
	infoBody.Text = table.concat(lines, "\n")
	teleportButton.Visible = true
end

-- ======================= Map construction =======================

local function buildPanel(gui: ScreenGui)
	panel = mk("Frame", {
		Name = "CityPanel",
		Size = UDim2.fromOffset(640, 442),
		Position = UDim2.new(0.5, -320, 0.5, -221),
		BackgroundColor3 = Color3.fromRGB(28, 28, 34),
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	})
	mk("UICorner", { CornerRadius = UDim.new(0, 12), Parent = panel })

	mk("TextLabel", {
		Size = UDim2.fromOffset(300, 36),
		Position = UDim2.fromOffset(16, 10),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 200, 90),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "City Map",
		Parent = panel,
	})

	trafficLabel = mk("TextLabel", {
		Size = UDim2.fromOffset(240, 26),
		Position = UDim2.new(1, -266, 0, 12),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(180, 220, 255),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "Traffic: -",
		Parent = panel,
	})

	local close = mk("TextButton", {
		Size = UDim2.fromOffset(32, 32),
		Position = UDim2.new(1, -40, 0, 10),
		BackgroundColor3 = Color3.fromRGB(70, 40, 40),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "X",
		Parent = panel,
	})
	mk("UICorner", { CornerRadius = UDim.new(0, 8), Parent = close })
	close.MouseButton1Click:Connect(function()
		panel.Visible = false
	end)

	-- Minimap.
	mapFrame = mk("Frame", {
		Name = "Map",
		Size = UDim2.fromOffset(MAP_PX + 24, MAP_PX + 24),
		Position = UDim2.fromOffset(16, 54),
		BackgroundColor3 = Color3.fromRGB(70, 110, 70),
		Parent = panel,
	})
	mk("UICorner", { CornerRadius = UDim.new(0, 10), Parent = mapFrame })

	local mapInner = mk("Frame", {
		Name = "Inner",
		Size = UDim2.fromOffset(MAP_PX, MAP_PX),
		Position = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = mapFrame,
	})

	-- District blocks.
	for id, district in Config.City.Districts do
		local x0, y0 = worldToPx(district.rect.x0, district.rect.z0)
		local x1, y1 = worldToPx(district.rect.x1, district.rect.z1)
		local districtBtn = mk("TextButton", {
			Name = "District_" .. id,
			Position = UDim2.fromOffset(x0, y0),
			Size = UDim2.fromOffset(x1 - x0, y1 - y0),
			BackgroundColor3 = district.mapColor,
			BackgroundTransparency = 0.25,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.6,
			Text = "",
			TextTruncate = Enum.TextTruncate.AtEnd,
			AutoButtonColor = true,
			Parent = mapInner,
		})
		mk("UICorner", { CornerRadius = UDim.new(0, 8), Parent = districtBtn })
		local label = mk("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -8, 0, 14),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.4,
			Text = district.name,
			Parent = districtBtn,
		})
		local stroke = mk("UIStroke", {
			Name = "SelectStroke",
			Color = Color3.fromRGB(255, 255, 255),
			Thickness = 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = districtBtn,
		})
		districtBtn.MouseButton1Click:Connect(function()
			-- Toggle selection + highlight.
			for _, child in mapInner:GetChildren() do
				local s = child:FindFirstChild("SelectStroke")
				if s then
					(s :: UIStroke).Thickness = 0
				end
			end
			if selectedDistrict == id then
				showDistrictInfo(nil)
			else
				stroke.Thickness = 3
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
			BackgroundColor3 = Color3.fromRGB(80, 80, 86),
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
			BackgroundColor3 = Color3.fromRGB(80, 80, 86),
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
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = Color3.fromRGB(255, 220, 90),
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextColor3 = Color3.fromRGB(60, 50, 0),
			Text = "$",
			ZIndex = 4,
			Parent = iconFolder,
		})
		mk("UICorner", { CornerRadius = UDim.new(1, 0), Parent = zoneDot })
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
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.4,
			Text = "P",
			ZIndex = 4,
			Parent = iconFolder,
		})
		mk("UICorner", { CornerRadius = UDim.new(1, 0), Parent = plotDot })
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
	mk("UICorner", { CornerRadius = UDim.new(1, 0), Parent = playerDot })
	mk("UIStroke", { Color = Color3.fromRGB(40, 40, 40), Thickness = 2, Parent = playerDot })

	-- Info panel (right column).
	local infoPanel = mk("Frame", {
		Name = "Info",
		Size = UDim2.fromOffset(204, MAP_PX + 24),
		Position = UDim2.new(0, 16 + MAP_PX + 24 + 12, 0, 54),
		BackgroundColor3 = Color3.fromRGB(38, 38, 46),
		Parent = panel,
	})
	mk("UICorner", { CornerRadius = UDim.new(0, 10), Parent = infoPanel })

	infoName = mk("TextLabel", {
		Size = UDim2.new(1, -12, 0, 44),
		Position = UDim2.fromOffset(6, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextWrapped = true,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 200, 90),
		Text = "City Map",
		Parent = infoPanel,
	})

	infoBody = mk("TextLabel", {
		Size = UDim2.new(1, -12, 1, -110),
		Position = UDim2.fromOffset(6, 56),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextWrapped = true,
		TextScaled = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Color3.fromRGB(230, 230, 235),
		Text = "Click a district to see\nits traits and payouts.",
		Parent = infoPanel,
	})

	teleportButton = mk("TextButton", {
		Size = UDim2.new(1, -24, 0, 40),
		Position = UDim2.new(0.5, 0, 1, -52),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(90, 160, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "Teleport",
		Visible = false,
		Parent = infoPanel,
	})
	mk("UICorner", { CornerRadius = UDim.new(0, 10), Parent = teleportButton })
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
		Size = UDim2.fromOffset(230, 44),
		Position = UDim2.new(1, -246, 0, 292),
		BackgroundColor3 = Color3.fromRGB(40, 46, 66),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(140, 210, 255),
		Text = "CITY MAP",
		Parent = gui,
	})
	mk("UICorner", { CornerRadius = UDim.new(0, 10), Parent = button })
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
				ZIndex = 5,
				Parent = blipFolder,
			})
			mk("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dot })
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
		trafficLabel.Text = "Traffic: " .. trafficWord(payload.traffic)
		plotOwners = payload.plots or {}
		otherBlips = payload.players or {}
		refreshBlips()
		-- Live-update the info panel if a district is selected.
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
