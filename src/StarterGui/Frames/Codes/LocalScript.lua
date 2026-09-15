local TweenService = game:GetService("TweenService")
local buttonHoverSound = script.Parent["Button Hover Sound"]
local popSound = script.Parent.pop

local function enter(button, size)
	TweenService:Create(button, TweenInfo.new(.1), {Size = size}):Play()
	buttonHoverSound:Play()
end

local function leave(button, size)
	TweenService:Create(button, TweenInfo.new(.1), {Size = size}):Play()
end

local function down(button, size)
	TweenService:Create(button, TweenInfo.new(.1), {Size = size}):Play()
end

local function up(button, size)
	TweenService:Create(button, TweenInfo.new(.1), {Size = size}):Play()
	popSound:Play()
end

for i,frame in pairs(script.Parent:GetChildren()) do
	if frame:IsA("TextBox") then
		frame.MouseEnter:Connect(function()
			enter(frame, UDim2.new(0.921, 0,0.325, 0))
		end)
		frame.MouseLeave:Connect(function()
			leave(frame, UDim2.new(0.837, 0,0.295, 0))
		end)
	end
end