-- Admin console UI: Frames/Admin > CommandBar > {Input (TextBox), Send} plus the
-- shared List. Everything is validated server side; this is a transcript.
local Admin = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local MenuUi = require(script.Parent:WaitForChild("MenuUi"))

local FRAME_NAME = "Admin"
local MAX_LINES = 80

local client, player, frame
local input, send
local transcript = {}

local function refresh()
	if not frame then return end
	MenuUi.clearList(frame)
	for index, line in ipairs(transcript) do
		MenuUi.addRow(frame, { info = line, sub = "", order = index })
	end
end

local function append(text)
	for line in tostring(text):gmatch("[^\n]+") do
		table.insert(transcript, line)
	end
	while #transcript > MAX_LINES do
		table.remove(transcript, 1)
	end
	if frame and frame.Visible then
		refresh()
	end
end

local function submit()
	if not input then return end
	local text = input.Text
	input.Text = ""
	if text == "" then return end
	append("> " .. text)
	client.fire("Admin", text)
end

function Admin.Init(c)
	client = c
	player = c.Player
	frame = MenuUi.frame(FRAME_NAME)
	if not frame then return false end

	local commandBar = frame:FindFirstChild("CommandBar")
	input = commandBar and commandBar:FindFirstChild("Input")
	send = commandBar and commandBar:FindFirstChild("Send")

	local allowed = GameConfig.isAdmin(player.UserId, player)
	append(allowed
		and "Admin console ready. Type 'help' for the command list."
		or "Your UserId is not in GameData/Admins - commands will be refused.")

	MenuUi.Register(FRAME_NAME, { onOpen = refresh })

	if input then
		-- Only submit on Enter: the old TextBox fired on every FocusLost, so
		-- clicking away from a half-typed command sent it.
		input.FocusLost:Connect(function(enterPressed)
			if enterPressed then submit() end
		end)
	end
	if send and send:IsA("GuiButton") then
		send.Activated:Connect(submit)
	end

	client.on("Admin", function(text)
		append(text)
	end)

	return true
end

return Admin
