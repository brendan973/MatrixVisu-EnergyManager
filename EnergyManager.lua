--==[CONFIG]==--

local startProd = 1 -- % activation automatique
local stopProd = 6 -- % désactivation automatique

local chanSendData = 0
local chanForceProd = 1
local chanManageThresholds = 2

--=====[]=====--

local isProducing = false -- Etat de la production
local data = { cur = 0, max = 1, input = 0, output = 0 } -- Initialisation sécurisée
local forced = false

-- On met les wraps dans une fonction pour pouvoir les relancer si besoin
local function getMatrix()
    return peripheral.wrap("bottom")
end

local function getModem()
    return peripheral.wrap("top")
end

local matrix = getMatrix()
local mod = getModem()

term.clear()

local x, y = term.getSize()

--==[FUNCTIONS]==--

function writeNL(text)
    local x1, y1 = term.getCursorPos()
    term.setCursorPos(1, y1)
    term.write(text)
    if y1 >= y then 
        term.scroll(1) 
        term.setCursorPos(1, y)
    else
        term.setCursorPos(1, y1 + 1)
    end
end

function formatEnergy(n)
    local symbols = {"", "k", "M", "G", "T", "P", "E"}
    local section = 1
    while n >= 1000 and section < #symbols do
        n = n / 1000
        section = section + 1
    end
    -- Retourne le nombre avec 2 décimales et son symbole
    return string.format("%.2f %sFE", n, symbols[section])
end

local function getMatrixStockPercent()
    return ((data.cur / data.max) * 10)
end

-- --- COROUTINE1: ENVOIE DES DONNÉES A L'ECRAN PRINCIPAL ---
local function sendData()
    mod.open(chanSendData) -- Canal 1
    while true do
        -- On utilise pcall pour tenter de lire la matrix
        success, data = pcall(function()
            -- On vérifie si la matrix est toujours là
            if not matrix then error("Matrix missing") end
            
            return {
                max = matrix.getMaxEnergy() / 2.5,
                cur = matrix.getEnergy() / 2.5,
                input = matrix.getLastInput() / 2.5,
                output = matrix.getLastOutput() / 2.5
            }
        end)
    
        if success then
            -- Tout va bien, on calcule et on envoie
            local diff = math.floor(data.input - data.output)
            local packet = {
                IMEnergy = data.cur,
                IMEnergyMax = data.max,
                IMDiff = diff,
                isProducing = isProducing
            }
            mod.transmit(chanSendData, chanSendData, packet)
            
            -- local prefix = diff >= 0 and "+" or ""
            -- writeNL("Transmitted: "..formatEnergy(data.cur).." | "..formatEnergy(data.max).." | Flux: "..formatEnergy(diff))
        else
            -- Erreur détectée (Chunk déchargé, matrix cassée, etc.)
            term.clear()
            term.setCursorPos(1,1)
            writeNL("ERREUR: Matrix introuvable")
            writeNL("Tentative de reconnexion...")
            
            -- On essaie de re-wrap au cas où le bloc est revenu
            matrix = getMatrix()
            mod = getModem()
        end
        
        os.sleep(1)
    end
end

-- --- COROUTINE2: GESTION DE L'ACTIVATION DE LA PRODUCTION ---
local function manageProduction()
    while true do
        local percent = getMatrixStockPercent()

        -- Si on a atteint les limites, on désactive le mode "forcé"
        if percent <= startProd or percent >= stopProd then
            forced = false
        end

        -- On n'utilise l'automatisme QUE si on n'est pas en mode forcé
        if not forced then
            if percent <= startProd then
                isProducing = true
            elseif percent >= stopProd then
                isProducing = false
            end
        end

        redstone.setOutput("right",isProducing)

        os.sleep(1)
    end
end

-- --- COROUTINE3: GESTION DES NIVEAUS D'ACTIVATION ---
local function manageRemoteThresholds()
    mod.open(chanManageThresholds)
    while true do
        local _, _, channel, _, message = os.pullEvent("modem_message")
        if channel == chanManageThresholds and type(message) == "table" then
            startProd = message.start or startProd
            stopProd = message.stop or stopProd
            writeNL("Seuils MAJ: " .. startProd .. "% / " .. stopProd .. "%")
        end
    end
end

local function manageRemoteCommands()
    mod.open(chanForceProd)
    while true do
        local _, _, channel, _, message = os.pullEvent("modem_message")
        if channel == chanForceProd and type(message) == "table" then
            isProducing = message.isProducing
            forced = true -- ON BLOQUE L'AUTOMATISME
            writeNL("Commande forcee recue : " .. tostring(isProducing))
        end
    end
end

term.clear()
term.setCursorPos(1,1)
print("Monitoring Matrix en cours...")

parallel.waitForAny(sendData, manageProduction, manageRemoteThresholds, manageRemoteCommands)