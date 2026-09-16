-- Death screen: StarterGui/DeathGui > DeathFrame > Content > {Label, DeathInfo,
-- Buttons > Row1/Respawn, Row2/{Revive, Revenge}}.
--
-- Fixes over the old StarterCharacterScript:
--   * Revive/Revenge prompt the products configured in GameData. The old script
--     prompted 2662263658, which nothing defines, so the screen never closed
--     after a paid revive.
--   * Respawn waits for the server's answer instead of hiding immediately; the
--     server refuses a respawn when you are not actually dead.
--   * A killer who left the server no longer errors the handler (and with it the
--     whole death screen).
local DeathScreen = {}

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local UiModule = require(ReplicatedStorage:WaitForChild("UiModule"))

local client, player
local gui, content, deathInfo, respawnButton, reviveButton, revengeButton
local diedConnections = {}

local function hide()
	if gui then gui.Enabled = false end
end

local function sizeValue()
	local stats = player:FindFirstChild("leaderstats")
	local size = stats and stats:FindFirstChild("Size")
	return size and size.Value or 0
end

local function killerName()
	local killerId = player:GetAttribute("Killer")
	if not killerId then return nil end
	local killer = Players:GetPlayerByUserId(killerId)
	-- They may already have left; the message degrades instead of erroring.
	return killer and killer.Name or nil
end

local function prompt(kind, button)
	local product = GameConfig.getProductByKind(kind)
	if not product then
		client.Notify(("The %s product is not configured."):format(kind), "bad")
		return
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, product.productId)
	end)
	if not ok then
		warn(("[DeathScreen] %s prompt failed: %s"):format(kind, tostring(err)))
	end
	if button then button.Active = true end
end

local function show()
	if not gui then return end
	gui.Enabled = true

	local killer = killerName()
	local lost = sizeValue()

	if deathInfo then
		if killer then
			deathInfo.Text = ('You were eaten by <font color="rgb(255,90,90)">%s</font> and lost '
				.. '<font color="rgb(230,120,255)">%s</font> size!'):format(killer, UiModule.Format(lost))
		else
			deathInfo.Text = ('You were eaten by <font color="rgb(255,90,90)">the map</font> and lost '
				.. '<font color="rgb(230,120,255)">%s</font> size!'):format(UiModule.Format(lost))
		end
	end

	if revengeButton then
		local details = revengeButton:FindFirstChild("Details")
		if details then
			details.Text = killer and ("KILL: %s"):format(killer) or "KILL: nobody"
		end
		revengeButton.AutoButtonColor = killer ~= nil
	end

	if reviveButton then
		local details = reviveButton:FindFirstChild("Details")
		if details then
			details.Text = ("Keep %s size"):format(UiModule.Format(lost))
		end
	end
end

local function onCharacterAdded(character)
	hide()

	for _, conn in pairs(diedConnections) do
		if conn.Connected then conn:Disconnect() end
	end
	table.clear(diedConnections)

	local humanoid = character:WaitForChild("Humanoid", 20)
	if not humanoid then return end

	table.insert(diedConnections, humanoid.Died:Connect(function()
		-- The server hides the cube and sets the Dead attribute; we only own the UI.
		show()
	end))
end

function DeathScreen.Init(c)
	client = c
	player = c.Player

	gui = client.gui("DeathGui")
	if not gui then return false end
	content = gui:FindFirstChild("DeathFrame")
	content = content and content:FindFirstChild("Content")
	if not content then
		warn("[DeathScreen] DeathGui/DeathFrame/Content is missing")
		return false
	end

	deathInfo = content:FindFirstChild("DeathInfo")
	local buttons = content:FindFirstChild("Buttons")
	local row1 = buttons and buttons:FindFirstChild("Row1")
	local row2 = buttons and buttons:FindFirstChild("Row2")
	respawnButton = row1 and row1:FindFirstChild("Respawn")
	reviveButton = row2 and row2:FindFirstChild("Revive")
	revengeButton = row2 and row2:FindFirstChild("Revenge")

	gui.Enabled = false

	for _, button in ipairs({ respawnButton, reviveButton, revengeButton }) do
		if button then UiModule.Animate(button) end
	end

	if respawnButton then
		respawnButton.Activated:Connect(function()
			if not player:GetAttribute("Dead") then
				hide()
				return
			end
			-- The server answers Events.RespawnRequest with (ok, reason). Waiting
			-- for it means a rejected respawn cannot leave you invisible and stuck.
			respawnButton.Active = false
			client.fire("RespawnRequest")
			task.delay(3, function()
				respawnButton.Active = true
			end)
		end)
	end

	if reviveButton then
		reviveButton.Activated:Connect(function() prompt("revive", reviveButton) end)
	end
	if revengeButton then
		revengeButton.Activated:Connect(function() prompt("revenge", revengeButton) end)
	end

	client.on("RespawnRequest", function(ok, reason)
		if ok then
			hide()
		else
			if respawnButton then respawnButton.Active = true end
			client.Notify(reason ~= "" and ("Respawn refused: %s"):format(reason) or "Respawn refused.", "bad")
		end
	end)

	-- A paid revive/revenge closes the screen: the server re-spawns the character,
	-- which also hides it via CharacterAdded. Closing here keeps it instant even if
	-- the receipt is still being processed.
	local reviveProduct = GameConfig.getProductByKind("revive")
	local revengeProduct = GameConfig.getProductByKind("revenge")
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if not purchased then return end
		if userId ~= player.UserId then return end
		if (reviveProduct and productId == reviveProduct.productId)
			or (revengeProduct and productId == revengeProduct.productId) then
			hide()
		end
	end)

	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		task.spawn(onCharacterAdded, character)
	end)

	return true
end

return DeathScreen
