# GermanysAllStar – Developer Guide

Dieses Dokument ist als Einstieg fuer Entwickler (oder KI-Agents) gedacht,
um sich schnell im Projekt zurechtzufinden.

## Module

- **Core / Hub**
  - `Core/Bootstrap.lua`: Namespace `ADDON`, Hilfsfunktionen, Hub-Datenbank, Rechte-Logik.
  - `Core/Hub/UI.lua`: Hub-Fenster, App-Launcher, Rechteverwaltung.
- **GuildStockPlanner**
  - `Modules/GuildStockPlanner/Data/DB.lua`: Rezepte, Gildenbank-Scan-Resultate, Sync-Log.
  - `Modules/GuildStockPlanner/Services/Scanner.lua`: Scan der Gildenbank-Tabs.
  - `Modules/GuildStockPlanner/Services/Calculator.lua`: Berechnet fehlende Materialien.
  - `Modules/GuildStockPlanner/Services/ExportImport.lua`: Backup/Restore-Strings fuer Rezepte.
  - `Modules/GuildStockPlanner/Services/Sync.lua`: Gildenweiter Sync der Rezepte.
  - `Modules/GuildStockPlanner/UI/Main.lua`: Haupt-UI mit Tabs (Rezepte, Zu farmen, Gildenbank, Sync-Log, How-To, Einstellungen).
- **Raidplaner**
  - `Modules/Raidplaner/Data/RaidData.lua`: Statische Definitionen (Raids, Specs, Rollen).
  - `Modules/Raidplaner/Data/DB.lua`: Raid- & Signup-Persistenz, Tombstones, Raid-Logs.
  - `Modules/Raidplaner/Services/Sync.lua`: Gildenweiter Sync von Raids & Signups.
  - `Modules/Raidplaner/UI/Theme.lua`: Theme-Hooks fuer Backdrops/Labels.
  - `Modules/Raidplaner/UI/Main.lua`: Kalender, Create/Edit-Dialog, Raid-Detail, Roster, Signup, Logs.
  - `Modules/Raidplaner/Services/Planner.lua`: Wochenplaner-Ansicht fuer Raidleads (Raid-Kader).
  - `Modules/Raidplaner/Services/State.lua`: Hilfsfunktionen fuer Raid-Status (bestätigt/abgesagt) und UI-Refresh.
- **GuildStocks**
  - `Modules/GuildStocks/UI/Main.lua`: Anzeige aller Gildenbank-Bestände (Standalone-Viewer).

## Wichtige Einstiegspunkte

- Addon-Initialisierung & Slash-Command:
  - `Core/Bootstrap.lua`: Registrierung der Slash-Befehle (`/ga`, `/gsp`), Aufruf von `ADDON.Hub:Toggle()`.
- Hub öffnen:
  - `Core/Hub/UI.lua`: `ADDON.Hub:Toggle()` und `ADDON.Hub:EnsureHubFrame()`.
- GuildStockPlanner:
  - `Modules/GuildStockPlanner/UI/Main.lua`: `ADDON.UI:ToggleMainFrame()`.
- Raidplaner:
  - `Modules/Raidplaner/UI/Main.lua`: `RP:ToggleMainFrame()` (Kalender), `RP:OpenPlanner()` (Planer).

## Datenhaltung

- **GermanysAllStarDB** (SavedVariable)
  - Verwaltet vom `Core` / `HubDB` (Rechteverwaltung je Gilde).
- **GuildStockPlannerDB** (SavedVariable)
  - Verwaltet von `Modules/GuildStockPlanner/Data/DB.lua`.
- **Profile-Struktur**
  - `Core/Bootstrap.lua` → `ADDON:GetProfileKey()` (Realm::Gilde) als Schlüssel.

## Konventionen

- Keine externen Libraries, nur Standard-WoW-API.
- Alle Module hängen an einem gemeinsamen `ADDON`-Namespace.
- Raids und Rezepte werden immer über ihre jeweiligen DB-Module (`Modules/Raidplaner/Data/DB.lua`, `Modules/GuildStockPlanner/Data/DB.lua`) gelesen/geschrieben.

