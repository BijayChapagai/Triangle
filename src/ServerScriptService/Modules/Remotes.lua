-- Every RemoteEvent in one place, accessed defensively.
--
-- A missing event used to be fatal: the food handler indexed
-- Events.QuestUpdate.OnServerEvent and threw mid-eat, which left food claimed
-- but never destroyed (inedible cubes all over the map). Now a missing remote
-- warns once and degrades only the feature that needed it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local Events = ReplicatedStorage:WaitForChild("Events")
Remotes.Folder = Events

local warned = {}

function Remotes.get(name)
	local event = Events:FindFirstChild(name)
	if not event then
		if not warned[name] then
			warned[name] = true
			warn(("[Remotes] ReplicatedStorage.Events.%s is missing - that feature is disabled."):format(name))
		end
		return nil
	end
	return event
end

function Remotes.toClient(player, name, ...)
	local event = Remotes.get(name)
	if event and player then
		event:FireClient(player, ...)
	end
end

function Remotes.toAllClients(name, ...)
	local event = Remotes.get(name)
	if event then
		event:FireAllClients(...)
	end
end

function Remotes.onServer(name, handler)
	local event = Remotes.get(name)
	if not event then return nil end
	return event.OnServerEvent:Connect(function(player, ...)
		-- One bad argument or a throwing handler must never take the listener down.
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(("[Remotes] %s handler failed for %s: %s"):format(name, player.Name, tostring(err)))
		end
	end)
end

return Remotes
