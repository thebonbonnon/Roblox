--[[
	Heroes: shared logic for player-controlled and bot heroes.
	A hero unit persists for the whole match (level, gold, items, KDA); only its model is
	recreated on respawn.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapData = require(ReplicatedStorage.Shared.MapData)
local HeroDefs = require(ReplicatedStorage.Shared.Heroes)
local Items = require(ReplicatedStorage.Shared.Items)
local Units = require(script.Parent.Units)
local Effects = require(script.Parent.Effects)
local ModelFactory = require(script.Parent.ModelFactory)
local Animations = require(script.Parent.Animations)

local flat = Units.flat

local HeroService = {}
HeroService.heroes = {} -- set
HeroService.byPlayer = {}
HeroService.generation = 0
HeroService.net = nil
HeroService.matchState = nil -- Folder with attributes (BlueKills, RedKills, ...)

local TICK = 0.1
local accum = 0
local scoreAccum = 0

local function otherTeam(team)
	return team == "Blue" and "Red" or "Blue"
end
HeroService.otherTeam = otherTeam

local function notifyAll(kind, ...)
	if HeroService.net then
		HeroService.net.Notify:FireAllClients(kind, ...)
	end
end

---------------------------------------------------------------------------
-- Stats & progression
---------------------------------------------------------------------------
function HeroService.recalc(u)
	local d, L = u.def, u.level - 1
	local bonus = {}
	for _, id in ipairs(u.items) do
		for stat, v in pairs(Items.Defs[id].stats) do
			bonus[stat] = (bonus[stat] or 0) + v
		end
	end
	u.bonus = bonus
	local oldMax, oldMana = u.maxHp, u.maxMana
	u.maxHp = d.hp + d.hpPerLevel * L + (bonus.maxHp or 0)
	u.maxMana = d.mana + d.manaPerLevel * L + (bonus.maxMana or 0)
	u.damage = d.damage + d.damagePerLevel * L
	u.armor = d.armor + d.armorPerLevel * L
	u.speed = d.speed
	-- Gaining max health/mana also grants the difference.
	if oldMax and u.hp then
		u.hp = math.clamp(u.hp + (u.maxHp - oldMax), 1, u.maxHp)
	end
	if oldMana and u.mana then
		u.mana = math.clamp(u.mana + (u.maxMana - oldMana), 0, u.maxMana)
	end
end

function HeroService.addGold(u, amount)
	u.gold += amount
end

function HeroService.addXp(u, amount)
	if u.level >= Config.MaxLevel then
		return
	end
	u.xp += amount
	while u.level < Config.MaxLevel and u.xp >= Config.XpForLevel(u.level) do
		u.xp -= Config.XpForLevel(u.level)
		u.level += 1
		HeroService.recalc(u)
		if Units.valid(u) then
			Effects.flash(u.root.Position, 5, Color3.fromRGB(255, 220, 90), 0.6)
		end
	end
	if u.level >= Config.MaxLevel then
		u.xp = 0
	end
end

function HeroService.canShop(u)
	if not u.alive then
		return true
	end
	return Units.valid(u)
		and (flat(u.root.Position) - flat(MapData.Fountain[u.team])).Magnitude <= Config.ShopRadius
end

function HeroService.buy(u, itemId)
	local item = Items.Defs[itemId]
	if not item then
		return false, "Unknown item"
	end
	if #u.items >= Config.MaxItems then
		return false, "Inventory full"
	end
	if u.gold < item.cost then
		return false, "Not enough gold"
	end
	if not HeroService.canShop(u) then
		return false, "Return to your fountain to shop"
	end
	u.gold -= item.cost
	table.insert(u.items, itemId)
	HeroService.recalc(u)
	HeroService.sync(u)
	return true
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function HeroService.newHero(heroId, team, player)
	local def = HeroDefs.Defs[heroId]
	local u = Units.new({
		team = team,
		kind = "hero",
		name = player and player.DisplayName or ("Bot " .. def.displayName),
		range = def.range,
		attackCd = def.attackCd,
		radius = 1.5,
		ranged = def.ranged,
		barHeight = 4.2,
	})
	u.heroId = heroId
	u.def = def
	u.player = player
	u.isBot = player == nil
	u.level = 1
	u.xp = 0
	u.gold = Config.StartingGold
	u.items = {}
	u.kills, u.deaths, u.assists = 0, 0, 0
	u.cooldowns = {}
	u.maxHp = nil
	u.maxMana = nil
	HeroService.recalc(u)
	u.hp = u.maxHp
	u.mana = u.maxMana
	HeroService.heroes[u] = true
	if player then
		HeroService.byPlayer[player] = u
	end
	return u
end

function HeroService.spawn(u)
	local gen = HeroService.generation
	local pos = MapData.Fountain[u.team] + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
	u.hp = u.maxHp
	u.mana = u.maxMana
	u.target = nil
	u.buffs = {}
	u.stunUntil = 0
	u.recentHeroDamagers = {}

	if u.player then
		local player = u.player
		if not player.Parent then
			return
		end
		player:LoadCharacter()
		if gen ~= HeroService.generation or not HeroService.heroes[u] then
			return
		end
		local char = player.Character
		local hrp = char and char:WaitForChild("HumanoidRootPart", 5)
		local hum = char and char:WaitForChild("Humanoid", 5)
		if not hrp or not hum then
			return
		end
		char:PivotTo(CFrame.new(pos + Vector3.new(0, 4, 0)))
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.UseJumpPower = true
		hum.JumpPower = 45
		hum.WalkSpeed = u.def.speed
		char:SetAttribute("HeroId", u.heroId)
		Units.attach(u, char, hrp)
		u.firePart = char:FindFirstChild("Head") -- first person: shots come from the eyes
		u.alive = true
		-- R6 players wear their hero's gear and get attack animations (the Animate script that
		-- comes with the character already handles walking and idling).
		u.anim = nil
		if hum.RigType == Enum.HumanoidRigType.R6 then
			ModelFactory.attachGear("Hero_" .. u.heroId, char, u.team)
			u.anim = Animations.attach(hum, { actionsOnly = true })
		elseif not HeroService.warnedR15 then
			HeroService.warnedR15 = true
			warn("[MOBA] Players are spawning as R15. Set Game Settings > Avatar > Avatar Type to R6 so they wear hero gear.")
		end
		hum.Died:Connect(function()
			if u.model == char and u.alive then
				Units.kill(u, nil)
			end
		end)
		player:SetAttribute("RespawnAt", 0)
	else
		u.customSpawn(u, pos)
		u.alive = true
	end
	Units.refresh(u)
	HeroService.sync(u)
end

function HeroService.removeHero(u)
	HeroService.heroes[u] = nil
	if u.player then
		HeroService.byPlayer[u.player] = nil
	end
	if u.customDespawn then
		u.customDespawn(u)
	end
	Units.remove(u)
	local board = ReplicatedStorage:FindFirstChild("Scoreboard")
	local entry = board and board:FindFirstChild(tostring(u.id))
	if entry then
		entry:Destroy()
	end
end

function HeroService.clear()
	for u in pairs(HeroService.heroes) do
		HeroService.removeHero(u)
		if u.player and u.player.Character then
			u.player.Character:Destroy()
		end
	end
	HeroService.heroes = {}
	HeroService.byPlayer = {}
	local board = ReplicatedStorage:FindFirstChild("Scoreboard")
	if board then
		board:ClearAllChildren()
	end
end

---------------------------------------------------------------------------
-- Replication to clients
---------------------------------------------------------------------------
function HeroService.sync(u)
	Units.refresh(u)
	local p = u.player
	if not p then
		return
	end
	p:SetAttribute("HeroId", u.heroId)
	p:SetAttribute("Gold", math.floor(u.gold))
	p:SetAttribute("Level", u.level)
	p:SetAttribute("XP", math.floor(u.xp))
	p:SetAttribute("XPNext", Config.XpForLevel(u.level))
	p:SetAttribute("Kills", u.kills)
	p:SetAttribute("Deaths", u.deaths)
	p:SetAttribute("Assists", u.assists)
	p:SetAttribute("Items", table.concat(u.items, ","))
	p:SetAttribute("StatDamage", math.floor(Units.getDamage(u)))
	p:SetAttribute("StatPower", math.floor(u.bonus.power or 0))
	p:SetAttribute("StatArmor", math.floor(Units.getArmor(u)))
	p:SetAttribute("StatSpeed", math.floor(Units.getSpeed(u)))
	if Units.valid(u) then
		local hum = u.model:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = Units.getSpeed(u)
		end
	end
end

local function updateScoreboard()
	local board = ReplicatedStorage:FindFirstChild("Scoreboard")
	if not board then
		return
	end
	for u in pairs(HeroService.heroes) do
		local entry = board:FindFirstChild(tostring(u.id))
		if not entry then
			entry = Instance.new("Configuration")
			entry.Name = tostring(u.id)
			entry.Parent = board
		end
		entry:SetAttribute("Name", u.name)
		entry:SetAttribute("Team", u.team)
		entry:SetAttribute("Hero", u.def.displayName)
		entry:SetAttribute("Level", u.level)
		entry:SetAttribute("Kills", u.kills)
		entry:SetAttribute("Deaths", u.deaths)
		entry:SetAttribute("Assists", u.assists)
		entry:SetAttribute("Bot", u.isBot)
		entry:SetAttribute("Alive", u.alive)
		entry:SetAttribute("Items", table.concat(u.items, ","))
		entry:SetAttribute("UserId", u.player and u.player.UserId or 0)
	end
end

---------------------------------------------------------------------------
-- Per-tick logic: regen, fountain, auto-attacks
---------------------------------------------------------------------------
local function tickHero(u, dt)
	if not u.alive then
		return
	end
	if not Units.valid(u) then
		-- Character vanished (e.g. fell off the world or was removed)
		Units.kill(u, nil)
		return
	end
	local pos = flat(u.root.Position)

	u.gold += Config.PassiveGold * dt
	u.mana = math.min(u.maxMana, u.mana + u.def.manaRegen * dt)
	u.hp = math.min(u.maxHp, u.hp + (1.5 + u.level * 0.3) * dt)

	if (pos - flat(MapData.Fountain[u.team])).Magnitude <= Config.FountainRadius then
		u.hp = math.min(u.maxHp, u.hp + u.maxHp * Config.FountainRegen * dt)
		u.mana = math.min(u.maxMana, u.mana + u.maxMana * Config.FountainRegen * dt)
	end
	if (pos - flat(MapData.Fountain[otherTeam(u.team)])).Magnitude <= Config.FountainRadius + 6 then
		Units.damage(u, Config.FountainLaserDps * dt, nil)
		if not u.alive then
			return
		end
	end

	-- Auto attack the current target when in range. Movement toward it is handled by the
	-- client (players) or the bot brain.
	local t = u.target
	if t then
		if not Units.valid(t) or t.team == u.team or Units.isInvulnerable(t) then
			u.target = nil
		else
			local slack = u.player and 2.5 or 0.5 -- small tolerance for network latency
			if Units.edgeDist(u, t) <= u.range + slack and Units.canAttack(u) then
				Units.basicAttack(u, t)
			end
		end
	end

	HeroService.sync(u)
end

function HeroService.step(dt)
	accum += dt
	scoreAccum += dt
	if accum >= TICK then
		local elapsed = accum
		accum = 0
		for u in pairs(HeroService.heroes) do
			tickHero(u, elapsed)
		end
	end
	if scoreAccum >= 1 then
		scoreAccum = 0
		updateScoreboard()
	end
end

---------------------------------------------------------------------------
-- Rewards & death
---------------------------------------------------------------------------
local function heroesNear(team, pos, radius)
	local list = {}
	for h in pairs(HeroService.heroes) do
		if h.team == team and Units.valid(h) and (flat(h.root.Position) - flat(pos)).Magnitude <= radius then
			table.insert(list, h)
		end
	end
	return list
end

local function onHeroDeath(u, killer)
	u.deaths += 1
	u.target = nil
	local deathPos = u.root and u.root.Position or MapData.Nexus[u.team]
	local now = Units.now()

	-- Credit: killer hero, or the last enemy hero to damage us within the assist window.
	local killerHero = killer and killer.kind == "hero" and killer or nil
	local bestT = 0
	if not killerHero then
		for h, t in pairs(u.recentHeroDamagers) do
			if now - t <= Config.AssistWindow and t > bestT and HeroService.heroes[h] then
				killerHero, bestT = h, t
			end
		end
	end
	if killerHero then
		killerHero.kills += 1
		HeroService.addGold(killerHero, Config.HeroKillGold + Config.HeroKillGoldPerLevel * u.level)
	end
	for h, t in pairs(u.recentHeroDamagers) do
		if h ~= killerHero and now - t <= Config.AssistWindow and HeroService.heroes[h] then
			h.assists += 1
			HeroService.addGold(h, Config.AssistGold)
		end
	end
	for _, h in ipairs(heroesNear(otherTeam(u.team), deathPos, Config.XpShareRadius)) do
		HeroService.addXp(h, Config.HeroKillXp + Config.HeroKillXpPerLevel * u.level)
	end
	u.recentHeroDamagers = {}

	local enemy = otherTeam(u.team)
	if HeroService.matchState then
		local key = enemy .. "Kills"
		HeroService.matchState:SetAttribute(key, (HeroService.matchState:GetAttribute(key) or 0) + 1)
	end
	notifyAll("kill", killerHero and killerHero.name or "The enemy", killerHero and killerHero.team or enemy, u.name, u.team)

	-- Respawn
	local delay = Config.RespawnBase + Config.RespawnPerLevel * u.level
	if u.player then
		u.player:SetAttribute("RespawnAt", workspace:GetServerTimeNow() + delay)
		local hum = u.model and u.model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.Health = 0
		end
	elseif u.customDespawn then
		u.customDespawn(u)
	end
	HeroService.sync(u)
	local gen = HeroService.generation
	task.delay(delay, function()
		if gen == HeroService.generation and HeroService.heroes[u] and not u.alive then
			HeroService.spawn(u)
		end
	end)
end

Units.onDeath(function(dead, killer)
	if dead.kind == "hero" then
		if HeroService.heroes[dead] then
			onHeroDeath(dead, killer)
		end
	elseif dead.kind == "minion" then
		local s = Config.Minions[dead.minionType]
		if killer and killer.kind == "hero" then
			HeroService.addGold(killer, s.gold)
		end
		local near = heroesNear(otherTeam(dead.team), dead.root.Position, Config.XpShareRadius)
		local share = #near > 1 and 0.7 or 1
		for _, h in ipairs(near) do
			HeroService.addXp(h, s.xp * share)
		end
	elseif dead.kind == "tower" then
		local winnerTeam = otherTeam(dead.team)
		for h in pairs(HeroService.heroes) do
			if h.team == winnerTeam then
				HeroService.addGold(h, Config.TowerGold)
			end
		end
		notifyAll("tower", dead.team, dead.lane)
	end
end)

return HeroService
