local Sound = script.Parent.Toggle -- Change Sound to whatever your sound is called.

script.Parent.MouseButton1Click:Connect(function()
	Sound:Play()
end)
