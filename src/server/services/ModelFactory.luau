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

return ModelFactory
