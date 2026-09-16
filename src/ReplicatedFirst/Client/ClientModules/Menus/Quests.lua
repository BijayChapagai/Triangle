-- Daily quests. The list is GameData/Quests (Type, Goal, RewardCash,
-- RewardSkin, Text, Order); progress and claims come from the server through
-- Events.QuestUpdate, which sends either the whole list or a single update.
local Quests = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local UiModule = require(ReplicatedStorage:WaitForChild("UiModule"))
local MenuUi = require(script.Parent:WaitForChild("MenuUi"))

local FRAME_NAME = "Quests"
local READY = Color3.fromRGB(110, 220, 140)
local CLAIMED = Color3.fromRGB(150, 160, 185)
local BAR_WIDTH = 12

local client, frame
local progress = {}   -- quest id -> { progress, claimed }

local function bar(current, goal)
	if goal <= 0 then return "" end
	local filled = math.clamp(math.floor((current / goal) * BAR_WIDTH + 0.5), 0, BAR_WIDTH)
	return string.rep("|", filled) .. string.rep(".", BAR_WIDTH - filled)
end

local function refresh()
	if not frame or not frame.Visible then return end

	MenuUi.clearList(frame)

	local done, total = 0, 0
	for _, quest in ipairs(GameConfig.QUESTS) do
		total += 1
		local entry = progress[quest.id] or { progress = 0, claimed = false }
		local current = math.min(entry.progress, quest.goal)
		local ready = current >= quest.goal and not entry.claimed
		if entry.claimed then done += 1 end

		local rewards = {}
		if (quest.rewardCash or 0) > 0 then
			table.insert(rewards, ("+%s Cash"):format(UiModule.Format(quest.rewardCash)))
		end
		if quest.rewardSkin and quest.rewardSkin ~= "" then
			table.insert(rewards, quest.rewardSkin .. " skin")
		end

		MenuUi.addRow(frame, {
			info = entry.claimed and ('<font color="rgb(150,160,185)">%s</font>'):format(quest.text) or quest.text,
			sub = ("%s %d/%d   |   %s   |   %s"):format(
				bar(current, quest.goal), current, quest.goal,
				entry.claimed and "CLAIMED" or (ready and "TAP TO CLAIM" or "In progress"),
				table.concat(rewards, ", ")),
			accent = entry.claimed and CLAIMED or (ready and READY or nil),
			onClick = ready and function()
				client.fire("QuestClaim", quest.id)
			end or nil,
		})
	end

	MenuUi.addSection(frame, ("Daily quests   |   %d of %d claimed"):format(done, total), 0)
end
Quests.refresh = refresh

function Quests.Init(c)
	client = c
	frame = MenuUi.frame(FRAME_NAME)
	if not frame then return false end

	MenuUi.Register(FRAME_NAME, {
		onOpen = function()
			-- Ask for the authoritative list; the cached one may predate a claim
			-- made from chat or another client.
			client.fire("QuestFetch")
			refresh()
		end,
	})

	client.on("QuestUpdate", function(first, second, third, fourth)
		if typeof(first) == "table" then
			progress = {}
			for _, entry in ipairs(first) do
				progress[tostring(entry.id)] = {
					progress = tonumber(entry.progress) or 0,
					claimed = entry.claimed == true,
				}
			end
		elseif typeof(first) == "string" then
			local entry = progress[first] or { progress = 0, claimed = false }
			entry.progress = tonumber(second) or entry.progress
			entry.claimed = fourth == true
			progress[first] = entry
		end
		refresh()
	end)

	return true
end

return Quests
