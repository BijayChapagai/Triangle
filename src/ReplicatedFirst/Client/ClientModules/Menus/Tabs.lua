-- Tab launchers. The HUD bar carries three tabs - Grow, World, Store - and each
-- opens a small panel of rows; every row opens one of the real menus. That keeps
-- the original two-column HUD shape (the tabs sit where Invite / Music /
-- Favorite used to) instead of adding a row of seven buttons on top of it, and
-- every menu is still two taps away.
--
-- Which row opens what is content, not code: GameData/Tabs/<Tab>/<Label> carries
-- Target / Sub / Order / Color, so moving an entry to another tab, renaming it or
-- recolouring it is a Studio edit. A Target starting with "@" is an action
-- rather than a frame name; the actions live below.
local Tabs = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarEditorService = game:GetService("AvatarEditorService")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local MenuUi = require(script.Parent:WaitForChild("MenuUi"))

local client

--// ------------------------------------------------------------------- actions
-- The shipped Favorite button did this; the button is a tab row now, so the
-- prompt lives here. It only works from a published place, hence the pcall.
local ACTIONS = {
	Favorite = function()
		local ok, err = pcall(function()
			AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
		end)
		if not ok then
			warn("[Tabs] favourite prompt unavailable: " .. tostring(err))
			client.Notify("Favouriting is not available right now.", "bad")
		end
	end,
}

local function openTarget(target)
	if target:sub(1, 1) == "@" then
		local action = ACTIONS[target:sub(2)]
		if not action then
			warn(("[Tabs] GameData/Tabs points at an unknown action: %s"):format(target))
			return
		end
		local ok, err = pcall(action)
		if not ok then
			warn(("[Tabs] action %s failed: %s"):format(target, tostring(err)))
		end
		return
	end

	-- Opening a menu closes the launcher: UiModule.ToggleFrame hides the sibling
	-- panels, so two popups never stack on top of each other.
	if not MenuUi.Toggle(target) then
		client.Notify(("There is no %s menu in this place."):format(target), "bad")
	end
end
Tabs.openTarget = openTarget

local function refresh(frame, tab)
	MenuUi.clearList(frame)
	for _, entry in ipairs(tab.entries) do
		MenuUi.addRow(frame, {
			info = entry.label,
			sub = entry.sub,
			accent = entry.color,
			order = entry.order * 10,
			onClick = function()
				openTarget(entry.target)
			end,
		})
	end
end

function Tabs.Init(c)
	client = c

	local wired = 0
	for _, tab in ipairs(GameConfig.TABS) do
		local frame = MenuUi.frame(tab.name)
		if frame then
			MenuUi.Register(tab.name, {
				onOpen = function()
					refresh(frame, tab)
				end,
			})
			wired += 1
		else
			warn(("[Tabs] Frames.%s is missing from the place"):format(tab.name))
		end
	end

	if wired == 0 then
		warn("[Tabs] GameData/Tabs is empty - the HUD tabs would open nothing")
	end
	return wired > 0
end

return Tabs
