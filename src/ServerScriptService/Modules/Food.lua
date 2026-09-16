-- Food: the living cube economy.
--
-- workspace/FoodParts ships empty; this module fills it from the region plan and
-- keeps every pool topped up. Regions come from the place itself:
--   * open arena   inset from the 87-stud walls (Settings) so nothing spawns over
--                  the void, and kept OFF the zone daises so each dais reads as
--                  its own rarity tier
--   * zone daises  workspace/Zones/<Name> - the part IS the region, so moving or
--                  resizing a dais in Studio moves its food pool
--   * VIP wing     beyond workspace/VIPDoor, denser and Rare-or-better
--
-- Pickup is handled here too, with the same zone gate the teleport uses.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local function bump(zoneId, delta)
	liveCounts[zoneId] = math.max(0, (liveCounts[zoneId] or 0) + delta)
	return liveCounts[zoneId]
end

--// ------------------------------------------------------------------- regions
local function daisRegion(zone)
	local r = math.max(2, zone.radius - 2)
	return {
		minX = math.floor(zone.center[1] - r),
		maxX = math.floor(zone.center[1] + r),
		minZ = math.floor(zone.center[3] - r),
		maxZ = math.floor(zone.center[3] + r),
	}
end

local function inside(region, x, z)
	return x >= region.minX and x <= region.maxX and z >= region.minZ and z <= region.maxZ
end

-- { zoneId, region, floorY, target, pick(), avoid }
local function buildPlan()
	local plan = {}

	local avoid = {}
	for _, zone in ipairs(GameConfig.zones()) do
		table.insert(avoid, daisRegion(zone))
	end

	table.insert(plan, {
		zoneId = ARENA_ZONE_ID,
		region = C.SpawnRegion,
		floorY = GameConfig.MAP.FloorY,
		target = C.BaseFoodTarget,
		pick = function() return GameConfig.pickRarity() end,
		avoid = avoid,
	})

	for _, zone in ipairs(GameConfig.zones()) do
		table.insert(plan, {
			zoneId = zone.id,
			region = daisRegion(zone),
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
	local x = math.random(region.minX, region.maxX)
	local z = math.random(region.minZ, region.maxZ)
	if not entry.avoid then return x, z end

	-- Retry a few times to keep generic arena food off the rarity daises. A rare
	-- overlap is harmless, so there is no point looping until it is perfect.
	for _ = 1, 6 do
		local blocked = false
		for _, rect in ipairs(entry.avoid) do
			if inside(rect, x, z) then blocked = true break end
		end
		if not blocked then return x, z end
		x = math.random(region.minX, region.maxX)
		z = math.random(region.minZ, region.maxZ)
	end
	return x, z
end

--// ------------------------------------------------------------------ spawning
local function spawnOne(entry)
	local rarityKey = entry.pick()
	local rarity = GameConfig.RARITIES[rarityKey] or GameConfig.RARITY_LIST[1]
	if not rarity then return nil end

	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Block
	part.Name = "Food"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	-- Hundreds of shadow-casting neon parts under Lighting.Technology = Future is
	-- a frame-time disaster; food never needs to cast a shadow or be raycast.
	part.CastShadow = false
	part.CanQuery = false
	part.Transparency = 0
	part.Material = Enum.Material.Neon
	part.Color = rarity.color
	part.Size = Vector3.new(0.05, 0.05, 0.05) -- eased out to full size below
	part:SetAttribute("Rarity", rarity.name)
	part:SetAttribute("Value", rarity.value)
	part:SetAttribute("Zone", entry.zoneId)

	local x, z = pickPosition(entry)
	-- Rest ON the surface instead of sinking into it.
	part.CFrame = CFrame.new(x, (entry.floorY or GameConfig.MAP.FloorY) + rarity.size / 2, z)

	bump(entry.zoneId, 1)

	-- Tag BEFORE parenting so the pickup handler sees it exactly once.
	CollectionService:AddTag(part, "Food")
	part.Parent = FoodFolder

	TweenService:Create(part, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = Vector3.new(rarity.size, rarity.size, rarity.size),
	}):Play()

	part.Destroying:Connect(function()
		bump(entry.zoneId, -1)
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
	-- Zone/VIP gating is per cube, not per position: walking into a locked dais
	-- (they have no walls) must not hand out its rarity tier for free.
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
