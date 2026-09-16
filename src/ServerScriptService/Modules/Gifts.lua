-- Playtime gifts. The ladder itself lives in GameData/Gifts, so the times and
-- rewards are editable in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Progression = require(script.Parent:WaitForChild("Progression"))

local Gifts = {}

local function claim(player, giftId)
	giftId = tonumber(giftId)
	local gift = giftId and GameConfig.GIFTS[giftId]
	if not gift then return end

	local playtime = player:GetAttribute("PlayerTime") or 0
	if playtime < (gift.RequiredTime or 0) then return end

	local data = DataManager.Data(player)
	if not data then return end

	-- Persisted per-gift claim record. The old `CurrentGift >= gift` counter both
	-- reset on every rejoin and permanently locked any gift claimed out of order.
	-- Keys are strings: DataStore serialisation turns numeric table keys into
	-- strings, and a numeric key would silently re-open every gift after a reload.
	data.Gifts = data.Gifts or {}
	local key = tostring(giftId)
	if data.Gifts[key] then return end
	data.Gifts[key] = true

	local highest = 0
	for id in pairs(data.Gifts) do
		local n = tonumber(id)
		if n and n > highest then highest = n end
	end
	player:SetAttribute("CurrentGift", highest)

	if gift.Type == "Cash" then
		DataManager.AddCash(player, gift.Reward or 0)
		Progression.notify(player, ("Playtime gift: +%d Cash"):format(gift.Reward or 0), "good")
	else
		local ls = player:FindFirstChild("leaderstats")
		local size = ls and ls:FindFirstChild("Size")
		if size then
			size.Value += (gift.Reward or 0)
			Progression.setCubeSize(player.Character, GameConfig.visualSize(size.Value))
		end
		Progression.notify(player, ("Playtime gift: +%d Size"):format(gift.Reward or 0), "good")
	end
end

function Gifts.Init()
	Remotes.onServer("PlayTimeReward", claim)
end

return Gifts
