local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

local formatNumber = require(replicatedStorage.Modules:WaitForChild("FormatNumberAlt"))
local player = players.LocalPlayer

local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")

local cashLabel = script.Parent:WaitForChild("Cash"):WaitForChild("Label")

local textCash = formatNumber.FormatCompact(cash.Value)
cashLabel.Text = textCash

cash.Changed:Connect(function()
	local text = formatNumber.FormatCompact(cash.Value)
	cashLabel.Text = text
end)
