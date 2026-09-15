local startsize = UDim2.new(script.Parent.Size.Width.Scale, 0, script.Parent.Size.Height.Scale, 0)

local hoversize = UDim2.new(script.Parent.Size.Width.Scale * 1.05, 0, script.Parent.Size.Height.Scale * 1.05, 0) --change 1.05 to whatever works for you

script.Parent.MouseEnter:Connect(function()
	script.Parent:TweenSize(hoversize,Enum.EasingDirection.Out,Enum.EasingStyle.Sine,.25,true)
end)

script.Parent.MouseLeave:Connect(function()
	script.Parent:TweenSize(startsize,Enum.EasingDirection.Out,Enum.EasingStyle.Sine,.25,true)
end)