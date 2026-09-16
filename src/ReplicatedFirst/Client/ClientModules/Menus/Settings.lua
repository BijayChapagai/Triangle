-- Settings menu. The list of settings is content (GameData/Prefs), so adding a
-- value there adds a row here with no code. Values are saved to the profile
-- through Events.SavePrefs and applied live through Client.Prefs, which every
-- consumer listens to.
--
-- Numeric settings cycle through fixed steps instead of using a drag slider: a
-- slider needs new asset, and cycling is exact with one tap on a touch screen.
local Settings = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local MenuUi = require(script.Parent:WaitForChild("MenuUi"))

local FRAME_NAME = "Settings"

-- Order and copy. A pref that is not listed still gets a row (labelled with its
-- key), so new content appears instead of silently disappearing.
local ORDER = { "MusicVolume", "UiScale", "KillFeed", "CameraPunch", "ReducedMotion", "AutoFarmFlee" }
local LABELS = {
	MusicVolume = "Music volume",
	UiScale = "Interface scale",
	KillFeed = "Kill feed",
	CameraPunch = "Camera punch",
	ReducedMotion = "Reduced motion",
	AutoFarmFlee = "Auto-farm avoids bigger cubes",
}
local HINTS = {
	MusicVolume = "tap to change",
	UiScale = "tap to change",
	KillFeed = "show who ate whom",
	CameraPunch = "fov kick when you eat a player",
	ReducedMotion = "no fov kick, menus snap instead of sliding",
	AutoFarmFlee = "run from a bigger cube instead of farming beside it",
}
local STEPS = {
	MusicVolume = { 0, 0.2, 0.4, 0.6, 0.8, 1 },
	UiScale = { 0.8, 0.9, 1, 1.1, 1.25, 1.5 },
}

local client, frame

local function percent(value)
	return ("%d%%"):format(math.floor((tonumber(value) or 0) * 100 + 0.5))
end

local function valueText(key, value)
	if typeof(value) == "boolean" then
		return value and "ON" or "OFF"
	end
	if key == "MusicVolume" or key == "UiScale" then
		return percent(value)
	end
	return tostring(value)
end

local function sortedKeys()
	local keys, seen = {}, {}
	for _, key in ipairs(ORDER) do
		if GameConfig.PREFS[key] ~= nil then
			table.insert(keys, key)
			seen[key] = true
		end
	end
	local extras = {}
	for key in pairs(GameConfig.PREFS) do
		if not seen[key] then table.insert(extras, key) end
	end
	table.sort(extras)
	for _, key in ipairs(extras) do
		table.insert(keys, key)
	end
	return keys
end

local function nextStep(key)
	local steps = STEPS[key]
	if not steps then return nil end
	local current = tonumber(client.Prefs[key]) or 0
	local at = #steps
	for index, step in ipairs(steps) do
		if math.abs(step - current) < 0.001 then
			at = index
			break
		end
	end
	return steps[at % #steps + 1]
end

local function refresh()
	if not frame or not frame.Visible then return end

	MenuUi.clearList(frame)
	MenuUi.addSection(frame, "Saved to your profile")

	for index, key in ipairs(sortedKeys()) do
		MenuUi.addRow(frame, {
			info = LABELS[key] or key,
			sub = ("%s   |   %s"):format(valueText(key, client.Prefs[key]), HINTS[key] or "tap to change"),
			order = index * 10,
			onClick = function()
				-- Read the current value at click time: the row outlives the change.
				local value = client.Prefs[key]
				if typeof(value) == "boolean" then
					client.setPref(key, not value)
				else
					local step = nextStep(key)
					if step then client.setPref(key, step) end
				end
			end,
		})
	end

	MenuUi.addRow(frame, {
		info = "Reset to defaults",
		sub = "every setting back to what the place ships with",
		order = 900,
		onClick = function()
			for key, default in pairs(GameConfig.PREFS) do
				client.setPref(key, default)
			end
		end,
	})
end
Settings.refresh = refresh

function Settings.Init(c)
	client = c
	frame = MenuUi.frame(FRAME_NAME)
	if not frame then return false end

	MenuUi.Register(FRAME_NAME, {
		onOpen = refresh,
	})

	-- Values change from this menu and from the server echo; either way the rows
	-- have to show the new value while the menu is open.
	for key in pairs(GameConfig.PREFS) do
		client.onPref(key, function()
			if frame.Visible then refresh() end
		end)
	end

	return true
end

return Settings
