local ProgressionConfig = {}

-- Size rank names (1-based). Thresholds scale with rebirths so higher
-- rebirths need more size for the same rank -> "harder" progression.
ProgressionConfig.RANKS = {
	"Cube", "Block", "Big Cube", "Huge Cube", "Mega Cube",
	"Titan Cube", "Colossus", "Galaxy Cube", "Void Cube", "God Cube", "Omni Cube",
}
ProgressionConfig.RANK_THRESHOLDS = {
	0, 60, 180, 500, 1200, 3000, 7000, 16000, 40000, 100000, 250000,
}

-- Food rarity tiers (weighted). value = size gained, size = cube world size.
ProgressionConfig.RARITIES = {
	Common    = { name = "Common",    weight = 62,  value = 5,    size = 1.0, color = {255, 70, 130} },
	Rare      = { name = "Rare",      weight = 24,  value = 28,   size = 1.7, color = {60, 170, 255} },
	Epic      = { name = "Epic",      weight = 10,  value = 110,  size = 2.4, color = {180, 90, 255} },
	Legendary = { name = "Legendary", weight = 3.5, value = 400,  size = 3.2, color = {255, 205, 50} },
	Mythic    = { name = "Mythic",    weight = 0.5, value = 1500, size = 4.2, color = {255, 95, 35} },
}

-- Cube skins. unlock: "start" | "size" | "cash" | "rebirth"
ProgressionConfig.SKINS = {
	{ id = "Default",  color = {255, 0, 80},    unlock = "start" },
	{ id = "Emerald",  color = {0, 255, 140},   unlock = "size",    req = 200 },
	{ id = "Sapphire", color = {40, 120, 255},  unlock = "size",    req = 1500 },
	{ id = "Gold",     color = {255, 215, 0},   unlock = "cash",    req = 5000 },
	{ id = "Galaxy",   color = {150, 0, 255},   unlock = "rebirth", req = 1 },
	{ id = "Inferno",  color = {255, 70, 0},    unlock = "rebirth", req = 3 },
	{ id = "Frost",    color = {120, 230, 255}, unlock = "rebirth", req = 5 },
	{ id = "Void",     color = {90, 0, 170},    unlock = "rebirth", req = 10 },
}

-- 5 zones. center/radius define the region. req gates entry (harder each zone).
ProgressionConfig.ZONES = {
	{ id = 1, name = "Greenfield",   color = {80, 220, 120},  rarity = "Common",    req = {},                              center = {0, 0, 0},        radius = 72 },
	{ id = 2, name = "Crystal Cave", color = {80, 200, 255},  rarity = "Rare",      req = { size = 300 },                  center = {-235, 0, -235}, radius = 56 },
	{ id = 3, name = "Lava Forge",   color = {255, 130, 40},  rarity = "Epic",      req = { size = 1500 },                 center = {235, 0, -235},  radius = 56 },
	{ id = 4, name = "Frozen Peak",  color = {150, 230, 255}, rarity = "Legendary", req = { rebirth = 2 },                 center = {-235, 0, 235},  radius = 56 },
	{ id = 5, name = "Void Core",    color = {175, 70, 255},  rarity = "Mythic",    req = { rebirth = 5 },                 center = {235, 0, 235},   radius = 56 },
}

-- Daily quests (reset every real day).
ProgressionConfig.QUESTS = {
	{ id = "eat50",    type = "eat",    goal = 50,   rewardCash = 500,   text = "Eat 50 cubes" },
	{ id = "eat500",   type = "eat",    goal = 500,  rewardCash = 2500,  text = "Eat 500 cubes" },
	{ id = "kill3",    type = "kill",   goal = 3,    rewardCash = 1200,  text = "Eliminate 3 players" },
	{ id = "size100",  type = "size",   goal = 100,  rewardCash = 1500,  text = "Reach Size 100" },
	{ id = "size1000", type = "size",   goal = 1000, rewardCash = 8000,  text = "Reach Size 1000" },
	{ id = "rebirth1", type = "rebirth", goal = 1,   rewardSkin = "Galaxy", rewardCash = 0, text = "Rebirth once (unlocks Galaxy skin)" },
}

function ProgressionConfig.getRank(sizeVal, rebirths)
	local scale = 1 + (rebirths or 0) * 0.6
	local thr = ProgressionConfig.RANK_THRESHOLDS
	local rank = 1
	for i = 1, #thr do
		if sizeVal >= thr[i] * scale then rank = i end
	end
	return rank, ProgressionConfig.RANKS[rank]
end

function ProgressionConfig.visualSize(sizeVal)
	return 1 + math.sqrt(math.max(sizeVal, 0)) * 0.12
end

function ProgressionConfig.rebirthRequirement(rebirths)
	return math.floor(300 * (rebirths + 1) * (rebirths + 1) * 0.6) + 150 * rebirths + 200
end

function ProgressionConfig.rebirthMultiplier(rebirths)
	return 1 + rebirths * 0.12
end

function ProgressionConfig.color3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- pick a rarity key, optionally raising the floor (zones)
function ProgressionConfig.pickRarity(floorTier)
	local pool = {}
	for key, r in pairs(ProgressionConfig.RARITIES) do
		if floorTier == nil or r.value >= ProgressionConfig.RARITIES[floorTier].value then
			table.insert(pool, { key = key, weight = r.weight })
		end
	end
	local total = 0
	for _, p in ipairs(pool) do total = total + p.weight end
	local roll = math.random() * total
	for _, p in ipairs(pool) do
		roll = roll - p.weight
		if roll <= 0 then return p.key end
	end
	return pool[#pool].key
end

-- // Central tuning knobs. Edit these to customize the whole game in one place.
ProgressionConfig.CONFIG = {
	BaseFoodTarget = 450,                                   -- cubes kept alive across the open map
	ZoneFoodTarget = 70,                                    -- cubes kept alive inside each zone
	SpawnInterval = 1.5,                                    -- seconds between top-up passes
	SpawnRegion = { minX = -270, maxX = 400, minZ = -320, maxZ = 320 }, -- base map bounds
	FoodY = 0.6,                                            -- height of base-map food
	ZoneFoodY = 3.2,                                        -- height of zone food
}

return ProgressionConfig
