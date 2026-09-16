-- Codes menu: Frames/Codes > TextBox (+ the hover/pop Sounds that ship with it).
-- Codes and their cash values live in GameData/Codes; the server validates and
-- always answers through Events.Notify.
local Codes = {}

local MenuUi = require(script.Parent:WaitForChild("MenuUi"))

local FRAME_NAME = "Codes"

local client, frame, box, popSound, hoverSound

local function play(sound)
	if sound and sound:IsA("Sound") then
		sound.TimePosition = 0
		sound:Play()
	end
end

local function submit()
	if not box then return end
	local text = box.Text
	box.Text = ""
	if text == "" then return end
	play(popSound)
	client.fire("AttemptCode", text)
end

function Codes.Init(c)
	client = c
	frame = MenuUi.frame(FRAME_NAME)
	if not frame then return false end

	box = frame:FindFirstChildOfClass("TextBox") or frame:FindFirstChild("TextBox")
	popSound = frame:FindFirstChild("pop")
	hoverSound = frame:FindFirstChild("Button Hover Sound")

	MenuUi.Register(FRAME_NAME, {
		onOpen = function()
			-- Focus the box so a code can be typed straight away (desktop only:
			-- forcing the keyboard open on console/mobile is intrusive).
			if box then
				task.defer(function()
					pcall(function() box:CaptureFocus() end)
				end)
			end
		end,
	})

	if box then
		-- Enter only: the old handler fired on every FocusLost, which sent
		-- half-typed codes and then cleared nothing.
		box.FocusLost:Connect(function(enterPressed)
			if enterPressed then submit() end
		end)
		box.Focused:Connect(function()
			play(hoverSound)
		end)
	end

	return true
end

return Codes
