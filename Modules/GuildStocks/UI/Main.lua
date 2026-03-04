---------------------------------------------------------------------------
-- GuildStocks – UI.lua
-- Read-only Uebersicht: Fehlende Materialien & Hauptitems unter Soll.
-- Fuer ALLE Gildenmitglieder einsehbar – keine Bearbeitung moeglich.
-- Einheitliche scrollbare Liste mit ein-/ausklappbaren Sektionen.
-- Nutzt ADDON.Calculator und ADDON.DB (aus GuildStockPlanner).
-- Design: gleicher Look wie GuildStockPlanner (Inset, Buttons, Farben).
---------------------------------------------------------------------------
local _, ADDON = ...

ADDON.GuildStocks = {}
local GS = ADDON.GuildStocks
local Theme = ADDON.Theme
local DS = ADDON.DesignSystem

---------------------------------------------------------------------------
-- Layout (identisch mit GSP)
---------------------------------------------------------------------------
local MAIN_W, MAIN_H     = 740, 540
local INSET_PAD           = 10
local ROW_H               = 26
local SCROLL_BAR_W        = 26
local LOGO_TEX            = "Interface\\AddOns\\GermanysAllStar\\Textures\\logo"

local BD_MAIN = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local BD_INSET = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

---------------------------------------------------------------------------
-- Lokale Refs
---------------------------------------------------------------------------
local gsFrame, contentInset
local scrollFrame, scrollContent, rows
local lastScanLabel, summaryLabel
local sectionCollapsed = { true, false } -- [1] Hauptitems (eingeklappt), [2] Materialien (ausgeklappt)

---------------------------------------------------------------------------
-- Helfer (gleich wie GSP)
---------------------------------------------------------------------------

local function ApplyBackdrop(frame, bd, r, g, b, a, er, eg, eb, ea)
    if bd == BD_INSET then
        DS.ApplyPanelStyle(frame)
    else
        DS.ApplyWindowStyle(frame)
    end
end

local function MakeMovable(frame)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
end

local function CreateLabel(parent, fontObj, text, ...)
    local variant = "normal"
    if fontObj == "GameFontDisableSmall" then variant = "muted"
    elseif fontObj == "GameFontNormalSmall" or fontObj == "GameFontHighlightSmall" then variant = "small"
    elseif fontObj == "GameFontNormalLarge" then variant = "header" end
    return DS.CreateLabel(parent, variant, text, ...)
end

local function CreateBtn(parent, w, h, text, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(w, h)
    btn.text = btn:CreateFontString(nil, "OVERLAY", Theme.fonts.small)
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text)
    btn.SetText = function(self, value) self.text:SetText(value or "") end
    btn.GetText = function(self) return self.text:GetText() end
    DS.ApplyButtonStyle(btn)
    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end

local function CreateRowIcon(parent)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 4, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return icon
end

local function SetRowIcon(icon, itemID)
    if not itemID then
        icon:SetTexture(nil)
        icon:Hide()
        return
    end
    local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
    if texture then
        icon:SetTexture(texture)
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        GetItemInfo(itemID) -- Cache
    end
    icon:Show()
end

--- Stellt sicher, dass der Scroll-Bereich korrekt ist.
local function UpdateScrollRange(sf)
    if not sf then return end
    sf:UpdateScrollChildRect()
    local sfName = sf:GetName()
    local scrollbar = sf.ScrollBar
        or (sfName and _G[sfName .. "ScrollBar"])
    if scrollbar then
        local maxVal = sf:GetVerticalScrollRange()
        scrollbar:SetMinMaxValues(0, maxVal)
    end
end

---------------------------------------------------------------------------
-- Row-Pool
---------------------------------------------------------------------------

local function GetRow(index)
    if rows[index] then return rows[index] end

    local row = CreateFrame("Frame", nil, scrollContent)
    row:SetHeight(ROW_H)
    row:SetPoint("RIGHT", scrollContent, "RIGHT")

    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.03)
    end

    row.icon     = CreateRowIcon(row)
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.nameText:SetWidth(300)
    row.nameText:SetJustifyH("LEFT")

    row.col2Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.col2Text:SetPoint("LEFT", 350, 0)
    row.col2Text:SetWidth(80)
    row.col2Text:SetJustifyH("RIGHT")

    row.col3Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.col3Text:SetPoint("LEFT", 440, 0)
    row.col3Text:SetWidth(80)
    row.col3Text:SetJustifyH("RIGHT")

    row.col4Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.col4Text:SetPoint("LEFT", 530, 0)
    row.col4Text:SetWidth(90)
    row.col4Text:SetJustifyH("RIGHT")

    -- Tooltip bei Hover (mit Icons)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.itemID)
            if self.craftable and self.subMats and #self.subMats > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(
                    "Zum Craften (" .. (self.missingQty or "?") .. "x) benoetigt:",
                    1, 0.82, 0)
                for _, sub in ipairs(self.subMats) do
                    local sName = GetItemInfo(sub.itemID) or ("Item:" .. sub.itemID)
                    local sIcon = GetItemIcon(sub.itemID)
                    local iconStr = sIcon and ("|T" .. sIcon .. ":14:14|t ") or ""
                    GameTooltip:AddDoubleLine(
                        "  " .. iconStr .. sName,
                        sub.required .. "x",
                        1, 1, 1, 1, 0.82, 0)
                end
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    rows[index] = row
    return row
end

---------------------------------------------------------------------------
-- Sektions-Header Helfer
---------------------------------------------------------------------------

local function SetupHeader(row, sectionIdx, count, label, c2, c3, c4)
    row.itemID     = nil
    row.craftable  = nil
    row.subMats    = nil
    row.missingQty = nil
    SetRowIcon(row.icon, nil)
    local arrow = sectionCollapsed[sectionIdx] and "|cffffd100[+]|r " or "|cffffd100[-]|r "
    row.nameText:SetText(arrow .. "|cffffd100" .. label .. " (" .. count .. ")|r")
    row.col2Text:SetText("|cffffd100" .. c2 .. "|r")
    row.col3Text:SetText("|cffffd100" .. c3 .. "|r")
    row.col4Text:SetText("|cffffd100" .. c4 .. "|r")
    row:SetScript("OnMouseDown", function()
        sectionCollapsed[sectionIdx] = not sectionCollapsed[sectionIdx]
        GS:Refresh()
    end)
    if not row._headerBg then
        row._headerBg = row:CreateTexture(nil, "BACKGROUND", nil, 2)
        row._headerBg:SetAllPoints()
    end
    row._headerBg:SetColorTexture(0.18, 0.18, 0.25, 0.55)
    row._headerBg:Show()
end

local function ResetRow(row)
    row:SetScript("OnMouseDown", nil)
    if row._headerBg then row._headerBg:Hide() end
    row.craftable  = nil
    row.subMats    = nil
    row.missingQty = nil
end

---------------------------------------------------------------------------
-- Refresh – einheitliche Liste
---------------------------------------------------------------------------

function GS:Refresh()
    if not scrollContent then return end

    local missingMats, missingMains = ADDON.Calculator:Calculate()

    -- Alle Zeilen verstecken
    for _, r in ipairs(rows) do r:Hide() end

    local idx = 0

    -----------------------------------------------------------------------
    -- Sektion 1: Hauptitems unter Soll
    -----------------------------------------------------------------------
    if #missingMains > 0 then
        idx = idx + 1
        local hdr = GetRow(idx)
        SetupHeader(hdr, 1, #missingMains, "Hauptitems unter Soll",
            "Soll", "In Bank", "Fehlend")
        hdr:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_H)
        hdr:Show()

        if not sectionCollapsed[1] then
            for _, data in ipairs(missingMains) do
                idx = idx + 1
                local row = GetRow(idx)
                ResetRow(row)
                row.itemID = data.itemID
                SetRowIcon(row.icon, data.itemID)
                row.nameText:SetText(ADDON:GetColoredItemName(data.itemID))
                row.col2Text:SetText("|cffffd100" .. data.desired .. "|r")
                row.col3Text:SetText("|cff88cc88" .. data.inBank .. "|r")
                row.col4Text:SetText("|cffff4444" .. data.missing .. "|r")
                row:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_H)
                row:Show()
            end
        end

        -- Leerzeile Trenner
        idx = idx + 1
        local spacer = GetRow(idx)
        ResetRow(spacer)
        spacer.itemID = nil
        SetRowIcon(spacer.icon, nil)
        spacer.nameText:SetText("")
        spacer.col2Text:SetText("")
        spacer.col3Text:SetText("")
        spacer.col4Text:SetText("")
        spacer:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_H)
        spacer:Show()
    end

    -----------------------------------------------------------------------
    -- Sektion 2: Zu farmende Materialien
    -----------------------------------------------------------------------
    if #missingMats > 0 then
        idx = idx + 1
        local hdr = GetRow(idx)
        SetupHeader(hdr, 2, #missingMats, "Zu farmende Materialien",
            "Benoetigt", "In Bank", "Fehlend")
        hdr:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_H)
        hdr:Show()

        if not sectionCollapsed[2] then
            for _, data in ipairs(missingMats) do
                idx = idx + 1
                local row = GetRow(idx)
                ResetRow(row)
                row.itemID     = data.itemID
                row.craftable  = data.craftable
                row.subMats    = data.subMats
                row.missingQty = data.missing
                SetRowIcon(row.icon, data.itemID)
                local nameStr = ADDON:GetColoredItemName(data.itemID)
                if data.craftable then
                    nameStr = nameStr .. " |cff88cc88(craftbar)|r"
                end
                row.nameText:SetText(nameStr)
                row.col2Text:SetText("|cffffd100" .. data.required .. "|r")
                row.col3Text:SetText("|cff88cc88" .. data.inBank .. "|r")
                row.col4Text:SetText("|cffff4444" .. data.missing .. "|r")
                row:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_H)
                row:Show()
            end
        end
    end

    -----------------------------------------------------------------------
    -- Leer-Hinweis
    -----------------------------------------------------------------------
    if idx == 0 then
        idx = 1
        local row = GetRow(idx)
        ResetRow(row)
        row.itemID = nil
        SetRowIcon(row.icon, nil)
        local scan = ADDON.DB:GetLastScan()
        if scan.ts == 0 then
            row.nameText:SetText("|cff888888Noch kein Scan durchgefuehrt.|r")
        else
            row.nameText:SetText("|cff88ff88Alles auf Lager! Keine Fehlbestaende.|r")
        end
        row.col2Text:SetText("")
        row.col3Text:SetText("")
        row.col4Text:SetText("")
        row:SetPoint("TOPLEFT", 0, 0)
        row:Show()
    end

    -- Scroll-Content-Hoehe und Scrollbar aktualisieren
    scrollContent:SetHeight(math.max(1, idx * ROW_H))
    UpdateScrollRange(scrollFrame)

    -- Zusammenfassung
    summaryLabel:SetText(
        "|cffaaaaaa" .. #missingMains .. " Hauptitems unter Soll  |  "
        .. #missingMats .. " Materialien fehlen|r")
end

---------------------------------------------------------------------------
-- Init – Hauptfenster (Design identisch mit GSP)
---------------------------------------------------------------------------

function GS:Init()
    if gsFrame then return end
    rows = {}

    gsFrame = CreateFrame("Frame", "GASGuildStocksFrame", UIParent, "BackdropTemplate")
    gsFrame:SetSize(MAIN_W, MAIN_H)
    gsFrame:SetPoint("CENTER")
    gsFrame:SetFrameStrata("HIGH")
    ApplyBackdrop(gsFrame, BD_MAIN, 0.05, 0.05, 0.08, 0.96, 0.5, 0.5, 0.5)
    gsFrame:EnableMouse(true) -- Klicks blockieren
    MakeMovable(gsFrame)
    gsFrame:Hide()
    tinsert(UISpecialFrames, "GASGuildStocksFrame")

    -- Hintergrund-Logo (dezentes Wasserzeichen)
    local bgLogo = gsFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgLogo:SetTexture(LOGO_TEX)
    bgLogo:SetSize(320, 320)
    bgLogo:SetPoint("CENTER", 0, 0)
    bgLogo:SetAlpha(0.18)

    -- Titel
    CreateLabel(gsFrame, "GameFontNormalLarge",
        "|cffff8800GAS|r GuildStocks", "TOPLEFT", 16, -14)

    -- Schliessen-Button
    local closeBtn = CreateFrame("Button", nil, gsFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Zurueck zum Hub (gleicher Button-Stil wie GSP)
    local hubBtn = CreateBtn(gsFrame, 70, 24, "< Hub", function()
        gsFrame:Hide()
        if ADDON.Hub then ADDON.Hub:Toggle() end
    end)
    hubBtn:SetPoint("TOPRIGHT", -36, -12)

    -- Scan-Zeitstempel
    lastScanLabel = CreateLabel(gsFrame, "GameFontNormalSmall", "", "TOPLEFT", 16, -38)
    lastScanLabel:SetJustifyH("LEFT")
    lastScanLabel:SetWidth(340)

    -- Zusammenfassung (Anzahl fehlender Items)
    summaryLabel = CreateLabel(gsFrame, "GameFontNormalSmall", "", "TOPRIGHT", -36, -38)
    summaryLabel:SetJustifyH("RIGHT")
    summaryLabel:SetWidth(300)

    -- Content-Inset (wie GSP – dunkles Innenpanel)
    contentInset = CreateFrame("Frame", nil, gsFrame, "BackdropTemplate")
    contentInset:SetPoint("TOPLEFT", INSET_PAD, -56)
    contentInset:SetPoint("BOTTOMRIGHT", -INSET_PAD, INSET_PAD)
    ApplyBackdrop(contentInset, BD_INSET, 0.07, 0.07, 0.1, 0.85, 0.35, 0.35, 0.35)

    -- Hinweis-Text (innerhalb des Insets)
    local hint = CreateLabel(contentInset, "GameFontDisableSmall",
        "|cff888888Klicke auf Ueberschrift zum Ein-/Ausklappen.  Hover ueber (craftbar) fuer Unter-Materialien.|r",
        "TOPLEFT", 8, -6)
    hint:SetWidth(MAIN_W - 60)

    -- ScrollFrame (innerhalb des Insets)
    scrollFrame = CreateFrame("ScrollFrame", "GSGuildStocksScroll", contentInset, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 6, -22)
    scrollFrame:SetPoint("BOTTOMRIGHT", -6 - SCROLL_BAR_W, 6)

    scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetWidth(MAIN_W - INSET_PAD * 2 - 12 - SCROLL_BAR_W)
    scrollContent:SetHeight(1)
    scrollFrame:SetScrollChild(scrollContent)

    -----------------------------------------------------------------------
    -- GET_ITEM_INFO_RECEIVED – Icons / Namen nachladen
    -----------------------------------------------------------------------
    local pending = false
    local infoFrame = CreateFrame("Frame")
    infoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    infoFrame:SetScript("OnEvent", function()
        if gsFrame and gsFrame:IsShown() then
            if pending then return end
            pending = true
            C_Timer.After(0.3, function()
                pending = false
                if gsFrame:IsShown() then GS:Refresh() end
            end)
        end
    end)

    -- Credits
    local credits = gsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    credits:SetText("|cff666666GuildStocks \226\128\147 Nur Ansicht  |  Made by B\195\161bushka|r")
    credits:SetPoint("BOTTOMRIGHT", -14, 6)

    self.gsFrame = gsFrame
end

---------------------------------------------------------------------------
-- Toggle
---------------------------------------------------------------------------

function GS:ToggleMainFrame()
    if not self.gsFrame then self:Init() end
    if self.gsFrame:IsShown() then
        self.gsFrame:Hide()
        return
    end
    if not ADDON:GetGuildInfo() then
        ADDON:Print("Du bist in keiner Gilde.")
        return
    end
    ADDON.DB:EnsureProfile()
    self.gsFrame:Show()

    -- Scan-Zeitstempel anzeigen
    local scan = ADDON.DB:GetLastScan()
    if scan and scan.ts and scan.ts > 0 then
        lastScanLabel:SetText("|cff888888Letzter Scan: " .. date("%d.%m.%Y %H:%M", scan.ts) .. "|r")
    else
        lastScanLabel:SetText("|cffff4444Noch kein Gildenbank-Scan vorhanden!|r")
    end

    self:Refresh()
end
