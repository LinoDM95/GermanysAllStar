# GermanysAllStar – Developer Guide

Dieses Dokument ist als Einstieg fuer Entwickler (oder KI-Agents) gedacht,
um sich schnell im Projekt zurechtzufinden.

## Module

- **Core / Hub**
  - `Core.lua`: Namespace `ADDON`, Hilfsfunktionen, Hub-Datenbank, Rechte-Logik.
  - `HubUI.lua`: Hub-Fenster, App-Launcher, Rechteverwaltung.
- **GuildStockPlanner**
  - `GuildStockPlanner/DB.lua`: Rezepte, Gildenbank-Scan-Resultate, Sync-Log.
  - `GuildStockPlanner/Scanner.lua`: Scan der Gildenbank-Tabs.
  - `GuildStockPlanner/Calculator.lua`: Berechnet fehlende Materialien.
  - `GuildStockPlanner/ExportImport.lua`: Backup/Restore-Strings fuer Rezepte.
  - `GuildStockPlanner/Sync.lua`: Gildenweiter Sync der Rezepte.
  - `GuildStockPlanner/UI.lua`: Haupt-UI mit Tabs (Rezepte, Zu farmen, Gildenbank, Sync-Log, How-To, Einstellungen).
- **Raidplaner**
  - `Raidplaner/RaidData.lua`: Statische Definitionen (Raids, Specs, Rollen).
  - `Raidplaner/DB.lua`: Raid- & Signup-Persistenz, Tombstones, Raid-Logs.
  - `Raidplaner/Sync.lua`: Gildenweiter Sync von Raids & Signups.
  - `Raidplaner/UITheme.lua`: Theme-Hooks fuer Backdrops/Labels.
  - `Raidplaner/UI.lua`: Kalender, Create/Edit-Dialog, Raid-Detail, Roster, Signup, Logs.
  - `Raidplaner/Planner.lua`: Wochenplaner-Ansicht fuer Raidleads (Raid-Kader).
  - `Raidplaner/State.lua`: Hilfsfunktionen fuer Raid-Status (bestätigt/abgesagt) und UI-Refresh.
- **GuildStocks**
  - `GuildStocks/UI.lua`: Anzeige aller Gildenbank-Bestände (Standalone-Viewer).

## Wichtige Einstiegspunkte

- Addon-Initialisierung & Slash-Command:
  - `Core.lua`: Registrierung der Slash-Befehle (`/ga`, `/gsp`), Aufruf von `ADDON.Hub:Toggle()`.
- Hub öffnen:
  - `HubUI.lua`: `ADDON.Hub:Toggle()` und `ADDON.Hub:EnsureHubFrame()`.
- GuildStockPlanner:
  - `GuildStockPlanner/UI.lua`: `ADDON.UI:ToggleMainFrame()`.
- Raidplaner:
  - `Raidplaner/UI.lua`: `RP:ToggleMainFrame()` (Kalender), `RP:OpenPlanner()` (Planer).

## Datenhaltung

- **GermanysAllStarDB** (SavedVariable)
  - Verwaltet vom `Core` / `HubDB` (Rechteverwaltung je Gilde).
- **GuildStockPlannerDB** (SavedVariable)
  - Verwaltet von `GuildStockPlanner/DB.lua`.
- **Profile-Struktur**
  - `Core.lua` → `ADDON:GetProfileKey()` (Realm::Gilde) als Schlüssel.

## Konventionen

- Keine externen Libraries, nur Standard-WoW-API.
- Alle Module hängen an einem gemeinsamen `ADDON`-Namespace.
- Raids und Rezepte werden immer über ihre jeweiligen DB-Module (`Raidplaner/DB.lua`, `GuildStockPlanner/DB.lua`) gelesen/geschrieben.

