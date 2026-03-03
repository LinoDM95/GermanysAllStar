local _, ADDON = ...

ADDON.UITheme = ADDON.UITheme or {}
local THEME = ADDON.UITheme

THEME.colors = {
    gold      = { 1.00, 0.82, 0.00, 1.00 },
    secondary = { 0.66, 0.66, 0.66, 1.00 },
    danger    = { 1.00, 0.27, 0.27, 1.00 },
    success   = { 0.27, 1.00, 0.27, 1.00 },
}

THEME.spacing = {
    S = 8,
    M = 12,
    L = 16,
}

THEME.backdrops = {
    panel = {
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
    inset = {
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
    cell = {
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    },
    button = {
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    },
}

local function SetFSColor(fs, color)
    if not fs then return end
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

function THEME:ApplyTheme(frame, variant)
    if not frame or not frame.SetBackdrop then return end
    local bd = self.backdrops[variant or "panel"] or self.backdrops.panel
    frame:SetBackdrop(bd)
    if variant == "inset" then
        frame:SetBackdropColor(0.05, 0.06, 0.10, 0.92)
        frame:SetBackdropBorderColor(0.35, 0.42, 0.50, 0.85)
    elseif variant == "cell" then
        frame:SetBackdropColor(0.08, 0.08, 0.12, 0.66)
        frame:SetBackdropBorderColor(0.30, 0.30, 0.30, 0.30)
    else
        frame:SetBackdropColor(0.04, 0.05, 0.09, 0.96)
        frame:SetBackdropBorderColor(0.50, 0.55, 0.65, 0.90)
    end
end

function THEME:CreatePanel(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    self:ApplyTheme(f, "panel")
    return f
end

function THEME:CreateInset(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    self:ApplyTheme(f, "inset")
    return f
end

function THEME:CreateSeparator(parent, alpha)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetColorTexture(0.55, 0.46, 0.20, alpha or 0.7)
    return sep
end

function THEME:CreateLabelGold(parent, fontObj, text, ...)
    local fs = parent:CreateFontString(nil, "OVERLAY", fontObj or "GameFontNormal")
    SetFSColor(fs, self.colors.gold)
    if text then fs:SetText(text) end
    if select("#", ...) > 0 then fs:SetPoint(...) end
    return fs
end

function THEME:CreateButtonRed(parent, width, height, text, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop(self.backdrops.button)

    btn._normal = { 0.35, 0.07, 0.07, 0.98 }
    btn._hover  = { 0.48, 0.12, 0.12, 1.00 }
    btn._down   = { 0.26, 0.05, 0.05, 1.00 }
    btn._border = { 0.75, 0.30, 0.18, 0.95 }

    btn:SetBackdropColor(unpack(btn._normal))
    btn:SetBackdropBorderColor(unpack(btn._border))

    btn._txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn._txt:SetPoint("CENTER")
    btn._txt:SetText(text or "")
    SetFSColor(btn._txt, self.colors.gold)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    btn:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then self:SetBackdropColor(unpack(self._down)) end
    end)
    btn:SetScript("OnMouseUp", function(self)
        if self:IsEnabled() and MouseIsOver(self) then
            self:SetBackdropColor(unpack(self._hover))
        elseif self:IsEnabled() then
            self:SetBackdropColor(unpack(self._normal))
        end
    end)
    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self:SetBackdropColor(unpack(self._hover)) end
    end)
    btn:SetScript("OnLeave", function(self)
        if self:IsEnabled() then self:SetBackdropColor(unpack(self._normal)) end
    end)
    btn:SetScript("OnEnable", function(self)
        self:SetBackdropColor(unpack(self._normal))
        self:SetBackdropBorderColor(unpack(self._border))
        SetFSColor(self._txt, THEME.colors.gold)
    end)
    btn:SetScript("OnDisable", function(self)
        self:SetBackdropColor(0.12, 0.12, 0.12, 0.85)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.80)
        SetFSColor(self._txt, THEME.colors.secondary)
    end)

    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end

function THEME:CreateScrollArea(parent, name)
    local sf = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, sf)
    child:SetPoint("TOPLEFT", 0, 0)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    sf.content = child
    return sf, child
end

function THEME:RaiseGlobalDropdowns(level)
    local strataLevel = level or 20
    for i = 1, UIDROPDOWNMENU_MAXLEVELS or 3 do
        local list = _G["DropDownList" .. i]
        if list then
            local level = strataLevel + i
            list:SetFrameStrata("TOOLTIP")
            list:SetFrameLevel(level)
            if not list._gasRaiseHooked then
                list:HookScript("OnShow", function(self)
                    self:SetFrameStrata("TOOLTIP")
                    self:SetFrameLevel(level)
                end)
                list._gasRaiseHooked = true
            end
        end
    end
end
