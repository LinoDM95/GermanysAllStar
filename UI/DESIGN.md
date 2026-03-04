# GermanysAllStar UI Design System

## Source of truth
- Visual baseline comes from `Modules/GuildStockPlanner/UI/Main.lua`.
- Tokens are centralized in `UI/Theme.lua` and applied through `UI/DesignSystem.lua`.

## Core tokens
- `Theme.colors.*`: window/panel backgrounds, borders, text, button states.
- `Theme.alpha.windowBg`: central alpha for all main windows (intentionally less transparent).
- `Theme.spacing.*`: padding/gap/section spacing.
- `Theme.sizes.*`: shared header/footer/row sizes and minimum window sizes.
- `Theme.fonts.*`: normal/small/header/muted mappings.
- `Theme.backdrops.*`: window/panel/tooltip/input backdrop presets.

## Rules
1. No magic numbers for spacing or alpha in feature UIs.
2. Prefer `DesignSystem.Apply*` for all styling.
3. Prefer `UIFactory` for new windows and reusable controls.
4. Keep behavior unchanged: styling/layout only.
5. Use `ClearAllPoints()` before re-anchoring existing frames.

## Typical usage
```lua
local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
ADDON.DesignSystem.ApplyWindowStyle(frame)

local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
ADDON.DesignSystem.ApplyButtonStyle(btn)
```
