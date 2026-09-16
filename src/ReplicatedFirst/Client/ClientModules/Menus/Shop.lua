-- Shop menu: gamepasses.
--
-- Two frames sell passes and both are wired here:
--   Frames/Shop > ScrollingFrame > {VIP, x2 Cash, x2 Speed} > Buy (ImageButton)
--   Frames/VIP  > Purchase (TextButton)
-- The pass ids come from GameData/Gamepasses. The old scripts hard-coded them and
-- the HUD versions pointed at ids the server never honoured, so paying did
-- nothing. Owned passes are dimmed and stop prompting.
local Shop = {}

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local UiModule = require(ReplicatedStorage:WaitForChild("UiModule"))
local MenuUi = require(script.Parent:WaitForChild("MenuUi"))

-- Frame/item name -> pass kind, and the attribute the server sets for owners.
local PASS_ITEMS = {
	{ frame = "Shop", item = "VIP", button = "Buy", kind = "vip", attribute = "VIP" },
	{ frame = "Shop", item = "x2 Cash", button = "Buy", kind = "cash", attribute = "2xMoney" },
	{ frame = "Shop", item = "x2 Speed", button = "Buy", kind = "speed", attribute = "2xSpeed" },
	{ frame = "VIP", item = "Purchase", button = nil, kind = "vip", attribute = "VIP", text = true },
}

local client, player

local function markOwned(entry, button)
	if entry.text and button:IsA("TextButton") then
		button.Text = "OWNED"
	end
	-- No new GUI is created: dimming the shipped button is enough to read as
	-- "you have this", and AutoButtonColor/Active stop it looking pressable.
	if button:IsA("ImageButton") then
		button.ImageTransparency = 0.55
	end
	button.AutoButtonColor = false
	button.Active = false
end

local function wire(entry)
	local frame = MenuUi.frame(entry.frame)
	if not frame then return end

	local holder = entry.item and frame:FindFirstChild(entry.item)
	-- Frames/Shop keeps its items inside a ScrollingFrame.
	if not holder then
		local scroll = frame:FindFirstChildOfClass("ScrollingFrame")
		holder = scroll and scroll:FindFirstChild(entry.item)
	end
	if not holder then
		warn(("[Shop] %s/%s is missing from the place"):format(entry.frame, tostring(entry.item)))
		return
	end

	local button = entry.button and holder:FindFirstChild(entry.button) or holder
	if not button or not button:IsA("GuiButton") then
		warn(("[Shop] no button in %s/%s"):format(entry.frame, tostring(entry.item)))
		return
	end

	UiModule.Animate(button)

	local passId = GameConfig.passId(entry.kind)

	if player:GetAttribute(entry.attribute) then
		markOwned(entry, button)
	end

	player:GetAttributeChangedSignal(entry.attribute):Connect(function()
		if player:GetAttribute(entry.attribute) then
			markOwned(entry, button)
		end
	end)

	button.Activated:Connect(function()
		if player:GetAttribute(entry.attribute) then
			client.Notify("You already own this.", "info")
			return
		end
		if not passId then
			client.Notify("This pass is not configured in GameData.", "bad")
			return
		end
		local ok, err = pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, passId)
		end)
		if not ok then warn("[Shop] prompt failed: " .. tostring(err)) end
	end)
end

function Shop.Init(c)
	client = c
	player = c.Player

	MenuUi.Register("Shop", {})
	MenuUi.Register("VIP", {})

	for _, entry in ipairs(PASS_ITEMS) do
		local ok, err = pcall(wire, entry)
		if not ok then warn("[Shop] wiring failed: " .. tostring(err)) end
	end

	-- Purchases land as attributes from the server; also reflect them instantly.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchaser, passId, purchased)
		if purchaser ~= player or not purchased then return end
		for _, entry in ipairs(PASS_ITEMS) do
			if GameConfig.passId(entry.kind) == passId then
				player:SetAttribute(entry.attribute, true)
			end
		end
	end)

	return true
end

return Shop
