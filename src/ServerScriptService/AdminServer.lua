-- Cmdr-style admin console (group-gated). (ModuleScript; call AdminServer.Init() from Game.)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Events = ReplicatedStorage.Events

local Config = require(ReplicatedStorage.Modules.ProgressionConfig)
local Manager = require(script.Parent.Data.Manager)
local Progression = require(script.Parent.Progression)

local GROUP = 34195654
local godConnections = {}

local function findPlayer(name)
	if not name then return nil end
	name = name:lower()
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name:lower():sub(1, #name) == name then return p end
	end
	return nil
end

local function setGod(player, on)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChild("Humanoid")
	if not hum then return end
	if on then
		hum.Health = hum.MaxHealth
		if not godConnections[player] then
			godConnections[player] = hum.HealthChanged:Connect(function(h)
				if h < hum.MaxHealth then hum.Health = hum.MaxHealth end
			end)
		end
	else
		if godConnections[player] then godConnections[player]:Disconnect(); godConnections[player] = nil end
	end
end

local function setNoclip(player, on)
	if not player.Character then return end
	for _, p in ipairs(player.Character:GetDescendants()) do
		if p:IsA("BasePart") then p.CanCollide = not on end
	end
end

local function handle(player, cmd)
	local args = {}
	for w in string.gmatch(cmd or "", "[^%s]+") do table.insert(args, w) end
	-- convenience shorthand
	if #args >= 2 and args[2] == "me" then args[2] = player.Name end
	if #args >= 3 and args[3] == "me" then args[3] = player.Name end
	local action = args[1]

	if action == "givecash" then
		local t = findPlayer(args[2]); local amt = tonumber(args[3]) or 0
		if t and Manager.Profiles[t] then
			Manager.Profiles[t].Data.Cash = Manager.Profiles[t].Data.Cash + amt
			t.leaderstats.Cash.Value = Manager.Profiles[t].Data.Cash
		end
	elseif action == "size" then
		local t = findPlayer(args[2]); local amt = tonumber(args[3]) or 0
		if t and t.leaderstats then
			t.leaderstats.Size.Value = amt
			Progression.setCubeSize(t.Character, Config.visualSize(amt))
		end
	elseif action == "rebirth" then
		Progression.TryRebirth(args[2] and findPlayer(args[2]) or player)
	elseif action == "kill" then
		local t = findPlayer(args[2])
		if t and t.Character then
			local hum = t.Character:FindFirstChild("Humanoid")
			if hum then hum.Health = 0 end
		end
	elseif action == "tp" then
		local t = findPlayer(args[2]); local t2 = findPlayer(args[3])
		if t and t2 and t.Character and t2.Character and t2.Character.PrimaryPart then
			t.Character:PivotTo(t2.Character.PrimaryPart.CFrame)
		end
	elseif action == "bring" then
		local t = findPlayer(args[2])
		if t and t.Character and player.Character and player.Character.PrimaryPart then
			t.Character:PivotTo(player.Character.PrimaryPart.CFrame)
		end
	elseif action == "skin" then
		Progression.EquipSkin(args[2] and findPlayer(args[2]) or player, args[3])
	elseif action == "god" then
		setGod(player, not godConnections[player])
	elseif action == "noclip" then
		local on = not player:GetAttribute("Noclip")
		setNoclip(player, on)
		player:SetAttribute("Noclip", on)
	elseif action == "heal" then
		if player.Character then
			local hum = player.Character:FindFirstChild("Humanoid")
			if hum then hum.Health = hum.MaxHealth end
		end
	elseif action == "clearspawn" then
		for _, f in ipairs(workspace.FoodParts:GetChildren()) do
			if CollectionService:HasTag(f, "Food") then f:Destroy() end
		end
	elseif action == "zone" then
		Progression.TryZoneTeleport(args[2] and findPlayer(args[2]) or player, tonumber(args[3]) or 1)
	else
		Events.Admin:FireClient(player, "Unknown command: " .. tostring(action))
		return
	end
	Events.Admin:FireClient(player, "> " .. cmd)
end

function AdminServer.Init()
	Events.Admin.OnServerEvent:Connect(function(player, cmd)
		if not player:IsInGroup(GROUP) then
			Events.Admin:FireClient(player, "No permission (need group).")
			return
		end
		handle(player, cmd)
	end)
end

return AdminServer
