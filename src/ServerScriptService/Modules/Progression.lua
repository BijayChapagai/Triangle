-- Progression: rebirths, skins, daily quests, zone gating and the visuals that
-- go with them. All numbers come from the GameData instances via GameConfig.
--
-- Two rules this module is written around:
--   1. Nothing here may throw into gameplay code. Remotes go through Remotes.*,
--      which no-ops (and warns once) when an event is missing from the place.
--   2. Nothing expensive is client-triggerable without a throttle.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Leaderboards = require(script.Parent:WaitForChild("Leaderboards"))

local Progression = {}

local Progress = {}          -- [player] = { questId = progress }
local sizeTweens = {}        -- [character] = Tween
local lastRebirthRequest = {}
local lastZoneTeleport = {}   -- [player] = os.clock(), throttles the zone remote

local function dayStamp()
	return math.floor(os.time() / 86400)
end

local function sizeOf(player)
	local ls = player:FindFirstChild("leaderstats")
	local size = ls and ls:FindFirstChild("Size")
	return size and size.Value or 0
end

--// ------------------------------------------------------------------- notify
-- Server -> client toast. kind: "info" | "good" | "bad"
function Progression.notify(player, text, kind)
	Remotes.toClient(player, "Notify", tostring(text), kind or "info")
end

--// ------------------------------------------------------------------ visuals
function Progression.setCubeSize(character, target)
	if not character then return end
	local part = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	if not part then return end

	local max = GameConfig.maxCubeSize()
	local v = math.clamp(target or 1, 0.4, max)
	local time = tonumber(GameConfig.get("SizeTweenTime", 0.22)) or 0.22
	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local existing = sizeTweens[character]
	if existing then existing:Cancel() end

	local tween = TweenService:Create(part, info, { Size = Vector3.new(v, v, v) })
	sizeTweens[character] = tween
	tween.Completed:Connect(function()
		if sizeTweens[character] == tween then sizeTweens[character] = nil end
	end)
	tween:Play()
	return v
end

-- Re-assert the physical cube size, but only when it has actually drifted and no
-- tween is in flight. Called by Characters' slow heartbeat: the character is
-- client-owned, so a modified client can resize its own cube and a bigger hitbox
-- eats more food per second.
function Progression.assertCubeSize(character, target)
	if not character then return false end
	if sizeTweens[character] then return false end
	local part = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	if not part then return false end

	local want = math.clamp(target or 1, 0.4, GameConfig.maxCubeSize())
	if math.abs(part.Size.X - want) < 0.05 then return false end

	Progression.setCubeSize(character, want)
	return true
end

function Progression.applySkin(player)
	local data = DataManager.Data(player)
	local char = player.Character
	if not char or not char.PrimaryPart then return end
	local skin = GameConfig.getSkin(data and data.Skin) or GameConfig.SKINS[1]
	char.PrimaryPart.Color = skin.color
end

function Progression.refreshVisuals(player)
	Progression.applySkin(player)
	Progression.setCubeSize(player.Character, GameConfig.visualSize(sizeOf(player)))
end

function Progression.applyRankText(player)
	local ls = player:FindFirstChild("leaderstats")
	local size = ls and ls:FindFirstChild("Size")
	if not size then return end
	local _, rankName = GameConfig.getRank(size.Value, DataManager.Rebirths(player))
	local char = player.Character
	local display = char and char:FindFirstChild("PlayerDisplay")
	local label = display and display:FindFirstChild("PlayerSize")
	if label then
		label.Text = ("Size: %d  [%s]"):format(math.floor(size.Value), rankName)
	end
end

--// ------------------------------------------------------------------- quests
local function ownsSkin(data, skinId)
	for _, s in ipairs(data.OwnedSkins or {}) do
		if s == skinId then return true end
	end
	return false
end

local function sendQuests(player)
	local prog = Progress[player] or {}
	local data = DataManager.Data(player)
	local claimed = (data and data.ClaimedQuests) or {}
	local payload = {}
	for _, q in ipairs(GameConfig.QUESTS) do
		table.insert(payload, {
			id = q.id,
			text = q.text,
			goal = q.goal,
			progress = prog[q.id] or 0,
			claimed = claimed[q.id] or false,
			rewardCash = q.rewardCash or 0,
			rewardSkin = (q.rewardSkin ~= "" and q.rewardSkin) or nil,
		})
	end
	Remotes.toClient(player, "QuestUpdate", payload)
end
Progression.sendQuests = sendQuests

local function pushQuest(player, q, value, claimed)
	Remotes.toClient(player, "QuestUpdate", q.id, value, value >= (q.goal or 1), claimed or false)
end

function Progression.AddProgress(player, questType, amount)
	local data = DataManager.Data(player)
	local prog = Progress[player]
	if not data or not prog then return end

	for _, q in ipairs(GameConfig.QUESTS) do
		if q.type == questType and q.goal > 0 then
			local current = prog[q.id] or 0
			if current < q.goal then
				current = math.min(q.goal, current + (amount or 1))
				prog[q.id] = current
				data.Quests[q.id] = current
				pushQuest(player, q, current, data.ClaimedQuests[q.id] or false)
			end
		end
	end
end

function Progression.CheckSize(player)
	local data = DataManager.Data(player)
	if not data then return end
	local prog = Progress[player]
	local size = sizeOf(player)

	if prog then
		for _, q in ipairs(GameConfig.QUESTS) do
			if q.type == "size" then
				local current = math.min(size, q.goal)
				if (prog[q.id] or 0) < current then
					prog[q.id] = current
					data.Quests[q.id] = current
					pushQuest(player, q, current, data.ClaimedQuests[q.id] or false)
				end
			end
		end
	end

	-- "size" skins are achievements: granted permanently the first time the
	-- milestone is hit (size resets on death/rebirth, ownership does not).
	local unlocked
	for _, s in ipairs(GameConfig.SKINS) do
		if s.unlock == "size" and size >= s.req and not ownsSkin(data, s.id) then
			table.insert(data.OwnedSkins, s.id)
			unlocked = unlocked or {}
			table.insert(unlocked, s.id)
		end
	end
	if unlocked then
		Progression.sendSkins(player)
		for _, id in ipairs(unlocked) do
			Progression.notify(player, ("Unlocked the %s skin!"):format(id), "good")
		end
	end
end

-- Claim every finished, unclaimed quest in one click. Each reward still goes
-- through ClaimQuest, so nothing can be paid twice or bypass its own checks.
function Progression.ClaimAllQuests(player)
	local data = DataManager.Data(player)
	local prog = Progress[player]
	if not data or not prog then return 0 end

	local claimed = 0
	for _, q in ipairs(GameConfig.QUESTS) do
		if not data.ClaimedQuests[q.id] and (prog[q.id] or 0) >= q.goal then
			Progression.ClaimQuest(player, q.id)
			claimed += 1
		end
	end
	return claimed
end

function Progression.ClaimQuest(player, questId)
	local data = DataManager.Data(player)
	local prog = Progress[player]
	if not data or not prog or typeof(questId) ~= "string" then return end

	for _, q in ipairs(GameConfig.QUESTS) do
		if q.id == questId then
			if (prog[q.id] or 0) < q.goal then
				Progression.notify(player, "That quest is not finished yet.", "bad")
				return
			end
			if data.ClaimedQuests[questId] then return end

			data.ClaimedQuests[questId] = true

			if q.rewardCash > 0 then
				DataManager.AddCash(player, q.rewardCash)
				Progression.notify(player, ("+%d Cash from %s"):format(q.rewardCash, q.text), "good")
			end
			if q.rewardSkin ~= "" then
				if not ownsSkin(data, q.rewardSkin) then
					table.insert(data.OwnedSkins, q.rewardSkin)
				end
				data.Skin = q.rewardSkin
				Progression.applySkin(player)
			end

			-- State first, messages second: a failure below can never roll back a
			-- reward that was already granted.
			pushQuest(player, q, prog[q.id], true)
			Progression.sendSkins(player)
			sendQuests(player)
			return
		end
	end
end

--// -------------------------------------------------------------------- skins
function Progression.sendSkins(player)
	local data = DataManager.Data(player)
	if not data then return end
	Remotes.toClient(player, "SkinList", data.OwnedSkins, data.Skin)
end

function Progression.EquipSkin(player, skinId)
	local data = DataManager.Data(player)
	if not data or typeof(skinId) ~= "string" then return end
	if not GameConfig.getSkin(skinId) then return end
	if not ownsSkin(data, skinId) then
		Progression.notify(player, "You do not own that skin.", "bad")
		return
	end
	data.Skin = skinId
	Progression.applySkin(player)
	Progression.sendSkins(player)
end

-- Cash sink: "cash" skins are bought, not unlocked.
function Progression.BuySkin(player, skinId)
	local data = DataManager.Data(player)
	if not data or typeof(skinId) ~= "string" then return end
	local skin = GameConfig.getSkin(skinId)
	if not skin or skin.unlock ~= "cash" then
		Progression.notify(player, "That skin is not for sale.", "bad")
		return
	end
	if ownsSkin(data, skinId) then
		Progression.EquipSkin(player, skinId)
		return
	end

	local price = skin.req or 0
	if data.Cash < price then
		Progression.notify(player, ("Needs %d Cash (%d more)."):format(price, price - data.Cash), "bad")
		return
	end

	DataManager.AddCash(player, -price)
	table.insert(data.OwnedSkins, skinId)
	data.Skin = skinId
	Progression.applySkin(player)
	Progression.sendSkins(player)
	Progression.notify(player, ("Bought the %s skin for %d Cash!"):format(skinId, price), "good")
end

--// -------------------------------------------------------------------- zones
-- Shared by the teleport remote AND the food handler. A zone arena is walled and
-- its door is the teleport, but a gate that only checked the door would be one
-- admin command away from handing out a locked rarity tier for free.
-- A random spawn point in the hub arena. Lives here (not in Characters) so both
-- the zone remote and respawning agree on what "the arena" means.
function Progression.arenaPivot()
	local spawns = workspace:FindFirstChild("Spawns")
	local options = {}
	if spawns then
		for _, spawn in ipairs(spawns:GetChildren()) do
			if spawn:IsA("BasePart") then
				table.insert(options, spawn)
			end
		end
	end
	if #options == 0 then
		return CFrame.new(0, GameConfig.MAP.FloorY + 5, 0)
	end
	return options[math.random(1, #options)]:GetPivot()
end

-- Where a fresh cube appears: the zone the player was last standing in, if they
-- are still allowed there, otherwise a random spawn. Being thrown back to the
-- arena after every death in a far zone reads as a bug even when it is not one.
function Progression.respawnPivot(player)
	local data = DataManager.Data(player)
	local zoneId = data and tonumber(data.LastZone) or 0

	if zoneId == GameConfig.VIP.ZoneId then
		if player:GetAttribute("VIP") then
			return CFrame.new(GameConfig.VIP.Teleport)
		end
	elseif zoneId > 0 then
		local zone = GameConfig.getZone(zoneId)
		if zone and Progression.CanUseZone(player, zoneId) then
			return CFrame.new(zone.center[1], zone.topY + 4, zone.center[3])
		end
	end

	return Progression.arenaPivot()
end

function Progression.CanUseZone(player, zoneId)
	zoneId = tonumber(zoneId) or 0
	if zoneId <= 0 then return true end

	if zoneId == GameConfig.VIP.ZoneId then
		if player:GetAttribute("VIP") then return true end
		return false, "VIP gamepass required"
	end

	local zone = GameConfig.getZone(zoneId)
	if not zone then return false, "Unknown zone" end

	local reason = GameConfig.zoneLockReason(zone, sizeOf(player), DataManager.Rebirths(player))
	if reason ~= "" then return false, reason end
	return true
end

-- Shared tail for a successful teleport: start the cooldown, remember where the
-- player ended up (respawning puts them back here) and confirm to the client.
local function finishTeleport(player, zoneId)
	lastZoneTeleport[player] = os.clock()
	local data = DataManager.Data(player)
	if data then data.LastZone = zoneId end
	Remotes.toClient(player, "ZoneTeleport", zoneId, true, "")
end

function Progression.TryZoneTeleport(player, zoneId)
	if not DataManager.HasProfile(player) then return end
	zoneId = tonumber(zoneId)
	if not zoneId then return end

	-- The remote is public and PivotTo is not free: one hop per cooldown.
	local cooldown = tonumber(GameConfig.get("ZoneTeleportCooldown", 5)) or 5
	local last = lastZoneTeleport[player]
	if last and os.clock() - last < cooldown then
		Remotes.toClient(player, "ZoneTeleport", zoneId, false, "wait a moment")
		return
	end

	-- Zone 0 is "back to the arena": always allowed, no gate to check.
	if zoneId == 0 then
		local char = player.Character
		if char and char.PrimaryPart then
			char:PivotTo(Progression.arenaPivot())
		end
		finishTeleport(player, 0)
		return
	end

	-- The VIP wing is a pseudo-zone: same gate, different destination.
	if zoneId == GameConfig.VIP.ZoneId then
		local allowed, reason = Progression.CanUseZone(player, zoneId)
		if not allowed then
			Remotes.toClient(player, "ZoneTeleport", zoneId, false, reason or "")
			Progression.notify(player, reason or "Locked", "bad")
			return
		end
		local char = player.Character
		if char and char.PrimaryPart then
			char:PivotTo(CFrame.new(GameConfig.VIP.Teleport))
		end
		finishTeleport(player, zoneId)
		return
	end

	local zone = GameConfig.getZone(zoneId)
	if not zone then return end

	local allowed, reason = Progression.CanUseZone(player, zoneId)
	if not allowed then
		Remotes.toClient(player, "ZoneTeleport", zoneId, false, reason or "")
		Progression.notify(player, ("%s: %s"):format(zone.name, reason or "locked"), "bad")
		return
	end

	local char = player.Character
	if char and char.PrimaryPart then
		-- Arrive in the middle of the arena: on its floor, clear of its walls.
		char:PivotTo(CFrame.new(zone.center[1], zone.topY + 4, zone.center[3]))
	end
	finishTeleport(player, zoneId)
end

--// ------------------------------------------------------------------ rebirth
function Progression.TryRebirth(player)
	local data = DataManager.Data(player)
	if not data then return end

	-- One rebirth per second: the remote is public and this rewrites the profile.
	local now = os.clock()
	if lastRebirthRequest[player] and now - lastRebirthRequest[player] < 1 then return end
	lastRebirthRequest[player] = now

	local required = GameConfig.rebirthRequirement(data.Rebirths)
	local current = sizeOf(player)

	if current < required then
		Remotes.toClient(player, "Rebirth", data.Rebirths, data.RebirthMult, false, required)
		Progression.notify(player, ("Need Size %d to rebirth (you have %d).")
			:format(required, math.floor(current)), "bad")
		return
	end

	data.Rebirths += 1
	data.RebirthMult = GameConfig.rebirthMultiplier(data.Rebirths)
	player:SetAttribute("Rebirths", data.Rebirths)
	player:SetAttribute("RebirthMult", data.RebirthMult)

	-- Grant the cheapest rebirth skin not owned yet, so the order always matches
	-- the requirements advertised in the Skins menu.
	local rebirthSkins = {}
	for _, s in ipairs(GameConfig.SKINS) do
		if s.unlock == "rebirth" then table.insert(rebirthSkins, s) end
	end
	table.sort(rebirthSkins, function(a, b) return (a.req or 0) < (b.req or 0) end)

	local newSkin
	for _, s in ipairs(rebirthSkins) do
		if not ownsSkin(data, s.id) then newSkin = s.id break end
	end
	if newSkin then
		table.insert(data.OwnedSkins, newSkin)
		data.Skin = newSkin
	end

	local cashReward = GameConfig.rebirthCashReward(data.Rebirths)
	if cashReward > 0 then
		DataManager.AddCash(player, cashReward)
	end

	local ls = player:FindFirstChild("leaderstats")
	local size = ls and ls:FindFirstChild("Size")
	if size then size.Value = 0 end

	-- Reset size-linked quest progress so those quests can be re-earned, but only
	-- while they are still unclaimed.
	local prog = Progress[player]
	if prog then
		for _, q in ipairs(GameConfig.QUESTS) do
			if q.type == "size" and not data.ClaimedQuests[q.id] then
				prog[q.id] = 0
				data.Quests[q.id] = 0
			end
		end
	end

	Progression.refreshVisuals(player)
	Progression.applyRankText(player)
	Progression.AddProgress(player, "rebirth", 1)

	Remotes.toClient(player, "Rebirth", data.Rebirths, data.RebirthMult, true,
		GameConfig.rebirthRequirement(data.Rebirths))
	Progression.sendSkins(player)
	sendQuests(player)

	local message = ("Rebirth %d! Size multiplier x%.2f"):format(data.Rebirths, data.RebirthMult)
	if newSkin then message ..= ("   +   %s skin"):format(newSkin) end
	if cashReward > 0 then message ..= ("   +   %d Cash"):format(cashReward) end
	Progression.notify(player, message, "good")
end

--// ---------------------------------------------------------------- lifecycle
function Progression.InitPlayer(player)
	local data = DataManager.Data(player)
	if not data then return end

	if #data.OwnedSkins == 0 then
		table.insert(data.OwnedSkins, GameConfig.SKINS[1].id)
	end

	-- Daily reset (UTC day).
	local today = dayStamp()
	if data.QuestDay ~= today then
		data.Quests = {}
		data.ClaimedQuests = {}
		data.QuestDay = today
	end

	-- Mirrored onto the player so the client can evaluate zone gates and draw the
	-- rebirth HUD without a remote round trip.
	player:SetAttribute("Rebirths", data.Rebirths or 0)
	player:SetAttribute("RebirthMult", data.RebirthMult or 1)

	local prog = {}
	for _, q in ipairs(GameConfig.QUESTS) do
		prog[q.id] = data.Quests[q.id] or 0
	end
	Progress[player] = prog

	-- Re-check milestones already passed (e.g. skins added in an update).
	Progression.CheckSize(player)
	Progression.refreshVisuals(player)
	Progression.applyRankText(player)

	Progression.sendSkins(player)
	sendQuests(player)
	Leaderboards.Send(player)

	-- Restore playtime gift claims so the HUD does not offer them again.
	local highestGift = 0
	for id in pairs(data.Gifts or {}) do
		local n = tonumber(id)
		if n and n > highestGift then highestGift = n end
	end
	player:SetAttribute("CurrentGift", highestGift)

	Remotes.toClient(player, "Rebirth", data.Rebirths, data.RebirthMult, false,
		GameConfig.rebirthRequirement(data.Rebirths))
end

function Progression.PlayerRemoving(player)
	local data = DataManager.Data(player)
	local prog = Progress[player]
	if data and prog then
		data.Quests = prog
	end
	Progress[player] = nil
	lastRebirthRequest[player] = nil
	lastZoneTeleport[player] = nil
	Leaderboards.PlayerRemoving(player)
end

function Progression.Init()
	-- Runs while the profile is still writable, before DataManager releases it.
	DataManager.RegisterPreRelease(function(player)
		Progression.PlayerRemoving(player)
		local ok, err = pcall(Leaderboards.Update, player)
		if not ok then warn("[Progression] final leaderboard write failed: " .. tostring(err)) end
	end)

	Remotes.onServer("Rebirth", function(player) Progression.TryRebirth(player) end)
	Remotes.onServer("EquipSkin", function(player, skinId) Progression.EquipSkin(player, skinId) end)
	Remotes.onServer("BuySkin", function(player, skinId) Progression.BuySkin(player, skinId) end)
	Remotes.onServer("QuestFetch", function(player) sendQuests(player) end)
	Remotes.onServer("QuestClaim", function(player, questId) Progression.ClaimQuest(player, questId) end)
	Remotes.onServer("QuestClaimAll", function(player)
		Remotes.toClient(player, "QuestClaimAll", Progression.ClaimAllQuests(player))
	end)
	Remotes.onServer("ZoneTeleport", function(player, zoneId) Progression.TryZoneTeleport(player, zoneId) end)
end

return Progression
