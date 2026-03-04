---------------------------------------------------------------------------
-- GermanysAllStar – Core.lua
-- Shared Namespace, Hilfsfunktionen, Hub-DB, Permissions, Slash-Commands
---------------------------------------------------------------------------
local ADDON_NAME, ADDON = ...

ADDON.version      = "2.0.0"
ADDON.debugEnabled = false

-- Alle registrierten Apps mit Metadaten
-- public = true  → App ist fuer ALLE Mitglieder offen (kein Whitelist noetig)
-- public = false → App ist standardmaessig gesperrt, muss freigeschaltet werden
ADDON.allApps = {
    { key = "GuildStockPlanner", label = "GSP",          public = false },
    { key = "GuildStocks",       label = "GuildStocks",   public = true  },
    { key = "Raidplaner",        label = "Raidplaner",    public = true  },
}

function ADDON:IsPublicApp(appKey)
    for _, app in ipairs(self.allApps) do
        if app.key == appKey then return app.public end
    end
    return false
end

-- Abwaertskompatibilitaet
ADDON.registeredApps = {} -- wird unten befuellt
for _, app in ipairs(ADDON.allApps) do
    table.insert(ADDON.registeredApps, app.key)
end

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

function ADDON:ParseItemID(input)
    if not input then return nil end
    if type(input) == "number" then
        return input > 0 and math.floor(input) or nil
    end
    local str = tostring(input):match("^%s*(.-)%s*$")
    if str == "" then return nil end
    local id = str:match("item:(%d+)")
    if id then return tonumber(id) end
    local num = tonumber(str)
    if num and num > 0 then return math.floor(num) end
    return nil
end

function ADDON:SafeInt(val, minVal, default)
    local n = tonumber(val)
    if not n then return default or 0 end
    n = math.floor(n + 0.5)
    if minVal and n < minVal then return minVal end
    return n
end

function ADDON:Clamp(val, lo, hi)
    if val < lo then return lo end
    if val > hi then return hi end
    return val
end

function ADDON:Debug(...)
    if not self.debugEnabled then return end
    print("|cff00ccff[GAS Debug]|r", ...)
end

function ADDON:Print(...)
    print("|cffff8800[GermanysAllStar]|r", ...)
end

function ADDON:GetGuildInfo()
    if not IsInGuild() then return nil end
    local guildName, guildRankName, guildRankIndex = GetGuildInfo("player")
    if not guildName or guildName == "" then return nil end
    local realmName = GetRealmName() or "UnknownRealm"
    return guildName, realmName, guildRankName, guildRankIndex
end

function ADDON:GetProfileKey()
    local guildName, realmName = self:GetGuildInfo()
    if not guildName then return nil end
    return realmName .. "::" .. guildName
end

function ADDON:GetColoredItemName(itemID)
    if not itemID then return "|cffff0000[Unbekannt]|r" end
    local name, _, quality = GetItemInfo(itemID)
    if name and quality then
        local r, g, b = GetItemQualityColor(quality)
        return string.format("|cff%02x%02x%02x%s|r",
            math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), name)
    end
    if name then return name end
    return "|cffffd100[Item:" .. itemID .. "]|r"
end

function ADDON:ResolveItemInput(input)
    local id = self:ParseItemID(input)
    if id then return id end
    if not input or type(input) ~= "string" then return nil end
    local name = input:match("^%s*(.-)%s*$")
    if name == "" then return nil end
    if self.UI and self.UI.GetSearchPool then
        local pool = self.UI:GetSearchPool()
        local lower = name:lower()
        for itemID, itemName in pairs(pool) do
            if itemName:lower() == lower then return itemID end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Hub-DB  (GermanysAllStarDB – Permissions pro Gilde)
---------------------------------------------------------------------------
ADDON.HubDB = {}
local HubDB = ADDON.HubDB

function HubDB:Initialize()
    if not GermanysAllStarDB then
        GermanysAllStarDB = { version = 1, profiles = {} }
    end
    -- Migration: alte Versionen
    if (GermanysAllStarDB.version or 0) < 1 then
        GermanysAllStarDB.version = 1
        GermanysAllStarDB.profiles = GermanysAllStarDB.profiles or {}
    end
end

function HubDB:GetProfile()
    local key = ADDON:GetProfileKey()
    if not key then return nil end
    if not GermanysAllStarDB.profiles[key] then
        GermanysAllStarDB.profiles[key] = {
            permissions    = {},
            officerMaxRank = 3, -- Standard: Rang 0-3 gelten als Offizier
        }
    end
    local p = GermanysAllStarDB.profiles[key]
    if not p.permissions then p.permissions = {} end
    if not p.officerMaxRank then p.officerMaxRank = 3 end
    return p
end

---------------------------------------------------------------------------
-- Permissions – Zugriffssteuerung pro App
---------------------------------------------------------------------------

--- Gibt den konfigurierten maximalen Offiziersrang-Index zurueck.
--- Rang 0 = GM, Rang 1 = erster Offiziersrang, etc.
--- Alle Raenge bis einschliesslich dieses Index gelten als "Offizier".
function ADDON:GetOfficerMaxRank()
    local profile = self.HubDB:GetProfile()
    if not profile then return 3 end
    return profile.officerMaxRank or 3
end

function ADDON:SetOfficerMaxRank(maxRank)
    local profile = self.HubDB:GetProfile()
    if not profile then return end
    profile.officerMaxRank = math.max(0, math.floor(maxRank or 3))
end

--- Bin ich Gildenmeister oder Offizier?
function ADDON:AmIOfficer()
    local _, _, _, rankIndex = self:GetGuildInfo()
    if rankIndex == nil then return false end
    return rankIndex <= self:GetOfficerMaxRank()
end

--- Ist ein anderer Spieler Offizier? (braucht GuildRoster-Daten)
function ADDON:IsPlayerOfficer(playerName)
    if not playerName then return false end
    local short = playerName:match("^([^-]+)") or playerName
    local shortLower = short:lower()
    local maxRank = self:GetOfficerMaxRank()
    for i = 1, GetNumGuildMembers() do
        local n, _, rankIndex = GetGuildRosterInfo(i)
        if n then
            local sn = (n:match("^([^-]+)") or n):lower()
            if sn == shortLower then
                return rankIndex <= maxRank
            end
        end
    end
    return false
end

--- Hat der aktuelle Spieler Zugriff auf eine App?
function ADDON:HasAppAccess(appName)
    -- Public Apps: immer fuer alle frei
    if self:IsPublicApp(appName) then return true end
    -- Offiziere/GM haben immer Zugriff
    if self:AmIOfficer() then return true end
    -- Whitelist pruefen
    local profile = self.HubDB:GetProfile()
    if not profile or not profile.permissions then return false end
    local perms = profile.permissions[appName]
    if not perms then return false end
    local myName = UnitName("player")
    if not myName then return false end
    return perms[myName] == true
end

--- Berechtigung setzen (true = Zugriff, nil = entfernen)
function ADDON:SetPermission(appName, playerName, access)
    local profile = self.HubDB:GetProfile()
    if not profile then return end
    if not profile.permissions[appName] then
        profile.permissions[appName] = {}
    end
    if access then
        profile.permissions[appName][playerName] = true
    else
        profile.permissions[appName][playerName] = nil
    end
end

--- Alle Berechtigungen fuer eine App lesen
function ADDON:GetPermissions(appName)
    local profile = self.HubDB:GetProfile()
    if not profile or not profile.permissions then return {} end
    return profile.permissions[appName] or {}
end

---------------------------------------------------------------------------
-- Permission Sync (GUILD Addon-Channel "GAS")
---------------------------------------------------------------------------
local PERM_PREFIX = "GAS"
local permSendQueue = {}
local permSending = false

local function ProcessPermQueue()
    if #permSendQueue == 0 then
        permSending = false
        return
    end
    permSending = true
    local msg = table.remove(permSendQueue, 1)
    C_ChatInfo.SendAddonMessage(PERM_PREFIX, msg, "GUILD")
    C_Timer.After(0.2, ProcessPermQueue)
end

local function QueuePermMsg(msg)
    table.insert(permSendQueue, msg)
    if not permSending then ProcessPermQueue() end
end

--- Einzelne Berechtigung broadcasten
function ADDON:BroadcastPermission(appName, playerName, access)
    QueuePermMsg("S:" .. appName .. ":" .. playerName .. ":" .. (access and "1" or "0"))
end

--- Alle Berechtigungen aller Apps broadcasten (nur Offiziere)
function ADDON:BroadcastAllPermissions()
    if not self:AmIOfficer() then return end
    local profile = self.HubDB:GetProfile()
    if not profile or not profile.permissions then return end
    for appName, players in pairs(profile.permissions) do
        for playerName, access in pairs(players) do
            if access then
                QueuePermMsg("S:" .. appName .. ":" .. playerName .. ":1")
            end
        end
    end
    QueuePermMsg("DONE")
    self:Debug("Perm-Broadcast gestartet.")
end

--- Eingehende Permission-Message verarbeiten
function ADDON:OnPermAddonMessage(prefix, msg, channel, sender)
    if prefix ~= PERM_PREFIX or channel ~= "GUILD" then return end
    local myName = UnitName("player")
    local senderShort = sender:match("^([^-]+)") or sender
    if senderShort == myName then return end
    -- Nur Offiziere duerfen Permissions aendern
    if not self:IsPlayerOfficer(senderShort) then
        self:Debug("Perm von Nicht-Offizier ignoriert: " .. senderShort)
        return
    end
    local cmd, rest = msg:match("^(%w+):(.+)$")
    if cmd == "S" and rest then
        local appName, playerName, access = rest:match("^([^:]+):([^:]+):(%d)$")
        if appName and playerName then
            self:SetPermission(appName, playerName, access == "1")
            self:Debug("Perm empfangen: " .. playerName .. " -> " .. appName .. " = " .. access)
        end
    end
    -- "DONE" message (kein rest noetig) – koennte fuer UI-Refresh genutzt werden
end

function ADDON:InitPermSync()
    C_ChatInfo.RegisterAddonMessagePrefix(PERM_PREFIX)

    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self, event, ...)
        if event == "CHAT_MSG_ADDON" then
            ADDON:OnPermAddonMessage(...)
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Gilden-Roster anfordern
            if C_GuildInfo and C_GuildInfo.GuildRoster then
                C_GuildInfo.GuildRoster()
            elseif GuildRoster then
                GuildRoster()
            end
            -- Nach kurzer Verzoegerung Permissions broadcasten (nur Offiziere)
            C_Timer.After(12, function()
                ADDON:BroadcastAllPermissions()
            end)
        end
    end)
end

---------------------------------------------------------------------------
-- Slash-Commands – ALLES ueber /ga
---------------------------------------------------------------------------
SLASH_GERMANYSALLSTAR1 = "/ga"
SLASH_GERMANYSALLSTAR2 = "/gsp" -- Alias leitet ebenfalls zum Hub
SlashCmdList["GERMANYSALLSTAR"] = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "debug on" then
        ADDON.debugEnabled = true
        ADDON:Print("Debug aktiviert.")
    elseif cmd == "debug off" then
        ADDON.debugEnabled = false
        ADDON:Print("Debug deaktiviert.")
    elseif cmd == "raid" then
        if ADDON.Raidplaner then ADDON.Raidplaner:ToggleMainFrame() end
    else
        if ADDON.Hub then ADDON.Hub:Toggle() end
    end
end

SLASH_GASRAIDPLANER1 = "/raidplaner"
SlashCmdList["GASRAIDPLANER"] = function()
    if ADDON.Raidplaner then ADDON.Raidplaner:ToggleMainFrame() end
end

---------------------------------------------------------------------------
-- Bootstrap
---------------------------------------------------------------------------
local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
bootFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ADDON.HubDB:Initialize()
        ADDON.DB:Initialize()
        if ADDON.Sync then ADDON.Sync:Init() end
        if ADDON.RaidplanerSync then ADDON.RaidplanerSync:Init() end
        ADDON:InitPermSync()
        ADDON:Print("v" .. ADDON.version .. " geladen.  |cffffd100/ga|r zum Oeffnen.")
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_GUILD_UPDATE" then
        ADDON.DB:EnsureProfile()
    end
end)
