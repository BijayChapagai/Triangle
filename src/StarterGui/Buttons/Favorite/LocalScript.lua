local AvatarEditorService = game:GetService("AvatarEditorService")
local PlaceID = game.PlaceId

script.Parent.MouseButton1Click:Connect(function()
	AvatarEditorService:PromptSetFavorite(PlaceID, Enum.AvatarItemType.Asset, true)
end)