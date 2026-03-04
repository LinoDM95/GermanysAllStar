local _, ADDON = ...

local Theme = ADDON.Theme or {}
ADDON.DesignSystem = ADDON.DesignSystem or {}
local DS = ADDON.DesignSystem

local function SetTextColor(fs, color)
    if not fs or not color then return end
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

function DS.ApplyTextStyle(fontString, variant)
    if not fontString then return end
    local fonts = Theme.fonts or {}
    local fontObj = fonts[variant] or fonts.normal or "GameFontNormal"
    fontString:SetFontObject(fontObj)
    if variant == "muted" then
        SetTextColor(fontString, Theme.colors.textMuted)
    else
        SetTextColor(fontString, Theme.colors.text)
    end
end

local function ApplyBackdrop(frame, bd, color, alpha)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop(bd)
    local c = color or Theme.colors.windowBg
    frame:SetBackdropColor(c[1], c[2], c[3], alpha or c[4] or 1)
    local border = Theme.colors.border
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
end

function DS.ApplyWindowStyle(frame)
    ApplyBackdrop(frame, Theme.backdrops.window, Theme.colors.windowBg, Theme.alpha.windowBg)
end

function DS.ApplyPanelStyle(frame)
    ApplyBackdrop(frame, Theme.backdrops.panel, Theme.colors.panelBg, Theme.alpha.panelBg)
end

function DS.ApplyHeaderStyle(frame)
    if not frame then return end
    if not frame._gasHeaderBg then
        frame._gasHeaderBg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        frame._gasHeaderBg:SetAllPoints()
    end
    frame._gasHeaderBg:SetColorTexture(0.18, 0.18, 0.25, 0.55)
end

function DS.ApplyButtonStyle(button, variant)
    if not button or button._gasStyled then return end
    variant = variant or "secondary"
    if button.SetBackdrop then
        button:SetBackdrop(Theme.backdrops.panel)
    end
    local c = Theme.colors.button
    local function setState(state)
        if not button.SetBackdropColor then return end
        local rgba = c[state] or c.normal
        button:SetBackdropColor(rgba[1], rgba[2], rgba[3], rgba[4])
        local br = (state == "disabled") and c.disabledBorder or c.border
        button:SetBackdropBorderColor(br[1], br[2], br[3], br[4])
    end

    local fs = button:GetFontString()
    if fs then DS.ApplyTextStyle(fs, "small") end

    if not button._gasHighlight then
        local hl = button:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        local hc = Theme.colors.highlight
        hl:SetColorTexture(hc[1], hc[2], hc[3], hc[4])
        button._gasHighlight = hl
    end

    button:HookScript("OnEnter", function(self)
        if self:IsEnabled() then setState("hover") end
    end)
    button:HookScript("OnLeave", function(self)
        if self:IsEnabled() then setState("normal") end
    end)
    button:HookScript("OnMouseDown", function(self)
        if self:IsEnabled() then setState("pressed") end
    end)
    button:HookScript("OnMouseUp", function(self)
        if self:IsEnabled() then
            if MouseIsOver(self) then setState("hover") else setState("normal") end
        end
    end)
    button:HookScript("OnDisable", function() setState("disabled") end)
    button:HookScript("OnEnable", function() setState("normal") end)

    setState(button:IsEnabled() and "normal" or "disabled")
    button._gasStyled = true
end

function DS.ApplyTabStyle(tab)
    if not tab then return end
    local fs = tab:GetFontString()
    if fs then DS.ApplyTextStyle(fs, "small") end
end

function DS.ApplyInputStyle(editBox)
    if not editBox then return end
    if editBox.SetBackdrop then
        editBox:SetBackdrop(Theme.backdrops.input)
        editBox:SetBackdropColor(Theme.colors.panelBg[1], Theme.colors.panelBg[2], Theme.colors.panelBg[3], Theme.alpha.insetBg)
        local border = Theme.colors.border
        editBox:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end
    if editBox.SetTextColor then
        local tc = Theme.colors.text
        editBox:SetTextColor(tc[1], tc[2], tc[3], tc[4])
    end
end

function DS.ApplyCheckboxStyle(checkButton)
    if not checkButton then return end
    if checkButton.label then
        DS.ApplyTextStyle(checkButton.label, "small")
    end
end

function DS.CreateLabel(parent, fontVariant, text, ...)
    local fs = parent:CreateFontString(nil, "OVERLAY", Theme.fonts[fontVariant] or fontVariant or Theme.fonts.normal)
    if text then fs:SetText(text) end
    if select("#", ...) > 0 then fs:SetPoint(...) end
    if fontVariant == "muted" then
        SetTextColor(fs, Theme.colors.textMuted)
    else
        SetTextColor(fs, Theme.colors.text)
    end
    return fs
end

