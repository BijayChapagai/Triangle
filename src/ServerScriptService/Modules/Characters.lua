-- Characters: spawning, the per-character wiring, eating and kills.
--
-- Everything that has to happen to a cube (name tag, skin, size, touch rules,
-- death cleanup, gamepass walkspeed) lives in bindCharacter, so all three ways a
-- cube can appear -- first join, free respawn and paid revive -- get identical
-- treatment. Previously each path wired a different subset, which is why a
-- revived player became immortal-but-harmless and a respawned one silently lost
-- their x2 Speed pass.
local Characters = {}

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Progression = require(script.Parent:WaitForChild("Progression"))

local CharacterTemplate = ServerStorage:WaitForChild("Character")
local SpawnsFolder = workspace:WaitForChild("Spawns")

-- Per-player runtime state that must not leak across respawns or leaves.
local bindings = {}         -- [player] = { touched, died, sizeChanged }
local autoFarmThreads = {}  -- [player] = true while the loop is alive
local autoFarmEnabled = {}  -- [player] = bool
local lastRespawn = {}      -- [player] = os.clock()
local protectTokens = {}    -- [player] = spawn protection generation

--// ------------------------------------------------------------------ helpers
local function getSizeObject(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Size")
end

local function sizeOf(player)
	local size = getSizeObject(player)
	return size and size.Value or 0
end
Characters.sizeOf = sizeOf

local function pickSpawn()
	local options = {}
	for _, spawn in ipairs(SpawnsFolder:GetChildren()) do
		if spawn:IsA("BasePart") then
			table.insert(options, spawn)
		end
	end
	if #options == 0 then return CFrame.new(0, 5, 0) end
	return options[math.random(1, #options)]:GetPivot()
end

-- WalkSpeed lives in StarterPlayer (an asset property), never in code: the x2
-- Speed pass doubles whatever the place says the base speed is.
local function targetWalkSpeed(player)
	local base = tonumber(StarterPlayer.CharacterWalkSpeed) or 16
	if player:GetAttribute("2xSpeed") then base *= 2 end
	return base
end

-- Spawn protection, in both directions: a protected cube cannot be eaten and
-- cannot eat anybody, so it is never a free aggression window. It stops spawn
-- camping from being a strategy and stops a player who just paid to respawn from
-- being deleted again before they can move.
-- An attribute rather than a local so the client can show it and Admin can read it.
local function protect(player, seconds)
	seconds = tonumber(seconds) or 0
	local token = (protectTokens[player] or 0) + 1
	protectTokens[player] = token
	if seconds <= 0 then
		player:SetAttribute("SpawnProtected", false)
		return
	end
	player:SetAttribute("SpawnProtected", true)
	task.delay(seconds, function()
		-- Only the newest spawn may clear it: respawning twice inside one window
		-- must not end the second window early.
		if protectTokens[player] == token then
			player:SetAttribute("SpawnProtected", false)
		end
	end)
end

local function disconnectAll(player)
	local b = bindings[player]
	if not b then return end
	for _, conn in pairs(b) do
		if typeof(conn) == "RBXScriptConnection" and conn.Connected then
			conn:Disconnect()
		end
	end
	bindings[player] = nil
end

--// ---------------------------------------------------------------- character
local function newCharacter()
	local model = CharacterTemplate:Clone()

	-- PrimaryPart is set in the place file, but a Clone of a Model keeps it; the
	-- explicit fallback means a future edit to the template cannot break spawning.
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
	end

	local root = model.PrimaryPart
	if root then
		-- Colour comes from the equipped skin, not a random roll: with a skin
		-- system a random colour just gets overwritten a frame later.
		root.Transparency = 0
		root.CanCollide = true
		root.CanTouch = true
		root.Anchored = false
	end

	local highlight = model:FindFirstChildOfClass("Highlight")
	if highlight then highlight.Enabled = true end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth

		-- Hygiene. A cube is one part with a welded root, so the avatar states
		-- below can only produce weird physics (climbing a wall, sitting in
		-- mid-air, ragdolling on death), and the built-in name tag would double
		-- up with PlayerDisplay.
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.BreakJointsOnDeath = false -- keep the weld, and the death tween, intact
		for _, state in ipairs({
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.PlatformStanding,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.Seated,
			Enum.HumanoidStateType.Swimming,
		}) do
			humanoid:SetStateEnabled(state, false)
		end
	end

	-- StarterCharacterScripts are copied manually because this game assigns
	-- player.Character itself instead of using the built-in spawn flow.
	local starterScripts = game:GetService("StarterPlayer"):FindFirstChild("StarterCharacterScripts")
	if starterScripts then
		for _, object in ipairs(starterScripts:GetChildren()) do
			object:Clone().Parent = model
		end
	end

	return model
end

-- Wire every per-character behaviour. Safe to call repeatedly: the previous
-- connections are dropped first, so respawning N times no longer leaves N copies
-- of the Size.Changed / Touched handlers running.
local function bindCharacter(player, model)
	disconnectAll(player)

	local b = {}
	bindings[player] = b

	local root = model.PrimaryPart
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local display = model:FindFirstChild("PlayerDisplay")

	model.Name = player.Name

	-- Name tag: never set on first join before, so everyone read "@NAME".
	if display then
		local nameLabel = display:FindFirstChild("PlayerName")
		if nameLabel then nameLabel.Text = "@" .. player.Name end
	end
	Progression.applyRankText(player)

	-- Walkspeed comes from the place and has to be re-applied to every new
	-- character, x2 Speed pass included.
	if humanoid then
		humanoid.WalkSpeed = targetWalkSpeed(player)
	end

	-- Death: hide the cube AND stop it interacting with the world. An invisible
	-- corpse that kept its Touched connection used to kill living players who
	-- walked over it, and bank kill-quest progress for someone already dead.
	if humanoid then
		b.died = humanoid.Died:Connect(function()
			player:SetAttribute("Dead", true)
			if root then
				root.Transparency = 1
				root.CanCollide = false
				root.CanTouch = false
				root.Anchored = true
			end
			if b.touched and b.touched.Connected then
				b.touched:Disconnect()
				b.touched = nil
			end
			local highlight = model:FindFirstChildOfClass("Highlight")
			if highlight then highlight.Enabled = false end
		end)
	end

	-- Touch rules: the bigger cube eats the smaller one.
	if root then
		b.touched = root.Touched:Connect(function(other)
			if not other or not other.Parent then return end
			local otherPlayer = Players:GetPlayerFromCharacter(other.Parent)
			if not otherPlayer or otherPlayer == player then return end

			-- Both sides need loaded data: touching during the load window is a
			-- no-op instead of an "index nil with Size" error.
			if not DataManager.HasProfile(player) or not DataManager.HasProfile(otherPlayer) then return end
			if player:GetAttribute("Dead") or otherPlayer:GetAttribute("Dead") then return end
			if player:GetAttribute("SpawnProtected") or otherPlayer:GetAttribute("SpawnProtected") then
				return
			end

			local otherCharacter = otherPlayer.Character
			if not otherCharacter then return end
			local otherRoot = otherCharacter.PrimaryPart
			local otherHumanoid = otherCharacter:FindFirstChildOfClass("Humanoid")
			if not otherRoot or not otherHumanoid or otherHumanoid.Health <= 0 then return end
			if otherRoot.CanTouch == false then return end

			local mySize = sizeOf(player)
			local theirSize = sizeOf(otherPlayer)

			-- Both Touched handlers fire in the same frame. On a tie, resolve by
			-- UserId so two cubes cannot kill each other simultaneously.
			if mySize == theirSize then
				if player.UserId < otherPlayer.UserId then
					Characters.OnKill(player, otherPlayer)
				end
				return
			end
			if theirSize > mySize then
				return -- we are the snack; the other handler lands the kill
			end

			Characters.OnKill(player, otherPlayer)
		end)
	end

	-- Size changes drive the rank text, the quests and the visual cube.
	-- leaderstats may not exist yet at first join, so hook it up asynchronously
	-- rather than losing the connection for the whole session.
	local function hookSize(size)
		if bindings[player] ~= b then return end -- superseded by a newer bind
		b.sizeChanged = size.Changed:Connect(function()
			Progression.applyRankText(player)
			Progression.CheckSize(player)
			Progression.setCubeSize(player.Character, GameConfig.visualSize(size.Value))
		end)
		Progression.applyRankText(player)
		Progression.CheckSize(player)
		Progression.setCubeSize(player.Character, GameConfig.visualSize(size.Value))
	end

	local size = getSizeObject(player)
	if size then
		hookSize(size)
	else
		task.spawn(function()
			local ls = player:WaitForChild("leaderstats", 60)
			local value = ls and ls:WaitForChild("Size", 10)
			if value then hookSize(value) end
		end)
	end

	player:SetAttribute("Dead", humanoid ~= nil and humanoid.Health <= 0)

	-- Slow re-assert. The character is client-owned, so a modified client can
	-- change its own WalkSpeed or resize its own cube. Neither can win a fight
	-- (kills compare server-side leaderstats.Size), but a bigger hitbox sweeps up
	-- more food per second and a faster cube makes the x2 Speed pass worthless.
	-- One pass every couple of seconds costs nothing and closes both.
	local interval = tonumber(GameConfig.get("HeartbeatInterval", 2)) or 2
	task.spawn(function()
		while bindings[player] == b do
			task.wait(interval)
			if bindings[player] ~= b or not player.Parent then break end
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				local want = targetWalkSpeed(player)
				if hum.WalkSpeed ~= want then hum.WalkSpeed = want end
			end
			Progression.assertCubeSize(model, GameConfig.visualSize(sizeOf(player)))
		end
	end)
end
Characters.bindCharacter = bindCharacter

--// --------------------------------------------------------------------- kill
-- force bypasses spawn protection, which is how the KillAll product reaches a
-- player who respawned a moment ago. Every other guard still applies.
function Characters.OnKill(killer, victim, force)
	if not killer or not victim or killer == victim then return end
	if not force then
		if victim:GetAttribute("SpawnProtected") or killer:GetAttribute("SpawnProtected") then
			return
		end
	end
	local victimCharacter = victim.Character
	if not victimCharacter then return end
	local victimHumanoid = victimCharacter:FindFirstChildOfClass("Humanoid")
	if not victimHumanoid or victimHumanoid.Health <= 0 then return end
	if victim:GetAttribute("Dead") then return end

	victim:SetAttribute("Killer", killer.UserId)
	victimHumanoid.Health = 0

	-- Reward: absorb part of their size plus a flat cash bonus. The victim resets
	-- to 0 on respawn either way, so this rewards the winner without punishing
	-- the loser twice.
	local transfer = tonumber(GameConfig.get("KillSizeTransfer", 0.1)) or 0.1
	local cap = tonumber(GameConfig.get("KillSizeCap", 25000)) or 25000
	local absorbed = math.min(cap, sizeOf(victim) * transfer)

	local killerSize = getSizeObject(killer)
	if killerSize and absorbed > 0 then
		killerSize.Value += absorbed
	end

	DataManager.AddCash(killer, tonumber(GameConfig.get("KillCash", 25)) or 25)
	DataManager.AddStat(killer, "Kills", 1)
	Progression.AddProgress(killer, "kill", 1)

	Progression.notify(killer, absorbed > 0
		and ("Ate %s   +   %d Size"):format(victim.Name, math.floor(absorbed))
		or ("Ate %s"):format(victim.Name), "good")
end

--// ------------------------------------------------------------------- spawning
local function spawnCharacter(player, keepSize)
	local oldModel = player.Character
	local model = newCharacter()

	player.Character = model
	model.Parent = workspace
	model:PivotTo(pickSpawn())

	-- Ownership is assigned explicitly: with auto-assignment a freshly spawned
	-- cube can end up server-owned (rubber-banding for its own player) when
	-- somebody else happens to be nearest.
	local root = model.PrimaryPart
	if root then
		if not pcall(function() root:SetNetworkOwner(player) end) then
			pcall(function() root:SetNetworkOwnershipAuto() end)
		end
	end

	protect(player, GameConfig.get("SpawnProtection", 3))

	if not keepSize then
		-- Reset BEFORE the visuals are applied, otherwise the fresh cube is drawn
		-- at the size the player died with while their Size stat reads 0.
		local size = getSizeObject(player)
		if size then size.Value = 0 end
	end

	bindCharacter(player, model)
	Progression.applySkin(player)
	Progression.setCubeSize(model, GameConfig.visualSize(sizeOf(player)))

	if oldModel and oldModel ~= model and oldModel.Parent then
		oldModel:Destroy()
	end

	return model
end
Characters.spawnCharacter = spawnCharacter

-- Free respawn from the death screen.
function Characters.Respawn(player)
	local cooldown = tonumber(GameConfig.get("RespawnCooldown", 1)) or 1
	local now = os.clock()
	local last = lastRespawn[player]
	if last and now - last < cooldown then return false, "too soon" end
	lastRespawn[player] = now

	-- The remote is public: only a dead player may respawn. Without this, firing
	-- it while alive was a free full-health refresh and a model-churn DoS.
	if not player:GetAttribute("Dead") then return false, "not dead" end
	if not DataManager.HasProfile(player) then return false, "no data" end

	spawnCharacter(player, false)
	player:SetAttribute("Killer", nil)
	return true
end

-- Paid revive: keeps the size, otherwise identical to a respawn.
function Characters.Revive(player)
	if not DataManager.HasProfile(player) then return false end
	spawnCharacter(player, true)
	player:SetAttribute("Killer", nil)
	return true
end

--// ------------------------------------------------------------------ autofarm
-- Server-side "walk to the nearest cube", opt-in from the HUD button.
function Characters.AutoFarm(player, enabled)
	enabled = enabled == true
	autoFarmEnabled[player] = enabled
	if not enabled then return end
	if autoFarmThreads[player] then return end -- already running

	autoFarmThreads[player] = true
	task.spawn(function()
		while autoFarmEnabled[player] and player.Parent do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")

			if not humanoid or not root or humanoid.Health <= 0 then
				task.wait(0.5)
				continue
			end

			local foodFolder = workspace:FindFirstChild("FoodParts")
			local closestFood, closestDistance
			if foodFolder then
				for _, food in ipairs(foodFolder:GetChildren()) do
					if food:IsA("BasePart") and food.CanTouch then
						local distance = (root.Position - food.Position).Magnitude
						if not closestDistance or distance < closestDistance then
							closestDistance = distance
							closestFood = food
						end
					end
				end
			end

			if closestFood then
				humanoid:MoveTo(closestFood.Position)
			end
			task.wait(0.5)
		end
		autoFarmThreads[player] = nil
		autoFarmEnabled[player] = nil
	end)
end

--// -------------------------------------------------------------------- eating
-- Eat a cube -> grow (rebirth multiplier) and earn cash. Visuals, rank text and
-- quest progress are all driven by the Size.Changed hook in bindCharacter.
function Characters.IncreaseSize(player, amount)
	local data = DataManager.Data(player)
	if not data then return end
	local size = getSizeObject(player)
	if not size then return end

	local rebirths = data.Rebirths or 0
	DataManager.AddCash(player, GameConfig.cashPerCube(rebirths, player:GetAttribute("2xMoney") == true))

	size.Value += (1 + (amount or 0) * 50) * (data.RebirthMult or 1)
	DataManager.AddStat(player, "Eaten", 1)
end

--// ---------------------------------------------------------------- lifecycle
function Characters.PlayerSetup(player)
	player:SetAttribute("PlayerTime", 0)
	player:SetAttribute("CurrentGift", 0)
	player:SetAttribute("Dead", false)
	spawnCharacter(player, true)

	-- Visuals and the Size hook wait for the profile: leaderstats does not exist
	-- yet at PlayerAdded, and the old `task.wait(0.1)` guess lost that race on
	-- every single join.
	local function afterData()
		if player.Character then
			-- Re-bind so the Size hook, the death handler and the touch rules are
			-- all attached with the profile present.
			bindCharacter(player, player.Character)
		end
		Progression.applySkin(player)
		Progression.setCubeSize(player.Character, GameConfig.visualSize(sizeOf(player)))
		Progression.applyRankText(player)
	end

	if player:GetAttribute("DataLoaded") then
		-- Already loaded (re-entrant call): a change signal would never fire.
		afterData()
		return
	end

	local conn
	conn = player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		if not player:GetAttribute("DataLoaded") then return end
		if conn then conn:Disconnect() end
		afterData()
	end)
end

function Characters.PlayerRemoving(player)
	autoFarmEnabled[player] = nil
	autoFarmThreads[player] = nil
	lastRespawn[player] = nil
	protectTokens[player] = nil
	disconnectAll(player)
end

function Characters.Init()
	Remotes.onServer("RespawnRequest", function(player)
		local ok, reason = Characters.Respawn(player)
		-- The client only hides the death screen once the server confirms, so a
		-- rejected request can never leave someone invisible and stuck.
		Remotes.toClient(player, "RespawnRequest", ok, reason or "")
		if not ok then
			Progression.notify(player, "You are not dead, or your data is still loading.", "bad")
		end
	end)

	Remotes.onServer("AutoFarm", function(player, enabled)
		Characters.AutoFarm(player, enabled)
	end)
end

return Characters
