local collection_service = game:GetService("CollectionService")
local GUI_service = game:GetService("GuiService")
local workspace_service = game:GetService("Workspace")

local scale_component_to_base_resolution: {[UIScale]: Vector2} = {}
-- Required property `AbsoluteContentSize` is not in `UILayout` superclass.
type scrolling_frame_layout_component = UIGridStyleLayout | UIListLayout
local layout_component_to_rescaling_connection: {[scrolling_frame_layout_component]: RBXScriptConnection?} = {}

local camera = workspace_service:FindFirstChild("Camera")
local actual_viewport_size: Vector2? = nil

local has_initialized = false

local function rescale(scale_component: UIScale, base_resolution: Vector2)
	assert(actual_viewport_size ~= nil)
	scale_component.Scale = 1 / math.max(base_resolution.X / actual_viewport_size.X, base_resolution.Y / actual_viewport_size.Y)
end

local function rescale_all()
	local top_inset, bottom_inset = GUI_service:GetGuiInset()
	actual_viewport_size = camera.ViewportSize - top_inset - bottom_inset

	for scale_component, base_resolution in scale_component_to_base_resolution do
		rescale(scale_component, base_resolution)
	end
end

local function register_scale(component: UIScale)
	local base_resolution = component:GetAttribute("base_resolution")
	assert(typeof(base_resolution) == "Vector2")
	scale_component_to_base_resolution[component] = base_resolution
end

local function register_scrolling_frame_layout_component(layout_component: scrolling_frame_layout_component)
	local scale_component_referral = layout_component:FindFirstChild("scale_component_referral")
	assert(scale_component_referral:IsA("ObjectValue"))
	assert(scale_component_referral.Value ~= nil)
	assert(scale_component_referral.Value:IsA("UIScale"))
	local scale_component: UIScale = scale_component_referral.Value
	local scrolling_frame = layout_component.Parent
	assert(scrolling_frame ~= nil)
	assert(scrolling_frame:IsA("ScrollingFrame"))
	-- https://devforum.roblox.com/t/automaticcanvassize-working-with-uilistlayout-and-uiscale-causes-wrong-automatic-size/1334861.
	layout_component_to_rescaling_connection[layout_component] = layout_component:GetPropertyChangedSignal(
		"AbsoluteContentSize"
	):Connect(function()
		scrolling_frame.CanvasSize = UDim2.fromOffset(
			layout_component.AbsoluteContentSize.X / scale_component.Scale,
			layout_component.AbsoluteContentSize.Y / scale_component.Scale
		)
	end)
	scrolling_frame.CanvasSize = UDim2.fromOffset(
		layout_component.AbsoluteContentSize.X / scale_component.Scale,
		layout_component.AbsoluteContentSize.Y / scale_component.Scale
	)
	print('set')
end

local function initialize()
	assert(has_initialized == false)
	has_initialized = true

	collection_service:GetInstanceAddedSignal("scale_component"):Connect(function(object: Instance)
		assert(object:IsA("UIScale"))

		register_scale(object)
		rescale(object, scale_component_to_base_resolution[object])
	end)
	collection_service:GetInstanceRemovedSignal("scale_component"):Connect(function(object: Instance)
		assert(object:IsA("UIScale"))
		scale_component_to_base_resolution[object] = nil
	end)

	for _, object in collection_service:GetTagged("scale_component") do
		assert(object:IsA("UIScale"))

		register_scale(object)
	end

	collection_service:GetInstanceAddedSignal("scrolling_frame_layout_component"):Connect(function(object: Instance)
		assert(object:IsA("UIGridStyleLayout") or object:IsA("UIListLayout"))
		register_scrolling_frame_layout_component(object)
	end)
	for _, object in collection_service:GetTagged("scrolling_frame_layout_component") do
		assert(object:IsA("UIGridStyleLayout") or object:IsA("UIListLayout"))
		register_scrolling_frame_layout_component(object)
	end
	collection_service:GetInstanceRemovedSignal("scrolling_frame_layout_component"):Connect(function(object: Instance)
		assert(object:IsA("UIGridStyleLayout") or object:IsA("UIListLayout"))
		local rescaling_connection = layout_component_to_rescaling_connection[object]
		assert(rescaling_connection ~= nil)
		rescaling_connection:Disconnect()
		layout_component_to_rescaling_connection[object] = nil
	end)

	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale_all)
	rescale_all()
end

initialize()