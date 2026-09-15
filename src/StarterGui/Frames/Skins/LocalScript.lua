local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local Events = ReplicatedStorage.Events
local Config = require(ReplicatedStorage.Modules.ProgressionConfig)

local frame = script.Parent
local list = frame:WaitForChild("List")

local owned = { "Default" }
local equipped = "Default"

local function clear()
	for _, v in ipairs(list:GetChildren()) do
		if v:IsA("GuiButton") or v:IsA("Frame") then v:Destroy() end
	end
end

local function build()
	clear()
	for _, skin in ipairs(Config.SKINS) do
		local isOwned = false
		for _, s in ipairs(owned) do if s == skin.id then isOwned = true end end
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, -10, 0, 52)
		row.BackgroundColor3 = isOwned and Color3.fromRGB(40, 190, 120) or Color3.fromRGB(80, 80, 92)
		local status = isOwned and (equipped == skin.id and " (equipped)" or " (owned)") or (" (locked: " .. skin.unlock .. (skin.req and (" " .. skin.req) or "") .. ")")
		row.Text = skin.id .. status
		row.TextColor3 = Color3.new(1, 1, 1)
		row.TextScaled = true
		row.Parent = list
		row.Activated:Connect(function()
			if isOwned then Events.EquipSkin:FireServer(skin.id) end
		end)
	end
end

Events.SkinList.OnClientEvent:Connect(function(o, e)
	owned = o or owned
	equipped = e or equipped
	build()
end)

build()
