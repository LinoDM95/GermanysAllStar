---------------------------------------------------------------------------
-- GuildStockPlanner – ExportImport.lua
-- Serialisiert/deserialisiert Rezepte als kopierbare Strings.
-- Unterstuetzt endlos verschachtelte Sub-Materialien.
-- Format:
--   R:mainItemID:desiredStock:yield   – Rezept-Header
--   M:itemID:qty                      – Material (Tiefe 0)
--   S:depth:itemID:qty                – Sub-Material (Tiefe >= 1)
-- Abwaertskompatibel: alte Exports ohne S:-Zeilen werden normal gelesen.
---------------------------------------------------------------------------
local _, ADDON = ...

ADDON.ExportImport = {}
local EI = ADDON.ExportImport

local HEADER  = "GSP_EXPORT_V1"
local FOOTER  = "GSP_END"

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------

--- Gibt einen kopierbaren String mit allen Rezepten zurueck.
function EI:Export()
    local recipes = ADDON.DB:GetRecipes()
    local lines   = { HEADER }

    for _, recipe in pairs(recipes) do
        table.insert(lines, string.format("R:%d:%d:%d",
            recipe.mainItemID,
            recipe.desiredStock or 0,
            math.max(1, recipe.yield or 1)))

        -- Rekursives Exportieren aller Material-Ebenen
        local function addMats(mats, depth)
            for _, mat in ipairs(mats) do
                if mat.itemID and mat.qty then
                    if depth == 0 then
                        table.insert(lines, string.format("M:%d:%d",
                            mat.itemID, mat.qty))
                    else
                        table.insert(lines, string.format("S:%d:%d:%d",
                            depth, mat.itemID, mat.qty))
                    end
                    if mat.subMats then
                        addMats(mat.subMats, depth + 1)
                    end
                end
            end
        end
        if recipe.mats then addMats(recipe.mats, 0) end
    end

    table.insert(lines, FOOTER)
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Import
---------------------------------------------------------------------------

--- Parst einen Export-String.
--- @return success boolean
--- @return recipes_or_error table|string  Bei Erfolg: { [mainItemID] = recipe, ... }
function EI:Import(str)
    if not str or str == "" then
        return false, "Leerer String."
    end

    local lines = { strsplit("\n", str) }

    -- Erstes Element trimmen und pruefen
    local first = strtrim(lines[1] or "")
    if first ~= HEADER then
        return false, "Ungueltiges Format (Header fehlt)."
    end

    local recipes       = {}
    local currentRecipe = nil
    -- depthStack[d+1].list = Ziel-Tabelle, depthStack[d+1].lastEntry = letzter Eintrag
    local depthStack    = {}

    for i = 2, #lines do
        local line = strtrim(lines[i] or "")
        if line == FOOTER then break end

        -- Rezept-Header
        local rID, rStock, rYield = line:match("^R:(%d+):(%d+):(%d+)$")
        if rID then
            currentRecipe = {
                mainItemID   = tonumber(rID),
                desiredStock = tonumber(rStock) or 0,
                yield        = math.max(1, tonumber(rYield) or 1),
                mats         = {},
            }
            recipes[currentRecipe.mainItemID] = currentRecipe
            depthStack = { { list = currentRecipe.mats, lastEntry = nil } }
        else
            -- Material (Tiefe 0)
            local mID, mQty = line:match("^M:(%d+):(%d+)$")
            if mID and currentRecipe then
                local entry = { itemID = tonumber(mID), qty = tonumber(mQty) or 1 }
                table.insert(currentRecipe.mats, entry)
                depthStack[1] = { list = currentRecipe.mats, lastEntry = entry }
            else
                -- Sub-Material (Tiefe >= 1)
                local sDepth, sID, sQty = line:match("^S:(%d+):(%d+):(%d+)$")
                if sDepth and currentRecipe then
                    local depth = tonumber(sDepth)
                    local entry = { itemID = tonumber(sID), qty = tonumber(sQty) or 1 }

                    -- Eltern-Ebene vorbereiten
                    if depth > 0 then
                        local parent = depthStack[depth]
                        if parent and parent.lastEntry then
                            if not parent.lastEntry.subMats then
                                parent.lastEntry.subMats = {}
                            end
                            depthStack[depth + 1] = {
                                list = parent.lastEntry.subMats,
                                lastEntry = nil,
                            }
                        end
                    end

                    local target = depthStack[depth + 1]
                    if target then
                        table.insert(target.list, entry)
                        target.lastEntry = entry
                    end
                end
            end
        end
    end

    return true, recipes
end
