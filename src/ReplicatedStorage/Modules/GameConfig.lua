--!nonstrict
-- Types for the content contract. Every module reads game content through this
-- file, so these aliases are the shapes the whole codebase agrees on. Typing is
-- gradual (nonstrict): an unannotated module still checks out, and tools/verify.py
-- strips the annotations before its Lua 5.x parse, so the round trip and the
-- syntax pass keep working without a Luau binary.
--!strict
-- GameConfig: reads the game's CONTENT out of the place, never out of code.
--
-- Everything tunable is an instance you can edit in Studio:
--   ReplicatedStorage/GameData/Settings     scalars (food targets, rebirth curve...)
--   ReplicatedStorage/GameData/Admins       who may use the admin console (UserId)
--   ReplicatedStorage/GameData/Ranks        rank name -> size threshold
--   ReplicatedStorage/GameData/Rarities     food tiers: Weight/Value/Size/Color
--   ReplicatedStorage/GameData/Skins        Color/Unlock/Req/Order
--   ReplicatedStorage/GameData/Quests       Type/Goal/RewardCash/RewardSkin/Text
--   ReplicatedStorage/GameData/Gifts        RequiredTime/Reward/Type
--   ReplicatedStorage/GameData/Codes        code -> cash
--   ReplicatedStorage/GameData/Tabs         which menu each HUD tab row opens
--   ReplicatedStorage/GameData/Products     ProductId/Kind/Amount/Label
--   ReplicatedStorage/GameData/Gamepasses   GamePassId/Kind
--   Workspace/Zones/<Name>                  every zone is its own arena: a Model
--                                           holding a Floor slab, four walls and a
--                                           sign. The Floor's position/size define
--                                           the spawn area, and the Id/Rarity/
--                                           ReqSize/ReqRebirth/Color children (on
--                                           the Model, or on the part for a hand
--                                           built zone) define the rules. Move or
--                                           resize an arena and the game follows.
--
-- This module only READS those instances at require time and exposes plain Lua
-- tables, so gameplay code never touches the instance tree.
local GameConfig = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules", 60)
local GameData = ReplicatedStorage:WaitForChild("GameData", 60)
if not GameData then
	warn("[GameConfig] ReplicatedStorage.GameData is missing - the game has no content to load.")
	GameData = Instance.new("Folder")
end

local missingWarned = {}

export type Rarity = {
	name: string,
	weight: number,
	value: number,
	size: number,
	color: Color3,
	rgb: { number },
}

export type Skin = {
	id: string,
	color: Color3,
	rgb: { number },
	unlock: string, -- start | cash | size | rebirth
	req: number,
	order: number,
}

-- A zone IS its arena: the Floor part supplies the centre, the half width
-- (radius) and the top surface; the value children supply the rules.
-- centre is {x, topY, z}.
export type Zone = {
	id: number,
	name: string,
	part: BasePart,
	color: Color3,
	rgb: { number },
	rarity: string,
	req: { size: number?, rebirth: number? },
	center: { number },
	radius: number,
	topY: number,
}

export type Quest = {
	id: string,
	type: string, -- eat | kill | rebirth | size
	goal: number,
	rewardCash: number,
	rewardSkin: string,
	text: string,
	order: number,
}

-- Client preferences. Keys and default values come from GameData/Prefs, so the
-- value type is whatever the content says it is.
export type TabEntry = {
	target: string,   -- a frame name under StarterGui/Frames, or "@Action"
	label: string,
	sub: string,
	color: Color3,
	order: number,
}

export type Tab = {
	name: string,
	entries: { TabEntry },
}

export type Prefs = { [string]: boolean | number | string }

local function want(parent: Instance?, name: string): Instance?
	local child = parent and parent:FindFirstChild(name)
	if not child then
		local key = tostring(parent and parent.Name) .. "/" .. name
		if not missingWarned[key] then
			missingWarned[key] = true
			warn(("[GameConfig] GameData.%s is missing; using the fallback."):format(key))
		end
	end
	return child
end

local function valueOf(instance: Instance?, fallback: any): any
	if instance == nil then return fallback end
	local v = instance.Value
	if v == nil then return fallback end
	return v
end

local function numbers(folder: Instance?): { number }
	local out = {}
	if not folder then return out end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("NumberValue") or child:IsA("IntValue") then
			out[child.Name] = child.Value
		elseif child:IsA("StringValue") then
			out[child.Name] = child.Value
		elseif child:IsA("BoolValue") then
			out[child.Name] = child.Value
		end
	end
	return out
end

local function rgbOf(color3: Color3): { number }
	return { math.floor(color3.R * 255 + 0.5), math.floor(color3.G * 255 + 0.5), math.floor(color3.B * 255 + 0.5) }
end

local function colorOf(parent: Instance?, fallback: { number }): Color3
	local cv = parent and parent:FindFirstChild("Color")
	if cv and cv:IsA("Color3Value") then
		return cv.Value
	end
	return Color3.fromRGB(fallback[1], fallback[2], fallback[3])
end

--// ------------------------------------------------------------------ settings
local SETTINGS = numbers(want(GameData, "Settings"))
GameConfig.SETTINGS = SETTINGS

local function setting(name: string, fallback: any): any
	local v = SETTINGS[name]
	if v == nil then return fallback end
	return v
end
GameConfig.get = setting

GameConfig.GAME_NAME = tostring(setting("GameName", "Eat The Cube"))
GameConfig.GROUP_ID = tonumber(setting("GroupId", 0)) or 0
GameConfig.DATASTORE_NAME = tostring(setting("DataStoreName", "Yeah"))

GameConfig.MAP = {
	FloorY = tonumber(setting("FloorY", 0)) or 0,
	WallInnerX = tonumber(setting("WallInnerX", 278.5)) or 278.5,
	WallInnerZ = tonumber(setting("WallInnerZ", 328.5)) or 328.5,
	SpawnRegion = {
		minX = tonumber(setting("SpawnRegionMinX", -272)) or -272,
		maxX = tonumber(setting("SpawnRegionMaxX", 272)) or 272,
		minZ = tonumber(setting("SpawnRegionMinZ", -322)) or -322,
		maxZ = tonumber(setting("SpawnRegionMaxZ", 322)) or 322,
	},
}

GameConfig.CONFIG = {
	BaseFoodTarget = tonumber(setting("BaseFoodTarget", 420)) or 420,
	ZoneFoodTarget = tonumber(setting("ZoneFoodTarget", 60)) or 60,
	SpawnInterval = tonumber(setting("SpawnInterval", 1.5)) or 1.5,
	SpawnBatch = tonumber(setting("SpawnBatch", 10)) or 10,
	SeedBatch = tonumber(setting("SeedBatch", 40)) or 40,
	SpawnRegion = GameConfig.MAP.SpawnRegion,
}

--// -------------------------------------------------------------------- admins
GameConfig.ADMINS = {}
local adminsFolder = want(GameData, "Admins")
if adminsFolder then
	for _, entry in ipairs(adminsFolder:GetChildren()) do
		local idValue = entry:FindFirstChild("UserId")
		local id = tonumber(valueOf(idValue, entry.Name))
		if id then
			GameConfig.ADMINS[id] = tostring(valueOf(entry:FindFirstChild("Role"), "admin"))
		end
	end
end

-- Admin access is by UserId (Settings/Admins in the asset), with the group as an
-- optional fallback so a whole team can be granted access later.
function GameConfig.isAdmin(userId: number, player: Player?): boolean
	userId = tonumber(userId)
	if userId and GameConfig.ADMINS[userId] then return true end
	local group = GameConfig.GROUP_ID
	if group and group > 0 and player then
		local ok, inGroup = pcall(function() return player:IsInGroup(group) end)
		if ok and inGroup then
			local okRank, rank = pcall(function() return player:GetRankInGroup(group) end)
			-- 250+ is admin/owner rank; ordinary members do not get the console.
			if okRank and (rank or 0) >= 250 then return true end
		end
	end
	return false
end

--// --------------------------------------------------------------------- ranks
local RANKS = {}
local ranksFolder = want(GameData, "Ranks")
if ranksFolder then
	for _, entry in ipairs(ranksFolder:GetChildren()) do
		if entry:IsA("NumberValue") or entry:IsA("IntValue") then
			table.insert(RANKS, { name = entry.Name, threshold = tonumber(entry.Value) or 0 })
		end
	end
end
table.sort(RANKS, function(a, b) return a.threshold < b.threshold end)
if #RANKS == 0 then
	RANKS = { { name = "Cube", threshold = 0 } }
end
GameConfig.RANKS = RANKS

function GameConfig.getRank(sizeVal: number, rebirths: number): string
	local scale = 1 + (rebirths or 0) * (tonumber(setting("RankRebirthScale", 0.6)) or 0.6)
	local rank = 1
	for i, entry in ipairs(RANKS) do
		if (sizeVal or 0) >= entry.threshold * scale then rank = i end
	end
	return rank, RANKS[rank].name
end

--// ----------------------------------------------------------------- rarities
local RARITIES = {}
local RARITY_LIST: { Rarity } = {}
local rarityFolder = want(GameData, "Rarities")
if rarityFolder then
	for _, entry in ipairs(rarityFolder:GetChildren()) do
		local weight = tonumber(valueOf(entry:FindFirstChild("Weight"), 0)) or 0
		local value = tonumber(valueOf(entry:FindFirstChild("Value"), 1)) or 1
		local size = tonumber(valueOf(entry:FindFirstChild("Size"), 1)) or 1
		local color = colorOf(entry, { 255, 255, 255 })
		RARITIES[entry.Name] = {
			name = entry.Name, weight = weight, value = value, size = size,
			color = color, rgb = rgbOf(color),
		}
		table.insert(RARITY_LIST, RARITIES[entry.Name])
	end
end
table.sort(RARITY_LIST, function(a, b) return a.value < b.value end)
GameConfig.RARITIES = RARITIES
GameConfig.RARITY_LIST = RARITY_LIST

-- pick a rarity key, optionally raising the floor (the VIP wing)
function GameConfig.pickRarity(floorTier: string?): string
	local floorValue = nil
	if floorTier ~= nil then
		local floorRarity = RARITIES[floorTier]
		if floorRarity then
			floorValue = floorRarity.value
		else
			warn(("[GameConfig] unknown rarity floor %q"):format(tostring(floorTier)))
		end
	end

	local pool, total = {}, 0
	for _, r in ipairs(RARITY_LIST) do
		if floorValue == nil or r.value >= floorValue then
			table.insert(pool, r)
			total += r.weight
		end
	end
	if #pool == 0 or total <= 0 then
		return RARITY_LIST[1] and RARITY_LIST[1].name or "Common"
	end

	local roll = math.random() * total
	for _, r in ipairs(pool) do
		roll -= r.weight
		if roll <= 0 then return r.name end
	end
	return pool[#pool].name
end

--// --------------------------------------------------------------------- skins
local SKINS = {}
local skinsFolder = want(GameData, "Skins")
if skinsFolder then
	for _, entry in ipairs(skinsFolder:GetChildren()) do
		local color = colorOf(entry, { 255, 0, 80 })
		table.insert(SKINS, {
			id = entry.Name,
			color = color,
			rgb = rgbOf(color),
			unlock = tostring(valueOf(entry:FindFirstChild("Unlock"), "start")),
			req = tonumber(valueOf(entry:FindFirstChild("Req"), 0)) or 0,
			order = tonumber(valueOf(entry:FindFirstChild("Order"), 0)) or 0,
		})
	end
end
table.sort(SKINS, function(a, b2)
	if a.order ~= b2.order then return a.order < b2.order end
	return a.id < b2.id
end)
if #SKINS == 0 then
	SKINS = { { id = "Default", color = Color3.fromRGB(255, 0, 80), rgb = { 255, 0, 80 }, unlock = "start", req = 0, order = 1 } }
end
GameConfig.SKINS = SKINS

function GameConfig.getSkin(skinId: string?): Skin?
	for _, s in ipairs(SKINS) do
		if s.id == skinId then return s end
	end
	return nil
end

--// --------------------------------------------------------------------- tabs
-- The HUD has three tab buttons; each opens a launcher panel whose rows come
-- from GameData/Tabs, so which menu a row opens - and which tab it lives on - is
-- a Studio edit rather than a script change. A target starting with "@" names an
-- action (see Menus/Tabs.lua) instead of a frame.
local TABS: { Tab } = {}
local tabsFolder = want(GameData, "Tabs")
if tabsFolder then
	for _, tab in ipairs(tabsFolder:GetChildren()) do
		local entries: { TabEntry } = {}
		for _, entry in ipairs(tab:GetChildren()) do
			local target = tostring(valueOf(entry:FindFirstChild("Target"), ""))
			if target ~= "" then
				table.insert(entries, {
					target = target,
					label = tostring(valueOf(entry:FindFirstChild("Label"), entry.Name)),
					sub = tostring(valueOf(entry:FindFirstChild("Sub"), "")),
					color = colorOf(entry, { 0, 200, 255 }),
					order = tonumber(valueOf(entry:FindFirstChild("Order"), #entries + 1)) or (#entries + 1),
				})
			end
		end
		table.sort(entries, function(a, b2) return a.order < b2.order end)
		table.insert(TABS, { name = tab.Name, entries = entries })
	end
end
GameConfig.TABS = TABS

function GameConfig.getTab(name: string): Tab?
	for _, tab in ipairs(TABS) do
		if tab.name == name then return tab end
	end
	return nil
end

--// --------------------------------------------------------------------- zones
local ZONES = {}
GameConfig.ZONES = ZONES          -- the same table GameConfig.zones() fills

-- Scan workspace/Zones, where every zone is its own arena: a Model holding the
-- Floor slab (the walkable region, and the source of centre/radius/topY), four
-- walls, a sign and the rule values. A bare Part is still accepted, so a zone
-- hand built in Studio does not need the wrapper.
--
-- The server always has the map at require time; a ReplicatedFirst client may
-- not, so the scan is re-runnable and never blocks for long (a 30 second
-- WaitForChild here would freeze the loading screen). Zone models are Persistent
-- - they never stream out, which is what lets a client in the hub list arenas
-- 1500 studs away - but they land a moment after join, so an empty folder gets
-- one short bounded wait instead of an empty Zones menu.
local zonesScanned = false
local zonesWaited = false
local ZONE_ARRIVAL_WAIT = 1.5

-- Rule values live on the arena Model, or on the part itself for a hand built
-- zone; either way the same names mean the same thing.
local function zoneValue(entry: Instance, floor: Instance, name: string, fallback: any): any
	local found = entry:FindFirstChild(name)
	if not found then found = floor:FindFirstChild(name) end
	return valueOf(found, fallback)
end

local function scanZones(waitSeconds: number?): boolean
	local folder = workspace:FindFirstChild("Zones")
	if not folder and waitSeconds then
		folder = workspace:WaitForChild("Zones", waitSeconds)
	end
	if not folder then return false end

	if waitSeconds and not zonesWaited and #folder:GetChildren() == 0 then
		zonesWaited = true
		local deadline = os.clock() + math.min(waitSeconds, ZONE_ARRIVAL_WAIT)
		while #folder:GetChildren() == 0 and os.clock() < deadline do
			task.wait(0.05)
		end
	end

	table.clear(ZONES)
	for _, entry in ipairs(folder:GetChildren()) do
		local floor: BasePart? = nil
		if entry:IsA("BasePart") then
			floor = entry
		else
			local slab = entry:FindFirstChild("Floor")
			if slab and slab:IsA("BasePart") then floor = slab end
		end

		if floor then
			local id = tonumber(zoneValue(entry, floor, "Id", 0)) or 0
			local color = colorOf(entry, rgbOf(floor.Color))
			local req = {}
			local reqSize = tonumber(zoneValue(entry, floor, "ReqSize", 0)) or 0
			local reqRebirth = tonumber(zoneValue(entry, floor, "ReqRebirth", 0)) or 0
			if reqSize > 0 then req.size = reqSize end
			if reqRebirth > 0 then req.rebirth = reqRebirth end

			table.insert(ZONES, {
				id = id,
				name = entry.Name,
				part = floor,
				color = color,
				rgb = rgbOf(color),
				rarity = tostring(zoneValue(entry, floor, "Rarity", "Common")),
				req = req,
				center = { floor.Position.X, floor.Position.Y + floor.Size.Y / 2, floor.Position.Z },
				radius = math.min(floor.Size.X, floor.Size.Z) / 2,
				topY = floor.Position.Y + floor.Size.Y / 2,
			})
		end
	end

	table.sort(ZONES, function(a, b) return a.id < b.id end)
	zonesScanned = true
	return true
end

-- First attempt without waiting at all; zones() retries once the map is there.
scanZones(nil)

-- The zone list. Client menus must call this rather than reading ZONES directly,
-- because in ReplicatedFirst the map may not have replicated at require time.
function GameConfig.zones(): { Zone }
	if not zonesScanned or #ZONES == 0 then
		scanZones(5)
	end
	return ZONES
end

function GameConfig.getZone(zoneId: number): Zone?
	zoneId = tonumber(zoneId)
	for _, z in ipairs(GameConfig.zones()) do
		if z.id == zoneId then return z end
	end
	return nil
end

-- Human readable lock reason ("" when unlocked). Used by the server gate, the
-- Zones menu and the generated signs so all three always agree.
function GameConfig.zoneLockReason(zone: Zone?, sizeVal: number, rebirths: number): string
	if not zone or not zone.req then return "" end
	local req = zone.req
	if req.rebirth and (rebirths or 0) < req.rebirth then
		return "Requires " .. req.rebirth .. " Rebirth" .. (req.rebirth == 1 and "" or "s")
	end
	if req.size and (sizeVal or 0) < req.size then
		return "Requires Size " .. req.size
	end
	return ""
end

--// -------------------------------------------------------------------- VIP
local vipRegion = {
	minX = tonumber(setting("VipRegionMinX", 288)) or 288,
	maxX = tonumber(setting("VipRegionMaxX", 405)) or 405,
	minZ = tonumber(setting("VipRegionMinZ", -56)) or -56,
	maxZ = tonumber(setting("VipRegionMaxZ", 60)) or 60,
}
GameConfig.VIP = {
	ZoneId = tonumber(setting("VipZoneId", 6)) or 6,
	FoodTarget = tonumber(setting("VipFoodTarget", 130)) or 130,
	RarityFloor = tostring(setting("VipRarityFloor", "Rare")),
	Region = vipRegion,
	Teleport = Vector3.new(
		tonumber(setting("VipTeleportX", 350)) or 350,
		GameConfig.MAP.FloorY + 5,
		tonumber(setting("VipTeleportZ", 2)) or 2),
}

--// ------------------------------------------------------------------- quests
local QUESTS = {}
local questsFolder = want(GameData, "Quests")
if questsFolder then
	for _, entry in ipairs(questsFolder:GetChildren()) do
		table.insert(QUESTS, {
			id = entry.Name,
			type = tostring(valueOf(entry:FindFirstChild("Type"), "eat")),
			goal = tonumber(valueOf(entry:FindFirstChild("Goal"), 1)) or 1,
			rewardCash = tonumber(valueOf(entry:FindFirstChild("RewardCash"), 0)) or 0,
			rewardSkin = tostring(valueOf(entry:FindFirstChild("RewardSkin"), "")),
			text = tostring(valueOf(entry:FindFirstChild("Text"), entry.Name)),
			order = tonumber(valueOf(entry:FindFirstChild("Order"), 0)) or 0,
		})
	end
end
table.sort(QUESTS, function(a, b2)
	if a.order ~= b2.order then return a.order < b2.order end
	return a.id < b2.id
end)
GameConfig.QUESTS = QUESTS

--// -------------------------------------------------------------------- gifts
local GIFTS = {}
local giftsFolder = want(GameData, "Gifts")
if giftsFolder then
	for _, entry in ipairs(giftsFolder:GetChildren()) do
		local id = tonumber(entry.Name)
		if id then
			GIFTS[id] = {
				RequiredTime = tonumber(valueOf(entry:FindFirstChild("RequiredTime"), 0)) or 0,
				Reward = tonumber(valueOf(entry:FindFirstChild("Reward"), 0)) or 0,
				Type = tostring(valueOf(entry:FindFirstChild("Type"), "Size")),
			}
		end
	end
end
GameConfig.GIFTS = GIFTS

--// --------------------------------------------------------------- update log
local UPDATELOG = {}
local logFolder = want(GameData, "UpdateLog")
if logFolder then
	for _, entry in ipairs(logFolder:GetChildren()) do
		local index = tonumber(entry.Name)
		if index and entry:IsA("StringValue") then
			UPDATELOG[index] = tostring(entry.Value)
		end
	end
end
GameConfig.UPDATELOG = UPDATELOG

--// -------------------------------------------------------------------- prefs
-- Defaults for the client settings menu (GameData/Prefs). A player's own values
-- live in their profile under Data.Prefs; these are what a fresh profile starts
-- from, and they stay editable in Studio like every other content.
local PREFS: Prefs = {}
local prefsFolder = want(GameData, "Prefs")
if prefsFolder then
	for _, entry in ipairs(prefsFolder:GetChildren()) do
		if entry:IsA("BoolValue") then
			PREFS[entry.Name] = entry.Value == true
		elseif entry:IsA("NumberValue") or entry:IsA("IntValue") then
			PREFS[entry.Name] = tonumber(entry.Value) or 0
		elseif entry:IsA("StringValue") then
			PREFS[entry.Name] = tostring(entry.Value)
		end
	end
end
GameConfig.PREFS = PREFS

-- Merge saved prefs over the defaults. Unknown keys are dropped and a value whose
-- type does not match the default is replaced, so neither a stale profile nor a
-- tampered client can invent settings. Used by both the server and the client.
function GameConfig.mergePrefs(saved: { [string]: any }?): Prefs
	local out = {}
	local hasSaved = type(saved) == "table"
	for key, default in pairs(PREFS) do
				local value = nil
		if hasSaved then value = saved[key] end
		if typeof(value) == typeof(default) then
			out[key] = value
		else
			out[key] = default
		end
	end
	return out
end

--// -------------------------------------------------------------------- codes
local CODES = {}
local codesFolder = want(GameData, "Codes")
if codesFolder then
	for _, entry in ipairs(codesFolder:GetChildren()) do
		if entry:IsA("NumberValue") or entry:IsA("IntValue") or entry:IsA("StringValue") then
			CODES[entry.Name:upper()] = tonumber(entry.Value) or 0
		end
	end
end
GameConfig.CODES = CODES

--// ----------------------------------------------------------------- products
local PRODUCTS = {}
local PRODUCT_LIST = {}
local productsFolder = want(GameData, "Products")
if productsFolder then
	for _, entry in ipairs(productsFolder:GetChildren()) do
		local id = tonumber(valueOf(entry:FindFirstChild("ProductId"), 0)) or 0
		if id > 0 then
			local def = {
				id = entry.Name,
				productId = id,
				kind = tostring(valueOf(entry:FindFirstChild("Kind"), "size")),
				amount = tonumber(valueOf(entry:FindFirstChild("Amount"), 0)) or 0,
				label = tostring(valueOf(entry:FindFirstChild("Label"), entry.Name)),
			}
			PRODUCTS[id] = def
			table.insert(PRODUCT_LIST, def)
		end
	end
end
GameConfig.PRODUCTS = PRODUCTS
GameConfig.PRODUCT_LIST = PRODUCT_LIST

function GameConfig.getProductByKind(kind: string): any
	for _, def in ipairs(PRODUCT_LIST) do
		if def.kind == kind then return def end
	end
	return nil
end

--// --------------------------------------------------------------- gamepasses
local PASSES = {}
local passesFolder = want(GameData, "Gamepasses")
if passesFolder then
	for _, entry in ipairs(passesFolder:GetChildren()) do
		local kind = tostring(valueOf(entry:FindFirstChild("Kind"), entry.Name))
		local id = tonumber(valueOf(entry:FindFirstChild("GamePassId"), 0)) or 0
		if id > 0 then PASSES[kind] = id end
	end
end
GameConfig.GAMEPASSES = PASSES
GameConfig.VIP.GamePassId = PASSES.vip or 975187916

function GameConfig.passId(kind: string): number
	return PASSES[kind]
end

--// ------------------------------------------------------------ progression math
function GameConfig.visualSize(sizeVal: number): number
	local factor = tonumber(setting("VisualSizeFactor", 0.12)) or 0.12
	return 1 + math.sqrt(math.max(sizeVal or 0, 0)) * factor
end

function GameConfig.maxCubeSize(): number
	return tonumber(setting("MaxCubeSize", 220)) or 220
end

-- r0 = 450, r1 = 1715, r2 = 4550, r5 = 27.4k, r10 = 109.7k with the shipped numbers
function GameConfig.rebirthRequirement(rebirths: number): number
	local r = math.max(rebirths or 0, 0)
	local base = tonumber(setting("RebirthBase", 250)) or 250
	local exp = tonumber(setting("RebirthExponent", 2.6)) or 2.6
	local add = tonumber(setting("RebirthAdd", 200)) or 200
	return math.floor(base * ((r + 1) ^ exp)) + add
end

function GameConfig.rebirthMultiplier(rebirths: number): number
	local step = tonumber(setting("RebirthMultStep", 0.12)) or 0.12
	return 1 + (rebirths or 0) * step
end

-- Cash payout for rebirthing: feeds the cash-priced skins, so Cash is a currency
-- with something to spend it on instead of just a number in the HUD.
function GameConfig.rebirthCashReward(rebirths: number): number
	local per = tonumber(setting("RebirthCashPerLevel", 250)) or 250
	return per * math.max(rebirths or 0, 0)
end

-- Cash per cube eaten; doubled by the x2 Cash gamepass.
function GameConfig.cashPerCube(rebirths: number, hasDoubleCash: boolean): number
	local base = tonumber(setting("CashPerCubeBase", 1)) or 1
	local per = tonumber(setting("CashPerCubePerRebirth", 1)) or 1
	return base + per * math.max(rebirths or 0, 0) * (hasDoubleCash and 2 or 1)
end

function GameConfig.color3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

return GameConfig
