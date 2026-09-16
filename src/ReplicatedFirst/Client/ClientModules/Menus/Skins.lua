-- Skins menu. The catalogue is GameData/Skins (Color, Unlock, Req, Order) and
-- ownership comes from the server through Events.SkinList, so nothing here can
-- be spoofed into wearing a skin it does not own.
local Skins = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local UiModule = require(ReplicatedStorage:WaitForChild("UiModule"))
local MenuUi = require(script.Parent:WaitForChild("MenuUi"))

local FRAME_NAME = "Skins"
local EQUIPPED = Color3.fromRGB(110, 220, 140)

local client, player, frame
local owned = {}
local equipped = ""

local SECTIONS = {
	{ key = "start", title = "Starting skin" },
	{ key = "cash", title = "Cash shop" },
	{ key = "size", title = "Size milestones" },
	{ key = "rebirth", title = "Rebirth rewards" },
}

local function sizeValue()
	local stats = player:FindFirstChild("leaderstats")
	local size = stats and stats:FindFirstChild("Size")
	return size and size.Value or 0
end

local function statusOf(skin)
	if equipped == skin.id then
		return "Equipped", true
	end
	if owned[skin.id] then
		return "Tap to equip", true
	end
	if skin.unlock == "cash" then
		local price = skin.req or 0
		local cash = 0
		local stats = player:FindFirstChild("leaderstats")
		local cashValue = stats and stats:FindFirstChild("Cash")
		if cashValue then cash = cashValue.Value end
		return ("Buy for %s Cash%s"):format(UiModule.Format(price), cash >= price and "" or " (not enough)"), true
	end
	if skin.unlock == "size" then
		return ("Reach Size %s (%s now)"):format(UiModule.Format(skin.req or 0), UiModule.Format(sizeValue())), false
	end
	if skin.unlock == "rebirth" then
		return ("Rebirth %d time%s"):format(skin.req or 1, (skin.req or 1) == 1 and "" or "s"), false
	end
	return "Locked", false
end

local function refresh()
	if not frame or not frame.Visible then return end

	MenuUi.clearList(frame)

	for _, section in ipairs(SECTIONS) do
		local rows = {}
		for _, skin in ipairs(GameConfig.SKINS) do
			if skin.unlock == section.key then
				table.insert(rows, skin)
			end
		end
		if #rows == 0 then continue end

		MenuUi.addSection(frame, section.title)
		for _, skin in ipairs(rows) do
			local status, actionable = statusOf(skin)
			local rgb = skin.rgb or { 255, 255, 255 }
			MenuUi.addRow(frame, {
				info = ('<font color="rgb(%d,%d,%d)">%s</font>'):format(rgb[1], rgb[2], rgb[3], skin.id),
				sub = status,
				accent = equipped == skin.id and EQUIPPED or skin.color,
				onClick = actionable and function()
					if owned[skin.id] then
						client.fire("EquipSkin", skin.id)
					else
						client.fire("BuySkin", skin.id)
					end
				end or nil,
			})
		end
	end
end
Skins.refresh = refresh

function Skins.Init(c)
	client = c
	player = c.Player
	frame = MenuUi.frame(FRAME_NAME)
	if not frame then return false end

	MenuUi.Register(FRAME_NAME, {
		onOpen = refresh,
	})

	client.on("SkinList", function(ownedList, currentSkin)
		owned = {}
		if typeof(ownedList) == "table" then
			for _, id in ipairs(ownedList) do
				owned[tostring(id)] = true
			end
		end
		equipped = tostring(currentSkin or "")
		refresh()
	end)

	-- Prices are compared against live cash, so refresh while the menu is open.
	local stats = player:FindFirstChild("leaderstats")
	local function hook(values)
		for _, value in ipairs(values) do
			value.Changed:Connect(function()
				if frame.Visible then refresh() end
			end)
		end
	end
	if stats then
		local values = {}
		for _, name in ipairs({ "Cash", "Size" }) do
			local value = stats:FindFirstChild(name)
			if value then table.insert(values, value) end
		end
		hook(values)
	else
		task.spawn(function()
			local s = player:WaitForChild("leaderstats", 60)
			if s then
				local values = {}
				for _, name in ipairs({ "Cash", "Size" }) do
					local v = s:WaitForChild(name, 10)
					if v then table.insert(values, v) end
				end
				hook(values)
			end
		end)
	end

	return true
end

return Skins
