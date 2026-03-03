---------------------------------------------------------------------------
-- GuildStockPlanner – DB.lua
-- Datenmodell, Persistenz, Profil-Verwaltung pro Gilde+Realm
---------------------------------------------------------------------------
local _, ADDON = ...

ADDON.DB = {}
local DB = ADDON.DB

local DB_VERSION = 2 -- v2: modifiedAt, deletions, syncLog

local DEFAULT_SETTINGS = {
    officerOnly         = false,
    maxRankIndex        = 2,
    autoRecalcAfterScan = true,
}

local MAX_LOG_ENTRIES = 1000

---------------------------------------------------------------------------
-- Initialisierung
---------------------------------------------------------------------------

function DB:Initialize()
    if not GuildStockPlannerDB then
        GuildStockPlannerDB = {
            version  = DB_VERSION,
            profiles = {},
        }
    end
    -- Migrations (Version-Stempel aktualisieren)
    if (GuildStockPlannerDB.version or 0) < DB_VERSION then
        GuildStockPlannerDB.version = DB_VERSION
    end
    self:EnsureProfile()
end

--- Stellt sicher, dass fuer die aktuelle Gilde ein Profil existiert.
function DB:EnsureProfile()
    local key = ADDON:GetProfileKey()
    if not key then return end
    if not GuildStockPlannerDB.profiles[key] then
        GuildStockPlannerDB.profiles[key] = {
            recipes    = {},
            settings   = {},
            lastScan   = { ts = 0, bankCounts = {} },
            deletions  = {},
            syncLog    = {},
        }
    end
    local profile = GuildStockPlannerDB.profiles[key]
    -- Defaults fuer fehlende Settings-Keys
    for k, v in pairs(DEFAULT_SETTINGS) do
        if profile.settings[k] == nil then
            profile.settings[k] = v
        end
    end
    if not profile.recipes              then profile.recipes    = {} end
    if not profile.lastScan             then profile.lastScan   = { ts = 0, bankCounts = {} } end
    if not profile.lastScan.bankCounts  then profile.lastScan.bankCounts = {} end
    if not profile.deletions            then profile.deletions  = {} end
    if not profile.syncLog              then profile.syncLog    = {} end

    -- Migration: modifiedAt fuer bestehende Rezepte setzen
    for _, recipe in pairs(profile.recipes) do
        if not recipe.modifiedAt then
            recipe.modifiedAt = time()
        end
    end
end

---------------------------------------------------------------------------
-- Profil-Zugriff
---------------------------------------------------------------------------

function DB:GetProfile()
    local key = ADDON:GetProfileKey()
    if not key then return nil end
    if not GuildStockPlannerDB or not GuildStockPlannerDB.profiles then return nil end
    return GuildStockPlannerDB.profiles[key]
end

---------------------------------------------------------------------------
-- Rezepte CRUD
---------------------------------------------------------------------------

function DB:GetRecipes()
    local profile = self:GetProfile()
    if not profile then return {} end
    return profile.recipes
end

function DB:GetRecipe(mainItemID)
    local recipes = self:GetRecipes()
    return recipes[mainItemID]
end

function DB:SaveRecipe(recipe)
    local profile = self:GetProfile()
    if not profile then
        ADDON:Print("Fehler: Kein Gildenprofil gefunden.")
        return false
    end
    if not recipe or not recipe.mainItemID then
        ADDON:Print("Fehler: Ungueltiges Rezept.")
        return false
    end
    profile.recipes[recipe.mainItemID] = {
        mainItemID   = recipe.mainItemID,
        desiredStock = recipe.desiredStock or 0,
        yield        = math.max(1, recipe.yield or 1),
        mats         = recipe.mats or {},
        modifiedAt   = recipe.modifiedAt or time(),
    }
    -- Tombstone entfernen falls vorhanden
    if profile.deletions then
        profile.deletions[recipe.mainItemID] = nil
    end
    return true
end

function DB:DeleteRecipe(mainItemID)
    local profile = self:GetProfile()
    if not profile then return false end
    profile.recipes[mainItemID] = nil
    if not profile.deletions then profile.deletions = {} end
    profile.deletions[mainItemID] = time()
    return true
end

---------------------------------------------------------------------------
-- Tombstones (Loeschungen)
---------------------------------------------------------------------------

function DB:GetDeletions()
    local profile = self:GetProfile()
    if not profile then return {} end
    return profile.deletions or {}
end

--- Entfernt Tombstones aelter als 7 Tage.
function DB:CleanupDeletions()
    local profile = self:GetProfile()
    if not profile or not profile.deletions then return end
    local cutoff = time() - (7 * 24 * 3600)
    for id, ts in pairs(profile.deletions) do
        if ts < cutoff then
            profile.deletions[id] = nil
        end
    end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

function DB:GetSettings()
    local profile = self:GetProfile()
    if not profile then return DEFAULT_SETTINGS end
    return profile.settings
end

function DB:SaveSettings(settings)
    local profile = self:GetProfile()
    if not profile then return end
    for k, v in pairs(settings) do
        profile.settings[k] = v
    end
end

---------------------------------------------------------------------------
-- Scan-Ergebnisse
---------------------------------------------------------------------------

function DB:GetLastScan()
    local profile = self:GetProfile()
    if not profile then return { ts = 0, bankCounts = {} } end
    return profile.lastScan
end

function DB:SaveScanResults(bankCounts, timestamp)
    local profile = self:GetProfile()
    if not profile then return end
    profile.lastScan = {
        ts         = timestamp or time(),
        bankCounts = bankCounts,
    }
end

---------------------------------------------------------------------------
-- Berechtigungen
---------------------------------------------------------------------------

function DB:CanEditRecipes()
    local settings = self:GetSettings()
    if not settings.officerOnly then return true end
    -- Nutze den Hub-weiten Offiziersrang-Check
    return ADDON:AmIOfficer()
end

---------------------------------------------------------------------------
-- Sync-Log
---------------------------------------------------------------------------

--- Fuegt einen Log-Eintrag hinzu (neueste zuerst).
--- action: "add", "del", "edit", "sync_in", "sync_out", "sync_ok"
function DB:AddLogEntry(action, who, itemID, detail)
    local profile = self:GetProfile()
    if not profile then return end
    if not profile.syncLog then profile.syncLog = {} end
    table.insert(profile.syncLog, 1, {
        ts     = time(),
        action = action,
        who    = who or "",
        itemID = itemID,
        detail = detail or "",
    })
    -- Limit
    while #profile.syncLog > MAX_LOG_ENTRIES do
        table.remove(profile.syncLog)
    end
end

function DB:GetSyncLog()
    local profile = self:GetProfile()
    if not profile then return {} end
    return profile.syncLog or {}
end
