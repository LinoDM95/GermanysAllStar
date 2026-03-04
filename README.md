# GermanysAllStar

**Germany's AllStar Gilden-Toolkit** – Alle Gilden-Apps an einem Ort.

## Installation

1. Kopiere den Ordner `GermanysAllStar` in dein WoW AddOns-Verzeichnis:

   ```
   World of Warcraft\_classic_/Interface/AddOns/GermanysAllStar/
   ```

2. **"Load out of date AddOns"** aktivieren (Interface 20504).

3. Falls das alte `GuildStockPlanner`-Addon installiert war: **deaktivieren/loeschen**.
   Gespeicherte Rezepte in `GuildStockPlannerDB` bleiben erhalten.

4. WoW neustarten oder `/reload`.

## Slash-Befehl

| Befehl            | Beschreibung                        |
|--------------------|-------------------------------------|
| `/ga`             | Hub-Fenster oeffnen (einziger Einstiegspunkt) |
| `/ga debug on`    | Debug-Ausgaben aktivieren           |
| `/ga debug off`   | Debug-Ausgaben deaktivieren         |

`/gsp` ist ein Alias fuer `/ga` – alle Apps werden ausschliesslich ueber das Hub geoeffnet.

## Hub-Fenster

Das Hub zeigt eine Uebersicht aller Gilden-Apps mit dem **Gildenwappen als Hintergrund**.

### Zugriffssteuerung (Whitelist)

- **Gildenmeister & Offiziere** (Rang 0 und 1) haben **immer** vollen Zugriff auf alle Apps.
- **Alle anderen** Mitglieder sind standardmaessig fuer alle Apps **gesperrt**.
- Offiziere koennen ueber den Button **"Rechteverwaltung"** einzelnen Mitgliedern Zugriff auf einzelne Apps erteilen.
- Die Rechteverwaltung ist fuer Nicht-Offiziere **komplett unsichtbar**.
- Rechteaenderungen werden automatisch ueber den GUILD Addon-Channel an alle synchronisiert.

## GuildStockPlanner

### Scan-Ablauf

1. Gildenbank am NPC oeffnen.
2. Im GuildStockPlanner auf **"Scan (Gildenbank)"** klicken.
3. Das AddOn liest alle Tabs nacheinander.
4. Ergebnis: Item-Counts + Zeitstempel gespeichert.

### Rezepte verwalten

- Items per **Shift-Klick**, **ItemID** oder **Itemname** eingeben.
- Bearbeiten / Loeschen pro Zeile.

### Rezept-Backup (Export / Import)

Im GuildStockPlanner unter **Einstellungen → Export (Backup)**:
- Alle Rezepte als kopierbaren Text-String exportieren.
- Jederzeit unter **Import (Wiederherstellen)** einfuegen.

### Rezept-Synchronisation

Automatische stille Synchronisation ueber den GUILD Addon-Channel:
- **Beim Login:** Fingerprint-Abgleich nach 8 Sekunden.
- **Merge-Regel:** Neuester Zeitstempel gewinnt.
- **Live:** Jede Aenderung wird sofort gesendet.
- **Manuell:** "Sync Rezepte"-Button im GuildStockPlanner.

### Sync-Log

Im Tab "Sync-Log" siehst du wer wann was hinzugefuegt, geloescht oder synchronisiert hat.

## Dateistruktur (Projekt-Overview)

```
GermanysAllStar/
  GermanysAllStar.toc         (Lade-Reihenfolge, SavedVariables)

  Core/
    Bootstrap.lua             (Addon-Namespace, Utilities, Hub-DB, Permissions)
    Hub/
      UI.lua                  (Hub-Launcher, Rechteverwaltung, App-Auswahl)

  Textures/
    logo.tga                  (Gildenwappen 512x512, Wasserzeichen fuer UIs)

  Modules/
    GuildStockPlanner/        (Modul: Gildenbank-Planer)
      README.md
      Data/
        DB.lua                (Datenmodell, Persistenz, Sync-Log)
      Services/
        Scanner.lua           (Gildenbank-Scan)
        Calculator.lua        (Berechnung fehlender Materialien)
        ExportImport.lua      (String Export/Import Backup)
        Sync.lua              (Guild-Channel Rezept-Sync)
      UI/
        Main.lua              (GuildStockPlanner UI, Tabs, How-To)

    Raidplaner/               (Modul: Raid-Kalender & Roster)
      README.md
      Data/
        RaidData.lua          (Statischer Datensatz: Raids, Specs, Rollen)
        DB.lua                (Datenmodell, Persistenz, Tombstones, Raid-Logs)
      Services/
        Sync.lua              (Gildenweiter Raid-/Signup-Sync)
        Planner.lua           (Wochen-Planer-Ansicht fuer Raidleads)
        State.lua             (Hilfsfunktionen fuer Raid-Status, UI-Refresh)
      UI/
        Theme.lua             (Theme-Hooks fuer Backdrops/Labels)
        Main.lua              (Kalender, Detailfenster, Signup, Roster, Logs)

    GuildStocks/              (Modul: Gildenbestands-Viewer)
      README.md
      UI/
        Main.lua              (Anzeige aller Gildenbank-Bestände)
```

## Lizenz

Frei verwendbar. Keine Gewaehr.
