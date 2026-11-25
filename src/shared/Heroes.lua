--[[
	Hero definitions.

	Ability types:
	  skillshot : projectile fired toward the mouse. fields: range, speed, width, pierce, count, spread
	  aoe       : circle at the mouse position (clamped to range). fields: range, radius, delay
	  selfaoe   : circle around the caster. fields: radius, delay
	  dash      : move toward the mouse. fields: range, damage (hits enemies along the path), buff
	  buff      : self buff. fields: duration, speedMult, armor, attackSpeed, heal, healPerLevel
	  execute   : leap to the enemy hero nearest the mouse. fields: range, radius, missingHp

	Common fields: name, mana, cooldown, damage, perLevel, ratio (scaling from Power), stun, slow, slowDuration
]]
local Heroes = {}

Heroes.Order = { "Knight", "Mage", "Ranger", "Guardian", "Assassin", "Gunslinger" }

Heroes.Defs = {
	Knight = {
		displayName = "Knight",
		role = "Fighter",
		description = "Durable melee bruiser who charges in and locks down groups.",
		color = Color3.fromRGB(205, 205, 215),
		hp = 620, hpPerLevel = 85, mana = 280, manaPerLevel = 30, manaRegen = 4,
		damage = 58, damagePerLevel = 4, armor = 30, armorPerLevel = 2.5,
		range = 6, attackCd = 1.0, speed = 18, ranged = false,
		build = { "LongSword", "Ruby", "ClothArmor", "WarBlade", "Aegis", "Boots" },
		abilities = {
			Q = { name = "Cleave", type = "selfaoe", radius = 11, damage = 75, perLevel = 18, ratio = 0.6, mana = 35, cooldown = 6 },
			W = { name = "Rally", type = "buff", duration = 3, speedMult = 1.4, heal = 70, healPerLevel = 15, mana = 50, cooldown = 14 },
			E = { name = "Charge", type = "dash", range = 26, damage = 60, perLevel = 12, ratio = 0.4, stun = 0.75, mana = 50, cooldown = 11 },
			R = { name = "Judgment", type = "aoe", range = 30, radius = 14, delay = 0.6, damage = 250, perLevel = 35, ratio = 0.9, stun = 1.5, mana = 100, cooldown = 60 },
		},
	},

	Mage = {
		displayName = "Mage",
		role = "Mage",
		description = "Fragile long-range caster with huge burst damage.",
		color = Color3.fromRGB(150, 90, 230),
		hp = 470, hpPerLevel = 70, mana = 520, manaPerLevel = 45, manaRegen = 7,
		damage = 42, damagePerLevel = 3, armor = 15, armorPerLevel = 1.5,
		range = 40, attackCd = 1.15, speed = 16, ranged = true,
		build = { "Tome", "Sapphire", "ArchStaff", "Boots", "Ruby", "ArchStaff" },
		abilities = {
			Q = { name = "Fireball", type = "skillshot", range = 48, speed = 95, width = 2.5, damage = 110, perLevel = 22, ratio = 0.8, mana = 45, cooldown = 5 },
			W = { name = "Frost Nova", type = "aoe", range = 36, radius = 10, delay = 0.25, damage = 70, perLevel = 15, ratio = 0.5, slow = 0.45, slowDuration = 2, mana = 60, cooldown = 10 },
			E = { name = "Blink", type = "dash", range = 22, mana = 60, cooldown = 14 },
			R = { name = "Meteor", type = "aoe", range = 50, radius = 16, delay = 1.1, damage = 340, perLevel = 45, ratio = 1.0, mana = 120, cooldown = 70 },
		},
	},

	Ranger = {
		displayName = "Ranger",
		role = "Marksman",
		description = "Sustained ranged damage. Kites with tumbles and slows.",
		color = Color3.fromRGB(90, 180, 90),
		hp = 510, hpPerLevel = 78, mana = 320, manaPerLevel = 30, manaRegen = 5,
		damage = 52, damagePerLevel = 4.5, armor = 18, armorPerLevel = 2,
		range = 45, attackCd = 0.85, speed = 17, ranged = true,
		build = { "LongSword", "Boots", "WarBlade", "WarBlade", "ClothArmor", "Ruby" },
		abilities = {
			Q = { name = "Piercing Arrow", type = "skillshot", range = 60, speed = 130, width = 2, pierce = true, damage = 95, perLevel = 20, ratio = 0.5, mana = 45, cooldown = 7 },
			W = { name = "Volley", type = "skillshot", count = 5, spread = 50, range = 40, speed = 100, width = 1.8, damage = 60, perLevel = 12, ratio = 0.4, slow = 0.25, slowDuration = 1.5, mana = 55, cooldown = 10 },
			E = { name = "Tumble", type = "dash", range = 14, buff = { duration = 3, attackSpeed = 0.5 }, mana = 40, cooldown = 9 },
			R = { name = "Rain of Arrows", type = "aoe", range = 55, radius = 18, delay = 0.8, damage = 280, perLevel = 40, ratio = 0.8, slow = 0.4, slowDuration = 2, mana = 100, cooldown = 65 },
		},
	},

	Guardian = {
		displayName = "Guardian",
		role = "Tank",
		description = "Massive armored tank. Stuns, slows and soaks tower shots.",
		color = Color3.fromRGB(200, 160, 70),
		hp = 720, hpPerLevel = 100, mana = 300, manaPerLevel = 30, manaRegen = 5,
		damage = 50, damagePerLevel = 3, armor = 45, armorPerLevel = 3.5,
		range = 6, attackCd = 1.2, speed = 17, ranged = false,
		build = { "Ruby", "ClothArmor", "Aegis", "Boots", "Aegis", "Ruby" },
		abilities = {
			Q = { name = "Shield Bash", type = "skillshot", range = 18, speed = 70, width = 3, damage = 70, perLevel = 14, ratio = 0.5, stun = 1.0, mana = 50, cooldown = 9 },
			W = { name = "Fortify", type = "buff", duration = 4, armor = 60, heal = 40, healPerLevel = 10, mana = 50, cooldown = 15 },
			E = { name = "Ground Slam", type = "selfaoe", radius = 13, damage = 60, perLevel = 12, ratio = 0.4, slow = 0.4, slowDuration = 2, mana = 45, cooldown = 8 },
			R = { name = "Earthquake", type = "selfaoe", radius = 20, delay = 0.5, damage = 200, perLevel = 30, ratio = 0.6, stun = 1.5, mana = 110, cooldown = 65 },
		},
	},

	Assassin = {
		displayName = "Assassin",
		role = "Assassin",
		description = "Fast melee killer that dives and executes low-health heroes.",
		color = Color3.fromRGB(60, 60, 70),
		hp = 530, hpPerLevel = 80, mana = 300, manaPerLevel = 30, manaRegen = 5,
		damage = 66, damagePerLevel = 5, armor = 20, armorPerLevel = 2,
		range = 5.5, attackCd = 0.95, speed = 19, ranged = false,
		build = { "LongSword", "Boots", "WarBlade", "LongSword", "Aegis", "WarBlade" },
		abilities = {
			Q = { name = "Shadow Strike", type = "dash", range = 18, damage = 110, perLevel = 22, ratio = 0.6, mana = 40, cooldown = 6 },
			W = { name = "Smoke Veil", type = "buff", duration = 3, speedMult = 1.5, attackSpeed = 0.3, mana = 50, cooldown = 13 },
			E = { name = "Poison Blade", type = "skillshot", range = 35, speed = 110, width = 2, damage = 80, perLevel = 16, ratio = 0.5, slow = 0.35, slowDuration = 2.5, mana = 40, cooldown = 8 },
			R = { name = "Execute", type = "execute", range = 14, radius = 10, damage = 180, perLevel = 30, ratio = 0.7, missingHp = 0.35, mana = 90, cooldown = 50 },
		},
	},

	Gunslinger = {
		displayName = "Gunslinger",
		role = "Gunner",
		description = "Fast-firing sharpshooter with a frag grenade and a bullet-storm finisher.",
		color = Color3.fromRGB(140, 92, 56),
		hp = 500, hpPerLevel = 75, mana = 300, manaPerLevel = 30, manaRegen = 5,
		damage = 30, damagePerLevel = 2.5, armor = 16, armorPerLevel = 2,
		range = 48, attackCd = 0.45, speed = 17, ranged = true,
		build = { "LongSword", "Boots", "WarBlade", "WarBlade", "Ruby", "ClothArmor" },
		abilities = {
			Q = { name = "Rapid Fire", type = "buff", duration = 3, attackSpeed = 0.8, speedMult = 1.1, mana = 40, cooldown = 10 },
			W = { name = "Frag Grenade", type = "aoe", range = 35, radius = 9, delay = 0.8, damage = 110, perLevel = 22, ratio = 0.6, mana = 50, cooldown = 9 },
			E = { name = "Combat Roll", type = "dash", range = 14, buff = { duration = 2, attackSpeed = 0.4 }, mana = 35, cooldown = 7 },
			R = { name = "Bullet Storm", type = "skillshot", count = 9, spread = 40, range = 50, speed = 160, width = 1.6, damage = 70, perLevel = 12, ratio = 0.5, mana = 100, cooldown = 55 },
		},
	},
}

Heroes.Slots = { "Q", "W", "E", "R" }

return Heroes
