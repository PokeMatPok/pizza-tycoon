--!strict
-- ModelFactory: the "model service". Every 3D asset in the game is built
-- procedurally here from anchored parts, so the game needs zero uploaded
-- meshes. When you later import real meshes (Meshy/Sloyd/Creator Store),
-- swap the body of the corresponding builder function only.

local ModelFactory = {}

-- Apply a props table to an Instance, parenting last.
local function applyProps(p: Part, props: { [string]: any })
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	local parent = props.Parent
	if parent then
		p.Parent = parent
	end
end

function ModelFactory.basePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	applyProps(p, props)
	return p
end

-- Smoothly tween a model's pivot from its current CFrame to a target.
function ModelFactory.tweenModel(model: Model, target: CFrame, duration: number)
	local value = Instance.new("CFrameValue")
	value.Value = model:GetPivot()
	local conn = value.Changed:Connect(function(v: CFrame)
		if model.Parent then
			model:PivotTo(v)
		end
	end)
	local tween = game:GetService("TweenService"):Create(
		value,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ Value = target }
	)
	tween.Completed:Connect(function()
		conn:Disconnect()
		value:Destroy()
	end)
	tween:Play()
	return tween
end

-- Walk a model through a list of CFrames sequentially (multi-leg tween).
function ModelFactory.walkPath(model: Model, points: { CFrame }, studsPerSec: number)
	local total = 0
	for i = 2, #points do
		total += (points[i - 1].Position - points[i].Position).Magnitude
	end
	task.spawn(function()
		for i = 2, #points do
			if not model.Parent then
				return
			end
			local dist = (points[i - 1].Position - points[i].Position).Magnitude
			local tween = ModelFactory.tweenModel(model, points[i], math.max(0.2, dist / studsPerSec))
			tween.Completed:Wait()
		end
	end)
	return total
end

-- ============================ Food & shop ============================

-- A pizza. One flat cylinder body + topping dots. Cheap: 5 parts.
function ModelFactory.pizza(recipeColor: Color3, toppingColor: Color3, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Pizza"
	local body = ModelFactory.basePart({
		Shape = Enum.PartType.Cylinder,
		Name = "Body",
		Size = Vector3.new(0.35, 3.2, 3.2),
		Color = recipeColor,
		Material = Enum.Material.Neon,
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)),
		CanCollide = false,
		Parent = model,
	})
	local rng = Random.new()
	for i = 1, 4 do
		local angle = (i / 4) * math.pi * 2 + rng:NextNumber(0, 0.5)
		local offset = CFrame.new(math.cos(angle) * 0.8, 0.19, math.sin(angle) * 0.8)
		ModelFactory.basePart({
			Name = "Topping",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.05, 0.6, 0.6),
			Color = toppingColor,
			Material = Enum.Material.SmoothPlastic,
			CFrame = body.CFrame * offset * CFrame.Angles(0, 0, math.rad(90)),
			CanCollide = false,
			Parent = model,
		})
	end
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

-- Ingredient crate with a text label.
function ModelFactory.crate(ingredientColor: Color3, label: string, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Crate"
	local box = ModelFactory.basePart({
		Name = "Box",
		Size = Vector3.new(3, 2.2, 3),
		Color = ingredientColor,
		Material = Enum.Material.WoodPlanks,
		CFrame = cf,
		Parent = model,
	})
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = false
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Text = label
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Parent = gui
	gui.Parent = box
	model.PrimaryPart = box
	model.Parent = parent
	return model
end

-- Oven: frame + glowing interior. Tier influences glow color.
function ModelFactory.oven(tierColor: Color3, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Oven"
	local base = ModelFactory.basePart({
		Name = "Frame",
		Size = Vector3.new(8, 5, 6),
		Color = Color3.fromRGB(90, 90, 95),
		Material = Enum.Material.Metal,
		CFrame = cf,
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Mouth",
		Size = Vector3.new(5.6, 2.4, 0.4),
		Color = tierColor,
		Material = Enum.Material.Neon,
		CFrame = cf * CFrame.new(0, -0.4, 3.1),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Chimney",
		Size = Vector3.new(1.4, 3, 1.4),
		Color = Color3.fromRGB(70, 70, 75),
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(2.5, 4, -1.5),
		Parent = model,
	})
	model.PrimaryPart = base
	model.Parent = parent
	return model
end

-- The shop counter where customers buy.
function ModelFactory.counter(accent: Color3, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Counter"
	local top = ModelFactory.basePart({
		Name = "Top",
		Size = Vector3.new(10, 1, 4),
		Color = accent,
		Material = Enum.Material.Marble,
		CFrame = cf,
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Body",
		Size = Vector3.new(9.6, 3.4, 3.6),
		Color = Color3.fromRGB(80, 60, 45),
		Material = Enum.Material.Wood,
		CFrame = cf * CFrame.new(0, -2.2, 0),
		Parent = model,
	})
	model.PrimaryPart = top
	model.Parent = parent
	return model
end

-- Delivery van: box body + cabin + 4 cylinder wheels.
function ModelFactory.van(accent: Color3, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Van"
	local body = ModelFactory.basePart({
		Name = "Body",
		Size = Vector3.new(11, 4, 6),
		Color = Color3.fromRGB(235, 235, 235),
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(0, 3.2, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Cabin",
		Size = Vector3.new(3, 2.6, 5.6),
		Color = accent,
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(4, 2, 0),
		Parent = model,
	})
	for _, offset in { Vector3.new(3.5, 1.2, 3.1), Vector3.new(3.5, 1.2, -3.1), Vector3.new(-3.5, 1.2, 3.1), Vector3.new(-3.5, 1.2, -3.1) } do
		ModelFactory.basePart({
			Name = "Wheel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.6, 2.2, 2.2),
			Color = Color3.fromRGB(35, 35, 35),
			CFrame = cf * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90)),
			Parent = model,
		})
	end
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

-- Ghost customer: blocky semi-transparent figure, tweened by OrderSystem.
function ModelFactory.customer(shirtColor: Color3, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Customer"
	local torso = ModelFactory.basePart({
		Name = "Torso",
		Size = Vector3.new(2, 2.4, 1.1),
		Color = shirtColor,
		Material = Enum.Material.SmoothPlastic,
		CFrame = cf,
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		Color = Color3.fromRGB(255, 205, 160),
		CFrame = cf * CFrame.new(0, 2, 0),
		Parent = model,
	})
	for _, side in { 1, -1 } do
		ModelFactory.basePart({
			Name = "Leg",
			Size = Vector3.new(0.9, 1.8, 0.9),
			Color = Color3.fromRGB(45, 45, 60),
			CFrame = cf * CFrame.new(side * 0.55, -2.1, 0),
			Parent = model,
		})
	end
	model.PrimaryPart = torso
	model.Parent = parent
	return model
end

-- Traffic car: small low-poly sedan (body, cabin, 4 wheels, headlights).
-- Non-collidable: anchored server-driven decoration.
function ModelFactory.car(bodyColor: Color3, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Car"
	local body = ModelFactory.basePart({
		Name = "Body",
		Size = Vector3.new(7, 1.6, 3.6),
		Color = bodyColor,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CFrame = cf * CFrame.new(0, 1.5, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Cabin",
		Size = Vector3.new(3.2, 1.4, 3.2),
		Color = Color3.fromRGB(180, 220, 235),
		Material = Enum.Material.Glass,
		Transparency = 0.4,
		CanCollide = false,
		CanQuery = false,
		CFrame = cf * CFrame.new(-0.4, 2.9, 0),
		Parent = model,
	})
	for _, offset in { Vector3.new(2.3, 0.7, 1.9), Vector3.new(2.3, 0.7, -1.9), Vector3.new(-2.3, 0.7, 1.9), Vector3.new(-2.3, 0.7, -1.9) } do
		ModelFactory.basePart({
			Name = "Wheel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.7, 1.4, 1.4),
			Color = Color3.fromRGB(30, 30, 32),
			CanCollide = false,
			CanQuery = false,
			CFrame = cf * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90)),
			Parent = model,
		})
	end
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "Headlight",
			Size = Vector3.new(0.2, 0.5, 0.7),
			Color = Color3.fromRGB(255, 240, 170),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			CFrame = cf * CFrame.new(3.55, 1.4, side * 1.2),
			Parent = model,
		})
	end
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

-- Pedestrian NPC: blocky figure with configurable shirt/pants/skin.
function ModelFactory.pedestrian(shirtColor: Color3, pantsColor: Color3, skinColor: Color3, parent: Instance, cf: CFrame): Model
	local model = ModelFactory.customer(shirtColor, parent, cf)
	model.Name = "Pedestrian"
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name == "Head" then
			child.Color = skinColor
		elseif child:IsA("BasePart") and child.Name == "Leg" then
			child.Color = pantsColor
		end
	end
	return model
end

-- Shared delivery zone pad: neon ring + center beacon.
function ModelFactory.zonePad(zoneColor: Color3, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "ZonePad"
	local ring = ModelFactory.basePart({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 24, 24),
		Color = zoneColor,
		Material = Enum.Material.Neon,
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)),
		CanCollide = false,
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Beacon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4, 4, 4),
		Color = zoneColor,
		Material = Enum.Material.Neon,
		CFrame = cf * CFrame.new(0, 6, 0),
		CanCollide = false,
		Parent = model,
	})
	model.PrimaryPart = ring
	model.Parent = parent
	return model
end

-- Floating text sign showing stock/upgrade info, server-updated.
function ModelFactory.infoSign(parent: Instance, cf: CFrame, size: Vector2?)
	local sign = ModelFactory.basePart({
		Name = "InfoSign",
		Size = Vector3.new(4, 2.5, 0.4),
		Color = Color3.fromRGB(25, 25, 30),
		Material = Enum.Material.SmoothPlastic,
		CFrame = cf,
		CanCollide = false,
		Parent = parent,
	})
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset((size and size.X) or 220, (size and size.Y) or 70)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = false
	gui.Parent = sign
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.Text = ""
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.4
	text.Parent = gui
	return sign, text
end

-- Proximity prompt helper with a cost label on the same part.
function ModelFactory.prompt(part: BasePart, actionText: string, objectText: string, holdTime: number?): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = holdTime or 0.4
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return prompt
end

-- ============================ City kit ============================
-- All low-poly: box bodies, a few accent parts, no meshes. Recognizable
-- silhouettes at a glance, cheap to render.

-- Rounded "leaf ball" tree.
function ModelFactory.tree(parent: Instance, cf: CFrame, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Tree"
	local trunk = ModelFactory.basePart({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(rng:NextNumber(4, 6), 0.9, 0.9),
		Color = Color3.fromRGB(95, 65, 40),
		Material = Enum.Material.Wood,
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)) * CFrame.new(0, 2.4, 0),
		Parent = model,
	})
	local leafColor = Color3.fromRGB(rng:NextInteger(60, 90), rng:NextInteger(130, 175), rng:NextInteger(55, 80))
	ModelFactory.basePart({
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(6.5, 6.5, 6.5),
		Color = leafColor,
		Material = Enum.Material.Grass,
		CFrame = cf * CFrame.new(0, 7, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Leaves2",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4.4, 4.4, 4.4),
		Color = leafColor,
		Material = Enum.Material.Grass,
		CFrame = cf * CFrame.new(rng:NextNumber(-1.5, 1.5), 9, rng:NextNumber(-1.5, 1.5)),
		Parent = model,
	})
	model.PrimaryPart = trunk
	model.Parent = parent
	return model
end

-- Palm tree: tilted trunk + 4 flat leaf blades.
function ModelFactory.palm(parent: Instance, cf: CFrame, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Palm"
	local trunk = ModelFactory.basePart({
		Name = "Trunk",
		Size = Vector3.new(0.9, 11, 0.9),
		Color = Color3.fromRGB(140, 105, 70),
		Material = Enum.Material.Wood,
		CFrame = cf * CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, math.rad(rng:NextNumber(-6, 6))) * CFrame.new(0, 5.5, 0),
		Parent = model,
	})
	for i = 1, 4 do
		local angle = (i / 4) * math.pi * 2 + rng:NextNumber(0, 0.4)
		ModelFactory.basePart({
			Name = "Leaf",
			Size = Vector3.new(0.25, 0.15, 5.4),
			Color = Color3.fromRGB(60, 165, 90),
			Material = Enum.Material.Grass,
			CFrame = trunk.CFrame * CFrame.new(0, 5.6, 0) * CFrame.Angles(0, angle, math.rad(-16)) * CFrame.new(0, 0, -2.6),
			CanCollide = false,
			Parent = model,
		})
	end
	model.PrimaryPart = trunk
	model.Parent = parent
	return model
end

-- Street lamp: pole, arm and a glowing head.
function ModelFactory.lamp(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "StreetLamp"
	local pole = ModelFactory.basePart({
		Name = "Pole",
		Size = Vector3.new(0.5, 11, 0.5),
		Color = Color3.fromRGB(60, 60, 65),
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(0, 5.5, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.4, 1.4, 1.4),
		Color = Color3.fromRGB(255, 235, 160),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CFrame = cf * CFrame.new(0, 11.3, 0),
		Parent = model,
	})
	model.PrimaryPart = pole
	model.Parent = parent
	return model
end

-- Park bench: seat, backrest and legs.
function ModelFactory.bench(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "Bench"
	local seat = ModelFactory.basePart({
		Name = "Seat",
		Size = Vector3.new(6, 0.4, 1.8),
		Color = Color3.fromRGB(120, 85, 55),
		Material = Enum.Material.WoodPlanks,
		CFrame = cf * CFrame.new(0, 1.4, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Back",
		Size = Vector3.new(6, 1.6, 0.4),
		Color = Color3.fromRGB(120, 85, 55),
		Material = Enum.Material.WoodPlanks,
		CFrame = cf * CFrame.new(0, 2.3, -0.8),
		Parent = model,
	})
	for _, side in { -2.4, 2.4 } do
		ModelFactory.basePart({
			Name = "Leg",
			Size = Vector3.new(0.4, 1.4, 1.6),
			Color = Color3.fromRGB(70, 70, 75),
			Material = Enum.Material.Metal,
			CFrame = cf * CFrame.new(side, 0.7, 0),
			Parent = model,
		})
	end
	model.PrimaryPart = seat
	model.Parent = parent
	return model
end

-- Cafe table: round top + pedestal + two stools.
function ModelFactory.tableSet(parent: Instance, cf: CFrame, accent: Color3)
	local model = Instance.new("Model")
	model.Name = "TableSet"
	local top = ModelFactory.basePart({
		Name = "Top",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35, 4, 4),
		Color = Color3.fromRGB(235, 235, 235),
		Material = Enum.Material.Marble,
		CanCollide = false,
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)) * CFrame.new(0, 2.8, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Pedestal",
		Size = Vector3.new(0.5, 2.8, 0.5),
		Color = Color3.fromRGB(70, 70, 75),
		Material = Enum.Material.Metal,
		CanCollide = false,
		CFrame = cf * CFrame.new(0, 1.4, 0),
		Parent = model,
	})
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "Stool",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 1.5, 1.5),
			Color = accent,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CFrame = cf * CFrame.Angles(0, 0, math.rad(90)) * CFrame.new(0, 0.75, side * 3.4),
			Parent = model,
		})
	end
	model.PrimaryPart = top
	model.Parent = parent
	return model
end

-- =========================== Buildings ===========================

-- Pitched roof from two slanted slabs meeting at a ridge (runs along Z).
local function pitchedRoof(parent: Instance, cf: CFrame, width: number, depth: number, wallHeight: number, roofColor: Color3)
	local rise = width * 0.3
	local slabLen = math.sqrt((width / 2) ^ 2 + rise ^ 2) + 0.6
	local angle = math.atan(rise / (width / 2))
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "Roof",
			Size = Vector3.new(slabLen, 0.5, depth + 1.2),
			Color = roofColor,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CFrame = cf * CFrame.new(side * width / 4, wallHeight + rise / 2, 0)
				* CFrame.Angles(0, 0, side * angle),
			Parent = parent,
		})
	end
end

-- Generic low-poly building. `style` controls silhouette:
--   downtown / oldtown / suburbs / industrial / waterfront
function ModelFactory.building(style: string, parent: Instance, cf: CFrame, width: number, depth: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Building"

	local palette
	if style == "downtown" then
		palette = {
			walls = { Color3.fromRGB(55, 62, 88), Color3.fromRGB(48, 52, 72), Color3.fromRGB(66, 70, 95), Color3.fromRGB(40, 44, 62) },
			roof = Color3.fromRGB(35, 38, 52),
			window = Color3.fromRGB(150, 220, 255),
			pitched = false,
			hMin = 36, hMax = 78,
		}
	elseif style == "oldtown" then
		palette = {
			walls = { Color3.fromRGB(160, 95, 70), Color3.fromRGB(175, 120, 85), Color3.fromRGB(150, 90, 60), Color3.fromRGB(185, 140, 100) },
			roof = Color3.fromRGB(150, 70, 50),
			window = Color3.fromRGB(255, 220, 140),
			pitched = true,
			hMin = 14, hMax = 22,
		}
	elseif style == "suburbs" then
		palette = {
			walls = { Color3.fromRGB(225, 215, 190), Color3.fromRGB(200, 220, 190), Color3.fromRGB(215, 200, 220), Color3.fromRGB(230, 230, 230) },
			roof = Color3.fromRGB(110, 80, 60),
			window = Color3.fromRGB(190, 230, 255),
			pitched = true,
			hMin = 9, hMax = 12,
		}
	elseif style == "industrial" then
		palette = {
			walls = { Color3.fromRGB(120, 120, 118), Color3.fromRGB(135, 110, 90), Color3.fromRGB(105, 108, 112) },
			roof = Color3.fromRGB(85, 85, 88),
			window = Color3.fromRGB(200, 210, 215),
			pitched = false,
			hMin = 10, hMax = 15,
		}
	else -- waterfront
		palette = {
			walls = { Color3.fromRGB(245, 205, 180), Color3.fromRGB(180, 230, 225), Color3.fromRGB(250, 235, 200), Color3.fromRGB(160, 210, 220) },
			roof = Color3.fromRGB(60, 140, 140),
			window = Color3.fromRGB(255, 245, 210),
			pitched = true,
			hMin = 8, hMax = 12,
		}
	end

	local height = rng:NextNumber(palette.hMin, palette.hMax)
	local wallColor = palette.walls[rng:NextInteger(1, #palette.walls)]

	local body = ModelFactory.basePart({
		Name = "Body",
		Size = Vector3.new(width, height, depth),
		Color = wallColor,
		Material = if style == "downtown" then Enum.Material.Glass else Enum.Material.SmoothPlastic,
		CFrame = cf * CFrame.new(0, height / 2, 0),
		Parent = model,
	})

	if palette.pitched then
		pitchedRoof(model, cf, width, depth, height, palette.roof)
		if rng:NextNumber() < 0.5 then
			ModelFactory.basePart({
				Name = "Chimney",
				Size = Vector3.new(1.2, 3, 1.2),
				Color = Color3.fromRGB(120, 70, 55),
				CanCollide = false,
				CFrame = cf * CFrame.new(width * 0.25, height + width * 0.28, -depth * 0.2),
				Parent = model,
			})
		end
	else
		ModelFactory.basePart({
			Name = "Roof",
			Size = Vector3.new(width + 1.4, 0.8, depth + 1.4),
			Color = palette.roof,
			CanCollide = false,
			CFrame = cf * CFrame.new(0, height + 0.4, 0),
			Parent = model,
		})
		if style == "downtown" and height > 50 then
			-- Skyscraper setback: a smaller glass crown on top.
			ModelFactory.basePart({
				Name = "Crown",
				Size = Vector3.new(width * 0.55, height * 0.22, depth * 0.55),
				Color = wallColor,
				Material = Enum.Material.Glass,
				CFrame = cf * CFrame.new(0, height + height * 0.11, 0),
				Parent = model,
			})
			ModelFactory.basePart({
				Name = "CrownLight",
				Size = Vector3.new(width * 0.2, 1.2, depth * 0.2),
				Color = Color3.fromRGB(120, 220, 255),
				Material = Enum.Material.Neon,
				CanCollide = false,
				CFrame = cf * CFrame.new(0, height * 1.25, 0),
				Parent = model,
			})
		end
		if style == "industrial" then
			-- Roll-up door on the front face.
			ModelFactory.basePart({
				Name = "RollDoor",
				Size = Vector3.new(width * 0.4, height * 0.6, 0.3),
				Color = Color3.fromRGB(160, 160, 155),
				Material = Enum.Material.CorrodedMetal,
				CFrame = cf * CFrame.new(0, height * 0.3, depth / 2 + 0.1),
				Parent = model,
			})
		end
	end

	-- Windows: quads on the front face in a loose grid, plus sides for downtown.
	local cols = math.max(1, math.floor(width / 10))
	local rows = if palette.pitched then math.min(2, math.max(1, math.floor(height / 8))) else math.max(1, math.floor(height / 12))
	for r = 1, rows do
		for c = 1, cols do
			if rng:NextNumber() < 0.85 then
				local wx = (c - 0.5) * (width / cols) - width / 2
				local wy = (r - 0.5) * (height / rows)
				ModelFactory.basePart({
					Name = "Window",
					Size = Vector3.new(4.4, if palette.pitched then 3.2 else 5, 0.25),
					Color = palette.window,
					Material = Enum.Material.SmoothPlastic,
					Transparency = 0.35,
					CanCollide = false,
					CFrame = cf * CFrame.new(wx, wy, depth / 2 + 0.12),
					Parent = model,
				})
			end
		end
	end

	model.PrimaryPart = body
	model.Parent = parent
	return model
end

-- ======================= Restaurant building =======================

-- A recognizable low-poly pizzeria: box hall, open storefront with a
-- striped awning, big roof sign with a neon pizza medallion, windows on
-- the sides and a chimney over the ovens. Built on claim by PlotManager.
-- `cf` is the building center (floor level). Front faces local -Z.
function ModelFactory.restaurantBuilding(accent: Color3, baseColor: Color3, shopName: string, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Restaurant"

	local W, D, H = 52, 36, 14 -- width (x), depth (z), wall height

	-- Floor slab.
	ModelFactory.basePart({
		Name = "Floor",
		Size = Vector3.new(W, 0.5, D),
		Color = baseColor,
		Material = Enum.Material.Concrete,
		CFrame = cf * CFrame.new(0, 0.25, 0),
		Parent = model,
	})

	-- Back wall (+Z end).
	ModelFactory.basePart({
		Name = "BackWall",
		Size = Vector3.new(W, H, 1),
		Color = baseColor,
		Material = Enum.Material.SmoothPlastic,
		CFrame = cf * CFrame.new(0, H / 2, D / 2 - 0.5),
		Parent = model,
	})
	-- Side walls.
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "SideWall",
			Size = Vector3.new(1, H, D),
			Color = baseColor,
			Material = Enum.Material.SmoothPlastic,
			CFrame = cf * CFrame.new(side * (W / 2 - 0.5), H / 2, 0),
			Parent = model,
		})
	end
	-- Front wall (-Z end) with a wide doorway in the middle.
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "FrontWall",
			Size = Vector3.new(W / 2 - 9, H, 1),
			Color = baseColor,
			Material = Enum.Material.SmoothPlastic,
			CFrame = cf * CFrame.new(side * (9 + (W / 2 - 9) / 2), H / 2, -D / 2 + 0.5),
			Parent = model,
		})
	end
	ModelFactory.basePart({
		Name = "DoorHeader",
		Size = Vector3.new(18, H - 10, 1),
		Color = baseColor,
		Material = Enum.Material.SmoothPlastic,
		CFrame = cf * CFrame.new(0, 10 + (H - 10) / 2, -D / 2 + 0.5),
		Parent = model,
	})

	-- Flat roof + parapet.
	ModelFactory.basePart({
		Name = "Roof",
		Size = Vector3.new(W + 2, 0.6, D + 2),
		Color = Color3.fromRGB(70, 70, 78),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CFrame = cf * CFrame.new(0, H + 0.3, 0),
		Parent = model,
	})
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "Parapet",
			Size = Vector3.new(W + 2, 1.2, 0.8),
			Color = baseColor,
			CanCollide = false,
			CFrame = cf * CFrame.new(0, H + 1.2, side * (D / 2 + 0.6)),
			Parent = model,
		})
	end

	-- Big rooftop sign: board + shop name + neon pizza medallion.
	local signBoard = ModelFactory.basePart({
		Name = "Sign",
		Size = Vector3.new(26, 6, 1),
		Color = Color3.fromRGB(28, 28, 34),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CFrame = cf * CFrame.new(0, H + 4.5, -D / 2 + 1),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "SignPizza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.7, 4.4, 4.4),
		Color = Color3.fromRGB(240, 190, 90),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CFrame = signBoard.CFrame * CFrame.new(-10.5, 0, 0.5) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = model,
	})
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 30
	surfaceGui.Parent = signBoard
	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.Font = Enum.Font.GothamBold
	signText.TextScaled = true
	signText.Text = shopName
	signText.TextColor3 = accent
	signText.TextStrokeColor3 = Color3.new(0, 0, 0)
	signText.TextStrokeTransparency = 0.3
	signText.TextTruncate = Enum.TextTruncate.AtEnd
	signText.Parent = surfaceGui

	-- Striped awning over the storefront.
	for i = 0, 5 do
		ModelFactory.basePart({
			Name = "Awning",
			Size = Vector3.new(W / 6 - 0.2, 0.3, 6),
			Color = if i % 2 == 0 then accent else Color3.fromRGB(240, 240, 240),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CFrame = cf * CFrame.new(-W / 2 + W / 12 + i * (W / 6), 10.4, -D / 2 - 2.8)
				* CFrame.Angles(math.rad(18), 0, 0),
			Parent = model,
		})
	end

	-- Windows on both side walls.
	for _, side in { -1, 1 } do
		for _, wz in { -10, 4 } do
			ModelFactory.basePart({
				Name = "Window",
				Size = Vector3.new(0.25, 6, 9),
				Color = Color3.fromRGB(190, 230, 255),
				Material = Enum.Material.SmoothPlastic,
				Transparency = 0.35,
				CanCollide = false,
				CFrame = cf * CFrame.new(side * (W / 2 + 0.05), 7.5, wz),
				Parent = model,
			})
		end
	end

	-- Chimney above the oven corner (-X side).
	ModelFactory.basePart({
		Name = "Chimney",
		Size = Vector3.new(2.4, 4.5, 2.4),
		Color = Color3.fromRGB(110, 75, 60),
		CanCollide = false,
		CFrame = cf * CFrame.new(-16, H + 2, 6),
		Parent = model,
	})

	model.PrimaryPart = model.Floor :: BasePart
	model.Parent = parent
	return model
end

return ModelFactory
