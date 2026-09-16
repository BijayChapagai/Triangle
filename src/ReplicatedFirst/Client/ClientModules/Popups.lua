-- "+1.2K" popups when Cash or Size goes up.
--
-- Asset driven: the templates are ImageLabel children of this module (Cash, Size
-- - add another one named after any leaderstats value and it works), and they
-- are cloned into the IncrementUI ScreenGui that also ships here. The old
-- version polled Player:GetDescendants() every second, used spawn/delay/wait,
-- and leaked a connection per character.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiModule = require(ReplicatedStorage:WaitForChild("UiModule"))

local Popups = {}

local MAX_LIVE = 12
local live = 0

local ui
local templates = {}

local function show(template, amount)
	if not ui or not template then return end
	if live >= MAX_LIVE then return end

	live += 1
	local icon = template:Clone()
	local label = icon:FindFirstChild("Amount")
	if label then label.Text = "+" .. UiModule.Format(amount) end

	local originalSize = icon.Size
	if label then
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1
	end
	icon.ImageTransparency = 1
	icon.Position = UDim2.new(math.random(10, 70) / 100, 0, math.random(10, 60) / 100, 0)
	icon.Size = originalSize + UDim2.new(0.25, 0, 0.25, 0)
	icon.Parent = ui

	local popIn = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	TweenService:Create(icon, popIn, { Size = originalSize, ImageTransparency = 0 }):Play()
	if label then
		TweenService:Create(label, popIn, { TextTransparency = 0, TextStrokeTransparency = 0 }):Play()
	end

	task.delay(0.75, function()
		-- Freeze the absolute position first so the float-away tween is not
		-- fighting the scale-relative layout it was born in.
		local position = icon.AbsolutePosition
		local size = icon.AbsoluteSize
		local drift = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

		TweenService:Create(icon, drift, {
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.new(0, size.X, 0, size.Y),
			Position = UDim2.new(0, position.X, 0, position.Y - 40),
			ImageTransparency = 1,
		}):Play()
		if label then
			TweenService:Create(label, drift, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end

		task.delay(1.05, function()
			live = math.max(0, live - 1)
			if icon then icon:Destroy() end
		end)
	end)
end

local function watch(value, template)
	local last = value.Value or 0
	value.Changed:Connect(function()
		local current = value.Value or 0
		local delta = current - last
		last = current
		-- Only gains pop: showing "-5000" on every purchase would be noise.
		if delta > 0 then
			show(template, delta)
		end
	end)
end

local function hookLeaderstats(player)
	local stats = player:WaitForChild("leaderstats", 60)
	if not stats then return end

	local function attach(value)
		local template = templates[value.Name]
		if template then watch(value, template) end
	end

	for _, value in ipairs(stats:GetChildren()) do
		if value:IsA("NumberValue") or value:IsA("IntValue") then
			attach(value)
		end
	end
	stats.ChildAdded:Connect(function(value)
		if value:IsA("NumberValue") or value:IsA("IntValue") then
			attach(value)
		end
	end)
end

function Popups.Init(client)
	local player = client and client.Player
	local playerGui = client and client.playerGui and client.playerGui()
	if not player or not playerGui then return false end

	ui = script:FindFirstChild("IncrementUI")
	if not ui then
		warn("[Popups] IncrementUI ScreenGui is missing from this module")
		return false
	end
	ui.Parent = playerGui

	for _, child in ipairs(script:GetChildren()) do
		if child:IsA("ImageLabel") then
			templates[child.Name] = child
		end
	end

	if next(templates) == nil then
		warn("[Popups] no ImageLabel templates - nothing will pop")
	end

	task.spawn(hookLeaderstats, player)
	return true
end

return Popups
