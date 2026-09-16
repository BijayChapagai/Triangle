-- Player lifecycle: gamepass ownership, session playtime, and handing the
-- character work over to Characters. Join order does not matter because every
-- data-dependent step waits on the DataLoaded attribute that DataManager sets.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Progression = require(script.Parent:WaitForChild("Progression"))
local Characters = require(script.Parent:WaitForChild("Characters"))

local PlayerModule = {}

local playTimeThreads = {}

local PASS_ATTRIBUTES = {
	speed = "2xSpeed",
	cash = "2xMoney",
	vip = "VIP",
}

local function ownsPass(player, passId)
	if not passId or passId <= 0 then return false end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	if not ok then
		-- Throttled or offline: leave the attribute unset rather than guessing.
		warn(("[Players] gamepass check failed for %s: %s"):format(player.Name, tostring(owns)))
		return false
	end
	return owns == true
end

-- Cached on attributes so every later respawn is free and no repeated
-- MarketplaceService calls can throttle.
local function cacheGamepasses(player)
	for kind, attribute in pairs(PASS_ATTRIBUTES) do
		local passId = GameConfig.passId(kind)
		if passId and ownsPass(player, passId) then
			player:SetAttribute(attribute, true)
		end
	end
end

local function startPlayTime(player)
	playTimeThreads[player] = true
	task.spawn(function()
		while playTimeThreads[player] and player.Parent do
			task.wait(1)
			if not (playTimeThreads[player] and player.Parent) then break end
			local t = (player:GetAttribute("PlayerTime") or 0) + 1
			player:SetAttribute("PlayerTime", t)
			if t % 60 == 0 then
				DataManager.AddStat(player, "PlayTime", 60)
			end
		end
	end)
end

-- The profile loads asynchronously; progression must not start before it exists.
local function waitForData(player, timeout)
	if player:GetAttribute("DataLoaded") then return true end

	local loaded = false
	local conn
	conn = player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		if player:GetAttribute("DataLoaded") then loaded = true end
	end)

	local deadline = os.clock() + (timeout or 60)
	while not loaded and os.clock() < deadline and player.Parent do
		task.wait(0.1)
	end
	if conn then conn:Disconnect() end
	return loaded
end

local function onPlayerAdded(player)
	cacheGamepasses(player)

	local ok, err = pcall(Characters.PlayerSetup, player)
	if not ok then
		warn(("[Players] character setup failed for %s: %s"):format(player.Name, tostring(err)))
	end

	startPlayTime(player)

	-- Quests, skins, gifts and the leaderboard all need the profile. Without this
	-- hand-off nothing progression related would ever be initialised: the server
	-- would silently ignore every quest and skin request.
	task.spawn(function()
		if not waitForData(player) then
			warn(("[Players] %s never finished loading data - progression is inactive")
				:format(player.Name))
			return
		end
		if not player.Parent then return end
		local ok2, err2 = pcall(Progression.InitPlayer, player)
		if not ok2 then
			warn(("[Players] progression init failed for %s: %s"):format(player.Name, tostring(err2)))
		end
	end)
end

local function onPlayerRemoving(player)
	playTimeThreads[player] = nil
	Characters.PlayerRemoving(player)
end

function PlayerModule.Init()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Buying a pass mid-session applies immediately instead of on the next rejoin.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then return end
		for kind, attribute in pairs(PASS_ATTRIBUTES) do
			if GameConfig.passId(kind) == passId then
				player:SetAttribute(attribute, true)
				if kind == "speed" then
					local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if humanoid then humanoid.WalkSpeed *= 2 end
				elseif kind == "vip" then
					Progression.notify(player, "VIP unlocked: the VIP wing and its rare food are yours.", "good")
				else
					Progression.notify(player, "x2 Cash is now active!", "good")
				end
			end
		end
	end)
end

return PlayerModule
