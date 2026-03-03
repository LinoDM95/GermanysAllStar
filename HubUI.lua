---------------------------------------------------------------------------
-- GermanysAllStar – HubUI.lua
-- Hub / App-Launcher + Rechteverwaltung (Whitelist)
-- Nur Gildenmeister & Offiziere sehen die Rechteverwaltung.
-- Unter Offizieren sind alle Apps standardmaessig gesperrt.
---------------------------------------------------------------------------
local _, ADDON = ...

ADDON.Hub = {}
local Hub = ADDON.Hub

---------------------------------------------------------------------------
-- Layout-Konstanten
---------------------------------------------------------------------------
local HUB_W, HUB_H     = 480, 580
local PERM_W, PERM_H    = 560, 560
local LOGO_TEX           = "Interface\\AddOns\\GermanysAllStar\\Textures\\logo"
local LOGO_ALPHA_HUB     = 0.30      -- deutlich sichtbar
local LOGO_SIZE_HUB      = 320

local BD_MAIN = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local BD_CARD = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

---------------------------------------------------------------------------
-- Lokale Refs
---------------------------------------------------------------------------
local hubFrame
local permFrame, permScrollContent, permRows
local appCards = {}

---------------------------------------------------------------------------
-- Kleine Helfer
---------------------------------------------------------------------------

local function MakeMovable(frame)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
end

local function CreateLabel(parent, font, text, anchor, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetText(text)
    if anchor then fs:SetPoint(anchor, x or 0, y or 0) end
    return fs
end

local function CreateBtn(parent, w, h, label, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(w, h)
    btn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(0.15, 0.15, 0.22, 1)
    btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("CENTER")
    txt:SetText(label)
    btn.label = txt
    btn:SetScript("OnClick", onClick)
    return btn
end

---------------------------------------------------------------------------
-- App-Card erzeugen
---------------------------------------------------------------------------

local function CreateAppCard(parent, index, data)
    local y = -68 - (index - 1) * 94

    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    card:SetSize(HUB_W - 32, 84)
    card:SetPoint("TOPLEFT", 16, y)
    card:SetBackdrop(BD_CARD)
    card:SetBackdropColor(0.08, 0.08, 0.12, 0.92)
    card:SetBackdropBorderColor(data.color[1], data.color[2], data.color[3], 0.6)

    -- Hover
    local hl = card:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(data.color[1], data.color[2], data.color[3], 0.12)

    -- Akzentbalken
    local accent = card:CreateTexture(nil, "ARTWORK")
    accent:SetSize(4, 64)
    accent:SetPoint("LEFT", 8, 0)
    accent:SetColorTexture(data.color[1], data.color[2], data.color[3], 0.85)

    -- Name
    card.nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.nameText:SetText("|cffffffff" .. data.name .. "|r")
    card.nameText:SetPoint("TOPLEFT", 22, -12)

    -- Beschreibung
    card.descText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.descText:SetText(data.description)
    card.descText:SetPoint("TOPLEFT", 22, -30)
    card.descText:SetWidth(320)
    card.descText:SetJustifyH("LEFT")

    -- Status / Lock
    card.statusText = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.statusText:SetPoint("BOTTOMRIGHT", -16, 8)
    card.statusText:SetJustifyH("RIGHT")

    -- Pfeil
    card.arrow = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.arrow:SetText("|cff888888>|r")
    card.arrow:SetPoint("RIGHT", -16, 0)

    -- Lock-Overlay (fuer gesperrte Apps)
    card.lockOverlay = card:CreateTexture(nil, "OVERLAY", nil, 7)
    card.lockOverlay:SetAllPoints()
    card.lockOverlay:SetColorTexture(0, 0, 0, 0.55)
    card.lockOverlay:Hide()

    card.lockText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.lockText:SetText("|cffff4444Gesperrt|r")
    card.lockText:SetPoint("CENTER")
    card.lockText:Hide()

    card.appKey = data.appKey
    card.openFn  = data.onClick

    card:SetScript("OnClick", function()
        if not ADDON:HasAppAccess(data.appKey) then
            ADDON:Print("|cffff4444Kein Zugriff auf " .. data.name .. ". Frage einen Offizier.|r")
            return
        end
        data.onClick()
    end)

    return card
end

---------------------------------------------------------------------------
-- App-Cards aktualisieren (Lock-Status)
---------------------------------------------------------------------------

local function RefreshAppCards()
    for _, card in ipairs(appCards) do
        local hasAccess = ADDON:HasAppAccess(card.appKey)
        if hasAccess then
            card.lockOverlay:Hide()
            card.lockText:Hide()
            card.arrow:SetText("|cff888888>|r")
            card.statusText:SetText("")
        else
            card.lockOverlay:Show()
            card.lockText:Show()
            card.arrow:SetText("")
            card.statusText:SetText("|cffff4444Kein Zugriff|r")
        end
    end
end

---------------------------------------------------------------------------
-- Perm-Panel: MATRIX-VIEW – alle Apps als Spalten pro Spieler
-- (nur fuer Offiziere sichtbar)
---------------------------------------------------------------------------

-- Spalten-Layout fuer App-Checkboxen
-- Feste Positionen: Name (links), Rang, dann pro App eine Spalte
local COL_NAME_X  = 6
local COL_RANK_X  = 175
local COL_APP_START_X = 290  -- Startpunkt fuer App-Spalten
local COL_APP_WIDTH   = 80   -- Breite pro App-Spalte

local function CreatePermPanel()
    if permFrame then return end

    permFrame = CreateFrame("Frame", "GASPermFrame", UIParent, "BackdropTemplate")
    permFrame:SetSize(PERM_W, PERM_H)
    permFrame:SetPoint("CENTER", 240, 0)
    permFrame:SetFrameStrata("DIALOG")
    permFrame:SetBackdrop(BD_MAIN)
    permFrame:SetBackdropColor(0.04, 0.04, 0.07, 0.97)
    permFrame:SetBackdropBorderColor(0.7, 0.55, 0.15, 1)
    MakeMovable(permFrame)
    permFrame:Hide()

    -- Logo Hintergrund
    local logo = permFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    logo:SetTexture(LOGO_TEX)
    logo:SetSize(200, 200)
    logo:SetPoint("CENTER", 0, 0)
    logo:SetAlpha(0.08)

    -- Titel
    CreateLabel(permFrame, "GameFontNormalLarge",
        "|cffff8800Rechteverwaltung|r", "TOPLEFT", 16, -14)

    -- Close
    local closeBtn = CreateFrame("Button", nil, permFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Info-Text
    CreateLabel(permFrame, "GameFontDisableSmall",
        "Offiziere & GM: immer Zugriff.  |cff66bb66Gruen|r = Immer frei (Public App).\nHier bestimmst du fuer jedes Mitglied den Zugang zu jeder App.",
        "TOPLEFT", 16, -38)

    -- Offiziersrang-Schwelle
    CreateLabel(permFrame, "GameFontNormalSmall",
        "Offizier ab Rang (0 = GM, hoeher = mehr Raenge):", "TOPLEFT", 16, -68)

    local rankValLabel = CreateLabel(permFrame, "GameFontNormal", "", "TOPLEFT", 370, -66)

    local rankSlider = CreateFrame("Slider", nil, permFrame, "OptionsSliderTemplate")
    rankSlider:SetSize(200, 16)
    rankSlider:SetPoint("TOPLEFT", 16, -86)
    rankSlider:SetMinMaxValues(0, 9)
    rankSlider:SetValueStep(1)
    rankSlider:SetObeyStepOnDrag(true)
    rankSlider.Low:SetText("0")
    rankSlider.High:SetText("9")
    rankSlider:SetValue(ADDON:GetOfficerMaxRank())
    rankValLabel:SetText("|cffffd100Rang 0 - " .. ADDON:GetOfficerMaxRank() .. "|r")
    rankSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        ADDON:SetOfficerMaxRank(value)
        rankValLabel:SetText("|cffffd100Rang 0 - " .. value .. "|r")
        Hub:RefreshPermPanel()
        RefreshAppCards()
    end)

    -- Separator 1
    local sep1 = permFrame:CreateTexture(nil, "ARTWORK")
    sep1:SetHeight(1)
    sep1:SetPoint("TOPLEFT", 12, -108)
    sep1:SetPoint("TOPRIGHT", -12, -108)
    sep1:SetColorTexture(0.5, 0.4, 0.15, 0.5)

    -- Kopfzeile: Name, Rang, dann pro App eine Spalte
    CreateLabel(permFrame, "GameFontHighlightSmall", "Name", "TOPLEFT", COL_NAME_X + 6, -116)
    CreateLabel(permFrame, "GameFontHighlightSmall", "Rang", "TOPLEFT", COL_RANK_X, -116)

    for i, app in ipairs(ADDON.allApps) do
        local xPos = COL_APP_START_X + (i - 1) * COL_APP_WIDTH
        local lbl = CreateLabel(permFrame, "GameFontHighlightSmall", app.label, "TOPLEFT", xPos, -116)
        if app.public then
            lbl:SetText("|cff66bb66" .. app.label .. "|r")
        end
    end

    -- Separator 2
    local sep2 = permFrame:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT", 12, -128)
    sep2:SetPoint("TOPRIGHT", -12, -128)
    sep2:SetColorTexture(0.4, 0.4, 0.4, 0.3)

    -- ScrollFrame
    local scrollFrame = CreateFrame("ScrollFrame", nil, permFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -132)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 50)
    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(PERM_W - 48, 1)
    scrollFrame:SetScrollChild(scrollContent)
    permScrollContent = scrollContent
    permRows = {}

    -- Buttons unten
    local allOnBtn = CreateBtn(permFrame, 170, 26, "Alle erlauben (nicht-frei)", function()
        Hub:SetAllPermissions(true)
    end)
    allOnBtn:SetPoint("BOTTOMLEFT", 12, 14)

    local allOffBtn = CreateBtn(permFrame, 170, 26, "Alle sperren (nicht-frei)", function()
        Hub:SetAllPermissions(false)
    end)
    allOffBtn:SetPoint("LEFT", allOnBtn, "RIGHT", 8, 0)

    -- Roster-Update registrieren
    permFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
    permFrame:SetScript("OnEvent", function(self, event)
        if event == "GUILD_ROSTER_UPDATE" and permFrame:IsShown() then
            Hub:RefreshPermPanel()
        end
    end)
end

---------------------------------------------------------------------------
-- Perm-Row Helfer – jetzt mit dynamischen App-Checkboxen
---------------------------------------------------------------------------

local function GetPermRow(index)
    if permRows[index] then return permRows[index] end

    local row = CreateFrame("Frame", nil, permScrollContent)
    row:SetHeight(24)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * 25)
    row:SetPoint("RIGHT", permScrollContent, "RIGHT")

    -- Zebra
    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.03)
    end

    -- Name
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", COL_NAME_X, 0)
    row.nameText:SetWidth(160)
    row.nameText:SetJustifyH("LEFT")

    -- Rang
    row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.rankText:SetPoint("LEFT", COL_RANK_X, 0)
    row.rankText:SetWidth(105)
    row.rankText:SetJustifyH("LEFT")

    -- Pro App eine Checkbox + Status-Label
    row.appChecks = {}
    row.appLabels = {}
    for i, app in ipairs(ADDON.allApps) do
        local xPos = COL_APP_START_X + (i - 1) * COL_APP_WIDTH

        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("LEFT", xPos + 4, 0)
        row.appChecks[i] = cb

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 1, 0)
        row.appLabels[i] = lbl
    end

    permRows[index] = row
    return row
end

---------------------------------------------------------------------------
-- Perm-Panel aktualisieren – Matrix-View
---------------------------------------------------------------------------

function Hub:RefreshPermPanel()
    if not permFrame or not permFrame:IsShown() then return end

    local numMembers = GetNumGuildMembers()
    local maxRank = ADDON:GetOfficerMaxRank()

    -- Berechtigungen pro App laden
    local appPerms = {}
    for _, app in ipairs(ADDON.allApps) do
        appPerms[app.key] = ADDON:GetPermissions(app.key)
    end

    -- Gilden-Mitglieder sammeln und sortieren
    local members = {}
    for i = 1, numMembers do
        local name, rank, rankIndex, level, class = GetGuildRosterInfo(i)
        if name then
            local shortName = name:match("^([^-]+)") or name
            table.insert(members, {
                name      = shortName,
                rank      = rank or "?",
                rankIndex = rankIndex or 99,
            })
        end
    end

    -- Sortierung: Offiziere oben, dann alphabetisch
    table.sort(members, function(a, b)
        if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
        return a.name < b.name
    end)

    -- Rows befuellen
    for rowIdx, m in ipairs(members) do
        local row = GetPermRow(rowIdx)
        local isOfficer = (m.rankIndex <= maxRank)

        -- Name
        row.nameText:SetText(isOfficer
            and ("|cff00cc66" .. m.name .. "|r")
            or ("|cffdddddd" .. m.name .. "|r"))

        -- Rang
        row.rankText:SetText(isOfficer
            and ("|cff00cc66" .. m.rank .. "|r")
            or ("|cff999999" .. m.rank .. "|r"))

        -- Pro App Checkbox setzen
        for i, app in ipairs(ADDON.allApps) do
            local cb = row.appChecks[i]
            local lbl = row.appLabels[i]
            local perms = appPerms[app.key] or {}
            local isPublic = app.public

            if isPublic then
                -- Oeffentliche App: immer frei, Checkbox deaktiviert
                cb:SetChecked(true)
                cb:Disable()
                cb:SetAlpha(0.55)
                lbl:SetText("|cff66bb66frei|r")
            elseif isOfficer then
                -- Offizier: immer Zugriff, Checkbox deaktiviert
                cb:SetChecked(true)
                cb:Disable()
                cb:SetAlpha(0.55)
                lbl:SetText("|cff00cc66immer|r")
            else
                -- Normales Mitglied: editierbar
                local hasAccess = (perms[m.name] == true)
                cb:SetChecked(hasAccess)
                cb:Enable()
                cb:SetAlpha(1)
                lbl:SetText(hasAccess and "|cff88cc88ja|r" or "")

                local memberName = m.name
                local appKey = app.key
                cb:SetScript("OnClick", function(self)
                    local checked = self:GetChecked()
                    ADDON:SetPermission(appKey, memberName, checked)
                    ADDON:BroadcastPermission(appKey, memberName, checked)
                    Hub:RefreshPermPanel()
                    RefreshAppCards()
                end)
            end
        end

        row:Show()
    end

    -- Ueberflüssige Rows verstecken
    for i = #members + 1, #permRows do
        permRows[i]:Hide()
    end

    -- ScrollContent-Hoehe anpassen
    permScrollContent:SetHeight(math.max(1, #members * 25))
    -- Scroll-Range aktualisieren
    local scrollParent = permScrollContent:GetParent()
    if scrollParent and scrollParent.UpdateScrollChildRect then
        scrollParent:UpdateScrollChildRect()
        local sfName = scrollParent:GetName()
        local scrollbar = scrollParent.ScrollBar
            or (sfName and _G[sfName .. "ScrollBar"])
        if scrollbar then
            scrollbar:SetMinMaxValues(0, scrollParent:GetVerticalScrollRange())
        end
    end
end

---------------------------------------------------------------------------
-- Alle Permissions setzen (nur nicht-public Apps, nur Nicht-Offiziere)
---------------------------------------------------------------------------

function Hub:SetAllPermissions(access)
    local maxRank = ADDON:GetOfficerMaxRank()
    local numMembers = GetNumGuildMembers()
    for i = 1, numMembers do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name then
            local shortName = name:match("^([^-]+)") or name
            -- Nur fuer Nicht-Offiziere
            if rankIndex > maxRank then
                -- Nur fuer nicht-public Apps
                for _, app in ipairs(ADDON.allApps) do
                    if not app.public then
                        ADDON:SetPermission(app.key, shortName, access)
                        ADDON:BroadcastPermission(app.key, shortName, access)
                    end
                end
            end
        end
    end
    self:RefreshPermPanel()
    RefreshAppCards()
end

---------------------------------------------------------------------------
-- Perm-Panel oeffnen / schliessen
---------------------------------------------------------------------------

function Hub:ShowPermPanel()
    CreatePermPanel()
    -- Roster anfordern
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
    permFrame:Show()
    self:RefreshPermPanel()
end

function Hub:HidePermPanel()
    if permFrame then permFrame:Hide() end
end

---------------------------------------------------------------------------
-- Init – Hub-Fenster erstellen
---------------------------------------------------------------------------

function Hub:Init()
    if hubFrame then return end

    hubFrame = CreateFrame("Frame", "GASHubFrame", UIParent, "BackdropTemplate")
    hubFrame:SetSize(HUB_W, HUB_H)
    hubFrame:SetPoint("CENTER")
    hubFrame:SetFrameStrata("HIGH")
    hubFrame:SetBackdrop(BD_MAIN)
    hubFrame:SetBackdropColor(0.04, 0.04, 0.07, 0.97)
    hubFrame:SetBackdropBorderColor(0.55, 0.45, 0.2, 1)
    MakeMovable(hubFrame)
    hubFrame:Hide()
    tinsert(UISpecialFrames, "GASHubFrame")

    -- Hintergrund-Logo (deutlich sichtbar)
    local logo = hubFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    logo:SetTexture(LOGO_TEX)
    logo:SetSize(LOGO_SIZE_HUB, LOGO_SIZE_HUB)
    logo:SetPoint("CENTER", 0, 10)
    logo:SetAlpha(LOGO_ALPHA_HUB)

    -- Titel
    CreateLabel(hubFrame, "GameFontNormalLarge",
        "|cffff8800Germany's AllStar|r", "TOPLEFT", 16, -16)

    -- Untertitel
    CreateLabel(hubFrame, "GameFontNormalSmall",
        "|cffaaaaaa Gilden-Toolkit  v" .. ADDON.version .. "|r", "TOPLEFT", 16, -36)

    -- Schliessen
    local closeBtn = CreateFrame("Button", nil, hubFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Separator
    local sep = hubFrame:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 12, -56)
    sep:SetPoint("TOPRIGHT", -12, -56)
    sep:SetColorTexture(0.5, 0.4, 0.15, 0.5)

    -----------------------------------------------------------------------
    -- App: GuildStockPlanner
    -----------------------------------------------------------------------
    local gspCard = CreateAppCard(hubFrame, 1, {
        appKey      = "GuildStockPlanner",
        name        = "GuildStockPlanner",
        description = "Gildenbank-Bestaende planen,\nMaterialien berechnen, Rezepte syncen.",
        color       = { 0.2, 0.65, 0.35 },
        onClick     = function()
            hubFrame:Hide()
            if ADDON.UI then ADDON.UI:ToggleMainFrame() end
        end,
    })
    table.insert(appCards, gspCard)

    -----------------------------------------------------------------------
    -- App: GuildStocks (fuer ALLE Mitglieder – kein Whitelist noetig)
    -----------------------------------------------------------------------
    local gsCard = CreateAppCard(hubFrame, 2, {
        appKey      = "GuildStocks",
        name        = "GuildStocks",
        description = "Uebersicht: Welche Materialien muessen\ngefarmt werden? Was fehlt in der Gildenbank?",
        color       = { 0.45, 0.55, 0.8 },
        onClick     = function()
            hubFrame:Hide()
            if ADDON.GuildStocks then ADDON.GuildStocks:ToggleMainFrame() end
        end,
    })
    table.insert(appCards, gsCard)

    -----------------------------------------------------------------------
    -- App: Raidplaner (oeffentlich – fuer alle Mitglieder)
    -----------------------------------------------------------------------
    local rpCard = CreateAppCard(hubFrame, 3, {
        appKey      = "Raidplaner",
        name        = "Raidplaner",
        description = "Gilden-Raidkalender: Raids planen,\nanmelden und Kader verwalten.",
        color       = { 0.7, 0.35, 0.2 },
        onClick     = function()
            hubFrame:Hide()
            if ADDON.Raidplaner then ADDON.Raidplaner:ToggleMainFrame() end
        end,
    })
    table.insert(appCards, rpCard)

    -----------------------------------------------------------------------
    -- Rechteverwaltung-Button (NUR fuer Offiziere sichtbar)
    -----------------------------------------------------------------------
    local permBtn = CreateBtn(hubFrame, 170, 28, "|cffffd100Rechteverwaltung|r", function()
        Hub:ShowPermPanel()
    end)
    permBtn:SetPoint("BOTTOMLEFT", 16, 14)
    permBtn:SetBackdropBorderColor(0.7, 0.55, 0.15, 1)

    -- Credits unten mittig
    local credits = hubFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    credits:SetText("|cffcc8800Made by B\195\161bushka|r")
    credits:SetPoint("BOTTOM", 0, 16)

    -----------------------------------------------------------------------
    -- OnShow – Rechte und Lock-Status aktualisieren
    -----------------------------------------------------------------------
    hubFrame:SetScript("OnShow", function()
        -- Offizier-Check: Perms-Button sichtbar?
        local isOff = ADDON:AmIOfficer()
        permBtn:SetShown(isOff)
        RefreshAppCards()
    end)

    self.hubFrame = hubFrame
end

---------------------------------------------------------------------------
-- Toggle
---------------------------------------------------------------------------

function Hub:Toggle()
    if not hubFrame then self:Init() end
    if hubFrame:IsShown() then
        hubFrame:Hide()
        self:HidePermPanel()
    else
        hubFrame:Show()
    end
end
