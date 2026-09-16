-- Admin console. Access is by UserId (GameData/Admins) with group rank 250+ as a
-- fallback, every command is pcall-wrapped, and each one answers through
-- Events.Admin so the client console can print a transcript.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Progression = require(script.Parent:WaitForChild("Progression"))
local Characters = require(script.Parent:WaitForChild("Characters"))
local Food = require(script.Parent:WaitForChild("Food"))

local Admin = {}

local godConnections = {}
local noclipConnections = {}

local function say(player, text)
	Remotes.toClient(player, "Admin", tostring(text))
end

local function findPlayer(name)
	if typeof(name) ~= "string" or name == "" then return nil end
	name = name:lower()
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name:lower() == name then return p end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name:lower():sub(1, #name) == name then return p end
	end
	return nil
end

local function resolve(player, name)
	if name == nil or name == "me" then return player end
	return findPlayer(name)
end

local function humanoidOf(player)
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function setGod(player, on)
	local humanoid = humanoidOf(player)
	if not humanoid then return false end
	if on then
		humanoid.Health = humanoid.MaxHealth
		if not godConnections[player] then
			godConnections[player] = humanoid.HealthChanged:Connect(function(health)
				if health < humanoid.MaxHealth then humanoid.Health = humanoid.MaxHealth end
			end)
		end
	elseif godConnections[player] then
		godConnections[player]:Disconnect()
		godConnections[player] = nil
	end
	return true
end

-- A one-shot CanCollide = false does not survive: collision flags are rewritten
-- as the character moves, so noclip has to be held every physics step.
local function setNoclip(player, on)
	player:SetAttribute("Noclip", on)
	if on then
		if noclipConnections[player] then return end
		noclipConnections[player] = RunService.Stepped:Connect(function()
			local char = player.Character
			if not char then return end
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide then
					part.CanCollide = false
				end
			end
		end)
	else
		if noclipConnections[player] then
			noclipConnections[player]:Disconnect()
			noclipConnections[player] = nil
		end
		local char = player.Character
		if char then
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") then part.CanCollide = true end
			end
		end
	end
end

local HELP = table.concat({
	"help - this list",
	"givecash <player> <amount>   size <player> <amount>",
	"rebirth <player>             skin <player> <skinId>",
	"kill <player>   heal   respawn <player>",
	"tp <player> <player>   bring <player>   zone <player> <zoneId>",
	"god   noclip",
	"food - live cubes per region   clearfood - destroy them (they regrow)",
	"say <message> - broadcast to every player",
}, "\n")

local commands = {
	help = function(player)
		say(player, HELP)
	end,

	givecash = function(player, args)
		local target = resolve(player, args[2])
		if not target or not DataManager.HasProfile(target) then return "no such player/data" end
		local amount = tonumber(args[3]) or 0
		DataManager.AddCash(target, amount)
		return ("gave %s %d cash"):format(target.Name, amount)
	end,

	size = function(player, args)
		local target = resolve(player, args[2])
		if not target then return "no such player" end
		local ls = target:FindFirstChild("leaderstats")
		local size = ls and ls:FindFirstChild("Size")
		if not size then return "target has no Size stat yet" end
		size.Value = math.max(0, tonumber(args[3]) or 0)
		return ("%s size set to %d"):format(target.Name, size.Value)
	end,

	rebirth = function(player, args)
		local target = resolve(player, args[2])
		if not target then return "no such player" end
		Progression.TryRebirth(target)
		return "rebirth attempted for " .. target.Name
	end,

	kill = function(player, args)
		local target = resolve(player, args[2])
		local humanoid = target and humanoidOf(target)
		if not humanoid then return "no such player" end
		humanoid.Health = 0
		return "killed " .. target.Name
	end,

	heal = function(player)
		local humanoid = humanoidOf(player)
		if not humanoid then return "no character" end
		humanoid.Health = humanoid.MaxHealth
		return "healed"
	end,

	respawn = function(player, args)
		local target = resolve(player, args[2])
		if not target then return "no such player" end
		-- Admin respawn ignores the "must be dead" rule on purpose.
		Characters.spawnCharacter(target, false)
		return "respawned " .. target.Name
	end,

	tp = function(player, args)
		local a, b = resolve(player, args[2]), resolve(player, args[3])
		if not a or not b then return "usage: tp <player> <player>" end
		local charA, charB = a.Character, b.Character
		if not charA or not charB or not charB.PrimaryPart then return "missing character" end
		charA:PivotTo(charB.PrimaryPart.CFrame + Vector3.new(0, 6, 0))
		return ("teleported %s to %s"):format(a.Name, b.Name)
	end,

	bring = function(player, args)
		local target = resolve(player, args[2])
		if not target then return "no such player" end
		local charT, charP = target.Character, player.Character
		if not charT or not charP or not charP.PrimaryPart then return "missing character" end
		charT:PivotTo(charP.PrimaryPart.CFrame + Vector3.new(0, 6, 0))
		return "brought " .. target.Name
	end,

	zone = function(player, args)
		local target = resolve(player, args[2])
		if not target then return "no such player" end
		local zoneId = tonumber(args[3]) or 1
		Progression.TryZoneTeleport(target, zoneId)
		return ("zone teleport %d for %s"):format(zoneId, target.Name)
	end,

	skin = function(player, args)
		local target = resolve(player, args[2])
		if not target then return "no such player" end
		local skinId = args[3]
		if not GameConfig.getSkin(skinId) then return "unknown skin: " .. tostring(skinId) end
		local data = DataManager.Data(target)
		if not data then return "no data" end
		if not table.find(data.OwnedSkins or {}, skinId) then
			table.insert(data.OwnedSkins, skinId)
		end
		Progression.EquipSkin(target, skinId)
		return ("%s now wears %s"):format(target.Name, skinId)
	end,

	god = function(player)
		local on = godConnections[player] == nil
		if not setGod(player, on) then return "no character" end
		return on and "god on" or "god off"
	end,

	noclip = function(player)
		local on = not player:GetAttribute("Noclip")
		setNoclip(player, on)
		return on and "noclip on" or "noclip off"
	end,

	food = function(player)
		local counts, total = {}, 0
		for _, part in ipairs(CollectionService:GetTagged("Food")) do
			local zone = tostring(part:GetAttribute("Zone") or 0)
			counts[zone] = (counts[zone] or 0) + 1
			total += 1
		end
		local lines = {}
		for zone, n in pairs(counts) do
			table.insert(lines, ("zone %s: %d"):format(zone, n))
		end
		table.sort(lines)
		say(player, ("food: %d live | %s | targets %s")
			:format(total, table.concat(lines, ", "), Food.Stats()))
	end,

	clearfood = function()
		local n = Food.Count()
		Food.Clear()
		return ("destroyed %d cubes (they regrow automatically)"):format(n)
	end,

	say = function(player, args)
		local message = table.concat(args, " ", 2)
		if message == "" then return "usage: say <message>" end
		Remotes.toAllClients("Notify", "[ADMIN] " .. message, "info")
		return "broadcast sent"
	end,
}

local function handle(player, cmd)
	local args = {}
	for word in string.gmatch(cmd or "", "%S+") do
		table.insert(args, word)
	end
	local action = args[1] and args[1]:lower()
	if not action or action == "" then return end

	if args[2] == "me" then args[2] = player.Name end

	local fn = commands[action]
	if not fn then
		say(player, ("Unknown command: %s (type 'help')"):format(tostring(action)))
		return
	end

	local ok, result = pcall(fn, player, args)
	if not ok then
		say(player, ("Error in '%s': %s"):format(action, tostring(result)))
		return
	end
	if result ~= nil then say(player, "> " .. tostring(result)) end
end

function Admin.Init()
	Remotes.onServer("Admin", function(player, cmd)
		if not GameConfig.isAdmin(player.UserId, player) then
			say(player, "No permission: your UserId is not in GameData/Admins.")
			return
		end
		handle(player, typeof(cmd) == "string" and cmd or "")
	end)

	Players.PlayerRemoving:Connect(function(player)
		if godConnections[player] then
			godConnections[player]:Disconnect()
			godConnections[player] = nil
		end
		if noclipConnections[player] then
			noclipConnections[player]:Disconnect()
			noclipConnections[player] = nil
		end
	end)
end

return Admin
