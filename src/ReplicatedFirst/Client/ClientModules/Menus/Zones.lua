-- Zones menu. The zones ARE the map: each dais in workspace/Zones carries its own
-- Id, Rarity, ReqSize, ReqRebirth and Color, so moving or retuning a zone in
-- Studio updates this menu, the signs and the server gate together.
local Zones = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local MenuUi = require(script.Parent:WaitForChild("MenuUi"))

local FRAME_NAME = "Zones"
local OPEN = Color3.fromRGB(110, 220, 140)
local LOCKED = Color3.fromRGB(235, 90, 90)
local VIP_COLOR = Color3.fromRGB(255, 205, 90)

local client, player, frame
local statusLabel
local watching = false

local function sizeValue()
	local stats = player:FindFirstChild("leaderstats")
	local size = stats and stats:FindFirstChild("Size")
	return size and size.Value or 0
end

local function rebirths()
	-- The server keeps the authoritative count; the menu only needs a best guess
	-- for the lock text, and it is corrected on the next Rebirth event.
	return Zones.rebirthCount or 0
end

local function currentZoneName()
	local character = player.Character
	local root = character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))
	if not root then return nil end

	for _, zone in ipairs(GameConfig.zones()) do
		local dx = root.Position.X - zone.center[1]
		local dz = root.Position.Z - zone.center[3]
		if (dx * dx + dz * dz) <= (zone.radius * zone.radius) then
			return zone.name
		end
	end

	local vip = GameConfig.VIP
	local region = vip.Region
	if root.Position.X >= region.minX and root.Position.X <= region.maxX
		and root.Position.Z >= region.minZ and root.Position.Z <= region.maxZ then
		return "VIP wing"
	end
	return nil
end

local function refresh()
	if not frame or not frame.Visible then return end

	MenuUi.clearList(frame)

	local size = sizeValue()
	local count = rebirths()

	MenuUi.addSection(frame, "Rarity zones")

	for _, zone in ipairs(GameConfig.zones()) do
		local rarity = GameConfig.RARITIES[zone.rarity]
		local reason = GameConfig.zoneLockReason(zone, size, count)
		local unlocked = reason == ""

		MenuUi.addRow(frame, {
			info = ('<font color="rgb(%d,%d,%d)">%s</font>'):format(
				zone.rgb[1], zone.rgb[2], zone.rgb[3], zone.name),
			sub = ("%s cubes  |  %s"):format(zone.rarity, unlocked and "Tap to travel" or reason),
			accent = unlocked and zone.color or LOCKED,
			onClick = function()
				client.fire("ZoneTeleport", zone.id)
			end,
		})
	end

	-- The VIP wing is not a dais in workspace/Zones, but it behaves like one.
	local vip = GameConfig.VIP
	local hasVip = player:GetAttribute("VIP") == true
	MenuUi.addRow(frame, {
		info = ('<font color="rgb(255,205,90)">VIP wing</font>'),
		sub = hasVip and ("%s+ cubes  |  Tap to travel"):format(vip.RarityFloor)
			or ("%s+ cubes  |  VIP gamepass required"):format(vip.RarityFloor),
		accent = hasVip and OPEN or VIP_COLOR,
		onClick = function()
			client.fire("ZoneTeleport", vip.ZoneId)
		end,
	})

	if statusLabel then
		local here = currentZoneName()
		statusLabel.Text = here and ("You are in: %s"):format(here) or "You are in the open arena"
	end
end
Zones.refresh = refresh

local function watchPosition()
	if watching then return end
	watching = true
	task.spawn(function()
		while frame and frame.Parent do
			task.wait(0.5)
			if not frame.Visible then continue end
			if statusLabel then
				local here = currentZoneName()
				statusLabel.Text = here and ("You are in: %s"):format(here) or "You are in the open arena"
			end
		end
		watching = false
	end)
end

function Zones.Init(c)
	client = c
	player = c.Player
	frame = MenuUi.frame(FRAME_NAME)
	if not frame then return false end

	statusLabel = frame:FindFirstChild("Status")

	MenuUi.Register(FRAME_NAME, {
		onOpen = function()
			refresh()
			watchPosition()
		end,
	})

	client.on("ZoneTeleport", function(zoneId, allowed, reason)
		refresh()
		if not allowed and reason and reason ~= "" then
			client.Notify(("Travel refused: %s"):format(reason), "bad")
		end
	end)

	client.on("Rebirth", function(rebirthCount)
		Zones.rebirthCount = tonumber(rebirthCount) or 0
		if frame.Visible then refresh() end
	end)

	-- Size unlocks zones, so keep the lock text current while open.
	local function hookSize(size)
		size.Changed:Connect(function()
			if frame.Visible then refresh() end
		end)
	end
	local stats = player:FindFirstChild("leaderstats")
	local size = stats and stats:FindFirstChild("Size")
	if size then
		hookSize(size)
	else
		task.spawn(function()
			local s = player:WaitForChild("leaderstats", 60)
			local v = s and s:WaitForChild("Size", 10)
			if v then hookSize(v) end
		end)
	end

	return true
end

return Zones
