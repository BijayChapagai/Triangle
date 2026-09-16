-- Update log menu: Frames/UpdateLog > ScrollingFrame > template > Main >
-- {Number, Update}. The entries are GameData/UpdateLog (ordered StringValues), so
-- publishing a patch note is a Studio edit, not a code change.
local UpdateLog = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules:WaitForChild("GameConfig"))
local MenuUi = require(script.Parent:WaitForChild("MenuUi"))

local FRAME_NAME = "UpdateLog"

local frame, scroll, template
local built = false

local function build()
	if built or not scroll or not template then return end
	built = true

	template.Visible = false -- the old script left the template on screen

	local order = {}
	for index, text in pairs(GameConfig.UPDATELOG) do
		table.insert(order, { index = index, text = text })
	end
	-- Newest first: the highest numbered entry is the latest patch.
	table.sort(order, function(a, b) return a.index > b.index end)

	for position, entry in ipairs(order) do
		local card = template:Clone()
		card.Name = "Entry" .. entry.index
		card.Visible = true
		card.LayoutOrder = position

		local main = card:FindFirstChild("Main") or card
		local number = main:FindFirstChild("Number")
		local text = main:FindFirstChild("Update")

		if number then number.Text = "v" .. entry.index end
		if text then text.Text = entry.text end

		card.Parent = scroll
	end

	if #order == 0 then
		warn("[UpdateLog] GameData/UpdateLog has no entries")
	end
end

function UpdateLog.Init(client)
	frame = MenuUi.frame(FRAME_NAME)
	if not frame then return false end

	-- This frame predates the generated menus: its list is a plain ScrollingFrame
	-- and its template is a card, not a row.
	scroll = frame:FindFirstChildOfClass("ScrollingFrame") or frame:FindFirstChild("ScrollingFrame")
	template = scroll and scroll:FindFirstChild("template")

	if not scroll or not template then
		warn("[UpdateLog] ScrollingFrame/template is missing")
		return false
	end

	-- Build once, lazily: the log never changes during a session.
	MenuUi.Register(FRAME_NAME, { onOpen = build })

	return true
end

return UpdateLog
