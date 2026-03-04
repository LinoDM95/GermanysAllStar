local _, ADDON = ...

ADDON.RaidplanerLayout = ADDON.RaidplanerLayout or {}
local L = ADDON.RaidplanerLayout

-----------------------------------------------------------------------
-- Basis-Anchor-Helper
-----------------------------------------------------------------------

--- Fuellt parent mit frame, optional mit einheitlichem oder {l,r,t,b}-Inset.
function L.AnchorFill(frame, parent, inset)
    if not frame or not parent then return end
    frame:ClearAllPoints()
    local l, r, t, b
    if type(inset) == "number" then
        l, r, t, b = inset, inset, inset, inset
    elseif type(inset) == "table" then
        l = inset.left or inset[1] or 0
        r = inset.right or inset[2] or l
        t = inset.top or inset[3] or l
        b = inset.bottom or inset[4] or l
    else
        l, r, t, b = 0, 0, 0, 0
    end
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", l, -t)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -r, b)
end

--- Verankert frame am oberen Rand von parent mit fixer Hoehe.
function L.AnchorTop(frame, parent, inset, height)
    if not frame or not parent then return end
    frame:ClearAllPoints()
    inset = inset or 0
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
    frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -inset, -inset)
    if height then
        frame:SetHeight(height)
    end
end

--- Verankert frame am unteren Rand von parent mit fixer Hoehe.
function L.AnchorBottom(frame, parent, inset, height)
    if not frame or not parent then return end
    frame:ClearAllPoints()
    inset = inset or 0
    frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", inset, inset)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
    if height then
        frame:SetHeight(height)
    end
end

-----------------------------------------------------------------------
-- Stack-Helper (HStack / VStack)
-----------------------------------------------------------------------

local function normalizeInset(inset)
    if type(inset) == "number" then
        return inset, inset, inset, inset
    elseif type(inset) == "table" then
        local l = inset.left or inset[1] or 0
        local r = inset.right or inset[2] or l
        local t = inset.top or inset[3] or l
        local b = inset.bottom or inset[4] or l
        return l, r, t, b
    end
    return 0, 0, 0, 0
end

--- Legt children horizontal in parent an.
-- @param align "TOP", "CENTER", "BOTTOM"
function L.HStack(parent, children, gap, inset, align, fixedWidths)
    if not parent or not children then return end
    gap = gap or 0
    align = align or "TOP"
    local l, r, t, b = normalizeInset(inset)

    local x = l
    local yPoint = (align == "BOTTOM") and "BOTTOMLEFT"
        or (align == "CENTER") and "LEFT" or "TOPLEFT"

    for idx, child in ipairs(children) do
        if child then
            child:ClearAllPoints()
            child:SetPoint(yPoint, parent, "TOPLEFT", x, -t)
            if fixedWidths and fixedWidths[idx] then
                child:SetWidth(fixedWidths[idx])
                x = x + fixedWidths[idx] + gap
            else
                local w = child:GetWidth() or 0
                x = x + w + gap
            end
        end
    end
end

--- Legt children vertikal in parent an.
-- @param align "LEFT", "CENTER", "RIGHT"
function L.VStack(parent, children, gap, inset, align, fixedHeights)
    if not parent or not children then return end
    gap = gap or 0
    align = align or "LEFT"
    local l, r, t, b = normalizeInset(inset)

    local y = -t
    local xPoint = (align == "RIGHT") and "TOPRIGHT"
        or (align == "CENTER") and "TOP" or "TOPLEFT"

    for idx, child in ipairs(children) do
        if child then
            child:ClearAllPoints()
            child:SetPoint(xPoint, parent, "TOPLEFT", l, y)
            if fixedHeights and fixedHeights[idx] then
                child:SetHeight(fixedHeights[idx])
                y = y - fixedHeights[idx] - gap
            else
                local h = child:GetHeight() or 0
                y = y - h - gap
            end
        end
    end
end

-----------------------------------------------------------------------
-- Grid
-----------------------------------------------------------------------

function L.Grid(parent, items, cols, gapX, gapY, inset, rowHeight)
    if not parent or not items or cols <= 0 then return end
    gapX = gapX or 0
    gapY = gapY or 0
    rowHeight = rowHeight or 20
    local l, r, t, b = normalizeInset(inset)

    for index, child in ipairs(items) do
        if child then
            child:ClearAllPoints()
            local col = (index - 1) % cols
            local row = math.floor((index - 1) / cols)
            local x = l + col * (child:GetWidth() + gapX)
            local y = -t - row * (rowHeight + gapY)
            child:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        end
    end
end

-----------------------------------------------------------------------
-- Text / Button Utilities
-----------------------------------------------------------------------

function L.MeasureText(fs)
    if not fs or not fs:GetText() then return 0, 0 end
    fs:SetWidth(0)
    fs:SetHeight(0)
    fs:SetWordWrap(false)
    local w = fs:GetStringWidth() or 0
    local h = fs:GetStringHeight() or 0
    return w, h
end

function L.AutoSizeButton(btn, paddingX, minWidth)
    if not btn or not btn.GetText then return end
    paddingX = paddingX or 16
    minWidth = minWidth or 0
    local txt = btn:GetText() or ""
    local fs = btn:GetFontString()
    if not fs then
        btn:SetWidth(minWidth)
        return
    end
    fs:SetText(txt)
    local w = (fs:GetStringWidth() or 0) + paddingX
    if w < minWidth then w = minWidth end
    btn:SetWidth(w)
end

