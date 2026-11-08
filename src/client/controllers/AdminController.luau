--!strict
-- AdminController: builds the admin panel ONLY for accounts listed in
-- Config.AdminUserIds. Every button just fires Net.AdminCommand; the
-- server independently re-validates the user id, so this UI is a
-- convenience layer, not the security boundary. Styled to the same
-- web-standard token system as the HUD and city map.

local Players = game:GetService("Players")

local AdminController = {}

local Net, Config
local player = Players.LocalPlayer

-- Design tokens (same system as UIController / CityMapController).
local COLOR = {
	surface = Color3.fromRGB(19, 19, 26),
	surfaceHi = Color3.fromRGB(26, 26, 35),
	surfaceHover = Color3.fromRGB(36, 36, 48),
	text = Color3.fromRGB(245, 245, 247),
	muted = Color3.fromRGB(154, 158, 168),
	accent = Color3.fromRGB(245, 158, 11),
	accent2 = Color3.fromRGB(239, 68, 68),
	green = Color3.fromRGB(74, 222, 128),
	red = Color3.fromRGB(248, 113, 113),
}

-- Local mirror of the server's AdminState snapshot.
local view = {
	cash = 0,
	readyPizzas = 0,
	upgrades = { oven = 0, warehouse = 1, marketing = 1, security = 1 },
	staff = { chef = 0, driver = 0 },
	expansions = 0,
	maxExpansions = 3,
	unlockedCount = 1,
	currentEvent = nil,
	plotTheme = nil,
}

local panel: Frame
local statusLabel: TextLabel
local stepperLabels: { { any } } = {} -- { label, row } entries
local eventButtons: { { any } } = {} -- { id, button } entries

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

local function send(cmd: string, args: { [string]: any }?)
	Net.AdminCommand:FireServer(cmd, args or {})
end

-- Button with a hover state. `accent` controls the label color.
local function button(parent: Instance, text: string, accent: Color3?, onClick: () -> ()): TextButton
	local b = mk("TextButton", {
		Name = text,
		BackgroundColor3 = COLOR.surfaceHi,
		Text = text,
		TextColor3 = accent or COLOR.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		AutoButtonColor = false,
		Parent = parent,
	})
	round(b, UDim.new(0, 10))
	stroke(b, COLOR.text, 0.92, 1)
	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = COLOR.surfaceHover
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = COLOR.surfaceHi
	end)
	b.Activated:Connect(onClick)
	return b
end

local function section(parent: Instance, title: string): Frame
	local holder = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	mk("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = holder,
	})
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Text = title,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = COLOR.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = holder,
	})
	return holder
end

-- A row of equal-width buttons (grid).
local function buttonRow(parent: Instance, buttons: { { any } }): Frame
	local row = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = parent,
	})
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	for i, def in buttons do
		local b = button(
			row,
			def.text,
			def.accent,
			def.onClick
		)
		b.Size = UDim2.new(1 / #buttons, -6, 1, 0)
		b.LayoutOrder = i
	end
	return row
end

local function syncView()
	statusLabel.Text = ("Cash $%d · Ready %d · Recipes %d · Plot %s"):format(
		view.cash,
		view.readyPizzas,
		view.unlockedCount,
		view.plotTheme or "none"
	)
	for _, entry in stepperLabels do
		local row = entry.row
		local value = 0
		if row.kind == "expansions" then
			value = view.expansions
		elseif row.cmd == "set_upgrade" then
			value = (view.upgrades :: any)[row.kind]
		else
			value = (view.staff :: any)[row.kind]
		end
		entry.label.Text = tostring(value)
	end
	for _, entry in eventButtons do
		local active = view.currentEvent == entry.id
		entry.button.BackgroundColor3 = if active then COLOR.accent else COLOR.surfaceHi
		entry.button.TextColor3 = if active then COLOR.surface else COLOR.text
	end
end

local function buildPanel(parent: Instance)
	panel = mk("Frame", {
		Name = "AdminPanel",
		BackgroundColor3 = COLOR.surface,
		Size = UDim2.fromOffset(420, 480),
		Position = UDim2.fromOffset(16, 64),
		Visible = false,
		Parent = parent,
	})
	round(panel, UDim.new(0, 14))
	stroke(panel, COLOR.text, 0.9, 1)

	-- Header bar.
	local header = mk("Frame", {
		BackgroundColor3 = COLOR.surfaceHi,
		Size = UDim2.new(1, 0, 0, 52),
		Parent = panel,
	})
	round(header, UDim.new(0, 14))
	mk("TextButton", {
		Name = "Close",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.new(1, -44, 0, 8),
		Text = "✕",
		TextColor3 = COLOR.muted,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Parent = header,
	}).Activated:Connect(function()
		panel.Visible = false
	end)
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -100, 0, 24),
		Position = UDim2.fromOffset(16, 6),
		Text = "🛡 Admin",
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		TextColor3 = COLOR.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	statusLabel = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -100, 0, 14),
		Position = UDim2.fromOffset(16, 31),
		Text = "Cash $0 · Ready 0 · Recipes 1 · Plot none",
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = COLOR.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})

	-- Scrollable command list.
	local scroll = mk("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 1, -68),
		Position = UDim2.fromOffset(12, 60),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = COLOR.muted,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Parent = panel,
	})
	local list = mk("UIListLayout", {
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})
	list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scroll.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 8)
	end)

	-- ===== Economy =====
	local eco = section(scroll, "ECONOMY")
	eco.LayoutOrder = 1

	local cashRow = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = eco,
	})
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = cashRow,
	})
	local cashInput = mk("TextBox", {
		BackgroundColor3 = COLOR.surfaceHi,
		Size = UDim2.new(0, 110, 1, 0),
		Text = "",
		PlaceholderText = "Cash amount…",
		PlaceholderColor3 = COLOR.muted,
		TextColor3 = COLOR.text,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = cashRow,
	})
	round(cashInput, UDim.new(0, 10))
	stroke(cashInput, COLOR.text, 0.92, 1)
	cashInput.LayoutOrder = 1
	local setBtn = button(cashRow, "Set cash", COLOR.accent, function()
		local amount = tonumber(cashInput.Text)
		if amount then
			send("set_cash", { amount = amount })
		end
	end)
	setBtn.Size = UDim2.new(1, -180, 1, 0)
	setBtn.LayoutOrder = 2
	local k1 = button(cashRow, "+$1k", nil, function()
		send("add_cash", { amount = 1000 })
	end)
	k1.Size = UDim2.fromOffset(58, 34)
	k1.LayoutOrder = 3

	buttonRow(eco, {
		{ text = "+$10k", accent = nil, onClick = function()
			send("add_cash", { amount = 10000 })
		end },
		{ text = "+100 all ingredients", accent = nil, onClick = function()
			send("give_ingredients", { amount = 100 })
		end },
		{ text = "Unlock all recipes", accent = nil, onClick = function()
			send("unlock_all", {})
		end },
	})
	local readyBtn = button(eco, "+10 ready pizzas (max 50)", nil, function()
		send("set_ready", { amount = math.min(Config.ReadyPizzaCap, view.readyPizzas + 10) })
	end)
	readyBtn.Size = UDim2.new(1, 0, 0, 34)

	-- ===== Progression =====
	local prog = section(scroll, "PROGRESSION")
	prog.LayoutOrder = 2

	local stepperDefs = {
		{ label = "Oven tier", kind = "oven", cmd = "set_upgrade", min = 0, max = #Config.OvenTiers },
		{ label = "Warehouse", kind = "warehouse", cmd = "set_upgrade", min = 1, max = #Config.WarehouseTiers },
		{ label = "Marketing", kind = "marketing", cmd = "set_upgrade", min = 1, max = #Config.MarketingTiers },
		{ label = "Security", kind = "security", cmd = "set_upgrade", min = 1, max = #Config.SecurityTiers },
		{ label = "Chefs", kind = "chef", cmd = "set_staff", min = 0, max = Config.Staff.chef.max },
		{ label = "Drivers", kind = "driver", cmd = "set_staff", min = 0, max = Config.Staff.driver.max },
		{ label = "Expansions", kind = "expansions", cmd = "set_expansions", min = 0, max = 3 },
	}
	for _, def in stepperDefs do
		local row = mk("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 30),
			Parent = prog,
		})
		mk("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -100, 1, 0),
			Text = def.label,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = COLOR.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local minus = button(row, "–", nil, function()
			local current = 0
			if def.kind == "expansions" then
				current = view.expansions
			elseif def.cmd == "set_upgrade" then
				current = (view.upgrades :: any)[def.kind]
			else
				current = (view.staff :: any)[def.kind]
			end
			local next = math.max(def.min, current - 1)
			send(def.cmd, { kind = def.kind, tier = next, count = next })
		end)
		minus.Size = UDim2.fromOffset(30, 30)
		minus.Position = UDim2.new(1, -98, 0, 0)
		local valueLabel = mk("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(32, 30),
			Position = UDim2.new(1, -64, 0, 0),
			Text = "0",
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = COLOR.accent,
			Parent = row,
		})
		local plus = button(row, "+", nil, function()
			local current = 0
			if def.kind == "expansions" then
				current = view.expansions
			elseif def.cmd == "set_upgrade" then
				current = (view.upgrades :: any)[def.kind]
			else
				current = (view.staff :: any)[def.kind]
			end
			local maxValue = def.max
			if def.kind == "expansions" then
				maxValue = view.maxExpansions
			end
			local next = math.min(maxValue, current + 1)
			send(def.cmd, { kind = def.kind, tier = next, count = next })
		end)
		plus.Size = UDim2.fromOffset(30, 30)
		plus.Position = UDim2.new(1, -30, 0, 0)
		table.insert(stepperLabels, { label = valueLabel, row = def })
	end

	-- ===== Events =====
	local eventsSection = section(scroll, "CITY EVENTS")
	eventsSection.LayoutOrder = 3

	local eventIds = {}
	for id in Config.Events do
		table.insert(eventIds, id)
	end
	table.sort(eventIds)

	-- Two-column grid of event buttons.
	local grid = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 74),
		Parent = eventsSection,
	})
	mk("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, 32),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for i, id in eventIds do
		local event = Config.Events[id]
		local b = button(grid, event.name, nil, function()
			send("trigger_event", { id = id })
		end)
		b.LayoutOrder = i
		table.insert(eventButtons, { id = id, button = b })
	end
	local endBtn = button(eventsSection, "End current event", COLOR.red, function()
		send("clear_event", {})
	end)
	endBtn.Size = UDim2.new(1, 0, 0, 32)

	-- ===== Teleport =====
	local tp = section(scroll, "TELEPORT")
	tp.LayoutOrder = 4

	local districtIds = {}
	for id in Config.City.Districts do
		table.insert(districtIds, id)
	end
	table.sort(districtIds)

	local tpGrid = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 108),
		Parent = tp,
	})
	mk("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, 32),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tpGrid,
	})
	for i, id in districtIds do
		local district = Config.City.Districts[id]
		local b = button(tpGrid, district.name, COLOR.accent, function()
			send("teleport", { districtId = id })
		end)
		b.LayoutOrder = i
	end

	-- ===== Data =====
	local dataSec = section(scroll, "DATA")
	dataSec.LayoutOrder = 5

	buttonRow(dataSec, {
		{ text = "Save now", accent = COLOR.green, onClick = function()
			send("save_now", {})
		end },
		{ text = "Release plot", accent = COLOR.red, onClick = function()
			send("release_plot", {})
		end },
		{ text = "Wipe my data", accent = COLOR.red, onClick = function()
			send("wipe_data", {})
		end },
	})
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 14),
		Text = "Wipe = fresh start (plot, cash, recipes, upgrades). No undo.",
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextColor3 = COLOR.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = dataSec,
	})
end

function AdminController.Init(ctx)
	Net = ctx.Net
	Config = ctx.Config

	-- Only build anything for admin accounts. The server re-checks every
	-- command independently, so this gate is purely cosmetic.
	if not table.find(Config.AdminUserIds, player.UserId) then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "PizzaTycoonAdmin"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Parent = playerGui

	buildPanel(gui)

	-- Toggle button, top-left below nothing else (HUD is top-center/right).
	local toggle = mk("TextButton", {
		Name = "AdminToggle",
		BackgroundColor3 = COLOR.surface,
		Text = "🛡 Admin",
		TextColor3 = COLOR.text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(96, 38),
		Position = UDim2.fromOffset(16, 16),
		Parent = gui,
	})
	round(toggle, UDim.new(0, 12))
	stroke(toggle, COLOR.accent2, 0.4, 1)
	toggle.MouseEnter:Connect(function()
		toggle.BackgroundColor3 = COLOR.surfaceHi
	end)
	toggle.MouseLeave:Connect(function()
		toggle.BackgroundColor3 = COLOR.surface
	end)
	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			send("get_status", {})
		end
	end)

	-- Keep the local view in sync with server snapshots.
	Net.AdminState.OnClientEvent:Connect(function(snap)
		if typeof(snap) ~= "table" then
			return
		end
		view.cash = snap.cash or 0
		view.readyPizzas = snap.readyPizzas or 0
		if typeof(snap.upgrades) == "table" then
			for key, value in snap.upgrades do
				(view.upgrades :: any)[key] = value
			end
		end
		if typeof(snap.staff) == "table" then
			for key, value in snap.staff do
				(view.staff :: any)[key] = value
			end
		end
		view.expansions = snap.expansions or 0
		view.maxExpansions = snap.maxExpansions or 3
		view.unlockedCount = snap.unlockedCount or 1
		view.currentEvent = snap.currentEvent
		view.plotTheme = snap.plotTheme
		syncView()
	end)

	-- Initial snapshot request (also covers respawns).
	send("get_status", {})
	syncView()
end

return AdminController
