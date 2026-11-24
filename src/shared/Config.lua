-- Global tuning values for the MOBA. Shared by server and client.
local Config = {}

Config.TeamNames = { "Blue", "Red" }
Config.TeamColors = {
	Blue = Color3.fromRGB(60, 140, 255),
	Red = Color3.fromRGB(235, 70, 70),
}
Config.TeamSize = 5
Config.FillWithBots = true -- empty slots are filled with AI heroes

Config.GroundY = 0 -- top surface of the battlefield
Config.MapHalfSize = 300

-- Match flow
Config.HeroSelectTime = 20 -- seconds before a random hero is auto-picked
Config.RestartDelay = 15 -- seconds after a nexus falls before a new match

-- Economy / progression
Config.StartingGold = 500
Config.PassiveGold = 2 -- gold per second
Config.MaxItems = 6
Config.MaxLevel = 15
Config.UltLevel = 6 -- R unlocks at this level
function Config.XpForLevel(level)
	return 120 + level * 70
end
Config.XpShareRadius = 45
Config.HeroKillGold = 300
Config.HeroKillGoldPerLevel = 15
Config.AssistGold = 120
Config.HeroKillXp = 160
Config.HeroKillXpPerLevel = 25
Config.TowerGold = 150 -- given to every hero on the destroying team
Config.AssistWindow = 10

-- Respawn
Config.RespawnBase = 6
Config.RespawnPerLevel = 1.5

-- Fountain
Config.FountainRadius = 26
Config.FountainRegen = 0.12 -- fraction of max hp/mana per second
Config.FountainLaserDps = 500 -- damage per second to enemy heroes in your fountain
Config.ShopRadius = 32

-- Minion waves
Config.FirstWaveDelay = 8
Config.WaveInterval = 30
Config.SiegeEvery = 3
Config.MinionAggro = 16
Config.MinionLeash = 26
Config.Minions = {
	melee = {
		hp = 340, damage = 22, armor = 10, range = 3.5, attackCd = 1.2, speed = 13,
		ranged = false, radius = 1.4,
		gold = 20, xp = 30,
	},
	caster = {
		hp = 230, damage = 30, armor = 0, range = 18, attackCd = 1.5, speed = 13,
		ranged = true, radius = 1.2,
		gold = 16, xp = 26,
	},
	siege = {
		hp = 750, damage = 50, armor = 20, range = 22, attackCd = 2.0, speed = 11,
		ranged = true, radius = 2.2,
		gold = 45, xp = 60,
	},
}

-- Structures
Config.Tower = { hp = 3000, damage = 150, armor = 40, range = 24, attackCd = 1.1, radius = 4 }
Config.Nexus = { hp = 5500, armor = 30, radius = 8 }

return Config
