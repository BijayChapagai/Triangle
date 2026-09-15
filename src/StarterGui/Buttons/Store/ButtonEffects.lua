local UiModule = require(game.ReplicatedStorage.UiModule)
local player = game.Players.LocalPlayer

for i,button in pairs(script.Parent:GetChildren()) do
	if button:IsA("GuiButton") then
		UiModule.Animate(button)
		button.MouseButton1Click:Connect(function()
			local frame = script.Parent.Parent.Frames:FindFirstChild(button.Name)
			if frame then
				UiModule.ToggleFrame(player, frame)
			end
		end)
	end
end