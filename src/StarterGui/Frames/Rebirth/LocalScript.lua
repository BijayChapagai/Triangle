local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local Events = ReplicatedStorage.Events

local frame = script.Parent
local rebirths, mult, req = 0, 1, 0

local info = frame:FindFirstChild("Info") or Instance.new("TextLabel")
info.Name = "Info"
info.Size = UDim2.new(0.9, 0, 0.3, 0)
info.Position = UDim2.new(0.05, 0, 0.14, 0)
info.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
info.TextColor3 = Color3.new(1, 1, 1)
info.TextScaled = true
info.TextWrapped = true
info.Parent = frame

local btn = frame:FindFirstChild("RebirthButton") or Instance.new("TextButton")
btn.Name = "RebirthButton"
btn.Size = UDim2.new(0.6, 0, 0.16, 0)
btn.Position = UDim2.new(0.2, 0, 0.5, 0)
btn.BackgroundColor3 = Color3.fromRGB(255, 120, 40)
btn.TextColor3 = Color3.new(1, 1, 1)
btn.TextScaled = true
btn.Text = "REBIRTH"
btn.Parent = frame

local function refresh()
	info.Text = string.format("Rebirths: %d\nSize Multiplier: x%.2f\nNext rebirth needs Size: %d", rebirths, mult, req)
end

btn.Activated:Connect(function()
	Events.Rebirth:FireServer()
end)

Events.Rebirth.OnClientEvent:Connect(function(r, m, success, requirement)
	rebirths = r or rebirths
	mult = m or mult
	req = requirement or req
	refresh()
end)

refresh()
