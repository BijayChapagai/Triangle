-- Loading screen. The whole UI is an asset: this script's sibling `Loading`
-- ScreenGui (LoadingFrame > Title, Icon, LoadingBar > Bar + Percentage, Skip).
-- Only the progress and the title are written at runtime.
local LoadingScreen = {}

local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

-- Deliberately no ReplicatedStorage dependency: this module has to be requirable
-- (and the screen visible) before the rest of the game has replicated. The title
-- is filled in by Client.lua through SetTitle once GameData arrives.
local template                           -- the Loading ScreenGui, found in Init

local gui, frame, bar, percentage, title, skip
local skipped = false
local finished = false
local progress = 0

function LoadingScreen.Init(client)
	-- The ScreenGui ships as a child of the Client LocalScript (this module lives
	-- one level down, in ClientModules), so walk up rather than assume a path.
	local holder = client and client.Bootstrap
	if not holder then
		holder = script.Parent
		while holder and not holder:IsA("LocalScript") do
			holder = holder.Parent
		end
	end
	template = holder and holder:FindFirstChild("Loading")

	if not template then
		warn("[LoadingScreen] no Loading ScreenGui under the Client LocalScript")
		return false
	end

	gui = template:Clone()
	-- CoreGui, not PlayerGui: the loading screen must survive StarterGui resets
	-- and be visible before PlayerGui exists.
	local ok, err = pcall(function()
		gui.Parent = CoreGui
	end)
	if not ok then
		warn("[LoadingScreen] could not parent to CoreGui: " .. tostring(err))
		gui.Parent = client and client.playerGui and client.playerGui() or nil
	end
	if not gui or not gui.Parent then return false end

	gui.Name = "LoadingScreen"
	frame = gui:FindFirstChild("LoadingFrame")
	title = frame and frame:FindFirstChild("Title")
	bar = frame and frame:FindFirstChild("LoadingBar")
	percentage = bar and bar:FindFirstChild("Percentage")
	skip = frame and frame:FindFirstChild("Skip")

	if bar then
		LoadingScreen._fill = bar:FindFirstChild("Bar")
	end

	-- The Skip button used to be its own LocalScript that only animated on hover;
	-- skipping the preload is the whole point of having the button.
	if skip then
		skip.MouseButton1Click:Connect(function()
			skipped = true
			local label = skip:FindFirstChildOfClass("TextLabel")
			if label then label.Text = "Skipping..." end
		end)
		local Ui = client and client.Ui
		if Ui then Ui.Animate(skip) end
	end

	LoadingScreen.SetProgress(0, "Loading...")

	-- Never trap a player behind the loading screen: force-finish after this.
	task.delay(LoadingScreen.TIMEOUT, function()
		if not finished then
			warn("[LoadingScreen] preload timed out, finishing anyway")
			LoadingScreen.Finish()
		end
	end)

	return true
end

LoadingScreen.TIMEOUT = 25

-- Called by the bootstrap once GameData has replicated; the asset owns the rest
-- of the look.
function LoadingScreen.SetTitle(text)
	if title and text then
		title.Text = tostring(text)
	end
end

function LoadingScreen.Skipped()
	return skipped
end

-- fraction 0..1, message optional. Cheap enough to call every frame.
function LoadingScreen.SetProgress(fraction, message)
	progress = math.clamp(tonumber(fraction) or 0, 0, 1)

	if LoadingScreen._fill then
		LoadingScreen._fill.Size = UDim2.new(progress, 0, 1, 0)
	end
	if percentage then
		-- Was "%d/%d%%" against a hard-coded 100, which read as "47/100%".
		percentage.Text = ("%d%%"):format(math.floor(progress * 100 + 0.5))
	end
	if message and title then
		title.Text = tostring(message)
	end
	return progress
end

function LoadingScreen.Finish()
	if finished then return end
	finished = true
	LoadingScreen.SetProgress(1)

	if not gui or not gui.Parent then return end

	-- Fade every visible surface, then destroy. A hard Enabled = false looked
	-- like a crash on slow machines.
	local targets = {}
	for _, object in ipairs(gui:GetDescendants()) do
		if object:IsA("ImageLabel") or object:IsA("ImageButton") then
			table.insert(targets, { object, { ImageTransparency = 1 } })
		elseif object:IsA("TextLabel") or object:IsA("TextButton") then
			table.insert(targets, { object, { TextTransparency = 1, TextStrokeTransparency = 1 } })
			if object.BackgroundTransparency < 1 then
				table.insert(targets, { object, { BackgroundTransparency = 1 } })
			end
		elseif object:IsA("Frame") then
			table.insert(targets, { object, { BackgroundTransparency = 1 } })
		end
	end

	local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, entry in ipairs(targets) do
		local ok = pcall(function()
			TweenService:Create(entry[1], info, entry[2]):Play()
		end)
		if not ok then break end
	end

	task.delay(0.4, function()
		if gui then gui:Destroy() end
		gui = nil
	end)
end

return LoadingScreen
