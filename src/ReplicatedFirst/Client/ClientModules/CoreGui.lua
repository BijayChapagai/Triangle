-- CoreGui configuration: what Roblox's built-in UI is allowed to show.
--
-- This replaces the old NoResetCharacter LocalScript, which spun a
-- `repeat task.wait(1) until success` loop forever and printed on every join.
-- SetCore legitimately fails before the core UI exists, so it is retried a
-- bounded number of times and then left alone.
local CoreGui = {}

local StarterGui = game:GetService("StarterGui")

-- Core GUIs to hide: no tools in this game, and death is handled by our own
-- screen, so the built-in health bar is redundant.
local DISABLE = {
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.Health,
}

local ENABLE = {
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.Chat,
}

local function applyCore(name, value, tries)
	for _ = 1, (tries or 10) do
		local ok = pcall(function()
			StarterGui:SetCore(name, value)
		end)
		if ok then return true end
		task.wait(0.5)
	end
	warn(("[CoreGui] could not set %s = %s"):format(tostring(name), tostring(value)))
	return false
end

local function applyEnabled(coreGuiType, enabled, tries)
	for _ = 1, (tries or 10) do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(coreGuiType, enabled)
		end)
		if ok then return true end
		task.wait(0.5)
	end
	warn(("[CoreGui] could not set %s enabled = %s"):format(tostring(coreGuiType), tostring(enabled)))
	return false
end

function CoreGui.Init(client)
	-- The reset button must be off: this game assigns player.Character itself, and
	-- the built-in reset would destroy the cube outside the respawn flow.
	task.spawn(function()
		applyCore("ResetButtonCallback", false)
	end)

	task.spawn(function()
		for _, coreGuiType in ipairs(DISABLE) do
			applyEnabled(coreGuiType, false)
		end
		for _, coreGuiType in ipairs(ENABLE) do
			applyEnabled(coreGuiType, true)
		end
	end)

	return true
end

return CoreGui
