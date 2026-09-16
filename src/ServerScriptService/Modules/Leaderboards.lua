-- Global leaderboards (OrderedDataStore), cached so the menu is instant and a
-- spammy client cannot make the server re-read DataStores. Nothing here touches
-- a DataStore at require time, so the module loads in Studio on an unpublished
-- place and simply reports empty boards.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local Leaderboards = {}

local SIZE_STORE = "CubeLB_Size"
local CASH_STORE = "CubeLB_Cash"

-- Stores are opened lazily and behind pcall. GetOrderedDataStore throws when API
-- services are unavailable - an unpublished place in Studio, or "Enable Studio
-- Access to API Services" left off - and a throw at require time takes the whole
-- server down with it: Server.lua dies on this line and every module after it
-- never loads. Degrading to empty boards costs one warning instead.
local stores = {}
local storeState = nil  -- nil = not probed, false = unavailable, true = available

local function getStore(name)
	local cached = stores[name]
	if cached ~= nil then
		return cached or nil
	end
	if storeState == false then
		stores[name] = false
		return nil
	end

	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)
	if not ok or typeof(store) ~= "Instance" then
		storeState = false
		stores[name] = false
		warn(("[Leaderboards] DataStore unavailable (%s) - boards stay empty. Publish the place and enable Studio API access to fill them."):format(tostring(store)))
		return nil
	end

	storeState = true
	stores[name] = store
	return store
end

-- False until a store could be opened, so callers can tell "nobody is on the
-- board yet" apart from "this place cannot reach DataStores".
function Leaderboards.Available()
	return getStore(SIZE_STORE) ~= nil
end

local BOARD_SIZE = tonumber(GameConfig.get("LeaderboardSize", 50)) or 50
local TTL = tonumber(GameConfig.get("LeaderboardTtl", 20)) or 20
local THROTTLE = tonumber(GameConfig.get("LeaderboardThrottle", 5)) or 5
local WRITE_INTERVAL = tonumber(GameConfig.get("LeaderboardWriteInterval", 30)) or 30

local cache = { lists = { Size = {}, Cash = {} }, stamp = -math.huge }
local nameCache = {}
local lastRequest = {}

local function resolveName(userId)
	local cached = nameCache[userId]
	if cached ~= nil then return cached end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	-- Failures are cached too (as false) so one bad key is not retried forever.
	local result = (ok and type(name) == "string" and name ~= "") and name or false
	nameCache[userId] = result
	return result
end

local function readBoard(store)
	local entries = {}
	if not store then return entries, false end

	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, BOARD_SIZE)
	end)
	if not ok or not pages then return entries, false end

	local okPage, page = pcall(function() return pages:GetCurrentPage() end)
	if not okPage then return entries, false end

	for _, e in ipairs(page) do
		local id = tonumber(e.key)
		local name = id and resolveName(id)
		table.insert(entries, { name = name or "???", value = e.value })
	end
	return entries, true
end

local function refresh()
	local size, okSize = readBoard(getStore(SIZE_STORE))
	local cash, okCash = readBoard(getStore(CASH_STORE))
	if not okSize and not okCash then return false end
	-- Keep whichever board succeeded before, so a transient DataStore hiccup does
	-- not blank the UI.
	cache.lists = {
		Size = okSize and size or cache.lists.Size,
		Cash = okCash and cash or cache.lists.Cash,
	}
	cache.stamp = os.clock()
	return true
end

function Leaderboards.Cache()
	if os.clock() - cache.stamp > TTL then
		refresh()
	end
	return cache.lists
end

function Leaderboards.Send(player)
	Remotes.toClient(player, "Leaderboard", Leaderboards.Cache())
end

-- Client facing entry point: throttled per player.
function Leaderboards.Request(player)
	local now = os.clock()
	local last = lastRequest[player]
	if last and now - last < THROTTLE then return end
	lastRequest[player] = now
	Leaderboards.Send(player)
end

-- Attribute-guarded so a player whose numbers have not changed costs nothing.
function Leaderboards.Update(player)
	local ls = player:FindFirstChild("leaderstats")
	if not ls or not DataManager.HasProfile(player) then return end

	local sizeStore, cashStore = getStore(SIZE_STORE), getStore(CASH_STORE)
	if not sizeStore and not cashStore then return end

	local size = ls:FindFirstChild("Size")
	local sizeVal = size and math.floor(size.Value) or 0
	if sizeStore and player:GetAttribute("LB_Size") ~= sizeVal then
		local ok = pcall(function() sizeStore:SetAsync(tostring(player.UserId), sizeVal) end)
		if ok then player:SetAttribute("LB_Size", sizeVal) end
	end

	local cashVal = math.floor(DataManager.Cash(player))
	if cashStore and player:GetAttribute("LB_Cash") ~= cashVal then
		local ok = pcall(function() cashStore:SetAsync(tostring(player.UserId), cashVal) end)
		if ok then player:SetAttribute("LB_Cash", cashVal) end
	end
end

function Leaderboards.PlayerRemoving(player)
	lastRequest[player] = nil
end

function Leaderboards.Init()
	Remotes.onServer("Leaderboard", Leaderboards.Request)

	-- Keep the cache warm and push periodic writes.
	task.spawn(function()
		while task.wait(TTL) do
			pcall(refresh)
		end
	end)

	task.spawn(function()
		while task.wait(WRITE_INTERVAL) do
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(Leaderboards.Update, player)
				if not ok then warn("[Leaderboards] write failed: " .. tostring(err)) end
			end
		end
	end)
end

return Leaderboards
