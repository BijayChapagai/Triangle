local tweenService = game:GetService("TweenService")

local enterMulti = 1.1
local downMulti = 0.8

local hoverSound = script.hoverSound
local clickSound = script.clickSound

local AnimationModule = {}

local function enter(Button, size)
	if Button.Name == "Big" then
		enterMulti = 1.03
	end
	tweenService:Create(Button, TweenInfo.new(.1), {Size = UDim2.new(size.X.Scale * enterMulti, size.X.Offset, size.Y.Scale * enterMulti, size.Y.Offset)}):Play()
	hoverSound:Play()
	if Button:FindFirstChild("ImageLabel") then
		tweenService:Create(Button.ImageLabel, TweenInfo.new(.1), {Rotation = math.random(10,25)}):Play()
	end
	enterMulti = 1.1
end
local function leave(Button, size)
	if Button.Name == "Big" then
		enterMulti = 1.03
	end
	tweenService:Create(Button, TweenInfo.new(.1), {Size = size}):Play()
	if Button:FindFirstChild("ImageLabel") then
		tweenService:Create(Button.ImageLabel, TweenInfo.new(.1), {Rotation = 0}):Play()
	end
	enterMulti = 1.1
end
local function down(Button, size)
	if Button.Name == "Big" then
		enterMulti = 1.03
	end
	tweenService:Create(Button, TweenInfo.new(.1), {Size = UDim2.new(size.X.Scale * downMulti, size.X.Offset, size.Y.Scale * downMulti, size.Y.Offset)}):Play()
	enterMulti = 1.1
end
local function up(Button, size)
	if Button.Name == "Big" then
		enterMulti = 1.03
	end
	tweenService:Create(Button, TweenInfo.new(.1), {Size = UDim2.new(size.X.Scale * enterMulti, size.X.Offset, size.Y.Scale * enterMulti, size.Y.Offset)}):Play()
	enterMulti = 1.1
	clickSound:Play()
end

AnimationModule.Animate = function(Button)
	if Button:IsA("GuiButton") or Button:IsA("Frame") then
		local size = Button.Size
		
		Button.MouseEnter:Connect(function()
			enter(Button, size)
		end)
		Button.MouseLeave:Connect(function()
			leave(Button, size)
		end)
		if Button:IsA("GuiButton") then
			Button.MouseButton1Down:Connect(function()
				down(Button, size)
			end)
			Button.MouseButton1Up:Connect(function()
				up(Button, size)
			end)
		end
	end
end
AnimationModule.ToggleFrame = function(player, Frame)
	local position = Frame.Position
	if Frame:IsA("GuiBase") then
		if Frame.Visible == false then
			for i,aFrame in pairs(player.PlayerGui.Frames:GetChildren()) do
				aFrame.Visible = false
			end

			local cc = workspace.CurrentCamera
			wait()
			Frame.Position = UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale + 0.1, position.Y.Offset)
			Frame.Visible = true
			tweenService:Create(Frame, TweenInfo.new(.25, Enum.EasingStyle.Bounce), {Position = position}):Play()
			tweenService:Create(cc, TweenInfo.new(.25, Enum.EasingStyle.Bounce), {FieldOfView = 80}):Play()
		else
			local cc = workspace.CurrentCamera
			wait()
			Frame.Visible = false
			tweenService:Create(cc, TweenInfo.new(.25, Enum.EasingStyle.Linear), {FieldOfView = 70}):Play()
		end	
	end
end

return AnimationModule
