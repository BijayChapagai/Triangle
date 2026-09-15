local Progression = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Modules.ProgressionConfig)
local Manager = require(script.Parent.Data.Manager)
local Events = ReplicatedStorage.Events

local SizeLB = DataStoreService:GetOrderedDataStore("CubeLB_Size")
local CashLB = DataStoreService:GetOrderedDataStore("CubeLB_Cash")

local Progress = {}     -- [player] = { questId = progress }
local sizeTweens = {}   -- [character] = Tween

local function dayStamp()
	return math.floor(os.time() / 86400)
end

function Progression.setCubeSize(character, target)
	if not character or not character.PrimaryPart then return end
	local pp = character.PrimaryPart
	local v = math.clamp(target, 0.4, 220)
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if sizeTweens[character] then sizeTweens[character]:Cancel() end
	local t = TweenService:Create(pp, info, { Size = Vector3.new(v, v, v) })
	sizeTweens[character] = t
	t.Completed:Connect(function()
		if sizeTweens[character] == t then sizeTweens[character] = nil end
	end)
	t:Play()
end

function Progression.applySkin(player)
	local profile = Manager.Profiles[player]
	if not profile then return end
	local char = player.Character
	if not char or not char.PrimaryPart then return end
	local skinId = profile.Data.Skin or "Default"
	for _, s in ipairs(Config.SKINS) do
		if s.id == skinId then
			char.PrimaryPart.Color = Config.color3(s.color)
			return
		end
	end
end

local function sendQuests(player)
	local prog = Progress[player] or {}
	local claimed = (Manager.Profiles[player] and Manager.Profiles[player].Data.ClaimedQuests) or {}
	local payload = {}
	for _, q in ipairs(Config.QUESTS) do
		table.insert(payload, {
			id = q.id, text = q.text, goal = q.goal,
			progress = prog[q.id] or 0,
			claimed = claimed[q.id] or false,
		})
	end
	Events.QuestUpdate:FireClient(player, payload)
end
Progression.sendQuests = sendQuests

local function sendLeaderboard(player)
	local lists = { Size = {}, Cash = {} }
	local ok1, pages1 = pcall(function() return SizeLB:GetSortedAsync(false, 50) end)
	if ok1 and pages1 then
		for _, e in ipairs(pages1:GetCurrentPage()) do
			local nm = "??"
			local ok, p = pcall(function() return Players:GetNameFromUserIdAsync(tonumber(e.key)) end)
			if ok then nm = p end
			table.insert(lists.Size, { name = nm, value = e.value })
		end
	end
	local ok2, pages2 = pcall(function() return CashLB:GetSortedAsync(false, 50) end)
	if ok2 and pages2 then
		for _, e in ipairs(pages2:GetCurrentPage()) do
			local nm = "??"
			local ok, p = pcall(function() return Players:GetNameFromUserIdAsync(tonumber(e.key)) end)
			if ok then nm = p end
			table.insert(lists.Cash, { name = nm, value = e.value })
		end
	end
	Events.Leaderboard:FireClient(player, lists)
end
Progression.sendLeaderboard = sendLeaderboard

function Progression.updateLeaderboard(player)
	local profile = Manager.Profiles[player]
	if not profile or not player.leaderstats then return end
	pcall(function() SizeLB:SetAsync(tostring(player.UserId), math.floor(player.leaderstats.Size.Value)) end)
	pcall(function() CashLB:SetAsync(tostring(player.UserId), math.floor(profile.Data.Cash)) end)
end

function Progression.InitPlayer(player)
	local profile = Manager.Profiles[player]
	if not profile then return end
	local data = profile.Data
	local today = dayStamp()
	if data.QuestDay ~= today then
		data.Quests = {}
		data.ClaimedQuests = {}
		data.QuestDay = today
	end
	Progress[player] = {}
	for _, q in ipairs(Config.QUESTS) do
		Progress[player][q.id] = data.Quests[q.id] or 0
	end
	Events.SkinList:FireClient(player, data.OwnedSkins, data.Skin)
	sendQuests(player)
	sendLeaderboard(player)
end

function Progression.PlayerRemoving(player)
	local profile = Manager.Profiles[player]
	if profile and Progress[player] then
		profile.Data.Quests = Progress[player]
	end
	Progress[player] = nil
end

function Progression.AddProgress(player, qtype, amount)
	local profile = Manager.Profiles[player]
	if not profile then return end
	local prog = Progress[player]
	if not prog then return end
	for _, q in ipairs(Config.QUESTS) do
		if q.type == qtype and (q.goal or 0) > 0 then
			local cur = prog[q.id] or 0
			if cur < q.goal then
				cur = math.min(q.goal, cur + amount)
				prog[q.id] = cur
				profile.Data.Quests[q.id] = cur
				Events.QuestUpdate:FireClient(player, q.id, cur, cur >= q.goal, false)
			end
		end
	end
end

function Progression.CheckSize(player)
	local profile = Manager.Profiles[player]
	if not profile or not player.leaderstats then return end
	local sz = player.leaderstats.Size.Value
	local prog = Progress[player]
	if not prog then return end
	for _, q in ipairs(Config.QUESTS) do
		if q.type == "size" then
			local cur = math.min(sz, q.goal)
			if (prog[q.id] or 0) < cur then
				prog[q.id] = cur
				profile.Data.Quests[q.id] = cur
				Events.QuestUpdate:FireClient(player, q.id, cur, cur >= q.goal, false)
			end
		end
	end
end

function Progression.ClaimQuest(player, questId)
	local profile = Manager.Profiles[player]
	if not profile then return end
	local prog = Progress[player]
	if not prog then return end
	local data = profile.Data
	data.ClaimedQuests = data.ClaimedQuests or {}
	for _, q in ipairs(Config.QUESTS) do
		if q.id == questId then
			if (prog[q.id] or 0) < (q.goal or 1) then return end
			if data.ClaimedQuests[questId] then return end
			data.ClaimedQuests[questId] = true
			if q.rewardCash and q.rewardCash > 0 then
				profile.Data.Cash = profile.Data.Cash + q.rewardCash
				player.leaderstats.Cash.Value = profile.Data.Cash
			end
			if q.rewardSkin then
				local owned = data.OwnedSkins
				local has = false
				for _, s in ipairs(owned) do if s == q.rewardSkin then has = true end end
				if not has then table.insert(owned, q.rewardSkin) end
				data.Skin = q.rewardSkin
				Progression.applySkin(player)
			end
			Events.QuestUpdate:FireClient(player, questId, prog[q.id], true, true)
			Events.SkinList:FireClient(player, data.OwnedSkins, data.Skin)
			return
		end
	end
end

function Progression.EquipSkin(player, skinId)
	local profile = Manager.Profiles[player]
	if not profile then return end
	local owned = profile.Data.OwnedSkins
	local ok = false
	for _, s in ipairs(owned) do if s == skinId then ok = true end end
	if not ok then return end
	profile.Data.Skin = skinId
	Progression.applySkin(player)
	Events.SkinList:FireClient(player, owned, skinId)
end

function Progression.TryRebirth(player)
	local profile = Manager.Profiles[player]
	if not profile then return end
	local data = profile.Data
	local req = Config.rebirthRequirement(data.Rebirths)
	local cur = (player.leaderstats and player.leaderstats.Size.Value) or 0
	if cur < req then
		Events.Rebirth:FireClient(player, data.Rebirths, data.RebirthMult, false, req)
		return
	end
	data.Rebirths = data.Rebirths + 1
	data.RebirthMult = Config.rebirthMultiplier(data.Rebirths)
	local rebirthSkins = {}
	for _, s in ipairs(Config.SKINS) do if s.unlock == "rebirth" then table.insert(rebirthSkins, s.id) end end
	local newSkin = rebirthSkins[((data.Rebirths - 1) % #rebirthSkins) + 1]
	local has = false
	for _, s in ipairs(data.OwnedSkins) do if s == newSkin then has = true end end
	if not has then table.insert(data.OwnedSkins, newSkin) end
	data.Skin = newSkin
	if player.leaderstats then player.leaderstats.Size.Value = 0 end
	Progression.setCubeSize(player.Character, Config.visualSize(0))
	Progression.applySkin(player)
	Progression.AddProgress(player, "rebirth", 1)
	Events.Rebirth:FireClient(player, data.Rebirths, data.RebirthMult, true, req)
	Events.SkinList:FireClient(player, data.OwnedSkins, newSkin)
end

function Progression.TryZoneTeleport(player, zoneId)
	local profile = Manager.Profiles[player]
	if not profile then return end
	local zone
	for _, z in ipairs(Config.ZONES) do if z.id == zoneId then zone = z end end
	if not zone then return end
	local ok = true
	local reason = ""
	if zone.req.size and (player.leaderstats.Size.Value or 0) < zone.req.size then
		ok = false; reason = "Need Size " .. zone.req.size
	end
	if zone.req.rebirth and (profile.Data.Rebirths or 0) < zone.req.rebirth then
		ok = false; reason = "Need " .. zone.req.rebirth .. " Rebirths"
	end
	if not ok then
		Events.ZoneTeleport:FireClient(player, zoneId, false, reason)
		return
	end
	if player.Character and player.Character.PrimaryPart then
		local c = zone.center
		player.Character:PivotTo(CFrame.new(c[1], 4, c[3]))
	end
	Events.ZoneTeleport:FireClient(player, zoneId, true, "")
end

return Progression
