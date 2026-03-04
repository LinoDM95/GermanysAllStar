---------------------------------------------------------------------------
-- Raidplaner – State.lua
-- Hilfsfunktionen fuer Raid-Status (bestaetigt / abgesagt) inkl. Kalenderfarbe.
---------------------------------------------------------------------------
local _, ADDON = ...

ADDON.Raidplaner = ADDON.Raidplaner or {}
local RP = ADDON.Raidplaner

--- Setzt den Status eines Raids und aktualisiert Timestamps + UI.
-- @param raidId   ID des Raids
-- @param newState String: "PLANNED" (offen), "CONFIRMED", "CANCELLED"
-- @param broadcast boolean – ob Aenderung ueber Sync verbreitet werden soll
function RP:SetRaidState(raidId, newState, broadcast)
    local raid = ADDON.RaidplanerDB:GetRaid(raidId)
    if not raid then return end

    raid.state     = newState or "PLANNED"
    raid.updatedAt = time()

    ADDON.RaidplanerDB:SaveRaid(raid)

    if broadcast and ADDON.RaidplanerSync and ADDON.RaidplanerSync.BroadcastRaid then
        ADDON.RaidplanerSync:BroadcastRaid(raid)
    end

    -- Optional: Log-Eintrag
    local actor = UnitName("player") or "?"
    local label = (raid.raidName or raid.raidKey or "?") .. " am " .. (raid.date or "?")
    local fromText, toText = "", ""
    if raid.time and raid.time ~= "" then
        fromText, toText = (ADDON.Raidplaner.FormatRaidTimeRange or function(t) return t, nil end)(raid.time)
    end
    local timeLabel = fromText
    if toText and toText ~= "" then
        timeLabel = fromText .. " - " .. toText
    end

    local stateLabel = (newState == "CONFIRMED" and "best\u00e4tigt")
        or (newState == "CANCELLED" and "abgesagt")
        or "offen"

    if ADDON.RaidplanerDB.AddLog then
        ADDON.RaidplanerDB:AddLog(string.format(
            "%s hat den Raid \"%s\" (%s) als %s markiert.",
            actor,
            label,
            timeLabel or "?",
            stateLabel
        ))
    end

    -- UI refreshen, falls Fenster offen sind
    if RP.rpFrame and RP.rpFrame:IsShown() then
        RP:RefreshCalendar()
    end
    if RP.detailFrame and RP.detailFrame:IsShown() and RP.detailFrame.currentRaidId == raidId then
        RP:ShowRaidDetail(raidId)
    end
    if RP.plannerFrame and RP.plannerFrame:IsShown() and RP.RefreshPlanner then
        RP:RefreshPlanner()
    end
end

