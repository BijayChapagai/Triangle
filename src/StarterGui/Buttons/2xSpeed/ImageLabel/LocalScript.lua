local imageLabel = script.Parent
local TS = game:GetService("TweenService")

-- Settings
local originalSize = UDim2.new(0.362, 0,1.455, 0) -- Original size of the image
local originalPos = UDim2.new(0.5, 0, 0.5, 0) -- Original pos of the image
local newSize = UDim2.new(0.557, 0,1.643, 0) -- New Size of Image
local sizeSpeed = 0.4 -- Dont Change this!
local rotationSpeed = 0.2 -- Change The Rotate Speed

local isAnimating = false 

local function startAnimation()
	if isAnimating then
		return
	end

	isAnimating = true

	local sizeTween = TS:Create(imageLabel, TweenInfo.new(sizeSpeed), { Size = newSize })
	sizeTween:Play()
	sizeTween.Completed:Connect(function()
		local rotateLeft = TS:Create(imageLabel, TweenInfo.new(rotationSpeed), { Rotation = imageLabel.Rotation + 20 })
		rotateLeft:Play()
		rotateLeft.Completed:Connect(function()
			local rotateRight = TS:Create(imageLabel, TweenInfo.new(rotationSpeed), { Rotation = imageLabel.Rotation - 40 })
			rotateRight:Play()
			rotateRight.Completed:Connect(function()
				local revertTween = TS:Create(imageLabel, TweenInfo.new(sizeSpeed), { Size = originalSize, Rotation = 0 })
				revertTween:Play()
				revertTween.Completed:Connect(function()
					isAnimating = false
				end)
			end)
		end)
	end)
end

while true do
	startAnimation()
	wait(5)
end

