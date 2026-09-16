-- Daily quests. The list is GameData/Quests (Type, Goal, RewardCash,
-- RewardSkin, Text, Order); progress and claims come from the server through
-- Events.QuestUpdate, which sends either the whole list or a single update.
local Quests = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local UiModule = require(ReplicatedStorage:WaitForChild("UiModule"))
local MenuUi = require(script.Parent:WaitForChild("MenuUi"))

local FRAME_NAME = "Quests"
local READY = Color3.fromRGB(35, 255, 70)     -- the shipped BUY green
local CLAIMED = Color3.fromRGB(40, 60, 90)
local client, frame
local progress = {}   -- quest id -> { progress, claimed }
local statusLabel, claimAll

-- The server resets dailies on the UTC day, so the countdown is pure client
-- arithmetic: no remote, and it cannot disagree with the reset.
local function countdownText()
	local left = 86400 - (os.time() % 86400)
	return ("Resets in %dh %02dm"):format(math.floor(left / 3600), math.floor((left % 3600) / 60))
end

local function readyCount()
	local count = 0
	for _, quest in ipairs(GameConfig.QUESTS) do
		local entry = progress[quest.id]
		if entry and not entry.claimed and entry.progress >= quest.goal then count += 1 end
	end
	return count
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
			info = entry.claimed and ('<font color="rgb(30,50,70)">%s</font>'):format(quest.text) or quest.text,
			sub = ("%d/%d   |   %s   |   %s"):format(
				current, quest.goal,
				entry.claimed and "CLAIMED" or (ready and "TAP TO CLAIM" or "In progress"),
				table.concat(rewards, ", ")),
			bar = quest.goal > 0 and (current / quest.goal) or 1,
			barColor = entry.claimed and CLAIMED or READY,
			accent = entry.claimed and CLAIMED or (ready and READY or nil),
			onClick = ready and function()
				client.fire("QuestClaim", quest.id)
			end or nil,
		})
	end

	MenuUi.addSection(frame, ("Daily quests   |   %d of %d claimed"):format(done, total), 0)

	if statusLabel then statusLabel.Text = countdownText() end
	if claimAll then
		local ready = readyCount()
		claimAll.Text = ready > 0 and ("Claim All (%d)"):format(ready) or "Claim All"
		claimAll.AutoButtonColor = ready > 0
	end
end
Quests.refresh = refresh

function Quests.Init(c)
	client = c
	frame = MenuUi.frame(FRAME_NAME)
	if not frame then return false end

	statusLabel = frame:FindFirstChild("Status")
	claimAll = frame:FindFirstChild("ClaimAll")
	if claimAll then
		UiModule.Animate(claimAll)
		claimAll.Activated:Connect(function()
			-- One remote for the lot: the server claims through the same path as a
			-- single claim, so nothing here can double-pay.
			if readyCount() > 0 then client.fire("QuestClaimAll") end
		end)
	end

	MenuUi.Register(FRAME_NAME, {
		onOpen = function()
			-- Ask for the authoritative list; the cached one may predate a claim
			-- made from chat or another client.
			client.fire("QuestFetch")
			refresh()
		end,
	})

	client.on("QuestClaimAll", function(count)
		count = tonumber(count) or 0
		client.Notify(count > 0 and ("Claimed %d quest reward%s.")
			:format(count, count == 1 and "" or "s") or "Nothing ready to claim.",
			count > 0 and "good" or "info")
		refresh()
	end)

	-- Only worth ticking while the menu is actually on screen.
	task.spawn(function()
		while frame and frame.Parent do
			task.wait(20)
			if frame.Visible and statusLabel then statusLabel.Text = countdownText() end
		end
	end)

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
