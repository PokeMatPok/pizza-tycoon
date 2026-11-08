--!strict
-- ModelFactory: the "model service". Every 3D asset in the game is built
-- procedurally here from anchored parts, so the game needs zero uploaded
-- meshes. When you later import real meshes (Meshy/Sloyd/Creator Store),
-- swap the body of the corresponding builder function only.
--
-- Real scale reference: a Roblox avatar is ~5 studs tall (R6: legs 2,
-- torso 2, head ~1). Door openings are 3 avatars tall, roads are 20 studs
-- (4 cars wide), downtown towers 60-140 studs.

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

-- ============================ Avatars ============================
-- Classic R6 block avatar: head, torso, two arms, two legs (~5 studs tall).
-- `cf` is the GROUND CFrame (feet on cf). Model pivot = torso center,
-- 3 studs above the ground. Limbs are named so poseWalk can animate them.

local SKIN_TONES = {
	Color3.fromRGB(255, 205, 160),
	Color3.fromRGB(235, 185, 145),
	Color3.fromRGB(205, 155, 115),
	Color3.fromRGB(160, 110, 75),
}

local function r6Avatar(name: string, shirtColor: Color3, pantsColor: Color3, skinColor: Color3, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = name
	local torso = ModelFactory.basePart({
		Name = "Torso",
		Size = Vector3.new(2, 2, 1),
		Color = shirtColor,
		Material = Enum.Material.SmoothPlastic,
		CFrame = cf * CFrame.new(0, 3, 0),
		CanCollide = false,
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.2, 1.2, 1.2),
		Color = skinColor,
		Material = Enum.Material.SmoothPlastic,
		CFrame = cf * CFrame.new(0, 4.6, 0),
		CanCollide = false,
		Parent = model,
	})
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = if side < 0 then "LeftArm" else "RightArm",
			Size = Vector3.new(1, 2, 1),
			Color = shirtColor,
			Material = Enum.Material.SmoothPlastic,
			CFrame = torso.CFrame * CFrame.new(side * 1.5, 0.7, 0) * CFrame.new(0, -1, 0),
			CanCollide = false,
			Parent = model,
		})
		ModelFactory.basePart({
			Name = if side < 0 then "LeftLeg" else "RightLeg",
			Size = Vector3.new(1, 2, 1),
			Color = pantsColor,
			Material = Enum.Material.SmoothPlastic,
			CFrame = torso.CFrame * CFrame.new(side * 0.5, -1, 0) * CFrame.new(0, -1, 0),
			CanCollide = false,
			Parent = model,
		})
	end
	model.PrimaryPart = torso
	model.Parent = parent
	return model
end

-- Pose an R6 avatar's limbs for a walk cycle. `swing` in [-1, 1]
-- (0 = standing). Arms and legs counter-swing like a real walk.
function ModelFactory.poseWalk(model: Model, swing: number)
	local torso = model.PrimaryPart
	if not torso then
		return
	end
	local base = torso.CFrame
	for _, side in { -1, 1 } do
		local arm = model:FindFirstChild(if side < 0 then "LeftArm" else "RightArm")
		if arm and arm:IsA("BasePart") then
			arm.CFrame = base * CFrame.new(side * 1.5, 0.7, 0)
				* CFrame.Angles(side * swing, 0, 0) * CFrame.new(0, -1, 0)
		end
		local leg = model:FindFirstChild(if side < 0 then "LeftLeg" else "RightLeg")
		if leg and leg:IsA("BasePart") then
			leg.CFrame = base * CFrame.new(side * 0.5, -1, 0)
				* CFrame.Angles(-side * swing, 0, 0) * CFrame.new(0, -1, 0)
		end
	end
end

-- Customer avatar (tweened by OrderSystem / Production).
function ModelFactory.customer(shirtColor: Color3, parent: Instance, cf: CFrame): Model
	return r6Avatar("Customer", shirtColor, Color3.fromRGB(45, 45, 60), SKIN_TONES[2], parent, cf)
end

-- Pedestrian NPC: R6 avatar with configurable shirt/pants/skin.
function ModelFactory.pedestrian(shirtColor: Color3, pantsColor: Color3, skinColor: Color3, parent: Instance, cf: CFrame): Model
	return r6Avatar("Pedestrian", shirtColor, pantsColor, skinColor, parent, cf)
end

-- Random outfit helpers used by the Pedestrians service.
function ModelFactory.randomSkinTone(rng: Random): Color3
	return SKIN_TONES[rng:NextInteger(1, #SKIN_TONES)]
end

function ModelFactory.randomShirt(rng: Random): Color3
	local palette = {
		Color3.fromRGB(225, 80, 70), Color3.fromRGB(80, 120, 220), Color3.fromRGB(240, 200, 70),
		Color3.fromRGB(90, 180, 110), Color3.fromRGB(230, 120, 160), Color3.fromRGB(150, 110, 200),
		Color3.fromRGB(240, 240, 240), Color3.fromRGB(60, 70, 90), Color3.fromRGB(240, 140, 60),
	}
	return palette[rng:NextInteger(1, #palette)]
end

function ModelFactory.randomPants(rng: Random): Color3
	local palette = {
		Color3.fromRGB(50, 55, 75), Color3.fromRGB(75, 60, 50), Color3.fromRGB(40, 40, 45),
		Color3.fromRGB(100, 80, 60), Color3.fromRGB(90, 95, 105),
	}
	return palette[rng:NextInteger(1, #palette)]
end

-- ============================ Food & shop ============================

-- A pizza. One flat cylinder body + topping dots. Cheap: 5 parts.
function ModelFactory.pizza(recipeColor: Color3, toppingColor: Color3, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Pizza"
	local body = ModelFactory.basePart({
		Shape = Enum.PartType.Cylinder,
		Name = "Body",
		Size = Vector3.new(0.4, 4, 4),
		Color = recipeColor,
		Material = Enum.Material.Neon,
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)),
		CanCollide = false,
		Parent = model,
	})
	local rng = Random.new()
	for i = 1, 4 do
		local angle = (i / 4) * math.pi * 2 + rng:NextNumber(0, 0.5)
		local offset = CFrame.new(math.cos(angle) * 1.0, 0.23, math.sin(angle) * 1.0)
		ModelFactory.basePart({
			Name = "Topping",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.05, 0.75, 0.75),
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
		Size = Vector3.new(4, 3, 4),
		Color = ingredientColor,
		Material = Enum.Material.WoodPlanks,
		CFrame = cf,
		Parent = model,
	})
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
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
-- `cf` is the GROUND center (frame sits on the floor); mouth faces +Z.
function ModelFactory.oven(tierColor: Color3, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Oven"
	local base = ModelFactory.basePart({
		Name = "Frame",
		Size = Vector3.new(9, 6.5, 7),
		Color = Color3.fromRGB(90, 90, 95),
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(0, 3.25, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Mouth",
		Size = Vector3.new(6.4, 3.2, 0.5),
		Color = tierColor,
		Material = Enum.Material.Neon,
		CFrame = cf * CFrame.new(0, 1.6, 3.55),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Hood",
		Size = Vector3.new(9.6, 1.2, 7.4),
		Color = Color3.fromRGB(110, 110, 116),
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(0, 7.1, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Chimney",
		Size = Vector3.new(2, 4.5, 2),
		Color = Color3.fromRGB(70, 70, 75),
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(-3, 9.4, -1.5),
		Parent = model,
	})
	model.PrimaryPart = base
	model.Parent = parent
	return model
end

-- The shop counter where customers buy.
-- `cf` is the TOP SURFACE center of the counter.
function ModelFactory.counter(accent: Color3, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Counter"
	local top = ModelFactory.basePart({
		Name = "Top",
		Size = Vector3.new(14, 1.2, 5),
		Color = accent,
		Material = Enum.Material.Marble,
		CFrame = cf,
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Body",
		Size = Vector3.new(13.4, 4.2, 4.4),
		Color = Color3.fromRGB(80, 60, 45),
		Material = Enum.Material.Wood,
		CFrame = cf * CFrame.new(0, -2.7, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Kick",
		Size = Vector3.new(13.8, 0.5, 4.8),
		Color = Color3.fromRGB(50, 38, 28),
		Material = Enum.Material.Wood,
		CFrame = cf * CFrame.new(0, -4.75, 0),
		Parent = model,
	})
	model.PrimaryPart = top
	model.Parent = parent
	return model
end

-- Delivery van: box body + cabin + 4 cylinder wheels. Length along X.
-- `cf` is the GROUND center (wheels touch the ground).
function ModelFactory.van(accent: Color3, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Van"
	local body = ModelFactory.basePart({
		Name = "Body",
		Size = Vector3.new(13, 4.6, 6.6),
		Color = Color3.fromRGB(235, 235, 235),
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(0, 3.7, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Cabin",
		Size = Vector3.new(3.4, 3, 6),
		Color = accent,
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(4.8, 2.9, 0),
		Parent = model,
	})
	for _, offset in { Vector3.new(4.4, 1.1, 2.3), Vector3.new(4.4, 1.1, -2.3), Vector3.new(-4.4, 1.1, 2.3), Vector3.new(-4.4, 1.1, -2.3) } do
		ModelFactory.basePart({
			Name = "Wheel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.8, 2.2, 2.2),
			Color = Color3.fromRGB(35, 35, 35),
			CFrame = cf * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90)),
			Parent = model,
		})
	end
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "Headlight",
			Size = Vector3.new(0.2, 0.8, 1.2),
			Color = Color3.fromRGB(255, 240, 170),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CFrame = cf * CFrame.new(6.55, 2.6, side * 2),
			Parent = model,
		})
	end
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

-- Traffic car: low-poly sedan. Length along Z so CFrame.lookAt (forward
-- = -Z) drives it nose-first. `cf` is the GROUND center (wheels touch).
function ModelFactory.car(bodyColor: Color3, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Car"
	local body = ModelFactory.basePart({
		Name = "Body",
		Size = Vector3.new(4.2, 1.7, 8.5),
		Color = bodyColor,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CFrame = cf * CFrame.new(0, 1.6, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Cabin",
		Size = Vector3.new(3.8, 1.5, 4),
		Color = Color3.fromRGB(180, 220, 235),
		Material = Enum.Material.Glass,
		Transparency = 0.4,
		CanCollide = false,
		CanQuery = false,
		CFrame = cf * CFrame.new(0, 3.1, 0.3),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Bumper",
		Size = Vector3.new(4.3, 0.8, 0.6),
		Color = Color3.fromRGB(50, 50, 55),
		CanCollide = false,
		CanQuery = false,
		CFrame = cf * CFrame.new(0, 1.0, -4.45),
		Parent = model,
	})
	for _, offset in { Vector3.new(1.95, 0.8, -2.6), Vector3.new(1.95, 0.8, 2.6), Vector3.new(-1.95, 0.8, -2.6), Vector3.new(-1.95, 0.8, 2.6) } do
		ModelFactory.basePart({
			Name = "Wheel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, 1.6, 1.6),
			Color = Color3.fromRGB(30, 30, 32),
			CanCollide = false,
			CanQuery = false,
			CFrame = cf * CFrame.new(offset),
			Parent = model,
		})
	end
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "Headlight",
			Size = Vector3.new(0.7, 0.5, 0.2),
			Color = Color3.fromRGB(255, 240, 170),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			CFrame = cf * CFrame.new(side * 1.3, 1.9, -4.3),
			Parent = model,
		})
		ModelFactory.basePart({
			Name = "Taillight",
			Size = Vector3.new(0.7, 0.5, 0.2),
			Color = Color3.fromRGB(255, 60, 50),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			CFrame = cf * CFrame.new(side * 1.3, 1.9, 4.3),
			Parent = model,
		})
	end
	model.PrimaryPart = body
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
		Size = Vector3.new(0.6, 26, 26),
		Color = zoneColor,
		Material = Enum.Material.Neon,
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)),
		CanCollide = false,
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Beacon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4.5, 4.5, 4.5),
		Color = zoneColor,
		Material = Enum.Material.Neon,
		CFrame = cf * CFrame.new(0, 7, 0),
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
		Size = Vector3.new(rng:NextNumber(5, 7.5), 1.1, 1.1),
		Color = Color3.fromRGB(95, 65, 40),
		Material = Enum.Material.Wood,
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)) * CFrame.new(0, 2.7, 0),
		Parent = model,
	})
	local leafColor = Color3.fromRGB(rng:NextInteger(60, 90), rng:NextInteger(130, 175), rng:NextInteger(55, 80))
	ModelFactory.basePart({
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(8.5, 8.5, 8.5),
		Color = leafColor,
		Material = Enum.Material.Grass,
		CFrame = cf * CFrame.new(0, 8.5, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Leaves2",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(5.5, 5.5, 5.5),
		Color = leafColor,
		Material = Enum.Material.Grass,
		CFrame = cf * CFrame.new(rng:NextNumber(-2, 2), 11.5, rng:NextNumber(-2, 2)),
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
		Size = Vector3.new(1, 13, 1),
		Color = Color3.fromRGB(140, 105, 70),
		Material = Enum.Material.Wood,
		CFrame = cf * CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, math.rad(rng:NextNumber(-6, 6))) * CFrame.new(0, 6.5, 0),
		Parent = model,
	})
	for i = 1, 4 do
		local angle = (i / 4) * math.pi * 2 + rng:NextNumber(0, 0.4)
		ModelFactory.basePart({
			Name = "Leaf",
			Size = Vector3.new(0.3, 0.18, 6.4),
			Color = Color3.fromRGB(60, 165, 90),
			Material = Enum.Material.Grass,
			CFrame = trunk.CFrame * CFrame.new(0, 6.6, 0) * CFrame.Angles(0, angle, math.rad(-18)) * CFrame.new(0, 0, -3.1),
			CanCollide = false,
			Parent = model,
		})
	end
	model.PrimaryPart = trunk
	model.Parent = parent
	return model
end

-- Street lamp: pole, arm reaching over the road (local -Z) and a glowing
-- head at the arm's end. Orient `cf` with lookAt toward the road.
function ModelFactory.lamp(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "StreetLamp"
	local pole = ModelFactory.basePart({
		Name = "Pole",
		Size = Vector3.new(0.6, 13, 0.6),
		Color = Color3.fromRGB(60, 60, 65),
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(0, 6.5, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Arm",
		Size = Vector3.new(0.4, 0.4, 3.5),
		Color = Color3.fromRGB(60, 60, 65),
		Material = Enum.Material.Metal,
		CanCollide = false,
		CFrame = cf * CFrame.new(0, 12.9, -1.75),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		Color = Color3.fromRGB(255, 235, 160),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CFrame = cf * CFrame.new(0, 12.7, -3.4),
		Parent = model,
	})
	model.PrimaryPart = pole
	model.Parent = parent
	return model
end

-- Traffic light: pole + arm + head with red/amber/green. Local -Z faces
-- the road it controls. ~9 parts.
function ModelFactory.trafficLight(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "TrafficLight"
	local pole = ModelFactory.basePart({
		Name = "Pole",
		Size = Vector3.new(0.7, 15, 0.7),
		Color = Color3.fromRGB(50, 50, 55),
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(0, 7.5, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Arm",
		Size = Vector3.new(0.5, 0.5, 7),
		Color = Color3.fromRGB(50, 50, 55),
		Material = Enum.Material.Metal,
		CanCollide = false,
		CFrame = cf * CFrame.new(0, 14.6, -3.5),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Head",
		Size = Vector3.new(1.8, 4.6, 1.1),
		Color = Color3.fromRGB(35, 35, 40),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CFrame = cf * CFrame.new(0, 12.3, -7),
		Parent = model,
	})
	local lights = {
		{ Color3.fromRGB(255, 60, 50), 13.8 },
		{ Color3.fromRGB(255, 190, 60), 12.3 },
		{ Color3.fromRGB(90, 235, 120), 10.8 },
	}
	for i, entry in lights do
		ModelFactory.basePart({
			Name = "Light" .. i,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.1, 1.1, 1.1),
			Color = entry[1],
			Material = if i == 3 then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanQuery = false,
			CFrame = cf * CFrame.new(0, entry[2], -7.6),
			Parent = model,
		})
	end
	model.PrimaryPart = pole
	model.Parent = parent
	return model
end

-- Bus stop shelter: two poles, roof, glass back, bench. Local -Z = road.
function ModelFactory.busStop(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "BusStop"
	local roof = ModelFactory.basePart({
		Name = "Roof",
		Size = Vector3.new(10, 0.5, 5),
		Color = Color3.fromRGB(40, 45, 55),
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(0, 8, 0.5),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "BackPanel",
		Size = Vector3.new(9.5, 5.5, 0.3),
		Color = Color3.fromRGB(140, 190, 210),
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		CFrame = cf * CFrame.new(0, 5.3, 2.6),
		Parent = model,
	})
	for _, side in { -4.2, 4.2 } do
		ModelFactory.basePart({
			Name = "Pole",
			Size = Vector3.new(0.4, 8, 0.4),
			Color = Color3.fromRGB(60, 60, 65),
			Material = Enum.Material.Metal,
			CFrame = cf * CFrame.new(side, 4, 2.4),
			Parent = model,
		})
	end
	ModelFactory.basePart({
		Name = "Bench",
		Size = Vector3.new(6.5, 0.5, 1.8),
		Color = Color3.fromRGB(120, 85, 55),
		Material = Enum.Material.WoodPlanks,
		CFrame = cf * CFrame.new(0, 2.2, 0.8),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "BenchLeg",
		Size = Vector3.new(6, 1.9, 0.4),
		Color = Color3.fromRGB(70, 70, 75),
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(0, 1, 1.55),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Sign",
		Size = Vector3.new(2.6, 4.2, 0.2),
		Color = Color3.fromRGB(30, 90, 200),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CFrame = cf * CFrame.new(4.6, 6, 2.5),
		Parent = model,
	})
	model.PrimaryPart = roof
	model.Parent = parent
	return model
end

-- Fire hydrant.
function ModelFactory.hydrant(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "Hydrant"
	local body = ModelFactory.basePart({
		Name = "Body",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.9, 1.3, 1.3),
		Color = Color3.fromRGB(210, 40, 35),
		CFrame = cf * CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Cap",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.8, 0.8, 0.8),
		Color = Color3.fromRGB(210, 40, 35),
		CFrame = cf * CFrame.new(0, 2.25, 0),
		Parent = model,
	})
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "Nozzle",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 0.55, 0.55),
			Color = Color3.fromRGB(180, 35, 30),
			CFrame = cf * CFrame.new(side * 0.85, 1.35, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Parent = model,
		})
	end
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

-- Trash bin.
function ModelFactory.trashBin(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "TrashBin"
	local body = ModelFactory.basePart({
		Name = "Body",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.2, 1.7, 1.7),
		Color = Color3.fromRGB(45, 60, 50),
		CFrame = cf * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Lid",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 1.9, 1.9),
		Color = Color3.fromRGB(30, 40, 35),
		CFrame = cf * CFrame.new(0, 3.35, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = model,
	})
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

-- Plaza fountain: ring wall, neon water disc, column and finial ball.
function ModelFactory.fountain(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "Fountain"
	local ring = ModelFactory.basePart({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.6, 18, 18),
		Color = Color3.fromRGB(180, 175, 165),
		Material = Enum.Material.Concrete,
		CFrame = cf * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Water",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.2, 15, 15),
		Color = Color3.fromRGB(120, 200, 235),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CFrame = cf * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Column",
		Size = Vector3.new(2.2, 5.5, 2.2),
		Color = Color3.fromRGB(180, 175, 165),
		Material = Enum.Material.Concrete,
		CFrame = cf * CFrame.new(0, 5.3, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Basin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 5, 5),
		Color = Color3.fromRGB(180, 175, 165),
		Material = Enum.Material.Concrete,
		CanCollide = false,
		CFrame = cf * CFrame.new(0, 8.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Finial",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.2, 2.2, 2.2),
		Color = Color3.fromRGB(140, 210, 240),
		Material = Enum.Material.Neon,
		Transparency = 0.3,
		CanCollide = false,
		CFrame = cf * CFrame.new(0, 9.9, 0),
		Parent = model,
	})
	model.PrimaryPart = ring
	model.Parent = parent
	return model
end

-- Street food cart: body, counter, wheels and a striped canopy.
function ModelFactory.foodCart(parent: Instance, cf: CFrame, accent: Color3)
	local model = Instance.new("Model")
	model.Name = "FoodCart"
	local body = ModelFactory.basePart({
		Name = "Body",
		Size = Vector3.new(5.4, 2.6, 2.6),
		Color = Color3.fromRGB(225, 90, 70),
		Material = Enum.Material.SmoothPlastic,
		CFrame = cf * CFrame.new(0, 2, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Top",
		Size = Vector3.new(5.6, 0.35, 2.8),
		Color = Color3.fromRGB(240, 240, 240),
		Material = Enum.Material.Marble,
		CFrame = cf * CFrame.new(0, 3.45, 0),
		Parent = model,
	})
	for _, offset in { Vector3.new(1.8, 0.65, 1.3), Vector3.new(1.8, 0.65, -1.3), Vector3.new(-1.8, 0.65, 1.3), Vector3.new(-1.8, 0.65, -1.3) } do
		ModelFactory.basePart({
			Name = "Wheel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 1.3, 1.3),
			Color = Color3.fromRGB(40, 40, 40),
			CanCollide = false,
			CFrame = cf * CFrame.new(offset),
			Parent = model,
		})
	end
	ModelFactory.basePart({
		Name = "CanopyPole",
		Size = Vector3.new(0.3, 5.5, 0.3),
		Color = Color3.fromRGB(80, 80, 85),
		Material = Enum.Material.Metal,
		CanCollide = false,
		CFrame = cf * CFrame.new(0, 6, 0),
		Parent = model,
	})
	for i = 0, 3 do
		ModelFactory.basePart({
			Name = "CanopyBlade",
			Size = Vector3.new(0.25, 3.6, 3),
			Color = if i % 2 == 0 then accent else Color3.fromRGB(240, 240, 240),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CFrame = cf * CFrame.new(0, 8.2, 0)
				* CFrame.Angles(math.rad(-16), (i / 4) * math.pi * 2, 0) * CFrame.new(0, 1.6, 0),
			Parent = model,
		})
	end
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

-- Patio umbrella: pole + 4 canopy blades.
function ModelFactory.umbrella(parent: Instance, cf: CFrame, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Umbrella"
	local pole = ModelFactory.basePart({
		Name = "Pole",
		Size = Vector3.new(0.35, 8, 0.35),
		Color = Color3.fromRGB(80, 80, 85),
		Material = Enum.Material.Metal,
		CanCollide = false,
		CFrame = cf * CFrame.new(0, 4, 0),
		Parent = model,
	})
	for i = 0, 3 do
		ModelFactory.basePart({
			Name = "Blade",
			Size = Vector3.new(0.25, 4.4, 3.2),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CFrame = cf * CFrame.new(0, 7.9, 0)
				* CFrame.Angles(math.rad(-15), (i / 4) * math.pi * 2, 0) * CFrame.new(0, 2, 0),
			Parent = model,
		})
	end
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
		Size = Vector3.new(7, 0.5, 2),
		Color = Color3.fromRGB(120, 85, 55),
		Material = Enum.Material.WoodPlanks,
		CFrame = cf * CFrame.new(0, 1.9, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Back",
		Size = Vector3.new(7, 2.2, 0.4),
		Color = Color3.fromRGB(120, 85, 55),
		Material = Enum.Material.WoodPlanks,
		CFrame = cf * CFrame.new(0, 3.2, -0.95),
		Parent = model,
	})
	for _, side in { -2.9, 2.9 } do
		ModelFactory.basePart({
			Name = "Leg",
			Size = Vector3.new(0.5, 1.9, 1.8),
			Color = Color3.fromRGB(70, 70, 75),
			Material = Enum.Material.Metal,
			CFrame = cf * CFrame.new(side, 0.95, 0),
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
		Size = Vector3.new(0.4, 4.5, 4.5),
		Color = Color3.fromRGB(235, 235, 235),
		Material = Enum.Material.Marble,
		CanCollide = false,
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)) * CFrame.new(0, 3.2, 0),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "Pedestal",
		Size = Vector3.new(0.6, 3.2, 0.6),
		Color = Color3.fromRGB(70, 70, 75),
		Material = Enum.Material.Metal,
		CanCollide = false,
		CFrame = cf * CFrame.new(0, 1.6, 0),
		Parent = model,
	})
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "Stool",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.35, 1.7, 1.7),
			Color = accent,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CFrame = cf * CFrame.Angles(0, 0, math.rad(90)) * CFrame.new(0, 0.85, side * 3.6),
			Parent = model,
		})
	end
	model.PrimaryPart = top
	model.Parent = parent
	return model
end

-- =========================== Buildings ===========================

-- Pitched roof from two slanted slabs meeting at a ridge (runs along Z).
-- The ridge is UP: both slabs rise toward the center line.
local function pitchedRoof(parent: Instance, cf: CFrame, width: number, depth: number, wallHeight: number, roofColor: Color3, riseRatio: number?)
	local rise = width * (riseRatio or 0.32)
	local slabLen = math.sqrt((width / 2) ^ 2 + rise ^ 2) + 0.8
	local angle = math.atan(rise / (width / 2))
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "Roof",
			Size = Vector3.new(slabLen, 0.5, depth + 1.6),
			Color = roofColor,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CFrame = cf * CFrame.new(side * width / 4, wallHeight + rise / 2, 0)
				* CFrame.Angles(0, 0, -side * angle),
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
			base = Color3.fromRGB(30, 32, 44),
			accent = Color3.fromRGB(90, 170, 220),
			pitched = false,
			hMin = 60, hMax = 140,
		}
	elseif style == "oldtown" then
		palette = {
			walls = { Color3.fromRGB(160, 95, 70), Color3.fromRGB(175, 120, 85), Color3.fromRGB(150, 90, 60), Color3.fromRGB(185, 140, 100) },
			roof = Color3.fromRGB(150, 70, 50),
			window = Color3.fromRGB(255, 220, 140),
			base = Color3.fromRGB(130, 80, 60),
			accent = Color3.fromRGB(235, 130, 70),
			pitched = true,
			hMin = 20, hMax = 32,
		}
	elseif style == "suburbs" then
		palette = {
			walls = { Color3.fromRGB(225, 215, 190), Color3.fromRGB(200, 220, 190), Color3.fromRGB(215, 200, 220), Color3.fromRGB(230, 230, 230) },
			roof = Color3.fromRGB(110, 80, 60),
			window = Color3.fromRGB(190, 230, 255),
			base = Color3.fromRGB(180, 170, 150),
			accent = Color3.fromRGB(120, 160, 200),
			pitched = true,
			hMin = 14, hMax = 20,
		}
	elseif style == "industrial" then
		palette = {
			walls = { Color3.fromRGB(120, 120, 118), Color3.fromRGB(135, 110, 90), Color3.fromRGB(105, 108, 112) },
			roof = Color3.fromRGB(85, 85, 88),
			window = Color3.fromRGB(200, 210, 215),
			base = Color3.fromRGB(90, 90, 88),
			accent = Color3.fromRGB(200, 130, 60),
			pitched = false,
			hMin = 20, hMax = 28,
		}
	else -- waterfront
		palette = {
			walls = { Color3.fromRGB(245, 205, 180), Color3.fromRGB(180, 230, 225), Color3.fromRGB(250, 235, 200), Color3.fromRGB(160, 210, 220) },
			roof = Color3.fromRGB(60, 140, 140),
			window = Color3.fromRGB(255, 245, 210),
			base = Color3.fromRGB(150, 190, 190),
			accent = Color3.fromRGB(90, 200, 190),
			pitched = true,
			hMin = 12, hMax = 18,
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

	local hasStorefront = style == "downtown" or style == "oldtown"
	if hasStorefront then
		-- Ground-floor storefront: slightly protruding base with a glass
		-- band, awning and a door facing the street (+Z).
		ModelFactory.basePart({
			Name = "Storefront",
			Size = Vector3.new(width + 1.4, 9, depth + 1.4),
			Color = palette.base,
			Material = Enum.Material.SmoothPlastic,
			CFrame = cf * CFrame.new(0, 4.5, 0),
			Parent = model,
		})
		ModelFactory.basePart({
			Name = "ShopGlass",
			Size = Vector3.new(width * 0.78, 4.2, 0.3),
			Color = Color3.fromRGB(190, 225, 245),
			Material = Enum.Material.Glass,
			Transparency = 0.35,
			CanCollide = false,
			CFrame = cf * CFrame.new(0, 5.4, depth / 2 + 0.62),
			Parent = model,
		})
		ModelFactory.basePart({
			Name = "ShopDoor",
			Size = Vector3.new(5, 6.4, 0.3),
			Color = Color3.fromRGB(60, 45, 38),
			Material = Enum.Material.Wood,
			CanCollide = false,
			CFrame = cf * CFrame.new(width * 0.28, 4.2, depth / 2 + 0.62),
			Parent = model,
		})
		ModelFactory.basePart({
			Name = "ShopAwning",
			Size = Vector3.new(width + 1, 0.5, 3.6),
			Color = palette.accent,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CFrame = cf * CFrame.new(0, 8.4, depth / 2 + 2.2) * CFrame.Angles(math.rad(-14), 0, 0),
			Parent = model,
		})
	end

	if palette.pitched then
		pitchedRoof(model, cf, width, depth, height, palette.roof, if style == "oldtown" then 0.38 else 0.3)
		if rng:NextNumber() < 0.5 then
			ModelFactory.basePart({
				Name = "Chimney",
				Size = Vector3.new(1.6, 4, 1.6),
				Color = Color3.fromRGB(120, 70, 55),
				CanCollide = false,
				CFrame = cf * CFrame.new(width * 0.25, height + width * 0.36, -depth * 0.2),
				Parent = model,
			})
		end
	else
		ModelFactory.basePart({
			Name = "Roof",
			Size = Vector3.new(width + 1.6, 0.9, depth + 1.6),
			Color = palette.roof,
			CanCollide = false,
			CFrame = cf * CFrame.new(0, height + 0.45, 0),
			Parent = model,
		})
		if style == "downtown" and height > 80 then
			-- Skyscraper setback: a smaller glass crown on top.
			ModelFactory.basePart({
				Name = "Crown",
				Size = Vector3.new(width * 0.55, height * 0.2, depth * 0.55),
				Color = wallColor,
				Material = Enum.Material.Glass,
				CFrame = cf * CFrame.new(0, height + height * 0.1, 0),
				Parent = model,
			})
			ModelFactory.basePart({
				Name = "CrownLight",
				Size = Vector3.new(width * 0.2, 1.4, depth * 0.2),
				Color = Color3.fromRGB(120, 220, 255),
				Material = Enum.Material.Neon,
				CanCollide = false,
				CFrame = cf * CFrame.new(0, height * 1.23, 0),
				Parent = model,
			})
		end
		if style == "industrial" then
			-- Roll-up door + roof vents.
			ModelFactory.basePart({
				Name = "RollDoor",
				Size = Vector3.new(width * 0.4, height * 0.5, 0.3),
				Color = Color3.fromRGB(160, 160, 155),
				Material = Enum.Material.CorrodedMetal,
				CFrame = cf * CFrame.new(0, height * 0.25, depth / 2 + 0.1),
				Parent = model,
			})
			for _, vx in { -width * 0.25, width * 0.25 } do
				ModelFactory.basePart({
					Name = "Vent",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(2, 2.4, 2.4),
					Color = Color3.fromRGB(140, 140, 138),
					CanCollide = false,
					CFrame = cf * CFrame.new(vx, height + 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
					Parent = model,
				})
			end
		end
	end

	-- Windows: loose grid on the front face, starting above the storefront.
	local cols = math.max(1, math.min(if hasStorefront then 4 else 3, math.floor(width / 10)))
	local rows = if palette.pitched
		then math.max(1, math.min(3, math.floor((height - 10) / 8)))
		else math.max(1, math.min(5, math.floor(height / 16)))
	local usable = if hasStorefront then height - 10 else height
	for r = 1, rows do
		for c = 1, cols do
			if rng:NextNumber() < 0.85 then
				local wx = (c - 0.5) * (width / cols) - width / 2
				local wy = (if hasStorefront then 10 else 0) + (r - 0.5) * (usable / rows)
				ModelFactory.basePart({
					Name = "Window",
					Size = Vector3.new(if palette.pitched then 5 else 6.5, if palette.pitched then 4.5 else 7, 0.25),
					Color = palette.window,
					Material = Enum.Material.SmoothPlastic,
					Transparency = 0.35,
					CanCollide = false,
					CFrame = cf * CFrame.new(wx, wy, depth / 2 + 0.15),
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
-- `cf` is the building center at FOUNDATION level: the floor slab top
-- ends up at cf.Y + 0.3 (pass cf.Y = ground - 0.3 to line up with it).
-- Front faces local -Z. Real scale: W64 x D44, 18-stud walls (~3.6 avatars).
function ModelFactory.restaurantBuilding(accent: Color3, baseColor: Color3, shopName: string, parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Restaurant"

	local W, D, H = 64, 44, 18 -- width (x), depth (z), wall height

	local top = cf * CFrame.new(0, 0.3, 0) -- floor surface level

	-- Floor slab.
	ModelFactory.basePart({
		Name = "Floor",
		Size = Vector3.new(W, 0.3, D),
		Color = baseColor,
		Material = Enum.Material.Concrete,
		CFrame = cf * CFrame.new(0, 0.15, 0),
		Parent = model,
	})

	-- Back wall (+Z end).
	ModelFactory.basePart({
		Name = "BackWall",
		Size = Vector3.new(W, H, 1),
		Color = baseColor,
		Material = Enum.Material.SmoothPlastic,
		CFrame = top * CFrame.new(0, H / 2, D / 2 - 0.5),
		Parent = model,
	})
	-- Side walls.
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "SideWall",
			Size = Vector3.new(1, H, D),
			Color = baseColor,
			Material = Enum.Material.SmoothPlastic,
			CFrame = top * CFrame.new(side * (W / 2 - 0.5), H / 2, 0),
			Parent = model,
		})
	end
	-- Front wall (-Z end) with a wide doorway in the middle.
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "FrontWall",
			Size = Vector3.new(W / 2 - 11, H, 1),
			Color = baseColor,
			Material = Enum.Material.SmoothPlastic,
			CFrame = top * CFrame.new(side * (11 + (W / 2 - 11) / 2), H / 2, -D / 2 + 0.5),
			Parent = model,
		})
	end
	ModelFactory.basePart({
		Name = "DoorHeader",
		Size = Vector3.new(22, H - 14, 1),
		Color = baseColor,
		Material = Enum.Material.SmoothPlastic,
		CFrame = top * CFrame.new(0, 14 + (H - 14) / 2, -D / 2 + 0.5),
		Parent = model,
	})
	-- Glass door leaves (walk-through, decoration only).
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "DoorLeaf",
			Size = Vector3.new(10.8, 13.5, 0.25),
			Color = Color3.fromRGB(190, 225, 245),
			Material = Enum.Material.Glass,
			Transparency = 0.5,
			CanCollide = false,
			CFrame = top * CFrame.new(side * 5.5, 7.05, -D / 2 + 0.35),
			Parent = model,
		})
	end

	-- Flat roof + parapet.
	ModelFactory.basePart({
		Name = "Roof",
		Size = Vector3.new(W + 2, 0.6, D + 2),
		Color = Color3.fromRGB(70, 70, 78),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CFrame = top * CFrame.new(0, H + 0.3, 0),
		Parent = model,
	})
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "Parapet",
			Size = Vector3.new(W + 2, 1.4, 0.8),
			Color = baseColor,
			CanCollide = false,
			CFrame = top * CFrame.new(0, H + 1.3, side * (D / 2 + 0.6)),
			Parent = model,
		})
	end

	-- Big rooftop sign: board + shop name + neon pizza medallion.
	local signBoard = ModelFactory.basePart({
		Name = "Sign",
		Size = Vector3.new(34, 8, 1),
		Color = Color3.fromRGB(28, 28, 34),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CFrame = top * CFrame.new(0, H + 6, -D / 2 + 2),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "SignPizza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 5.2, 5.2),
		Color = Color3.fromRGB(240, 190, 90),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CFrame = signBoard.CFrame * CFrame.new(-13.5, 0, 0.5) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = model,
	})
	for _, side in { -1, 1 } do
		ModelFactory.basePart({
			Name = "SignLeg",
			Size = Vector3.new(0.8, 2.4, 0.8),
			Color = Color3.fromRGB(40, 40, 46),
			CanCollide = false,
			CFrame = signBoard.CFrame * CFrame.new(side * 12, -4.8, 0),
			Parent = model,
		})
	end
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
	for i = 0, 7 do
		ModelFactory.basePart({
			Name = "Awning",
			Size = Vector3.new(W / 8 - 0.2, 0.35, 8),
			Color = if i % 2 == 0 then accent else Color3.fromRGB(240, 240, 240),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CFrame = top * CFrame.new(-W / 2 + W / 16 + i * (W / 8), 14.4, -D / 2 - 3.9)
				* CFrame.Angles(math.rad(18), 0, 0),
			Parent = model,
		})
	end

	-- Windows on both side walls.
	for _, side in { -1, 1 } do
		for _, wz in { -12, 4 } do
			ModelFactory.basePart({
				Name = "Window",
				Size = Vector3.new(0.25, 8, 12),
				Color = Color3.fromRGB(190, 230, 255),
				Material = Enum.Material.SmoothPlastic,
				Transparency = 0.35,
				CanCollide = false,
				CFrame = top * CFrame.new(side * (W / 2 + 0.05), 9, wz),
				Parent = model,
			})
		end
	end

	-- Interior ceiling light strips.
	for _, wz in { -14, 6 } do
		ModelFactory.basePart({
			Name = "CeilingLight",
			Size = Vector3.new(W - 10, 0.4, 1.8),
			Color = Color3.fromRGB(255, 235, 190),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CFrame = top * CFrame.new(0, H - 1, wz),
			Parent = model,
		})
	end

	-- Chimney above the oven corner (-X side).
	ModelFactory.basePart({
		Name = "Chimney",
		Size = Vector3.new(3, 5, 3),
		Color = Color3.fromRGB(110, 75, 60),
		CanCollide = false,
		CFrame = top * CFrame.new(-20, H + 2.8, 8),
		Parent = model,
	})

	-- Rooftop AC unit (+X side).
	ModelFactory.basePart({
		Name = "ACUnit",
		Size = Vector3.new(6, 2, 4),
		Color = Color3.fromRGB(130, 130, 135),
		Material = Enum.Material.Metal,
		CanCollide = false,
		CFrame = top * CFrame.new(20, H + 1.3, 8),
		Parent = model,
	})
	ModelFactory.basePart({
		Name = "ACFan",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 3, 3),
		Color = Color3.fromRGB(90, 90, 95),
		Material = Enum.Material.Metal,
		CanCollide = false,
		CFrame = top * CFrame.new(20, H + 2.7, 8) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = model,
	})

	model.PrimaryPart = model.Floor :: BasePart
	model.Parent = parent
	return model
end

return ModelFactory
