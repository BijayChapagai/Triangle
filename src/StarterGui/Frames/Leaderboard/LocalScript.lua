local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local Events = ReplicatedStorage.Events

local frame = script.Parent
local list = frame:WaitForChild("List")
local tab = "Size"
local lastLists = { Size = {}, Cash = {} }

local sizeTab = frame:FindFirstChild("SizeTab") or Instance.new("TextButton")
sizeTab.Name = "SizeTab"
sizeTab.Size = UDim2.new(0.3, 0, 0.09, 0)
sizeTab.Position = UDim2.new(0.1, 0, 0.13, 0)
sizeTab.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
sizeTab.TextColor3 = Color3.new(1, 1, 1)
sizeTab.TextScaled = true
sizeTab.Text = "Size"
sizeTab.Parent = frame

local cashTab = frame:FindFirstChild("CashTab") or Instance.new("TextButton")
cashTab.Name = "CashTab"
cashTab.Size = UDim2.new(0.3, 0, 0.09, 0)
cashTab.Position = UDim2.new(0.6, 0, 0.13, 0)
cashTab.BackgroundColor3 = Color3.fromRGB(200, 120, 60)
cashTab.TextColor3 = Color3.new(1, 1, 1)
cashTab.TextScaled = true
cashTab.Text = "Cash"
cashTab.Parent = frame

local function clear()
	for _, v in ipairs(list:GetChildren()) do
		if v:IsA("TextLabel") or v:IsA("Frame") then v:Destroy() end
	end
end

local function build()
	clear()
	local data = lastLists[tab] or {}
	for i, e in ipairs(data) do
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -10, 0, 32)
		lbl.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextScaled = true
		lbl.Text = string.format("#%d   %s   -   %s", i, e.name, tostring(e.value))
		lbl.Parent = list
	end
end

Events.Leaderboard.OnClientEvent:Connect(function(lists)
	lastLists = lists or lastLists
	build()
end)

sizeTab.Activated:Connect(function() tab = "Size"; build() end)
cashTab.Activated:Connect(function() tab = "Cash"; build() end)

Events.Leaderboard:FireServer()
