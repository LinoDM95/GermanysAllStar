# Raidplaner – Modulübersicht

Dieses Modul stellt den Raid-Kalender, das Detailfenster mit Anmeldungen
und den Wochen-Planer bereit.

## Dateien

- `RaidData.lua`
  - Statische Definitionen:
    - `RD.raids` – Liste aller Raids (key, name, size, short).
    - `RD.classSpecs` – Specs pro Klasse mit Rolle.
    - `RD.roles` – Rollen-Metadaten (Farbe, Sortierung).
  - Hilfsfunktionen wie `RD:GetByKey`, `RD:GetSpecsForClass`, `RD:GetRoleInfo`.
- `DB.lua`
  - Datenmodell und Persistenz für:
    - Raids (`GetRaids`, `SaveRaid`, `DeleteRaid`, `GenerateId`).
    - Signups (`SaveSignup`, `GetSignups`).
    - Lösch-Tombstones (`GetDeletions`, `CleanupDeletions`).
    - Raid-Logs (`AddLog`, `GetLogs`).
  - Wird von `Sync.lua` und `UI.lua` verwendet.
- `Sync.lua`
  - Gildenweiter Sync über Addon-Messages (`"GASRP"`):
    - Hello/Fingerprint (`RH`), Raid-Upserts (`RA`), Löschungen (`RD`),
      Signups (`RS`), Full-Sync-Finish (`RF`).
  - Core-Funktionen:
    - `RSync:BroadcastFull`, `RSync:BroadcastRaid`, `RSync:BroadcastSignup`,
      `RSync:OnRaidReceived`, `RSync:OnSignupReceived`, `RSync:RefreshUI`.
- `UITheme.lua`
  - Optionale Theme-Schicht für einheitliche Backdrops/Labels.
  - Wird von `UI.lua` verwendet (z.B. `THEME:ApplyTheme`).
- `UI.lua`
  - Hauptfenster / Kalender (`RP:Init`, `RP:ToggleMainFrame`, `RP:RefreshCalendar`).
  - Raid-Erstellen/Bearbeiten-Dialog (`RP:OpenCreateRaid`, `RP:OpenEditRaid`, `RP:SaveRaidFromDialog`).
  - Raid-Detail & Anmeldungen (`RP:ShowRaidDetail`, `RP:HandleSignup`, `RP:RefreshRoster`).
  - Raid-Löschen (`RP:ConfirmDeleteRaid`).
  - Raid-Logs (`RP:ToggleLogs`, `RP:RefreshLogs`).
- `Planner.lua`
  - Wochen-Planer für Raidleads (`RP:OpenPlanner`, `RP:RefreshPlanner`).
  - Visualisiert Spieler-Rollen vs. Raids einer Woche.
  - Nutzt dieselben Raid-/Signup-Daten wie der Kalender.
- `State.lua`
  - Hilfsfunktion `RP:SetRaidState(raidId, newState, broadcast)`:
    - Setzt `raid.state` (`"PLANNED"`, `"CONFIRMED"`, `"CANCELLED"`).
    - Speichert den Raid, broadcastet optional, schreibt Logeintrag.
    - Frischt Kalender, Detail-View und Planner bei Bedarf neu auf.

## Wichtige Einstiegspunkte

- **Kalender öffnen:** `RP:ToggleMainFrame()` (in `UI.lua`).
- **Raid-Planer öffnen:** `RP:OpenPlanner()` (in `Planner.lua`).
- **Raid-Status ändern:** `RP:SetRaidState()` (in `State.lua`).

