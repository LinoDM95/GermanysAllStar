---------------------------------------------------------------------------
-- GuildStockPlanner – Sync.lua
-- Stille Gilden-Synchronisation ueber GUILD Addon-Messages.
-- Kein Whisper, kein Chat – komplett unsichtbar (wie DBM, Details, etc.).
--
-- Protokoll:
--   HI:fingerprint          – Login-Announce / Fingerprint-Check
--   RC:serializedRecipe     – Rezept-Daten (Full Sync)
--   DT:itemID:timestamp     – Tombstone / Loeschung (Full Sync)
--   FE                      – Full Sync beendet
--   AD:serializedRecipe     – Live: Rezept hinzugefuegt/geaendert
--   DL:itemID:timestamp     – Live: Rezept geloescht
--   BS:timestamp            – Bank-Scan Start (Zeitstempel)
--   BD:id1.cnt1,id2.cnt2,...– Bank-Scan Daten (Chunks)
--   BE                      – Bank-Scan Ende
--
-- Merge-Regel: Neuester Zeitstempel (modifiedAt) gewinnt immer.
-- Offline-Sicherheit: Daten werden lokal gespeichert (SavedVariables).
-- Beim naechsten gemeinsamen Online-Zeitpunkt wird automatisch gesynct.
---------------------------------------------------------------------------
local _, ADDON = ...

ADDON.Sync = {}
local Sync = ADDON.Sync

local PREFIX  = "GSP"
local CHANNEL = "GUILD"

-- Nachrichtentypen
local MSG_HELLO       = "HI"
local MSG_RECIPE      = "RC"
local MSG_TOMBSTONE   = "DT"
local MSG_FINISH      = "FE"
local MSG_LIVEADD     = "AD"
local MSG_LIVEDEL     = "DL"
local MSG_BANK_START  = "BS"
local MSG_BANK_DATA   = "BD"
local MSG_BANK_END    = "BE"

-- State
Sync.statusText        = "Bereit"
Sync.lastFullBroadcast = 0
Sync.initialized       = false

local outQueue          = {}
local mergeStats        = { added = 0, updated = 0, deleted = 0 }
local helloSent         = false

local FULL_BROADCAST_CD = 20   -- Sekunden Cooldown zwischen Full Broadcasts
local PERIODIC_INTERVAL = 300  -- Alle 5 Minuten HELLO senden
local BANK_CHUNK_SIZE   = 15   -- Items pro BD-Nachricht (255 Byte Limit)

-- Akkumulator fuer eingehende Bank-Scan-Daten
local incomingBank = {
    sender    = nil,
    ts        = 0,
    counts    = {},
    receiving = false,
}

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
    if not name then return nil end
    return name:match("^([^%-]+)") or name
end

---------------------------------------------------------------------------
-- Serialisierung  (Format mit Unter-Materialien beliebiger Tiefe)
--   mainItemID:desiredStock:yield:modifiedAt:m1.q1:>s1.sq1:>>ss1.ssq1:m2.q2:...
--   ">" Praefix gibt die Verschachtelungstiefe an.
--   Abwaertskompatibel: Rezepte ohne ">" werden als flache Materialliste gelesen.
---------------------------------------------------------------------------

local function SerializeRecipe(recipe)
    local parts = {
        tostring(recipe.mainItemID),
        tostring(recipe.desiredStock or 0),
        tostring(math.max(1, recipe.yield or 1)),
        tostring(recipe.modifiedAt or 0),
    }
    local function addMats(mats, depth)
        local prefix = string.rep(">", depth)
        for _, mat in ipairs(mats) do
            if mat.itemID and mat.qty then
                table.insert(parts, prefix .. mat.itemID .. "." .. mat.qty)
                if mat.subMats then
                    addMats(mat.subMats, depth + 1)
                end
            end
        end
    end
    addMats(recipe.mats or {}, 0)
    return table.concat(parts, ":")
end

local function DeserializeRecipe(data)
    local parts = { strsplit(":", data) }
    local mainItemID = tonumber(parts[1])
    if not mainItemID then return nil end

    local mats = {}
    -- depthStack[d+1] = { list = Ziel-Tabelle, lastEntry = letzter Eintrag }
    local depthStack = { { list = mats, lastEntry = nil } }

    for i = 5, #parts do
        local p = parts[i]
        -- Tiefe anhand der ">" Praefixe bestimmen
        local depth = 0
        while p:sub(depth + 1, depth + 1) == ">" do
            depth = depth + 1
        end
        local matStr = p:sub(depth + 1)
        local mID, mQty = matStr:match("^(%d+)%.(%d+)$")
        if mID and mQty then
            local entry = { itemID = tonumber(mID), qty = tonumber(mQty) }

            -- Ziel-Liste fuer diese Tiefe vorbereiten
            if depth > 0 then
                local parent = depthStack[depth]
                if parent and parent.lastEntry then
                    if not parent.lastEntry.subMats then
                        parent.lastEntry.subMats = {}
                    end
                    depthStack[depth + 1] = {
                        list = parent.lastEntry.subMats,
                        lastEntry = nil,
                    }
                end
            end

            local target = depthStack[depth + 1]
            if target then
                table.insert(target.list, entry)
                target.lastEntry = entry
            end
        end
    end

    return {
        mainItemID   = mainItemID,
        desiredStock = tonumber(parts[2]) or 0,
        yield        = math.max(1, tonumber(parts[3]) or 1),
        modifiedAt   = tonumber(parts[4]) or 0,
        mats         = mats,
    }
end

---------------------------------------------------------------------------
-- Fingerprint  (schneller Hash ueber alle Rezepte + Tombstones + Scan)
---------------------------------------------------------------------------

local function ComputeFingerprint()
    local recipes   = ADDON.DB:GetRecipes()
    local deletions = ADDON.DB:GetDeletions()
    local scan      = ADDON.DB:GetLastScan()
    local parts = {}
    for id, r in pairs(recipes) do
        table.insert(parts, id .. ":" .. (r.modifiedAt or 0))
    end
    for id, ts in pairs(deletions) do
        table.insert(parts, "d" .. id .. ":" .. ts)
    end
    -- Scan-Zeitstempel in Fingerprint aufnehmen
    table.insert(parts, "scan:" .. (scan.ts or 0))
    table.sort(parts)
    local str = table.concat(parts, ",")
    if str == "" then return "000000" end
    local hash = 0
    for i = 1, #str do
        hash = (hash * 31 + str:byte(i)) % 16777216
    end
    return string.format("%06x", hash)
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------

function Sync:SetStatus(text)
    self.statusText = text
    ADDON:Debug("Sync:", text)
    if ADDON.UI and ADDON.UI.UpdateScanStatus then
        ADDON.UI:UpdateScanStatus()
    end
end

function Sync:GetStatusText()
    return self.statusText
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function Sync:Init()
    if self.initialized then return end
    self.initialized = true

    -- Prefix registrieren
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX)
    end

    -- Event Frame
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            Sync:OnAddonMessage(...)
        elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUILD_UPDATE" then
            -- Einmalig HELLO senden sobald Gilde verfuegbar
            if not helloSent and ADDON:GetProfileKey() then
                helloSent = true
                ADDON.DB:EnsureProfile()
                ADDON.DB:CleanupDeletions()
                C_Timer.After(8, function()
                    if ADDON:GetProfileKey() then
                        Sync:BroadcastHello()
                    end
                end)
            end
        end
    end)

    -- Queue-Verarbeitung (1 Nachricht pro 0.12s – respektiert WoW Throttle)
    local elapsed = 0
    local queueFrame = CreateFrame("Frame")
    queueFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.12 then return end
        elapsed = 0
        if #outQueue > 0 then
            local msg = table.remove(outQueue, 1)
            SendMsg(msg)
        end
    end)

    -- Periodischer HELLO (alle 5 Minuten) – faengt Spaeteinsteiger auf
    self:SchedulePeriodicHello()

    ADDON:Debug("Sync initialisiert.")
end

function Sync:SchedulePeriodicHello()
    C_Timer.After(PERIODIC_INTERVAL, function()
        if ADDON:GetProfileKey() then
            Sync:BroadcastHello()
        end
        Sync:SchedulePeriodicHello()
    end)
end

---------------------------------------------------------------------------
-- Senden – Rezepte
---------------------------------------------------------------------------

--- HELLO mit Fingerprint senden – loesung Sync-Check aus.
function Sync:BroadcastHello()
    if not IsInGuild() then return end
    local fp = ComputeFingerprint()
    SendMsg(MSG_HELLO .. ":" .. fp)
    self:SetStatus("HELLO gesendet")
    ADDON:Debug("Sync HELLO, FP:", fp)
end

--- Full Broadcast einreihen (mit Cooldown).
function Sync:QueueFullBroadcast()
    if GetTime() - self.lastFullBroadcast < FULL_BROADCAST_CD then
        ADDON:Debug("Sync: Full broadcast cooldown aktiv, ueberspringe.")
        return false
    end
    self.lastFullBroadcast = GetTime()
    local delay = math.random(10, 30) / 10 -- 1-3 Sek zufaellige Verzoegerung
    C_Timer.After(delay, function()
        Sync:BroadcastFull()
    end)
    return true
end

--- Sendet alle Rezepte + Tombstones + Bank-Scan ueber Guild-Channel (Queue).
function Sync:BroadcastFull()
    if not IsInGuild() then return end
    local recipes   = ADDON.DB:GetRecipes()
    local deletions = ADDON.DB:GetDeletions()

    local count = 0
    for _, recipe in pairs(recipes) do
        QueueMsg(MSG_RECIPE .. ":" .. SerializeRecipe(recipe))
        count = count + 1
    end
    for id, ts in pairs(deletions) do
        QueueMsg(MSG_TOMBSTONE .. ":" .. id .. ":" .. ts)
    end
    QueueMsg(MSG_FINISH)

    -- Bank-Scan-Daten mitsenden
    local scan = ADDON.DB:GetLastScan()
    if scan.ts and scan.ts > 0 and scan.bankCounts then
        self:QueueBankScanMessages(scan.bankCounts, scan.ts)
    end

    self:SetStatus("Sende " .. count .. " Rezepte...")
    ADDON.DB:AddLogEntry("sync_out", MyName(), nil, count .. " Rezepte gesendet")
    ADDON:Debug("Sync: Full broadcast gestartet,", count, "Rezepte.")
end

--- Live-Broadcast: Rezept hinzugefuegt/geaendert.
function Sync:BroadcastRecipeAdd(recipe)
    if not recipe or not IsInGuild() then return end
    QueueMsg(MSG_LIVEADD .. ":" .. SerializeRecipe(recipe))
end

--- Live-Broadcast: Rezept geloescht.
function Sync:BroadcastRecipeDel(mainItemID)
    if not mainItemID or not IsInGuild() then return end
    local deletions = ADDON.DB:GetDeletions()
    local ts = deletions[mainItemID] or time()
    QueueMsg(MSG_LIVEDEL .. ":" .. mainItemID .. ":" .. ts)
end

---------------------------------------------------------------------------
-- Senden – Bank-Scan
---------------------------------------------------------------------------

--- Reiht BS/BD/BE-Nachrichten in die Queue ein.
function Sync:QueueBankScanMessages(bankCounts, timestamp)
    timestamp = timestamp or time()
    QueueMsg(MSG_BANK_START .. ":" .. timestamp)

    local chunk = {}
    local chunkCount = 0
    for itemID, count in pairs(bankCounts) do
        table.insert(chunk, itemID .. "." .. count)
        chunkCount = chunkCount + 1
        if chunkCount >= BANK_CHUNK_SIZE then
            QueueMsg(MSG_BANK_DATA .. ":" .. table.concat(chunk, ","))
            chunk = {}
            chunkCount = 0
        end
    end
    if chunkCount > 0 then
        QueueMsg(MSG_BANK_DATA .. ":" .. table.concat(chunk, ","))
    end

    QueueMsg(MSG_BANK_END)
end

--- Oeffentliche Funktion: Bank-Scan broadcasten (vom Scanner aufgerufen).
function Sync:BroadcastBankScan(bankCounts, timestamp)
    if not IsInGuild() then return end
    self:QueueBankScanMessages(bankCounts, timestamp)

    local count = 0
    for _ in pairs(bankCounts) do count = count + 1 end
    ADDON.DB:AddLogEntry("bank_out", MyName(), nil,
        count .. " Items gesendet")
    self:SetStatus("Bank-Scan gesendet (" .. count .. " Items)")
    ADDON:Debug("Sync: Bank-Scan gesendet,", count, "Items.")
end

---------------------------------------------------------------------------
-- Empfangen
---------------------------------------------------------------------------

function Sync:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX then return end
    if channel ~= "GUILD" then return end
    local senderName = StripRealm(sender)
    if senderName == MyName() then return end -- Eigene Nachrichten ignorieren

    local cmd, data = message:match("^(%a+):?(.*)")
    if not cmd then return end

    if cmd == MSG_HELLO then
        self:OnHello(data, senderName)
    elseif cmd == MSG_RECIPE then
        self:OnRecipeReceived(data, senderName)
    elseif cmd == MSG_TOMBSTONE then
        self:OnTombstoneReceived(data, senderName)
    elseif cmd == MSG_FINISH then
        self:OnFinish(senderName)
    elseif cmd == MSG_LIVEADD then
        self:OnLiveAdd(data, senderName)
    elseif cmd == MSG_LIVEDEL then
        self:OnLiveDel(data, senderName)
    elseif cmd == MSG_BANK_START then
        self:OnBankScanStart(data, senderName)
    elseif cmd == MSG_BANK_DATA then
        self:OnBankScanData(data, senderName)
    elseif cmd == MSG_BANK_END then
        self:OnBankScanEnd(senderName)
    end
end

---------------------------------------------------------------------------
-- HELLO – Fingerprint-Vergleich
---------------------------------------------------------------------------

function Sync:OnHello(data, sender)
    local theirFP = strtrim(data or "")
    local myFP    = ComputeFingerprint()

    if theirFP == myFP then
        self:SetStatus("Sync OK (" .. date("%H:%M") .. ")")
        ADDON:Debug("Sync: Fingerprints match mit", sender)
        return
    end

    -- Fingerprints unterschiedlich → unsere Daten senden
    ADDON:Debug("Sync: Fingerprint mismatch mit", sender, "– sende Daten")
    self:SetStatus("Sync mit " .. sender .. "...")
    self:QueueFullBroadcast()
end

---------------------------------------------------------------------------
-- Full Sync empfangen
---------------------------------------------------------------------------

function Sync:OnRecipeReceived(data, sender)
    local recipe = DeserializeRecipe(data)
    if not recipe or not recipe.mainItemID then return end
    self:MergeRecipe(recipe, sender)
end

function Sync:OnTombstoneReceived(data, sender)
    local parts = { strsplit(":", data) }
    local itemID = tonumber(strtrim(parts[1] or ""))
    local ts     = tonumber(parts[2]) or 0
    if not itemID then return end
    self:MergeTombstone(itemID, ts, sender)
end

function Sync:OnFinish(sender)
    local stats = mergeStats
    mergeStats  = { added = 0, updated = 0, deleted = 0 }

    local total = stats.added + stats.updated + stats.deleted
    if total > 0 then
        local detail = string.format("+%d ~%d -%d", stats.added, stats.updated, stats.deleted)
        ADDON.DB:AddLogEntry("sync_in", sender, nil, detail)
        self:SetStatus("Empfangen von " .. sender .. " (" .. detail .. ")")
        ADDON:Print("Sync von " .. sender .. ": " .. detail)
    else
        self:SetStatus("Sync OK (" .. date("%H:%M") .. ")")
    end

    self:RefreshUI()

    -- Auch unsere Daten senden (falls der Sender welche fehlt)
    -- Cooldown verhindert Endlosschleifen.
    self:QueueFullBroadcast()
end

---------------------------------------------------------------------------
-- Live-Aenderungen (einzelne Rezepte)
---------------------------------------------------------------------------

function Sync:OnLiveAdd(data, sender)
    local recipe = DeserializeRecipe(data)
    if not recipe or not recipe.mainItemID then return end

    if self:MergeRecipe(recipe, sender) then
        local name = GetItemInfo(recipe.mainItemID)
        ADDON.DB:AddLogEntry("add", sender, recipe.mainItemID,
            (name or ("Item:" .. recipe.mainItemID)))
        self:SetStatus(sender .. ": +" .. (name or recipe.mainItemID))
        self:RefreshUI()
    end
end

function Sync:OnLiveDel(data, sender)
    local parts  = { strsplit(":", data) }
    local itemID = tonumber(strtrim(parts[1] or ""))
    local ts     = tonumber(parts[2]) or 0
    if not itemID then return end

    if self:MergeTombstone(itemID, ts, sender) then
        local name = GetItemInfo(itemID)
        ADDON.DB:AddLogEntry("del", sender, itemID,
            (name or ("Item:" .. itemID)))
        self:SetStatus(sender .. ": -" .. (name or itemID))
        self:RefreshUI()
    end
end

---------------------------------------------------------------------------
-- Bank-Scan empfangen
---------------------------------------------------------------------------

function Sync:OnBankScanStart(data, sender)
    local ts = tonumber(data)
    if not ts then return end

    local localScan = ADDON.DB:GetLastScan()
    if localScan.ts and localScan.ts >= ts then
        -- Unser Scan ist neuer oder gleich → ignorieren
        incomingBank.receiving = false
        ADDON:Debug("Sync: Bank-Scan von", sender, "ignoriert (lokal neuer)")
        return
    end

    incomingBank.sender    = sender
    incomingBank.ts        = ts
    incomingBank.counts    = {}
    incomingBank.receiving = true
    ADDON:Debug("Sync: Bank-Scan von", sender, "wird empfangen, ts:", ts)
end

function Sync:OnBankScanData(data, sender)
    if not incomingBank.receiving then return end
    if sender ~= incomingBank.sender then return end

    for pair in data:gmatch("[^,]+") do
        local id, count = pair:match("^(%d+)%.(%d+)$")
        if id and count then
            local numID    = tonumber(id)
            local numCount = tonumber(count)
            incomingBank.counts[numID] = (incomingBank.counts[numID] or 0) + numCount
        end
    end
end

function Sync:OnBankScanEnd(sender)
    if not incomingBank.receiving then return end
    if sender ~= incomingBank.sender then return end

    incomingBank.receiving = false

    -- Nochmal pruefen ob noch neuer als lokal
    local localScan = ADDON.DB:GetLastScan()
    if localScan.ts and localScan.ts >= incomingBank.ts then
        ADDON:Debug("Sync: Bank-Scan verworfen (lokal inzwischen neuer)")
        return
    end

    -- Speichern mit dem Original-Timestamp des Senders
    ADDON.DB:SaveScanResults(incomingBank.counts, incomingBank.ts)

    local count = 0
    for _ in pairs(incomingBank.counts) do count = count + 1 end

    ADDON.DB:AddLogEntry("bank_in", sender, nil,
        count .. " Items empfangen")
    self:SetStatus("Bank von " .. sender .. " (" .. count .. " Items)")
    ADDON:Print("Gildenbank-Daten von " .. sender
        .. " empfangen (" .. count .. " Items).")

    self:RefreshUI()
end

---------------------------------------------------------------------------
-- Merge-Logik (Timestamp-basiert, neuester gewinnt immer)
---------------------------------------------------------------------------

--- Merged ein empfangenes Rezept. Gibt true zurueck wenn uebernommen.
function Sync:MergeRecipe(recipe, sender)
    local profile = ADDON.DB:GetProfile()
    if not profile then return false end

    local myRecipe   = profile.recipes[recipe.mainItemID]
    local myDeletion = (profile.deletions or {})[recipe.mainItemID]

    -- Wenn wir geloescht haben UND die Loeschung neuer/gleich → ignorieren
    if myDeletion and myDeletion >= (recipe.modifiedAt or 0) then
        return false
    end

    -- Wenn unsere Version neuer/gleich → ignorieren
    if myRecipe and (myRecipe.modifiedAt or 0) >= (recipe.modifiedAt or 0) then
        return false
    end

    -- Ihre Version ist neuer → uebernehmen (direkt in profile – KEIN Broadcast!)
    local isNew = (myRecipe == nil)
    profile.recipes[recipe.mainItemID] = {
        mainItemID   = recipe.mainItemID,
        desiredStock = recipe.desiredStock or 0,
        yield        = math.max(1, recipe.yield or 1),
        mats         = recipe.mats or {},
        modifiedAt   = recipe.modifiedAt or 0,
    }
    -- Tombstone entfernen
    if profile.deletions then
        profile.deletions[recipe.mainItemID] = nil
    end

    if isNew then
        mergeStats.added = mergeStats.added + 1
    else
        mergeStats.updated = mergeStats.updated + 1
    end

    ADDON:Debug("Sync: Rezept uebernommen von", sender, ":", recipe.mainItemID)
    return true
end

--- Merged einen empfangenen Tombstone. Gibt true zurueck wenn Rezept geloescht.
function Sync:MergeTombstone(itemID, ts, sender)
    local profile = ADDON.DB:GetProfile()
    if not profile then return false end

    local myRecipe = profile.recipes[itemID]

    -- Wenn unser Rezept neuer ist → behalten
    if myRecipe and (myRecipe.modifiedAt or 0) > ts then
        return false
    end

    -- Loeschung ist neuer → Rezept entfernen, Tombstone setzen
    local hadRecipe = (myRecipe ~= nil)
    profile.recipes[itemID] = nil
    if not profile.deletions then profile.deletions = {} end
    local myTs = profile.deletions[itemID] or 0
    if ts > myTs then
        profile.deletions[itemID] = ts
    end

    if hadRecipe then
        mergeStats.deleted = mergeStats.deleted + 1
    end

    ADDON:Debug("Sync: Tombstone uebernommen von", sender, ":", itemID)
    return hadRecipe
end

---------------------------------------------------------------------------
-- UI-Refresh (aktualisiert GSP + GuildStocks)
---------------------------------------------------------------------------

function Sync:RefreshUI()
    -- GSP Hauptfenster
    if ADDON.UI and ADDON.UI.mainFrame and ADDON.UI.mainFrame:IsShown() then
        local tab = ADDON.UI.activeTab
        if tab == 1 then
            ADDON.UI:RefreshRecipeList()
        elseif tab == 2 then
            ADDON.UI:RefreshFarmTab()
        elseif tab == 3 then
            ADDON.UI:RefreshStockTab()
        elseif tab == 4 then
            ADDON.UI:RefreshLogTab()
        end
    end

    -- GuildStocks (separates Fenster)
    if ADDON.GuildStocks and ADDON.GuildStocks.gsFrame
        and ADDON.GuildStocks.gsFrame:IsShown() then
        ADDON.GuildStocks:Refresh()
    end
end

---------------------------------------------------------------------------
-- Manueller Sync
---------------------------------------------------------------------------

function Sync:ManualSync()
    if not IsInGuild() then
        ADDON:Print("Du bist in keiner Gilde.")
        return
    end
    self.lastFullBroadcast = 0 -- Cooldown zuruecksetzen
    self:BroadcastHello()
    C_Timer.After(1, function()
        Sync.lastFullBroadcast = 0
        Sync:BroadcastFull()
    end)
    ADDON.DB:AddLogEntry("sync_out", MyName(), nil, "Manueller Sync gestartet")
    self:SetStatus("Manueller Sync...")
end
