---------------------------------------------------------------------------
-- Raidplaner – RaidData.lua
-- TBC Classic Raid-Definitionen (statischer Datensatz)
---------------------------------------------------------------------------
local _, ADDON = ...

ADDON.RaidData = {}
local RD = ADDON.RaidData

---------------------------------------------------------------------------
-- Raid-Liste (key, name, size, short = Kalender-Kuerzel)
---------------------------------------------------------------------------
RD.raids = {
    { key = "KARAZHAN",    name = "Karazhan",              size = 10, short = "Kara"  },
    { key = "ZULAMAN",     name = "Zul'Aman",              size = 10, short = "ZA"    },
    { key = "GRUUL",       name = "Gruul's Lair",          size = 25, short = "Gruul" },
    { key = "MAGTHERIDON", name = "Magtheridon's Lair",    size = 25, short = "Maggy" },
    { key = "GRUUL_MAGGY", name = "Gruul + Magtheridon",   size = 25, short = "Gruul+Maggy" },
    { key = "SSC",         name = "Serpentshrine Cavern",   size = 25, short = "SSC"   },
    { key = "TK",          name = "Tempest Keep",           size = 25, short = "TK"    },
    { key = "HYJAL",       name = "Hyjal Summit",          size = 25, short = "Hyjal" },
    { key = "BT",          name = "Black Temple",          size = 25, short = "BT"    },
    { key = "SUNWELL",     name = "Sunwell Plateau",       size = 25, short = "SWP"   },
}

---------------------------------------------------------------------------
-- TBC Specs pro Klasse (key, name, role)
---------------------------------------------------------------------------
RD.classSpecs = {
    WARRIOR = {
        { key = "ARMS",       name = "Arms",          role = "DD"   },
        { key = "FURY",       name = "Fury",          role = "DD"   },
        { key = "PROT_WAR",   name = "Protection",    role = "TANK" },
    },
    PALADIN = {
        { key = "HOLY_PAL",   name = "Holy",          role = "HEAL" },
        { key = "PROT_PAL",   name = "Protection",    role = "TANK" },
        { key = "RET",        name = "Retribution",   role = "DD"   },
    },
    HUNTER = {
        { key = "BM",         name = "Beast Mastery",  role = "DD"  },
        { key = "MM",         name = "Marksmanship",   role = "DD"  },
        { key = "SURV",       name = "Survival",       role = "DD"  },
    },
    ROGUE = {
        { key = "ASSA",       name = "Assassination",  role = "DD"  },
        { key = "COMBAT",     name = "Combat",         role = "DD"  },
        { key = "SUB",        name = "Subtlety",       role = "DD"  },
    },
    PRIEST = {
        { key = "DISC",       name = "Discipline",     role = "HEAL" },
        { key = "HOLY_PR",    name = "Holy",           role = "HEAL" },
        { key = "SHADOW",     name = "Shadow",         role = "DD"   },
    },
    SHAMAN = {
        { key = "ELE",        name = "Elemental",      role = "DD"   },
        { key = "ENH",        name = "Enhancement",    role = "DD"   },
        { key = "RESTO_S",    name = "Restoration",    role = "HEAL" },
    },
    MAGE = {
        { key = "ARCANE",     name = "Arcane",         role = "DD"  },
        { key = "FIRE",       name = "Fire",           role = "DD"  },
        { key = "FROST_M",    name = "Frost",          role = "DD"  },
    },
    WARLOCK = {
        { key = "AFFLI",      name = "Affliction",     role = "DD"  },
        { key = "DEMO",       name = "Demonology",     role = "DD"  },
        { key = "DESTRO",     name = "Destruction",    role = "DD"  },
    },
    DRUID = {
        { key = "BALANCE",    name = "Balance",        role = "DD"   },
        { key = "FERAL_DD",   name = "Feral DPS",      role = "DD"   },
        { key = "FERAL_TANK", name = "Feral Tank",     role = "TANK" },
        { key = "RESTO_D",    name = "Restoration",    role = "HEAL" },
    },
}

---------------------------------------------------------------------------
-- Rollen-Definitionen (Sortierreihenfolge + Farbe)
---------------------------------------------------------------------------
RD.roles = {
    { key = "TANK", name = "Tank",   color = "4488ff", order = 1 },
    { key = "HEAL", name = "Heiler", color = "44ff44", order = 2 },
    { key = "DD",   name = "DD",     color = "ff4444", order = 3 },
}

RD.roleByKey = {}
for _, r in ipairs(RD.roles) do RD.roleByKey[r.key] = r end

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------

function RD:GetByKey(key)
    if not key then return nil end
    for _, r in ipairs(self.raids) do
        if r.key == key then return r end
    end
    return nil
end

function RD:GetIndex(key)
    for i, r in ipairs(self.raids) do
        if r.key == key then return i end
    end
    return 1
end

--- Alle Specs einer Klasse.
function RD:GetSpecsForClass(classToken)
    return self.classSpecs[classToken] or {}
end

--- Spec-Info anhand Key.
function RD:GetSpecInfo(classToken, specKey)
    local specs = self.classSpecs[classToken]
    if not specs then return nil end
    for _, s in ipairs(specs) do
        if s.key == specKey then return s end
    end
    return nil
end

--- Rollen-Info anhand Key.
function RD:GetRoleInfo(roleKey)
    return self.roleByKey[roleKey]
end
