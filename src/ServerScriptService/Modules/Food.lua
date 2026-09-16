-- Food: the living cube economy.
--
-- workspace/FoodParts ships empty; this module fills it from the region plan and
-- keeps every pool topped up. Regions come from the place itself:
--   * hub arena    inset from the 87-stud walls (Settings) so nothing spawns over
--                  the void; mixed rarity, the pool everybody starts in
--   * zone arenas  workspace/Zones/<Name>/Floor - the slab IS the region, so
--                  moving or resizing an arena in Studio moves its food pool.
--                  Each arena is walled, stands far from the hub, and holds only
--                  its own rarity
--   * VIP wing     beyond workspace/VIPDoor, denser and Rare-or-better
--
-- Pickup is handled here too, with the same zone gate the teleport uses.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Progression = require(script.Parent:WaitForChild("Progression"))
local Characters = require(script.Parent:WaitForChild("Characters"))

local Food = {}

local C = GameConfig.CONFIG
local ARENA_ZONE_ID = 0

local FoodFolder = workspace:FindFirstChild("FoodParts")
if not FoodFolder then
	FoodFolder = Instance.new("Folder")
	FoodFolder.Name = "FoodParts"
	FoodFolder.Parent = workspace
end

-- Live cube count per region, so the top-up loop never rescans the folder.
local liveCounts = {}
local hooked = {}
local lastZoneWarn = {}

--// ----------------------------------------------------------------- templates
-- ServerStorage/Food/<Rarity> IS the cube: material, colour, finish, size and the
-- optional Glow light are properties of that part, and the Spin/Tilt/Bob/Pulse
-- values inside it drive the client animator. Food clones it rather than building
-- a part, so repainting a tier in Studio repaints every cube of that tier.
local FoodTemplates = ServerStorage:FindFirstChild("Food")
local warnedTemplate = {}

-- Legendary and Mythic cubes ship a PointLight. A zone arena holds 150 of one
-- rarity, and 150 light sources is a frame-time disaster, so a region keeps this
-- many glows and the rest of the tier loses only the light - the material, spin,
-- bob and pulse are free and still say which tier it is.
local FX_BUDGET = math.max(0, tonumber(C.FoodFxBudget) or 0)
local fxUsed = {}

local function numberOf(part, name)
	local value = part:FindFirstChild(name)
	if value and (value:IsA("NumberValue") or value:IsA("IntValue")) then
		return tonumber(value.Value) or 0
	end
	return 0
end

local function makeCube(rarity)
	local template = FoodTemplates and FoodTemplates:FindFirstChild(rarity.name)
	if template and template:IsA("BasePart") then
		return template:Clone()
	end

	-- No template: that tier loses its personality, not the game its food.
	if not warnedTemplate[rarity.name] then
		warnedTemplate[rarity.name] = true
		warn(("[Food] ServerStorage/Food/%s is missing - that tier falls back to a plain cube")
			:format(rarity.name))
	end
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = rarity.color
	part.Size = Vector3.new(rarity.size, rarity.size, rarity.size)
	return part
end

local function bump(zoneId, delta)
	liveCounts[zoneId] = math.max(0, (liveCounts[zoneId] or 0) + delta)
	return liveCounts[zoneId]
end

--// ------------------------------------------------------------------- regions
-- The inside of a zone arena: its floor slab, minus a lip so a cube never spawns
-- intersecting a wall. The walls stand just outside the slab, so the slab's half
-- width is the arena's half width and one inset covers both.
local function zoneRegion(zone)
	local r = math.max(2, zone.radius - 2)
	return {
		minX = math.floor(zone.center[1] - r),
		maxX = math.floor(zone.center[1] + r),
		minZ = math.floor(zone.center[3] - r),
		maxZ = math.floor(zone.center[3] + r),
	}
end

-- { zoneId, region, floorY, target, pick() }
local function buildPlan()
	local plan = {}

	table.insert(plan, {
		zoneId = ARENA_ZONE_ID,
		region = C.SpawnRegion,
		floorY = GameConfig.MAP.FloorY,
		target = C.BaseFoodTarget,
		pick = function() return GameConfig.pickRarity() end,
	})

	for _, zone in ipairs(GameConfig.zones()) do
		table.insert(plan, {
			zoneId = zone.id,
			region = zoneRegion(zone),
			floorY = zone.topY,
			target = C.ZoneFoodTarget,
			pick = (function(rarity) return function() return rarity end end)(zone.rarity),
		})
	end

	local vip = GameConfig.VIP
	if vip.FoodTarget > 0 then
		table.insert(plan, {
			zoneId = vip.ZoneId,
			region = vip.Region,
			floorY = GameConfig.MAP.FloorY,
			target = vip.FoodTarget,
			pick = (function(floor)
				return function() return GameConfig.pickRarity(floor) end
			end)(vip.RarityFloor),
		})
	end

	return plan
end

local PLAN = {}

local function pickPosition(entry)
	local region = entry.region
	return math.random(region.minX, region.maxX), math.random(region.minZ, region.maxZ)
end

--// ------------------------------------------------------------------ spawning
local function spawnOne(entry)
	local rarityKey = entry.pick()
	local rarity = GameConfig.RARITIES[rarityKey] or GameConfig.RARITY_LIST[1]
	if not rarity then return nil end

	local part = makeCube(rarity)
	part.Name = "Food"
	part:SetAttribute("Rarity", rarity.name)
	part:SetAttribute("Value", rarity.value)
	part:SetAttribute("Zone", entry.zoneId)

	-- Keep the light only while the region's budget lasts.
	local glow = part:FindFirstChild("Glow")
	if glow then
		fxUsed[entry.zoneId] = (fxUsed[entry.zoneId] or 0) + 1
		if fxUsed[entry.zoneId] > FX_BUDGET then
			glow:Destroy()
			glow = nil
		end
	end

	local x, z = pickPosition(entry)
	-- Rest ON the surface instead of sinking into it, and clear of it by however
	-- far this tier hovers, so the bob never clips the floor.
	local bob = numberOf(part, "Bob")
	local baseY = (entry.floorY or GameConfig.MAP.FloorY) + rarity.size / 2 + bob
	part.CFrame = CFrame.new(x, baseY, z)
	-- The client animator hovers and breathes around this height; it is an
	-- attribute rather than a value object so it costs one replication each.
	part:SetAttribute("BaseY", baseY)

	bump(entry.zoneId, 1)

	-- Tag BEFORE parenting so the pickup handler sees it exactly once.
	CollectionService:AddTag(part, "Food")
	part.Parent = FoodFolder

	-- The pop-in, spin, hover and breathing are the client's job (FoodFx): one
	-- owner of Size and CFrame per cube, and only for cubes a player can see.

	part.Destroying:Connect(function()
		bump(entry.zoneId, -1)
		if glow then
			fxUsed[entry.zoneId] = math.max(0, (fxUsed[entry.zoneId] or 1) - 1)
		end
	end)

	return part
end

local function deficit(entry)
	return math.max(0, entry.target - (liveCounts[entry.zoneId] or 0))
end

local function seedMap()
	local queue = {}
	for _, entry in ipairs(PLAN) do
		for _ = 1, entry.target do
			table.insert(queue, entry)
		end
	end
	local made = 0
	for _, entry in ipairs(queue) do
		if spawnOne(entry) then made += 1 end
		if made % C.SeedBatch == 0 then
			task.wait() -- never freeze the server while seeding
		end
	end
	return made
end

--// ------------------------------------------------------------------- pickup
local function eat(food, player)
	-- Zone/VIP gating is per cube, not per position. Arenas are walled and the
	-- teleport is gated, so this is the last line of defence: an admin teleport, a
	-- moved arena or a future gateway must never hand out a locked rarity tier.
	local zoneId = food:GetAttribute("Zone") or 0
	if zoneId ~= 0 then
		local allowed, reason = Progression.CanUseZone(player, zoneId)
		if not allowed then
			food.CanTouch = true -- let them try again instead of burning the cube
			local now = os.clock()
			if not lastZoneWarn[player] or now - lastZoneWarn[player] > 3 then
				lastZoneWarn[player] = now
				Progression.notify(player, reason or "Locked", "bad")
			end
			return
		end
	end

	local value = food:GetAttribute("Value") or 5
	Characters.IncreaseSize(player, value / 50)
	Progression.AddProgress(player, "eat", 1)

	-- Smooth shrink-out; the top-up loop refills the region.
	local ok, err = pcall(function()
		local tween = TweenService:Create(food, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = Vector3.new(0.05, 0.05, 0.05),
			Transparency = 1,
		})
		tween.Completed:Connect(function()
			food:Destroy()
		end)
		tween:Play()
	end)
	if not ok then
		warn("[Food] despawn tween failed, destroying directly: " .. tostring(err))
		food:Destroy()
	end
end

local function handleFood(food)
	if hooked[food] then return end
	hooked[food] = true

	local conn
	conn = food.Touched:Connect(function(otherPart)
		if not conn.Connected then return end
		if not otherPart or not otherPart.Parent then return end

		local player = Players:GetPlayerFromCharacter(otherPart.Parent)
		if not player then return end
		if food.CanTouch == false then return end

		-- Claim the cube first so two touches in the same frame cannot both eat it.
		food.CanTouch = false

		-- Nothing below may throw: an error here used to leave the cube claimed
		-- but alive, i.e. permanently inedible map litter.
		local ok, err = pcall(eat, food, player)
		if not ok then
			warn("[Food] eat failed: " .. tostring(err))
			food:Destroy()
		end
	end)

	food.Destroying:Connect(function()
		hooked[food] = nil
		if conn.Connected then conn:Disconnect() end
	end)
end

--// --------------------------------------------------------------------- admin
function Food.Clear()
	for _, part in ipairs(CollectionService:GetTagged("Food")) do
		part:Destroy()
	end
	table.clear(liveCounts)
	table.clear(fxUsed)
end

function Food.Count()
	return #CollectionService:GetTagged("Food")
end

function Food.Stats()
	local out = {}
	for _, entry in ipairs(PLAN) do
		table.insert(out, ("%d/%d"):format(liveCounts[entry.zoneId] or 0, entry.target))
	end
	return table.concat(out, "  ")
end

--// ---------------------------------------------------------------------- init
function Food.Init()
	PLAN = buildPlan()

	Food.Clear() -- clean slate: Studio sessions can leave food behind

	local made = seedMap()
	print(("[Food] seeded %d cubes across %d regions"):format(made, #PLAN))

	CollectionService:GetInstanceAddedSignal("Food"):Connect(function(instance)
		if instance:IsA("BasePart") then handleFood(instance) end
	end)
	CollectionService:GetInstanceRemovedSignal("Food"):Connect(function(instance)
		hooked[instance] = nil
	end)
	for _, food in ipairs(CollectionService:GetTagged("Food")) do
		if food:IsA("BasePart") then handleFood(food) end
	end

	-- Keep every pool full with a smooth trickle (no pop-in storms).
	task.spawn(function()
		while task.wait(C.SpawnInterval) do
			for _, entry in ipairs(PLAN) do
				local missing = deficit(entry)
				for _ = 1, math.min(missing, C.SpawnBatch) do
					spawnOne(entry)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastZoneWarn[player] = nil
	end)
end

return Food
