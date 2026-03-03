local _, ADDON = ...

local RP = ADDON.Raidplaner
if not RP then return end

local ROLE_COL_W, NAME_COL_W = 80, 150
local RAID_COL_W, ROW_H = 120, 22
local HEADER_H, GAP = 42, 4

local ROLE_META = {
    TANK = { order = 1, label = "Tank", color = "66aaff" },
    HEAL = { order = 2, label = "Heiler", color = "66ff88" },
    DD   = { order = 3, label = "DD", color = "ff7777" },
}

local plannerFrame
local pRows, pCells, pHeaders = {}, {}, {}

local function ParseDate(dateStr)
    local y, m, d = (dateStr or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return nil end
    return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

local function YMD(ts)
    return date("%Y-%m-%d", ts)
end

local function WeekStartFromDate(dateStr)
    local ts = ParseDate(dateStr)
    if not ts then return nil end
    local w = tonumber(date("%w", ts)) or 0 -- 0=So,3=Mi
    local offset = (w - 3) % 7
    return ts - offset * 86400
end

local function WeekRangeByStart(weekStartTs)
    return weekStartTs, weekStartTs + 6 * 86400
end

local function FormatHeadDate(dateStr)
    local y, m, d = (dateStr or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return dateStr or "?" end
    return string.format("%s.%s.%s", d, m, string.sub(y, 3, 4))
end

local function GetSignupRole(signup)
    local role = signup.role or ""
    if role == "" and signup.class and signup.spec and signup.spec ~= "" then
        local specInfo = ADDON.RaidData:GetSpecInfo(signup.class, signup.spec)
        if specInfo then role = specInfo.role end
    end
    if role == "" then role = "DD" end
    return role
end

local function IsSignupPlanned(signup)
    if not signup then return false end
    if signup.confirmed ~= nil then
        return signup.confirmed == true
    end
    return signup.status == "YES"
end

local function GetPlannedRoleCounts(raid)
    local counts = { TANK = 0, HEAL = 0, DD = 0 }
    for _, signup in pairs((raid and raid.signups) or {}) do
        if IsSignupPlanned(signup) then
            local role = GetSignupRole(signup)
            if counts[role] ~= nil then
                counts[role] = counts[role] + 1
            end
        end
    end
    return counts
end


local function GetRoleForPlayer(player)
    if player.primaryRole then return player.primaryRole end
    local bestRole, bestCount = "DD", -1
    for role, count in pairs(player.roleCounts or {}) do
        local ord = (ROLE_META[role] and ROLE_META[role].order) or 99
        local bestOrd = (ROLE_META[bestRole] and ROLE_META[bestRole].order) or 99
        if count > bestCount or (count == bestCount and ord < bestOrd) then
            bestRole, bestCount = role, count
        end
    end
    return bestRole
end

local function GetClassColorCode(class, fallback)
    if RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class] then
        return RAID_CLASS_COLORS[class].colorStr or fallback
    end
    return fallback
end

local function IsPlayerPlannedInSameRaidWeek(name, raidKey, exceptRaidId)
    if not plannerFrame or not plannerFrame.planData then return false end
    for _, other in ipairs(plannerFrame.planData.columns or {}) do
        if other.raidKey == raidKey and other.id ~= exceptRaidId then
            local os = other.signups and other.signups[name]
            if os and IsSignupPlanned(os) then
                return true
            end
        end
    end
    return false
end

local function DetermineInitialWeekStart()
    local now = date("*t")
    local fallback = WeekStartFromDate(string.format("%04d-%02d-%02d", now.year, now.month, now.day))

    local bestFuture, bestPast
    local nowTs = time()
    for _, raid in pairs(ADDON.RaidplanerDB:GetRaids()) do
        local ts = ParseDate(raid.date)
        if ts then
            if ts >= nowTs then
                if (not bestFuture) or ts < bestFuture then bestFuture = ts end
            else
                if (not bestPast) or ts > bestPast then bestPast = ts end
            end
        end
    end

    if bestFuture then return WeekStartFromDate(date("%Y-%m-%d", bestFuture)) end
    if bestPast then return WeekStartFromDate(date("%Y-%m-%d", bestPast)) end
    return fallback
end

local function CollectRaidFilterOptionsForWeek(weekStartTs)
    local fromTs, toTs = WeekRangeByStart(weekStartTs)
    local byKey = {}

    for _, raid in pairs(ADDON.RaidplanerDB:GetRaids()) do
        local ts = ParseDate(raid.date)
        if ts and ts >= fromTs and ts <= toTs and raid.raidKey and raid.raidKey ~= "" then
            byKey[raid.raidKey] = true
        end
    end

    local opts = {}
    for raidKey in pairs(byKey) do
        local def = ADDON.RaidData:GetByKey(raidKey)
        opts[#opts + 1] = {
            key = raidKey,
            text = (def and (def.short or def.name)) or raidKey,
            order = ADDON.RaidData:GetIndex(raidKey) or 999,
        }
    end
    table.sort(opts, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.text < b.text
    end)
    return opts
end

local function RefreshPlannerFilterDropdownOptions()
    if not plannerFrame or not plannerFrame.filterDD then return end

    plannerFrame.filterOptions = CollectRaidFilterOptionsForWeek(plannerFrame.weekStartTs)
    local hasCurrentFilter = (plannerFrame.raidFilter == "ALL")
    if not hasCurrentFilter then
        for _, opt in ipairs(plannerFrame.filterOptions) do
            if opt.key == plannerFrame.raidFilter then
                hasCurrentFilter = true
                break
            end
        end
    end
    if not hasCurrentFilter then
        plannerFrame.raidFilter = "ALL"
    end

    UIDropDownMenu_Initialize(plannerFrame.filterDD, function(_, level)
        local function Add(name, key)
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.func = function()
                plannerFrame.raidFilter = key
                UIDropDownMenu_SetText(plannerFrame.filterDD, name)
                RP:RefreshPlanner()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end

        Add("Alle (Woche)", "ALL")
        for _, opt in ipairs(plannerFrame.filterOptions) do
            Add(opt.text, opt.key)
        end
    end)

    local label = "Alle (Woche)"
    if plannerFrame.raidFilter ~= "ALL" then
        for _, opt in ipairs(plannerFrame.filterOptions) do
            if opt.key == plannerFrame.raidFilter then
                label = opt.text
                break
            end
        end
    end
    UIDropDownMenu_SetText(plannerFrame.filterDD, label)
end

function RP:RebuildPlannerData()
    if not plannerFrame then return end
    local weekStartTs = plannerFrame.weekStartTs
    local fromTs, toTs = WeekRangeByStart(weekStartTs)
    local raidFilter = plannerFrame.raidFilter

    local columns = {}
    for _, raid in pairs(ADDON.RaidplanerDB:GetRaids()) do
        local ts = ParseDate(raid.date)
        if ts and ts >= fromTs and ts <= toTs and (not raidFilter or raidFilter == "ALL" or raid.raidKey == raidFilter) then
            columns[#columns + 1] = raid
        end
    end

    table.sort(columns, function(a, b)
        if a.date ~= b.date then return (a.date or "") < (b.date or "") end
        return (a.time or "") < (b.time or "")
    end)

    local playersByName = {}
    for _, raid in ipairs(columns) do
        for name, s in pairs(raid.signups or {}) do
            local pInfo = playersByName[name]
            if not pInfo then
                pInfo = {
                    name = name,
                    class = s.class,
                    roleCounts = { TANK = 0, HEAL = 0, DD = 0 },
                    plannedAny = false,
                }
                playersByName[name] = pInfo
            end
            if not pInfo.class and s.class then pInfo.class = s.class end

            local roleKey = GetSignupRole(s)
            pInfo.roleCounts[roleKey] = (pInfo.roleCounts[roleKey] or 0) + 1
            if IsSignupPlanned(s) then
                pInfo.plannedAny = true
                if not pInfo.primaryRole then pInfo.primaryRole = roleKey end
            end
        end
    end

    local roleBuckets = { TANK = {}, HEAL = {}, DD = {} }
    for _, pInfo in pairs(playersByName) do
        pInfo.roleKey = GetRoleForPlayer(pInfo)
        pInfo.classColor = RAID_CLASS_COLORS and pInfo.class and RAID_CLASS_COLORS[pInfo.class] or nil
        roleBuckets[pInfo.roleKey] = roleBuckets[pInfo.roleKey] or {}
        roleBuckets[pInfo.roleKey][#roleBuckets[pInfo.roleKey] + 1] = pInfo
    end

    local rows = {}
    rows[#rows + 1] = { isSection = true, sectionType = "header", title = "Raid Kader" }
    for _, roleKey in ipairs({ "TANK", "HEAL", "DD" }) do
        local rolePlayers = roleBuckets[roleKey] or {}
        local plannedPlayers, waitingPlayers = {}, {}
        for _, pInfo in ipairs(rolePlayers) do
            if pInfo.plannedAny then
                plannedPlayers[#plannedPlayers + 1] = pInfo
            else
                waitingPlayers[#waitingPlayers + 1] = pInfo
            end
        end
        table.sort(plannedPlayers, function(a, b) return a.name < b.name end)
        table.sort(waitingPlayers, function(a, b) return a.name < b.name end)

        rows[#rows + 1] = {
            isSection = true,
            sectionType = "role",
            roleKey = roleKey,
            planned = #plannedPlayers,
            total = #rolePlayers,
            inRoster = true,
        }

        for _, pInfo in ipairs(plannedPlayers) do
            rows[#rows + 1] = {
                isSection = false,
                name = pInfo.name,
                class = pInfo.class,
                classColor = pInfo.classColor,
                roleKey = roleKey,
                plannedAny = true,
                inRoster = true,
            }
        end

        roleBuckets[roleKey] = waitingPlayers
    end

    rows[#rows + 1] = { isSection = true, sectionType = "divider" }
    rows[#rows + 1] = { isSection = true, sectionType = "header", title = "Spieler (nicht eingeplant)" }

    local waitingPlayers = {}
    for _, roleKey in ipairs({ "TANK", "HEAL", "DD" }) do
        for _, pInfo in ipairs(roleBuckets[roleKey] or {}) do
            waitingPlayers[#waitingPlayers + 1] = pInfo
        end
    end
    table.sort(waitingPlayers, function(a, b) return a.name < b.name end)

    for _, pInfo in ipairs(waitingPlayers) do
        rows[#rows + 1] = {
            isSection = false,
            name = pInfo.name,
            class = pInfo.class,
            classColor = pInfo.classColor,
            roleKey = pInfo.roleKey,
            plannedAny = false,
            inRoster = false,
        }
    end

    plannerFrame.planData = { columns = columns, rows = rows, playersByName = playersByName }
end

local function MakeCell(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(RAID_COL_W - 2, ROW_H - 2)
    b:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    b.raidId, b.rowKey = nil, nil
    return b
end

function RP:PlannerAssignPlayerToRaid(name, raidId)
    local raid = ADDON.RaidplanerDB:GetRaid(raidId)
    if not raid or not raid.signups or not raid.signups[name] then return end
    local s = raid.signups[name]

    local wasPlanned = IsSignupPlanned(s)
    if wasPlanned then
        s.confirmed = false
    else
        s.confirmed = true
        s.status = "YES"
    end
    s.updatedAt = time()

    if s.confirmed then
        local weekStart = WeekStartFromDate(raid.date)
        local fromTs, toTs = WeekRangeByStart(weekStart)
        for _, other in pairs(ADDON.RaidplanerDB:GetRaids()) do
            local ots = ParseDate(other.date)
            if other.id ~= raid.id and ots and ots >= fromTs and ots <= toTs and other.raidKey == raid.raidKey then
                local os = other.signups and other.signups[name]
                if os and IsSignupPlanned(os) then
                    os.confirmed = false
                    os.updatedAt = s.updatedAt
                    ADDON.RaidplanerDB:SaveRaid(other)
                    ADDON.RaidplanerSync:BroadcastSignup(other.id, os)
                end
            end
        end
    end

    ADDON.RaidplanerDB:SaveRaid(raid)
    ADDON.RaidplanerSync:BroadcastSignup(raidId, s)
    self:RefreshCalendar()
    if self.detailFrame and self.detailFrame:IsShown() and self.detailFrame.currentRaidId then
        self:RefreshRoster(self.detailFrame.currentRaidId)
    end
    self:RefreshPlanner()
end

function RP:RefreshPlanner()
    if not plannerFrame or not plannerFrame:IsShown() then return end
    if ADDON.UITheme and ADDON.UITheme.RaiseGlobalDropdowns then
        ADDON.UITheme:RaiseGlobalDropdowns(32)
    end
    RefreshPlannerFilterDropdownOptions()
    self:RebuildPlannerData()
    local pd = plannerFrame.planData or { rows = {}, columns = {}, playersByName = {} }

    for _, h in ipairs(pHeaders) do h:Hide() end
    for _, r in ipairs(pRows) do r:Hide() end
    for _, c in ipairs(pCells) do c:Hide() end

    local leftW = ROLE_COL_W + NAME_COL_W
    local rightW = math.max(1, #pd.columns * RAID_COL_W)

    plannerFrame.rightHeaderChild:SetSize(rightW, HEADER_H)
    plannerFrame.rightContent:SetSize(rightW, math.max(1, #pd.rows * ROW_H))
    plannerFrame.leftContent:SetSize(leftW, math.max(1, #pd.rows * ROW_H))

    for i, raid in ipairs(pd.columns) do
        local h = pHeaders[i]
        if not h then
            h = CreateFrame("Frame", nil, plannerFrame.rightHeaderChild)
            h:SetSize(RAID_COL_W, HEADER_H)
            h.t = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            h.t:SetPoint("CENTER")
            pHeaders[i] = h
        end
        h:SetPoint("TOPLEFT", (i - 1) * RAID_COL_W, 0)
        local def = ADDON.RaidData:GetByKey(raid.raidKey)
        local short = def and def.short or raid.raidKey or "?"
        local planned = GetPlannedRoleCounts(raid)
        h.t:SetText(
            "|cffffd100" .. short .. "|r\n"
            .. "|cffcccccc" .. FormatHeadDate(raid.date) .. "|r\n"
            .. "|cff66aaffT:" .. planned.TANK .. "|r "
            .. "|cff66ff88H:" .. planned.HEAL .. "|r "
            .. "|cffff7777D:" .. planned.DD .. "|r"
        )
        h:Show()
    end

    for rowIdx, rowData in ipairs(pd.rows) do
        local row = pRows[rowIdx]
        if not row then
            row = CreateFrame("Button", nil, plannerFrame.leftContent, "BackdropTemplate")
            row:SetSize(leftW, ROW_H)
            row:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 6, 0)
            row.text:SetWidth(leftW - 12)
            row.text:SetJustifyH("LEFT")
            row:SetScript("OnClick", function(self)
                if not RP:CanManageRaids() or self.isSection or not self.playerName then return end
                if plannerFrame.selectedPlayerName == self.playerName then
                    plannerFrame.selectedPlayerName = nil
                else
                    plannerFrame.selectedPlayerName = self.playerName
                end
                RP:RefreshPlanner()
            end)
            pRows[rowIdx] = row
        end

        row:SetPoint("TOPLEFT", 0, -(rowIdx - 1) * ROW_H)
        row.isSection = rowData.isSection

        if rowData.isSection then
            row.playerName = nil
            if rowData.sectionType == "header" then
                row:SetBackdropColor(0.2, 0.16, 0.05, 0.55)
                row.text:SetText("|cffffd100" .. (rowData.title or "") .. "|r")
            elseif rowData.sectionType == "divider" then
                row:SetBackdropColor(0.9, 0.75, 0.2, 0.45)
                row.text:SetText("")
            else
                local meta = ROLE_META[rowData.roleKey] or ROLE_META.DD
                row:SetBackdropColor(0.05, 0.08, 0.12, 0.55)
                row.text:SetText("|cff" .. meta.color .. meta.label .. "|r |cff00ff00(" .. rowData.planned .. " Dabei, " .. rowData.total .. " gesamt)|r")
            end
        else
            row.playerName = rowData.name
            local selected = plannerFrame.selectedPlayerName == rowData.name
            local isPlanned = rowData.plannedAny
            if selected then
                row:SetBackdropColor(0.25, 0.20, 0.05, 0.55)
            else
                row:SetBackdropColor(0, 0, 0, 0.20)
            end
            if rowData.classColor then
                local cr, cg, cb = rowData.classColor.r * 255, rowData.classColor.g * 255, rowData.classColor.b * 255
                row.text:SetText(string.format("|cff%02x%02x%02x%s|r", cr, cg, cb, rowData.name))
            else
                row.text:SetText("|cffffffff" .. rowData.name .. "|r")
            end
        end
        row:Show()

        for colIdx, raid in ipairs(pd.columns) do
            local idx = (rowIdx - 1) * math.max(1, #pd.columns) + colIdx
            local cell = pCells[idx]
            if not cell then
                cell = MakeCell(plannerFrame.rightContent)
                cell:SetScript("OnMouseUp", function(self)
                    if not RP:CanManageRaids() then return end
                    local selectedName = plannerFrame.selectedPlayerName
                    if not selectedName or not self.canAssign then return end
                    RP:PlannerAssignPlayerToRaid(selectedName, self.raidId)
                end)
                pCells[idx] = cell
            end
            cell:SetPoint("TOPLEFT", (colIdx - 1) * RAID_COL_W + 1, -(rowIdx - 1) * ROW_H - 1)
            cell.raidId = raid.id
            cell.raidObj = raid

            if rowData.isSection then
                cell.canAssign = false
                if rowData.sectionType == "role" and rowData.inRoster then
                    local roleCounts = GetPlannedRoleCounts(raid)
                    local count = roleCounts[rowData.roleKey] or 0
                    local meta = ROLE_META[rowData.roleKey] or ROLE_META.DD
                    cell.label:SetText("|cff" .. meta.color .. tostring(count) .. "|r")
                    cell:SetBackdropColor(0.05, 0.08, 0.12, 0.45)
                    cell:SetBackdropBorderColor(0.1, 0.2, 0.25, 0.35)
                elseif rowData.sectionType == "divider" then
                    cell.label:SetText("")
                    cell:SetBackdropColor(0.9, 0.75, 0.2, 0.45)
                    cell:SetBackdropBorderColor(0.9, 0.75, 0.2, 0.6)
                else
                    cell.label:SetText("")
                    cell:SetBackdropColor(0.12, 0.10, 0.04, 0.35)
                    cell:SetBackdropBorderColor(0.25, 0.2, 0.08, 0.4)
                end
                cell:Show()
            else
                local s = raid.signups and raid.signups[rowData.name]
                local selectedName = plannerFrame.selectedPlayerName
                local isSelectedRow = selectedName == rowData.name
                local isPlanned = s and IsSignupPlanned(s)
                local blocked = false
                if selectedName and raid.raidKey then
                    blocked = IsPlayerPlannedInSameRaidWeek(selectedName, raid.raidKey, raid.id)
                end

                cell.canAssign = isSelectedRow and s ~= nil and (not blocked or isPlanned)

                local txt = ""
                if s then
                    if isPlanned then
                        local classCode = GetClassColorCode(s.class or rowData.class, "ffffffff")
                        txt = "|c" .. classCode .. rowData.name .. "|r"
                    elseif rowData.plannedAny then
                        txt = ""
                    else
                        local specInfo = ADDON.RaidData:GetSpecInfo(s.class, s.spec or "")
                        txt = "|cff888888" .. ((specInfo and specInfo.name) or (s.spec or "-")) .. "|r"
                    end
                end
                cell.label:SetText(txt)

                if cell.canAssign then
                    cell:SetBackdropColor(0.16, 0.15, 0.05, 0.52)
                    cell:SetBackdropBorderColor(0.95, 0.85, 0.2, 0.8)
                elseif selectedName and s and blocked and not isPlanned then
                    cell:SetBackdropColor(0.12, 0.04, 0.04, 0.50)
                    cell:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.55)
                else
                    cell:SetBackdropColor(0.08, 0.08, 0.12, 0.5)
                    cell:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.35)
                end
                cell:Show()
            end
        end
    end

    local maxV = math.max(0, (#pd.rows * ROW_H) - plannerFrame.contentH)
    plannerFrame.vScroll:SetMinMaxValues(0, maxV)
    if plannerFrame.vScroll:GetValue() > maxV then plannerFrame.vScroll:SetValue(maxV) end

    local maxH = math.max(0, rightW - plannerFrame.rightW)
    plannerFrame.hScroll:SetMinMaxValues(0, maxH)
    if plannerFrame.hScroll:GetValue() > maxH then plannerFrame.hScroll:SetValue(maxH) end

    plannerFrame.weekLabel:SetText("|cffffd100Mi-Di:|r " .. date("%d.%m.%Y", plannerFrame.weekStartTs) .. " - " .. date("%d.%m.%Y", plannerFrame.weekStartTs + 6 * 86400))
end

function RP:OpenPlanner()
    if not self:CanManageRaids() then
        ADDON:Print("Nur GM/Raidlead darf den Planer nutzen.")
        return
    end
    if not plannerFrame then self:EnsurePlannerFrame() end
    if plannerFrame and not plannerFrame.userNavigatedWeek then
        plannerFrame.weekStartTs = DetermineInitialWeekStart()
    end
    plannerFrame:Show()
    self:RefreshPlanner()
end

function RP:EnsurePlannerFrame()
    if plannerFrame then return end
    plannerFrame = CreateFrame("Frame", "GASRPPlannerFrame", UIParent, "BackdropTemplate")
    plannerFrame:SetSize(1180, 680)
    plannerFrame:SetPoint("CENTER")
    plannerFrame:SetFrameStrata("TOOLTIP")
    plannerFrame:SetFrameLevel(30)
    plannerFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    plannerFrame:SetBackdropColor(0.04, 0.04, 0.07, 0.97)
    plannerFrame:SetMovable(true)
    plannerFrame:EnableMouse(true)
    plannerFrame:RegisterForDrag("LeftButton")
    plannerFrame:SetScript("OnDragStart", plannerFrame.StartMoving)
    plannerFrame:SetScript("OnDragStop", plannerFrame.StopMovingOrSizing)
    plannerFrame:Hide()
    tinsert(UISpecialFrames, "GASRPPlannerFrame")

    local title = plannerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("|cffffd100Raid Planer|r")

    local close = CreateFrame("Button", nil, plannerFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local prev = CreateFrame("Button", nil, plannerFrame, "UIPanelButtonTemplate")
    prev:SetSize(28, 22)
    prev:SetPoint("TOPLEFT", 12, -42)
    prev:SetText("<")

    plannerFrame.weekLabel = plannerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    plannerFrame.weekLabel:SetPoint("LEFT", prev, "RIGHT", 8, 0)
    plannerFrame.weekLabel:SetWidth(260)
    plannerFrame.weekLabel:SetJustifyH("LEFT")

    local nextB = CreateFrame("Button", nil, plannerFrame, "UIPanelButtonTemplate")
    nextB:SetSize(28, 22)
    nextB:SetPoint("LEFT", plannerFrame.weekLabel, "RIGHT", 8, 0)
    nextB:SetText(">")

    local ddLabel = plannerFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ddLabel:SetPoint("LEFT", nextB, "RIGHT", 10, 0)
    ddLabel:SetText("Raidfilter:")

    plannerFrame.filterDD = CreateFrame("Frame", "GASRPPlannerFilterDD", plannerFrame, "UIDropDownMenuTemplate")
    plannerFrame.filterDD:SetPoint("LEFT", ddLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(plannerFrame.filterDD, 130)

    local leftX, topY = 12, -74
    plannerFrame.leftW = ROLE_COL_W + NAME_COL_W
    plannerFrame.rightW = 1180 - plannerFrame.leftW - 50
    plannerFrame.contentH = 680 - 120

    local leftHeader = CreateFrame("Frame", nil, plannerFrame, "BackdropTemplate")
    leftHeader:SetPoint("TOPLEFT", leftX, topY)
    leftHeader:SetSize(plannerFrame.leftW, HEADER_H)
    leftHeader:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    leftHeader:SetBackdropColor(0, 0, 0, 0.35)
    local lh = leftHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lh:SetPoint("LEFT", 4, 0)
    lh:SetText("|cffffd100Rolle / Spieler|r")

    plannerFrame.rightHeaderSF = CreateFrame("ScrollFrame", nil, plannerFrame)
    plannerFrame.rightHeaderSF:SetPoint("TOPLEFT", leftHeader, "TOPRIGHT", GAP, 0)
    plannerFrame.rightHeaderSF:SetSize(plannerFrame.rightW, HEADER_H)
    plannerFrame.rightHeaderChild = CreateFrame("Frame", nil, plannerFrame.rightHeaderSF)
    plannerFrame.rightHeaderChild:SetSize(1, HEADER_H)
    plannerFrame.rightHeaderSF:SetScrollChild(plannerFrame.rightHeaderChild)

    plannerFrame.leftSF = CreateFrame("ScrollFrame", nil, plannerFrame)
    plannerFrame.leftSF:SetPoint("TOPLEFT", leftX, topY - HEADER_H - 2)
    plannerFrame.leftSF:SetSize(plannerFrame.leftW, plannerFrame.contentH)
    plannerFrame.leftContent = CreateFrame("Frame", nil, plannerFrame.leftSF)
    plannerFrame.leftContent:SetSize(1, 1)
    plannerFrame.leftSF:SetScrollChild(plannerFrame.leftContent)

    plannerFrame.rightSF = CreateFrame("ScrollFrame", nil, plannerFrame)
    plannerFrame.rightSF:SetPoint("TOPLEFT", plannerFrame.leftSF, "TOPRIGHT", GAP, 0)
    plannerFrame.rightSF:SetSize(plannerFrame.rightW, plannerFrame.contentH)
    plannerFrame.rightContent = CreateFrame("Frame", nil, plannerFrame.rightSF)
    plannerFrame.rightContent:SetSize(1, 1)
    plannerFrame.rightSF:SetScrollChild(plannerFrame.rightContent)

    local sep = plannerFrame:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", plannerFrame.leftSF, "TOPRIGHT", 1, 2)
    sep:SetPoint("BOTTOMLEFT", plannerFrame.leftSF, "BOTTOMRIGHT", 1, -2)
    sep:SetWidth(1)
    sep:SetColorTexture(0.8, 0.7, 0.2, 0.4)

    plannerFrame.vScroll = CreateFrame("Slider", nil, plannerFrame, "UIPanelScrollBarTemplate")
    plannerFrame.vScroll:SetPoint("TOPLEFT", plannerFrame.rightSF, "TOPRIGHT", 2, -16)
    plannerFrame.vScroll:SetPoint("BOTTOMLEFT", plannerFrame.rightSF, "BOTTOMRIGHT", 2, 16)
    plannerFrame.vScroll:SetMinMaxValues(0, 0)
    plannerFrame.vScroll:SetValueStep(8)
    plannerFrame.vScroll:SetObeyStepOnDrag(true)
    plannerFrame.vScroll:SetScript("OnValueChanged", function(self, value)
        plannerFrame.leftSF:SetVerticalScroll(value)
        plannerFrame.rightSF:SetVerticalScroll(value)
    end)

    plannerFrame.hScroll = CreateFrame("Slider", nil, plannerFrame, "UIPanelHorizontalScrollBarTemplate")
    plannerFrame.hScroll:SetPoint("TOPLEFT", plannerFrame.rightSF, "BOTTOMLEFT", 16, -2)
    plannerFrame.hScroll:SetPoint("TOPRIGHT", plannerFrame.rightSF, "BOTTOMRIGHT", -16, -2)
    plannerFrame.hScroll:SetMinMaxValues(0, 0)
    plannerFrame.hScroll:SetValueStep(8)
    plannerFrame.hScroll:SetObeyStepOnDrag(true)
    plannerFrame.hScroll:SetScript("OnValueChanged", function(self, value)
        plannerFrame.rightSF:SetHorizontalScroll(value)
        plannerFrame.rightHeaderSF:SetHorizontalScroll(value)
    end)

    plannerFrame.rightSF:EnableMouseWheel(true)
    plannerFrame.rightHeaderSF:EnableMouseWheel(true)

    local function ScrollHorizontal(delta)
        local step = 36 * (delta > 0 and -1 or 1)
        local v = plannerFrame.hScroll:GetValue() + step
        local min, max = plannerFrame.hScroll:GetMinMaxValues()
        if v < min then v = min elseif v > max then v = max end
        plannerFrame.hScroll:SetValue(v)
    end

    local function ScrollVertical(delta)
        local step = 24 * (delta > 0 and -1 or 1)
        local v = plannerFrame.vScroll:GetValue() + step
        local min, max = plannerFrame.vScroll:GetMinMaxValues()
        if v < min then v = min elseif v > max then v = max end
        plannerFrame.vScroll:SetValue(v)
    end

    plannerFrame.rightSF:SetScript("OnMouseWheel", function(_, delta)
        if IsShiftKeyDown() then
            ScrollHorizontal(delta)
        else
            ScrollVertical(delta)
        end
    end)
    plannerFrame.rightHeaderSF:SetScript("OnMouseWheel", function(_, delta)
        ScrollHorizontal(delta)
    end)

    plannerFrame.weekStartTs = DetermineInitialWeekStart()
    plannerFrame.raidFilter = "ALL"

    prev:SetScript("OnClick", function()
        plannerFrame.userNavigatedWeek = true
        plannerFrame.weekStartTs = plannerFrame.weekStartTs - (7 * 86400)
        RP:RefreshPlanner()
    end)
    nextB:SetScript("OnClick", function()
        plannerFrame.userNavigatedWeek = true
        plannerFrame.weekStartTs = plannerFrame.weekStartTs + (7 * 86400)
        RP:RefreshPlanner()
    end)

    RefreshPlannerFilterDropdownOptions()

    RP.plannerFrame = plannerFrame
end
