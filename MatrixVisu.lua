-- --- CONFIGURATION ---
local mod = peripheral.wrap("top")
local mon = peripheral.wrap("right")
local chanReceiveData = 0
local chanForceProd = 1
local chanManageThresholds = 2

local x, y = mon.getSize() -- 29, 12

-- --- VARIABLES D'ÉTAT (Globales pour les coroutines) ---

local IMEnergy = 0
local IMEnergyMax = 0
local IMDiff = 0
local isProducing = false

-- --- PARAMÈTRES GRAPHIQUES ---
local bgColor = colors.black
local progBarStartX = 2
local progBarStartY = 3
local progBarWidth = 3
local progBarLength = x - 2

local fourStartX = 2
local fourStartY = 10
local textForceON = "FORCE-ON"
local textForceOFF = "FORCE-OFF"

-- Initialisation de l'écran
mod.open(chanReceiveData)
mod.open(chanForceProd)
mod.open(chanManageThresholds)
mon.setTextScale(1)

-- --- FONCTIONS OUTILS ---

function formatEnergy(n)
    if not n or n == 0 then return "0 FE" end
    
    -- On stocke si le nombre est négatif
    local isNegative = n < 0
    -- On travaille avec la valeur absolue (positive)
    local val = math.abs(n)
    
    local symbols = {"", "k", "M", "G", "T", "P", "E"}
    local section = 1
    
    while val >= 1000 and section < #symbols do
        val = val / 1000
        section = section + 1
    end
    
    -- On remet le signe moins si nécessaire au moment du formatage
    local sign = isNegative and "-" or ""
    return string.format("%s%.2f %sFE", sign, val, symbols[section])
end

local function drawProgBar(startX, startY, length, height, color)
    local line = string.rep(" ", length)
    local blitColor = string.rep(color, length)
    for i = 0, height - 1 do
        mon.setCursorPos(startX, startY + i)
        mon.blit(line, blitColor, blitColor)
    end
end

-- --- COROUTINE 1 : RÉCEPTION DES DONNÉES ---
local function updateData()
    while true do
        local _, _, chanRecData, _, message, _ = os.pullEvent("modem_message")
        if chanRecData == chanReceiveData then
            -- Mise à jour des variables
            IMEnergy    = message.IMEnergy
            IMEnergyMax = message.IMEnergyMax
            IMDiff      = message.IMDiff
            isProducing = message.isProducing
        end
    end
end

-- --- COROUTINE 2 : GESTION TACTILE ---
local function handleButton()
    while true do
        local _, _, touchX, touchY = os.pullEvent("monitor_touch")
        
        -- Détection bouton ON
        if touchY == fourStartY + 1 and touchX >= fourStartX and touchX <= fourStartX + #textForceON then
            mod.transmit(chanForceProd, chanForceProd, {isProducing = true})
        
        -- Détection bouton OFF
        elseif touchY == fourStartY + 1 and touchX >= (fourStartX + #textForceON + 1) and touchX <= (fourStartX + #textForceON + 1 + #textForceOFF) then
            mod.transmit(chanForceProd, chanForceProd, {isProducing = false})
        end
    end
end

-- --- COROUTINE 3 : DESSIN UNIQUE (BOUCLE D'AFFICHAGE) ---
local function updateScreen()
    while true do
        -- 1. Nettoyage
        mon.setBackgroundColor(bgColor)
        mon.clear()

        -- 2. Titre
        mon.setCursorPos(1, 1)
        mon.setTextColor(colors.blue)
        mon.write("MatrixVisu by Brendan")

        -- 3. Barre de progression
        mon.setCursorPos(3, progBarStartY - 1)
        mon.setTextColor(colors.white)
        mon.write("Induction Matrix")

        -- Barre de fond (Gris)
        drawProgBar(progBarStartX, progBarStartY, progBarLength, progBarWidth, "7") -- Gris pour le fond
        
        -- Calcul du remplissage
        local percentage = math.max(0, math.min(1, IMEnergy / IMEnergyMax))
        local fillWidth = math.floor(percentage * progBarLength)
        
        if fillWidth > 0 then
            drawProgBar(progBarStartX, progBarStartY, fillWidth, progBarWidth, "0") -- Blanc pour le remplissage
        end

        -- 4. Stats sous la barre
        mon.setCursorPos(3, progBarStartY + progBarWidth + 1)
        mon.setTextColor(colors.white)

        -- Calcul Pourcentage
        local Percent = math.floor((IMEnergy / IMEnergyMax) * 100)

        mon.write(formatEnergy(IMEnergy) .. " / " .. formatEnergy(IMEnergyMax))
        
        mon.setCursorPos(3, progBarStartY + progBarWidth + 2)
        mon.setTextColor(colors.white)
        mon.write("Stock: "..Percent.."%")
        if IMDiff >= 0 then
            mon.write(" | ")
            mon.setTextColor(colors.green)
            mon.write("+" .. formatEnergy(IMDiff) .. "/t")
        else
            mon.write(" | ")
            mon.setTextColor(colors.red)
            mon.write(formatEnergy(IMDiff) .. "/t")
        end

        -- 5. Section Fours
        mon.setCursorPos(fourStartX, fourStartY)
        mon.setTextColor(colors.white)
        mon.write("Fours : ")
        
        if isProducing == false then
            mon.setTextColor(colors.red)
            mon.write("INACTIF")
        elseif isProducing == true then
            mon.setTextColor(colors.green)
            mon.write("ACTIF")
        end

        -- Dessin des boutons physiques (Blit pour les couleurs de fond)
        mon.setCursorPos(fourStartX, fourStartY + 1)
        mon.blit(textForceON, "00000000", "dddddddd") -- Fond Vert clair (d)
        
        mon.setCursorPos(fourStartX + #textForceON + 1, fourStartY + 1)
        mon.blit(textForceOFF, "000000000", "eeeeeeeee") -- Fond Rouge clair (e)

        -- 6. Pause pour laisser respirer le processeur
        sleep(0.5)
    end
end

-- --- LANCEMENT ---
term.clear()
term.setCursorPos(1,1)
print("Monitoring Matrix en cours...")

-- Utilisation de waitForAny pour pouvoir arrêter le programme proprement
parallel.waitForAny(updateData, handleButton, updateScreen)