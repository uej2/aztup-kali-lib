local library = loadstring(game:HttpGet("https://raw.githubusercontent.com/laagginq/ui-libraries/main/aztup/src.lua"))()

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local NPCSFolder = Workspace:WaitForChild("NPCSFolder")
local BloodFolder = Workspace:WaitForChild("BloodFolder")

-- ESP Variables
local espEnabled = false
local stopEspLoop = false
local espPlayerAddedConnection = nil
local espCharacterAddedConnections = {}
local mouseUnlockEnabled = false
local aimlockWallCheck = false
local mouseUnlockConnection = nil
local rolesLockedByDistance = false
local selectedHitbox = "Head" -- default
local lockedDistanceRoles = {}
local playersMatchingHints = {}
local hintTextConnection = nil
local firstVigilanteTracker = {}
local distanceThreshold = 250

-- Weapon Lists
local killerWeapons = {
    ["CharcoalSteel JS-22"] = true, ["Pretty Pink RR-LCP"] = true, ["JS2-BondsDerringy"] = true,
    ["GILDED"] = true, ["Kamatov"] = true, ["JS2-Derringy"] = true, ["JS-22"] = true,
    ["NGO"] = true, ["Throwing Dagger"] = true, ["SoundMaker"] = true, ["SoundMakerSlower"] = true,
    ["RR-LightCompactPistolS"] = true, ["J9-Mereta"] = true, ["RY's GG-17"] = true,
    ["RR-LCP"] = true, ["JS1 Competitor"] = true, ["AT's KAR15"] = true, ["VK's ANKM"] = true,
    ["Clothed Sawn-off"] = true, ["Sawn-off"] = true, ["Clothed Rosen-Obrez"] = true,
    ["Rosen-Obrez"] = true, ["DarkSteel K1911"] = true, ["SilverSteel K1911"] = true,
    ["K1911"] = true, ["ZZ-90"] = true, ["SKORPION"] = true, ["Mares Leg"] = true,
    ["RR-LightCompactPistol"] = true, ["RR-LightCompactPistolS"] = true, ["KamatovS"] = true,
    ["Throwing Tomahawk"] = true, ["Throwing Kunai"] = true, ["ChromeSlide Turqoise RR-LCP"] = true,
    ["JS-1 CYCLOPS"] = true, ["THUMPA"] = true, ["LUT-E 'KRUS'"] = true
}
local vigilanteWeapons = {
    ["Beagle"] = true, ["IZVEKH-412"] = true, ["SilverSteel RR-Snubby"] = true,
    ["RR-Snubby"] = true, ["ZKZ-Obrez"] = true, ["GG-17"] = true, ["J9-M"] = true,
    ["J9-Meretta"] = true, ["Pretty Pink GG-17"] = true, ["GG-17 TAN"] = true,
    ["GG-17 GILDED"] = true, ["RR-Snubby GILDED"] = true
}
local specialKillerWeapons = {
    ["RY's GG-17"] = true, ["AT's KAR15"] = true, ["VK's ANKM"] = true
}
local allRoleWeapons = {}
for name, _ in pairs(killerWeapons) do allRoleWeapons[name] = true end
for name, _ in pairs(vigilanteWeapons) do allRoleWeapons[name] = true end

-- Role Colors and Labels
local killerColor = Color3.fromRGB(255, 0, 0)
local killerLabel = "SHOOTER"
local vigilanteColor = Color3.fromRGB(0, 255, 255)
local vigilanteLabel = "VIGILANTE"
local innocentColor = Color3.fromRGB(0, 255, 0)
local innocentLabel = "INNOCENT"
local hintMatchColor = Color3.new(1, 1, 0)
local hintMatchLabel = "HINT MATCH"
local vigilanteHintColor = Color3.fromRGB(128, 0, 128)
local vigilanteHintLabel = "VIGILANTE + HINT MATCH"

-- Bin Class
local Bin = {}
Bin.__index = Bin
function Bin.new()
    local self = setmetatable({}, Bin)
    return self
end
function Bin:add(item)
    local node = { item = item }
    if self.head == nil then self.head = node end
    if self.tail then self.tail.next = node end
    self.tail = node
    return item
end
function Bin:destroy()
    while self.head do
        local item = self.head.item
        if type(item) == "function" then
            item()
        elseif typeof(item) == "RBXScriptConnection" then
            item:Disconnect()
        elseif type(item) == "thread" then
            task.cancel(item)
        elseif item.destroy ~= nil then
            item:destroy()
        elseif item.Destroy ~= nil then
            item:Destroy()
        end
        self.head = self.head.next
    end
end

-- Component Classes
local BaseComponent = {}
BaseComponent.__index = BaseComponent
function BaseComponent.new(instance)
    local self = setmetatable({}, BaseComponent)
    self.instance = instance
    self.bin = Bin.new()
    return self
end
function BaseComponent:destroy()
    self.bin:destroy()
end

local RigComponent = setmetatable({}, { __index = BaseComponent })
RigComponent.__index = RigComponent
function RigComponent.new(instance)
    local self = setmetatable(BaseComponent.new(instance), RigComponent)
    local root = instance:WaitForChild("HumanoidRootPart") or error("Root part not found")
    local head = instance:WaitForChild("Head") or error("Head not found")
    local humanoid = instance:WaitForChild("Humanoid") or error("Humanoid not found")
    self.root = root
    self.head = head
    self.humanoid = humanoid
    self.bin:batch(
        humanoid.Died:Connect(function() self:destroy() end),
        instance.Destroying:Connect(function() self:destroy() end)
    )
    return self
end

local CharacterComponent = setmetatable({}, { __index = RigComponent })
CharacterComponent.__index = CharacterComponent
CharacterComponent.active = {}
function CharacterComponent.new(instance)
    return setmetatable(RigComponent.new(instance), CharacterComponent)
end

local PlayerComponent = setmetatable({}, { __index = BaseComponent })
PlayerComponent.__index = PlayerComponent
PlayerComponent.active = {}
function PlayerComponent.new(playerId)
    local self = setmetatable(BaseComponent.new(playerId), PlayerComponent)
    self.name = playerId.Name
    if playerId.Character then
        task.spawn(function() self:onCharacterAdded(playerId.Character) end)
    end
    self.bin:batch(
        playerId.CharacterAdded:Connect(function(character) self:onCharacterAdded(character) end),
        playerId.CharacterRemoving:Connect(function() self:onCharacterRemoving() end),
        function()
            PlayerComponent.active[playerId] = nil
        end
    )
    PlayerComponent.active[playerId] = self
    return self
end
function PlayerComponent:onCharacterAdded(character)
    if self.character then self.character:destroy() end
    self.character = CharacterComponent.new(character)
end
function PlayerComponent:onCharacterRemoving()
    if self.character then self.character:destroy() end
    self.character = nil
end
function PlayerComponent:getName()
    return self.name
end
function PlayerComponent:getCharacter()
    return self.character
end

-- ESP Functions
local function addNameTag(character, text, color)
    local head = character:FindFirstChild("Head")
    if not head then return end
    local oldTag = head:FindFirstChild("RoleBillboard")
    if oldTag then oldTag:Destroy() end
    local bb = Instance.new("BillboardGui")
    bb.Name = "RoleBillboard"
    bb.Size = UDim2.new(0, 100, 0, 20)
    bb.StudsOffset = Vector3.new(0, 2.5, 0)
    bb.Adornee = head
    bb.AlwaysOnTop = true
    bb.Parent = head
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.2
    label.TextScaled = true
    label.Font = Enum.Font.Arcade
    label.Parent = bb
end

local function clearOldStuff(character)
    if not character then return end
    local oldHighlight = character:FindFirstChild("RoleHighlight")
    if oldHighlight and oldHighlight:IsA("Highlight") then oldHighlight:Destroy() end
    local head = character:FindFirstChild("Head")
    if head then
        local tag = head:FindFirstChild("RoleBillboard")
        if tag then tag:Destroy() end
    end
end

local function tagPlayer(player, roleColor, labelText)
    if not espEnabled then
        print("DEBUG: tagPlayer blocked - ESP is disabled")
        return
    end
    if not player.Character then
        print("DEBUG: tagPlayer skipped - no character for " .. player.Name)
        return
    end
    clearOldStuff(player.Character)
    local highlight = Instance.new("Highlight", player.Character)
    highlight.Name = "RoleHighlight"
    highlight.Archivable = true
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Enabled = true
    highlight.FillColor = roleColor
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 1
    highlight.OutlineTransparency = 0.3
    if labelText then addNameTag(player.Character, labelText, roleColor) end

    -- Add dot above player's head
    local head = player.Character:FindFirstChild("Head")
    if head then
        local dotGui = Instance.new("BillboardGui")
        dotGui.Name = "DotBillboard"
        dotGui.Size = UDim2.new(0, 10, 0, 10)
        dotGui.StudsOffset = Vector3.new(0, 3.5, 0)
        dotGui.Adornee = head
        dotGui.AlwaysOnTop = true
        dotGui.Parent = head
        local dotFrame = Instance.new("Frame")
        dotFrame.Size = UDim2.new(1, 0, 1, 0)
        dotFrame.BackgroundColor3 = roleColor
        dotFrame.BackgroundTransparency = 0
        dotFrame.Parent = dotGui
        local uiCorner = Instance.new("UICorner")
        uiCorner.CornerRadius = UDim.new(0.5, 0)
        uiCorner.Parent = dotFrame
        print("DEBUG: Added DotBillboard for " .. player.Name)
    end
end

local function collectPlayerTools(player)
    local tools = {}
    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") then tools[tool.Name] = tool end
        end
    end
    if player.Character then
        for _, tool in ipairs(player.Character:GetChildren()) do
            if tool:IsA("Tool") then tools[tool.Name] = tool end
        end
    end
    local playerNPCModel = NPCSFolder:FindFirstChild(player.Name)
    if playerNPCModel then
        for _, child in ipairs(playerNPCModel:GetChildren()) do
            if child:IsA("Tool") then tools[child.Name] = child end
        end
    end
    return tools
end

local function getStandardRoleFromWeapons(toolsByName)
    for weaponName, _ in pairs(killerWeapons) do
        if not specialKillerWeapons[weaponName] and toolsByName[weaponName] then
            return "Killer", killerColor, killerLabel
        end
    end
    for weaponName, _ in pairs(vigilanteWeapons) do
        if toolsByName[weaponName] then
            return "Vigilante", vigilanteColor, vigilanteLabel
        end
    end
    return nil, nil, nil
end

local function parseSingleHint(hintContent)
    local hintType = "invalid"
    local hintValue = nil
    local cleanedContent = hintContent:match("^%s*(.-)%s*$") or ""
    print("DEBUG: parseSingleHint called with:", cleanedContent)
    if string.len(cleanedContent) == 0 then
        print("DEBUG: parseSingleHint: Empty content after trimming.")
        return hintType, hintValue
    end
    local taskMatch = cleanedContent:match("^Is often seen%s*(.*)$")
    if taskMatch then
        hintType = "task"
        hintValue = taskMatch:match("^%s*(.-)%s*$")
        print("DEBUG: Parsed as Task. Value:", hintValue)
        return hintType, hintValue
    end
    local traitBracketMatch = cleanedContent:match("^%[.-%]$")
    if traitBracketMatch then
        local cleanClue = traitBracketMatch:gsub("[%[%]]", ""):match("^%s*(.-)%s*$") or ""
        if string.len(cleanClue) > 0 and cleanClue:lower() ~= "assigned task" and cleanClue:lower() ~= "seen" then
            hintType = "trait"
            hintValue = cleanClue
            print("DEBUG: Parsed as Bracketed Trait. Value:", hintValue)
            return hintType, hintValue
        end
    end
    if hintType == "invalid" then
        hintType = "trait"
        hintValue = cleanedContent
        print("DEBUG: Parsed as Unbracketed Trait. Value:", hintValue)
    end
    return hintType, hintValue
end

local function updateMatchingHintPlayers()
    print("DEBUG: updateMatchingHintPlayers called")
    playersMatchingHints = {}
    print("DEBUG: playersMatchingHints cleared")
    if not espEnabled then
        print("DEBUG: updateMatchingHintPlayers: ESP not enabled")
        return
    end
    local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    if not PlayerGui then
        print("DEBUG: updateMatchingHintPlayers: PlayerGui not found")
        return
    end
    local TargetHintLabel = PlayerGui:FindFirstChild("RESETONDEATHStatusGui") and PlayerGui.RESETONDEATHStatusGui:FindFirstChild("TARGETHINT")
    if not TargetHintLabel or not TargetHintLabel:IsA("TextLabel") then
        print("DEBUG: updateMatchingHintPlayers: TARGETHINT label not found or invalid")
        return
    end
    local hintText = TargetHintLabel.Text
    print("DEBUG: Raw TARGETHINT text:", hintText)
    if string.len(string.gsub(hintText, "%s", "")) == 0 then
        print("DEBUG: Hint text is empty.")
        return
    end
    local hintPrefix = "Hints : "
    if string.lower(hintText):sub(1, string.len(hintPrefix)) ~= string.lower(hintPrefix) then
        print("DEBUG: Local player is not the killer ('" .. hintText:sub(1, string.len(hintPrefix)) .. "' != '" .. hintPrefix .. "'). Skipping hint matching.")
        return
    end
    local actualHintContent = hintText:sub(string.len(hintPrefix) + 1):match("^%s*(.-)%s*$")
    print("DEBUG: Raw Hint Content (after removing 'Hints : ' and trimming):", actualHintContent)
    local individualHintParts = {}
    local currentPos = 1
    while currentPos <= string.len(actualHintContent) do
        local nextPlus = string.find(actualHintContent, " + ", currentPos, true)
        if nextPlus then
            local hintPart = string.sub(actualHintContent, currentPos, nextPlus - 1)
            table.insert(individualHintParts, hintPart)
            currentPos = nextPlus + string.len(" + ")
        else
            local hintPart = string.sub(actualHintContent, currentPos)
            table.insert(individualHintParts, hintPart)
            currentPos = string.len(actualHintContent) + 1
        end
    end
    if #individualHintParts == 0 and string.len(actualHintContent) > 0 then
        table.insert(individualHintParts, actualHintContent)
    end
    print("DEBUG: Split into Individual Hint Parts:", individualHintParts)
    local targetConditions = {}
    for i, hintPartContent in ipairs(individualHintParts) do
        local targetNumberMatch = hintPartContent:match("^%[%s*(%d+)%s*%]")
        local targetNumber = tonumber(targetNumberMatch) or 1
        local cleanedHintPartContent = hintPartContent:gsub("^%[%s*%d+%s*%]%s*", ""):match("^%s*(.-)%s*$") or ""
        print("DEBUG: Processing Hint Part:", hintPartContent, "Target Number:", targetNumber, "Cleaned Content:", cleanedHintPartContent)
        local hintType, hintValue = parseSingleHint(cleanedHintPartContent)
        if hintType ~= "invalid" and hintValue and string.len(hintValue) > 0 then
            if not targetConditions[targetNumber] then targetConditions[targetNumber] = {} end
            table.insert(targetConditions[targetNumber], { type = hintType, value = hintValue })
            print("DEBUG: Parsed Condition for Target", targetNumber, ": Type =", hintType, "Value =", hintValue)
        else
            print("DEBUG: Hint Part", i, "contained no valid condition after parsing. Skipping.")
        end
    end
    if next(targetConditions) == nil then
        print("DEBUG: No valid target conditions parsed from hint text. No players will match.")
        return
    end
    for _, player in Players:GetPlayers() do
        if player ~= LocalPlayer then
            local playerNPCModel = NPCSFolder:FindFirstChild(player.Name)
            if playerNPCModel then
                local configObject = playerNPCModel:FindFirstChild("Configuration")
                local playerMatchesAnyTarget = false
                for targetNumber, conditionsForTarget in pairs(targetConditions) do
                    local playerMatchesAllConditionsForTarget = true
                    print("DEBUG: Checking player", player.Name, "against conditions for Target", targetNumber)
                    for i, condition in ipairs(conditionsForTarget) do
                        print("DEBUG:   Checking Condition", i, " (Type:", condition.type, ", Value:", condition.value, ") for Target", targetNumber)
                        local conditionMet = false
                        if condition.type == "task" then
                            local assignedTaskObject = playerNPCModel:FindFirstChild("AssignedTask")
                            print("DEBUG:     Checking Task for player", player.Name, ": Hint Value =", condition.value, ", AssignedTask Object Found =", assignedTaskObject ~= nil, ", AssignedTask Value =", assignedTaskObject and assignedTaskObject.Value or "N/A")
                            if assignedTaskObject and assignedTaskObject:IsA("StringValue") and assignedTaskObject.Value == condition.value then
                                conditionMet = true
                                print("DEBUG:     Player", player.Name, "MATCHES Task:", condition.value, " for Target", targetNumber)
                            else
                                print("DEBUG:     Player", player.Name, "does NOT match Task:", condition.value, " for Target", targetNumber)
                            end
                        elseif condition.type == "trait" then
                            if configObject then
                                print("DEBUG:     Checking Trait for player", player.Name, ": Hint Value =", condition.value, ". Searching Configuration children.")
                                for _, configChild in ipairs(configObject:GetChildren()) do
                                    if configChild:IsA("StringValue") then
                                        print("DEBUG:       Checking Configuration StringValue:", configChild.Name, ", Value:", configChild.Value)
                                        if configChild.Value == condition.value then
                                            conditionMet = true
                                            print("DEBUG:       Player", player.Name, "MATCHES Trait (Configuration child):", condition.value, " via StringValue:", configChild.Name, " for Target", targetNumber)
                                            break
                                        end
                                    end
                                end
                                if not conditionMet then
                                    print("DEBUG:     Player", player.Name, "does NOT match Trait (Configuration children):", condition.value, " for Target", targetNumber)
                                end
                            else
                                print("DEBUG:     Player", player.Name, "NPC model does not have 'Configuration' object. Cannot check trait for Target", targetNumber)
                            end
                        end
                        if not conditionMet then
                            playerMatchesAllConditionsForTarget = false
                            print("DEBUG: Player", player.Name, "does NOT match Condition", i, " for Target", targetNumber, ". Marking as NOT matching ALL conditions for THIS target.")
                            break
                        end
                    end
                    if playerMatchesAllConditionsForTarget then
                        playerMatchesAnyTarget = true
                        print("DEBUG: Player", player.Name, "MATCHES ALL conditions for Target", targetNumber, ". Marking as matching ANY target.")
                        break
                    end
                end
                if playerMatchesAnyTarget then
                    playersMatchingHints[player] = true
                    print("DEBUG: Player", player.Name, "MARKED as playersMatchingHints (matched ANY target).")
                end
            end
        end
    end
end

local function connectHintTextSignal()
    if not espEnabled then return end
    if hintTextConnection then
        print("DEBUG: Disconnecting existing hintTextConnection.")
        hintTextConnection:Disconnect()
        hintTextConnection = nil
    end
    local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    if not PlayerGui then
        print("DEBUG: connectHintTextSignal: PlayerGui not found")
        return
    end
    local statusGui = PlayerGui:WaitForChild("RESETONDEATHStatusGui", 20)
    if not statusGui then
        print("DEBUG: connectHintTextSignal: RESETONDEATHStatusGui not found")
        return
    end
    local TargetHintLabel = statusGui:WaitForChild("TARGETHINT", 10)
    if not TargetHintLabel or not TargetHintLabel:IsA("TextLabel") then
        print("DEBUG: connectHintTextSignal: TARGETHINT TextLabel not found or invalid")
        return
    end
    hintTextConnection = TargetHintLabel:GetPropertyChangedSignal("Text"):Connect(updateMatchingHintPlayers)
    print("DEBUG: TARGETHINT TextLabel signal connected")
    updateMatchingHintPlayers()
end

local function detectRoles()
    if not espEnabled then
        print("DEBUG: detectRoles: ESP not enabled, skipping.")
        return
    end
    print("DEBUG: detectRoles called.")
    local newHighestPriorityKillerDetected = false
    local theSingleKillerGunHolder = nil
    local specialKillerDetected = false
    local playersWithSpecialWeapons = {}
    local everyoneHasGunConditionMet = false
    local noOneHasGunConditionMet = false
    local playersWithValidCharacters = {}
    local playersWithoutAnyGun = {}
    local playersWithAnyGun = {}
    local playersWithVigilanteWeapons = {}
    local vigilanteCount = 0
    local killerGunHoldersCount = 0
    local singleKillerGunHolderCandidate = nil
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            playersWithValidCharacters[player] = true
            local toolsByName = collectPlayerTools(player)
            local hasAnyRoleWeapon = false
            local hasVigilanteWeapon = false
            local hasKillerWeapon = false
            for name, _ in pairs(toolsByName) do
                if specialKillerWeapons[name] then
                    specialKillerDetected = true
                    playersWithSpecialWeapons[player] = true
                end
                if allRoleWeapons[name] then hasAnyRoleWeapon = true end
                if vigilanteWeapons[name] then
                    hasVigilanteWeapon = true
                    playersWithVigilanteWeapons[player] = true
                end
                if killerWeapons[name] then hasKillerWeapon = true end
            end
            if hasVigilanteWeapon then
                vigilanteCount = vigilanteCount + 1
                if firstVigilanteTracker[player] == nil then firstVigilanteTracker[player] = true end
            end
            if hasKillerWeapon then
                killerGunHoldersCount = killerGunHoldersCount + 1
                singleKillerGunHolderCandidate = player
            end
            if not hasAnyRoleWeapon then
                playersWithoutAnyGun[player] = true
            else
                playersWithAnyGun[player] = true
            end
        else
            clearOldStuff(player.Character)
        end
    end
    if vigilanteCount == 1 and killerGunHoldersCount == 1 and singleKillerGunHolderCandidate then
        newHighestPriorityKillerDetected = true
        theSingleKillerGunHolder = singleKillerGunHolderCandidate
        specialKillerDetected = false
        playersWithSpecialWeapons = {}
        everyoneHasGunConditionMet = false
        rolesLockedByDistance = false
        lockedDistanceRoles = {}
        if theSingleKillerGunHolder == LocalPlayer then
            print("DEBUG: Local player is New #1 Killer. Triggering updateMatchingHintPlayers.")
            updateMatchingHintPlayers()
        end
    end
    if not newHighestPriorityKillerDetected then
        local allValidTargetsHaveGun = true
        local otherPlayersWithCharCount = 0
        for player, _ in pairs(playersWithValidCharacters) do
            if player ~= LocalPlayer then otherPlayersWithCharCount = otherPlayersWithCharCount + 1 end
            if playersWithoutAnyGun[player] then allValidTargetsHaveGun = false break end
        end
        if allValidTargetsHaveGun and otherPlayersWithCharCount > 0 then everyoneHasGunConditionMet = true end
        local anyValidTargetHasGun = false
        for player, _ in pairs(playersWithValidCharacters) do
            if playersWithAnyGun[player] then anyValidTargetHasGun = true break end
        end
        if not anyValidTargetHasGun and otherPlayersWithCharCount > 0 then noOneHasGunConditionMet = true end
    end
    if not newHighestPriorityKillerDetected and not specialKillerDetected and everyoneHasGunConditionMet and not rolesLockedByDistance then
        rolesLockedByDistance = true
        lockedDistanceRoles = {}
        print("DEBUG: Distance Lock ACTIVATED.")
        local localHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if localHRP then
            for player, _ in pairs(playersWithValidCharacters) do
                local playerHRP = player.Character:FindFirstChild("HumanoidRootPart")
                if playerHRP then
                    local distance = (localHRP.Position - playerHRP.Position).Magnitude
                    if distance >= distanceThreshold then
                        lockedDistanceRoles[player] = "Killer"
                    else
                        lockedDistanceRoles[player] = "Innocent"
                    end
                end
            end
        else
            rolesLockedByDistance = false
            lockedDistanceRoles = {}
            warn("DEBUG: Distance Lock failed to activate: Local HRP missing.")
        end
    end
    if not newHighestPriorityKillerDetected and not specialKillerDetected and noOneHasGunConditionMet and rolesLockedByDistance then
        rolesLockedByDistance = false
        lockedDistanceRoles = {}
        print("DEBUG: Distance Lock DEACTIVATED.")
    end
    updateMatchingHintPlayers()
    for _, player in ipairs(Players:GetPlayers()) do
        if playersWithValidCharacters[player] then
            if newHighestPriorityKillerDetected and player == theSingleKillerGunHolder then
                print("DEBUG: Applying New #1 Killer tag for", player.Name)
                tagPlayer(player, killerColor, killerLabel)
            elseif specialKillerDetected then
                if playersWithSpecialWeapons[player] then
                    print("DEBUG: Applying Special Killer tag for", player.Name)
                    tagPlayer(player, killerColor, killerLabel)
                else
                    print("DEBUG: Applying Innocent tag (under Special Killer Rule) for", player.Name)
                    tagPlayer(player, innocentColor, innocentLabel)
                end
            elseif rolesLockedByDistance then
                local lockedRole = lockedDistanceRoles[player]
                print("DEBUG: Applying Distance Locked Rule for", player.Name, "Locked Role:", lockedRole)
                if lockedRole then
                    if lockedRole == "Killer" then
                        print("DEBUG: Tagging", player.Name, "as KILLER (by locked distance).")
                        tagPlayer(player, killerColor, killerLabel)
                    elseif lockedRole == "Innocent" then
                        print("DEBUG: Tagging", player.Name, "as INNOCENT (by locked distance).")
                        tagPlayer(player, innocentColor, innocentLabel)
                    end
                else
                    clearOldStuff(player.Character)
                    print("DEBUG: Player", player.Name, "valid but not in lockedDistanceRoles. Clearing.")
                end
            elseif playersMatchingHints[player] and playersWithVigilanteWeapons[player] then
                print("DEBUG: Applying VIGILANTE + HINT MATCH tag for", player.Name, ". Condition met.")
                tagPlayer(player, vigilanteHintColor, vigilanteHintLabel)
            elseif playersMatchingHints[player] and not firstVigilanteTracker[player] then
                print("DEBUG: Applying HINT MATCH tag (Yellow) for", player.Name, ". Condition met.")
                tagPlayer(player, hintMatchColor, hintMatchLabel)
            else
                local toolsByName = collectPlayerTools(player)
                local standardRole, standardColor, standardLabel = getStandardRoleFromWeapons(toolsByName)
                print("DEBUG: Applying Standard Detection for", player.Name, ". Standard Role:", standardLabel)
                if standardRole then
                    tagPlayer(player, standardColor, standardLabel)
                else
                    tagPlayer(player, innocentColor, innocentLabel)
                end
            end
        else
            print("DEBUG: Skipping tagging for", player.Name, " (not a valid target)")
            clearOldStuff(player.Character)
        end
    end
end

local function disableEsp()
    print("DEBUG: disableEsp called - starting full cleanup")
    espEnabled = false
    stopEspLoop = true

    -- Reset all state variables
    rolesLockedByDistance = false
    lockedDistanceRoles = {}
    playersMatchingHints = {}
    firstVigilanteTracker = {}

    -- Disconnect all signals
    if hintTextConnection then
        print("DEBUG: Disconnecting hintTextConnection")
        hintTextConnection:Disconnect()
        hintTextConnection = nil
    end
    if espPlayerAddedConnection then
        print("DEBUG: Disconnecting espPlayerAddedConnection")
        espPlayerAddedConnection:Disconnect()
        espPlayerAddedConnection = nil
    end
    for player, connection in pairs(espCharacterAddedConnections) do
        if connection and typeof(connection) == "RBXScriptConnection" then
            print("DEBUG: Disconnecting CharacterAdded connection for " .. player.Name)
            connection:Disconnect()
        end
        espCharacterAddedConnections[player] = nil
    end
    espCharacterAddedConnections = {}

    -- Aggressive cleanup of all visuals
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            local head = player.Character:FindFirstChild("Head")
            if head then
                local dot = head:FindFirstChild("DotBillboard")
                if dot then
                    dot:Destroy()
                    print("DEBUG: Destroyed DotBillboard for " .. player.Name)
                end
                local tag = head:FindFirstChild("RoleBillboard")
                if tag then
                    tag:Destroy()
                    print("DEBUG: Destroyed RoleBillboard for " .. player.Name)
                end
            end
            local highlight = player.Character:FindFirstChild("RoleHighlight")
            if highlight then
                highlight:Destroy()
                print("DEBUG: Destroyed RoleHighlight for " .. player.Name)
            end
            print("DEBUG: Completed visual cleanup for " .. player.Name)
        else
            print("DEBUG: No character for " .. player.Name .. ", skipped cleanup")
        end
    end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj.Name == "DotBillboard" and obj:IsA("BillboardGui") then
            obj:Destroy()
            print("DEBUG: Destroyed stray DotBillboard in Workspace")
        end
    end
    print("DEBUG: disableEsp completed")
end

local function teleportToDroppedGun()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end

    local hrp = char.HumanoidRootPart
    local closestGun, closestDist = nil, math.huge

    for _, tool in pairs(workspace:FindFirstChild("BloodFolder"):GetChildren()) do
        if tool:IsA("Tool") and (killerWeapons[tool.Name] or vigilanteWeapons[tool.Name] or specialKillerWeapons[tool.Name]) then
            local handle = tool:FindFirstChild("Handle")
            if handle then
                local dist = (handle.Position - hrp.Position).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closestGun = handle
                end
            end
        end
    end

    if closestGun then
        hrp.CFrame = closestGun.CFrame -- Teleport directly to the gun
    end
end

-- Initialize ComponentController
local function initComponentController()
    local onPlayerAdded = function(instance)
        if instance ~= LocalPlayer then PlayerComponent.new(instance) end
    end
    for _, instance in ipairs(Players:GetPlayers()) do
        if instance ~= LocalPlayer then task.spawn(onPlayerAdded, instance) end
    end
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(function(instance)
        local component = PlayerComponent.active[instance]
        if component then component:destroy() end
    end)
end

-- Initialize CameraController
local function initCameraController()
    Camera = Workspace.CurrentCamera
    Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        Camera = Workspace.CurrentCamera or Camera
    end)
end

-- Additional Features Variables
local instantPromptEnabled = false
local PromptButtonHoldBegan = nil
local hitboxEnabled = false
local hitboxSize = 9
local hitboxTransparency = 0.9
local originalHitboxSizes = {}
local doorHandleEnlarged = false
local doorHandleSizeMultiplier = 5.2
local originalHandleSizes = {}
local handleConnection = nil
local selectionBoxes = {}
local aimlockEnabled = false
local headAimEnabled = true
local aimlockFov = 60
local aimlockTeamCheck = false
local currentTarget = nil
local currentTargetDistance = "N/A"

-- Additional Feature Functions
local function applyHitbox(player)
    if player == LocalPlayer or not player.Character then return end
    local root = player.Character:FindFirstChild("HumanoidRootPart")
    if not root or not root:IsA("BasePart") then return end
    if not originalHitboxSizes[player] then
        originalHitboxSizes[player] = root.Size
    end
    root.Size = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
    root.Transparency = hitboxTransparency
end

local function restoreHitbox(player)
    if not player.Character then return end
    local root = player.Character:FindFirstChild("HumanoidRootPart")
    if not root or not root:IsA("BasePart") then return end
    local originalSize = originalHitboxSizes[player]
    if originalSize then
        root.Size = originalSize
        root.Transparency = 1
        originalHitboxSizes[player] = nil
    end
end

local function enableHitbox()
    if hitboxEnabled then
        return
    end
    hitboxEnabled = true
    for _, player in ipairs(Players:GetPlayers()) do
        applyHitbox(player)
    end
    Players.PlayerAdded:Connect(function(player)
        if hitboxEnabled then
            player.CharacterAdded:Connect(function()
                task.wait(0.1)
                applyHitbox(player)
            end)
        end
    end)
end

local function disableHitbox()
    if not hitboxEnabled then return end
    hitboxEnabled = false
    for _, player in ipairs(Players:GetPlayers()) do
        restoreHitbox(player)
    end
    originalHitboxSizes = {}
end

local function modifyHandleSize(obj, enlarge)
    if not obj:IsA("BasePart") or obj.Name ~= "Handeol" then return end
    if not originalHandleSizes[obj] then
        originalHandleSizes[obj] = obj.Size
    end
    obj.Size = enlarge and originalHandleSizes[obj] * doorHandleSizeMultiplier or originalHandleSizes[obj]
    if enlarge then
        if not selectionBoxes[obj] then
            local box = Instance.new("SelectionBox")
            box.Adornee = obj
            box.Color3 = Color3.new(1, 1, 0)
            box.LineThickness = 0.02
            box.Transparency = 0.8
            box.Parent = obj
            selectionBoxes[obj] = box
        end
    else
        if selectionBoxes[obj] then
            selectionBoxes[obj]:Destroy()
            selectionBoxes[obj] = nil
        end
    end
end

local function enableDoorHandleSize()
    if doorHandleEnlarged then
        return
    end
    doorHandleEnlarged = true
    for _, obj in ipairs(workspace:GetDescendants()) do
        modifyHandleSize(obj, true)
    end
    handleConnection = workspace.DescendantAdded:Connect(function(obj)
        if doorHandleEnlarged then
            modifyHandleSize(obj, true)
        end
    end)
end

local function disableDoorHandleSize()
    if not doorHandleEnlarged then
        return
    end
    doorHandleEnlarged = false
    if handleConnection then
        handleConnection:Disconnect()
        handleConnection = nil
    end
    for obj, originalSize in pairs(originalHandleSizes) do
        if obj and obj.Parent then
            modifyHandleSize(obj, false)
        end
    end
end

local function enableInstantPrompt()
    if instantPromptEnabled then
        return
    end
    instantPromptEnabled = true
    PromptButtonHoldBegan = game:GetService("ProximityPromptService").PromptButtonHoldBegan:Connect(function(prompt)
        if instantPromptEnabled then
            fireproximityprompt(prompt)
        end
    end)
end

local function disableInstantPrompt()
    if not instantPromptEnabled then return end
    instantPromptEnabled = false
    if PromptButtonHoldBegan then
        PromptButtonHoldBegan:Disconnect()
        PromptButtonHoldBegan = nil
    end
end

local function stopAnimations()
    local char = LocalPlayer.Character
    if not char then
        return
    end
    local hum = char:FindFirstChildOfClass("Humanoid") or char:FindFirstChildOfClass("AnimationController")
    if not hum then
        return
    end
    for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
        track:Stop()
    end
end

local function isVisible(part)
    if not part then return false end
    local origin = Camera.CFrame.Position
    local direction = (part.Position - origin).Unit * (part.Position - origin).Magnitude

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character} -- ignore yourself

    local result = workspace:Raycast(origin, direction, rayParams)

    -- If ray hits nothing or directly hits the target part or its ancestor, it's visible
    return (not result) or (result.Instance:IsDescendantOf(part.Parent))
end

local function getClosestTarget()
    local closestTarget = nil
    local shortestDistance = math.huge
    local screenCenter = Camera.ViewportSize / 2
    local playerPosition = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character.HumanoidRootPart.Position or Vector3.new(0, 0, 0)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local targetPart = player.Character:FindFirstChild(selectedHitbox)
            local humanoid = player.Character:FindFirstChild("Humanoid")
            if targetPart and humanoid and humanoid.Health > 0 then
                local distanceFromPlayer = (playerPosition - targetPart.Position).Magnitude
                local screenPoint, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                local distanceOnScreen = (Vector2.new(screenPoint.X, screenPoint.Y) - screenCenter).Magnitude
                if onScreen and distanceOnScreen < shortestDistance and distanceOnScreen <= aimlockFov and (not aimlockWallCheck or isVisible(targetPart)) then
                    if not aimlockTeamCheck or player.Team ~= LocalPlayer.Team then
                        closestTarget = player
                        shortestDistance = distanceOnScreen
                        currentTargetDistance = math.floor(distanceFromPlayer)
                    end
                end
            end
        end
    end
    return closestTarget
end

local function lockOnTarget()
    if currentTarget and currentTarget.Character then
        local char = currentTarget.Character
        local targetPart
        local targetVelocity = Vector3.new(0, 0, 0)

        local part = char:FindFirstChild(selectedHitbox)
        if part then
            targetPart = {
                Position = part.Position,
                Velocity = part.Velocity
            }
        end

        if targetPart and targetPart.Position then
            local predictionFactor = math.clamp(0.05 + (currentTargetDistance / 2000), 0.02, 0.1)
            local predictedPosition = targetPart.Position + (targetPart.Velocity * predictionFactor)
            Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, predictedPosition), 0.2)
        else
            currentTarget = nil
        end
    end
end

RunService.RenderStepped:Connect(function()
    if aimlockEnabled then
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            if not currentTarget then
                currentTarget = getClosestTarget()
            end
            if currentTarget then
                lockOnTarget()
            end
        else
            currentTarget = nil
        end
    end
end)

local function enableAimlock()
    if aimlockEnabled then
        return
    end
    aimlockEnabled = true
end

local function disableAimlock()
    if not aimlockEnabled then return end
    aimlockEnabled = false
    currentTarget = nil
end

-- UI Setup with Aztup Library
local uiVisible = true -- Track UI visibility state
local MainSection = library:CreateSection("Main")
local SettingsSection = library:CreateSection("Settings")

-- Aimbot Section
MainSection:Toggle("Enable Aimbot", function(Value)
    if Value then
        enableAimlock()
    else
        disableAimlock()
    end
end)

MainSection:Dropdown("Aimbot Target Part", {"Head", "HumanoidRootPart"}, function(partName)
    selectedHitbox = partName
end)

MainSection:Toggle("Wall Check", function(Value)
    aimlockWallCheck = Value
end)

-- ESP Section
MainSection:Toggle("Enable ESP", function(Value)
    if Value then
        if espEnabled then
            print("DEBUG: ESP already enabled, skipping")
            return
        end
        print("DEBUG: Enabling ESP")
        espEnabled = true
        stopEspLoop = false
        task.spawn(function()
            while espEnabled and not stopEspLoop do
                task.wait(0.5)
                if espEnabled then
                    detectRoles()
                end
            end
            print("DEBUG: ESP loop terminated")
        end)
        espPlayerAddedConnection = Players.PlayerAdded:Connect(function(player)
            print("DEBUG: Player added: " .. player.Name)
            if not espEnabled then return end
            local charAddedConn = player.CharacterAdded:Connect(function(character)
                if not espEnabled then return end
                task.wait(0.1)
                connectHintTextSignal()
                detectRoles()
            end)
            espCharacterAddedConnections[player] = charAddedConn
            if player.Character then
                task.wait(0.1)
                detectRoles()
            end
        end)
        Players.PlayerRemoving:Connect(function(player)
            print("DEBUG: Player removing: " .. player.Name)
            if espCharacterAddedConnections[player] then
                if typeof(espCharacterAddedConnections[player]) == "RBXScriptConnection" then
                    espCharacterAddedConnections[player]:Disconnect()
                end
                espCharacterAddedConnections[player] = nil
            end
            if player.Character then
                clearOldStuff(player.Character)
                print("DEBUG: Cleared visuals for leaving player: " .. player.Name)
            end
        end)
        connectHintTextSignal()
        detectRoles()
    else
        print("DEBUG: Disabling ESP via toggle")
        disableEsp()
    end
end)

-- Misc Section
MainSection:Bind("Unlock Mouse Cursor", Enum.KeyCode.U, function()
    print("DEBUG: Unlocking mouse cursor via keybind")
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    UserInputService.MouseIconEnabled = true
end)

MainSection:Toggle("Instant Proximity Prompts", function(Value)
    if Value then
        enableInstantPrompt()
    else
        disableInstantPrompt()
    end
end)

MainSection:Toggle("Enlarge Door Hitboxes", function(Value)
    if Value then
        enableDoorHandleSize()
    else
        disableDoorHandleSize()
    end
end)

MainSection:Bind("Toggle Hitbox Expansion (MELEE)", Enum.KeyCode.H, function()
    if hitboxEnabled then
        disableHitbox()
    else
        enableHitbox()
    end
end)

MainSection:Button("Teleport to Dropped Gun", function()
    teleportToDroppedGun()
end)

MainSection:Button("Stop Animations", function()
    stopAnimations()
end)

-- Settings Section (Toggle UI)
SettingsSection:Bind("Toggle UI", Enum.KeyCode.K, function()
    print("DEBUG: Toggling UI via keybind")
    uiVisible = not uiVisible
    library.gui.Enabled = uiVisible
end)

-- Initialize components
initComponentController()
initCameraController()

-- Finalize UI
library:Ready()

return nil
