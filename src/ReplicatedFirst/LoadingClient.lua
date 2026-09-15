--//Services\\--

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

local Player = game.Players.LocalPlayer
local PlayerGui = Player.PlayerGui
local LoadingGui = script:WaitForChild("Loading")

local Assets = game:GetDescendants()

local ClonedLoadingScreen = LoadingGui:Clone()
ClonedLoadingScreen.Enabled = true
ClonedLoadingScreen.Parent = PlayerGui

local LoadingFrame = ClonedLoadingScreen:FindFirstChild("LoadingFrame")
local LoadingBar = LoadingFrame and LoadingFrame:FindFirstChild("LoadingBar")
local Percentage = LoadingBar and LoadingBar:FindFirstChild("Percentage")
local Skip = LoadingFrame and LoadingFrame:FindFirstChild("Skip")

-- Check that all objects are correctly initialized
if not LoadingFrame or not LoadingBar or not Percentage or not Skip then
	warn("One or more objects are not initialized correctly")
    return
end

--//Functions\\--

ReplicatedFirst:RemoveDefaultLoadingScreen()

TweenService:Create(LoadingFrame:WaitForChild("Icon"),
    TweenInfo.new(2.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, true, 0),
    {Position = LoadingFrame:WaitForChild("Icon").Position - UDim2.new(0,0,0.1,0)}):Play()

TweenService:Create(LoadingFrame:WaitForChild("Pattern"),
    TweenInfo.new(30, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, true, 0.2),
    {Position = LoadingFrame:WaitForChild("Pattern").Position + UDim2.new(0.7,0,0.7,0)}):Play()

Skip.MouseButton1Click:Connect(function()
    ClonedLoadingScreen.Enabled = false
end)

for i = 1, #Assets do
    local asset = Assets[i]
    local percentage = math.round(i / #Assets * 100)

    ContentProvider:PreloadAsync({asset})

    Percentage.Text = percentage .. "/100%"

    TweenService:Create(LoadingBar.Bar, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Size = UDim2.fromScale(percentage / 100, 1)}):Play()

    if i % 3 == 0 then
        task.wait()
    end

    if Percentage.Text == "100/100%" then 
        ClonedLoadingScreen.Enabled = false
    end
end