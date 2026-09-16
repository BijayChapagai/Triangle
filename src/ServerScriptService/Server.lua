-- Eat The Cube - server bootstrap. This is the ONLY Script in the game.
--
-- Everything else in ServerScriptService/Modules is a ModuleScript that is
-- required here and initialised in dependency order. Nothing runs on require, so
-- the whole server can be read top to bottom and a module can never boot before
-- the data it depends on exists.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
local Modules = ServerScriptService:WaitForChild("Modules")

local DataManager = require(Modules:WaitForChild("DataManager"))
local Leaderboards = require(Modules:WaitForChild("Leaderboards"))
local Progression = require(Modules:WaitForChild("Progression"))
local Characters = require(Modules:WaitForChild("Characters"))
local Food = require(Modules:WaitForChild("Food"))
local Players_ = require(Modules:WaitForChild("Players"))
local Shop = require(Modules:WaitForChild("Shop"))
local Codes = require(Modules:WaitForChild("Codes"))
local Gifts = require(Modules:WaitForChild("Gifts"))
local Admin = require(Modules:WaitForChild("Admin"))

-- One failure must not take the rest of the server down with it.
local function boot(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		warn(("[Server] %s failed to start: %s"):format(name, tostring(err)))
	end
	return ok
end

-- Wire remote handlers first, then data, then the world, then players last:
-- players joining is what starts spawning characters, and every character path
-- expects the remotes and the food pools to already exist.
boot("Leaderboards", Leaderboards.Init)
boot("Progression", Progression.Init)
boot("Characters", Characters.Init)
boot("Gifts", Gifts.Init)
boot("Codes", Codes.Init)
boot("Shop", Shop.Init)
boot("Admin", Admin.Init)
boot("DataManager", DataManager.Init)
boot("Players", Players_.Init)
boot("Food", Food.Init)

print(("[Server] %s ready | %d zones, %d skins, %d quests, %d products | admins: %s")
	:format(GameConfig.GAME_NAME, #GameConfig.zones(), #GameConfig.SKINS, #GameConfig.QUESTS,
		#GameConfig.PRODUCT_LIST, table.concat(GameConfig.ADMINS, ", ")))
