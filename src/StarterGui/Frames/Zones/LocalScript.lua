local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local Events = ReplicatedStorage.Events
local Config = require(ReplicatedStorage.Modules.ProgressionConfig)

local frame = script.Parent
local list = frame:WaitForChild("List")
local status = frame:FindFirstChild("Status")

local function reqText(z)
	if not z.req or next(z.req) == nil then return "Unlocked" end
	if z.req.size then return "Need Size " .. z.req.size end
	if z.req.rebirth then return "Need " .. z.req.rebirth .. " Rebirths" end
	return "Locked"
end

for _, z in ipairs(Config.ZONES) do
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, -10, 0, 58)
	row.BackgroundColor3 = Color3.fromRGB(table.unpack(z.color))
	row.TextColor3 = Color3.new(1, 1, 1)
	row.TextScaled = true
	row.Text = z.name .. "\n" .. reqText(z) .. "   |   Rarity: " .. z.rarity
	row.Parent = list
	row.Activated:Connect(function()
		Events.ZoneTeleport:FireServer(z.id)
	end)
end

Events.ZoneTeleport.OnClientEvent:Connect(function(_, success, reason)
	if status then
		status.Text = success and "Teleported!" or ("Denied: " .. (reason or ""))
	end
end)
