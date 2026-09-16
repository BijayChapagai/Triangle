-- Eat The Cube - client bootstrap. This is the ONLY LocalScript in the game.
--
-- It lives in ReplicatedFirst so the loading screen can appear before the rest
-- of the game replicates. Everything else is a ModuleScript under
-- Client/ClientModules (and ClientModules/Menus), required here and started in
-- order, so the whole client can be read top to bottom.
--
-- The place supplies the UI: StarterGui.Buttons (menu bar + HUD), StarterGui.Frames
-- (menus), StarterGui.Currency, StarterGui.DeathGui and this script's own Loading
-- and Notifier ScreenGuis. No GUI is created in code.
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local modules = script:WaitForChild("ClientModules")
local menus = modules:WaitForChild("Menus")


--// ------------------------------------------------------- shared client state
local Client = {}
Client.Player = player
Client.Modules = {}
-- The LocalScript itself: the Loading and Notifier ScreenGuis are its children,
-- so modules can find their templates without hard-coding a path.
Client.Bootstrap = script

-- Filled in below, once the rest of the game has replicated. Modules read them
-- from this table (or require GameConfig themselves) after that point.
Client.GameConfig = nil
Client.Ui = nil
Client.Events = nil

-- Early notifications are buffered and flushed once the Notifier exists, so
-- something going wrong during startup is still visible to the player.
local pendingNotes = {}
function Client.Notify(text, kind)
	if #pendingNotes >= 20 then return end
	table.insert(pendingNotes, { text, kind })
end
function Client.flushNotes()
	local notify = Client.Notify
	for _, note in ipairs(pendingNotes) do
		notify(note[1], note[2])
	end
	table.clear(pendingNotes)
end

local warned = {}
function Client.event(name)
	local event = Client.Events and Client.Events:FindFirstChild(name)
	if not event then
		if not warned[name] then
			warned[name] = true
			warn(("[Client] Events.%s is missing from the place - that feature is disabled."):format(name))
		end
		return nil
	end
	return event
end

function Client.fire(name, ...)
	local event = Client.event(name)
	if event then event:FireServer(...) end
end

function Client.on(name, handler)
	local event = Client.event(name)
	if not event then return nil end
	return event.OnClientEvent:Connect(function(...)
		local ok, err = pcall(handler, ...)
		if not ok then warn(("[Client] %s handler failed: %s"):format(name, tostring(err))) end
	end)
end

-- Wait for the GUIs that StarterGui replicates. ReplicatedFirst runs before they
-- exist, so every consumer goes through this instead of racing them.
function Client.playerGui()
	return player:WaitForChild("PlayerGui", 30)
end

function Client.gui(name, timeout)
	local gui = Client.playerGui()
	return gui and gui:WaitForChild(name, timeout or 30)
end

--// ------------------------------------------------------------------- loading
local function start(name, parentDir)
	local holder = parentDir or modules
	local ok, mod = pcall(function()
		return require(holder:WaitForChild(name))
	end)
	if not ok then
		warn(("[Client] could not load module %s: %s"):format(name, tostring(mod)))
		return nil
	end
	Client.Modules[name] = mod
	return mod
end

local LoadingScreen = start("LoadingScreen")
if LoadingScreen then LoadingScreen.Init(Client) end

--// ---------------------------------------------- wait for the game to arrive
-- ReplicatedFirst runs before ReplicatedStorage and Workspace replicate, so the
-- loading screen comes up first and the wait happens behind it. Everything below
-- requires GameConfig, which reads GameData at require time - waiting here means
-- no module ever sees an empty content table.
if LoadingScreen then LoadingScreen.SetProgress(0.1, "Waiting for the game...") end
local gameData = ReplicatedStorage:WaitForChild("GameData", 60)
if not gameData then
	warn("[Client] ReplicatedStorage.GameData never replicated - content will be missing")
end

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
local UiModule = require(ReplicatedStorage:WaitForChild("UiModule"))
Client.GameConfig = GameConfig
Client.Ui = UiModule
Client.Events = ReplicatedStorage:WaitForChild("Events", 60)

--// ------------------------------------------------------------------ settings
-- Client preferences: defaults from GameData/Prefs, the player's own values from
-- their profile. Consumers register a listener instead of being named here, so
-- adding a setting in Studio needs no change to this file.
Client.Prefs = GameConfig.mergePrefs(nil)
local savedPrefs = {}
local prefListeners = {}

function Client.onPref(key, fn)
	table.insert(prefListeners, { key = key, fn = fn })
end

function Client.applyPrefs(prefs)
	savedPrefs = type(prefs) == "table" and prefs or {}
	Client.Prefs = GameConfig.mergePrefs(savedPrefs)
	for _, listener in ipairs(prefListeners) do
		local ok, err = pcall(listener.fn, Client.Prefs[listener.key], Client.Prefs)
		if not ok then
			warn(("[Client] preference listener for %s failed: %s")
				:format(listener.key, tostring(err)))
		end
	end
end

function Client.setPref(key, value)
	if GameConfig.PREFS[key] == nil then return end
	savedPrefs[key] = value
	Client.fire("SavePrefs", key, value)
	-- Applied immediately: waiting for the server echo would make a toggle feel
	-- broken, and the echo only confirms what was stored.
	Client.applyPrefs(savedPrefs)
end

Client.on("SavePrefs", function(prefs)
	Client.applyPrefs(prefs)
end)
Client.fire("SavePrefs") -- ask for the saved values; the defaults are already live

if LoadingScreen then
	LoadingScreen.SetTitle(GameConfig.GAME_NAME)
	LoadingScreen.SetProgress(0.3, "Reading game data...")
end

--// ------------------------------------------------------------------ modules
local function run(name, fn, ...)
	local mod = Client.Modules[name]
	if not mod then
		warn(("[Client] module %s is missing - skipping %s"):format(name, name))
		return false
	end
	local ok, err = pcall(fn, mod, ...)
	if not ok then
		warn(("[Client] %s failed to start: %s"):format(name, tostring(err)))
	end
	return ok
end

local CoreGui = start("CoreGui")
local UiScaler = start("UiScaler")
local Notifier = start("Notifier")
local Camera = start("Camera")
local Popups = start("Popups")
local Hud = start("Hud")
local DeathScreen = start("DeathScreen")
local VipDoor = start("VipDoor")
local Chat = start("Chat")
local KillFeed = start("KillFeed")
local ZoneGuard = start("ZoneGuard")
local MenuUi = start("MenuUi", menus)

if LoadingScreen then LoadingScreen.SetProgress(0.5, "Building the interface...") end

local function bootUi()
	run("CoreGui", function(m) m.Init(Client) end)
	run("UiScaler", function(m) m.Init(Client) end)
	run("Notifier", function(m) m.Init(Client) end)
	run("Camera", function(m) m.Init(Client) end)
	run("Popups", function(m) m.Init(Client) end)

	-- Menus first: Hud buttons toggle them, and each menu registers its frame.
	run("MenuUi", function(m) m.Init(Client) end)
	local menuNames = { "Rebirth", "Skins", "Quests", "Zones", "Leaderboard", "Admin",
		"Codes", "Shop", "Rewards", "UpdateLog", "Settings" }
	for index, name in ipairs(menuNames) do
		start(name, menus)
		run(name, function(m) m.Init(Client) end)
		if LoadingScreen then
			LoadingScreen.SetProgress(0.5 + 0.35 * (index / #menuNames), "Building the interface...")
		end
	end

	run("Hud", function(m) m.Init(Client) end)
	run("DeathScreen", function(m) m.Init(Client) end)
	run("VipDoor", function(m) m.Init(Client) end)
	run("Chat", function(m) m.Init(Client) end)
	run("KillFeed", function(m) m.Init(Client) end)
	run("ZoneGuard", function(m) m.Init(Client) end)
end

-- Preload the map while the loading screen is up, then hand over to the game.
local function preloadContent()
	local workspace_ = workspace
	local count = 0
	local descendants = workspace_:GetDescendants()
	for _, instance in ipairs(descendants) do
		count += 1
		if count % 400 == 0 then
			task.wait() -- never block a frame for the whole map
		end
	end
	if LoadingScreen then LoadingScreen.SetProgress(0.45, "Loading the map...") end
	return count
end

task.spawn(function()
	local ok, err = pcall(preloadContent)
	if not ok then warn("[Client] preload failed: " .. tostring(err)) end

	local guiOk = pcall(bootUi)
	if not guiOk then warn("[Client] UI startup failed") end

	Client.flushNotes()

	if LoadingScreen then
		local ok2, err2 = pcall(function() return LoadingScreen.Finish() end)
		if not ok2 then warn("[Client] loading screen finish failed: " .. tostring(err2)) end
	end

	print(("[Client] %s UI ready | %d zones, %d skins, %d quests")
		:format(GameConfig.GAME_NAME, #GameConfig.zones(), #GameConfig.SKINS, #GameConfig.QUESTS))
end)
