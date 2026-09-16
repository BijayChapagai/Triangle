-- Data layer: one ProfileService profile per player, mirrored into leaderstats.
--
-- Nothing may write to a profile after it is released, so systems that need a
-- last-chance save register a pre-release hook instead of racing
-- Players.PlayerRemoving (connection order between handlers is not defined, and
-- losing that race silently drops quest progress).
local DataManager = {}
DataManager.Profiles = {}

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local ProfileService = require(script.Parent:WaitForChild("ProfileService"))

-- Profile template. Adding a field here is enough: Reconcile() fills it in for
-- existing saves, and Init() re-checks the types for saves written by older
-- versions of the game.
local Template = {
	Cash = 0,
	RedeemedCodes = {},
	Rebirths = 0,
	RebirthMult = 1,
	Skin = "Default",
	OwnedSkins = { "Default" },
	Quests = {},
	ClaimedQuests = {},
	QuestDay = 0,
	Gifts = {},      -- claimed playtime gifts, ["<giftId>"] = true
	Receipts = {},   -- processed MarketplaceService purchase ids (idempotency)
	Stats = { Eaten = 0, Kills = 0, PlayTime = 0 },
}

-- NOTE: renaming this store abandons every existing save.
local ProfileStore = ProfileService.GetProfileStore(GameConfig.DATASTORE_NAME, Template)

local preReleaseHooks = {}

-- Register fn(player); runs while the profile is still writable.
function DataManager.RegisterPreRelease(fn)
	if type(fn) == "function" then
		table.insert(preReleaseHooks, fn)
	end
end

function DataManager.GetProfile(player)
	return DataManager.Profiles[player]
end

function DataManager.HasProfile(player)
	return DataManager.Profiles[player] ~= nil
end

-- Typed accessors so gameplay code never indexes a half-loaded profile.
function DataManager.Data(player)
	local profile = DataManager.Profiles[player]
	return profile and profile.Data
end

function DataManager.Cash(player)
	local data = DataManager.Data(player)
	return data and data.Cash or 0
end

function DataManager.AddCash(player, amount)
	local data = DataManager.Data(player)
	if not data then return 0 end
	data.Cash = math.max(0, (data.Cash or 0) + (amount or 0))
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	if cash then cash.Value = data.Cash end
	return data.Cash
end

function DataManager.Rebirths(player)
	local data = DataManager.Data(player)
	return (data and data.Rebirths) or 0
end

function DataManager.AddStat(player, key, amount)
	local data = DataManager.Data(player)
	if not data or type(data.Stats) ~= "table" then return end
	data.Stats[key] = (data.Stats[key] or 0) + (amount or 1)
end

local function runPreReleaseHooks(player)
	for _, fn in ipairs(preReleaseHooks) do
		-- A throwing hook must never block the release: that would leak the
		-- session lock and stop the player loading their data on the next server.
		local ok, err = pcall(fn, player)
		if not ok then
			warn("[DataManager] pre-release hook failed: " .. tostring(err))
		end
	end
end

local function harden(data)
	data.Cash = tonumber(data.Cash) or 0
	data.Rebirths = tonumber(data.Rebirths) or 0
	data.RebirthMult = tonumber(data.RebirthMult) or 1
	data.Skin = tostring(data.Skin or "Default")
	if type(data.OwnedSkins) ~= "table" then data.OwnedSkins = { "Default" } end
	if type(data.Quests) ~= "table" then data.Quests = {} end
	if type(data.ClaimedQuests) ~= "table" then data.ClaimedQuests = {} end
	if type(data.RedeemedCodes) ~= "table" then data.RedeemedCodes = {} end
	if type(data.Receipts) ~= "table" then data.Receipts = {} end
	if type(data.Gifts) ~= "table" then data.Gifts = {} end
	if type(data.Stats) ~= "table" then data.Stats = { Eaten = 0, Kills = 0, PlayTime = 0 } end
	return data
end

local function onPlayerAdded(player)
	local profile
	local ok, result = pcall(function()
		return ProfileStore:LoadProfileAsync("Player_" .. player.UserId)
	end)
	if ok then profile = result end

	if profile == nil then
		-- Tell the player why: a silent kick reads as "the game is broken".
		warn(("[DataManager] could not load the profile of %s (%d): %s")
			:format(player.Name, player.UserId, tostring(result)))
		player:Kick("Your save could not be loaded. Please rejoin in a moment.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile:ListenToRelease(function()
		DataManager.Profiles[player] = nil
		-- Only kick if they are still here: ListenToRelease also fires on the
		-- normal release at PlayerRemoving.
		if player:IsDescendantOf(Players) then
			player:Kick("Your save was loaded on another server. Please rejoin.")
		end
	end)

	if not player:IsDescendantOf(Players) then
		profile:Release()
		return
	end

	DataManager.Profiles[player] = profile
	harden(profile.Data)

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local cash = Instance.new("NumberValue")
	cash.Name = "Cash"
	cash.Value = profile.Data.Cash
	cash.Parent = leaderstats

	local size = Instance.new("NumberValue")
	size.Name = "Size"
	size.Value = 0
	size.Parent = leaderstats

	leaderstats.Parent = player

	-- Last: everything else waits on this flag (characters, menus, progression).
	player:SetAttribute("DataLoaded", true)
end

local function onPlayerRemoving(player)
	local profile = DataManager.Profiles[player]
	if profile then
		runPreReleaseHooks(player)
		profile:Release()
	end
	DataManager.Profiles[player] = nil
end

function DataManager.Init()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(function(player)
		local ok, err = pcall(onPlayerAdded, player)
		if not ok then
			warn("[DataManager] PlayerAdded failed: " .. tostring(err))
		end
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return DataManager
