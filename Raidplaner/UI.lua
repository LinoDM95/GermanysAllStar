---------------------------------------------------------------------------
-- Raidplaner – UI.lua
-- Kalender-Monatsansicht, Create/Edit Dialog, Detail+Roster-View
-- Nur Standard-FrameXML, keine externen Libs.
---------------------------------------------------------------------------
local _, ADDON = ...

ADDON.Raidplaner = {}
local RP = ADDON.Raidplaner

---------------------------------------------------------------------------
-- Layout-Konstanten
---------------------------------------------------------------------------
local MAIN_W, MAIN_H = 860, 620
local INSET_PAD       = 10
local GRID_COLS       = 7
local GRID_ROWS       = 6
local HEADER_H        = 22
local MAX_ENTRIES     = 3   -- Max angezeigte Raids pro Tageskachel

local WEEKDAYS    = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" }
local MONTH_NAMES = {
    "Januar", "Februar", "Maerz", "April", "Mai", "Juni",
    "Juli", "August", "September", "Oktober", "November", "Dezember",
}

local STATUS_ORDER  = { YES = 1, MAYBE = 2, BENCH = 3, NO = 4 }
local STATUS_COLOR  = { YES = "00cc00", MAYBE = "ffaa00", NO = "ff4444", BENCH = "8888ff" }
local STATUS_LABEL  = { YES = "Dabei", MAYBE = "Vielleicht", NO = "Abwesend", BENCH = "Reserve" }

local LOGO_TEX = "Interface\\AddOns\\GermanysAllStar\\Textures\\logo"

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
local BD_CELL = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 8,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

---------------------------------------------------------------------------
-- Forwarded locals
---------------------------------------------------------------------------
local rpFrame, contentInset, calendarContent
local monthLabel
local dayCells = {}
local currentYear, currentMonth
-- Dialog + Detail als oeffentliche Refs (fuer Sync-Refresh)
RP.detailFrame = nil

---------------------------------------------------------------------------
-- Kleine Helfer
---------------------------------------------------------------------------

local function ApplyBackdrop(frame, bd, r, g, b, a, er, eg, eb, ea)
    frame:SetBackdrop(bd)
    frame:SetBackdropColor(r or 0.05, g or 0.05, b or 0.08, a or 0.95)
    if er then frame:SetBackdropBorderColor(er, eg, eb, ea or 1) end
end

local function MakeMovable(frame)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
end

local function CreateLabel(parent, fontObj, text, ...)
    local fs = parent:CreateFontString(nil, "OVERLAY", fontObj or "GameFontNormal")
    if text then fs:SetText(text) end
    if select("#", ...) > 0 then fs:SetPoint(...) end
    return fs
end

local function CreateBtn(parent, w, h, text, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w, h)
    btn:SetText(text)
    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end

local function CreateEB(parent, w, h)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(w, h)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    eb:SetScript("OnEnterPressed",  function(s) s:ClearFocus() end)
    return eb
end

---------------------------------------------------------------------------
-- Kalender-Mathematik
---------------------------------------------------------------------------

local function DaysInMonth(y, m)
    -- day=0 des Folgemonats = letzter Tag des aktuellen Monats
    return tonumber(date("%d", time({ year = y, month = m + 1, day = 0, hour = 12 })))
end

local function FirstWeekday(y, m)
    -- date(%w): 0=So, 1=Mo ... 6=Sa → umrechnen auf Mo=1 ... So=7
    local w = tonumber(date("%w", time({ year = y, month = m, day = 1, hour = 12 })))
    return w == 0 and 7 or w
end

local function DateStr(y, m, d)
    return string.format("%04d-%02d-%02d", y, m, d)
end

local function InitMonth()
    local now   = date("*t")
    currentYear  = now.year
    currentMonth = now.month
end

---------------------------------------------------------------------------
-- Permission
---------------------------------------------------------------------------

--- Gildenmeister (0) + Gildenmeister (1) + Raidlead (2) duerfen Raids verwalten.
function RP:CanManageRaids()
    local _, _, _, rankIndex = ADDON:GetGuildInfo()
    if rankIndex == nil then return false end
    return rankIndex <= 2
end

---------------------------------------------------------------------------
-- Tageskachel erzeugen
---------------------------------------------------------------------------

local function CreateDayCell(idx, parent, cellW, cellH)
    local row = math.floor((idx - 1) / GRID_COLS)
    local col = (idx - 1) % GRID_COLS

    local cell = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    cell:SetSize(cellW, cellH)
    cell:SetPoint("TOPLEFT", col * cellW, -(HEADER_H + row * cellH))
    cell:SetBackdrop(BD_CELL)
    cell:SetBackdropColor(0.08, 0.08, 0.12, 0.6)
    cell:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.3)

    -- Tageszahl
    cell.dayLabel = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cell.dayLabel:SetPoint("TOPLEFT", 4, -2)

    -- "+" Button (nur fuer GM/Raidleiter sichtbar)
    cell.addBtn = CreateFrame("Button", nil, cell)
    cell.addBtn:SetSize(16, 16)
    cell.addBtn:SetPoint("TOPRIGHT", -2, -1)
    cell.addBtn.text = cell.addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cell.addBtn.text:SetPoint("CENTER")
    cell.addBtn.text:SetText("|cff00cc00+|r")
    cell.addBtn:SetScript("OnEnter", function(self)
        self.text:SetText("|cff44ff44+|r")
    end)
    cell.addBtn:SetScript("OnLeave", function(self)
        self.text:SetText("|cff00cc00+|r")
    end)
    cell.addBtn:Hide()

    -- Raid-Eintraege
    cell.entries = {}
    for i = 1, MAX_ENTRIES do
        local e = CreateFrame("Button", nil, cell)
        e:SetSize(cellW - 6, 14)
        e:SetPoint("TOPLEFT", 3, -(16 + (i - 1) * 15))
        e.text = e:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        e.text:SetPoint("LEFT", 1, 0)
        e.text:SetWidth(cellW - 10)
        e.text:SetJustifyH("LEFT")
        local hl = e:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.10)
        e:Hide()
        cell.entries[i] = e
    end

    -- "...mehr" Label
    cell.moreLabel = cell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cell.moreLabel:SetPoint("BOTTOMRIGHT", -4, 2)
    cell.moreLabel:Hide()

    cell.dateStr        = nil
    cell.isCurrentMonth = false
    return cell
end

---------------------------------------------------------------------------
-- Kalender auffrischen
---------------------------------------------------------------------------

function RP:RefreshCalendar()
    if not calendarContent then return end

    local daysInMonth = DaysInMonth(currentYear, currentMonth)
    local firstDay    = FirstWeekday(currentYear, currentMonth) -- Mo=1..So=7

    local prevM = currentMonth == 1  and 12 or currentMonth - 1
    local prevY = currentMonth == 1  and currentYear - 1 or currentYear
    local daysInPrev = DaysInMonth(prevY, prevM)

    local canManage = self:CanManageRaids()
    local today     = date("%Y-%m-%d")
    local raidIdx   = ADDON.RaidplanerDB:BuildDateIndex()

    monthLabel:SetText("|cffffd100" .. MONTH_NAMES[currentMonth]
        .. " " .. currentYear .. "|r")

    for i = 1, GRID_COLS * GRID_ROWS do
        local cell      = dayCells[i]
        local dayOffset = i - firstDay + 1
        local y, m, d
        local isCurrent = true

        if dayOffset < 1 then
            d = daysInPrev + dayOffset
            m = prevM
            y = prevY
            isCurrent = false
        elseif dayOffset > daysInMonth then
            d = dayOffset - daysInMonth
            m = currentMonth == 12 and 1 or currentMonth + 1
            y = currentMonth == 12 and currentYear + 1 or currentYear
            isCurrent = false
        else
            d = dayOffset; m = currentMonth; y = currentYear
        end

        cell.dateStr        = DateStr(y, m, d)
        cell.isCurrentMonth = isCurrent

        -- Styling
        if cell.dateStr == today then
            cell.dayLabel:SetText("|cff44ff44" .. d .. "|r")
            cell:SetBackdropColor(0.08, 0.14, 0.08, 0.85)
            cell:SetBackdropBorderColor(0.2, 0.6, 0.2, 0.6)
        elseif isCurrent then
            cell.dayLabel:SetText("|cffffffff" .. d .. "|r")
            cell:SetBackdropColor(0.08, 0.08, 0.12, 0.6)
            cell:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.3)
        else
            cell.dayLabel:SetText("|cff555555" .. d .. "|r")
            cell:SetBackdropColor(0.05, 0.05, 0.08, 0.4)
            cell:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.2)
        end

        -- Weekend spalten leicht einfaerben
        local col = (i - 1) % GRID_COLS
        if col >= 5 and isCurrent then -- Sa/So
            cell:SetBackdropColor(0.10, 0.08, 0.06, 0.65)
        end

        -- "+" Button
        if canManage and isCurrent then
            cell.addBtn:Show()
            local ds = cell.dateStr
            cell.addBtn:SetScript("OnClick", function() RP:OpenCreateRaid(ds) end)
        else
            cell.addBtn:Hide()
        end

        -- Raid-Eintraege
        local raids = raidIdx[cell.dateStr] or {}
        for j = 1, MAX_ENTRIES do
            local entry = cell.entries[j]
            if j <= #raids then
                local r   = raids[j]
                local def = ADDON.RaidData:GetByKey(r.raidKey)
                local sh  = def and def.short or r.raidKey
                local sz  = r.size or (def and def.size) or ""

                -- Status / Farbe bestimmen
                local baseText = (r.time or "?") .. " " .. sh .. " (" .. sz .. ")"
                local color    = "ffffd100" -- Standard: gelb (geplant)

                -- Vergangene Raids: grau
                local isPast = false
                if r.date and r.date ~= "" and r.date < today then
                    isPast = true
                end

                -- Kader-Belegung (YES + bestätigt)
                local confirmedYes = 0
                if r.signups then
                    for _, s in pairs(r.signups) do
                        local isConfirmed = s.confirmed
                        if isConfirmed == nil then
                            isConfirmed = (s.status == "YES" or s.status == "BENCH")
                        end
                        if isConfirmed and s.status == "YES" then
                            confirmedYes = confirmedYes + 1
                        end
                    end
                end
                local isFull = (r.size and confirmedYes >= (r.size or 0))

                local state = r.state or "PLANNED"
                if isPast then
                    color = "777777"
                elseif state == "CANCELLED" then
                    color    = "ff4444"
                    baseText = "~~" .. baseText .. "~~" -- pseudo-durchgestrichen
                elseif state == "CONFIRMED" or isFull then
                    color = "44ff44"
                end

                entry.text:SetText("|cff" .. color .. baseText .. "|r")
                entry.raidId = r.id
                entry:SetScript("OnClick", function() RP:ShowRaidDetail(r.id) end)
                -- Tooltip
                entry:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    local signupCount = 0
                    if r.signups then for _ in pairs(r.signups) do signupCount = signupCount + 1 end end
                    GameTooltip:AddLine((def and def.name or r.raidKey) .. " (" .. sz .. ")", 1, 0.82, 0)
                    GameTooltip:AddLine(r.date .. " um " .. (r.time or "?") .. " Uhr", 1, 1, 1)
                    if r.note and r.note ~= "" then
                        GameTooltip:AddLine(r.note, 0.7, 0.7, 0.7, true)
                    end
                    GameTooltip:AddLine(signupCount .. " Anmeldungen", 0.5, 0.8, 1)
                    GameTooltip:Show()
                end)
                entry:SetScript("OnLeave", function() GameTooltip:Hide() end)
                entry:Show()
            else
                entry:Hide()
            end
        end

        if #raids > MAX_ENTRIES then
            cell.moreLabel:SetText("|cffaaaaaa+" .. (#raids - MAX_ENTRIES) .. " mehr|r")
            cell.moreLabel:Show()
        else
            cell.moreLabel:Hide()
        end

        cell:Show()
    end
end

---------------------------------------------------------------------------
-- Create/Edit Raid Dialog
---------------------------------------------------------------------------
local createFrame

local function InitDropdown()
    if not createFrame or not createFrame.raidDD then return end
    UIDropDownMenu_Initialize(createFrame.raidDD, function(_, level)
        for _, r in ipairs(ADDON.RaidData.raids) do
            local info   = UIDropDownMenu_CreateInfo()
            info.text    = r.name .. "  (" .. r.size .. ")"
            info.value   = r.key
            info.func    = function(btn)
                createFrame.selectedKey = btn.value
                UIDropDownMenu_SetText(createFrame.raidDD, btn:GetText())
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

local function EnsureCreateDialog()
    if createFrame then return end

    createFrame = CreateFrame("Frame", "GASRPCreateFrame", UIParent, "BackdropTemplate")
    createFrame:SetSize(420, 300)
    createFrame:SetPoint("CENTER")
    createFrame:SetFrameStrata("TOOLTIP")
    ApplyBackdrop(createFrame, BD_MAIN, 0.05, 0.05, 0.08, 0.97, 0.6, 0.5, 0.2)
    MakeMovable(createFrame)
    createFrame:Hide()

    createFrame.title = CreateLabel(createFrame, "GameFontNormalLarge", "", "TOPLEFT", 16, -14)
    local cb = CreateFrame("Button", nil, createFrame, "UIPanelCloseButton")
    cb:SetPoint("TOPRIGHT", -2, -2)

    -- Raid Dropdown
    CreateLabel(createFrame, "GameFontNormalSmall", "Raid:", "TOPLEFT", 16, -48)
    createFrame.raidDD = CreateFrame("Frame", "GASRPRaidDD", createFrame, "UIDropDownMenuTemplate")
    createFrame.raidDD:SetPoint("TOPLEFT", 56, -42)
    UIDropDownMenu_SetWidth(createFrame.raidDD, 280)

    -- Datum
    CreateLabel(createFrame, "GameFontNormalSmall", "Datum:", "TOPLEFT", 16, -84)
    createFrame.dateEB = CreateEB(createFrame, 120, 22)
    createFrame.dateEB:SetPoint("TOPLEFT", 80, -80)

    -- Uhrzeit von / bis
    CreateLabel(createFrame, "GameFontNormalSmall", "Von:", "TOPLEFT", 220, -84)
    createFrame.timeFromEB = CreateEB(createFrame, 60, 22)
    createFrame.timeFromEB:SetPoint("TOPLEFT", 250, -80)

    CreateLabel(createFrame, "GameFontNormalSmall", "Bis:", "TOPLEFT", 320, -84)
    createFrame.timeToEB = CreateEB(createFrame, 60, 22)
    createFrame.timeToEB:SetPoint("TOPLEFT", 350, -80)

    -- Notiz
    CreateLabel(createFrame, "GameFontNormalSmall", "Notiz:", "TOPLEFT", 16, -118)
    createFrame.noteEB = CreateEB(createFrame, 310, 22)
    createFrame.noteEB:SetPoint("TOPLEFT", 80, -114)
    createFrame.noteEB:SetMaxLetters(180)

    -- Fehler-/Info-Label
    createFrame.infoLabel = CreateLabel(createFrame, "GameFontHighlightSmall", "", "TOPLEFT", 16, -150)
    createFrame.infoLabel:SetWidth(380)

    -- Speichern
    createFrame.saveBtn = CreateBtn(createFrame, 120, 26, "Speichern", function()
        RP:SaveRaidFromDialog()
    end)
    createFrame.saveBtn:SetPoint("BOTTOMLEFT", 16, 14)

    -- Abbrechen
    CreateBtn(createFrame, 100, 26, "Abbrechen", function()
        createFrame:Hide()
    end):SetPoint("LEFT", createFrame.saveBtn, "RIGHT", 8, 0)

    createFrame.editingRaidId = nil
    createFrame.selectedKey   = nil
end

function RP:OpenCreateRaid(dateStr)
    EnsureCreateDialog()
    createFrame.editingRaidId = nil
    createFrame.title:SetText("|cffffd100Raid ansetzen|r")
    createFrame.dateEB:SetText(dateStr or date("%Y-%m-%d"))
    createFrame.timeFromEB:SetText("20:00")
    createFrame.timeToEB:SetText("23:00")
    createFrame.noteEB:SetText("")
    createFrame.infoLabel:SetText("")
    createFrame.selectedKey = ADDON.RaidData.raids[1].key
    InitDropdown()
    local def = ADDON.RaidData:GetByKey(createFrame.selectedKey)
    UIDropDownMenu_SetText(createFrame.raidDD, def.name .. "  (" .. def.size .. ")")
    createFrame:SetFrameStrata("TOOLTIP")
    createFrame:Raise()
    createFrame:Show()
end

function RP:OpenEditRaid(raidId)
    if not self:CanManageRaids() then
        ADDON:Print("Nur GM und Raidleiter können Raids bearbeiten.")
        return
    end
    local raid = ADDON.RaidplanerDB:GetRaid(raidId)
    if not raid then return end
    EnsureCreateDialog()
    createFrame.editingRaidId = raidId
    createFrame.title:SetText("|cffffd100Raid bearbeiten|r")
    createFrame.dateEB:SetText(raid.date or "")
    local tFrom, tTo = nil, nil
    if raid.time and type(raid.time) == "string" then
        tFrom, tTo = raid.time:match("^(%d%d:%d%d)%-(%d%d:%d%d)$")
    end
    createFrame.timeFromEB:SetText(tFrom or raid.time or "20:00")
    createFrame.timeToEB:SetText(tTo or "23:00")
    createFrame.noteEB:SetText(raid.note or "")
    createFrame.infoLabel:SetText("")
    createFrame.selectedKey = raid.raidKey
    InitDropdown()
    local def = ADDON.RaidData:GetByKey(raid.raidKey)
    if def then
        UIDropDownMenu_SetText(createFrame.raidDD, def.name .. "  (" .. def.size .. ")")
    end
    createFrame:SetFrameStrata("TOOLTIP")
    createFrame:Raise()
    createFrame:Show()
end

function RP:SaveRaidFromDialog()
    if not createFrame then return end
    local key = createFrame.selectedKey
    if not key then
        createFrame.infoLabel:SetText("|cffff4444Bitte waehle einen Raid.|r")
        return
    end
    local dateStr = strtrim(createFrame.dateEB:GetText())
    if not dateStr:match("^%d%d%d%d%-%d%d%-%d%d$") then
        createFrame.infoLabel:SetText("|cffff4444Datum im Format YYYY-MM-DD.|r")
        return
    end
    local tFrom = strtrim(createFrame.timeFromEB:GetText() or "")
    local tTo   = strtrim(createFrame.timeToEB:GetText() or "")
    if not tFrom:match("^%d%d:%d%d$") or not tTo:match("^%d%d:%d%d$") then
        createFrame.infoLabel:SetText("|cffff4444Uhrzeit im Format HH:MM (von/bis).|r")
        return
    end

    local timeStr = tFrom .. "-" .. tTo
    local note = strtrim(createFrame.noteEB:GetText())
    local def  = ADDON.RaidData:GetByKey(key)
    local now  = time()
    local raid

    if createFrame.editingRaidId then
        raid = ADDON.RaidplanerDB:GetRaid(createFrame.editingRaidId)
        if raid then
            raid.raidKey   = key
            raid.raidName  = def and def.name or key
            raid.size      = def and def.size or 25
            raid.date      = dateStr
            raid.time      = timeStr
            raid.note      = note
            raid.updatedAt = now
            raid.state     = raid.state or "PLANNED"
        end
    else
        raid = {
            id         = ADDON.RaidplanerDB:GenerateId(),
            raidKey    = key,
            raidName   = def and def.name or key,
            size       = def and def.size or 25,
            date       = dateStr,
            time       = timeStr,
            note       = note,
            createdBy  = UnitName("player") or "?",
            createdAt  = now,
            updatedAt  = now,
            state      = "PLANNED",
            signups    = {},
        }
    end
    if not raid then return end

    ADDON.RaidplanerDB:SaveRaid(raid)
    ADDON.RaidplanerSync:BroadcastRaid(raid)
    ADDON:Print("Raid gespeichert: " .. (raid.raidName or "?") .. " am " .. dateStr)
    createFrame:Hide()
    self:RefreshCalendar()
end

---------------------------------------------------------------------------
-- Kommentar-Popup (klickbar zum Anzeigen des vollen Textes)
---------------------------------------------------------------------------
local commentPopup

local function ShowCommentPopup(playerName, comment)
    if not commentPopup then
        commentPopup = CreateFrame("Frame", "GASRPCommentPopup", UIParent, "BackdropTemplate")
        commentPopup:SetSize(320, 160)
        commentPopup:SetPoint("CENTER")
        commentPopup:SetFrameStrata("TOOLTIP")
        ApplyBackdrop(commentPopup, BD_MAIN, 0.06, 0.06, 0.1, 0.97, 0.5, 0.4, 0.2)
        MakeMovable(commentPopup)

        local closeCB = CreateFrame("Button", nil, commentPopup, "UIPanelCloseButton")
        closeCB:SetPoint("TOPRIGHT", -2, -2)

        commentPopup.title = CreateLabel(commentPopup, "GameFontNormal", "", "TOPLEFT", 14, -14)
        commentPopup.title:SetWidth(260)

        commentPopup.body = CreateLabel(commentPopup, "GameFontHighlightSmall", "", "TOPLEFT", 14, -38)
        commentPopup.body:SetWidth(290)
        commentPopup.body:SetJustifyH("LEFT")
        commentPopup.body:SetWordWrap(true)
    end
    commentPopup.title:SetText("|cffffd100Kommentar von " .. (playerName or "?") .. "|r")
    commentPopup.body:SetText("|cffffffff" .. (comment or "") .. "|r")
    commentPopup:Show()
end

---------------------------------------------------------------------------
-- Raid-Detail + Anmeldung + Roster
---------------------------------------------------------------------------
local requestRows = {}
local rosterRows  = {}

local DETAIL_W, DETAIL_H = 1100, 700
local ROSTER_ROW_H = 22

local function GetOrCreateRequestRow(index, parent)
    if requestRows[index] then return requestRows[index] end

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROSTER_ROW_H)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", 4, 0)
    row.nameText:SetWidth(110)
    row.nameText:SetJustifyH("LEFT")

    row.roleText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.roleText:SetPoint("LEFT", 118, 0)
    row.roleText:SetWidth(70)
    row.roleText:SetJustifyH("LEFT")

    row.specText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.specText:SetPoint("LEFT", 192, 0)
    row.specText:SetWidth(90)
    row.specText:SetJustifyH("LEFT")

    row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.statusText:SetPoint("LEFT", 286, 0)
    row.statusText:SetWidth(60)
    row.statusText:SetJustifyH("LEFT")

    -- Kommentar-Vorschau (klickbar wie rechts)
    row.commentBtn = CreateFrame("Button", nil, row)
    row.commentBtn:SetPoint("LEFT", 348, 0)
    row.commentBtn:SetSize(80, ROSTER_ROW_H)
    row.commentBtn.text = row.commentBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.commentBtn.text:SetPoint("LEFT", 0, 0)
    row.commentBtn.text:SetWidth(76)
    row.commentBtn.text:SetJustifyH("LEFT")
    local hl1 = row.commentBtn:CreateTexture(nil, "HIGHLIGHT")
    hl1:SetAllPoints()
    hl1:SetColorTexture(1, 1, 1, 0.06)

    -- Buttons fuer Raidlead: in Kader / Reserve
    row.mainBtn = CreateBtn(row, 24, 18, ">>", nil)
    row.mainBtn:SetPoint("RIGHT", -28, 0)
    row.mainBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("In Kader (Dabei)", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    row.mainBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.reserveBtn = CreateBtn(row, 24, 18, "R", nil)
    row.reserveBtn:SetPoint("RIGHT", -2, 0)
    row.reserveBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Als Reserve", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    row.reserveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    requestRows[index] = row
    return row
end

local function GetOrCreateRosterRow(index, parent)
    if rosterRows[index] then return rosterRows[index] end

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROSTER_ROW_H)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)

    -- Header-Modus (Rollen-Titel)
    row.headerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.headerText:SetPoint("LEFT", 6, 0)
    row.headerText:SetWidth(470)
    row.headerText:SetJustifyH("LEFT")

    -- Daten-Modus
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", 10, 0)
    row.nameText:SetWidth(120)
    row.nameText:SetJustifyH("LEFT")

    row.specText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.specText:SetPoint("LEFT", 135, 0)
    row.specText:SetWidth(100)
    row.specText:SetJustifyH("LEFT")

    row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.statusText:SetPoint("LEFT", 240, 0)
    row.statusText:SetWidth(80)
    row.statusText:SetJustifyH("LEFT")

    -- Kommentar als klickbarer Button
    row.commentBtn = CreateFrame("Button", nil, row)
    row.commentBtn:SetPoint("LEFT", 325, 0)
    row.commentBtn:SetSize(120, ROSTER_ROW_H)
    row.commentBtn.text = row.commentBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.commentBtn.text:SetPoint("LEFT", 0, 0)
    row.commentBtn.text:SetWidth(116)
    row.commentBtn.text:SetJustifyH("LEFT")
    local hl = row.commentBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    -- Button zum Zurueckschieben in die Anmeldungen (nur fuer Raidlead/GM)
    row.backBtn = CreateBtn(row, 24, 18, "<<", nil)
    row.backBtn:SetPoint("RIGHT", -2, 0)

    rosterRows[index] = row
    return row
end

local function ConfigureAsHeader(row, text, color, yPos)
    row:ClearAllPoints()
    local parent = row:GetParent() or row
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yPos)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yPos)
    row.bg:SetColorTexture(0.15, 0.15, 0.2, 0.5)
    row.headerText:SetText("|cff" .. color .. text .. "|r")
    row.headerText:Show()
    row.nameText:Hide()
    row.specText:Hide()
    row.statusText:Hide()
    row.commentBtn:Hide()
    if row.backBtn then row.backBtn:Hide() end
    row:Show()
end

local function ConfigureAsData(row, signup, yPos, even)
    row:ClearAllPoints()
    local parent = row:GetParent() or row
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yPos)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yPos)
    row.bg:SetColorTexture(1, 1, 1, even and 0.03 or 0)
    row.headerText:Hide()

    -- Name mit Klassenfarbe
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[signup.class]
    if cc then
        row.nameText:SetText(string.format("|cff%02x%02x%02x%s|r",
            cc.r * 255, cc.g * 255, cc.b * 255, signup.name))
    else
        row.nameText:SetText(signup.name or "?")
    end
    row.nameText:Show()

    -- Spec
    local specInfo = ADDON.RaidData:GetSpecInfo(signup.class, signup.spec or "")
    local specName = specInfo and specInfo.name or (signup.spec or "?")
    row.specText:SetText("|cffbbbbbb" .. specName .. "|r")
    row.specText:Show()

    -- Status
    local c = STATUS_COLOR[signup.status] or "ffffff"
    local n = STATUS_LABEL[signup.status] or signup.status
    row.statusText:SetText("|cff" .. c .. n .. "|r")
    row.statusText:Show()

    -- Kommentar (klickbar)
    local comment = signup.comment or ""
    if comment ~= "" then
        local short = (string.len(comment) > 18)
            and (string.sub(comment, 1, 16) .. "..") or comment
        row.commentBtn.text:SetText("|cff888888" .. short .. "|r")
        local pName = signup.name or "?"
        row.commentBtn:SetScript("OnClick", function()
            ShowCommentPopup(pName, comment)
        end)
        row.commentBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Kommentar anzeigen", 1, 0.82, 0)
            GameTooltip:AddLine(comment, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row.commentBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.commentBtn:Show()
    else
        row.commentBtn.text:SetText("")
        row.commentBtn:Hide()
    end

    row:Show()
end

local function EnsureDetailView()
    if RP.detailFrame then return end

    local df = CreateFrame("Frame", "GASRPDetailFrame", UIParent, "BackdropTemplate")
    df:SetSize(DETAIL_W, DETAIL_H)
    df:SetPoint("CENTER", 220, 0)
    df:SetFrameStrata("DIALOG")
    ApplyBackdrop(df, BD_MAIN, 0.05, 0.05, 0.08, 0.97, 0.5, 0.4, 0.15)
    MakeMovable(df)
    df:Hide()
    RP.detailFrame = df

    local cb = CreateFrame("Button", nil, df, "UIPanelCloseButton")
    cb:SetPoint("TOPRIGHT", -2, -2)

    -- Header
    df.titleLabel   = CreateLabel(df, "GameFontNormalLarge", "", "TOPLEFT", 16, -14)
    df.dateLabel    = CreateLabel(df, "GameFontHighlightSmall", "", "TOPLEFT", 16, -38)
    df.noteLabel    = CreateLabel(df, "GameFontHighlightSmall", "", "TOPLEFT", 16, -54)
    df.noteLabel:SetWidth(DETAIL_W - 40)
    df.creatorLabel = CreateLabel(df, "GameFontDisableSmall", "", "TOPLEFT", 16, -70)

    -- Raid-Status-Anzeige (z.B. Geplant, Bestätigt, Abgesagt)
    df.stateLabel = CreateLabel(df, "GameFontHighlightSmall", "", "TOPRIGHT", -16, -38)

    -- Spec-Dropdown
    CreateLabel(df, "GameFontNormalSmall", "Spec:", "TOPLEFT", 16, -96)
    df.specDD = CreateFrame("Frame", "GASRPSpecDD", df, "UIDropDownMenuTemplate")
    df.specDD:SetPoint("TOPLEFT", 48, -90)
    UIDropDownMenu_SetWidth(df.specDD, 150)
    df.selectedSpec = nil
    df.selectedRole = nil

    -- Signup-Buttons
    local btnY = -124
    df.yesBtn   = CreateBtn(df, 78, 24, "Dabei",      function() RP:HandleSignup("YES")   end)
    df.yesBtn:SetPoint("TOPLEFT", 16, btnY)
    df.maybeBtn = CreateBtn(df, 78, 24, "Vielleicht", function() RP:HandleSignup("MAYBE") end)
    df.maybeBtn:SetPoint("LEFT", df.yesBtn, "RIGHT", 4, 0)
    df.noBtn    = CreateBtn(df, 78, 24, "Abwesend",   function() RP:HandleSignup("NO")    end)
    df.noBtn:SetPoint("LEFT", df.maybeBtn, "RIGHT", 4, 0)
    df.benchBtn = CreateBtn(df, 78, 24, "Reserve",    function() RP:HandleSignup("BENCH") end)
    df.benchBtn:SetPoint("LEFT", df.noBtn, "RIGHT", 4, 0)

    -- Kommentar
    CreateLabel(df, "GameFontDisableSmall", "Kommentar:", "TOPLEFT", 16, -154)
    df.commentEB = CreateEB(df, 340, 22)
    df.commentEB:SetPoint("TOPLEFT", 94, -151)
    df.commentEB:SetMaxLetters(80)

    -- Mein Status
    df.myStatusLabel = CreateLabel(df, "GameFontNormal", "", "TOPLEFT", 16, -180)

    -- Separator
    local sep = df:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 10, -198)
    sep:SetPoint("TOPRIGHT", -10, -198)
    sep:SetColorTexture(0.5, 0.4, 0.15, 0.5)

    -- Kopfzeile fuer Anmeldungen (links) und Kader (rechts)
    CreateLabel(df, "GameFontHighlightSmall", "Anmeldungen", "TOPLEFT", 16, -206)
    CreateLabel(df, "GameFontHighlightSmall", "Bestätigter Kader", "TOPLEFT", DETAIL_W / 2 + 6, -206)
    df.rosterCountLabel = CreateLabel(df, "GameFontHighlightSmall", "", "TOPLEFT", DETAIL_W / 2 + 6, -220)

    -- Rollen-Zusammenfassung (unterhalb Kader-Kopf)
    df.roleSummary = CreateLabel(df, "GameFontDisableSmall", "", "TOPLEFT", DETAIL_W / 2 + 6, -234)
    df.roleSummary:SetWidth(DETAIL_W / 2 - 20)

    -- ScrollFrame: Anmeldungen (links)
    df.reqSF = CreateFrame("ScrollFrame", "GASRPRequestSF", df, "UIPanelScrollFrameTemplate")
    -- Linker Spaltenkopf fuer Anmeldungen
    local reqColY = -222
    CreateLabel(df, "GameFontDisableSmall", "Name",      "TOPLEFT", 16,  reqColY)
    CreateLabel(df, "GameFontDisableSmall", "Rolle",     "TOPLEFT", 136, reqColY)
    CreateLabel(df, "GameFontDisableSmall", "Spec",      "TOPLEFT", 206, reqColY)
    CreateLabel(df, "GameFontDisableSmall", "Status",    "TOPLEFT", 296, reqColY)
    CreateLabel(df, "GameFontDisableSmall", "Kommentar", "TOPLEFT", 370, reqColY)

    df.reqSF:SetPoint("TOPLEFT", 10, -236)
    df.reqSF:SetPoint("BOTTOMLEFT", 10, 50)
    df.reqSF:SetWidth(DETAIL_W / 2 - 24)
    df.reqContent = CreateFrame("Frame", nil, df.reqSF)
    df.reqContent:SetPoint("TOPLEFT", 0, 0)
    df.reqContent:SetWidth(DETAIL_W / 2 - 40)
    df.reqContent:SetHeight(1)
    df.reqSF:SetScrollChild(df.reqContent)

    -- Roster ScrollFrame (rechts) – beginnt auf gleicher Hoehe wie Anmeldungen
    df.rosterSF = CreateFrame("ScrollFrame", "GASRPRosterSF", df, "UIPanelScrollFrameTemplate")
    df.rosterSF:SetPoint("TOPRIGHT", -10, -236)
    df.rosterSF:SetPoint("BOTTOMRIGHT", -10, 50)
    df.rosterSF:SetWidth(DETAIL_W / 2 - 24)
    df.rosterContent = CreateFrame("Frame", nil, df.rosterSF)
    df.rosterContent:SetPoint("TOPLEFT", 0, 0)
    df.rosterContent:SetWidth(DETAIL_W / 2 - 40)
    df.rosterContent:SetHeight(1)
    df.rosterSF:SetScrollChild(df.rosterContent)

    -- Edit / Delete (nur fuer Berechtigte)
    df.editBtn = CreateBtn(df, 100, 24, "Bearbeiten", function()
        if df.currentRaidId then RP:OpenEditRaid(df.currentRaidId) end
    end)
    df.editBtn:SetPoint("BOTTOMLEFT", 16, 14)

    df.deleteBtn = CreateBtn(df, 100, 24, "|cffff4444Loeschen|r", function()
        if df.currentRaidId then RP:ConfirmDeleteRaid(df.currentRaidId) end
    end)
    df.deleteBtn:SetPoint("LEFT", df.editBtn, "RIGHT", 8, 0)

    -- Raid bestaetigen / absagen (nur fuer GM / Raidlead sichtbar)
    df.confirmRaidBtn = CreateBtn(df, 120, 24, "Raid bestätigen", function()
        if df.currentRaidId then RP:SetRaidState(df.currentRaidId, "CONFIRMED", true) end
    end)
    df.confirmRaidBtn:SetPoint("BOTTOMRIGHT", -150, 14)

    df.cancelRaidBtn = CreateBtn(df, 120, 24, "|cffff4444Raid absagen|r", function()
        if df.currentRaidId then RP:SetRaidState(df.currentRaidId, "CANCELLED", true) end
    end)
    df.cancelRaidBtn:SetPoint("LEFT", df.confirmRaidBtn, "RIGHT", 8, 0)

    df.currentRaidId = nil
end

local function InitSpecDropdown(df, classToken, selectedSpec)
    UIDropDownMenu_Initialize(df.specDD, function(_, level)
        local specs = ADDON.RaidData:GetSpecsForClass(classToken)
        for _, s in ipairs(specs) do
            local info     = UIDropDownMenu_CreateInfo()
            local roleInfo = ADDON.RaidData:GetRoleInfo(s.role)
            local roleCol  = roleInfo and roleInfo.color or "cccccc"
            info.text      = s.name .. "  |cff" .. roleCol .. "(" .. (roleInfo and roleInfo.name or s.role) .. ")|r"
            info.value     = s.key
            info.func      = function(btn)
                df.selectedSpec = btn.value
                df.selectedRole = s.role
                UIDropDownMenu_SetText(df.specDD, s.name)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    if selectedSpec and selectedSpec ~= "" then
        local specInfo = ADDON.RaidData:GetSpecInfo(classToken, selectedSpec)
        UIDropDownMenu_SetText(df.specDD, specInfo and specInfo.name or selectedSpec)
        df.selectedSpec = selectedSpec
        df.selectedRole = specInfo and specInfo.role or ""
    else
        local specs = ADDON.RaidData:GetSpecsForClass(classToken)
        if specs[1] then
            df.selectedSpec = specs[1].key
            df.selectedRole = specs[1].role
            UIDropDownMenu_SetText(df.specDD, specs[1].name)
        end
    end
end

function RP:ShowRaidDetail(raidId)
    local raid = ADDON.RaidplanerDB:GetRaid(raidId)
    if not raid then
        ADDON:Print("Raid nicht gefunden.")
        return
    end
    EnsureDetailView()
    local df = self.detailFrame
    df.currentRaidId = raidId

    local def = ADDON.RaidData:GetByKey(raid.raidKey)
    df.titleLabel:SetText("|cffffd100" .. (raid.raidName or "?")
        .. " (" .. (raid.size or "?") .. ")|r")
    local tFrom, tTo = nil, nil
    if raid.time and type(raid.time) == "string" then
        tFrom, tTo = raid.time:match("^(%d%d:%d%d)%-(%d%d:%d%d)$")
    end
    local timeText
    if tFrom and tTo then
        timeText = tFrom .. " - " .. tTo
    else
        timeText = raid.time or "?"
    end
    df.dateLabel:SetText("|cffffffff" .. (raid.date or "?")
        .. " von " .. timeText .. " Uhr|r")
    df.noteLabel:SetText(
        (raid.note and raid.note ~= "") and ("|cffaaaaaa" .. raid.note .. "|r") or "")
    df.creatorLabel:SetText("|cff888888Erstellt von: " .. (raid.createdBy or "?") .. "|r")

    -- Spec-Dropdown initialisieren
    local _, classToken = UnitClass("player")
    local myName   = UnitName("player")
    local mySignup = raid.signups and raid.signups[myName]
    InitSpecDropdown(df, classToken, mySignup and mySignup.spec or nil)

    -- Mein Status
    if mySignup then
        local c = STATUS_COLOR[mySignup.status] or "ffffff"
        local n = STATUS_LABEL[mySignup.status] or mySignup.status
        local specInfo = ADDON.RaidData:GetSpecInfo(mySignup.class, mySignup.spec or "")
        local specStr = specInfo and (" als " .. specInfo.name) or ""
        df.myStatusLabel:SetText("Dein Status: |cff" .. c .. n .. "|r" .. specStr)
        df.commentEB:SetText(mySignup.comment or "")
    else
        df.myStatusLabel:SetText("|cff888888Noch nicht angemeldet.|r")
        df.commentEB:SetText("")
    end

    -- Bearbeiten / Loeschen
    local canManage = self:CanManageRaids()
    df.editBtn:SetShown(canManage)
    df.deleteBtn:SetShown(canManage)

    self:RefreshRoster(raidId)
    df:Show()
end

---------------------------------------------------------------------------
-- Roster (nach Rolle gruppiert: Tank → Heiler → DD)
---------------------------------------------------------------------------

function RP:RefreshRoster(raidId)
    local df   = self.detailFrame
    local raid = ADDON.RaidplanerDB:GetRaid(raidId)
    if not df or not raid then return end

    local canManage = self:CanManageRaids()

    -----------------------------------------------------------------------
    -- Linke Seite: alle Anmeldungen (unabhängig vom Status),
    -- sortiert nach Rolle (Tank/Heiler/DD), dann Status, dann Name.
    -----------------------------------------------------------------------
    local function GetSignupRole(signup)
        local role = signup.role or ""
        if (role == "") and signup.spec and signup.spec ~= "" and signup.class then
            local specInfo = ADDON.RaidData:GetSpecInfo(signup.class, signup.spec)
            if specInfo then role = specInfo.role end
        end
        if role == "" then role = "DD" end
        return role
    end

    local ROLE_ORDER = { TANK = 1, HEAL = 2, DD = 3 }

    local entries = {}
    for _, signup in pairs(raid.signups or {}) do
        -- Spieler, die bereits im Kader bestaetigt sind, werden links nicht mehr als Anmeldung gezeigt.
        local isConfirmed = signup.confirmed
        if isConfirmed == nil then
            isConfirmed = (signup.status == "YES" or signup.status == "BENCH")
        end
        if not isConfirmed then
            entries[#entries + 1] = signup
        end
    end
    table.sort(entries, function(a, b)
        local ra = GetSignupRole(a)
        local rb = GetSignupRole(b)
        local roA = ROLE_ORDER[ra] or 99
        local roB = ROLE_ORDER[rb] or 99
        if roA ~= roB then return roA < roB end

        local oa = STATUS_ORDER[a.status] or 5
        local ob = STATUS_ORDER[b.status] or 5
        if oa ~= ob then return oa < ob end

        return (a.name or "") < (b.name or "")
    end)

    local reqIdx = 0
    local reqY   = 0
    for i, signup in ipairs(entries) do
        reqIdx = reqIdx + 1
        local row = GetOrCreateRequestRow(reqIdx, df.reqContent)
        row:ClearAllPoints()
        -- Stretch ueber die gesamte Breite des ScrollChilds, damit Text nicht geclippt wird
        row:SetPoint("TOPLEFT", df.reqContent, "TOPLEFT", 0, reqY)
        row:SetPoint("TOPRIGHT", df.reqContent, "TOPRIGHT", 0, reqY)
        row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)

        -- Name (mit Klassenfarbe)
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[signup.class]
        if cc then
            row.nameText:SetText(string.format("|cff%02x%02x%02x%s|r",
                cc.r * 255, cc.g * 255, cc.b * 255, signup.name))
        else
            row.nameText:SetText(signup.name or "?")
        end

        -- Rolle (Tank/Heiler/DD)
        local roleKey = GetSignupRole(signup)
        local roleInfo = ADDON.RaidData:GetRoleInfo(roleKey)
        local roleName = roleInfo and roleInfo.name or roleKey
        local roleCol  = roleInfo and roleInfo.color or "cccccc"
        row.roleText:SetText("|cff" .. roleCol .. roleName .. "|r")

        -- Spec
        local specInfo = ADDON.RaidData:GetSpecInfo(signup.class, signup.spec or "")
        local specName = specInfo and specInfo.name or (signup.spec or "?")
        row.specText:SetText("|cffbbbbbb" .. specName .. "|r")

        -- Status
        local c = STATUS_COLOR[signup.status] or "ffffff"
        local n = STATUS_LABEL[signup.status] or signup.status
        row.statusText:SetText("|cff" .. c .. n .. "|r")

        -- Kommentar (klickbar)
        local comment = signup.comment or ""
        if comment ~= "" then
            local short = (string.len(comment) > 12)
                and (string.sub(comment, 1, 10) .. "..") or comment
            row.commentBtn.text:SetText("|cff888888" .. short .. "|r")
            local pName = signup.name or "?"
            row.commentBtn:SetScript("OnClick", function()
                ShowCommentPopup(pName, comment)
            end)
            row.commentBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Kommentar anzeigen", 1, 0.82, 0)
                GameTooltip:AddLine(comment, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            row.commentBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.commentBtn:Show()
        else
            row.commentBtn.text:SetText("")
            row.commentBtn:Hide()
        end

        -- Bestätigungs-Buttons nur für Raidlead / GM
        if canManage then
            local raidIdCopy = raid.id
            local playerName = signup.name
            row.mainBtn:Show()
            row.reserveBtn:Show()
            row.mainBtn:SetScript("OnClick", function()
                RP:SetSignupStatus(raidIdCopy, playerName, "YES")
            end)
            row.reserveBtn:SetScript("OnClick", function()
                RP:SetSignupStatus(raidIdCopy, playerName, "BENCH")
            end)
        else
            row.mainBtn:Hide()
            row.reserveBtn:Hide()
        end

        row:Show()
        reqY = reqY - ROSTER_ROW_H
    end
    for i = reqIdx + 1, #requestRows do requestRows[i]:Hide() end
    df.reqContent:SetHeight(math.max(1, math.abs(reqY)))
    if df.reqSF.UpdateScrollChildRect then
        df.reqSF:UpdateScrollChildRect()
    end

    -----------------------------------------------------------------------
    -- Rechte Seite: bestätigter Kader (Status YES/BENCH), gruppiert nach Rolle
    -----------------------------------------------------------------------
    local byRole   = { TANK = {}, HEAL = {}, DD = {} }
    local yesCount = 0

    for _, signup in pairs(raid.signups or {}) do
        -- Nur bestaetigte Spieler zaehlen zum Kader.
        -- Aeltere Daten ohne confirmed-Feld gelten als bestaetigt,
        -- wenn ihr Status bereits YES oder BENCH ist.
        local isConfirmed = signup.confirmed
        if isConfirmed == nil then
            isConfirmed = (signup.status == "YES" or signup.status == "BENCH")
        end
        if isConfirmed and (signup.status == "YES" or signup.status == "BENCH") then
            local role = signup.role or ""
            if (role == "") and signup.spec and signup.spec ~= "" and signup.class then
                local specInfo = ADDON.RaidData:GetSpecInfo(signup.class, signup.spec)
                if specInfo then role = specInfo.role end
            end
            if role == "" then role = "DD" end
            if not byRole[role] then byRole[role] = {} end
            table.insert(byRole[role], signup)
            if signup.status == "YES" then yesCount = yesCount + 1 end
        end
    end

    for _, list in pairs(byRole) do
        table.sort(list, function(a, b)
            local oa = STATUS_ORDER[a.status] or 5
            local ob = STATUS_ORDER[b.status] or 5
            if oa ~= ob then return oa < ob end
            return (a.name or "") < (b.name or "")
        end)
    end

    local tankYes = 0; for _, s in ipairs(byRole.TANK) do if s.status == "YES" then tankYes = tankYes + 1 end end
    local healYes = 0; for _, s in ipairs(byRole.HEAL) do if s.status == "YES" then healYes = healYes + 1 end end
    local ddYes   = 0; for _, s in ipairs(byRole.DD)   do if s.status == "YES" then ddYes   = ddYes   + 1 end end

    df.rosterCountLabel:SetText("|cff00cc00" .. yesCount .. "|r / "
        .. (raid.size or "?") .. " Spieler")
    df.roleSummary:SetText(
        "|cff4488ffTank: " .. tankYes .. "|r" ..
        "   |cff44ff44Heiler: " .. healYes .. "|r" ..
        "   |cffff4444DD: " .. ddYes .. "|r")

    local rowIdx = 0
    local yPos   = 0
    local roleOrder = { "TANK", "HEAL", "DD" }

    for _, roleKey in ipairs(roleOrder) do
        local roleInfo = ADDON.RaidData:GetRoleInfo(roleKey)
        local list     = byRole[roleKey]
        local rColor   = roleInfo and roleInfo.color or "cccccc"
        local rName    = roleInfo and roleInfo.name or roleKey
        local yesInRole = 0
        for _, s in ipairs(list) do if s.status == "YES" then yesInRole = yesInRole + 1 end end

        rowIdx = rowIdx + 1
                local headerRow = GetOrCreateRosterRow(rowIdx, df.rosterContent)
                local headerTxt = rName .. "  (" .. yesInRole .. " Dabei, " .. #list .. " gesamt)"
                ConfigureAsHeader(headerRow, headerTxt, rColor, yPos)
        yPos = yPos - ROSTER_ROW_H

        if #list == 0 then
            rowIdx = rowIdx + 1
            local emptyRow = GetOrCreateRosterRow(rowIdx, df.rosterContent)
            emptyRow:ClearAllPoints()
            emptyRow:SetPoint("TOPLEFT", 0, yPos)
            emptyRow.bg:SetColorTexture(0, 0, 0, 0)
            emptyRow.headerText:SetText("    |cff555555– keine Spieler –|r")
            emptyRow.headerText:Show()
            emptyRow.nameText:Hide()
            emptyRow.specText:Hide()
            emptyRow.statusText:Hide()
            emptyRow.commentBtn:Hide()
            if emptyRow.backBtn then emptyRow.backBtn:Hide() end
            emptyRow:Show()
            yPos = yPos - ROSTER_ROW_H
        else
            for j, signup in ipairs(list) do
                rowIdx = rowIdx + 1
                local dataRow = GetOrCreateRosterRow(rowIdx, df.rosterContent)
                ConfigureAsData(dataRow, signup, yPos, (j % 2 == 0))
                -- Zurueck-Button nur fuer Raidlead/GM
                if canManage and dataRow.backBtn then
                    local raidIdCopy = raid.id
                    local playerName = signup.name
                    dataRow.backBtn:Show()
                    dataRow.backBtn:SetScript("OnClick", function()
                        RP:UnsetFromRoster(raidIdCopy, playerName)
                    end)
                elseif dataRow.backBtn then
                    dataRow.backBtn:Hide()
                end
                yPos = yPos - ROSTER_ROW_H
            end
        end
    end

    for i = rowIdx + 1, #rosterRows do rosterRows[i]:Hide() end

    df.rosterContent:SetHeight(math.max(1, math.abs(yPos)))
    if df.rosterSF.UpdateScrollChildRect then
        df.rosterSF:UpdateScrollChildRect()
    end
end

---------------------------------------------------------------------------
-- Signup
---------------------------------------------------------------------------

function RP:HandleSignup(status)
    local df = self.detailFrame
    if not df or not df.currentRaidId then return end

    local raidId = df.currentRaidId
    local raid   = ADDON.RaidplanerDB:GetRaid(raidId)
    if not raid then return end

    local myName           = UnitName("player")
    local _, classToken    = UnitClass("player")
    local comment          = strtrim(df.commentEB:GetText() or "")
    local specKey          = df.selectedSpec or ""
    local roleKey          = df.selectedRole or ""

    -- Rolle aus Spec ableiten falls nicht gesetzt
    if roleKey == "" and specKey ~= "" then
        local specInfo = ADDON.RaidData:GetSpecInfo(classToken, specKey)
        if specInfo then roleKey = specInfo.role end
    end

    local signup = {
        name      = myName,
        class     = classToken,
        spec      = specKey,
        role      = roleKey,
        status    = status,
        comment   = comment,
        confirmed = false, -- erst nach manueller Bestaetigung durch Raidlead/GM
        updatedAt = time(),
    }

    if not raid.signups then raid.signups = {} end
    raid.signups[myName] = signup

    ADDON.RaidplanerSync:BroadcastSignup(raidId, signup)

    local specInfo = ADDON.RaidData:GetSpecInfo(classToken, specKey)
    local specStr  = specInfo and (" als " .. specInfo.name) or ""
    ADDON:Print("Angemeldet: " .. (STATUS_LABEL[status] or status) .. specStr)
    self:ShowRaidDetail(raidId)
end

--- Status fuer bestehenden Signup aendern (z.B. aus Anmeldeliste in Kader schieben).
function RP:SetSignupStatus(raidId, playerName, newStatus)
    local raid = ADDON.RaidplanerDB:GetRaid(raidId)
    if not raid or not raid.signups or not raid.signups[playerName] then return end

    local s = raid.signups[playerName]
    s.status    = newStatus
    s.confirmed = true
    s.updatedAt = time()

    ADDON.RaidplanerSync:BroadcastSignup(raidId, s)
    self:RefreshRoster(raidId)
end

--- Spieler aus dem Kader wieder zur reinen Anmeldung machen.
function RP:UnsetFromRoster(raidId, playerName)
    local raid = ADDON.RaidplanerDB:GetRaid(raidId)
    if not raid or not raid.signups or not raid.signups[playerName] then return end

    local s = raid.signups[playerName]
    s.confirmed = false
    s.updatedAt = time()

    ADDON.RaidplanerSync:BroadcastSignup(raidId, s)
    self:RefreshRoster(raidId)
end

---------------------------------------------------------------------------
-- Raid loeschen (mit Bestaetigung)
---------------------------------------------------------------------------

function RP:ConfirmDeleteRaid(raidId)
    if not self:CanManageRaids() then
        ADDON:Print("Nur GM und Raidleiter können Raids löschen.")
        return
    end
    local raid = ADDON.RaidplanerDB:GetRaid(raidId)
    if not raid then return end

    StaticPopupDialogs["GAS_RP_DELETE_RAID"] = {
        text     = "Raid \"" .. (raid.raidName or "?") .. "\" am "
                   .. (raid.date or "?") .. " wirklich loeschen?",
        button1  = "Ja",
        button2  = "Nein",
        OnAccept = function()
            ADDON.RaidplanerDB:DeleteRaid(raidId)
            ADDON.RaidplanerSync:BroadcastDelete(raidId)
            ADDON:Print("Raid geloescht.")
            if RP.detailFrame then RP.detailFrame:Hide() end
            RP:RefreshCalendar()
        end,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("GAS_RP_DELETE_RAID")
end

---------------------------------------------------------------------------
-- Hauptfenster erstellen
---------------------------------------------------------------------------

function RP:Init()
    if rpFrame then return end
    InitMonth()

    -- Hauptframe
    rpFrame = CreateFrame("Frame", "GASRaidplanerFrame", UIParent, "BackdropTemplate")
    rpFrame:SetSize(MAIN_W, MAIN_H)
    rpFrame:SetPoint("CENTER")
    rpFrame:SetFrameStrata("HIGH")
    ApplyBackdrop(rpFrame, BD_MAIN, 0.04, 0.04, 0.07, 0.96, 0.55, 0.45, 0.2)
    MakeMovable(rpFrame)
    rpFrame:Hide()
    tinsert(UISpecialFrames, "GASRaidplanerFrame")

    -- Logo
    local bg = rpFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetTexture(LOGO_TEX)
    bg:SetSize(320, 320)
    bg:SetPoint("CENTER", 0, 0)
    bg:SetAlpha(0.15)

    -- Titel
    CreateLabel(rpFrame, "GameFontNormalLarge",
        "|cffff8800GAS|r |cffffffffRaidplaner|r", "TOPLEFT", 16, -14)

    -- Close
    local closeBtn = CreateFrame("Button", nil, rpFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Hub Button
    local hubBtn = CreateBtn(rpFrame, 70, 24, "< Hub", function()
        rpFrame:Hide()
        if ADDON.Hub then ADDON.Hub:Toggle() end
    end)
    hubBtn:SetPoint("TOPRIGHT", -36, -11)

    -- Monats-Navigation
    local prevBtn = CreateBtn(rpFrame, 30, 24, "<", function()
        currentMonth = currentMonth - 1
        if currentMonth < 1 then currentMonth = 12; currentYear = currentYear - 1 end
        RP:RefreshCalendar()
    end)
    prevBtn:SetPoint("TOPLEFT", 16, -42)

    monthLabel = CreateLabel(rpFrame, "GameFontNormal", "", "LEFT", prevBtn, "RIGHT", 8, 0)
    monthLabel:SetWidth(180)
    monthLabel:SetJustifyH("LEFT")

    local nextBtn = CreateBtn(rpFrame, 30, 24, ">", function()
        currentMonth = currentMonth + 1
        if currentMonth > 12 then currentMonth = 1; currentYear = currentYear + 1 end
        RP:RefreshCalendar()
    end)
    nextBtn:SetPoint("LEFT", monthLabel, "RIGHT", 4, 0)

    local todayBtn = CreateBtn(rpFrame, 60, 24, "Heute", function()
        InitMonth()
        RP:RefreshCalendar()
    end)
    todayBtn:SetPoint("LEFT", nextBtn, "RIGHT", 8, 0)

    -- Content Inset
    contentInset = CreateFrame("Frame", nil, rpFrame, "BackdropTemplate")
    contentInset:SetPoint("TOPLEFT", INSET_PAD, -72)
    contentInset:SetPoint("BOTTOMRIGHT", -INSET_PAD, 28)
    ApplyBackdrop(contentInset, BD_INSET, 0.07, 0.07, 0.1, 0.85, 0.35, 0.35, 0.35)

    -- Kalender-Content (innerhalb Inset)
    calendarContent = CreateFrame("Frame", nil, contentInset)
    calendarContent:SetPoint("TOPLEFT", 4, -4)
    calendarContent:SetPoint("BOTTOMRIGHT", -4, 4)

    -- Verfuegbare Groesse berechnen
    local insetW = MAIN_W - INSET_PAD * 2 - 8
    local insetH = MAIN_H - 72 - 28 - 8
    local cellW  = math.floor(insetW / GRID_COLS)
    local cellH  = math.floor((insetH - HEADER_H) / GRID_ROWS)

    -- Wochentag-Kopfzeile
    for i, day in ipairs(WEEKDAYS) do
        local lbl = calendarContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", (i - 1) * cellW + cellW / 2 - 8, 0)
        local color = (i >= 6) and "|cffff8888" or "|cffcccccc"
        lbl:SetText(color .. day .. "|r")
    end

    -- 42 Tageskacheln erzeugen
    for idx = 1, GRID_COLS * GRID_ROWS do
        dayCells[idx] = CreateDayCell(idx, calendarContent, cellW, cellH)
    end

    -- Hinweis unten links
    local hint = rpFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetText("|cff888888Klicke auf einen Raid fuer Details & Anmeldung."
        .. "  GM/Raidleiter: [+] zum Ansetzen.|r")
    hint:SetPoint("BOTTOMLEFT", 16, 8)

    -- Credits
    local credits = rpFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    credits:SetText("|cff666666Raidplaner  |  Made by B\195\161bushka|r")
    credits:SetPoint("BOTTOMRIGHT", -14, 8)

    self.rpFrame = rpFrame
end

---------------------------------------------------------------------------
-- Toggle
---------------------------------------------------------------------------

function RP:ToggleMainFrame()
    if not self.rpFrame then self:Init() end
    if self.rpFrame:IsShown() then
        self.rpFrame:Hide()
        return
    end
    if not ADDON:GetGuildInfo() then
        ADDON:Print("Du bist in keiner Gilde – Raidplaner deaktiviert.")
        return
    end
    ADDON.DB:EnsureProfile()
    self.rpFrame:Show()
    self:RefreshCalendar()
    -- Sync anfragen
    if ADDON.RaidplanerSync then
        ADDON.RaidplanerSync:BroadcastHello()
    end
end
