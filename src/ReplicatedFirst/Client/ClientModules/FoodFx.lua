-- Food personality, client side.
--
-- ServerStorage/Food/<Rarity> dresses each tier - material, colour, finish and
-- the top tiers' Glow light. This module is the half that moves: every cube ships
-- Spin/Tilt/Bob/Pulse values and a BaseY attribute, and one loop here turns those
-- into a tumble, a hover and a breath.
--
-- It runs on the client on purpose. The map carries 420 cubes in the hub and 150
-- per zone arena; 500 server-owned CFrame writes a frame is a frame-time disaster,
-- while a client only ever animates what streaming actually handed it, and stops
-- past MAX_DISTANCE. The server still owns a cube the moment it is claimed
-- (CanTouch goes false and a despawn tween plays), so this lets go of claimed
-- cubes instead of fighting that tween for Size.
local FoodFx = {}

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local POP_TIME = 0.3      -- seconds to ease out to full size, as the old server tween did
local BOB_SPEED = 1.9     -- radians/second of hover
local PULSE_SPEED = 2.6   -- radians/second of breathing
local MAX_DISTANCE = 240  -- studs; past this a cube is a dot and the motion is wasted
local MAX_ANIMATED = 260  -- hard cap, so a dense arena cannot melt a low-end phone

local state = {}          -- part -> motion record
local reducedMotion = false
local camera
local warned = false

local function easeOutBack(t)
	-- The curve the spawn tween used: a cube arrives slightly too big, then settles.
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function numberOf(part, name)
	local value = part:FindFirstChild(name)
	if value and (value:IsA("NumberValue") or value:IsA("IntValue")) then
		return tonumber(value.Value) or 0
	end
	return 0
end

local function track(part)
	local record = state[part]
	if record then return record end

	record = {
		x = part.Position.X,
		z = part.Position.Z,
		baseY = tonumber(part:GetAttribute("BaseY")) or part.Position.Y,
		size = part.Size,
		spin = numberOf(part, "Spin"),
		tilt = numberOf(part, "Tilt"),
		bob = numberOf(part, "Bob"),
		pulse = numberOf(part, "Pulse"),
		phase = math.random() * math.pi * 2,
		age = 0,
		rotX = 0,
		rotY = 0,
	}
	state[part] = record
	return record
end

local function step(part, record, dt, now)
	record.age += dt

	local scale = easeOutBack(math.clamp(record.age / POP_TIME, 0, 1))
	if not reducedMotion then
		record.rotY += record.spin * dt
		record.rotX += record.tilt * dt
		scale *= 1 + record.pulse * math.sin(now * PULSE_SPEED + record.phase)
	end
	part.Size = record.size * math.max(scale, 0.02)

	local y = record.baseY
	if not reducedMotion and record.bob > 0 then
		y += record.bob * math.sin(now * BOB_SPEED + record.phase)
	end

	part.CFrame = CFrame.new(record.x, y, record.z)
		* CFrame.Angles(math.rad(record.rotX), math.rad(record.rotY), 0)
end

local function sweep(dt, now)
	local origin = camera and camera.CFrame.Position
	if not origin then return end

	local animated = 0
	for _, part in ipairs(CollectionService:GetTagged("Food")) do
		if not part:IsA("BasePart") or not part.Parent then
			continue
		end
		-- Claimed: the server's despawn tween owns Size and Transparency again.
		if part.CanTouch == false then
			state[part] = nil
			continue
		end
		if (part.Position - origin).Magnitude > MAX_DISTANCE then
			state[part] = nil
			continue
		end

		animated += 1
		if animated > MAX_ANIMATED then break end
		step(part, track(part), dt, now)
	end
end

function FoodFx.Init(client)
	camera = workspace.CurrentCamera
	reducedMotion = client.Prefs and client.Prefs.ReducedMotion == true
	client.onPref("ReducedMotion", function(value)
		reducedMotion = value == true
	end)

	-- Heartbeat, not RenderStepped: these are server-owned instances, so there is
	-- nothing to line up with a frame, and Heartbeat keeps the work off the
	-- render budget.
	RunService.Heartbeat:Connect(function(dt)
		-- dt spikes after a stall; clamp so a cube does not teleport half a turn.
		local ok, err = pcall(sweep, math.min(dt, 0.1), os.clock())
		if not ok and not warned then
			warned = true
			warn("[FoodFx] animation stopped: " .. tostring(err))
		end
	end)

	CollectionService:GetInstanceRemovedSignal("Food"):Connect(function(instance)
		state[instance] = nil
	end)

	return true
end

return FoodFx
