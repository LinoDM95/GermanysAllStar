---------------------------------------------------------------------------
-- Raidplaner – DB.lua
-- Datenmodell, CRUD, Fingerprint
-- Nutzt das bestehende GuildStockPlannerDB-Profil (SavedVariables).
---------------------------------------------------------------------------
local _, ADDON = ...

ADDON.RaidplanerDB = {}
local RDB = ADDON.RaidplanerDB

---------------------------------------------------------------------------
-- Profil-Zugriff (Lazy Init des raidplaner-Subtables)
---------------------------------------------------------------------------

function RDB:GetData()
    local profile = ADDON.DB:GetProfile()
    if not profile then return nil end
    if not profile.raidplaner then
        profile.raidplaner = {
            version      = 1,
            raids        = {},
            deletedRaids = {},
        }
    end
    local rp = profile.raidplaner
    if not rp.raids        then rp.raids        = {} end
    if not rp.deletedRaids then rp.deletedRaids = {} end
    return rp
end

---------------------------------------------------------------------------
-- CRUD – Raids
---------------------------------------------------------------------------

function RDB:GetRaids()
    local data = self:GetData()
    return data and data.raids or {}
end

function RDB:GetRaid(id)
    return self:GetRaids()[id]
end

function RDB:SaveRaid(raid)
    local data = self:GetData()
    if not data or not raid or not raid.id then return false end
    data.raids[raid.id] = raid
    data.deletedRaids[raid.id] = nil -- Tombstone entfernen
    return true
end

function RDB:DeleteRaid(raidId)
    local data = self:GetData()
    if not data then return false end
    data.raids[raidId] = nil
    data.deletedRaids[raidId] = time()
    return true
end

function RDB:GetDeletions()
    local data = self:GetData()
    return data and data.deletedRaids or {}
end

---------------------------------------------------------------------------
-- CRUD – Signups
---------------------------------------------------------------------------

function RDB:SaveSignup(raidId, signup)
    local raid = self:GetRaid(raidId)
    if not raid then return false end
    if not raid.signups then raid.signups = {} end
    raid.signups[signup.name] = signup
    return true
end

function RDB:GetSignups(raidId)
    local raid = self:GetRaid(raidId)
    if not raid or not raid.signups then return {} end
    return raid.signups
end

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

function RDB:GenerateId()
    return time() .. "-" .. (UnitName("player") or "X") .. "-" .. math.random(1000, 9999)
end

--- Alle Raids an einem bestimmten Datum, nach Uhrzeit sortiert.
function RDB:GetRaidsForDate(dateStr)
    local result = {}
    for _, raid in pairs(self:GetRaids()) do
        if raid.date == dateStr then
            table.insert(result, raid)
        end
    end
    table.sort(result, function(a, b) return (a.time or "") < (b.time or "") end)
    return result
end

--- Baut ein date→raids-Lookup fuer schnelles Rendern des Kalenders.
function RDB:BuildDateIndex()
    local idx = {}
    for _, raid in pairs(self:GetRaids()) do
        local d = raid.date
        if d then
            if not idx[d] then idx[d] = {} end
            table.insert(idx[d], raid)
        end
    end
    for _, list in pairs(idx) do
        table.sort(list, function(a, b) return (a.time or "") < (b.time or "") end)
    end
    return idx
end

--- Tombstones aelter als 7 Tage entfernen.
function RDB:CleanupDeletions()
    local data = self:GetData()
    if not data then return end
    local cutoff = time() - 604800 -- 7 Tage
    for id, ts in pairs(data.deletedRaids) do
        if ts < cutoff then
            data.deletedRaids[id] = nil
        end
    end
end

---------------------------------------------------------------------------
-- Fingerprint (fuer Sync – schneller Hash ueber alle Raids + Tombstones)
---------------------------------------------------------------------------

function RDB:ComputeFingerprint()
    local data = self:GetData()
    if not data then return "000000" end

    local parts = {}
    for id, raid in pairs(data.raids) do
        table.insert(parts, id .. ":" .. (raid.updatedAt or 0))
    end
    for id, ts in pairs(data.deletedRaids) do
        table.insert(parts, "d" .. id .. ":" .. ts)
    end
    table.sort(parts)

    local str = table.concat(parts, ",")
    if str == "" then return "000000" end

    local hash = 0
    for i = 1, #str do
        hash = (hash * 31 + str:byte(i)) % 16777216
    end
    return string.format("%06x", hash)
end
