-- Rebirth menu. Numbers come from GameData/Settings (RebirthBase, RebirthExponent,
-- RebirthAdd, RebirthMultStep, RebirthCashPerLevel) so tuning is a Studio edit.
local Rebirth = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local UiModule = require(ReplicatedStorage:WaitForChild("UiModule"))
local MenuUi = require(script.Parent:WaitForChild("MenuUi"))

local FRAME_NAME = "Rebirth"
local READY = Color3.fromRGB(110, 220, 140)
local LOCKED = Color3.fromRGB(235, 90, 90)

local client, player, frame
local state = { rebirths = 0, mult = 1, required = 0 }

local function sizeValue()
	local stats = player:FindFirstChild("leaderstats")
	local size = stats and stats:FindFirstChild("Size")
	return size and size.Value or 0
end

local function refresh()
	if not frame or not frame.Visible then return end

	local size = sizeValue()
	local rebirths = state.rebirths
	local required = state.required
	if required <= 0 then required = GameConfig.rebirthRequirement(rebirths) end
	local ready = size >= required
	local _, rankName = GameConfig.getRank(size, rebirths)
	local step = tonumber(GameConfig.get("RebirthMultStep", 0.12)) or 0.12

	MenuUi.clearList(frame)

	MenuUi.addSection(frame, ("Rebirth %d   |   %s"):format(rebirths, rankName))

	MenuUi.addRow(frame, {
		info = "Size multiplier",
		sub = ("x%.2f now, +%.2f per rebirth"):format(state.mult, step),
	})

	MenuUi.addRow(frame, {
		info = "Cash per cube",
		sub = ("%d%s per cube eaten"):format(
			GameConfig.cashPerCube(rebirths, false),
			player:GetAttribute("2xMoney") and " (x2 pass active)" or ""),
	})

	MenuUi.addRow(frame, {
		info = "Requirement",
		sub = ready and "Reached!" or ("Size %s / %s"):format(UiModule.Format(size), UiModule.Format(required)),
		accent = ready and READY or nil,
	})

	MenuUi.addRow(frame, {
		info = "Next reward",
		sub = ("+%s Cash and the next rebirth skin")
			:format(UiModule.Format(GameConfig.rebirthCashReward(rebirths + 1))),
	})

	MenuUi.addRow(frame, {
		info = ready and "REBIRTH NOW" or "NOT READY YET",
		sub = ready and "Resets your size; keeps skins, cash and quests"
			or ("Grow %s more size"):format(UiModule.Format(required - size)),
		accent = ready and READY or LOCKED,
		onClick = function()
			client.fire("Rebirth")
		end,
	})
end
Rebirth.refresh = refresh

function Rebirth.Init(c)
	client = c
	player = c.Player
	frame = MenuUi.frame(FRAME_NAME)
	if not frame then return false end

	MenuUi.Register(FRAME_NAME, { onOpen = refresh })

	client.on("Rebirth", function(rebirths, mult, success, nextRequired)
		state.rebirths = tonumber(rebirths) or state.rebirths
		state.mult = tonumber(mult) or state.mult
		state.required = tonumber(nextRequired) or 0
		refresh()
	end)

	-- Keep the requirement row honest while the menu is open.
	local function hookSize(size)
		size.Changed:Connect(function()
			if frame.Visible then refresh() end
		end)
	end

	local stats = player:FindFirstChild("leaderstats")
	local size = stats and stats:FindFirstChild("Size")
	if size then
		hookSize(size)
	else
		task.spawn(function()
			local s = player:WaitForChild("leaderstats", 60)
			local v = s and s:WaitForChild("Size", 10)
			if v then hookSize(v) end
		end)
	end

	player:GetAttributeChangedSignal("2xMoney"):Connect(function()
		if frame.Visible then refresh() end
	end)

	return true
end

return Rebirth
