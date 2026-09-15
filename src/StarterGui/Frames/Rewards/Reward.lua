local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RewardList = require(ReplicatedStorage.Modules:WaitForChild("RewardList"))

coroutine.wrap(function()
	while task.wait(1) do
		local PlayerTime = game:GetService("Players").LocalPlayer:GetAttribute("PlayerTime")
		if not PlayerTime then return end
		for _, prize in script.Parent:WaitForChild("Rewards"):GetChildren() do
			if not prize:IsA("ImageButton") then continue end

			local index = string.match(prize.Name, "%d+")
			local RewardInfo = RewardList[tonumber(index)]
			local timeLeft = RewardInfo.RequiredTime - PlayerTime

			timeLeft = math.max(timeLeft, 0)
			if timeLeft <= 0 then
				-- time is less than zero
			end
			
			local v = prize:WaitForChild("Time")
			
			prize.Activated:Connect(function()
				if timeLeft > 0 then return end
				ReplicatedStorage.Events:WaitForChild("PlayTimeReward"):FireServer(tonumber(index))
				v.Text = "CLAIMED"
				prize:SetAttribute("Claimed", true)
			end)
			
			local hours = math.floor(timeLeft / 3600)
			local minutes = math.floor((timeLeft % 3600) / 60)
			local seconds = timeLeft % 60
			
			local timeString
			
			if hours > 0 then
				-- hours greater than 0
				timeString = string.format("%d:%02d:%02d", hours, minutes, seconds)
			else
				-- greater than 0
				timeString = string.format("%02d:%02d", minutes, seconds)
			end
			
			if timeLeft > 0 then
				v.Text = timeString
			end
			
			if timeLeft <= 0 and prize:GetAttribute("Claimed") == nil then
				v.Text = "CLAIM"
			end
			
		end
	end
end)()