-- Camera: keeps the field of view under control and adds a small "punch" when
-- the cube grows a lot in one bite (eating another player). Menus tween the FOV
-- themselves through UiModule; this module owns the baseline they return to.
local Camera = {}

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))

local BASE_FOV = tonumber(GameConfig.get("CameraFov", 70)) or 70
local PUNCH = tonumber(GameConfig.get("CameraFovPunch", 6)) or 6
local PUNCH_TIME = tonumber(GameConfig.get("CameraPunchTime", 0.35)) or 0.35
local PUNCH_THRESHOLD = tonumber(GameConfig.get("CameraPunchThreshold", 40)) or 40
local PUNCH_COOLDOWN = 0.4

local camera
local punching = false
local lastPunch = 0
local punchEnabled = true
local motionEnabled = true

-- Both are player preferences (GameData/Prefs). Reduced motion is the wider one:
-- it kills the fov kick and makes every transition this module owns instant.
function Camera.SetPunchEnabled(on)
	punchEnabled = on ~= false
end

function Camera.SetMotionEnabled(on)
	motionEnabled = on ~= false
	if not motionEnabled and camera then
		camera.FieldOfView = BASE_FOV
	end
end

function Camera.setFov(fov, time)
	if not camera then return end
	fov = tonumber(fov) or BASE_FOV
	if not motionEnabled then
		camera.FieldOfView = fov
		return
	end
	TweenService:Create(camera, TweenInfo.new(time or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = fov,
	}):Play()
end

function Camera.punch(amount)
	if not camera or punching or not punchEnabled or not motionEnabled then return end
	local now = os.clock()
	if now - lastPunch < PUNCH_COOLDOWN then return end
	lastPunch = now
	punching = true

	local target = math.clamp(BASE_FOV + (tonumber(amount) or PUNCH), BASE_FOV, BASE_FOV + 25)
	TweenService:Create(camera, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = target,
	}):Play()
	task.delay(PUNCH_TIME, function()
		punching = false
		-- Only restore if no menu is open; menus hold FOV at their own value.
		if camera and not punching then
			Camera.setFov(BASE_FOV, 0.25)
		end
	end)
end

function Camera.Init(client)
	camera = workspace.CurrentCamera
	if not camera then
		warn("[Camera] no CurrentCamera yet")
		return false
	end

	local player = client and client.Player or Players.LocalPlayer

	-- Preferences before anything can punch: Client.Prefs already holds the
	-- defaults at this point, and the listeners pick up the saved values.
	Camera.SetPunchEnabled(client.Prefs and client.Prefs.CameraPunch)
	Camera.SetMotionEnabled(not (client.Prefs and client.Prefs.ReducedMotion))
	client.onPref("CameraPunch", function(value) Camera.SetPunchEnabled(value) end)
	client.onPref("ReducedMotion", function(value) Camera.SetMotionEnabled(not value) end)

	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = BASE_FOV

	local function watch(character)
		local humanoid = character and character:WaitForChild("Humanoid", 10)
		if humanoid then
			-- The custom cube characters keep Roblox's default camera, but a future
			-- template change should not silently turn this into a fixed camera.
			if camera.CameraType ~= Enum.CameraType.Custom then
				camera.CameraType = Enum.CameraType.Custom
			end
		end
	end

	if player.Character then task.spawn(watch, player.Character) end
	player.CharacterAdded:Connect(function(character)
		task.spawn(watch, character)
	end)

	-- FOV punch on big size jumps (a kill absorbs a chunk of the victim's size).
	local function hookSize(size)
		local last = size.Value
		size.Changed:Connect(function()
			local delta = size.Value - last
			last = size.Value
			if delta >= PUNCH_THRESHOLD then
				Camera.punch(PUNCH * math.clamp(delta / PUNCH_THRESHOLD, 1, 3))
			end
		end)
	end

	local ls = player:FindFirstChild("leaderstats")
	local size = ls and ls:FindFirstChild("Size")
	if size then
		hookSize(size)
	else
		task.spawn(function()
			local stats = player:WaitForChild("leaderstats", 60)
			local value = stats and stats:WaitForChild("Size", 10)
			if value then hookSize(value) end
		end)
	end

	return true
end

return Camera
