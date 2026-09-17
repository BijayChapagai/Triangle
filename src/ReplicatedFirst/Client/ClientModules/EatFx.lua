-- EatFx: what eating feels like.
--
-- Popups already flies the "+Size" number the moment leaderstats changes, so the
-- amount is covered. What a number cannot say is which tier you ate, or that you
-- have eaten nine in a row. The server sends FoodEaten(rarity, value) on every
-- pickup - it owns both numbers, so a client cannot inflate its own feedback -
-- and this turns them into three things:
--   * a chain counter (StarterGui/Combo) painted in the colour of the cube that
--     extended it, popping on each hit and fading when the window closes
--   * a camera punch scaled by tier and by chain length. Common gets none: it is
--     eaten every couple of seconds and a shake that often is sickening
--   * the shipped UI blip, pitched up per tier, so a Mythic sounds bigger than a
--     Common without shipping a single new audio asset
local EatFx = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local Camera = require(script.Parent:WaitForChild("Camera"))

local COMBO_GUI = "Combo"
local MIN_CHAIN = 2 -- "x1" is not a chain; the +Size popup already said it
local POP_TIME = 0.13
local POP_SCALE = 1.35
local FADE_TIME = 0.35
local MIN_VOLUME = 0.4
local MAX_VOLUME = 1
local MIN_PITCH = 0.5
local MAX_PITCH = 3 -- outside this a Sound stops being a blip and starts being noise

local client
local label, pop, blip
local chain = 0
local lastEat = 0
local fadeThread = nil
local fadeTween = nil
local reducedMotion = false

-- StarterGui is cloned into PlayerGui on spawn, which can be after this module
-- boots, so the lookup is lazy and self-healing rather than fatal at Init.
local function resolve()
	if label then return label end
	local playerGui = client and client.playerGui and client.playerGui()
	local gui = playerGui and playerGui:FindFirstChild(COMBO_GUI)
	label = (gui and gui:FindFirstChild("Label")) or nil
	pop = (label and label:FindFirstChild("Pop")) or nil
	return label
end

local function playBlip(value, pitch)
	if not blip then return end
	-- One Sound instance, retriggered: overlapping plays of the same instance cut
	-- each other off, so wind it back the way UiModule does for clicks. The volume
	-- tracks the value the server actually awarded, so a fat cube is a loud one.
	blip.PlaybackSpeed = math.clamp(pitch, MIN_PITCH, MAX_PITCH)
	blip.Volume = math.clamp(MIN_VOLUME + (tonumber(value) or 0) / 2000, MIN_VOLUME, MAX_VOLUME)
	blip.TimePosition = 0
	blip:Play()
end

local function hideChain()
	if not label then return end
	label.Visible = false
	label.Text = ""
	chain = 0
end

local function cancelFade()
	if fadeThread then
		task.cancel(fadeThread)
		fadeThread = nil
	end
	if fadeTween then
		fadeTween:Cancel() -- Cancelled tweens never fire Completed, so this cannot eat a live chain
		fadeTween = nil
	end
end

local function showChain(rarity)
	label.Text = "x" .. tostring(chain)
	label.TextColor3 = rarity.color
	label.TextTransparency = 0
	label.Visible = true
	if pop and not reducedMotion then
		pop.Scale = POP_SCALE
		TweenService:Create(pop, TweenInfo.new(POP_TIME, Enum.EasingStyle.Back,
			Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function scheduleFade(window)
	fadeThread = task.delay(window, function()
		fadeThread = nil
		if not label or chain < MIN_CHAIN then return end
		fadeTween = TweenService:Create(label, TweenInfo.new(FADE_TIME), { TextTransparency = 1 })
		fadeTween.Completed:Connect(function()
			fadeTween = nil
			hideChain()
		end)
		fadeTween:Play()
	end)
end

-- Server-driven: the rarity name and the value it awarded, nothing the client
-- gets to choose.
function EatFx.onEaten(rarityName, value)
	local rarity = GameConfig.RARITIES[tostring(rarityName or "")]
	if not rarity then return end
	local cfg = GameConfig.COMBO

	local now = os.clock()
	chain = (now - lastEat <= cfg.window) and (chain + 1) or 1
	lastEat = now

	-- The tier decides whether this cube is worth a kick at all, the chain decides
	-- how hard. Camera.punch keeps its own cooldown, so a fast chain reads as a few
	-- strong punches instead of a strobe.
	local steps = math.min(chain - 1, cfg.maxSteps)
	local punch = (rarity.punch or 0) * (1 + steps * cfg.punchStep)
	if punch > 0 then
		Camera.punch((tonumber(GameConfig.get("CameraFovPunch", 6)) or 6) * punch)
	end

	playBlip(value, (rarity.pitch or 1) + steps * cfg.pitchStep)

	if chain >= MIN_CHAIN and resolve() then
		cancelFade()
		showChain(rarity)
		scheduleFade(cfg.window)
	end
end

function EatFx.Init(c)
	client = c
	reducedMotion = client.Prefs and client.Prefs.ReducedMotion == true
	if client.onPref then
		client.onPref("ReducedMotion", function(value)
			reducedMotion = value == true
		end)
	end

	-- Reuse the shipped UI blip rather than adding audio: it is a Sound instance
	-- shipping inside the UiModule ModuleScript, reachable without editing it.
	local uiModule = ReplicatedStorage:FindFirstChild("UiModule")
	blip = (uiModule and uiModule:FindFirstChild("clickSound")) or nil
	if not blip then
		warn("[EatFx] UiModule/clickSound is missing - eating will be silent")
	end

	resolve()
	if not label then
		warn("[EatFx] StarterGui/Combo/Label is missing - the chain counter will not show")
	end

	if client.on then
		client.on("FoodEaten", EatFx.onEaten)
	end
	return label ~= nil and blip ~= nil
end

return EatFx
