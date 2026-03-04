local _, ADDON = ...

ADDON.Theme = ADDON.Theme or {}
local Theme = ADDON.Theme

-- Source of truth: GuildStockPlanner visual language
Theme.colors = {
    windowBg = { 0.04, 0.04, 0.07, 1.00 },
    panelBg = { 0.05, 0.06, 0.10, 1.00 },
    border = { 0.35, 0.40, 0.55, 1.00 },
    text = { 1.00, 0.82, 0.00, 1.00 },
    textMuted = { 0.66, 0.66, 0.66, 1.00 },
    highlight = { 1.00, 1.00, 1.00, 0.08 },
    button = {
        normal = { 0.15, 0.15, 0.22, 1.00 },
        hover = { 0.20, 0.20, 0.30, 1.00 },
        pressed = { 0.11, 0.11, 0.18, 1.00 },
        disabled = { 0.12, 0.12, 0.12, 0.85 },
        border = { 0.50, 0.50, 0.50, 1.00 },
        disabledBorder = { 0.25, 0.25, 0.25, 0.80 },
    },
}

Theme.alpha = {
    -- Reduced transparency compared to older windows.
    windowBg = 0.96,
    panelBg = 0.94,
    insetBg = 0.92,
}

Theme.spacing = {
    padding = 10,
    gap = 8,
    sectionGap = 12,
}

Theme.sizes = {
    headerHeight = 28,
    rowHeight = 26,
    footerHeight = 32,
    minWindowW = 480,
    minWindowH = 420,
}

Theme.fonts = {
    normal = "GameFontNormal",
    small = "GameFontNormalSmall",
    header = "GameFontNormalLarge",
    muted = "GameFontDisableSmall",
}

Theme.backdrops = {
    window = {
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
    panel = {
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
    tooltip = {
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
    input = {
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    },
}

