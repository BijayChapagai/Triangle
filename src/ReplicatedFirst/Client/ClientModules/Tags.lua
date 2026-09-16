-- Name tags and zone signs: constant size, soft edges.
--
-- Both are pixel-sized BillboardGuis, so they hold their size on screen however
-- far away you are (a billboard sized in scale units is world-sized, which is how
-- the name tags used to shrink to nothing across an arena). What they did NOT
-- have was an edge: Roblox cuts a billboard off dead at MaxDistance, so a tag
-- vanished between two frames and read as a glitch.
--
-- This module dissolves each billboard over the last quarter of its range and
-- fades it up when it first appears, so the cutoff is a fade. It only ever writes
-- transparency: the TEXT a tag shows belongs to the server, and its SIZE belongs
-- to the asset in Studio.
local Tags = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FADE_SPAN = 0.25      -- fraction of MaxDistance spent dissolving at the edge
local POP_IN = 0.35         -- seconds for a freshly spawned tag to fade up
local DEFAULT_RANGE = 600   -- only used if a billboard has no MaxDistance at all

local camera
local reducedMotion = false
local watched = {}          -- billboard -> record
local characters = {}       -- character -> true, so a respawn is picked up once

local function watch(billboard)
	local record = {
		labels = {},
		range = billboard.MaxDistance > 0 and billboard.MaxDistance or DEFAULT_RANGE,
		born = os.clock(),
		factor = -1,        -- forces a write on the first sweep
	}

	for _, child in ipairs(billboard:GetDescendants()) do
		if child:IsA("TextLabel") then
			table.insert(record.labels, {
				object = child,
				kind = "text",
				base = child.TextTransparency,
				background = child.BackgroundTransparency,
			})
		elseif child:IsA("ImageLabel") then
			table.insert(record.labels, {
				object = child,
				kind = "image",
				base = child.ImageTransparency,
				background = child.BackgroundTransparency,
			})
		end
	end

	watched[billboard] = record
	return record
end

local function apply(record, factor)
	if factor == record.factor then return end
	record.factor = factor

	local hidden = 1 - factor
	for _, label in ipairs(record.labels) do
		local object = label.object
		if object.Parent == nil then continue end
		if label.kind == "text" then
			object.TextTransparency = label.base + (1 - label.base) * hidden
		else
			object.ImageTransparency = label.base + (1 - label.base) * hidden
		end
		object.BackgroundTransparency = label.background + (1 - label.background) * hidden
	end
end

-- 1 while the billboard is in comfortable range, 0 once it is past MaxDistance,
-- and a ramp in between instead of a cliff.
local function rangeFactor(record, distance)
	if distance >= record.range then return 0 end
	local fadeStart = record.range * (1 - FADE_SPAN)
	if distance <= fadeStart then return 1 end
	return 1 - (distance - fadeStart) / (record.range - fadeStart)
end

local function collect()
	-- Player tags ride on the character the server hands out; a respawn is a new
	-- character, so the old record is dropped when its billboard loses its parent.
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and not characters[character] then
			characters[character] = true
			local billboard = character:FindFirstChild("PlayerDisplay", true)
			if billboard and billboard:IsA("BillboardGui") and not watched[billboard] then
				watch(billboard)
			end
		end
	end

	-- Zone signs are map geometry: one per arena, under its floor slab.
	local zones = workspace:FindFirstChild("Zones")
	if zones then
		for _, zone in ipairs(zones:GetChildren()) do
			local floor = zone:FindFirstChild("Floor")
			local sign = floor and floor:FindFirstChild("Sign")
			if sign and sign:IsA("BillboardGui") and not watched[sign] then
				watch(sign)
			end
		end
	end
end

local function sweep()
	local origin = camera and camera.CFrame.Position
	if not origin then return end

	collect()

	local now = os.clock()
	for billboard, record in pairs(watched) do
		if billboard.Parent == nil then
			watched[billboard] = nil
			continue
		end

		local adornee = billboard.Adornee or billboard.Parent
		local position = adornee and adornee:IsA("BasePart") and adornee.Position
		local factor = rangeFactor(record, position and (position - origin).Magnitude or 0)

		if not reducedMotion then
			factor *= math.clamp((now - record.born) / POP_IN, 0, 1)
		end
		apply(record, factor)
	end
end

function Tags.Init(client)
	camera = workspace.CurrentCamera
	reducedMotion = client.Prefs and client.Prefs.ReducedMotion == true
	client.onPref("ReducedMotion", function(value)
		reducedMotion = value == true
	end)

	Players.PlayerRemoving:Connect(function(player)
		local character = player.Character
		if character then characters[character] = nil end
	end)

	-- Heartbeat: a dissolve at frame rate is smooth and this touches a couple of
	-- dozen objects, so there is nothing to throttle.
	local warned = false
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(sweep)
		if not ok and not warned then
			warned = true
			warn("[Tags] stopped fading billboards: " .. tostring(err))
		end
	end)

	return true
end

return Tags
