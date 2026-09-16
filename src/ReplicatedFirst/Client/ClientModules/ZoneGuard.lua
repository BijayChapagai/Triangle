-- Locked zone warning: a red edge plus the reason, while the player is standing
-- in a zone they have not unlocked.
--
-- The server already refuses the food and the teleport. This exists so the gate
-- does not feel arbitrary: the dais sign states the requirement, and standing on
-- the dais says the same thing in the middle of the screen. Both the tint and the
-- label are asset (StarterGui/ZoneWarn), so the look is a Studio edit.
local ZoneGuard = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))

local CHECK_INTERVAL = 0.4

local client, player, tint, label
local showing -- name of the zone being warned about, or nil

local function sizeValue()
	local stats = player:FindFirstChild("leaderstats")
	local size = stats and stats:FindFirstChild("Size")
	return size and size.Value or 0
end

-- Name of the zone a position is inside plus why it is locked ("" when open).
-- The VIP wing is a pseudo-zone, so it is tested by region rather than radius.
local function zoneAt(position)
	for _, zone in ipairs(GameConfig.zones()) do
		local dx = position.X - zone.center[1]
		local dz = position.Z - zone.center[3]
		if (dx * dx + dz * dz) <= (zone.radius * zone.radius) then
			return zone.name, GameConfig.zoneLockReason(zone, sizeValue(),
				player:GetAttribute("Rebirths") or 0)
		end
	end

	local region = GameConfig.VIP.Region
	if position.X >= region.minX and position.X <= region.maxX
		and position.Z >= region.minZ and position.Z <= region.maxZ then
		if player:GetAttribute("VIP") then
			return "VIP wing", ""
		end
		return "VIP wing", "VIP gamepass required"
	end

	return nil, ""
end

local function hide()
	if not showing then return end
	showing = nil
	if tint then tint.Visible = false end
end

local function show(name, reason)
	local isNew = showing ~= name
	showing = name
	if tint then tint.Visible = true end
	if label then label.Text = ("%s: %s"):format(name, reason) end
	-- Toast only on the way in: repeating it every check would bury the feed.
	if isNew then
		client.Notify(("%s is locked - %s"):format(name, reason), "bad")
	end
end

function ZoneGuard.Init(c)
	client = c
	player = c.Player

	local gui = client.gui("ZoneWarn")
	tint = gui and gui:FindFirstChild("Tint")
	label = tint and tint:FindFirstChild("Label")
	if not tint then
		warn("[ZoneGuard] StarterGui/ZoneWarn is missing from the place - warning disabled")
		return false
	end
	tint.Visible = false

	task.spawn(function()
		while player.Parent do
			task.wait(CHECK_INTERVAL)

			local character = player.Character
			local root = character and (character.PrimaryPart
				or character:FindFirstChild("HumanoidRootPart"))
			if not root or player:GetAttribute("Dead") then
				hide()
				continue
			end

			-- Requirements are re-read every tick, so unlocking while standing on
			-- the dais (a rebirth, a size milestone, buying VIP) clears the warning
			-- without the player having to step off.
			local name, reason = zoneAt(root.Position)
			if name and reason ~= "" then
				show(name, reason)
			else
				hide()
			end
		end
	end)

	return true
end

return ZoneGuard
