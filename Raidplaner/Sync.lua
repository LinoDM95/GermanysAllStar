---------------------------------------------------------------------------
-- Raidplaner – Sync.lua
-- Stille Gilden-Synchronisation ueber GUILD Addon-Messages.
--
-- Protokoll (prefix "GASRP"):
--   RH:<fingerprint>   – Hello / Fingerprint-Check
--   RA:<payload>        – Raid-Daten (Upsert)
--   RD:<raidId>:<ts>    – Raid-Loeschung (Tombstone)
--   RS:<payload>        – Signup-Daten (Upsert)
--   RF                  – Full-Sync beendet
--
-- Merge-Regel: Neuester updatedAt gewinnt immer.
---------------------------------------------------------------------------
local _, ADDON = ...

ADDON.RaidplanerSync = {}
local RSync = ADDON.RaidplanerSync

local PREFIX  = "GASRP"
local CHANNEL = "GUILD"

-- Nachrichtentypen
local MSG_HELLO  = "RH"
local MSG_RAID   = "RA"
local MSG_DELETE  = "RD"
local MSG_SIGNUP  = "RS"
local MSG_FINISH  = "RF"

-- State
RSync.initialized       = false
RSync.statusText        = "Bereit"
RSync.lastFullBroadcast = 0

local outQueue       = {}
local FULL_BC_CD     = 20   -- Cooldown Full Broadcast
local PERIODIC_INT   = 300  -- Alle 5 Min HELLO

---------------------------------------------------------------------------
-- Helfer
---------------------------------------------------------------------------

local function SendMsg(msg)
    if not IsInGuild() then return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, CHANNEL)
    elseif SendAddonMessage then
        SendAddonMessage(PREFIX, msg, CHANNEL)
    end
end

local function QueueMsg(msg)
    table.insert(outQueue, msg)
end

local function MyName()
    return UnitName("player")
end

local function StripRealm(name)
    return name and (name:match("^([^%-]+)") or name) or nil
end

---------------------------------------------------------------------------
-- Serialisierung – Raid
-- Neues Format:
--   id:raidKey:size:date:time:createdBy:createdAt:updatedAt:state:note
-- Älteres Format (abwärtskompatibel weiter unterstützt):
--   id:raidKey:size:date:time:createdBy:createdAt:updatedAt:note
-- Note ist jeweils das LETZTE Feld (darf ":" enthalten).
---------------------------------------------------------------------------

local function SerializeRaid(raid)
    return table.concat({
        tostring(raid.id or ""),
        tostring(raid.raidKey or ""),
        tostring(raid.size or 10),
        tostring(raid.date or ""),
        tostring(raid.time or ""),
        tostring(raid.createdBy or ""),
        tostring(raid.createdAt or 0),
        tostring(raid.updatedAt or 0),
        tostring(raid.state or "PLANNED"),
        tostring(raid.note or ""),
    }, ":")
end

local function DeserializeRaid(data)
    local parts = { strsplit(":", data) }
    if #parts < 8 then return nil end
    local id = parts[1]
    if not id or id == "" then return nil end

    local raidKey = parts[2] or ""
    local def     = ADDON.RaidData:GetByKey(raidKey)

    local size     = tonumber(parts[3]) or 10
    local dateStr  = parts[4] or ""
    local timeStr  = parts[5] or ""
    local createdBy  = parts[6] or ""
    local createdAt  = tonumber(parts[7]) or 0
    local updatedAt  = tonumber(parts[8]) or 0

    local state
    local noteFrags = {}

    if #parts >= 9 then
        -- Neues Format mit state an Index 9
        if #parts >= 10 then
            state = parts[9]
            for i = 10, #parts do noteFrags[#noteFrags + 1] = parts[i] end
        else
            -- Kein Note-Feld, nur State
            state = parts[9]
        end
    else
        -- Altes Format: kein state, Note ab Index 9
        state = "PLANNED"
        for i = 9, #parts do noteFrags[#noteFrags + 1] = parts[i] end
    end

    return {
        id         = id,
        raidKey    = raidKey,
        raidName   = def and def.name or raidKey,
        size       = size,
        date       = dateStr,
        time       = timeStr,
        createdBy  = createdBy,
        createdAt  = createdAt,
        updatedAt  = updatedAt,
        state      = state or "PLANNED",
        note       = table.concat(noteFrags, ":"),
        signups    = {},
    }
end

---------------------------------------------------------------------------
-- Serialisierung – Signup
-- Format:  raidId:name:class:spec:role:status:updatedAt:comment
-- Comment ist das LETZTE Feld (darf ":" enthalten).
---------------------------------------------------------------------------

local function SerializeSignup(raidId, s)
    return table.concat({
        tostring(raidId),
        tostring(s.name or ""),
        tostring(s.class or ""),
        tostring(s.spec or ""),
        tostring(s.role or ""),
        tostring(s.confirmed and 1 or 0),
        tostring(s.status or ""),
        tostring(s.updatedAt or 0),
        tostring(s.comment or ""),
    }, ":")
end

local function DeserializeSignup(data)
    local parts = { strsplit(":", data) }
    if #parts < 5 then return nil, nil end

    -- Neues Format (9+ Felder):
    -- raidId:name:class:spec:role:confirmed:status:updatedAt:comment
    if #parts >= 8 and tonumber(parts[8]) then
        local commentFrags = {}
        for i = 9, #parts do commentFrags[#commentFrags + 1] = parts[i] end
        return parts[1], {
            name      = parts[2] or "",
            class     = parts[3] or "",
            spec      = parts[4] or "",
            role      = parts[5] or "",
            confirmed = (parts[6] == "1"),
            status    = parts[7] or "",
            updatedAt = tonumber(parts[8]) or 0,
            comment   = table.concat(commentFrags, ":"),
        }
    end

    -- Mittleres Format (ohne confirmed, aber mit spec/role):
    -- raidId:name:class:spec:role:status:updatedAt:comment
    if #parts >= 7 and tonumber(parts[7]) then
        local commentFrags = {}
        for i = 8, #parts do commentFrags[#commentFrags + 1] = parts[i] end
        return parts[1], {
            name      = parts[2] or "",
            class     = parts[3] or "",
            spec      = parts[4] or "",
            role      = parts[5] or "",
            confirmed = nil,
            status    = parts[6] or "",
            updatedAt = tonumber(parts[7]) or 0,
            comment   = table.concat(commentFrags, ":"),
        }
    end

    -- Ganz altes Format (6+ Felder): raidId:name:class:status:updatedAt:comment
    local commentFrags = {}
    for i = 6, #parts do commentFrags[#commentFrags + 1] = parts[i] end
    return parts[1], {
        name      = parts[2] or "",
        class     = parts[3] or "",
        spec      = "",
        role      = "",
        confirmed = nil,
        status    = parts[4] or "",
        updatedAt = tonumber(parts[5]) or 0,
        comment   = table.concat(commentFrags, ":"),
    }
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function RSync:Init()
    if self.initialized then return end
    self.initialized = true

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX)
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            RSync:OnAddonMessage(...)
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(12, function()
                if ADDON:GetProfileKey() then
                    ADDON.RaidplanerDB:CleanupDeletions()
                    RSync:BroadcastHello()
                end
            end)
        end
    end)

    -- Queue-Verarbeitung (1 Nachricht pro 0.12s)
    local elapsed = 0
    local qf = CreateFrame("Frame")
    qf:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.12 then return end
        elapsed = 0
        if #outQueue > 0 then
            SendMsg(table.remove(outQueue, 1))
        end
    end)

    self:SchedulePeriodic()
    ADDON:Debug("RaidplanerSync initialisiert.")
end

function RSync:SchedulePeriodic()
    C_Timer.After(PERIODIC_INT, function()
        if ADDON:GetProfileKey() then
            RSync:BroadcastHello()
        end
        RSync:SchedulePeriodic()
    end)
end

---------------------------------------------------------------------------
-- Senden
---------------------------------------------------------------------------

function RSync:BroadcastHello()
    if not IsInGuild() then return end
    local fp = ADDON.RaidplanerDB:ComputeFingerprint()
    SendMsg(MSG_HELLO .. ":" .. fp)
end

function RSync:QueueFullBroadcast()
    if GetTime() - self.lastFullBroadcast < FULL_BC_CD then return end
    self.lastFullBroadcast = GetTime()
    C_Timer.After(math.random(10, 30) / 10, function()
        RSync:BroadcastFull()
    end)
end

function RSync:BroadcastFull()
    if not IsInGuild() then return end
    local raids = ADDON.RaidplanerDB:GetRaids()

    for _, raid in pairs(raids) do
        QueueMsg(MSG_RAID .. ":" .. SerializeRaid(raid))
        -- Signups einzeln senden (fuer Message-Limit)
        if raid.signups then
            for _, signup in pairs(raid.signups) do
                QueueMsg(MSG_SIGNUP .. ":" .. SerializeSignup(raid.id, signup))
            end
        end
    end

    local dels = ADDON.RaidplanerDB:GetDeletions()
    for id, ts in pairs(dels) do
        QueueMsg(MSG_DELETE .. ":" .. id .. ":" .. ts)
    end

    QueueMsg(MSG_FINISH)
end

--- Live-Broadcast: Raid hinzugefuegt/geaendert.
function RSync:BroadcastRaid(raid)
    if not raid or not IsInGuild() then return end
    QueueMsg(MSG_RAID .. ":" .. SerializeRaid(raid))
    if raid.signups then
        for _, signup in pairs(raid.signups) do
            QueueMsg(MSG_SIGNUP .. ":" .. SerializeSignup(raid.id, signup))
        end
    end
end

--- Live-Broadcast: Raid geloescht.
function RSync:BroadcastDelete(raidId)
    if not raidId or not IsInGuild() then return end
    local dels = ADDON.RaidplanerDB:GetDeletions()
    local ts = dels[raidId] or time()
    QueueMsg(MSG_DELETE .. ":" .. raidId .. ":" .. ts)
end

--- Live-Broadcast: Signup.
function RSync:BroadcastSignup(raidId, signup)
    if not raidId or not signup or not IsInGuild() then return end
    QueueMsg(MSG_SIGNUP .. ":" .. SerializeSignup(raidId, signup))
end

---------------------------------------------------------------------------
-- Empfangen
---------------------------------------------------------------------------

function RSync:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or channel ~= "GUILD" then return end
    local senderName = StripRealm(sender)
    if senderName == MyName() then return end

    local cmd, data = message:match("^(%a+):?(.*)")
    if not cmd then return end

    if cmd == MSG_HELLO then
        self:OnHello(data, senderName)
    elseif cmd == MSG_RAID then
        self:OnRaidReceived(data, senderName)
    elseif cmd == MSG_DELETE then
        self:OnDeleteReceived(data, senderName)
    elseif cmd == MSG_SIGNUP then
        self:OnSignupReceived(data, senderName)
    elseif cmd == MSG_FINISH then
        self:OnFinish(senderName)
    end
end

---------------------------------------------------------------------------
-- Handler
---------------------------------------------------------------------------

function RSync:OnHello(data, sender)
    local theirFP = strtrim(data or "")
    local myFP    = ADDON.RaidplanerDB:ComputeFingerprint()
    if theirFP == myFP then return end
    ADDON:Debug("RSync: Fingerprint mismatch mit", sender)
    self:QueueFullBroadcast()
end

function RSync:OnRaidReceived(data, sender)
    local raid = DeserializeRaid(data)
    if not raid or not raid.id then return end

    local dels = ADDON.RaidplanerDB:GetDeletions()
    if dels[raid.id] and dels[raid.id] >= (raid.updatedAt or 0) then
        return -- Loeschung ist neuer
    end

    local localRaid = ADDON.RaidplanerDB:GetRaid(raid.id)
    if localRaid and (localRaid.updatedAt or 0) >= (raid.updatedAt or 0) then
        return -- Lokale Version neuer
    end

    -- Lokale Signups bewahren (die kommen ggf. spaeter per RS-Message)
    if localRaid and localRaid.signups then
        for name, signup in pairs(localRaid.signups) do
            if not raid.signups[name]
                or (raid.signups[name].updatedAt or 0) < (signup.updatedAt or 0) then
                raid.signups[name] = signup
            end
        end
    end

    ADDON.RaidplanerDB:SaveRaid(raid)
    self:RefreshUI()
end

function RSync:OnDeleteReceived(data, sender)
    local parts  = { strsplit(":", data) }
    local raidId = parts[1]
    local ts     = tonumber(parts[2]) or 0
    if not raidId or raidId == "" then return end

    local localRaid = ADDON.RaidplanerDB:GetRaid(raidId)
    if localRaid and (localRaid.updatedAt or 0) > ts then
        return -- Lokaler Raid neuer als Loeschung
    end

    ADDON.RaidplanerDB:DeleteRaid(raidId)
    self:RefreshUI()
end

function RSync:OnSignupReceived(data, sender)
    local raidId, signup = DeserializeSignup(data)
    if not raidId or not signup or signup.name == "" then return end

    local raid = ADDON.RaidplanerDB:GetRaid(raidId)
    if not raid then return end
    if not raid.signups then raid.signups = {} end

    local existing = raid.signups[signup.name]
    if existing and (existing.updatedAt or 0) >= (signup.updatedAt or 0) then
        return -- Existierender Signup neuer
    end

    raid.signups[signup.name] = signup
    self:RefreshUI()
end

function RSync:OnFinish(sender)
    -- Eigene Daten zuruecksenden (Cooldown verhindert Loops)
    self:QueueFullBroadcast()
end

---------------------------------------------------------------------------
-- UI-Refresh
---------------------------------------------------------------------------

function RSync:RefreshUI()
    if ADDON.Raidplaner and ADDON.Raidplaner.rpFrame
        and ADDON.Raidplaner.rpFrame:IsShown() then
        ADDON.Raidplaner:RefreshCalendar()
        -- Wenn Detail-View offen ist, auch aktualisieren
        if ADDON.Raidplaner.detailFrame
            and ADDON.Raidplaner.detailFrame:IsShown()
            and ADDON.Raidplaner.detailFrame.currentRaidId then
            ADDON.Raidplaner:ShowRaidDetail(ADDON.Raidplaner.detailFrame.currentRaidId)
        end
    end
end
