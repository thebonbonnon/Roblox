--[[
	5v5 MOBA - match orchestration.
	Builds the map, assigns players to teams, fills empty slots with bots, runs minion waves
	and restarts the match when a nexus is destroyed.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroDefs = require(ReplicatedStorage.Shared.Heroes)

local Net = require(script.Parent.Net).init()
local Units = require(script.Parent.Units)
local Effects = require(script.Parent.Effects)
local MapBuilder = require(script.Parent.MapBuilder)
local Structures = require(script.Parent.Structures)
local Minions = require(script.Parent.Minions)
local HeroService = require(script.Parent.HeroService)
local Bots = require(script.Parent.Bots)
local Abilities = require(script.Parent.Abilities)

Units.net = Net
Effects.init(Net)
HeroService.net = Net
Players.CharacterAutoLoads = false

---------------------------------------------------------------------------
-- Replicated state containers
---------------------------------------------------------------------------
local matchState = Instance.new("Folder")
matchState.Name = "MatchState"
matchState.Parent = ReplicatedStorage
HeroService.matchState = matchState

local scoreboard = Instance.new("Folder")
scoreboard.Name = "Scoreboard"
scoreboard.Parent = ReplicatedStorage

local unitsFolder = Instance.new("Folder")
unitsFolder.Name = "Units"
unitsFolder.Parent = workspace

local teamObjects = {}
for _, name in ipairs(Config.TeamNames) do
	local team = Teams:FindFirstChild(name) or Instance.new("Team")
	team.Name = name
	team.TeamColor = BrickColor.new(Config.TeamColors[name])
	team.AutoAssignable = false
	team.Parent = Teams
	teamObjects[name] = team
end

---------------------------------------------------------------------------
-- Team slots
---------------------------------------------------------------------------
local BOT_LANES = { "Top", "Mid", "Bot", "Bot", "Top", "Mid" }
local slots = { Blue = {}, Red = {} } -- arrays of hero units
local playerTeam = {} -- [player] = team name
local playerHero = {} -- [player] = heroId
local running = false
local generation = 0

local function humansOn(team)
	local n = 0
	for _, t in pairs(playerTeam) do
		if t == team then
			n += 1
		end
	end
	return n
end

local function assignTeam(player)
	local blue, red = humansOn("Blue"), humansOn("Red")
	local team = (red < blue) and "Red" or "Blue"
	if humansOn(team) >= Config.TeamSize then
		team = HeroService.otherTeam(team)
	end
	playerTeam[player] = team
	player.Team = teamObjects[team]
	return team
end

local function lanesInUse(team)
	local used = {}
	for _, u in ipairs(slots[team]) do
		if u.lane then
			used[u.lane] = (used[u.lane] or 0) + 1
		end
	end
	return used
end

local function spawnBot(team)
	-- Pick a hero not yet used on this team, for variety.
	local taken = {}
	for _, u in ipairs(slots[team]) do
		taken[u.heroId] = true
	end
	local options = {}
	for _, id in ipairs(HeroDefs.Order) do
		if not taken[id] then
			table.insert(options, id)
		end
	end
	if #options == 0 then
		options = HeroDefs.Order
	end
	local heroId = options[math.random(#options)]

	-- Pick the lane with the fewest bots (according to the default 1/1/2 + 1 layout).
	local used = lanesInUse(team)
	local lane = BOT_LANES[#slots[team] + 1] or "Mid"
	for _, l in ipairs(BOT_LANES) do
		if (used[l] or 0) == 0 then
			lane = l
			break
		end
	end

	local u = Bots.create(team, heroId, lane)
	table.insert(slots[team], u)
end

local function removeFromSlots(u)
	for _, list in pairs(slots) do
		local i = table.find(list, u)
		if i then
			table.remove(list, i)
		end
	end
end

local function removeOneBot(team)
	for i = #slots[team], 1, -1 do
		local u = slots[team][i]
		if u.isBot then
			table.remove(slots[team], i)
			Bots.remove(u)
			return true
		end
	end
	return false
end

local function fillBots()
	if not Config.FillWithBots then
		return
	end
	for _, team in ipairs(Config.TeamNames) do
		while #slots[team] < Config.TeamSize do
			spawnBot(team)
		end
	end
end

local function addPlayerHero(player)
	local team = playerTeam[player]
	if not team or not playerHero[player] or HeroService.byPlayer[player] then
		return
	end
	if #slots[team] >= Config.TeamSize then
		removeOneBot(team)
	end
	local u = HeroService.newHero(playerHero[player], team, player)
	table.insert(slots[team], u)
	task.spawn(HeroService.spawn, u)
end

---------------------------------------------------------------------------
-- Match flow
---------------------------------------------------------------------------
local function cleanup()
	running = false
	Minions.active = false
	Minions.clear()
	Bots.clear()
	HeroService.clear()
	Structures.clear()
	Units.clear()
	Effects.clear()
	unitsFolder:ClearAllChildren()
	MapBuilder.clear()
	slots = { Blue = {}, Red = {} }
end

local startMatch

local function endMatch(winner)
	if not running then
		return
	end
	running = false
	Minions.active = false
	matchState:SetAttribute("Phase", "Ended")
	matchState:SetAttribute("Winner", winner)
	Net.Notify:FireAllClients("victory", winner)
	local gen = generation
	task.delay(Config.RestartDelay, function()
		if gen == generation then
			cleanup()
			startMatch()
		end
	end)
end

function startMatch()
	generation += 1
	HeroService.generation = generation
	MapBuilder.build()
	Structures.build()
	Minions.active = true

	matchState:SetAttribute("Phase", "Playing")
	matchState:SetAttribute("Winner", "")
	matchState:SetAttribute("BlueKills", 0)
	matchState:SetAttribute("RedKills", 0)
	matchState:SetAttribute("StartTime", workspace:GetServerTimeNow())

	for _, player in ipairs(Players:GetPlayers()) do
		addPlayerHero(player)
	end
	fillBots()
	running = true

	local gen = generation
	task.spawn(function()
		task.wait(Config.FirstWaveDelay)
		local wave = 0
		while running and gen == generation do
			wave += 1
			Minions.spawnWave(wave)
			task.wait(Config.WaveInterval)
		end
	end)
end

Structures.onNexusDestroyed = function(loserTeam)
	endMatch(HeroService.otherTeam(loserTeam))
end

RunService.Heartbeat:Connect(function(dt)
	if not running then
		return
	end
	Minions.step(dt)
	Bots.step(dt)
	Structures.step(dt)
	HeroService.step(dt)
end)

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------
local function pickHero(player, heroId)
	if playerHero[player] or not HeroDefs.Defs[heroId] then
		return
	end
	playerHero[player] = heroId
	player:SetAttribute("HeroId", heroId)
	if running then
		addPlayerHero(player)
	end
end

Players.PlayerAdded:Connect(function(player)
	assignTeam(player)
	player:SetAttribute("HeroId", nil)
	player:SetAttribute("PickDeadline", workspace:GetServerTimeNow() + Config.HeroSelectTime)
	task.delay(Config.HeroSelectTime, function()
		if player.Parent and not playerHero[player] then
			pickHero(player, HeroDefs.Order[math.random(#HeroDefs.Order)])
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local u = HeroService.byPlayer[player]
	local team = playerTeam[player]
	playerTeam[player] = nil
	playerHero[player] = nil
	if u then
		removeFromSlots(u)
		HeroService.removeHero(u)
		if running and team then
			spawnBot(team)
		end
	end
end)

Net.PickHero.OnServerEvent:Connect(pickHero)

Net.SetTarget.OnServerEvent:Connect(function(player, model)
	local u = HeroService.byPlayer[player]
	if not u then
		return
	end
	local target = typeof(model) == "Instance" and Units.byModel[model] or nil
	if target and target.team ~= u.team and target.alive then
		u.target = target
	else
		u.target = nil
	end
end)

-- First-person basic attack: shoot (or swing) along the crosshair.
Net.Fire.OnServerEvent:Connect(function(player, dir)
	local u = HeroService.byPlayer[player]
	if not u or typeof(dir) ~= "Vector3" or dir.Magnitude < 0.5 or dir.Magnitude ~= dir.Magnitude then
		return
	end
	if not Units.valid(u) or not Units.canAttack(u) then
		return
	end
	dir = dir.Unit
	local head = u.model:FindFirstChild("Head")
	local origin = head and head.Position or (u.root.Position + Vector3.new(0, 1.5, 0))
	local reach = u.range + (u.ranged and 4 or 2.5)
	local target = Units.aimPick(u, origin, dir, reach, u.ranged and 1.2 or 2.5)
	if target then
		Units.basicAttack(u, target)
	else
		u.lastAttack = Units.now()
		if u.ranged then
			Effects.trail(origin + dir * 2, origin + dir * reach, Config.TeamColors[u.team])
		else
			Effects.flash(origin + dir * 3, 1.2, Color3.new(1, 1, 1), 0.15)
		end
	end
	Net.Cooldown:FireClient(player, "Attack", Units.getAttackCd(u))
end)

Net.CastAbility.OnServerEvent:Connect(function(player, slot, pos)
	local u = HeroService.byPlayer[player]
	if not u or typeof(slot) ~= "string" or typeof(pos) ~= "Vector3" then
		return
	end
	if slot ~= "Q" and slot ~= "W" and slot ~= "E" and slot ~= "R" then
		return
	end
	local ok, cd = Abilities.tryCast(u, slot, pos)
	if ok then
		Net.Cooldown:FireClient(player, slot, cd)
	end
end)

Net.BuyItem.OnServerEvent:Connect(function(player, itemId)
	local u = HeroService.byPlayer[player]
	if not u or typeof(itemId) ~= "string" then
		return
	end
	local ok, err = HeroService.buy(u, itemId)
	if not ok then
		Net.Notify:FireClient(player, "msg", err)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	assignTeam(player)
end

startMatch()
