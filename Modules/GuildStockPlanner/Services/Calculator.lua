---------------------------------------------------------------------------
-- GuildStockPlanner – Calculator.lua
-- Reine Berechnungsfunktionen (kein UI, keine Events)
-- Berechnet fehlende Hauptitems und Materialien.
-- Unterstuetzt endlos verschachtelte Sub-Materialien (beliebige Tiefe).
-- Sub-Materialien werden per Delta-Iteration korrekt aufgerechnet,
-- auch wenn ein Material sowohl direkt als auch als Sub-Material vorkommt.
---------------------------------------------------------------------------
local _, ADDON = ...

ADDON.Calculator = {}
local Calc = ADDON.Calculator

--- Berechnet fehlende Materialien und Hauptitems.
--- @return missingMats  table  { {itemID, required, inBank, missing, [craftable, subMats]}, ... }
--- @return missingMains table  { {itemID, desired, inBank, missing}, ... }
function Calc:Calculate()
    local recipes    = ADDON.DB:GetRecipes()
    local scan       = ADDON.DB:GetLastScan()
    local bankCounts = scan.bankCounts or {}

    local missingMains = {}

    ---------------------------------------------------------------------------
    -- Schritt 0: Sub-Material-Definitionen aus allen Rezepten sammeln
    --   subDefs[matItemID] = { { itemID = X, ratio = Y }, ... }
    --   ratio = sub.qty / mat.qty  (Bedarf pro 1 Einheit des Eltern-Mats)
    --   Rekursiv fuer beliebige Tiefe
    ---------------------------------------------------------------------------
    local subDefs = {}

    local function scanSubDefs(mats)
        for _, mat in ipairs(mats) do
            if mat.itemID and (mat.qty or 0) > 0 and mat.subMats then
                if not subDefs[mat.itemID] then
                    subDefs[mat.itemID] = {}
                    for _, sub in ipairs(mat.subMats) do
                        if sub.itemID and (sub.qty or 0) > 0 then
                            table.insert(subDefs[mat.itemID], {
                                itemID = sub.itemID,
                                ratio  = sub.qty / mat.qty,
                            })
                        end
                    end
                end
                -- Rekursiv tiefere Ebenen scannen
                for _, sub in ipairs(mat.subMats) do
                    if sub.subMats then
                        scanSubDefs({ sub })
                    end
                end
            end
        end
    end

    for _, recipe in pairs(recipes) do
        if recipe.mats then scanSubDefs(recipe.mats) end
    end

    ---------------------------------------------------------------------------
    -- Schritt 1: Direkte Material-Bedarfe aus allen Rezepten aggregieren
    ---------------------------------------------------------------------------
    local matData = {} -- [matItemID] = { total = N }

    for mainItemID, recipe in pairs(recipes) do
        local mainInBank  = bankCounts[mainItemID] or 0
        local desired     = recipe.desiredStock or 0
        local yld         = math.max(1, recipe.yield or 1)
        local missingMain = math.max(0, desired - mainInBank)

        if missingMain > 0 then
            table.insert(missingMains, {
                itemID  = mainItemID,
                desired = desired,
                inBank  = mainInBank,
                missing = missingMain,
            })

            local craftsNeeded = math.ceil(missingMain / yld)

            if craftsNeeded > 0 and recipe.mats then
                for _, mat in ipairs(recipe.mats) do
                    if mat.itemID and (mat.qty or 0) > 0 then
                        if not matData[mat.itemID] then
                            matData[mat.itemID] = { total = 0 }
                        end
                        matData[mat.itemID].total = matData[mat.itemID].total
                            + craftsNeeded * mat.qty
                    end
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Schritt 2: Sub-Materialien iterativ aufrechnen (Delta-Verfahren)
    --   Jedes Material wird erneut verarbeitet wenn sich sein Gesamtbedarf
    --   erhoht hat. Nur die DIFFERENZ wird fuer Sub-Materialien berechnet.
    --   So werden auch verschachtelte Ketten korrekt aufgerechnet.
    ---------------------------------------------------------------------------
    local lastProcessed = {} -- [matID] = total_beim_letzten_Durchlauf

    for _ = 1, 20 do -- Sicherheitslimit
        local newAdditions = {}
        local hasNew = false

        for matID, data in pairs(matData) do
            if subDefs[matID] then
                local prevTotal = lastProcessed[matID] or 0
                if data.total > prevTotal then
                    lastProcessed[matID] = data.total

                    local inBank       = bankCounts[matID] or 0
                    local prevMissing  = math.max(0, prevTotal - inBank)
                    local currMissing  = math.max(0, data.total - inBank)
                    local deltaMissing = currMissing - prevMissing

                    if deltaMissing > 0 then
                        for _, def in ipairs(subDefs[matID]) do
                            local subNeeded = math.ceil(deltaMissing * def.ratio)
                            newAdditions[def.itemID] =
                                (newAdditions[def.itemID] or 0) + subNeeded
                            hasNew = true
                        end
                    end
                end
            end
        end

        if not hasNew then break end

        for subID, amount in pairs(newAdditions) do
            if not matData[subID] then
                matData[subID] = { total = 0 }
            end
            matData[subID].total = matData[subID].total + amount
        end
    end

    ---------------------------------------------------------------------------
    -- Schritt 3: Fehlende Materialien mit Tooltip-Daten zusammenstellen
    ---------------------------------------------------------------------------
    local missingMats = {}

    for matID, data in pairs(matData) do
        local inBank  = bankCounts[matID] or 0
        local missing = math.max(0, data.total - inBank)
        if missing > 0 then
            local entry = {
                itemID   = matID,
                required = data.total,
                inBank   = inBank,
                missing  = missing,
            }

            -- Tooltip: unmittelbare Sub-Materialien (nur 1 Ebene)
            if subDefs[matID] then
                entry.craftable = true
                entry.subMats   = {}
                for _, def in ipairs(subDefs[matID]) do
                    table.insert(entry.subMats, {
                        itemID   = def.itemID,
                        required = math.ceil(missing * def.ratio),
                    })
                end
                table.sort(entry.subMats, function(a, b)
                    return a.required > b.required
                end)
            end

            table.insert(missingMats, entry)
        end
    end

    -- Sortiere nach groesstem Fehlbetrag absteigend
    table.sort(missingMats,  function(a, b) return a.missing > b.missing end)
    table.sort(missingMains, function(a, b) return a.missing > b.missing end)

    return missingMats, missingMains
end
