-- Menu wiring. Every button in StarterGui.Buttons whose name matches a frame in
-- StarterGui.Frames toggles that frame (the convention the old ButtonEffects
-- script used), plus a small row/list API the individual menus build on.
--
-- This replaces one LocalScript per button/frame: adding a menu in Studio now
-- needs no script at all, and adding behaviour needs only
-- MenuUi.Register("FrameName", { onOpen = fn }).
local MenuUi = {}

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiModule = require(ReplicatedStorage:WaitForChild("UiModule"))

local client, player
local buttonsGui, framesGui
local registry = {}   -- frame name -> { onOpen = fn, onClose = fn }
local openFrame = nil

--// ------------------------------------------------------------------- lookup
function MenuUi.frame(name)
	return framesGui and framesGui:FindFirstChild(name)
end

function MenuUi.Register(name, handlers)
	registry[name] = handlers or {}
	-- Registering after Init must still work (modules are started in any order).
	if framesGui then
		local frame = MenuUi.frame(name)
		if frame and not registry[name].wired then
			MenuUi.wireFrame(name, frame)
		end
	end
end

function MenuUi.wireFrame(name, frame)
	local entry = registry[name] or {}
	entry.wired = true
	registry[name] = entry

	local close = frame:FindFirstChild("Close")
	if close and close:IsA("GuiButton") then
		UiModule.Animate(close)
		close.Activated:Connect(function()
			MenuUi.Close(name)
		end)
	end
end

--// ------------------------------------------------------------------- open/close
function MenuUi.Toggle(name)
	local frame = MenuUi.frame(name)
	if not frame then
		warn(("[MenuUi] Frames.%s is missing from the place"):format(name))
		return false
	end

	local entry = registry[name]
	local becameVisible = UiModule.ToggleFrame(player, frame, entry and entry.onOpen)
	if becameVisible then
		openFrame = name
	else
		openFrame = nil
		if entry and entry.onClose then
			local ok, err = pcall(entry.onClose, frame)
			if not ok then warn(("[MenuUi] onClose failed for %s: %s"):format(name, tostring(err))) end
		end
	end
	return becameVisible
end

function MenuUi.Open(name)
	local frame = MenuUi.frame(name)
	if frame and frame.Visible then return true end
	return MenuUi.Toggle(name)
end

function MenuUi.Close(name)
	local frame = MenuUi.frame(name)
	if not frame or not frame.Visible then return end
	MenuUi.Toggle(name)
end

function MenuUi.CloseAll()
	if not framesGui then return end
	for _, frame in ipairs(framesGui:GetChildren()) do
		if frame:IsA("GuiObject") and frame.Visible then
			frame.Visible = false
			local entry = registry[frame.Name]
			if entry and entry.onClose then
				pcall(entry.onClose, frame)
			end
		end
	end
	openFrame = nil
end

function MenuUi.IsOpen(name)
	return openFrame == name
end

--// ------------------------------------------------------------------ list api
-- The generated frames all share this shape:
--   Frame > Title, List (ScrollingFrame) > UIListLayout + RowTemplate + SectionTemplate, Close
function MenuUi.list(frame)
	return frame and frame:FindFirstChild("List")
end

local function templateOf(frame, name)
	local list = MenuUi.list(frame)
	return list and list:FindFirstChild(name)
end

-- Remove previously built rows but keep the templates.
function MenuUi.clearList(frame)
	local list = MenuUi.list(frame)
	if not list then return end
	for _, child in ipairs(list:GetChildren()) do
		if child.Name ~= "RowTemplate" and child.Name ~= "SectionTemplate"
			and not child:IsA("UIListLayout") and not child:IsA("UIPadding")
			and not child:IsA("UICorner") then
			child:Destroy()
		end
	end
end

-- opts: { info, sub, onClick, accent (Color3), order, enabled }
function MenuUi.addRow(frame, opts)
	local template = templateOf(frame, "RowTemplate")
	local list = MenuUi.list(frame)
	if not template or not list then
		warn(("[MenuUi] %s has no List/RowTemplate"):format(frame and frame.Name or "?"))
		return nil
	end

	opts = opts or {}
	local row = template:Clone()
	row.Name = "Row"
	row.Visible = true
	row.LayoutOrder = opts.order or (#list:GetChildren() * 10)

	local info = row:FindFirstChild("Info")
	if info then info.Text = tostring(opts.info or "") end
	local sub = row:FindFirstChild("Subtitle")
	if sub then sub.Text = tostring(opts.sub or "") end

	if opts.accent then
		local stroke = row:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = opts.accent end
	end

	if opts.onClick then
		UiModule.Animate(row)
		row.AutoButtonColor = opts.enabled ~= false
		row.Activated:Connect(function()
			if opts.enabled == false then return end
			local ok, err = pcall(opts.onClick, row)
			if not ok then warn(("[MenuUi] row click failed in %s: %s"):format(frame.Name, tostring(err))) end
		end)
	else
		-- A row with no action should not look pressable.
		row.AutoButtonColor = false
	end

	row.Parent = list
	return row
end

function MenuUi.addSection(frame, text, order)
	local template = templateOf(frame, "SectionTemplate")
	local list = MenuUi.list(frame)
	if not template or not list then return nil end

	local section = template:Clone()
	section.Name = "Section"
	section.Text = tostring(text or "")
	section.Visible = true
	section.LayoutOrder = order or (#list:GetChildren() * 10)
	section.Parent = list
	return section
end

-- Hide the shipped templates: they are layout references, not content.
local function hideTemplates(frame)
	for _, name in ipairs({ "RowTemplate", "SectionTemplate" }) do
		local template = templateOf(frame, name)
		if template then template.Visible = false end
	end
end

--// --------------------------------------------------------------------- init
function MenuUi.Init(c)
	client = c
	player = c.Player

	buttonsGui = client.gui("Buttons")
	framesGui = client.gui("Frames")
	if not framesGui then return false end

	for _, frame in ipairs(framesGui:GetChildren()) do
		if frame:IsA("GuiObject") then
			frame.Visible = false
			hideTemplates(frame)
			MenuUi.wireFrame(frame.Name, frame)
		end
	end

	-- Any button in the HUD bar whose name matches a frame toggles it. Buttons
	-- with no matching frame (Music, AutoFarm, 2xCash, ...) are left to Hud.
	if buttonsGui then
		for _, button in ipairs(buttonsGui:GetChildren()) do
			if button:IsA("GuiButton") then
				UiModule.Animate(button)
				local target = button.Name
				if MenuUi.frame(target) then
					button.Activated:Connect(function()
						MenuUi.Toggle(target)
					end)
				end
			end
		end
	end

	-- Escape closes whatever menu is open (Roblox still gets the keypress for its
	-- own menu; we only stop the frame from staying on screen).
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Escape and openFrame then
			MenuUi.CloseAll()
		end
	end)

	-- Never leave a menu open across a respawn: the death screen and the fresh
	-- cube both want the screen to themselves.
	player.CharacterAdded:Connect(function()
		MenuUi.CloseAll()
	end)

	return true
end

return MenuUi
