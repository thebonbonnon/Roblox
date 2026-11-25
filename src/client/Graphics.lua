--[[
	Graphics quality. "High" is the full look; "Low" turns off the expensive parts (shadows, lamp
	lights, bloom, sun rays, water waves) and tells FX to use fewer particles.
	Starts on High and drops to Low automatically if the frame rate stays low. Press G to switch.
	All changes are local to this player.
]]
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Graphics = {}
Graphics.level = "High"

local listeners = {}
local fps = 60
local lowSince = nil
local autoDropped = false
local started = os.clock()

local function apply()
	local high = Graphics.level == "High"
	Lighting.GlobalShadows = high
	for _, e in ipairs(Lighting:GetChildren()) do
		if e:IsA("BloomEffect") or e:IsA("SunRaysEffect") or e:IsA("DepthOfFieldEffect") then
			e.Enabled = high
		end
	end
	local map = workspace:FindFirstChild("Map")
	if map then
		for _, d in ipairs(map:GetDescendants()) do
			if d:IsA("PointLight") or d:IsA("SpotLight") then
				d.Enabled = high
			end
		end
	end
	workspace.Terrain.WaterWaveSize = high and 0.08 or 0
	workspace.Terrain.WaterReflectance = high and 0.6 or 0.2
end

-- fn(level) is called whenever the level changes.
function Graphics.onChanged(fn)
	table.insert(listeners, fn)
end

function Graphics.set(level, reason)
	Graphics.level = level
	apply()
	for _, fn in ipairs(listeners) do
		task.spawn(fn, level, reason)
	end
end

function Graphics.fps()
	return fps
end

function Graphics.init()
	-- The server rebuilds the map and lighting every match; re-apply when they come back.
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Map" then
			task.defer(apply)
		end
	end)
	Lighting.ChildAdded:Connect(function()
		task.defer(apply)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.G and not UserInputService:GetFocusedTextBox() then
			Graphics.set(Graphics.level == "High" and "Low" or "High", "manual")
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		fps += (1 / math.max(dt, 1 / 240) - fps) * 0.05
		-- Auto-drop once if the game has been running slowly for a few seconds.
		if Graphics.level == "High" and not autoDropped and os.clock() - started > 15 then -- skip loading stutter
			if fps < 38 then
				lowSince = lowSince or os.clock()
				if os.clock() - lowSince > 4 then
					autoDropped = true
					Graphics.set("Low", "auto")
				end
			else
				lowSince = nil
			end
		end
	end)
	apply()
end

return Graphics
