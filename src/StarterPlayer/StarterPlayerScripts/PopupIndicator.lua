local Player=game:GetService("Players").LocalPlayer
local UI=script:WaitForChild("IncrementUI")
local Images={}
local LoadedInstances={}
local function SetDescendants()
	for i, v in pairs(Player:GetDescendants()) do 
		if not Player:FindFirstChild("PlayerGui") or not v:IsDescendantOf(Player.PlayerGui) then
			if v:IsA("NumberValue") or v:IsA("IntValue") then
				LoadedInstances[v.Name]=v
			end
		end
	end
	Player.DescendantAdded:Connect(function(v)
		if not Player:FindFirstChild("PlayerGui") or not v:IsDescendantOf(Player.PlayerGui) then
			if v:IsA("NumberValue") or v:IsA("IntValue") then
				LoadedInstances[v.Name]=v
			end
		end
	end)
end
local function Format(value)
	local idp=1
	if value < 1000 then return math.floor(value + 0.5)
	else local abbreviations = {"", "K", "M", "B", "T"} local ex = math.floor(math.log(math.max(1, math.abs(value)),1000))
		local abbrevs = abbreviations [1 + ex] or ("e+"..ex)
		local normal = math.floor(value * ((10 ^ idp) / (1000 ^ ex))) / (10 ^ idp)
		return ("%."..idp.."f%s"):format(normal, abbrevs)
	end
end
local function SetupPopup(Template)
	local DelayTrack=0
	spawn(function()
		local function OnInstance()
			local k=LoadedInstances[Template.Name]
			local oldvalue=k.Value
			k:GetPropertyChangedSignal("Value"):Connect(function()
				if k.Value>oldvalue then
					local TemplateClone=Template:Clone()
					TemplateClone.Amount.Text="+"..Format((k.Value)-oldvalue)
					TemplateClone.Parent=UI
				end
				oldvalue=k.Value
			end)
		end
		while true do 
			task.wait(1)
			if typeof(LoadedInstances[Template.Name])~='nil' or DelayTrack>=10 then
				break
			end
			DelayTrack=DelayTrack+1
		end
		if typeof(LoadedInstances[Template.Name])~='nil' then
			OnInstance()
		else
			warn("Popup Indicator: Unable To Find IntValue/NumberValue For Anything Named "..Template.Name.." In the Player.")
		end
	end)
end
local function SetUI()
	local TweenService=game:GetService("TweenService")
	UI.ChildAdded:Connect(function(Icon)
		local originalSize = Icon.Size
		Icon.Amount.TextTransparency = 1
		Icon.Amount.TextStrokeTransparency = 1
		Icon.ImageTransparency = 1
		Icon.Position = UDim2.new(math.random(10, 70) / 100, 0, math.random(10, 60) / 100, 0)
		Icon.Size = originalSize + UDim2.new(0.25, 0, 0.25, 0)
		TweenService:Create(Icon, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0), {Size = originalSize, ImageTransparency = 0}):Play()
		TweenService:Create(Icon.Amount, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0), {TextTransparency = 0, TextStrokeTransparency = 0}):Play()
		delay(0.75, function()
			local pos = Icon.AbsolutePosition
			local size = Icon.AbsoluteSize
			TweenService:Create(Icon, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0), {
				AnchorPoint = Vector2.new(0, 0.5),
				Size = UDim2.new(0, size.X, 0, size.Y),
				Position = UDim2.new(0, pos.X, 0, pos.Y),
				ImageTransparency = 1
			}):Play()
			TweenService:Create(Icon.Amount, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
			wait(1)
			Icon:Destroy()
		end)
	end)
	UI.Parent=Player:WaitForChild("PlayerGui")
end
SetDescendants()
for i, v in pairs(script:GetChildren()) do 
	if v:IsA("ImageLabel") then
		SetupPopup(v)
	end
end
script.ChildAdded:Connect(function(v)
	if v:IsA("ImageLabel") then
		SetupPopup(v)
	end
end)

SetUI()