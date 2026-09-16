-- Shop: developer products and the VIP door prompt.
--
-- Product definitions live in GameData/Products (ProductId, Kind, Amount, Label)
-- so adding a pack is a Studio edit. Every grant goes through one receipt
-- pipeline that records the PurchaseId: Roblox re-delivers a receipt whenever the
-- grant response is lost, and without that record the player gets the product
-- twice.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Progression = require(script.Parent:WaitForChild("Progression"))
local Characters = require(script.Parent:WaitForChild("Characters"))

local Shop = {}

local function grantSize(player, amount)
	local ls = player:FindFirstChild("leaderstats")
	local size = ls and ls:FindFirstChild("Size")
	if not size then return false end

	size.Value += amount
	Progression.setCubeSize(player.Character, GameConfig.visualSize(size.Value))
	Progression.applyRankText(player)
	Progression.CheckSize(player)
	return true
end

local KINDS = {
	size = function(player, product)
		local ok = grantSize(player, product.amount or 0)
		if ok then Progression.notify(player, (product.label or "Size") .. " added!", "good") end
		return ok
	end,

	killall = function(player)
		local killed = 0
		for _, other in ipairs(Players:GetPlayers()) do
			-- Everyone except the buyer: paying to kill yourself is not the product.
			if other ~= player and not other:GetAttribute("Dead") then
				-- force: a paid KillAll reaches players who are still in spawn
				-- protection, otherwise the product silently under-delivers.
				local ok = pcall(Characters.OnKill, player, other, true)
				if ok and other:GetAttribute("Dead") then killed += 1 end
			end
		end
		Progression.notify(player, ("Kill All: eliminated %d player%s.")
			:format(killed, killed == 1 and "" or "s"), "good")
		return true
	end,

	revive = function(player)
		-- Characters.Revive re-wires the Died/Touched/size hooks, the skin and the
		-- name tag. The old inline clone left the revived cube with no connections
		-- at all, so it could not eat and could not be eaten.
		local ok = Characters.Revive(player)
		if ok then Progression.notify(player, "Revived with your size kept!", "good") end
		return ok
	end,

	revenge = function(player)
		local killerId = player:GetAttribute("Killer")
		local killer = killerId and Players:GetPlayerByUserId(killerId)
		if killer and killer ~= player then
			pcall(Characters.OnKill, player, killer)
			Progression.notify(player, ("Revenge served on %s."):format(killer.Name), "good")
		else
			Progression.notify(player, "Your killer already left the server.", "bad")
		end
		-- Being dead is no fun: revenge puts you back in the game with your size.
		Characters.Revive(player)
		return true
	end,
}

local function grant(player, product)
	local handler = KINDS[product.kind]
	if not handler then
		warn(("[Shop] product %s has unknown kind %q"):format(product.id, tostring(product.kind)))
		return false
	end
	return handler(player, product) == true
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		-- Player left mid-purchase: let Roblox retry on their next join.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local product = GameConfig.PRODUCTS[receipt.ProductId]
	if not product then
		warn(("[Shop] no product definition for id %s (purchase %s)")
			:format(tostring(receipt.ProductId), tostring(receipt.PurchaseId)))
		-- Nothing can ever grant this; acknowledge it so it does not retry forever.
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local data = DataManager.Data(player)
	if not data then
		-- Data not loaded (or failed to load): retry rather than lose the grant.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	data.Receipts = data.Receipts or {}
	local purchaseId = tostring(receipt.PurchaseId or "")
	if purchaseId ~= "" and data.Receipts[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted
	end

	local ok, result = pcall(grant, player, product)
	if not ok then
		warn(("[Shop] %s failed for %s: %s"):format(product.id, player.Name, tostring(result)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if result ~= true then
		warn(("[Shop] %s could not be granted for %s right now"):format(product.id, player.Name))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	data.Receipts[purchaseId] = true
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- The VIP door used to be its own Script in Workspace; the prompt belongs with
-- the rest of the shop so the pass id comes from GameData like everything else.
local function wireVipDoor()
	local door = workspace:FindFirstChild("VIPDoor")
	local clickPart = door and door:FindFirstChild("ClickPart")
	local detector = clickPart and clickPart:FindFirstChildOfClass("ClickDetector")
	if not detector then return end

	local passId = GameConfig.passId("vip")
	detector.MouseClick:Connect(function(player)
		if not passId then return end
		if player:GetAttribute("VIP") then
			Progression.notify(player, "You already own VIP - the door is open.", "info")
			return
		end
		local ok, err = pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, passId)
		end)
		if not ok then warn("[Shop] VIP prompt failed: " .. tostring(err)) end
	end)
end

function Shop.Init()
	MarketplaceService.ProcessReceipt = processReceipt
	wireVipDoor()
end

return Shop
