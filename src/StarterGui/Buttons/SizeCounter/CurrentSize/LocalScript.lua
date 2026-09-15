
--// Variables
local Player = game:GetService('Players').LocalPlayer
local Character

local AttributeChanged = nil

local function OnCharacterAdded(Character)
	if AttributeChanged ~= nil then
		AttributeChanged:Discconect()
	end
	
	Character = Player.Character
	
	AttributeChanged = Character:GetAttributeChangedSignal('Value'):Connect(function()
		script.Parent.Text = string.format(' %s', Character:GetAttribute('Value'))
	end)
end

Player.CharacterAdded:Connect(OnCharacterAdded)
OnCharacterAdded(Player.Character)