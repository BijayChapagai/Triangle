-- HUD: cash, size, the toggle buttons and the small "juice" animations that
-- live in the Buttons ScreenGui.
--
-- Everything is bound by name from the asset, so moving or renaming an element
-- in Studio degrades only that element (a warning, not a dead script). All the
-- ids come from GameData: the old HUD buttons prompted 976647371/974979534,
-- which are not the passes the server honours, so purchases did nothing.
local Hud = {}

local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local UiModule = require(ReplicatedStorage:WaitForChild("UiModule"))

local MUSIC_VOLUME = 0.7

local player
local buttonsGui, currencyGui

-- Music volume is a preference (Settings menu), so it lives at module scope and
-- is applied whenever the sound shows up or the player changes it.
local musicSound
local musicVolume = MUSIC_VOLUME

local function applyMusic()
	if not musicSound or not musicSound.Parent then
		local folder = workspace:FindFirstChild("MusicFolder")
		musicSound = folder and folder:FindFirstChild("Music")
	end
	if musicSound and musicSound:IsA("Sound") then
		musicSound.Volume = musicVolume
	end
end

function Hud.SetMusicVolume(volume)
	musicVolume = math.clamp(tonumber(volume) or MUSIC_VOLUME, 0, 1)
	applyMusic()
end

-- Resolve "A/B/C" inside a container without exploding on a missing link.
local function resolve(root, path)
	local current = root
	for name in string.gmatch(path, "[^/]+") do
		current = current and current:FindFirstChild(name)
	end
	if not current and root then
		warn(("[Hud] %s is missing from the place"):format(path))
	end
	return current
end

local function setText(label, text)
	if label and label:IsA("TextLabel") or (label and label:IsA("TextButton")) then
		label.Text = text
	end
end

--// ------------------------------------------------------------ cash and size
local function hookStats()
	local stats = player:WaitForChild("leaderstats", 60)
	if not stats then return end

	local cashLabel = resolve(currencyGui, "Cash/Label")
	local sizeLabel = resolve(buttonsGui, "SizeCounter/CurrentSize")

	local cash = stats:FindFirstChild("Cash")
	if cash and cashLabel then
		local update = function() cashLabel.Text = UiModule.Format(cash.Value) end
		cash.Changed:Connect(update)
		update()
	end

	local size = stats:FindFirstChild("Size")
	if size and sizeLabel then
		-- The old label watched a "Value" attribute on the character that nothing
		-- ever set (and called Discconect on a nil connection), so it stayed at 0.
		local update = function() sizeLabel.Text = UiModule.Format(size.Value) end
		size.Changed:Connect(update)
		update()
	end
end

--// --------------------------------------------------------------- autofarm
local function hookAutoFarm()
	local button = resolve(buttonsGui, "AutoFarm")
	if not button or not button:IsA("GuiButton") then return end
	UiModule.Animate(button)

	local label = button:FindFirstChildOfClass("TextLabel")
	local enabled = false

	local function paint()
		local text = enabled and "Auto Farm: ON" or "Auto Farm: OFF"
		setText(button, text)
		if label then label.Text = text end
		if button:IsA("TextButton") then
			button.BackgroundColor3 = enabled and Color3.fromRGB(60, 190, 110) or Color3.fromRGB(200, 70, 70)
		end
	end
	paint()

	button.Activated:Connect(function()
		enabled = not enabled
		paint()
		Hud.client.fire("AutoFarm", enabled)
	end)
end

--// -------------------------------------------------------------- kill all
local function hookKillAll()
	local button = resolve(buttonsGui, "KillAllButton")
	if not button then return end
	UiModule.Animate(button)

	local sound = button:FindFirstChild("Toggle")
	local product = GameConfig.getProductByKind("killall")

	button.MouseButton1Click:Connect(function()
		if sound and sound:IsA("Sound") then sound:Play() end
		if not product then
			Hud.client.Notify("The Kill All product is not configured.", "bad")
			return
		end
		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(player, product.productId)
		end)
		if not ok then warn("[Hud] kill all prompt failed: " .. tostring(err)) end
	end)
end

--// ----------------------------------------------------------- gamepass hud
-- { button path, pass kind, owned text }
local PASS_BUTTONS = {
	{ "2xCash", "cash", "OWNED" },
	{ "2xSpeed", "speed", "OWNED" },
}

local function ownedLabel(button)
	return button:FindFirstChildOfClass("TextLabel")
end

local function markOwned(button, text)
	setText(button, text)
	local label = ownedLabel(button)
	if label then label.Text = text end
	if button:IsA("TextButton") then
		button.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
	end
end

local function pulseImage(button)
	-- The image inside these buttons bobs every few seconds to draw the eye. It
	-- used to run `while true wait(5)` forever even when hidden or after the
	-- pass was owned; now it stops when it is no longer useful.
	local image = button:FindFirstChild("ImageLabel")
	if not image then return end

	local baseSize = image.Size
	local bigSize = baseSize + UDim2.new(0.18, 0, 0.18, 0)

	task.spawn(function()
		while image.Parent and button.Parent do
			task.wait(5)
			if not button.Visible then continue end
			if player:GetAttribute("2xCash") and button.Name == "2xCash" then break end
			if player:GetAttribute("2xSpeed") and button.Name == "2xSpeed" then break end

			local up = TweenService:Create(image, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = bigSize, Rotation = 12,
			})
			up:Play()
			up.Completed:Wait()
			local down = TweenService:Create(image, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = baseSize, Rotation = 0,
			})
			down:Play()
			down.Completed:Wait()
		end
	end)
end

local function hookPassButtons()
	for _, entry in ipairs(PASS_BUTTONS) do
		local button = resolve(buttonsGui, entry[1])
		if not button then continue end
		UiModule.Animate(button)

		local kind, ownedText = entry[2], entry[3]
		local passId = GameConfig.passId(kind)
		local attribute = (kind == "cash") and "2xMoney" or "2xSpeed"

		if player:GetAttribute(attribute) then
			markOwned(button, ownedText)
		else
			pulseImage(button)
		end

		button.MouseButton1Click:Connect(function()
			if player:GetAttribute(attribute) then return end
			if not passId then
				Hud.client.Notify("This pass is not configured.", "bad")
				return
			end
			local ok, err = pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, passId)
			end)
			if not ok then warn("[Hud] pass prompt failed: " .. tostring(err)) end
		end)

		-- The server sets the attribute on join and after a purchase.
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if player:GetAttribute(attribute) then
				markOwned(button, ownedText)
			end
		end)
	end
end

local function productForButton(button)
	-- Prefer the ProductId attribute that ships on the button (editable in
	-- Studio), then fall back to matching a configured size product by amount.
	local attributeId = tonumber(button:GetAttribute("ProductId"))
	if attributeId and GameConfig.PRODUCTS[attributeId] then
		return GameConfig.PRODUCTS[attributeId]
	end

	local wanted = tonumber(button.Name:match("%d+"))
	if wanted then
		for _, def in ipairs(GameConfig.PRODUCT_LIST) do
			if def.kind == "size" and def.amount == wanted then
				return def
			end
		end
	end
	return nil
end

local function hookStore()
	local store = resolve(buttonsGui, "Store")
	if not store then return end

	for _, button in ipairs(store:GetChildren()) do
		if button:IsA("GuiButton") then
			UiModule.Animate(button)
			button.Activated:Connect(function()
				local product = productForButton(button)
				if not product then
					Hud.client.Notify(("No product is configured for %s."):format(button.Name), "bad")
					return
				end
				local ok, err = pcall(function()
					MarketplaceService:PromptProductPurchase(player, product.productId)
				end)
				if not ok then warn("[Hud] product prompt failed: " .. tostring(err)) end
			end)
		end
	end
end

--// --------------------------------------------------------------- rewards
-- Nudge the Rewards button while an unclaimed playtime gift is waiting.
local function hookRewardsNudge()
	local button = resolve(buttonsGui, "Rewards")
	if not button then return end
	UiModule.Animate(button)

	local image = button:FindFirstChild("ImageLabel")

	local function claimable()
		local playtime = player:GetAttribute("PlayerTime") or 0
		for id, gift in pairs(GameConfig.GIFTS) do
			-- The server records claims in the profile; the CurrentGift attribute
			-- mirrors the highest claimed id, so anything above it is fair game.
			if playtime >= (gift.RequiredTime or 0) and id > (player:GetAttribute("CurrentGift") or 0) then
				return true
			end
		end
		return false
	end

	task.spawn(function()
		while button.Parent do
			task.wait(2)
			if not claimable() or not button.Visible then continue end
			if image then
				local base = image.Rotation
				local tween = TweenService:Create(image, TweenInfo.new(0.25, Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out, 3, true), { Rotation = base + 14 })
				tween:Play()
				tween.Completed:Wait()
			else
				task.wait(1)
			end
		end
	end)
end

--// ------------------------------------------------------------------ init
function Hud.Init(client)
	Hud.client = client
	player = client.Player

	buttonsGui = client.gui("Buttons")
	currencyGui = client.gui("Currency")
	if not buttonsGui then return false end

	task.spawn(hookStats)
	hookAutoFarm()
	hookKillAll()
	hookPassButtons()
	hookStore()
	hookRewardsNudge()

	-- Volume is a preference: the Settings menu owns it, and 0 is the mute.
	Hud.SetMusicVolume(client.Prefs and client.Prefs.MusicVolume)
	client.onPref("MusicVolume", function(value) Hud.SetMusicVolume(value) end)

	return true
end

return Hud
