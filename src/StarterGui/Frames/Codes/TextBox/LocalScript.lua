local player = game.Players.LocalPlayer

script.Parent.FocusLost:Connect(function()
	game:GetService("ReplicatedStorage").Events:WaitForChild("AttemptCode"):FireServer(script.Parent.Text)
end)
