local Music = workspace.MusicFolder.Music

script.Parent.MouseButton1Click:Connect(function()
	if Music.Volume == 0 then
		Music.Volume = .7
		script.Parent.ImageLabel.Image =  "rbxassetid://116374907473809"
	else
		Music.Volume = 0
		script.Parent.ImageLabel.Image =  "rbxassetid://83783073128505"
	end
end)