--//Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--//Variables
local Manager = require(script.Manager)

for _, plr in Players:GetPlayers() do
	task.spawn(Manager.PlayerAdded, plr)
end

Players.PlayerAdded:Connect(Manager.PlayerAdded)
Players.PlayerRemoving:Connect(Manager.PlayerRemoving)