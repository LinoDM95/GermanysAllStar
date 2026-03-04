# GuildStockPlanner – Modulübersicht

Dieses Modul verwaltet Gildenbank-Scans, Rezepte und die Berechnung
fehlender Materialien.

## Dateien

- `DB.lua`
  - Verwaltet `GuildStockPlannerDB`.
  - Speichert:
    - Rezepte (`GetRecipes`, `SaveRecipe`, `DeleteRecipe`).
    - Letzten Gildenbank-Scan (`GetLastScan`, `SaveScan`).
    - Sync-Log (`AddLogEntry`, `GetSyncLog` – neueste zuerst).
- `Scanner.lua`
  - Führt den Gildenbank-Scan aus (`Scanner:StartScan`).
  - Liest alle Tabs und schreibt die Item-Counts in `DB.lua`.
- `Calculator.lua`
  - Kernlogik zur Berechnung fehlender Materialien (`Calculator:Calculate`).
  - Nutzt aktuelle Bank-Bestände + gewünschte Rezepte aus `DB.lua`.
- `ExportImport.lua`
  - Exportiert alle Rezepte als Text-String (`ExportImport:Export`).
  - Importiert aus einem String und gibt die Datentabelle zurück (`Import`).
- `Sync.lua`
  - Stiller Sync über den Gilden-Channel (`ADDON.Sync`).
  - Broadcast von Rezeptänderungen und Bank-Scans.
- `UI.lua`
  - Hauptfenster, Tabs & komplette UI-Logik.
  - Einstiegsfunktion: `ADDON.UI:ToggleMainFrame()`.

