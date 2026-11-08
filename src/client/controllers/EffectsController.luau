--!strict
-- EffectsController: floating "+$N" world text when you make a sale.

local Debris = game:GetService("Debris")

local EffectsController = {}

local Net

function EffectsController.Init(ctx)
	Net = ctx.Net
	Net.CashFloat.OnClientEvent:Connect(function(payload)
		local part = Instance.new("Part")
		part.Size = Vector3.new(0.4, 0.4, 0.4)
		part.Transparency = 1
		part.CanCollide = false
		part.Anchored = true
		part.CFrame = CFrame.new(payload.position)
		part.Parent = workspace

		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(140, 44)
		gui.AlwaysOnTop = true
		gui.Parent = part

		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		text.TextScaled = true
		text.Text = "+$" .. tostring(payload.amount)
		text.TextColor3 = Color3.fromRGB(130, 255, 130)
		text.TextStrokeTransparency = 0.3
		text.Parent = gui

		-- Float up and fade.
		local TweenService = game:GetService("TweenService")
		TweenService:Create(
			part,
			TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = part.CFrame + Vector3.new(0, 6, 0) }
		):Play()
		TweenService:Create(
			text,
			TweenInfo.new(1.4),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		):Play()
		Debris:AddItem(part, 1.5)
	end)
end

return EffectsController
