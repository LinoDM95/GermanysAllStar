---------------------------------------------------------------------------
-- GuildStockPlanner – UI.lua
-- Hauptfenster, Tabs, Rezept-Editor, Farm-Liste, Einstellungen
-- Nur Standard-FrameXML, keine externen Libs.
---------------------------------------------------------------------------
local _, ADDON = ...

ADDON.UI = {}
local UI = ADDON.UI
local Theme = ADDON.Theme
local DS = ADDON.DesignSystem

---------------------------------------------------------------------------
-- Layout-Konstanten
---------------------------------------------------------------------------
local MAIN_W              = 740
local MAIN_H              = 540
local INSET_PAD           = 10
local TAB_HEIGHT          = 28
local ROW_HEIGHT          = 26
local SCROLL_BAR_SPACE    = 26
local SCROLL_CONTENT_W    = MAIN_W - INSET_PAD * 2 - 10 - SCROLL_BAR_SPACE -- ~684
local EDITOR_W            = 600
local EDITOR_H            = 480
local MAT_ROW_H           = 30

---------------------------------------------------------------------------
-- Backdrop-Presets
---------------------------------------------------------------------------
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
-- Vorwaertsdeklarationen (Lokal-Cache)
---------------------------------------------------------------------------
local mainFrame, contentInset
local tabButtons   = {}
local tabFrames    = {}
local scanBtn, scanStatus, syncBtn
local recipeScrollFrame, recipeScrollContent, recipeRows, newRecipeBtn
local editorFrame
local farmScrollFrame, farmScrollContent, farmRows
local farmSectionCollapsed = { true, false } -- [1] Hauptitems (eingeklappt), [2] Materialien (ausgeklappt)
local stockScrollFrame, stockScrollContent, stockRows
local logScrollFrame, logScrollContent, logRows
local settingsFrame
local eiPopup, eiEditBox, eiTitle, eiImportBtn

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

local function ApplyBackdrop(frame, bd, r, g, b, a, er, eg, eb, ea)
    if not frame then return end
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
    if fontObj == "GameFontDisableSmall" then
        variant = "muted"
    elseif fontObj == "GameFontNormalSmall" or fontObj == "GameFontHighlightSmall" then
        variant = "small"
    elseif fontObj == "GameFontNormalLarge" then
        variant = "header"
    end
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

local function CreateEB(parent, w, h, numeric)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate,BackdropTemplate")
    eb:SetSize(w, h)
    eb:SetAutoFocus(false)
    if numeric then eb:SetNumeric(true) end
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    DS.ApplyInputStyle(eb)
    return eb
end

local function CreateCB(parent, text, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(text)
    cb.label = label
    DS.ApplyCheckboxStyle(cb)
    if onClick then cb:SetScript("OnClick", onClick) end
    return cb
end

local function CreateScrollFrame(parent, name)
    local sf = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(SCROLL_CONTENT_W)
    child:SetHeight(1)
    sf:SetScrollChild(child)
    return sf, child
end

--- Stellt sicher, dass der Scroll-Bereich nach Content-Aenderungen korrekt ist.
--- Behebt Probleme mit fehlender Scrollbar-Aktualisierung in manchen WoW-Versionen.
local function UpdateScrollRange(scrollFrame)
    if not scrollFrame then return end
    scrollFrame:UpdateScrollChildRect()
    local scrollName = scrollFrame:GetName()
    local scrollbar = scrollFrame.ScrollBar
        or (scrollName and _G[scrollName .. "ScrollBar"])
    if scrollbar then
        local maxVal = scrollFrame:GetVerticalScrollRange()
        scrollbar:SetMinMaxValues(0, maxVal)
    end
end

local ICON_SIZE = 20
local ICON_PAD  = 4  -- Abstand links
local TEXT_OFFSET = ICON_PAD + ICON_SIZE + 4 -- 28px – Text beginnt rechts vom Icon

--- Erzeugt eine Icon-Texture auf einem Row-Frame.
local function CreateRowIcon(row)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", ICON_PAD, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- leichter Rand-Clip fuer sauberere Optik
    return icon
end

--- Setzt das Icon fuer eine ItemID (oder versteckt es).
local function SetRowIcon(icon, itemID)
    if not icon then return end
    if not itemID then icon:Hide(); return end
    local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
    if texture then
        icon:SetTexture(texture)
        icon:Show()
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        icon:Show()
        GetItemInfo(itemID) -- Cache-Request
    end
end

--- Item-Tooltip bei Hover
local function SetItemTooltip(frame, getID)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        local id = type(getID) == "function" and getID(self) or self.itemID
        if id then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. id)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- AUTOCOMPLETE – Item-Namenssuche
---------------------------------------------------------------------------
local acFrame, acRows
local MAX_AC_RESULTS = 8
local AC_ROW_H       = 24
local itemSearchPool = nil
local poolBuildTime  = 0

--- Erzeugt den Autocomplete-Dropdown (einmalig).
function UI:CreateAutocomplete()
    acFrame = CreateFrame("Frame", "GSPAutocomplete", UIParent, "BackdropTemplate")
    acFrame:SetSize(340, MAX_AC_RESULTS * AC_ROW_H + 4)
    acFrame:SetFrameStrata("TOOLTIP")
    ApplyBackdrop(acFrame, BD_MAIN, 0.06, 0.06, 0.10, 0.98, 0.45, 0.45, 0.45)
    acFrame:EnableMouse(true)
    acFrame:Hide()

    acRows = {}
    for i = 1, MAX_AC_RESULTS do
        local row = CreateFrame("Button", nil, acFrame)
        row:SetSize(336, AC_ROW_H)
        row:SetPoint("TOPLEFT", 2, -(i - 1) * AC_ROW_H - 2)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 26, 0)
        row.text:SetWidth(230)
        row.text:SetJustifyH("LEFT")

        row.idText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.idText:SetPoint("RIGHT", -6, 0)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.25, 0.25, 0.45, 0.5)

        row:SetScript("OnClick", function(self)
            if self.itemID and UI.acActiveEB then
                UI.acActiveEB:SetText(tostring(self.itemID))
                UI.acActiveEB:ClearFocus()
                UI:HideAutocomplete()
            end
        end)

        acRows[i] = row
    end
end

--- Baut den Suchpool aus bekannten Items (Gildenbank, Taschen, Rezepte).
--- Wird alle 30 Sek. neu aufgebaut.
function UI:GetSearchPool()
    if itemSearchPool and (GetTime() - poolBuildTime) < 30 then
        return itemSearchPool
    end
    itemSearchPool = {}
    poolBuildTime  = GetTime()

    -- Gildenbank-Scan
    local scan = ADDON.DB:GetLastScan()
    for itemID in pairs(scan.bankCounts or {}) do
        local name = GetItemInfo(itemID)
        if name then itemSearchPool[itemID] = name end
    end

    -- Spieler-Taschen (0 = Rucksack, 1-4 = Taschen)
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local id = ADDON:ParseItemID(link)
                if id and not itemSearchPool[id] then
                    local name = GetItemInfo(id)
                    if name then itemSearchPool[id] = name end
                end
            end
        end
    end

    -- Rezepte (Hauptitems + Materialien)
    for mainID, recipe in pairs(ADDON.DB:GetRecipes()) do
        if not itemSearchPool[mainID] then
            local name = GetItemInfo(mainID)
            if name then itemSearchPool[mainID] = name end
        end
        for _, mat in ipairs(recipe.mats or {}) do
            if mat.itemID and not itemSearchPool[mat.itemID] then
                local name = GetItemInfo(mat.itemID)
                if name then itemSearchPool[mat.itemID] = name end
            end
        end
    end

    return itemSearchPool
end

--- Sucht Items nach Teilstring (case-insensitive).
function UI:SearchItems(query, maxResults)
    local pool = self:GetSearchPool()
    local q    = query:lower()
    local results = {}
    maxResults = maxResults or MAX_AC_RESULTS

    for itemID, name in pairs(pool) do
        if name:lower():find(q, 1, true) then
            table.insert(results, { itemID = itemID, name = name })
        end
    end

    -- Sortierung: Treffer am Anfang des Namens zuerst, dann alphabetisch
    table.sort(results, function(a, b)
        local aStart = (a.name:lower():sub(1, #q) == q)
        local bStart = (b.name:lower():sub(1, #q) == q)
        if aStart ~= bStart then return aStart end
        return a.name < b.name
    end)

    if #results > maxResults then
        local t = {}
        for i = 1, maxResults do t[i] = results[i] end
        return t
    end
    return results
end

--- Zeigt das Autocomplete-Dropdown unter der EditBox.
function UI:ShowAutocomplete(editBox, text)
    if not acFrame then return end
    if not text or #text < 2 then
        self:HideAutocomplete()
        return
    end
    if ADDON:ParseItemID(text) then
        self:HideAutocomplete()
        return
    end

    local results = self:SearchItems(text)
    if #results == 0 then
        self:HideAutocomplete()
        return
    end

    self.acActiveEB = editBox
    acFrame:ClearAllPoints()
    acFrame:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -2)

    for i = 1, MAX_AC_RESULTS do
        if i <= #results then
            local r = results[i]
            acRows[i].itemID = r.itemID
            local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(r.itemID)
            if tex then
                acRows[i].icon:SetTexture(tex)
            else
                acRows[i].icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            acRows[i].icon:Show()
            acRows[i].text:SetText(ADDON:GetColoredItemName(r.itemID))
            acRows[i].idText:SetText("|cff888888" .. r.itemID .. "|r")
            acRows[i]:Show()
        else
            acRows[i]:Hide()
        end
    end

    local shown = math.min(#results, MAX_AC_RESULTS)
    acFrame:SetHeight(shown * AC_ROW_H + 4)
    acFrame:Show()
end

function UI:HideAutocomplete()
    if acFrame then acFrame:Hide() end
    self.acActiveEB = nil
end

---------------------------------------------------------------------------
-- INIT
---------------------------------------------------------------------------
UI.initialized     = false
UI.activeTab       = 1
UI.itemLinkEBs     = {} -- EditBoxen die ItemLinks akzeptieren
UI.editorMats      = {} -- Arbeitskopie: { {itemID, qty, [subMats]}, ... }
UI.editorAllRows   = {} -- Einheitlicher Row-Pool (beliebige Tiefe)
UI.editingRecipeID = nil

function UI:Init()
    if self.initialized then return end
    self.initialized = true
    recipeRows = {}
    farmRows   = {}
    stockRows  = {}
    logRows    = {}

    self:CreateMainFrame()
    self:CreateRecipeEditor()
    self:CreateAutocomplete()
    self:CreateExportImportPopup()
    self:HookItemLinks()
    self:RegisterItemInfoEvent()

    -- StaticPopup: Rezept loeschen
    StaticPopupDialogs["GSP_CONFIRM_DELETE"] = {
        text       = "Rezept wirklich loeschen?",
        button1    = "Ja",
        button2    = "Nein",
        OnAccept   = function(popup)
            local id = popup.data
            if id then
                ADDON.DB:AddLogEntry("del", UnitName("player"), id)
                ADDON.DB:DeleteRecipe(id)
                if ADDON.Sync then ADDON.Sync:BroadcastRecipeDel(id) end
                UI:RefreshRecipeList()
                ADDON:Print("Rezept geloescht.")
            end
        end,
        timeout       = 0,
        whileDead     = true,
        hideOnEscape  = true,
        preferredIndex = 3,
    }

    -- StaticPopup: Import bestaetigen
    StaticPopupDialogs["GSP_CONFIRM_IMPORT"] = {
        text       = "Importierte Rezepte ueberschreiben bestehende mit gleicher ItemID. Fortfahren?",
        button1    = "Ja",
        button2    = "Nein",
        OnAccept   = function(popup)
            local recipes = popup.data
            if recipes then
                local profile = ADDON.DB:GetProfile()
                if profile then
                    for id, recipe in pairs(recipes) do
                        recipe.modifiedAt = time()
                        profile.recipes[id] = recipe
                        ADDON.DB:AddLogEntry("add", UnitName("player"), id)
                        if ADDON.Sync then
                            ADDON.Sync:BroadcastRecipeAdd(recipe)
                        end
                    end
                    ADDON:Print("Import erfolgreich!")
                    UI:RefreshRecipeList()
                end
            end
        end,
        timeout       = 0,
        whileDead     = true,
        hideOnEscape  = true,
        preferredIndex = 3,
    }
end

---------------------------------------------------------------------------
-- HAUPTFENSTER
---------------------------------------------------------------------------

function UI:CreateMainFrame()
    mainFrame = CreateFrame("Frame", "GSPMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(MAIN_W, MAIN_H)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("HIGH")
    ApplyBackdrop(mainFrame, BD_MAIN, 0.05, 0.05, 0.08, 0.96, 0.5, 0.5, 0.5)
    mainFrame:EnableMouse(true) -- Klicks blockieren
    MakeMovable(mainFrame)
    mainFrame:Hide()
    tinsert(UISpecialFrames, "GSPMainFrame") -- ESC schliessen

    -- Hintergrund-Logo (dezentes Wasserzeichen)
    local bgLogo = mainFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgLogo:SetTexture("Interface\\AddOns\\GermanysAllStar\\Textures\\logo")
    bgLogo:SetSize(320, 320)
    bgLogo:SetPoint("CENTER", 0, 0)
    bgLogo:SetAlpha(0.18)

    -- Titel
    CreateLabel(mainFrame, "GameFontNormalLarge", "|cffff8800GAS|r GuildStockPlanner", "TOPLEFT", 16, -14)

    -- Schliessen-Button
    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Action-Buttons (eine Zeile, rechtsbuendig, ohne Ueberlappung)
    scanBtn = CreateBtn(mainFrame, 150, 24, "Scan (Gildenbank)", function()
        ADDON.Scanner:StartScan()
    end)
    scanBtn:SetPoint("TOPRIGHT", -36, -12)

    syncBtn = CreateBtn(mainFrame, 110, 24, "Sync Rezepte", function()
        if ADDON.Sync then ADDON.Sync:ManualSync() end
    end)
    syncBtn:SetPoint("RIGHT", scanBtn, "LEFT", -6, 0)

    local hubBtn = CreateBtn(mainFrame, 70, 24, "< Hub", function()
        mainFrame:Hide()
        if ADDON.Hub then ADDON.Hub:Toggle() end
    end)
    hubBtn:SetPoint("RIGHT", syncBtn, "LEFT", -6, 0)

    -- Scan-/Sync-Status unter den Buttons
    scanStatus = CreateLabel(mainFrame, "GameFontNormalSmall", "Scan: Idle  |  Sync: Bereit", "TOPRIGHT", -36, -38)
    scanStatus:SetJustifyH("RIGHT")
    scanStatus:SetWidth(340)

    -- Content-Inset (unterhalb der Tabs)
    contentInset = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    contentInset:SetPoint("TOPLEFT", INSET_PAD, -84)
    contentInset:SetPoint("BOTTOMRIGHT", -INSET_PAD, INSET_PAD)
    ApplyBackdrop(contentInset, BD_INSET, 0.07, 0.07, 0.1, 0.85, 0.35, 0.35, 0.35)

    -- Tab-Buttons (unterhalb von scanStatus bei y=-38)
    local tabNames = { "Rezepte", "Zu farmen", "Gildenbank", "Sync-Log", "How-To", "Einstellungen" }
    local tabW = 110
    local tabSpacing = 4
    for i, name in ipairs(tabNames) do
        local tb = CreateFrame("Button", nil, mainFrame, "BackdropTemplate")
        tb:SetSize(tabW, TAB_HEIGHT)
        tb:SetPoint("TOPLEFT", INSET_PAD + (i - 1) * (tabW + tabSpacing), -54)

        local bg = tb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.12, 0.12, 0.18, 0.9)
        tb.bg = bg

        local hl = tb:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.25, 0.25, 0.35, 0.5)

        tb:SetNormalFontObject(GameFontNormal)
        tb:SetHighlightFontObject(GameFontHighlight)
        tb:SetText(name)
        local fs = tb:GetFontString()
        if fs then fs:SetPoint("CENTER") end

        tb:SetScript("OnClick", function() UI:ShowTab(i) end)
        tabButtons[i] = tb
    end

    -- Tab-Inhalte erstellen
    tabFrames[1] = self:CreateRecipeTab()
    tabFrames[2] = self:CreateFarmTab()
    tabFrames[3] = self:CreateStockTab()
    tabFrames[4] = self:CreateLogTab()
    tabFrames[5] = self:CreateHowToTab()
    tabFrames[6] = self:CreateSettingsTab()

    self.mainFrame = mainFrame
end

---------------------------------------------------------------------------
-- Tab-Wechsel
---------------------------------------------------------------------------

function UI:ShowTab(index)
    self.activeTab = index
    for i = 1, 6 do
        if tabFrames[i] then tabFrames[i]:SetShown(i == index) end
        if tabButtons[i] then
            if i == index then
                tabButtons[i].bg:SetColorTexture(0.22, 0.22, 0.32, 1)
            else
                tabButtons[i].bg:SetColorTexture(0.12, 0.12, 0.18, 0.9)
            end
        end
    end
    if index == 1 then self:RefreshRecipeList()
    elseif index == 2 then self:RefreshFarmTab()
    elseif index == 3 then self:RefreshStockTab()
    elseif index == 4 then self:RefreshLogTab()
    elseif index == 6 then self:RefreshSettingsTab()
    end
end

---------------------------------------------------------------------------
-- TOGGLE
---------------------------------------------------------------------------

function UI:ToggleMainFrame()
    if not self.initialized then self:Init() end
    if mainFrame:IsShown() then
        mainFrame:Hide()
        return
    end
    if not ADDON:GetGuildInfo() then
        ADDON:Print("Du bist in keiner Gilde.")
        return
    end
    ADDON.DB:EnsureProfile()
    mainFrame:Show()
    self:ShowTab(self.activeTab or 1)
end

---------------------------------------------------------------------------
-- SCAN-STATUS
---------------------------------------------------------------------------

function UI:UpdateScanStatus()
    if not scanStatus then return end
    local scanText = ADDON.Scanner:GetStatusText()
    local syncText = ADDON.Sync and ADDON.Sync:GetStatusText() or "Bereit"
    scanStatus:SetText("Scan: " .. scanText .. "  |cff888888|||r  Sync: " .. syncText)
end

---------------------------------------------------------------------------
-- REZEPTE-TAB
---------------------------------------------------------------------------

function UI:CreateRecipeTab()
    local f = CreateFrame("Frame", nil, contentInset)
    f:SetPoint("TOPLEFT", 5, -5)
    f:SetPoint("BOTTOMRIGHT", -5, 5)
    f:Hide()

    -- Kopfzeile
    newRecipeBtn = CreateBtn(f, 80, 24, "Neu", function()
        if not ADDON.DB:CanEditRecipes() then
            ADDON:Print("Keine Berechtigung zum Bearbeiten.")
            return
        end
        UI:OpenRecipeEditor(nil)
    end)
    newRecipeBtn:SetPoint("TOPLEFT", 0, 0)

    -- Spalten-Header
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetPoint("TOPLEFT", 0, -30)
    hdr:SetSize(SCROLL_CONTENT_W, 18)
    CreateLabel(hdr, "GameFontNormalSmall", "Item",    "LEFT", 8, 0)
    CreateLabel(hdr, "GameFontNormalSmall", "Soll",    "LEFT", 360, 0)
    CreateLabel(hdr, "GameFontNormalSmall", "Ertrag",  "LEFT", 440, 0)

    -- ScrollFrame
    recipeScrollFrame, recipeScrollContent = CreateScrollFrame(f, "GSPRecipeScroll")
    recipeScrollFrame:SetPoint("TOPLEFT", 0, -50)
    recipeScrollFrame:SetPoint("BOTTOMRIGHT", -SCROLL_BAR_SPACE, 0)

    return f
end

--- Erzeugt (oder gibt zurueck) eine Rezeptzeile.
function UI:GetRecipeRow(index)
    if recipeRows[index] then return recipeRows[index] end

    local row = CreateFrame("Frame", nil, recipeScrollContent, "BackdropTemplate")
    row:SetSize(SCROLL_CONTENT_W, ROW_HEIGHT)

    if index % 2 == 0 then
        row:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
        row:SetBackdropColor(0.12, 0.12, 0.16, 0.35)
    end

    row.icon = CreateRowIcon(row)

    row.itemText  = CreateLabel(row, "GameFontHighlight", nil, "LEFT", TEXT_OFFSET, 0)
    row.itemText:SetWidth(320)
    row.itemText:SetJustifyH("LEFT")

    row.stockText = CreateLabel(row, "GameFontNormal", nil, "LEFT", 360, 0)
    row.stockText:SetWidth(70)

    row.yieldText = CreateLabel(row, "GameFontNormal", nil, "LEFT", 440, 0)
    row.yieldText:SetWidth(60)

    row.editBtn = CreateBtn(row, 55, 20, "Bearb.", function()
        if not ADDON.DB:CanEditRecipes() then
            ADDON:Print("Keine Berechtigung.")
            return
        end
        UI:OpenRecipeEditor(row.recipeID)
    end)
    row.editBtn:SetPoint("LEFT", 510, 0)

    row.deleteBtn = CreateBtn(row, 55, 20, "Entf.", function()
        if not ADDON.DB:CanEditRecipes() then
            ADDON:Print("Keine Berechtigung.")
            return
        end
        local dialog = StaticPopup_Show("GSP_CONFIRM_DELETE")
        if dialog then dialog.data = row.recipeID end
    end)
    row.deleteBtn:SetPoint("LEFT", 570, 0)

    SetItemTooltip(row, function(self) return self.recipeID end)

    recipeRows[index] = row
    return row
end

function UI:RefreshRecipeList()
    if not recipeScrollContent then return end
    local recipes = ADDON.DB:GetRecipes()
    local canEdit = ADDON.DB:CanEditRecipes()

    -- Alle Zeilen verstecken
    for _, r in ipairs(recipeRows) do r:Hide() end

    -- Rezepte sortiert nach ItemID
    local sorted = {}
    for _, recipe in pairs(recipes) do
        table.insert(sorted, recipe)
    end
    table.sort(sorted, function(a, b) return a.mainItemID < b.mainItemID end)

    for i, recipe in ipairs(sorted) do
        local row = self:GetRecipeRow(i)
        row.recipeID = recipe.mainItemID
        SetRowIcon(row.icon, recipe.mainItemID)
        row.itemText:SetText(ADDON:GetColoredItemName(recipe.mainItemID))
        row.stockText:SetText(tostring(recipe.desiredStock))
        row.yieldText:SetText(tostring(recipe.yield))
        row.editBtn:SetEnabled(canEdit)
        row.deleteBtn:SetEnabled(canEdit)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:Show()
        GetItemInfo(recipe.mainItemID)
    end

    recipeScrollContent:SetHeight(math.max(1, #sorted * ROW_HEIGHT))
    UpdateScrollRange(recipeScrollFrame)
    if newRecipeBtn then newRecipeBtn:SetEnabled(canEdit) end
end

---------------------------------------------------------------------------
-- REZEPT-EDITOR (Modal)
---------------------------------------------------------------------------

function UI:CreateRecipeEditor()
    editorFrame = CreateFrame("Frame", "GSPEditorFrame", mainFrame, "BackdropTemplate")
    editorFrame:SetSize(EDITOR_W, EDITOR_H)
    editorFrame:SetPoint("CENTER", mainFrame, "CENTER")
    editorFrame:SetFrameStrata("DIALOG")
    ApplyBackdrop(editorFrame, BD_MAIN, 0.06, 0.06, 0.10, 0.98, 0.5, 0.5, 0.5)
    MakeMovable(editorFrame)
    editorFrame:Hide()

    self.edTitle = CreateLabel(editorFrame, "GameFontNormalLarge", "Rezept bearbeiten", "TOPLEFT", 16, -12)
    local cls = CreateFrame("Button", nil, editorFrame, "UIPanelCloseButton")
    cls:SetPoint("TOPRIGHT", -2, -2)
    cls:SetScript("OnClick", function() UI:CloseRecipeEditor() end)

    local y = -40

    -- Hauptitem
    CreateLabel(editorFrame, "GameFontNormal", "Hauptitem (Name, ItemID oder Shift-Klick):", "TOPLEFT", 16, y)
    y = y - 20
    self.edMainItemEB = CreateEB(editorFrame, 260, 24)
    self.edMainItemEB:SetPoint("TOPLEFT", 16, y)
    self.edMainItemEB:SetMaxLetters(80)
    table.insert(self.itemLinkEBs, self.edMainItemEB)

    self.edMainItemResolve = CreateLabel(editorFrame, "GameFontHighlightSmall", "", "LEFT", self.edMainItemEB, "RIGHT", 10, 0)
    self.edMainItemResolve:SetWidth(220)
    self.edMainItemEB:SetScript("OnTextChanged", function(eb, userInput)
        if not userInput then return end
        local text = eb:GetText()
        local id = ADDON:ResolveItemInput(text)
        if id then
            UI.edMainItemResolve:SetText(ADDON:GetColoredItemName(id))
            GetItemInfo(id)
            UI:HideAutocomplete()
        else
            UI.edMainItemResolve:SetText("")
            if text and #text >= 2 then
                UI:ShowAutocomplete(eb, text)
            else
                UI:HideAutocomplete()
            end
        end
    end)
    self.edMainItemEB:HookScript("OnEditFocusLost", function()
        C_Timer.After(0.2, function() UI:HideAutocomplete() end)
    end)

    y = y - 30

    -- Wunschbestand
    CreateLabel(editorFrame, "GameFontNormal", "Wunschbestand:", "TOPLEFT", 16, y)
    self.edDesiredEB = CreateEB(editorFrame, 80, 24, true)
    self.edDesiredEB:SetPoint("TOPLEFT", 150, y)
    self.edDesiredEB:SetMaxLetters(7)

    -- Ertrag pro Craft
    CreateLabel(editorFrame, "GameFontNormal", "Ertrag/Craft:", "TOPLEFT", 260, y)
    self.edYieldEB = CreateEB(editorFrame, 60, 24, true)
    self.edYieldEB:SetPoint("TOPLEFT", 370, y)
    self.edYieldEB:SetMaxLetters(5)

    y = y - 34

    -- Materialien Header
    CreateLabel(editorFrame, "GameFontNormal", "Materialien:", "TOPLEFT", 16, y)
    y = y - 4

    local addMatBtn = CreateBtn(editorFrame, 140, 22, "Material hinzufuegen", function()
        UI:AddEditorMat()
    end)
    addMatBtn:SetPoint("TOPLEFT", 140, y + 2)

    y = y - 22

    -- Scroll fuer Material-Zeilen
    local matScroll = CreateFrame("ScrollFrame", "GSPEditorMatScroll", editorFrame, "UIPanelScrollFrameTemplate")
    matScroll:SetPoint("TOPLEFT", 16, y)
    matScroll:SetPoint("BOTTOMRIGHT", -SCROLL_BAR_SPACE - 10, 50)
    self.edMatContent = CreateFrame("Frame", nil, matScroll)
    self.edMatContent:SetWidth(EDITOR_W - 60)
    self.edMatContent:SetHeight(1)
    matScroll:SetScrollChild(self.edMatContent)

    -- Speichern / Abbrechen
    CreateBtn(editorFrame, 120, 26, "Speichern", function()
        UI:SaveRecipeFromEditor()
    end):SetPoint("BOTTOMLEFT", 16, 14)

    CreateBtn(editorFrame, 120, 26, "Abbrechen", function()
        UI:CloseRecipeEditor()
    end):SetPoint("BOTTOMRIGHT", -16, 14)

end

--- Erzeugt eine einheitliche Editor-Zeile (funktioniert auf jeder Tiefe).
function UI:CreateEditorRowFrame(index)
    local row = CreateFrame("Frame", nil, self.edMatContent)
    row:SetSize(EDITOR_W - 60, MAT_ROW_H)

    -- Einrueckungs-Indikator (wird dynamisch konfiguriert)
    row.indentText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.indentText:SetPoint("LEFT", 2, 0)
    row.indentText:Hide()

    row.itemEB = CreateEB(row, 200, 22)
    row.itemEB:SetPoint("LEFT", 0, 0)
    table.insert(self.itemLinkEBs, row.itemEB)

    row.itemResolve = CreateLabel(row, "GameFontHighlightSmall", "", "LEFT", row.itemEB, "RIGHT", 6, 0)
    row.itemResolve:SetWidth(120)

    row.itemEB:SetMaxLetters(80)
    row.itemEB:SetScript("OnTextChanged", function(eb, userInput)
        if not userInput then return end
        local text = eb:GetText()
        local id = ADDON:ResolveItemInput(text)
        if id then
            row.itemResolve:SetText(ADDON:GetColoredItemName(id))
            GetItemInfo(id)
            UI:HideAutocomplete()
        else
            row.itemResolve:SetText("")
            if text and #text >= 2 then
                UI:ShowAutocomplete(eb, text)
            else
                UI:HideAutocomplete()
            end
        end
    end)
    row.itemEB:HookScript("OnEditFocusLost", function()
        C_Timer.After(0.2, function() UI:HideAutocomplete() end)
    end)

    CreateLabel(row, "GameFontNormalSmall", "Menge:", "LEFT", 340, 0)
    row.qtyEB = CreateEB(row, 60, 22, true)
    row.qtyEB:SetPoint("LEFT", 385, 0)
    row.qtyEB:SetMaxLetters(6)

    row.removeBtn = CreateBtn(row, 22, 22, "X", function()
        UI:RemoveByPath(row.path)
    end)
    row.removeBtn:SetPoint("LEFT", 452, 0)

    -- Sub-Material hinzufuegen ("+")
    row.addSubBtn = CreateBtn(row, 30, 22, "+", function()
        UI:AddSubByPath(row.path)
    end)
    row.addSubBtn:SetPoint("LEFT", 480, 0)

    return row
end

--- Konfiguriert eine Zeile fuer die angegebene Verschachtelungstiefe.
function UI:ConfigureRowDepth(row, depth)
    if depth > 0 then
        row.indentText:SetText("|cff666666\226\134\179|r") -- ↳
        row.indentText:ClearAllPoints()
        row.indentText:SetPoint("LEFT", (depth - 1) * 20 + 2, 0)
        row.indentText:Show()
    else
        row.indentText:SetText("")
        row.indentText:Hide()
    end

    local xStart = depth * 20
    row.itemEB:ClearAllPoints()
    row.itemEB:SetPoint("LEFT", xStart, 0)
    row.itemEB:SetWidth(math.max(80, 200 - xStart))
    row.itemResolve:SetWidth(math.max(40, 120 - xStart))
end

--- Gibt das Material-Entry fuer einen Pfad zurueck.
---   path = {2}       → editorMats[2]
---   path = {2, 1}    → editorMats[2].subMats[1]
---   path = {2, 1, 3} → editorMats[2].subMats[1].subMats[3]
function UI:GetMatByPath(path)
    if not path or #path == 0 then return nil end
    local current = self.editorMats
    for i = 1, #path - 1 do
        local entry = current[path[i]]
        if not entry or not entry.subMats then return nil end
        current = entry.subMats
    end
    return current[path[#path]]
end

function UI:SyncEditorMats()
    for _, row in ipairs(self.editorAllRows) do
        if row:IsShown() and row.path then
            local mat = self:GetMatByPath(row.path)
            if mat then
                mat.itemID = ADDON:ResolveItemInput(row.itemEB:GetText())
                mat.qty    = ADDON:SafeInt(row.qtyEB:GetText(), 1, 1)
            end
        end
    end
end

function UI:RefreshEditorMatRows()
    -- Alle verstecken
    for _, row in ipairs(self.editorAllRows) do row:Hide() end

    local rowIdx  = 0
    local yOffset = 0

    -- Rekursive Darstellung aller Materialien + Sub-Materialien
    local function displayMats(mats, depth, parentPath)
        for i, mat in ipairs(mats) do
            rowIdx = rowIdx + 1
            local row = self.editorAllRows[rowIdx]
            if not row then
                row = self:CreateEditorRowFrame(rowIdx)
                self.editorAllRows[rowIdx] = row
            end

            -- Pfad bauen (Kopie von parentPath + i)
            local path = {}
            for _, p in ipairs(parentPath) do path[#path + 1] = p end
            path[#path + 1] = i
            row.path  = path
            row.depth = depth

            -- Daten setzen
            row.itemEB:SetText(mat.itemID and tostring(mat.itemID) or "")
            row.qtyEB:SetText(tostring(mat.qty or 1))

            -- Tiefe konfigurieren (Einrueckung)
            self:ConfigureRowDepth(row, depth)

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -yOffset)
            row:Show()
            yOffset = yOffset + MAT_ROW_H

            -- Resolve-Label + Sub-Count
            local id = mat.itemID
            if id then
                local label = ADDON:GetColoredItemName(id)
                local subCount = mat.subMats and #mat.subMats or 0
                if subCount > 0 then
                    label = label .. " |cff88cc88(" .. subCount .. " Sub)|r"
                end
                row.itemResolve:SetText(label)
                GetItemInfo(id)
            else
                row.itemResolve:SetText("")
            end
            row.addSubBtn:Show()

            -- Rekursiv Sub-Materialien anzeigen
            if mat.subMats then
                displayMats(mat.subMats, depth + 1, path)
            end
        end
    end

    displayMats(self.editorMats, 0, {})
    self.edMatContent:SetHeight(math.max(1, yOffset))
end

function UI:AddEditorMat()
    self:SyncEditorMats()
    table.insert(self.editorMats, { itemID = nil, qty = 1 })
    self:RefreshEditorMatRows()
end

--- Fuegt ein Sub-Material per Pfad hinzu (beliebige Tiefe).
function UI:AddSubByPath(path)
    self:SyncEditorMats()
    local mat = self:GetMatByPath(path)
    if not mat then return end
    if not mat.subMats then mat.subMats = {} end
    table.insert(mat.subMats, { itemID = nil, qty = 1 })
    self:RefreshEditorMatRows()
end

--- Entfernt ein Material/Sub-Material per Pfad (beliebige Tiefe).
function UI:RemoveByPath(path)
    self:SyncEditorMats()
    if not path or #path == 0 then return end

    if #path == 1 then
        -- Top-Level Material
        table.remove(self.editorMats, path[1])
    else
        -- Verschachteltes Sub-Material: Eltern-Liste ermitteln
        local parentPath = {}
        for i = 1, #path - 1 do parentPath[#parentPath + 1] = path[i] end
        local parent = self:GetMatByPath(parentPath)
        if parent and parent.subMats then
            table.remove(parent.subMats, path[#path])
            if #parent.subMats == 0 then parent.subMats = nil end
        end
    end
    self:RefreshEditorMatRows()
end

--- Resolve-Label fuer Hauptitem manuell aktualisieren.
function UI:ResolveEditorMainItem()
    local text = self.edMainItemEB:GetText()
    local id = ADDON:ResolveItemInput(text)
    if id then
        self.edMainItemResolve:SetText(ADDON:GetColoredItemName(id))
    else
        self.edMainItemResolve:SetText("")
    end
end

function UI:OpenRecipeEditor(recipeID)
    if not editorFrame then return end
    self.editingRecipeID = recipeID

    if recipeID then
        local recipe = ADDON.DB:GetRecipe(recipeID)
        if recipe then
            self.edMainItemEB:SetText(tostring(recipe.mainItemID))
            self.edDesiredEB:SetText(tostring(recipe.desiredStock))
            self.edYieldEB:SetText(tostring(recipe.yield))
            -- Rekursives Laden aller Ebenen
            local function loadMats(src)
                local out = {}
                for _, m in ipairs(src or {}) do
                    local e = { itemID = m.itemID, qty = m.qty }
                    if m.subMats and #m.subMats > 0 then
                        e.subMats = loadMats(m.subMats)
                    end
                    out[#out + 1] = e
                end
                return out
            end
            self.editorMats = loadMats(recipe.mats)
        end
    else
        self.edMainItemEB:SetText("")
        self.edDesiredEB:SetText("0")
        self.edYieldEB:SetText("1")
        self.editorMats = {}
    end

    self:ResolveEditorMainItem()
    self:RefreshEditorMatRows()
    editorFrame:Show()
end

function UI:CloseRecipeEditor()
    if editorFrame then editorFrame:Hide() end
    self.editingRecipeID = nil
    self.editorMats = {}
end

function UI:SaveRecipeFromEditor()
    self:SyncEditorMats()

    local mainItemID = ADDON:ResolveItemInput(self.edMainItemEB:GetText())
    if not mainItemID then
        ADDON:Print("Item nicht gefunden. Nutze ItemID, Shift-Klick oder einen bekannten Itemnamen.")
        return
    end

    local desiredStock = ADDON:SafeInt(self.edDesiredEB:GetText(), 0, 0)
    local yield        = ADDON:SafeInt(self.edYieldEB:GetText(), 1, 1)

    -- Rekursives Speichern aller Ebenen
    local function buildMats(edMats)
        local out = {}
        for _, mat in ipairs(edMats) do
            if mat.itemID and mat.qty and mat.qty > 0 then
                local entry = { itemID = mat.itemID, qty = mat.qty }
                if mat.subMats and #mat.subMats > 0 then
                    entry.subMats = buildMats(mat.subMats)
                    if #entry.subMats == 0 then entry.subMats = nil end
                end
                out[#out + 1] = entry
            end
        end
        return out
    end
    local mats = buildMats(self.editorMats)

    -- Falls mainItemID geaendert wurde, altes Rezept loeschen
    if self.editingRecipeID and self.editingRecipeID ~= mainItemID then
        ADDON.DB:AddLogEntry("del", UnitName("player"), self.editingRecipeID)
        ADDON.DB:DeleteRecipe(self.editingRecipeID)
        if ADDON.Sync then ADDON.Sync:BroadcastRecipeDel(self.editingRecipeID) end
    end

    local recipe = {
        mainItemID   = mainItemID,
        desiredStock = desiredStock,
        yield        = yield,
        mats         = mats,
    }

    if ADDON.DB:SaveRecipe(recipe) then
        local savedRecipe = ADDON.DB:GetRecipe(mainItemID)
        ADDON.DB:AddLogEntry("add", UnitName("player"), mainItemID)
        if ADDON.Sync and savedRecipe then
            ADDON.Sync:BroadcastRecipeAdd(savedRecipe)
        end
        self:CloseRecipeEditor()
        self:RefreshRecipeList()
        ADDON:Print("Rezept gespeichert.")
    end
end

---------------------------------------------------------------------------
-- ZU-FARMEN-TAB
---------------------------------------------------------------------------

function UI:CreateFarmTab()
    local f = CreateFrame("Frame", nil, contentInset)
    f:SetPoint("TOPLEFT", 5, -5)
    f:SetPoint("BOTTOMRIGHT", -5, 5)
    f:Hide()

    farmScrollFrame, farmScrollContent = CreateScrollFrame(f, "GSPFarmScroll")
    farmScrollFrame:SetPoint("TOPLEFT", 0, 0)
    farmScrollFrame:SetPoint("BOTTOMRIGHT", -SCROLL_BAR_SPACE, 0)

    return f
end

function UI:GetFarmRow(index)
    if farmRows[index] then return farmRows[index] end

    local row = CreateFrame("Frame", nil, farmScrollContent, "BackdropTemplate")
    row:SetSize(SCROLL_CONTENT_W, ROW_HEIGHT)

    if index % 2 == 0 then
        row:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
        row:SetBackdropColor(0.12, 0.12, 0.16, 0.3)
    end

    row.icon = CreateRowIcon(row)

    row.itemText = CreateLabel(row, "GameFontHighlight", nil, "LEFT", TEXT_OFFSET, 0)
    row.itemText:SetWidth(250)
    row.itemText:SetJustifyH("LEFT")

    row.col2 = CreateLabel(row, "GameFontNormal", nil, "LEFT", 290, 0)
    row.col2:SetWidth(100)
    row.col3 = CreateLabel(row, "GameFontNormal", nil, "LEFT", 400, 0)
    row.col3:SetWidth(100)
    row.col4 = CreateLabel(row, "GameFontNormal", nil, "LEFT", 510, 0)
    row.col4:SetWidth(100)

    -- Erweiterter Tooltip: zeigt Sub-Materialien fuer craftbare Items
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.itemID then return end
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
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    farmRows[index] = row
    return row
end

--- Konfiguriert eine Farm-Zeile als klickbaren Sektions-Header.
local function SetupFarmHeader(row, sectionIdx, collapsed, count, label, col2Lbl, col3Lbl, col4Lbl)
    row.itemID     = nil
    row.craftable  = nil
    row.subMats    = nil
    row.missingQty = nil
    SetRowIcon(row.icon, nil)
    local arrow = collapsed and "|cffffd100[+]|r " or "|cffffd100[-]|r "
    row.itemText:SetText(arrow .. "|cffffd100" .. label .. " (" .. count .. ")|r")
    row.col2:SetText("|cffffd100" .. col2Lbl .. "|r")
    row.col3:SetText("|cffffd100" .. col3Lbl .. "|r")
    row.col4:SetText("|cffffd100" .. col4Lbl .. "|r")
    row:EnableMouse(true)
    row:SetScript("OnMouseDown", function()
        farmSectionCollapsed[sectionIdx] = not farmSectionCollapsed[sectionIdx]
        UI:RefreshFarmTab()
    end)
    -- Header-Hintergrund
    if not row._headerBg then
        row._headerBg = row:CreateTexture(nil, "BACKGROUND", nil, 2)
        row._headerBg:SetAllPoints()
    end
    row._headerBg:SetColorTexture(0.18, 0.18, 0.25, 0.55)
    row._headerBg:Show()
end

--- Setzt eine Farm-Zeile zurueck (normaler Item-Eintrag).
local function ResetFarmRow(row)
    row:SetScript("OnMouseDown", nil)
    if row._headerBg then row._headerBg:Hide() end
    row.craftable  = nil
    row.subMats    = nil
    row.missingQty = nil
end

function UI:RefreshFarmTab()
    if not farmScrollContent then return end

    for _, r in ipairs(farmRows) do r:Hide() end

    local missingMats, missingMains = ADDON.Calculator:Calculate()
    local scan = ADDON.DB:GetLastScan()
    local idx = 0

    ---------------------------------------------------------------------------
    -- Sektion 1: Hauptitems unter Soll
    ---------------------------------------------------------------------------
    if #missingMains > 0 then
        idx = idx + 1
        local hdrRow = self:GetFarmRow(idx)
        SetupFarmHeader(hdrRow, 1, farmSectionCollapsed[1], #missingMains,
            "Hauptitems unter Soll", "Soll", "Bank", "Fehlend")
        hdrRow:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_HEIGHT)
        hdrRow:Show()

        if not farmSectionCollapsed[1] then
            for _, entry in ipairs(missingMains) do
                idx = idx + 1
                local row = self:GetFarmRow(idx)
                ResetFarmRow(row)
                row.itemID = entry.itemID
                SetRowIcon(row.icon, entry.itemID)
                row.itemText:SetText(ADDON:GetColoredItemName(entry.itemID))
                row.col2:SetText(tostring(entry.desired))
                row.col3:SetText(tostring(entry.inBank))
                row.col4:SetText("|cffff4444" .. entry.missing .. "|r")
                row:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_HEIGHT)
                row:Show()
                GetItemInfo(entry.itemID)
            end
        end

        -- Leerzeile als Trenner
        idx = idx + 1
        local spacer = self:GetFarmRow(idx)
        ResetFarmRow(spacer)
        spacer.itemID = nil
        SetRowIcon(spacer.icon, nil)
        spacer.itemText:SetText("")
        spacer.col2:SetText("")
        spacer.col3:SetText("")
        spacer.col4:SetText("")
        spacer:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_HEIGHT)
        spacer:Show()
    end

    ---------------------------------------------------------------------------
    -- Sektion 2: Fehlende Materialien (Basis-Mats, rekursiv aufgeloest)
    ---------------------------------------------------------------------------
    if #missingMats > 0 then
        idx = idx + 1
        local hdrRow = self:GetFarmRow(idx)
        SetupFarmHeader(hdrRow, 2, farmSectionCollapsed[2], #missingMats,
            "Zu farmende Materialien", "Benoetigt", "Bank", "Fehlend")
        hdrRow:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_HEIGHT)
        hdrRow:Show()

        if not farmSectionCollapsed[2] then
            for _, entry in ipairs(missingMats) do
                idx = idx + 1
                local row = self:GetFarmRow(idx)
                ResetFarmRow(row)
                row.itemID     = entry.itemID
                row.craftable  = entry.craftable
                row.subMats    = entry.subMats
                row.missingQty = entry.missing
                SetRowIcon(row.icon, entry.itemID)
                local nameStr = ADDON:GetColoredItemName(entry.itemID)
                if entry.craftable then
                    nameStr = nameStr .. " |cff88cc88(craftbar)|r"
                end
                row.itemText:SetText(nameStr)
                row.col2:SetText(tostring(entry.required))
                row.col3:SetText(tostring(entry.inBank))
                row.col4:SetText("|cffff4444" .. entry.missing .. "|r")
                row:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_HEIGHT)
                row:Show()
                GetItemInfo(entry.itemID)
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Leer-Hinweis
    ---------------------------------------------------------------------------
    if idx == 0 then
        idx = 1
        local row = self:GetFarmRow(idx)
        ResetFarmRow(row)
        row.itemID = nil
        SetRowIcon(row.icon, nil)
        if scan.ts == 0 then
            row.itemText:SetText("|cff888888Noch kein Scan durchgefuehrt.|r")
        else
            row.itemText:SetText("|cff88ff88Alles auf Lager! Keine Fehlbestaende.|r")
        end
        row.col2:SetText("")
        row.col3:SetText("")
        row.col4:SetText("")
        row:SetPoint("TOPLEFT", 0, 0)
        row:Show()
    end

    farmScrollContent:SetHeight(math.max(1, idx * ROW_HEIGHT))
    UpdateScrollRange(farmScrollFrame)
end

---------------------------------------------------------------------------
-- GILDENBANK-TAB (alle gescannten Items)
---------------------------------------------------------------------------

function UI:CreateStockTab()
    local f = CreateFrame("Frame", nil, contentInset)
    f:SetPoint("TOPLEFT", 5, -5)
    f:SetPoint("BOTTOMRIGHT", -5, 5)
    f:Hide()

    -- Info-Zeile oben
    f.infoText = CreateLabel(f, "GameFontNormalSmall", "", "TOPLEFT", 8, -2)
    f.infoText:SetWidth(500)
    f.infoText:SetJustifyH("LEFT")

    -- Spalten-Header
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetPoint("TOPLEFT", 0, -20)
    hdr:SetSize(SCROLL_CONTENT_W, 18)
    CreateLabel(hdr, "GameFontNormalSmall", "Item",   "LEFT", 8, 0)
    CreateLabel(hdr, "GameFontNormalSmall", "Anzahl", "LEFT", 400, 0)

    -- ScrollFrame
    stockScrollFrame, stockScrollContent = CreateScrollFrame(f, "GSPStockScroll")
    stockScrollFrame:SetPoint("TOPLEFT", 0, -40)
    stockScrollFrame:SetPoint("BOTTOMRIGHT", -SCROLL_BAR_SPACE, 0)

    return f
end

function UI:GetStockRow(index)
    if stockRows[index] then return stockRows[index] end

    local row = CreateFrame("Frame", nil, stockScrollContent, "BackdropTemplate")
    row:SetSize(SCROLL_CONTENT_W, ROW_HEIGHT)

    if index % 2 == 0 then
        row:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
        row:SetBackdropColor(0.12, 0.12, 0.16, 0.3)
    end

    row.icon = CreateRowIcon(row)

    row.itemText = CreateLabel(row, "GameFontHighlight", nil, "LEFT", TEXT_OFFSET, 0)
    row.itemText:SetWidth(360)
    row.itemText:SetJustifyH("LEFT")

    row.countText = CreateLabel(row, "GameFontNormal", nil, "LEFT", 400, 0)
    row.countText:SetWidth(120)

    SetItemTooltip(row, function(self) return self.itemID end)

    stockRows[index] = row
    return row
end

function UI:RefreshStockTab()
    if not stockScrollContent then return end

    -- Alle Zeilen verstecken
    for _, r in ipairs(stockRows) do r:Hide() end

    local scan       = ADDON.DB:GetLastScan()
    local bankCounts = scan.bankCounts or {}
    local parent     = stockScrollFrame:GetParent() -- Tab-Frame mit infoText

    -- Info-Zeile aktualisieren
    if scan.ts == 0 then
        parent.infoText:SetText("|cff888888Noch kein Scan durchgefuehrt. Oeffne die Gildenbank und klicke 'Scan'.|r")
    else
        local itemCount = 0
        for _ in pairs(bankCounts) do itemCount = itemCount + 1 end
        parent.infoText:SetText(string.format(
            "Letzter Scan: |cffffd100%s|r  –  |cffffd100%d|r verschiedene Items",
            date("%d.%m.%Y %H:%M:%S", scan.ts), itemCount))
    end

    -- Items sammeln und nach Name sortieren (mit Fallback auf ID)
    local items = {}
    for itemID, count in pairs(bankCounts) do
        local name = GetItemInfo(itemID) -- fordert ggf. Cache-Request an
        table.insert(items, {
            itemID = itemID,
            count  = count,
            name   = name or ("Item:" .. itemID),
        })
    end
    table.sort(items, function(a, b)
        if a.name == b.name then return a.itemID < b.itemID end
        return a.name < b.name
    end)

    -- Zeilen befuellen
    for i, entry in ipairs(items) do
        local row = self:GetStockRow(i)
        row.itemID = entry.itemID
        SetRowIcon(row.icon, entry.itemID)
        row.itemText:SetText(ADDON:GetColoredItemName(entry.itemID))
        row.countText:SetText("|cffffffff" .. entry.count .. "|r")
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:Show()
    end

    stockScrollContent:SetHeight(math.max(1, #items * ROW_HEIGHT))
    UpdateScrollRange(stockScrollFrame)
end

---------------------------------------------------------------------------
-- SYNC-LOG-TAB
---------------------------------------------------------------------------

function UI:CreateLogTab()
    local f = CreateFrame("Frame", nil, contentInset)
    f:SetPoint("TOPLEFT", 5, -5)
    f:SetPoint("BOTTOMRIGHT", -5, 5)
    f:Hide()

    -- Info oben
    f.infoText = CreateLabel(f, "GameFontNormalSmall", "", "TOPLEFT", 8, -2)
    f.infoText:SetWidth(400)
    f.infoText:SetJustifyH("LEFT")

    -- Manueller Sync Button
    local syncNowBtn = CreateBtn(f, 120, 22, "Sync Rezepte", function()
        if ADDON.Sync then ADDON.Sync:ManualSync() end
    end)
    syncNowBtn:SetPoint("TOPRIGHT", 0, 0)

    -- Spalten-Header
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetPoint("TOPLEFT", 0, -28)
    hdr:SetSize(SCROLL_CONTENT_W, 18)
    CreateLabel(hdr, "GameFontNormalSmall", "Zeitpunkt",  "LEFT", 8, 0)
    CreateLabel(hdr, "GameFontNormalSmall", "Aktion",     "LEFT", 110, 0)
    CreateLabel(hdr, "GameFontNormalSmall", "Spieler",    "LEFT", 310, 0)
    CreateLabel(hdr, "GameFontNormalSmall", "Details",    "LEFT", 440, 0)

    -- ScrollFrame
    logScrollFrame, logScrollContent = CreateScrollFrame(f, "GSPLogScroll")
    logScrollFrame:SetPoint("TOPLEFT", 0, -48)
    logScrollFrame:SetPoint("BOTTOMRIGHT", -SCROLL_BAR_SPACE, 0)

    return f
end

function UI:GetLogRow(index)
    if logRows[index] then return logRows[index] end

    local row = CreateFrame("Frame", nil, logScrollContent, "BackdropTemplate")
    row:SetSize(SCROLL_CONTENT_W, ROW_HEIGHT)

    if index % 2 == 0 then
        row:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
        row:SetBackdropColor(0.12, 0.12, 0.16, 0.3)
    end

    row.timeText = CreateLabel(row, "GameFontHighlightSmall", nil, "LEFT", 8, 0)
    row.timeText:SetWidth(96)
    row.timeText:SetJustifyH("LEFT")

    row.actionText = CreateLabel(row, "GameFontNormalSmall", nil, "LEFT", 110, 0)
    row.actionText:SetWidth(195)
    row.actionText:SetJustifyH("LEFT")

    row.whoText = CreateLabel(row, "GameFontNormalSmall", nil, "LEFT", 310, 0)
    row.whoText:SetWidth(125)
    row.whoText:SetJustifyH("LEFT")

    row.detailText = CreateLabel(row, "GameFontDisableSmall", nil, "LEFT", 440, 0)
    row.detailText:SetWidth(240)
    row.detailText:SetJustifyH("LEFT")

    logRows[index] = row
    return row
end

function UI:RefreshLogTab()
    if not logScrollContent then return end
    for _, r in ipairs(logRows) do r:Hide() end

    local log = ADDON.DB:GetSyncLog()

    -- Info-Text
    local parent = logScrollFrame:GetParent()
    local syncText = ADDON.Sync and ADDON.Sync:GetStatusText() or "Bereit"
    parent.infoText:SetText("Sync-Status: |cffffd100" .. syncText .. "|r  |cff888888(" .. #log .. " Eintraege)|r")

    for i, entry in ipairs(log) do
        local row = self:GetLogRow(i)

        -- Zeitstempel
        row.timeText:SetText("|cffaaaaaa" .. date("%d.%m. %H:%M", entry.ts) .. "|r")

        -- Aktion (farbig)
        local actionStr = ""
        if entry.action == "add" then
            actionStr = "|cff88ff88+ Rezept hinzugefuegt|r"
        elseif entry.action == "del" then
            actionStr = "|cffff4444- Rezept geloescht|r"
        elseif entry.action == "edit" then
            actionStr = "|cffffd100~ Rezept bearbeitet|r"
        elseif entry.action == "sync_out" then
            actionStr = "|cff4488ff-> Daten gesendet|r"
        elseif entry.action == "sync_in" then
            actionStr = "|cff44ff88<- Daten empfangen|r"
        elseif entry.action == "sync_ok" then
            actionStr = "|cff88ff88= Sync OK|r"
        else
            actionStr = entry.action
        end
        row.actionText:SetText(actionStr)

        -- Spieler
        local whoColor = (entry.who == UnitName("player")) and "|cff88ccff" or "|cffffcc00"
        row.whoText:SetText(whoColor .. (entry.who or "") .. "|r")

        -- Details (Itemname oder sonstige Info)
        local detail = ""
        if entry.itemID then
            detail = ADDON:GetColoredItemName(entry.itemID)
            GetItemInfo(entry.itemID) -- Cache
        elseif entry.detail and entry.detail ~= "" then
            detail = "|cffcccccc" .. entry.detail .. "|r"
        end
        row.detailText:SetText(detail)

        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:Show()
    end

    if #log == 0 then
        local row = self:GetLogRow(1)
        row.timeText:SetText("")
        row.actionText:SetText("|cff888888Noch keine Sync-Aktivitaet.|r")
        row.whoText:SetText("")
        row.detailText:SetText("")
        row:SetPoint("TOPLEFT", 0, 0)
        row:Show()
    end

    logScrollContent:SetHeight(math.max(1, math.max(#log, 1) * ROW_HEIGHT))
    UpdateScrollRange(logScrollFrame)
end

---------------------------------------------------------------------------
-- HOW-TO-TAB
---------------------------------------------------------------------------

function UI:CreateHowToTab()
    local f = CreateFrame("Frame", nil, contentInset)
    f:SetPoint("TOPLEFT", 5, -5)
    f:SetPoint("BOTTOMRIGHT", -5, 5)
    f:Hide()

    -- ScrollFrame fuer den gesamten Text
    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 0)
    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetWidth(scrollFrame:GetWidth() or 680)
    scrollFrame:SetScrollChild(scrollContent)

    -- Textinhalt
    local helpText = scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    helpText:SetPoint("TOPLEFT", 10, -8)
    helpText:SetWidth(660)
    helpText:SetJustifyH("LEFT")
    helpText:SetSpacing(3)
    helpText:SetText(
        "|cffff8800GuildStockPlanner – Kurzanleitung|r\n" ..
        "|cffaaaaaa-----------------------------------------------------|r\n\n" ..

        "|cffffd100Was ist der GuildStockPlanner?|r\n" ..
        "Der GuildStockPlanner hilft eurer Gilde dabei, den Ueberblick ueber die\n" ..
        "Gildenbank zu behalten. Ihr legt Rezepte an (z.B. Flasks, Elixiere, Food)\n" ..
        "und das Addon berechnet automatisch, welche Materialien noch gefarmt werden muessen.\n\n" ..

        "|cffffd100Schritt 1: Gildenbank scannen|r\n" ..
        "  1.  Oeffne die |cff00ff00Gildenbank|r an einem Gildenbank-NPC.\n" ..
        "  2.  Klicke oben rechts auf |cff00ff00\"Scan (Gildenbank)\"|r.\n" ..
        "  3.  Das Addon liest automatisch alle Tabs nacheinander.\n" ..
        "  4.  Nach dem Scan weiss das Addon, was in der Bank liegt.\n\n" ..

        "|cffffd100Schritt 2: Rezepte anlegen|r\n" ..
        "  1.  Gehe zum Tab |cff00ff00\"Rezepte\"|r.\n" ..
        "  2.  Klicke auf |cff00ff00\"Neues Rezept\"|r.\n" ..
        "  3.  Gib das Hauptitem ein (das Endprodukt, z.B. Flask of Supreme Power).\n" ..
        "       > Per |cff00ffffShift-Klick|r auf ein Item im Inventar,\n" ..
        "       > oder |cff00ffffItemID|r eintippen,\n" ..
        "       > oder den |cff00ffffItemnamen|r eingeben (deutsch oder englisch).\n" ..
        "  4.  Setze den |cff00ff00Wunschbestand|r (wie viele sollen in der Bank sein?).\n" ..
        "  5.  Setze den |cff00ff00Ertrag|r (wie viele bekommt man pro Craft?).\n" ..
        "  6.  Fuege die |cff00ff00Materialien|r hinzu (Item + Menge pro Craft).\n" ..
        "  7.  Klicke |cff00ff00\"Speichern\"|r.\n\n" ..

        "|cffffd100Schritt 3: Fehlende Materialien ansehen|r\n" ..
        "  Wechsle zum Tab |cff00ff00\"Zu farmen\"|r.\n" ..
        "  Dort siehst du genau, welche Materialien noch fehlen:\n" ..
        "  |cffaaaaaa  Benoetigt = (Wunschbestand - In Bank) / Ertrag * Materialmenge|r\n" ..
        "  |cffaaaaaa  Fehlend   = Benoetigt - was schon in der Bank liegt|r\n\n" ..

        "  |cffffd100Sektionen ein-/ausklappen|r: Klicke auf die Ueberschriften\n" ..
        "  |cff00ff00\"Hauptitems\"|r oder |cff00ff00\"Zu farmende Materialien\"|r um die Sektionen\n" ..
        "  ein- oder auszuklappen.\n\n" ..

        "|cffffd100Unter-Materialien (Endlos verschachtelbar)|r\n" ..
        "  Materialien koennen selbst aus Unter-Materialien bestehen,\n" ..
        "  und Unter-Materialien koennen wiederum Unter-Materialien haben.\n" ..
        "  Im Rezept-Editor siehst du neben |cff00ff00jedem|r Material einen |cff00ff00\"+\"|r Button.\n" ..
        "  Klicke darauf, um Unter-Materialien hinzuzufuegen (beliebig tief).\n" ..
        "  Eingerueckte Zeilen (|cff666666\226\134\179|r) zeigen die Verschachtelung.\n\n" ..
        "  |cffffd100In der Farmliste:|r\n" ..
        "  Unter-Materialien werden zur Gesamtmenge dazugerechnet.\n" ..
        "  Materialien mit Unter-Materialien zeigen |cff88cc88(craftbar)|r.\n" ..
        "  |cff00ff00Hover|r zeigt die benoetigten Unter-Materialien im Tooltip.\n\n" ..

        "|cffffd100Weitere Tabs|r\n" ..
        "  |cff00ff00Gildenbank|r    – Zeigt alle gescannten Items mit Anzahl.\n" ..
        "  |cff00ff00Sync-Log|r     – Zeigt wer wann Rezepte hinzugefuegt oder geloescht hat.\n" ..
        "  |cff00ff00Einstellungen|r – Backup (Export/Import), Offizier-Sperre, Auto-Recalc.\n\n" ..

        "|cffff8800Synchronisation|r\n" ..
        "|cffaaaaaa-----------------------------------------------------|r\n" ..
        "Rezepte werden |cff00ff00automatisch|r zwischen allen Gildenmitgliedern synchronisiert,\n" ..
        "die das Addon installiert haben. Das passiert voellig unsichtbar ueber den\n" ..
        "Guild-Channel (kein Whisper, kein Chat).\n\n" ..
        "  |cffffd100Wann wird gesynct?|r\n" ..
        "  > Automatisch beim Login (nach ca. 8 Sekunden)\n" ..
        "  > Sofort bei jeder Aenderung (hinzufuegen/loeschen/bearbeiten)\n" ..
        "  > Manuell per |cff00ff00\"Sync Rezepte\"|r Button\n" ..
        "  > Alle 5 Minuten im Hintergrund (Fingerprint-Check)\n\n" ..

        "  |cffffd100Was passiert wenn keiner online ist?|r\n" ..
        "  Daten gehen nie verloren! Alles ist lokal gespeichert.\n" ..
        "  Sobald mehrere Spieler gleichzeitig online sind, wird automatisch abgeglichen.\n" ..
        "  |cffaaaaaa  Regel: Der neueste Zeitstempel gewinnt immer.|r\n\n" ..

        "|cffff8800Rezept-Backup|r\n" ..
        "|cffaaaaaa-----------------------------------------------------|r\n" ..
        "Unter |cff00ff00Einstellungen > Export (Backup)|r kannst du alle Rezepte als\n" ..
        "Text-String kopieren und sicher aufbewahren.\n" ..
        "Mit |cff00ff00Import (Wiederherstellen)|r laesst sich das Backup jederzeit einspielen.\n\n" ..

        "|cffff8800Befehle|r\n" ..
        "|cffaaaaaa-----------------------------------------------------|r\n" ..
        "  |cffffd100/ga|r           Hub oeffnen (App-Auswahl)\n" ..
        "  |cffffd100/ga debug on|r  Debug-Modus aktivieren\n" ..
        "  |cffffd100/ga debug off|r Debug-Modus deaktivieren\n\n" ..

        "|cff888888Made by Babushka  |  Germany's AllStar|r"
    )

    -- ScrollContent-Hoehe setzen
    scrollContent:SetScript("OnShow", function(self)
        C_Timer.After(0.01, function()
            local h = helpText:GetStringHeight()
            scrollContent:SetHeight(math.max(h + 20, 400))
        end)
    end)

    return f
end

---------------------------------------------------------------------------
-- EINSTELLUNGEN-TAB
---------------------------------------------------------------------------

function UI:CreateSettingsTab()
    local f = CreateFrame("Frame", nil, contentInset)
    f:SetPoint("TOPLEFT", 5, -5)
    f:SetPoint("BOTTOMRIGHT", -5, 5)
    f:Hide()
    settingsFrame = f

    local y = -10

    -- Checkbox: Nur Offiziere
    f.officerCB = CreateCB(f, "Nur Offiziere duerfen Rezepte aendern", function(self)
        local s = ADDON.DB:GetSettings()
        s.officerOnly = self:GetChecked() and true or false
        ADDON.DB:SaveSettings(s)
    end)
    f.officerCB:SetPoint("TOPLEFT", 12, y)
    y = y - 34

    -- Max Rang-Index
    CreateLabel(f, "GameFontNormal",
        "Max erlaubter Rang-Index (0 = GM, hoeher = niedrigerer Rang):",
        "TOPLEFT", 12, y)
    y = y - 22
    f.rankEB = CreateEB(f, 60, 24, true)
    f.rankEB:SetPoint("TOPLEFT", 12, y)
    f.rankEB:SetMaxLetters(2)
    f.rankEB:SetScript("OnEditFocusLost", function(self)
        local s = ADDON.DB:GetSettings()
        s.maxRankIndex = ADDON:SafeInt(self:GetText(), 0, 2)
        ADDON.DB:SaveSettings(s)
    end)
    f.rankEB:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    y = y - 34

    -- Checkbox: Auto-Recalc
    f.autoRecalcCB = CreateCB(f, "Automatisch neu berechnen nach Scan", function(self)
        local s = ADDON.DB:GetSettings()
        s.autoRecalcAfterScan = self:GetChecked() and true or false
        ADDON.DB:SaveSettings(s)
    end)
    f.autoRecalcCB:SetPoint("TOPLEFT", 12, y)
    y = y - 40

    -- Debug-Toggle Info
    CreateLabel(f, "GameFontNormalSmall",
        "Debug ein/aus: /gsp debug on  |  /gsp debug off",
        "TOPLEFT", 12, y)
    y = y - 30

    -- Separator
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 12, y)
    sep:SetPoint("TOPRIGHT", -12, y)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    y = y - 16

    -- Export / Import / Backup
    CreateLabel(f, "GameFontNormal", "Rezepte Backup & Teilen:", "TOPLEFT", 12, y)
    y = y - 20
    CreateLabel(f, "GameFontDisableSmall",
        "Exportiere alle Rezepte als String (Backup) oder importiere aus einem String.",
        "TOPLEFT", 12, y)
    y = y - 22

    CreateBtn(f, 160, 28, "Export (Backup)", function()
        UI:ShowExportPopup()
    end):SetPoint("TOPLEFT", 12, y)

    CreateBtn(f, 160, 28, "Import (Wiederherstellen)", function()
        UI:ShowImportPopup()
    end):SetPoint("TOPLEFT", 185, y)

    return f
end

function UI:RefreshSettingsTab()
    if not settingsFrame then return end
    local s = ADDON.DB:GetSettings()
    settingsFrame.officerCB:SetChecked(s.officerOnly)
    settingsFrame.rankEB:SetText(tostring(s.maxRankIndex or 2))
    settingsFrame.autoRecalcCB:SetChecked(s.autoRecalcAfterScan)
end

---------------------------------------------------------------------------
-- EXPORT / IMPORT POPUP
---------------------------------------------------------------------------

function UI:CreateExportImportPopup()
    eiPopup = CreateFrame("Frame", "GSPExportImportPopup", UIParent, "BackdropTemplate")
    eiPopup:SetSize(520, 400)
    eiPopup:SetPoint("CENTER")
    eiPopup:SetFrameStrata("DIALOG")
    ApplyBackdrop(eiPopup, BD_MAIN, 0.05, 0.05, 0.08, 0.98, 0.5, 0.5, 0.5)
    eiPopup:EnableMouse(true) -- Klicks blockieren
    MakeMovable(eiPopup)
    eiPopup:Hide()
    tinsert(UISpecialFrames, "GSPExportImportPopup")

    eiTitle = CreateLabel(eiPopup, "GameFontNormalLarge", "", "TOPLEFT", 16, -14)
    eiTitle:SetWidth(460)

    local cls = CreateFrame("Button", nil, eiPopup, "UIPanelCloseButton")
    cls:SetPoint("TOPRIGHT", -2, -2)

    -- Scroll + EditBox
    local sf = CreateFrame("ScrollFrame", "GSPEIScroll", eiPopup, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -44)
    sf:SetPoint("BOTTOMRIGHT", -36, 50)

    eiEditBox = CreateFrame("EditBox", "GSPEIEditBox", sf)
    eiEditBox:SetMultiLine(true)
    eiEditBox:SetAutoFocus(false)
    eiEditBox:SetFontObject(ChatFontNormal)
    eiEditBox:SetWidth(450)
    eiEditBox:SetHeight(10000) -- gross genug fuer beliebigen Text
    eiEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sf:SetScrollChild(eiEditBox)

    -- Import-Button (nur bei Import sichtbar)
    eiImportBtn = CreateBtn(eiPopup, 130, 26, "Importieren", nil)
    eiImportBtn:SetPoint("BOTTOMRIGHT", -14, 14)
    eiImportBtn:Hide()

    CreateBtn(eiPopup, 100, 26, "Schliessen", function()
        eiPopup:Hide()
    end):SetPoint("BOTTOMLEFT", 14, 14)
end

function UI:ShowExportPopup()
    local str = ADDON.ExportImport:Export()
    eiEditBox:SetText(str)
    eiTitle:SetText("Export (Strg+C zum Kopieren)")
    eiImportBtn:Hide()
    eiPopup:Show()
    eiEditBox:SetFocus()
    eiEditBox:HighlightText()
end

function UI:ShowImportPopup()
    eiEditBox:SetText("")
    eiTitle:SetText("Import (String einfuegen, dann Importieren)")
    eiImportBtn:Show()
    eiImportBtn:SetScript("OnClick", function()
        local str = eiEditBox:GetText()
        local success, result = ADDON.ExportImport:Import(str)
        if success then
            local dialog = StaticPopup_Show("GSP_CONFIRM_IMPORT")
            if dialog then dialog.data = result end
            eiPopup:Hide()
        else
            ADDON:Print("Import fehlgeschlagen: " .. tostring(result))
        end
    end)
    eiPopup:Show()
    eiEditBox:SetFocus()
end

---------------------------------------------------------------------------
-- ITEM-LINK HOOK (Shift-Klick)
---------------------------------------------------------------------------

function UI:HookItemLinks()
    local origInsertLink = ChatEdit_InsertLink
    ChatEdit_InsertLink = function(text)
        if ADDON.UI and ADDON.UI.itemLinkEBs then
            for _, eb in ipairs(ADDON.UI.itemLinkEBs) do
                if eb:IsVisible() and eb:HasFocus() then
                    eb:SetText(text)
                    return true
                end
            end
        end
        if origInsertLink then
            return origInsertLink(text)
        end
    end
end

---------------------------------------------------------------------------
-- GET_ITEM_INFO_RECEIVED – aktualisiert Anzeige nach Cache-Load
---------------------------------------------------------------------------

function UI:RegisterItemInfoEvent()
    local pending = false
    local infoFrame = CreateFrame("Frame")
    infoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    infoFrame:SetScript("OnEvent", function()
        if not mainFrame or not mainFrame:IsShown() then return end
        if pending then return end
        pending = true
        C_Timer.After(0.3, function()
            pending = false
            if not mainFrame:IsShown() then return end
            if UI.activeTab == 1 then
                UI:RefreshRecipeList()
            elseif UI.activeTab == 2 then
                UI:RefreshFarmTab()
            elseif UI.activeTab == 3 then
                UI:RefreshStockTab()
            elseif UI.activeTab == 4 then
                UI:RefreshLogTab()
            end
        end)
    end)
end
