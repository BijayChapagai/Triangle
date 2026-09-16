-- Toast notifications. The UI is an asset: the `Notifier` ScreenGui that ships
-- as a child of the Client LocalScript (Toasts > Toast, with UIListLayout).
-- The server pushes toasts through Events.Notify; anything on the client can
-- call client.Notify(text, kind).
local Notifier = {}

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))

local LIFETIME = tonumber(GameConfig.get("NotifyLifetime", 3.5)) or 3.5
local MAX = math.max(1, tonumber(GameConfig.get("NotifyMax", 5)) or 5)

-- Accent colours come from the asset (InfoColor/GoodColor/BadColor Color3Values
-- next to the Toast template); these are only fallbacks if they are deleted.
local KIND_COLORS = {
	good = Color3.fromRGB(110, 220, 140),
	bad = Color3.fromRGB(235, 90, 90),
}

local template                       -- the Notifier ScreenGui, found in Init

local gui, toasts, toastTemplate
local active = {}
local baseStrokeColor

function Notifier.Init(client)
	-- Ships as a child of the Client LocalScript (see LoadingScreen for why the
	-- walk up instead of script.Parent).
	local holder = client and client.Bootstrap
	if not holder then
		holder = script.Parent
		while holder and not holder:IsA("LocalScript") do
			holder = holder.Parent
		end
	end
	template = holder and holder:FindFirstChild("Notifier")

	if not template then
		warn("[Notifier] no Notifier ScreenGui under the Client LocalScript")
		return false
	end

	local playerGui = client and client.playerGui and client.playerGui()
	if not playerGui then return false end

	gui = template:Clone()
	gui.Name = "Notifier"
	gui.Parent = playerGui

	toasts = gui:FindFirstChild("Toasts")
	toastTemplate = toasts and toasts:FindFirstChild("Toast")
	if not toastTemplate then
		warn("[Notifier] Toasts/Toast is missing from the template")
		return false
	end
	toastTemplate.Visible = false -- it is a template, not a message

	local stroke = toastTemplate:FindFirstChildOfClass("UIStroke")
	if stroke then baseStrokeColor = stroke.Color end

	for _, entry in ipairs({ { "GoodColor", "good" }, { "BadColor", "bad" } }) do
		local value = gui:FindFirstChild(entry[1])
		if value and value:IsA("Color3Value") then
			KIND_COLORS[entry[2]] = value.Value
		end
	end

	-- Replace the buffered stub in the client bootstrap with the real thing.
	client.Notify = Notifier.Notify
	if client.flushNotes then client.flushNotes() end

	client.on("Notify", function(text, kind)
		Notifier.Notify(text, kind)
	end)

	return true
end

local function fadeOut(toast)
	local ok = pcall(function()
		TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1, TextStrokeTransparency = 1,
		}):Play()
		local stroke = toast:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		end
	end)
	task.delay(0.32, function()
		for i, entry in ipairs(active) do
			if entry == toast then table.remove(active, i) break end
		end
		if ok and toast then toast:Destroy() end
	end)
end

function Notifier.Notify(text, kind)
	if not toastTemplate or not toasts then
		-- Before the GUI exists (or if it failed to load) fall back to the console
		-- rather than dropping the message on the floor.
		print("[Notify] " .. tostring(text))
		return
	end
	if text == nil or tostring(text) == "" then return end

	-- Oldest first when the stack is full: a burst of messages must never grow
	-- the list without bound.
	while #active >= MAX do
		local oldest = table.remove(active, 1)
		if oldest and oldest.Parent then oldest:Destroy() end
	end

	local toast = toastTemplate:Clone()
	toast.Text = tostring(text)
	toast.Visible = true
	toast.BackgroundTransparency = toastTemplate.BackgroundTransparency
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = toastTemplate.TextStrokeTransparency

	local color = KIND_COLORS[kind]
	local stroke = toast:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
		stroke.Color = color or baseStrokeColor or stroke.Color
	end

	-- Fade in. The list is driven by a UIListLayout, so Position is not ours to
	-- tween - animating it just fights the layout.
	toast.BackgroundTransparency = 1
	toast.TextTransparency = 1
	toast.TextStrokeTransparency = 1
	toast.Parent = toasts
	table.insert(active, toast)

	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(toast, info, {
		BackgroundTransparency = toastTemplate.BackgroundTransparency,
		TextTransparency = 0,
		TextStrokeTransparency = toastTemplate.TextStrokeTransparency,
	}):Play()

	task.delay(LIFETIME, function()
		fadeOut(toast)
	end)
end

return Notifier
