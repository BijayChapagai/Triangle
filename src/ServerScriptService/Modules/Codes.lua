-- Redeemable codes. The code list lives in GameData/Codes (code -> cash), so a
-- new code is a new NumberValue in Studio, not a code change.
--
-- Codes are one-shot per profile and always answer the player: the original
-- version silently did nothing unless you were in the group, which players read
-- as "codes are broken".
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Progression = require(script.Parent:WaitForChild("Progression"))

local Codes = {}

local function attempt(player, code)
	if typeof(code) ~= "string" then return end

	local data = DataManager.Data(player)
	if not data then
		Progression.notify(player, "Your data is still loading, try again in a second.", "bad")
		return
	end

	-- Normalise: players type "cubes", " CUBES " and "Cubes" and expect all to work.
	local key = code:upper():gsub("^%s+", ""):gsub("%s+$", "")
	local reward = GameConfig.CODES[key]

	data.RedeemedCodes = data.RedeemedCodes or {}

	if not reward then
		Progression.notify(player, ('"%s" is not a valid code.'):format(code), "bad")
		return
	end

	if table.find(data.RedeemedCodes, key) then
		Progression.notify(player, ("You already redeemed %s."):format(key), "bad")
		return
	end

	table.insert(data.RedeemedCodes, key)
	DataManager.AddCash(player, reward)
	Progression.notify(player, ("Code %s redeemed: +%d Cash!"):format(key, reward), "good")
end

function Codes.Init()
	Remotes.onServer("AttemptCode", attempt)
end

return Codes
