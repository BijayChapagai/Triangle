-- Shared UI helpers: button animation, menu frame toggling and number
-- formatting. This is the only UI code both the menus and the HUD use, and it
-- lives in ReplicatedStorage so the loading screen can reach it too.
--
-- The hover/click sounds are Sound instances that ship as children of this
-- module, so they can be swapped in Studio without touching code.
local TweenService = game:GetService("TweenService")

local UiModule = {}

local ENTER = 1.1
local ENTER_BIG = 1.03
local DOWN = 0.8

local hoverSound = script:FindFirstChild("hoverSound")
local clickSound = script:FindFirstChild("clickSound")

local animated = {}

local function play(sound)
	if sound then
		-- Overlapping tweens of the same Sound cut each other off; TimePosition
		-- rewinds so rapid hovering still clicks.
		sound.TimePosition = 0
		sound:Play()
	end
end

local function grow(button, size, mult, time)
	local tween = TweenService:Create(button, TweenInfo.new(time or 0.1), {
		Size = UDim2.new(size.X.Scale * mult, size.X.Offset, size.Y.Scale * mult, size.Y.Offset),
	})
	tween:Play()
	return tween
end

-- Hover/press animation. Idempotent: wiring the same button twice no longer
-- stacks tweens (the old version re-read Button.Size while a tween was running,
-- which froze buttons at their hovered size).
function UiModule.Animate(button)
	if not button or animated[button] then return end
	if not (button:IsA("GuiButton") or button:IsA("Frame")) then return end
	animated[button] = true

	local base = button.Size
	local mult = (button.Name == "Big") and ENTER_BIG or ENTER
	local label = button:FindFirstChild("ImageLabel")

	button.MouseEnter:Connect(function()
		grow(button, base, mult)
		play(hoverSound)
		if label then
			TweenService:Create(label, TweenInfo.new(0.1), { Rotation = math.random(10, 25) }):Play()
		end
	end)

	button.MouseLeave:Connect(function()
		grow(button, base, 1)
		if label then
			TweenService:Create(label, TweenInfo.new(0.1), { Rotation = 0 }):Play()
		end
	end)

	if button:IsA("GuiButton") then
		button.MouseButton1Down:Connect(function()
			grow(button, base, DOWN)
		end)
		button.MouseButton1Up:Connect(function()
			grow(button, base, mult)
			play(clickSound)
		end)
	end
end

local function framesOf(player)
	local gui = player and player:FindFirstChildOfClass("PlayerGui")
	return gui and gui:FindFirstChild("Frames")
end

function UiModule.CloseAll(player)
	local frames = framesOf(player)
	if not frames then return end
	for _, frame in ipairs(frames:GetChildren()) do
		if frame:IsA("GuiObject") then
			frame.Visible = false
		end
	end
end

-- Toggle one menu frame, closing its siblings. `onOpen(frame)` runs after the
-- frame becomes visible so each menu can refresh its contents on demand instead
-- of polling every second forever.
function UiModule.ToggleFrame(player, frame, onOpen)
	if not frame or not frame:IsA("GuiObject") then return false end
	local frames = framesOf(player)
	local camera = workspace.CurrentCamera

	if frame.Visible then
		frame.Visible = false
		if camera then
			TweenService:Create(camera, TweenInfo.new(0.25, Enum.EasingStyle.Linear), { FieldOfView = 70 }):Play()
		end
		return false
	end

	if frames then
		for _, other in ipairs(frames:GetChildren()) do
			if other ~= frame and other:IsA("GuiObject") then
				other.Visible = false
			end
		end
	end

	local target = frame.Position
	frame.Position = UDim2.new(target.X.Scale, target.X.Offset, target.Y.Scale + 0.1, target.Y.Offset)
	frame.Visible = true

	local tween = TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = target,
	})
	tween:Play()
	if camera then
		TweenService:Create(camera, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = 80 }):Play()
	end

	if typeof(onOpen) == "function" then
		local ok, err = pcall(onOpen, frame)
		if not ok then warn("[UiModule] onOpen failed for " .. frame.Name .. ": " .. tostring(err)) end
	end
	return true
end

-- Compact number formatting (1.5K / 2.3M). FormatNumberAlt ships in the place;
-- if it is ever removed the HUD must still show something sensible.
local formatter
local formatterTried = false
local function compact(value)
	if not formatterTried then
		formatterTried = true
		local ok, mod = pcall(function()
			return require(game:GetService("ReplicatedStorage").Modules:WaitForChild("FormatNumberAlt", 5))
		end)
		if ok and type(mod) == "table" and type(mod.FormatCompact) == "function" then
			formatter = mod
		end
	end
	if formatter then
		local ok, out = pcall(formatter.FormatCompact, value)
		if ok then return tostring(out) end
	end
	-- Fallback: 1 decimal place with K/M/B/T suffixes.
	value = tonumber(value) or 0
	if math.abs(value) < 1000 then return tostring(math.floor(value + 0.5)) end
	local units = { "", "K", "M", "B", "T", "Qa" }
	local exp = math.floor(math.log(math.abs(value), 1000))
	local unit = units[exp + 1] or ("e+" .. exp)
	return ("%.1f%s"):format(value / (1000 ^ exp), unit)
end
UiModule.Format = compact
UiModule.FormatCompact = compact

-- HH:MM:SS / MM:SS for the playtime rewards menu.
function UiModule.FormatTime(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60
	if hours > 0 then
		return ("%d:%02d:%02d"):format(hours, minutes, secs)
	end
	return ("%02d:%02d"):format(minutes, secs)
end

function UiModule.Tween(instance, time, props, style, direction)
	local info = TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

return UiModule
