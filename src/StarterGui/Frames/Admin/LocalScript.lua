local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local Events = ReplicatedStorage.Events

local frame = script.Parent

local box = frame:FindFirstChild("CommandBar") or Instance.new("TextBox")
box.Name = "CommandBar"
box.Size = UDim2.new(0.9, 0, 0.1, 0)
box.Position = UDim2.new(0.05, 0, 0.1, 0)
box.PlaceholderText = "Type a command (e.g. :givecash me 1000)"
box.TextColor3 = Color3.new(1, 1, 1)
box.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
box.TextScaled = true
box.ClearTextOnFocus = false
box.Parent = frame

local out = frame:FindFirstChild("Output") or Instance.new("TextLabel")
out.Name = "Output"
out.Size = UDim2.new(0.9, 0, 0.72, 0)
out.Position = UDim2.new(0.05, 0, 0.22, 0)
out.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
out.TextColor3 = Color3.fromRGB(0, 1, 0.4)
out.TextScaled = true
out.TextWrapped = true
out.TextXAlignment = Enum.TextXAlignment.Left
out.TextYAlignment = Enum.TextYAlignment.Top
out.Text = "Cmdr console - group members only.\nCommands: :givecash <p> <amt>  :size <p> <amt>  :rebirth [p]  :kill <p>  :tp <p> <p>  :bring <p>  :skin <id>  :god  :noclip  :heal  :clearspawn  :zone <p> <id>"
out.Parent = frame

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.BackSlash then
		if not frame.Visible then frame.Visible = true end
		box:CaptureFocus()
	end
end)

box.FocusLost:Connect(function(enterPressed)
	if enterPressed and box.Text ~= "" then
		Events.Admin:FireServer(box.Text)
		box.Text = ""
	end
end)

Events.Admin.OnClientEvent:Connect(function(msg)
	if out and out:IsA("TextLabel") then
		out.Text = out.Text .. "\n" .. msg
	end
end)
