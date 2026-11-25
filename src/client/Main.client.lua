--[[
	MOBA client controller, first person:
	  WASD move, Space jump (again in the air to double jump), Shift dash, Ctrl/C slide,
	  mouse aim, Left click shoot / swing, Right click zoom,
	  Q E F R abilities (fired at what the crosshair points at), B shop, Tab scores.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local HUD = require(script.Parent:WaitForChild("HUD"))
local FX = require(script.Parent:WaitForChild("FX"))
local Viewmodel = require(script.Parent:WaitForChild("Viewmodel"))
local Movement = require(script.Parent:WaitForChild("Movement"))
local Graphics = require(script.Parent:WaitForChild("Graphics"))
local HeroDefs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Heroes"))

local camera = workspace.CurrentCamera

player.CameraMode = Enum.CameraMode.LockFirstPerson
player.CameraMinZoomDistance = 0.5
player.CameraMaxZoomDistance = 0.5

for _, coreType in ipairs({ Enum.CoreGuiType.Health, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.PlayerList }) do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreType, false)
	end)
end

HUD.init({ remotes = Remotes, movement = Movement, graphics = Graphics })
Graphics.onChanged(function(level, reason)
	FX.setQuality(level)
	if reason == "auto" then
		HUD.notify("msg", "Switched to low graphics for a smoother game (press G to change)", Color3.fromRGB(140, 220, 255))
	else
		HUD.notify("msg", "Graphics: " .. level .. " (press G to change)", Color3.fromRGB(140, 220, 255))
	end
end)
Graphics.init()
Viewmodel.init()
local fovKick = 0
Movement.init({
	blocked = function()
		return HUD.menuOpen()
	end,
	onDash = function(pos, dir)
		FX.dash(pos, dir)
		fovKick = 14
	end,
	onDoubleJump = function(pos)
		FX.jump(pos)
	end,
	onSlide = function(pos)
		FX.slide(pos)
		fovKick = 8
	end,
})

-- Ability keys. Slots keep their internal names (Q/W/E/R); W is "walk forward" in an FPS,
-- so the second ability lives on E and the third on F.
local ABILITY_KEYS = {}
for slot, label in pairs(HUD.KEY_LABELS) do
	ABILITY_KEYS[Enum.KeyCode[label]] = slot
end

local BASE_FOV, ZOOM_FOV = 75, 50
local firing, zooming = false, false
local lastFire = 0

local function alive()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and (char:GetAttribute("Health") or 1) > 0
end

-- What the crosshair points at: the aim direction and the world point it hits.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function aim()
	local cf = camera.CFrame
	local filter = { camera }
	if player.Character then
		table.insert(filter, player.Character)
	end
	rayParams.FilterDescendantsInstances = filter
	local result = workspace:Raycast(cf.Position, cf.LookVector * 500, rayParams)
	return cf.LookVector, result and result.Position or (cf.Position + cf.LookVector * 200)
end

-- Attacks react instantly on your screen (kick, crosshair) instead of waiting a round trip to
-- the server; the server still decides hits and damage. The attack interval is learned from
-- the server's confirmations (it changes with items and buffs).
local attackInterval = nil
local nextShot = 0
local function tryFire()
	if not alive() or HUD.menuOpen() then
		return
	end
	local now = os.clock()
	if not attackInterval then
		local def = HeroDefs.Defs[player:GetAttribute("HeroId") or ""]
		attackInterval = def and def.attackCd or 1
	end
	if now < nextShot then
		return
	end
	nextShot = now + attackInterval * 0.97
	lastFire = now
	Viewmodel.kick(1)
	HUD.attackPulse()
	Remotes.Fire:FireServer((aim()))
end

local function cast(slot)
	if not alive() or HUD.menuOpen() then
		return
	end
	local _, point = aim()
	Remotes.CastAbility:FireServer(slot, point)
	if HUD.isReady(slot) then
		Viewmodel.kick(0.8) -- instant feedback; the server confirms the cooldown
		FX.shake(0.12)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = true
		tryFire()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		zooming = true
	elseif ABILITY_KEYS[input.KeyCode] then
		cast(ABILITY_KEYS[input.KeyCode])
	elseif input.KeyCode == Enum.KeyCode.B then
		HUD.toggleShop()
	elseif input.KeyCode == Enum.KeyCode.Tab then
		HUD.showScoreboard(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		zooming = false
	elseif input.KeyCode == Enum.KeyCode.Tab then
		HUD.showScoreboard(false)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if firing then
		tryFire()
	end
	fovKick *= math.exp(-dt * 6)
	local target = ((zooming and alive() and not HUD.menuOpen()) and ZOOM_FOV or BASE_FOV) + fovKick
	camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * 12)
	Viewmodel.setHidden(HUD.menuOpen() or zooming)
end)

player.CharacterAdded:Connect(function()
	firing, zooming = false, false
	attackInterval = nil
end)

---------------------------------------------------------------------------
-- Server messages
---------------------------------------------------------------------------
Remotes.Cooldown.OnClientEvent:Connect(function(slot, duration)
	if slot == "Attack" then
		attackInterval = duration -- keep the local fire rate in sync with the server
	else
		HUD.setCooldown(slot, duration)
	end
end)

Remotes.Notify.OnClientEvent:Connect(function(kind, ...)
	HUD.notify(kind, ...)
end)

Remotes.FX.OnClientEvent:Connect(function(kind, ...)
	if kind == "dmg" then
		local pos, amount, heroVsHero, sourceUserId = ...
		HUD.damageNumber(pos, amount, heroVsHero)
		if sourceUserId == player.UserId then
			HUD.hitmarker(heroVsHero)
		end
	else
		FX.handle(kind, ...)
	end
end)
