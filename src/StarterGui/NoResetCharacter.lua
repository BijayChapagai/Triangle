---// Roblox Services
local StarterGUI = game:GetService("StarterGui")

---// Deactivates the Reset Button
repeat -- Starts the repeat loop
	local success = pcall(function() 
		StarterGUI:SetCore("ResetButtonCallback", false) 
	end)
	task.wait(1) -- Cooldown to avoid freezing
until success -- Runs the loop until the Reset Button is disabled.
print("SUCCESS | Reset button core GUI disabled!") -- Debugging