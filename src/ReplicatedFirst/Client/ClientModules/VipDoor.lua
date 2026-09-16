-- VIP door. Cosmetic half only: the server owns the real gate (zone 6 food is
-- refused unless the VIP attribute is set), so even a client that lies about
-- ownership gains nothing but walking through a door.
--
-- The door is an asset: workspace/VIPDoor (Part, CanCollide blocks non-owners)
-- with a SurfaceGui (TextLabel, ImageLabel, Buy) and ClickPart > ClickDetector.
-- Clicking prompts the gamepass server side; this module keeps the visuals in
-- sync with the VIP attribute the server sets on join and after a purchase.
local VipDoor = {}

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))

local door, buyLabel, signLabel

local function setOpen(client, open)
	if door then
		-- Parts only: a Model replacement would have neither property.
		if door:IsA("BasePart") then
			door.CanCollide = not open
			door.Transparency = open and math.max(door.Transparency, 0.35) or 0
		else
			for _, part in ipairs(door:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = not open
				end
			end
		end
	end
	if buyLabel then
		buyLabel.Text = open and "OPEN" or "VIP"
	end
	if signLabel then
		signLabel.Text = open and "Welcome to the VIP wing" or "VIP wing - gamepass required"
	end
end

local function applyFromAttribute(client, player)
	setOpen(client, player:GetAttribute("VIP") == true)
end

function VipDoor.Init(client)
	local player = client and client.Player

	-- The door is part of the map and may still be replicating.
	door = workspace:WaitForChild("VIPDoor", 30)
	if not door then
		warn("[VipDoor] workspace.VIPDoor is missing - the VIP wing stays closed")
		return false
	end

	local surface = door:FindFirstChildOfClass("SurfaceGui")
	buyLabel = surface and surface:FindFirstChild("Buy")
	signLabel = surface and surface:FindFirstChildOfClass("TextLabel")

	applyFromAttribute(client, player)
	player:GetAttributeChangedSignal("VIP"):Connect(function()
		applyFromAttribute(client, player)
	end)

	-- The server also sets the attribute on purchase; this makes the door open the
	-- instant the receipt lands rather than waiting for replication.
	local passId = GameConfig.passId("vip")
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchaser, purchasedPassId, purchased)
		if purchaser ~= player or not purchased then return end
		if passId and purchasedPassId ~= passId then return end
		player:SetAttribute("VIP", true)
		setOpen(client, true)
		if client.Notify then
			client.Notify("VIP unlocked - the door is open.", "good")
		end
	end)

	return true
end

return VipDoor
