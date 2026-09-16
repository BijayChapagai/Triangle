-- Chat: a welcome message and "!" shortcuts.
--
-- The shortcuts matter on console and mobile, where the menus are a few taps
-- away: "!quests" opens the panel directly. An admin can also run server
-- commands from here ("!admin givecash Bob 1000"), and the reply comes back into
-- chat rather than into a panel. Everything is still validated server side.
local Chat = {}

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))

local PREFIX = "!"

local HELP = table.concat({
	PREFIX .. "help - this list",
	PREFIX .. "gifts - open the playtime rewards",
	PREFIX .. "skins - open the skins menu",
	PREFIX .. "ranks - open the leaderboard",
	PREFIX .. "rebirth - rebirth if you qualify",
	PREFIX .. "admin <command> - admin only (type '!admin help')",
}, "\n")

local function systemMessage(text, color)
	-- SetCore fails until the chat window exists, so retry instead of dropping it.
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCore("ChatMakeSystemMessage", {
				Text = text,
				Color = color or Color3.fromRGB(255, 215, 90),
				Font = Enum.Font.GothamBold,
				TextSize = 18,
			})
		end)
		if ok then return true end
		task.wait(1)
	end
	return false
end
Chat.systemMessage = systemMessage

local function handleCommand(client, player, text)
	local body = text:sub(#PREFIX + 1)
	local head, rest = body:match("^(%S+)%s*(.*)$")
	head = head and head:lower() or ""

	if head == "help" or head == "" then
		systemMessage(HELP, Color3.fromRGB(180, 220, 255))
		return true
	end

	if head == "admin" then
		if GameConfig.isAdmin(player.UserId, player) then
			client.fire("Admin", rest)
		else
			systemMessage("You are not an admin.", Color3.fromRGB(255, 120, 110))
		end
		return true
	end

	if head == "rebirth" then
		client.fire("Rebirth")
		return true
	end

	-- Menu shortcuts go through MenuUi so chat and clicks behave identically.
	local menu = ({
		gifts = "Rewards", rewards = "Rewards", skins = "Skins", ranks = "Leaderboard",
		leaderboard = "Leaderboard", quests = "Quests", zones = "Zones", codes = "Codes",
		shop = "Shop", update = "UpdateLog", log = "UpdateLog", settings = "Settings",
		grow = "Grow", world = "World", store = "Store",
	})[head]
	if menu then
		local menus = client.Modules and client.Modules.MenuUi
		if menus and menus.Open then
			menus.Open(menu)
		end
		return true
	end

	systemMessage(("Unknown command '%s'. Type %shelp"):format(head, PREFIX), Color3.fromRGB(255, 120, 110))
	return true
end

function Chat.Init(client)
	local player = client and client.Player or Players.LocalPlayer

	task.spawn(function()
		systemMessage(("Welcome to %s! Eat cubes to grow, eat players to take their size. Type %shelp for shortcuts.")
			:format(GameConfig.GAME_NAME, PREFIX))
	end)

	-- Player.Chatted fires on the client for your own messages too, which is what
	-- makes the shortcuts possible without a server round trip for non-admins.
	-- Admin command output used to land in the console panel; with the panel gone
	-- it lands in chat, which is where the command was typed.
	client.on("Admin", function(text)
		systemMessage(tostring(text), Color3.fromRGB(255, 215, 90))
	end)

	player.Chatted:Connect(function(message)
		if typeof(message) ~= "string" then return end
		if message:sub(1, #PREFIX) ~= PREFIX then return end
		local ok, err = pcall(handleCommand, client, player, message)
		if not ok then warn("[Chat] command failed: " .. tostring(err)) end
	end)

	return true
end

return Chat
