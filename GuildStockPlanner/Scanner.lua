---------------------------------------------------------------------------
-- GuildStockPlanner – Scanner.lua
-- Gildenbank-Scan als Event-getriebene State Machine
---------------------------------------------------------------------------
local _, ADDON = ...

ADDON.Scanner = {}
local Scanner = ADDON.Scanner

---------------------------------------------------------------------------
-- States
---------------------------------------------------------------------------
local STATE_IDLE     = "Idle"
local STATE_SCANNING = "Scanning"
local STATE_DONE     = "Done"
local STATE_ERROR    = "Error"

Scanner.state            = STATE_IDLE
Scanner.statusText       = STATE_IDLE
Scanner.bankCounts       = {}
Scanner.currentTab       = 0
Scanner.totalTabs        = 0
Scanner.retryCount       = 0
Scanner.maxRetries       = 2
Scanner.waitingForEvent  = false
Scanner.bankOpen         = false

---------------------------------------------------------------------------
-- Event-Frame
---------------------------------------------------------------------------
local scanFrame = CreateFrame("Frame")
scanFrame:RegisterEvent("GUILDBANKFRAME_OPENED")
scanFrame:RegisterEvent("GUILDBANKFRAME_CLOSED")
-- Einige TBC-Clients feuern stattdessen GUILD_BANK_UPDATE oder andere Varianten.
-- Wir registrieren mehrere Events als Fallback.
scanFrame:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")

scanFrame:SetScript("OnEvent", function(_, event)
    if event == "GUILDBANKBAGSLOTS_CHANGED" then
        -- Sekundaerer Indikator: Bank ist offen, wenn Slot-Events kommen.
        if not Scanner.bankOpen then
            Scanner.bankOpen = true
            ADDON:Debug("Gildenbank offen (via GUILDBANKBAGSLOTS_CHANGED).")
        end
        -- Wenn wir gerade scannen und auf Daten warten, verarbeiten
        if Scanner.scanning and Scanner.waitingForEvent then
            Scanner:OnBagSlotsChanged()
        end
    elseif event == "GUILDBANKFRAME_OPENED" then
        Scanner.bankOpen = true
        ADDON:Debug("Gildenbank geoeffnet (GUILDBANKFRAME_OPENED).")
    elseif event == "GUILDBANKFRAME_CLOSED" then
        Scanner.bankOpen = false
        ADDON:Debug("Gildenbank geschlossen.")
        if Scanner.scanning then
            Scanner:Abort("Gildenbank geschlossen.")
        end
    end
end)

---------------------------------------------------------------------------
-- Interne Helfer
---------------------------------------------------------------------------

function Scanner:SetState(state, detail)
    self.state = state
    self.statusText = detail and (state .. ": " .. detail) or state
    ADDON:Debug("Scanner =>", self.statusText)
    if ADDON.UI and ADDON.UI.UpdateScanStatus then
        ADDON.UI:UpdateScanStatus()
    end
end

function Scanner:Abort(reason)
    self.scanning        = false
    self.waitingForEvent = false
    self:SetState(STATE_ERROR, reason or "Abgebrochen")
    ADDON:Print("Scan abgebrochen: " .. (reason or "unbekannt"))
end

--- Prueft ob die Gildenbank tatsaechlich offen ist.
--- Nutzt zuerst das Event-Flag, dann Fallback ueber das GuildBankFrame.
function Scanner:IsBankOpen()
    -- 1) Event-Flag
    if self.bankOpen then return true end
    -- 2) Fallback: Prüfe ob das UI-Frame sichtbar ist
    --    GuildBankFrame existiert erst nach dem Laden von Blizzard_GuildBankUI
    if GuildBankFrame and GuildBankFrame:IsShown() then
        self.bankOpen = true
        ADDON:Debug("Gildenbank offen erkannt (Frame-Fallback).")
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Oeffentliche API
---------------------------------------------------------------------------

function Scanner:StartScan()
    if self.state == STATE_SCANNING then
        ADDON:Print("Scan laeuft bereits.")
        return
    end
    if not ADDON:GetProfileKey() then
        ADDON:Print("Du bist in keiner Gilde.")
        self:SetState(STATE_ERROR, "Keine Gilde")
        return
    end
    if not self:IsBankOpen() then
        ADDON:Print("Bitte oeffne zuerst die Gildenbank.")
        self:SetState(STATE_ERROR, "Bank nicht offen")
        return
    end

    local numTabs = GetNumGuildBankTabs()
    if not numTabs or numTabs == 0 then
        ADDON:Print("Keine Gildenbank-Tabs vorhanden.")
        self:SetState(STATE_ERROR, "Keine Tabs")
        return
    end

    self.totalTabs  = numTabs
    self.currentTab = 0
    self.bankCounts = {}
    self.retryCount = 0
    self.scanning   = true
    self:SetState(STATE_SCANNING, "Starte...")
    self:ScanNextTab()
end

function Scanner:GetState()
    return self.state
end

function Scanner:GetStatusText()
    return self.statusText
end

---------------------------------------------------------------------------
-- Scan-Logik (tab-weise)
---------------------------------------------------------------------------

function Scanner:ScanNextTab()
    self.currentTab = self.currentTab + 1
    if self.currentTab > self.totalTabs then
        self:FinishScan()
        return
    end

    -- Tab sichtbar?
    local _, _, isViewable = GetGuildBankTabInfo(self.currentTab)
    if not isViewable then
        ADDON:Debug("Tab", self.currentTab, "nicht sichtbar – ueberspringe.")
        C_Timer.After(0.05, function() Scanner:ScanNextTab() end)
        return
    end

    self:SetState(STATE_SCANNING, "Tab " .. self.currentTab .. "/" .. self.totalTabs)
    self.waitingForEvent = true
    self.retryCount = 0
    QueryGuildBankTab(self.currentTab)
    self:StartTimeout()
end

function Scanner:StartTimeout()
    local expectedTab = self.currentTab
    C_Timer.After(3, function()
        if Scanner.currentTab ~= expectedTab then return end
        if not Scanner.waitingForEvent then return end
        Scanner:OnTimeout()
    end)
end

function Scanner:OnTimeout()
    if not self.waitingForEvent then return end
    self.retryCount = self.retryCount + 1
    if self.retryCount > self.maxRetries then
        ADDON:Print("Timeout bei Tab " .. self.currentTab .. " – ueberspringe.")
        self.waitingForEvent = false
        C_Timer.After(0.1, function() Scanner:ScanNextTab() end)
        return
    end
    ADDON:Debug("Retry", self.retryCount, "fuer Tab", self.currentTab)
    QueryGuildBankTab(self.currentTab)
    self:StartTimeout()
end

function Scanner:OnBagSlotsChanged()
    if not self.waitingForEvent then return end
    self.waitingForEvent = false
    -- Kurze Verzoegerung damit alle Slot-Daten da sind
    local tab = self.currentTab
    C_Timer.After(0.15, function()
        Scanner:ReadTabSlots(tab)
        C_Timer.After(0.05, function()
            Scanner:ScanNextTab()
        end)
    end)
end

---------------------------------------------------------------------------
-- Slots lesen
---------------------------------------------------------------------------
local MAX_GUILDBANK_SLOTS = 98

function Scanner:ReadTabSlots(tab)
    for slot = 1, MAX_GUILDBANK_SLOTS do
        local texture, itemCount = GetGuildBankItemInfo(tab, slot)
        if texture then
            local link = GetGuildBankItemLink(tab, slot)
            if link then
                local itemID = ADDON:ParseItemID(link)
                if itemID then
                    self.bankCounts[itemID] = (self.bankCounts[itemID] or 0) + (itemCount or 0)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Scan beenden
---------------------------------------------------------------------------

function Scanner:FinishScan()
    self.scanning        = false
    self.waitingForEvent = false
    ADDON.DB:SaveScanResults(self.bankCounts)

    local count = 0
    for _ in pairs(self.bankCounts) do count = count + 1 end

    self:SetState(STATE_DONE, date("%H:%M:%S"))
    ADDON:Print("Scan abgeschlossen – " .. count .. " verschiedene Items gefunden.")

    local settings = ADDON.DB:GetSettings()
    if settings.autoRecalcAfterScan and ADDON.UI and ADDON.UI.RefreshFarmTab then
        ADDON.UI:RefreshFarmTab()
    end

    -- Bank-Scan an alle Gildenmitglieder broadcasten
    local scan = ADDON.DB:GetLastScan()
    if ADDON.Sync and scan.ts and scan.ts > 0 then
        ADDON.Sync:BroadcastBankScan(self.bankCounts, scan.ts)
    end
end
