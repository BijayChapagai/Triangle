-- Playtime rewards menu: Frames/Rewards > Rewards > Reward1..RewardN, each an
-- ImageButton with Time and Amount labels.
--
-- The ladder itself is GameData/Gifts (RequiredTime, Reward, Type), so the asset
-- decides how many buttons are meaningful: extra buttons with no matching gift
-- are hidden, and gifts with no button are simply not shown.
local Rewards = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local UiModule = require(ReplicatedStorage:WaitForChild("UiModule"))
local MenuUi = require(script.Parent:WaitForChild("MenuUi"))

local FRAME_NAME = "Rewards"
local READY = Color3.fromRGB(35, 255, 70)     -- the shipped BUY green
local CLAIMED = Color3.fromRGB(40, 60, 90)

local client, player, frame, holder
local entries = {}     -- gift id -> { button, time, amount }
local ticking = false

local function giftIdOf(button)
	return tonumber(button.Name:match("%d+"))
end

local function claimState(id)
	local gift = GameConfig.GIFTS[id]
	if not gift then return "missing" end
	-- CurrentGift mirrors the highest claimed id (the server keeps the exact
	-- per-gift record, so a claim out of order still pays out).
	if id <= (player:GetAttribute("CurrentGift") or 0) then return "claimed" end
	if (player:GetAttribute("PlayerTime") or 0) >= (gift.RequiredTime or 0) then return "ready" end
	return "locked"
end

local function paint(id)
	local entry = entries[id]
	local gift = GameConfig.GIFTS[id]
	if not entry or not gift then return end

	local state = claimState(id)
	local remaining = math.max(0, (gift.RequiredTime or 0) - (player:GetAttribute("PlayerTime") or 0))

	if entry.amount then
		entry.amount.Text = ("+%s %s"):format(UiModule.Format(gift.Reward or 0), gift.Type or "Size")
	end
	if entry.time then
		if state == "claimed" then
			entry.time.Text = "CLAIMED"
		elseif state == "ready" then
			entry.time.Text = "TAP TO CLAIM"
		else
			entry.time.Text = UiModule.FormatTime(remaining)
		end
	end

	local stroke = entry.button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = (state == "ready") and READY or (state == "claimed") and CLAIMED or stroke.Color
	end
	entry.button.AutoButtonColor = state == "ready"
end

local function paintAll()
	for id in pairs(entries) do
		paint(id)
	end
end

local function tick()
	if ticking then return end
	ticking = true
	task.spawn(function()
		while frame and frame.Parent do
			task.wait(1)
			if not frame.Visible then continue end
			paintAll()
		end
		ticking = false
	end)
end

function Rewards.Init(c)
	client = c
	player = c.Player
	frame = MenuUi.frame(FRAME_NAME)
	if not frame then return false end

	holder = frame:FindFirstChild("Rewards")
	if not holder then
		warn("[Rewards] Frames/Rewards/Rewards is missing")
		return false
	end

	-- One connection per button, made once. The old script reconnected
	-- Activated every second from inside its update loop.
	for _, button in ipairs(holder:GetChildren()) do
		local id = button:IsA("GuiButton") and giftIdOf(button) or nil
		if not id or not GameConfig.GIFTS[id] then
			-- A button with no gift behind it is stale content: hide it rather than
			-- showing a reward that can never be claimed.
			if button:IsA("GuiObject") then button.Visible = false end
			continue
		end

		button.Visible = true
		entries[id] = {
			button = button,
			time = button:FindFirstChild("Time"),
			amount = button:FindFirstChild("Amount"),
		}
		UiModule.Animate(button)

		button.Activated:Connect(function()
			if claimState(id) ~= "ready" then
				if claimState(id) == "locked" then
					client.Notify("Keep playing to unlock that reward.", "info")
				end
				return
			end
			client.fire("PlayTimeReward", id)
			-- Optimistic paint; the server's attribute change confirms it.
			player:SetAttribute("CurrentGift", math.max(player:GetAttribute("CurrentGift") or 0, id))
		end)
	end

	MenuUi.Register(FRAME_NAME, {
		onOpen = function()
			paintAll()
			tick()
		end,
	})

	for _, signal in ipairs({ "PlayerTime", "CurrentGift" }) do
		player:GetAttributeChangedSignal(signal):Connect(function()
			if frame.Visible then paintAll() end
		end)
	end

	return true
end

return Rewards
