-- Living, rarity-based food economy (ModuleScript).
-- The workspace starts with an EMPTY FoodParts folder; this module fills it at
-- runtime and keeps it replenished. All tunables live in ProgressionConfig.
local FoodSpawner = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Modules.ProgressionConfig)
local C = Config.CONFIG

local FoodFolder = workspace.FoodParts

local function spawnFood(rarityKey, zoneId, center, radius)
	local rarity = Config.RARITIES[rarityKey]
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Block
	part.Name = "Food"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	part.Transparency = 0
	part.Material = Enum.Material.Neon
	part.Color = Config.color3(rarity.color)
	part.Size = Vector3.new(0.05, 0.05, 0.05)

	local x, z, y
	if zoneId and zoneId > 0 and center then
		local cx, _, cz = table.unpack(center)
		local ang = math.random() * math.pi * 2
		local r = math.sqrt(math.random()) * radius
		x = cx + math.cos(ang) * r
		z = cz + math.sin(ang) * r
		y = C.ZoneFoodY
	else
		x = math.random(C.SpawnRegion.minX, C.SpawnRegion.maxX)
		z = math.random(C.SpawnRegion.minZ, C.SpawnRegion.maxZ)
		y = C.FoodY
	end
	part.Position = Vector3.new(x, y, z)
	part:SetAttribute("Value", rarity.value)
	part:SetAttribute("Zone", zoneId or 0)
	CollectionService:AddTag(part, "Food")
	part.Parent = FoodFolder

	local ti = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local t = TweenService:Create(part, ti, { Size = Vector3.new(rarity.size, rarity.size, rarity.size) })
	t:Play()
	return part
end

function FoodSpawner.Init()
	-- Start from a clean slate (workspace ships empty; cubes are generated live)
	for _, f in ipairs(FoodFolder:GetChildren()) do
		if CollectionService:HasTag(f, "Food") then
			f:Destroy()
		end
	end

	-- Seed the map
	for _ = 1, C.BaseFoodTarget do spawnFood(Config.pickRarity(), 0) end
	for _, z in ipairs(Config.ZONES) do
		for _ = 1, C.ZoneFoodTarget do spawnFood(z.rarity, z.id, z.center, z.radius) end
	end

	-- Keep the map full with a smooth trickle (no pop-in)
	task.spawn(function()
		while task.wait(C.SpawnInterval) do
			local baseN = 0
			local counts = {}
			for _, z in ipairs(Config.ZONES) do counts[z.id] = 0 end
			for _, f in ipairs(FoodFolder:GetChildren()) do
				if CollectionService:HasTag(f, "Food") then
					local zid = f:GetAttribute("Zone") or 0
					if zid == 0 then
						baseN = baseN + 1
					else
						counts[zid] = (counts[zid] or 0) + 1
					end
				end
			end
			local toBase = math.max(0, C.BaseFoodTarget - baseN)
			for _ = 1, math.min(toBase, 8) do spawnFood(Config.pickRarity(), 0) end
			for _, z in ipairs(Config.ZONES) do
				local deficit = C.ZoneFoodTarget - (counts[z.id] or 0)
				for _ = 1, math.min(deficit, 4) do spawnFood(z.rarity, z.id, z.center, z.radius) end
			end
		end
	end)
end

return FoodSpawner
