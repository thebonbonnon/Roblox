--[[
	MOBA client controller: top-down camera, right-click move/attack, QWER abilities.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local HeroDefs = require(Shared:WaitForChild("Heroes"))
local MapData = require(Shared:WaitForChild("MapData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local HUD = require(script.Parent:WaitForChild("HUD"))
local FX = require(script.Parent:WaitForChild("FX"))

local camera = workspace.CurrentCamera

-- Disable default WASD/jump controls: QWER are ability keys in a MOBA.
task.spawn(function()
	local ok, PlayerModule = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	end)
	if ok and PlayerModule then
		PlayerModule:GetControls():Disable()
	end
end)

for _, coreType in ipairs({ Enum.CoreGuiType.Health, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.PlayerList }) do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreType, false)
	end)
end

HUD.init({ remotes = Remotes })

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local zoom = 70
local target = nil -- enemy model being auto-attacked
local moveDest = nil
local rightHeld = false
local lastMoveIssue = 0
local lastHoldUpdate = 0

local function myTeam()
	return player.Team and player.Team.Name or "Blue"
end

local function character()
	local char = player.Character
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 or (char:GetAttribute("Health") or 1) <= 0 then
		return nil
	end
	return char, hum, hrp
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function mouseGround()
	local m = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(m.X, m.Y)
	if ray.Direction.Y >= -1e-3 then
		return nil
	end
	local t = (Config.GroundY - ray.Origin.Y) / ray.Direction.Y
	return ray.Origin + ray.Direction * t
end

local function candidates()
	local list = {}
	local folder = workspace:FindFirstChild("Units")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			table.insert(list, m)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

-- Finds the enemy unit nearest to a ground point (generous click radius).
local function pickEnemy(point)
	local best, bestDist = nil, math.huge
	local team = myTeam()
	for _, m in ipairs(candidates()) do
		local t = m:GetAttribute("Team")
		if t and t ~= team and (m:GetAttribute("Health") or 0) > 0 and not m:GetAttribute("Invulnerable") and m.PrimaryPart then
			local d = (flat(m:GetPivot().Position) - flat(point)).Magnitude - (m:GetAttribute("Radius") or 1.5)
			if d < 3 and d < bestDist then
				best, bestDist = m, d
			end
		end
	end
	return best
end

local function setTarget(model)
	target = model
	Remotes.SetTarget:FireServer(model)
end

local function handleRightClick()
	local point = mouseGround()
	local char, hum = character()
	if not point or not char then
		return
	end
	local enemy = pickEnemy(point)
	if enemy then
		setTarget(enemy)
		moveDest = nil
		HUD.clickMarker(point, Color3.fromRGB(255, 80, 80))
	else
		if target then
			setTarget(nil)
		end
		moveDest = point
		hum:MoveTo(point)
		lastMoveIssue = os.clock()
		HUD.clickMarker(point, Color3.fromRGB(120, 255, 120))
	end
end

local function stop()
	setTarget(nil)
	moveDest = nil
	local _, hum, hrp = character()
	if hum then
		hum:MoveTo(hrp.Position)
	end
end

local function cast(slot)
	local char, hum, hrp = character()
	if not char then
		return
	end
	local point = mouseGround()
	if not point then
		return
	end
	Remotes.CastAbility:FireServer(slot, point)
	local heroId = player:GetAttribute("HeroId")
	local def = heroId and HeroDefs.Defs[heroId]
	local ab = def and def.abilities[slot]
	if ab and (ab.type == "dash" or ab.type == "execute") then
		-- Don't walk back to the old destination after dashing.
		moveDest = nil
		task.delay(0.25, function()
			if hum.Parent then
				hum:MoveTo(hrp.Position)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------
local ABILITY_KEYS = {
	[Enum.KeyCode.Q] = "Q",
	[Enum.KeyCode.W] = "W",
	[Enum.KeyCode.E] = "E",
	[Enum.KeyCode.R] = "R",
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightHeld = true
		handleRightClick()
	elseif ABILITY_KEYS[input.KeyCode] then
		cast(ABILITY_KEYS[input.KeyCode])
	elseif input.KeyCode == Enum.KeyCode.S then
		stop()
	elseif input.KeyCode == Enum.KeyCode.B then
		HUD.toggleShop()
	elseif input.KeyCode == Enum.KeyCode.Tab then
		HUD.showScoreboard(true)
	elseif input.KeyCode == Enum.KeyCode.Space then
		zoom = 70
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightHeld = false
	elseif input.KeyCode == Enum.KeyCode.Tab then
		HUD.showScoreboard(false)
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		zoom = math.clamp(zoom - input.Position.Z * 6, 35, 120)
	end
end)

---------------------------------------------------------------------------
-- Camera
---------------------------------------------------------------------------
local lastFocus = MapData.Fountain.Blue
RunService:BindToRenderStep("MobaCamera", Enum.RenderPriority.Camera.Value + 1, function()
	camera.CameraType = Enum.CameraType.Scriptable
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		lastFocus = hrp.Position
	elseif player.Team then
		lastFocus = lastFocus:Lerp(MapData.Fountain[myTeam()] or lastFocus, 0.02)
	end
	-- Red players view the map rotated 180 degrees so their base is always bottom-left.
	local flip = myTeam() == "Red" and -1 or 1
	local offset = Vector3.new(0, zoom, zoom * 0.55 * flip)
	camera.CFrame = CFrame.lookAt(lastFocus + offset, lastFocus)
end)

---------------------------------------------------------------------------
-- Movement / chase loop
---------------------------------------------------------------------------
local chaseAccum = 0
RunService.Heartbeat:Connect(function(dt)
	chaseAccum += dt
	if chaseAccum < 0.1 then
		return
	end
	chaseAccum = 0

	local char, hum, hrp = character()
	if not char then
		target, moveDest = nil, nil
		return
	end
	local now = os.clock()

	if rightHeld and now - lastHoldUpdate > 0.15 and not target then
		lastHoldUpdate = now
		local point = mouseGround()
		if point then
			moveDest = point
			hum:MoveTo(point)
			lastMoveIssue = now
		end
	end

	if target then
		if not target.Parent or (target:GetAttribute("Health") or 0) <= 0 then
			setTarget(nil)
			return
		end
		local heroId = player:GetAttribute("HeroId")
		local def = heroId and HeroDefs.Defs[heroId]
		local range = (def and def.range or 5) + (target:GetAttribute("Radius") or 1.5)
		local tpos = target:GetPivot().Position
		if (flat(tpos) - flat(hrp.Position)).Magnitude > range then
			hum:MoveTo(tpos)
		else
			hum:MoveTo(hrp.Position)
			hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(tpos.X, hrp.Position.Y, tpos.Z))
		end
	elseif moveDest then
		if (flat(moveDest) - flat(hrp.Position)).Magnitude < 2 then
			moveDest = nil
		elseif now - lastMoveIssue > 1 then
			-- Humanoid:MoveTo times out after 8 seconds; re-issue for long walks.
			hum:MoveTo(moveDest)
			lastMoveIssue = now
		end
	end
end)

player.CharacterAdded:Connect(function()
	target, moveDest = nil, nil
end)

---------------------------------------------------------------------------
-- Server messages
---------------------------------------------------------------------------
Remotes.Cooldown.OnClientEvent:Connect(function(slot, duration)
	HUD.setCooldown(slot, duration)
end)

Remotes.Notify.OnClientEvent:Connect(function(kind, ...)
	HUD.notify(kind, ...)
end)

Remotes.FX.OnClientEvent:Connect(function(kind, ...)
	if kind == "dmg" then
		HUD.damageNumber(...)
	else
		FX.handle(kind, ...)
	end
end)
