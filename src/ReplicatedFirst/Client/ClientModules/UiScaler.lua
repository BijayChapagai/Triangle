-- Resolution scaling for tagged UI.
--
-- Convention (from the asset, not from code):
--   * a UIScale tagged "scale_component" with a Vector2 attribute
--     "base_resolution" is scaled so its parent UI matches that design
--     resolution on any viewport;
--   * a UIListLayout/UIGridStyleLayout tagged "scrolling_frame_layout_component"
--     inside a ScrollingFrame, with an ObjectValue child
--     "scale_component_referral" pointing at that UIScale, keeps CanvasSize in
--     unscaled pixels (AutomaticCanvasSize gets this wrong under a UIScale).
--
-- Nothing in this game is tagged today, so this module is a no-op until you tag
-- something in Studio - but the original version called bare `assert()` and
-- indexed a possibly-nil Camera, which killed the whole LocalScript (and every
-- other script sharing it) the moment a tag was missing an attribute.
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")

local UiScaler = {}

local SCALE_TAG = "scale_component"
local LAYOUT_TAG = "scrolling_frame_layout_component"

local scales = {}        -- UIScale -> base resolution Vector2
local layoutConnections = {}
local viewportSize = nil
local camera = nil
local started = false
local userScale = 1     -- player preference, multiplied into every computed scale

local function rescale(scaleComponent, baseResolution)
	if not viewportSize or not baseResolution then return end
	if not scaleComponent.Parent then
		scales[scaleComponent] = nil
		return
	end
	local ratio = math.max(baseResolution.X / viewportSize.X, baseResolution.Y / viewportSize.Y)
	if ratio <= 0 then return end
	scaleComponent.Scale = userScale / ratio
end

local function rescaleAll()
	camera = workspace.CurrentCamera
	if not camera then return end

	local topInset, bottomInset = GuiService:GetGuiInset()
	viewportSize = camera.ViewportSize - topInset - bottomInset
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then return end

	for scaleComponent, baseResolution in pairs(scales) do
		rescale(scaleComponent, baseResolution)
	end
end

local function syncCanvas(layout, scaleComponent)
	local frame = layout.Parent
	if not frame or not frame:IsA("ScrollingFrame") then return end
	local scale = scaleComponent and scaleComponent.Scale
	if not scale or scale <= 0 then return end
	frame.CanvasSize = UDim2.fromOffset(
		layout.AbsoluteContentSize.X / scale,
		layout.AbsoluteContentSize.Y / scale)
end

local function registerScale(object)
	if not object:IsA("UIScale") then return end
	local baseResolution = object:GetAttribute("base_resolution")
	if typeof(baseResolution) ~= "Vector2" then
		warn(("[UiScaler] %s is tagged %q but has no Vector2 'base_resolution' attribute - skipped.")
			:format(object:GetFullName(), SCALE_TAG))
		return
	end
	scales[object] = baseResolution
	rescale(object, baseResolution)
end

local function registerLayout(layout)
	if not (layout:IsA("UIListLayout") or layout:IsA("UIGridStyleLayout")) then return end

	local referral = layout:FindFirstChild("scale_component_referral")
	if not referral or not referral:IsA("ObjectValue") then
		warn(("[UiScaler] %s is tagged %q but has no ObjectValue 'scale_component_referral' - skipped.")
			:format(layout:GetFullName(), LAYOUT_TAG))
		return
	end
	local scaleComponent = referral.Value
	if not scaleComponent or not scaleComponent:IsA("UIScale") then
		warn(("[UiScaler] %s referral does not point at a UIScale - skipped."):format(layout:GetFullName()))
		return
	end

	layoutConnections[layout] = layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		syncCanvas(layout, scaleComponent)
	end)
	syncCanvas(layout, scaleComponent)
end

-- Interface scale from the Settings menu. It multiplies the resolution-derived
-- scale instead of replacing it, so a small screen and a small preference combine
-- rather than fighting.
function UiScaler.SetUserScale(scale)
	userScale = math.clamp(tonumber(scale) or 1, 0.5, 2)
	if started then rescaleAll() end
end

function UiScaler.Init(client)
	if started then return true end
	started = true

	CollectionService:GetInstanceAddedSignal(SCALE_TAG):Connect(registerScale)
	CollectionService:GetInstanceRemovedSignal(SCALE_TAG):Connect(function(object)
		scales[object] = nil
	end)

	CollectionService:GetInstanceAddedSignal(LAYOUT_TAG):Connect(registerLayout)
	CollectionService:GetInstanceRemovedSignal(LAYOUT_TAG):Connect(function(layout)
		local connection = layoutConnections[layout]
		if connection then
			connection:Disconnect()
			layoutConnections[layout] = nil
		end
	end)

	for _, object in ipairs(CollectionService:GetTagged(SCALE_TAG)) do
		registerScale(object)
	end
	for _, layout in ipairs(CollectionService:GetTagged(LAYOUT_TAG)) do
		registerLayout(layout)
	end

	UiScaler.SetUserScale(client.Prefs and client.Prefs.UiScale)
	client.onPref("UiScale", function(value) UiScaler.SetUserScale(value) end)

	-- The camera can be missing this early (ReplicatedFirst); rescaleAll() looks
	-- it up again, and ViewportSize changes re-run it anyway.
	camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescaleAll)
	end
	rescaleAll()

	return true
end

return UiScaler
