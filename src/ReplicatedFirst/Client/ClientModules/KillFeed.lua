-- Kill feed: who ate whom, top centre of the screen.
--
-- Presentation only. The server reports the fact through Events.KillFeed with the
-- two names and the size the killer absorbed; whether it is shown at all is a
-- player preference (GameData/Prefs/KillFeed), and the strip itself is an asset
-- (StarterGui/KillFeed) so its position, colours and row height are Studio edits.
local KillFeed = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local UiModule = require(ReplicatedStorage:WaitForChild("UiModule"))

local MAX = tonumber(GameConfig.get("KillFeedMax", 5)) or 5
local LIFETIME = tonumber(GameConfig.get("KillFeedLifetime", 6)) or 6
local FADE = 0.4

local client, entries, template
local enabled = true
local order = 0

local function liveRows()
	local rows = {}
	for _, child in ipairs(entries:GetChildren()) do
		if child.Name == "Kill" then
			table.insert(rows, child)
		end
	end
	table.sort(rows, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	return rows
end

-- Oldest first: the strip has a fixed height and a busy server would otherwise
-- push rows off the bottom of it.
local function trim()
	local rows = liveRows()
	while #rows > MAX do
		local oldest = table.remove(rows, 1)
		oldest:Destroy()
	end
end

local function push(text)
	if not enabled or not entries or not template then return end

	order += 1
	local row = template:Clone()
	row.Name = "Kill"
	row.Text = text
	row.LayoutOrder = order
	row.BackgroundTransparency = 0.2
	row.TextTransparency = 0
	row.Visible = true
	row.Parent = entries
	trim()

	task.delay(LIFETIME, function()
		if not row.Parent then return end
		local fade = TweenService:Create(row, TweenInfo.new(FADE, Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out), { BackgroundTransparency = 1, TextTransparency = 1 })
		fade:Play()
		fade.Completed:Connect(function()
			if row.Parent then row:Destroy() end
		end)
	end)
end

function KillFeed.SetEnabled(on)
	enabled = on ~= false
	if not enabled and entries then
		for _, row in ipairs(liveRows()) do
			row:Destroy()
		end
	end
end

function KillFeed.Init(c)
	client = c

	local gui = client.gui("KillFeed")
	entries = gui and gui:FindFirstChild("Entries")
	template = entries and entries:FindFirstChild("Entry")
	if not entries or not template then
		warn("[KillFeed] StarterGui/KillFeed is missing from the place - kill feed disabled")
		return false
	end
	template.Visible = false

	-- Honour the preference immediately (defaults are applied before any module
	-- starts) and whenever it changes.
	KillFeed.SetEnabled(client.Prefs and client.Prefs.KillFeed)
	client.onPref("KillFeed", function(value)
		KillFeed.SetEnabled(value)
	end)

	client.on("KillFeed", function(killer, victim, absorbed)
		if typeof(killer) ~= "string" or typeof(victim) ~= "string" then return end
		absorbed = tonumber(absorbed) or 0

		local text = ('<b>%s</b> ate <b>%s</b>'):format(killer, victim)
		if absorbed > 0 then
			text = text .. ('   <font color="rgb(140,235,160)">+%s</font>'):format(UiModule.Format(absorbed))
		end
		push(text)
	end)

	return true
end

return KillFeed
