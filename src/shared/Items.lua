-- Shop items. Stats: damage, power (ability scaling), armor, maxHp, maxMana, speed, attackSpeed (fraction)
local Items = {}

Items.Order = { "LongSword", "Tome", "ClothArmor", "Boots", "Ruby", "Sapphire", "WarBlade", "ArchStaff", "Aegis" }

Items.Defs = {
	LongSword = { name = "Long Sword", short = "SWD", cost = 350, stats = { damage = 12 } },
	Tome = { name = "Amplifying Tome", short = "TOM", cost = 400, stats = { power = 25 } },
	ClothArmor = { name = "Cloth Armor", short = "ARM", cost = 300, stats = { armor = 15 } },
	Boots = { name = "Swift Boots", short = "BTS", cost = 300, stats = { speed = 3 } },
	Ruby = { name = "Ruby Crystal", short = "RBY", cost = 400, stats = { maxHp = 150 } },
	Sapphire = { name = "Sapphire Crystal", short = "SAP", cost = 300, stats = { maxMana = 200 } },
	WarBlade = { name = "War Blade", short = "WAR", cost = 1300, stats = { damage = 40, attackSpeed = 0.15 } },
	ArchStaff = { name = "Arch Staff", short = "STF", cost = 1400, stats = { power = 80 } },
	Aegis = { name = "Aegis Plate", short = "AEG", cost = 1200, stats = { armor = 45, maxHp = 250 } },
}

local STAT_NAMES = {
	damage = "Damage", power = "Power", armor = "Armor", maxHp = "Health",
	maxMana = "Mana", speed = "Speed", attackSpeed = "Attack Speed",
}

function Items.Describe(id)
	local item = Items.Defs[id]
	local parts = {}
	for stat, value in pairs(item.stats) do
		if stat == "attackSpeed" then
			table.insert(parts, string.format("+%d%% %s", value * 100, STAT_NAMES[stat]))
		else
			table.insert(parts, string.format("+%d %s", value, STAT_NAMES[stat] or stat))
		end
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

return Items
