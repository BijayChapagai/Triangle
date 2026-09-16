-- Global leaderboards. The boards are ordered data stores read on the server and
-- pushed through Events.Leaderboard; this menu only renders the cache and asks
-- for a refresh when it opens (the server throttles requests).
local Leaderboard = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiModule = require(ReplicatedStorage:WaitForChild("UiModule"))
local MenuUi = require(script.Parent:WaitForChild("MenuUi"))

local FRAME_NAME = "Leaderboard"
local ME = Color3.fromRGB(249, 173, 0)      -- the gold the shipped UI uses for timers

local client, player, frame
local cache = { Size = {}, Cash = {} }

local function addBoard(title, entries, suffix)
	MenuUi.addSection(frame, title)

	if #entries == 0 then
		MenuUi.addRow(frame, {
			info = "No entries yet",
			sub = "Boards refresh every few seconds",
		})
		return
	end

	for index, entry in ipairs(entries) do
		local mine = entry.name == player.Name
		MenuUi.addRow(frame, {
			info = ("#%d  %s"):format(index, entry.name),
			sub = ("%s %s"):format(UiModule.Format(entry.value), suffix),
			accent = mine and ME or nil,
		})
	end
end

local function refresh()
	if not frame or not frame.Visible then return end
	MenuUi.clearList(frame)
	addBoard("Biggest cubes", cache.Size or {}, "size")
	addBoard("Richest", cache.Cash or {}, "cash")
end
Leaderboard.refresh = refresh

function Leaderboard.Init(c)
	client = c
	player = c.Player
	frame = MenuUi.frame(FRAME_NAME)
	if not frame then return false end

	MenuUi.Register(FRAME_NAME, {
		onOpen = function()
			refresh()          -- show the cache immediately
			client.fire("Leaderboard")  -- then ask for fresh data
		end,
	})

	client.on("Leaderboard", function(lists)
		if typeof(lists) == "table" then
			cache.Size = typeof(lists.Size) == "table" and lists.Size or {}
			cache.Cash = typeof(lists.Cash) == "table" and lists.Cash or {}
		end
		refresh()
	end)

	-- While the board is open, ask again every 10 seconds. The server throttles
	-- requests per player, so a client cannot spam the data store through this.
	task.spawn(function()
		while frame and frame.Parent do
			task.wait(10)
			if frame.Visible then
				client.fire("Leaderboard")
			end
		end
	end)

	return true
end

return Leaderboard
