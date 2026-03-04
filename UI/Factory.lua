local _, ADDON = ...

local Theme = ADDON.Theme
local DS = ADDON.DesignSystem

ADDON.UIFactory = ADDON.UIFactory or {}
local Factory = ADDON.UIFactory

function Factory.CreateWindow(parent, title, options)
    options = options or {}
    local frame = CreateFrame("Frame", options.name, parent or UIParent, "BackdropTemplate")
    frame:SetSize(options.width or Theme.sizes.minWindowW, options.height or Theme.sizes.minWindowH)
    frame:SetPoint(options.point or "CENTER", options.relativeTo, options.relativePoint or "CENTER", options.x or 0, options.y or 0)
    DS.ApplyWindowStyle(frame)

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", Theme.spacing.padding, -Theme.spacing.padding)
    frame.header:SetPoint("TOPRIGHT", -Theme.spacing.padding, -Theme.spacing.padding)
    frame.header:SetHeight(Theme.sizes.headerHeight)

    frame.title = DS.CreateLabel(frame.header, "header", title or "", "LEFT", 0, 0)

    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeButton:SetPoint("TOPRIGHT", -2, -2)

    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", Theme.spacing.padding, -(Theme.spacing.padding + Theme.sizes.headerHeight))
    frame.body:SetPoint("BOTTOMRIGHT", -Theme.spacing.padding, Theme.spacing.padding + (options.footer and Theme.sizes.footerHeight or 0))

    if options.footer then
        frame.footer = CreateFrame("Frame", nil, frame)
        frame.footer:SetPoint("BOTTOMLEFT", Theme.spacing.padding, Theme.spacing.padding)
        frame.footer:SetPoint("BOTTOMRIGHT", -Theme.spacing.padding, Theme.spacing.padding)
        frame.footer:SetHeight(Theme.sizes.footerHeight)
    end

    return frame
end

function Factory.CreatePrimaryButton(parent, text, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetText(text or "")
    DS.ApplyButtonStyle(btn, "primary")
    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end

function Factory.CreateSecondaryButton(parent, text, onClick)
    return Factory.CreatePrimaryButton(parent, text, onClick)
end

function Factory.CreateSectionHeader(parent, text)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(Theme.sizes.headerHeight)
    DS.ApplyHeaderStyle(header)
    header.text = DS.CreateLabel(header, "small", text or "", "LEFT", Theme.spacing.gap, 0)
    return header
end

function Factory.CreateDivider(parent)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetColorTexture(0.55, 0.46, 0.20, 0.5)
    return sep
end

function Factory.CreateIconButton(parent, icon, tooltip)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(20, 20)
    DS.ApplyButtonStyle(btn)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexture(icon)
    if tooltip then
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return btn
end

