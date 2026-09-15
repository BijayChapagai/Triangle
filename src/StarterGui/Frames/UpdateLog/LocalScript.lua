local player = game.Players.LocalPlayer

local container = script.Parent.ScrollingFrame
local template = container.template

local Updates = {
	{"Game Release!"},
	
}

for index, update in pairs(Updates) do
	local clone = template:Clone()
	clone.Visible = true
	clone.Main.Number.Text = index
	clone.Main.Update.Text = update[1]
	clone.Parent = container
	
	
	--clone.Main.MouseButton1Click:Connect(function()
		--if update[2] then
			--teleportModule.Teleport(player, player.Character, update[2])
		--end
	--end)
end