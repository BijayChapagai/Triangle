local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local Events = ReplicatedStorage.Events

local frame = script.Parent
local list = frame:WaitForChild("List")
local quests = {}

local function clear()
	for _, v in ipairs(list:GetChildren()) do
		if v:IsA("Frame") then v:Destroy() end
	end
end

local function build()
	clear()
	for _, q in ipairs(quests) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -10, 0, 62)
		row.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
		row.Parent = list

		local txt = Instance.new("TextLabel")
		txt.Size = UDim2.new(1, -12, 0.45, 0)
		txt.Position = UDim2.new(0, 6, 0, 4)
		txt.BackgroundTransparency = 1
		txt.TextColor3 = Color3.new(1, 1, 1)
		txt.TextScaled = true
		txt.TextXAlignment = Enum.TextXAlignment.Left
		txt.Text = q.text .. "   (" .. (q.progress or 0) .. "/" .. q.goal .. ")"
		txt.Parent = row

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0.42, 0, 0.4, 0)
		btn.Position = UDim2.new(0.55, 0, 0.55, 0)
		btn.Text = q.claimed and "Claimed" or "Claim"
		btn.BackgroundColor3 = q.claimed and Color3.fromRGB(80, 80, 80) or Color3.fromRGB(60, 180, 100)
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.TextScaled = true
		btn.Parent = row
		btn.Activated:Connect(function()
			if not q.claimed then Events.QuestClaim:FireServer(q.id) end
		end)
	end
end

Events.QuestUpdate.OnClientEvent:Connect(function(...)
	local a = { ... }
	if type(a[1]) == "table" then
		quests = a[1]
	else
		local id, progress, _, claimed = a[1], a[2], a[3], a[4]
		for _, q in ipairs(quests) do
			if q.id == id then q.progress = progress; q.claimed = claimed; break end
		end
	end
	build()
end)

Events.QuestFetch:FireServer()
