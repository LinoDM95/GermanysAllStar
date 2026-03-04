local _, ADDON = ...

-- Compatibility wrapper: keeps existing Raidplaner API while using the
-- shared GuildStockPlanner-based design system.
ADDON.UITheme = ADDON.UITheme or {}
local THEME = ADDON.UITheme
local Theme = ADDON.Theme
local DS = ADDON.DesignSystem

THEME.colors = Theme.colors
THEME.spacing = { S = Theme.spacing.gap, M = Theme.spacing.padding, L = Theme.spacing.sectionGap }
THEME.layout = {
    padding = Theme.spacing.padding,
    gap = Theme.spacing.gap,
    sectionGap = Theme.spacing.sectionGap,
    rowHeight = Theme.sizes.rowHeight,
    headerHeight = Theme.sizes.headerHeight,
    footerHeight = Theme.sizes.footerHeight,
    minWidth = Theme.sizes.minWindowW,
    minHeight = Theme.sizes.minWindowH,
}
THEME.fonts = Theme.fonts
THEME.backdrops = {
    panel = Theme.backdrops.window,
    inset = Theme.backdrops.panel,
    cell = Theme.backdrops.panel,
    button = Theme.backdrops.panel,
}

function THEME:ApplyTheme(frame, variant)
    if variant == "inset" or variant == "cell" then
        DS.ApplyPanelStyle(frame)
    else
        DS.ApplyWindowStyle(frame)
    end
end

function THEME:CreatePanel(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    DS.ApplyWindowStyle(f)
    return f
end

function THEME:CreateInset(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    DS.ApplyPanelStyle(f)
    return f
end

function THEME:CreateSeparator(parent, alpha)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetColorTexture(0.55, 0.46, 0.20, alpha or 0.7)
    return sep
end

function THEME:CreateLabelGold(parent, fontObj, text, ...)
    local variant = "normal"
    if fontObj == "GameFontDisableSmall" then variant = "muted"
    elseif fontObj == "GameFontNormalSmall" or fontObj == "GameFontHighlightSmall" then variant = "small"
    elseif fontObj == "GameFontNormalLarge" then variant = "header" end
    return DS.CreateLabel(parent, variant, text, ...)
end

function THEME:CreateButtonRed(parent, width, height, text, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn._txt = btn:CreateFontString(nil, "OVERLAY", Theme.fonts.small)
    btn._txt:SetPoint("CENTER")
    btn._txt:SetText(text or "")
    DS.ApplyButtonStyle(btn, "primary")
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
            local lvl = strataLevel + i
            list:SetFrameStrata("TOOLTIP")
            list:SetFrameLevel(lvl)
            if not list._gasRaiseHooked then
                list:HookScript("OnShow", function(self)
                    self:SetFrameStrata("TOOLTIP")
                    self:SetFrameLevel(lvl)
                end)
                list._gasRaiseHooked = true
            end
        end
    end
end
