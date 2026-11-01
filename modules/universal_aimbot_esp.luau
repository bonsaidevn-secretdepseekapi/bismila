local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Config = {
    RuntimeKey = "__UNIVERSAL_AIMBOT_ESP",
    Title = "Universal AimBot/ESP",
    Theme = "Dark",
    SideBarWidth = 170,
    WindowSize = Vector2.new(620, 480),
    AimEnabled = false,
    AimKey = "MouseRightButton",
    MenuKey = Enum.KeyCode.Insert,
    Mode = "Legit",
    Modes = { "Legit", "Semi", "Rage" },
    ModeSmoothing = { Legit = 0.5, Semi = 1, Rage = 2 },
    FOV = 150,
    FOVMin = 50,
    FOVMax = 800,
    ShowFOV = false,
    Smoothing = 0.15,
    SmoothingMin = 0.05,
    SmoothingMax = 1,
    ReferenceFPS = 60,
    Bone = "Head",
    Bones = { "Head", "Root", "Nearest" },
    TeamCheck = true,
    WallCheck = true,
    ESP = { Box = false, Name = false, Health = false, Distance = false, Tracer = false },
    ESPOrder = { "Box", "Name", "Health", "Distance", "Tracer" },
    ESPColor = Color3.fromRGB(80, 220, 255),
    HealthColor = Color3.fromRGB(80, 230, 100),
    HealthBackground = Color3.fromRGB(25, 25, 25),
    FontSize = 14,
    TextGap = 3,
    HealthGap = 5,
    HealthWidth = 2,
    LineWidth = 1,
    CircleSides = 64,
    MinDepth = 0.1,
    BoundsSigns = { -1, 1 },
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local environment = getgenv()
local previous = environment[Config.RuntimeKey]
if type(previous) == "table" and type(previous.Destroy) == "function" then
    previous.Destroy()
end

assert(type(Drawing) == "table" and type(Drawing.new) == "function", "Drawing API is required")

local Window = WindUI:CreateWindow({
    Title = Config.Title,
    Icon = "crosshair",
    Theme = Config.Theme,
    SideBarWidth = Config.SideBarWidth,
    Size = UDim2.fromOffset(Config.WindowSize.X, Config.WindowSize.Y),
    ToggleKey = Config.MenuKey,
})

local runtime = { Connections = {}, Drawings = {}, Circle = nil, Destroyed = false }
environment[Config.RuntimeKey] = runtime
local aimKeyControl
local circleControls = {}

local function getPlayers()
    local result = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            table.insert(result, player)
        end
    end
    return result
end

local function getCharacter(player)
    local character = player.Character
    if not character then
        return nil, nil, nil, nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart") or (humanoid and humanoid.RootPart)
    local head = character:FindFirstChild("Head")
    if root and not root:IsA("BasePart") then
        root = nil
    end
    if head and not head:IsA("BasePart") then
        head = nil
    end
    return character, humanoid, root, head
end

local function isAlive(player)
    local _, humanoid = getCharacter(player)
    return humanoid ~= nil and humanoid.Health > 0
end

local function isTeammate(player)
    return LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team
end

local function getVisible(part)
    local camera = Workspace.CurrentCamera
    if not camera or not part or not part.Parent then
        return false
    end
    local filter = RaycastParams.new()
    filter.FilterType = Enum.RaycastFilterType.Exclude
    filter.FilterDescendantsInstances = LocalPlayer.Character and { LocalPlayer.Character } or {}
    local origin = camera.CFrame.Position
    local hit = Workspace:Raycast(origin, part.Position - origin, filter)
    if not hit then
        return true
    end
    local character = part:FindFirstAncestorOfClass("Model")
    return hit.Instance == part or (character ~= nil and hit.Instance:IsDescendantOf(character))
end

local function removeDrawing(object)
    if object then
        pcall(function()
            object:Remove()
            return
        end)
    end
    return
end

local function clearPlayer(player)
    local drawings = runtime.Drawings[player]
    if drawings then
        for _, object in pairs(drawings) do
            removeDrawing(object)
        end
        runtime.Drawings[player] = nil
    end
    return
end

local function clearESP()
    for player in pairs(runtime.Drawings) do
        clearPlayer(player)
    end
    return
end

local function clearCircle()
    removeDrawing(runtime.Circle)
    runtime.Circle = nil
    return
end

function runtime.Destroy(closeWindow)
    if runtime.Destroyed then
        return
    end
    runtime.Destroyed = true
    for _, connection in ipairs(runtime.Connections) do
        connection:Disconnect()
    end
    table.clear(runtime.Connections)
    clearESP()
    clearCircle()
    if environment[Config.RuntimeKey] == runtime then
        environment[Config.RuntimeKey] = nil
    end
    if closeWindow ~= false then
        Window:Destroy()
    end
    return
end

Window:OnDestroy(function()
    runtime.Destroy(false)
    return
end)

local function makeDrawing(kind, properties)
    local object = Drawing.new(kind)
    object.Visible = false
    object.Transparency = 1
    for name, value in pairs(properties) do
        object[name] = value
    end
    return object
end

local function playerDrawings(player)
    local drawings = runtime.Drawings[player]
    if drawings then
        return drawings
    end
    drawings = {}
    runtime.Drawings[player] = drawings
    if Config.ESP.Box then
        drawings.Box = makeDrawing("Square", { Filled = false, Thickness = Config.LineWidth })
    end
    for _, name in ipairs({ "Name", "Distance" }) do
        if Config.ESP[name] then
            drawings[name] = makeDrawing("Text", { Center = true, Outline = true, Size = Config.FontSize })
        end
    end
    if Config.ESP.Health then
        drawings.HealthBackground = makeDrawing("Line", { Thickness = Config.HealthWidth + Config.LineWidth })
        drawings.Health = makeDrawing("Line", { Thickness = Config.HealthWidth })
    end
    if Config.ESP.Tracer then
        drawings.Tracer = makeDrawing("Line", { Thickness = Config.LineWidth })
    end
    return drawings
end

local function getBounds(character, camera)
    local ok, frame, size = pcall(function()
        return character:GetBoundingBox()
    end)
    if not ok or not frame or not size then
        return nil, nil
    end
    local minimum = Vector2.new(math.huge, math.huge)
    local maximum = Vector2.new(-math.huge, -math.huge)
    for _, x in ipairs(Config.BoundsSigns) do
        for _, y in ipairs(Config.BoundsSigns) do
            for _, z in ipairs(Config.BoundsSigns) do
                local corner = frame:PointToWorldSpace(size * Vector3.new(x, y, z) / 2)
                local screen = camera:WorldToScreenPoint(corner)
                if screen.Z > Config.MinDepth then
                    minimum = Vector2.new(math.min(minimum.X, screen.X), math.min(minimum.Y, screen.Y))
                    maximum = Vector2.new(math.max(maximum.X, screen.X), math.max(maximum.Y, screen.Y))
                end
            end
        end
    end
    if minimum.X == math.huge then
        return nil, nil
    end
    return minimum, maximum
end

local function updateESP(player, camera)
    local character, humanoid, root = getCharacter(player)
    if not character or not humanoid or not root or not isAlive(player) then
        clearPlayer(player)
        return
    end
    local minimum, maximum = getBounds(character, camera)
    if not minimum then
        clearPlayer(player)
        return
    end
    local viewport = camera.ViewportSize
    if maximum.X < 0 or maximum.Y < 0 or minimum.X > viewport.X or minimum.Y > viewport.Y then
        local existing = runtime.Drawings[player]
        if existing then
            for _, object in pairs(existing) do
                object.Visible = false
            end
        end
        return
    end
    local drawings = runtime.Drawings[player]
    if drawings then
        for _, object in pairs(drawings) do
            object.Visible = false
        end
    end
    drawings = playerDrawings(player)
    for _, object in pairs(drawings) do
        object.Color = Config.ESPColor
        object.Visible = true
    end
    local centerX = (minimum.X + maximum.X) / 2
    if drawings.Box then
        drawings.Box.Position = minimum
        drawings.Box.Size = maximum - minimum
    end
    if drawings.Name then
        drawings.Name.Text = player.DisplayName
        drawings.Name.Position = Vector2.new(centerX, minimum.Y - Config.FontSize - Config.TextGap)
    end
    if drawings.Distance then
        local _, _, localRoot = getCharacter(LocalPlayer)
        local origin = localRoot and localRoot.Position or camera.CFrame.Position
        drawings.Distance.Text = string.format("%d studs", math.floor((root.Position - origin).Magnitude))
        drawings.Distance.Position = Vector2.new(centerX, maximum.Y + Config.TextGap)
    end
    if drawings.Health then
        local ratio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
        local bottom = Vector2.new(minimum.X - Config.HealthGap, maximum.Y)
        drawings.HealthBackground.From = bottom
        drawings.HealthBackground.To = Vector2.new(bottom.X, minimum.Y)
        drawings.HealthBackground.Color = Config.HealthBackground
        drawings.Health.From = bottom
        drawings.Health.To = Vector2.new(bottom.X, maximum.Y - (maximum.Y - minimum.Y) * ratio)
        drawings.Health.Color = Config.HealthColor
    end
    if drawings.Tracer then
        local inset = GuiService:GetGuiInset()
        drawings.Tracer.From = Vector2.new(camera.ViewportSize.X / 2 + inset.X, camera.ViewportSize.Y + inset.Y)
        drawings.Tracer.To = Vector2.new(centerX, maximum.Y)
    end
    return
end

local function selectTarget(camera, cursor)
    local selected = nil
    local bestDistance = Config.FOV
    for _, player in ipairs(getPlayers()) do
        if isAlive(player) and not (Config.TeamCheck and isTeammate(player)) then
            local character, _, root, head = getCharacter(player)
            local parts = {}
            if Config.Bone == "Nearest" then
                for _, child in ipairs(character:GetChildren()) do
                    if child:IsA("BasePart") then
                        table.insert(parts, child)
                    end
                end
            else
                local part = head
                if Config.Bone == "Root" then
                    part = root
                end
                if part then
                    table.insert(parts, part)
                end
            end
            for _, part in ipairs(parts) do
                local point, onScreen = camera:WorldToScreenPoint(part.Position)
                if onScreen and point.Z > Config.MinDepth then
                    local distance = (Vector2.new(point.X, point.Y) - cursor).Magnitude
                    local wallCheck = Config.WallCheck and Config.Mode ~= "Rage"
                    if distance < bestDistance and (not wallCheck or getVisible(part)) then
                        bestDistance = distance
                        selected = part
                    end
                end
            end
        end
    end
    return selected
end

local function aimHeld()
    if not aimKeyControl or aimKeyControl.Picking or UserInputService:GetFocusedTextBox() then
        return false
    end
    Config.AimKey = aimKeyControl.Value
    if Config.AimKey == "MouseLeftButton" then
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end
    if Config.AimKey == "MouseRightButton" then
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    end
    local key = Enum.KeyCode[Config.AimKey]
    return key ~= nil and UserInputService:IsKeyDown(key)
end

local function setCircle(value)
    if Config.ShowFOV == value then
        return
    end
    Config.ShowFOV = value
    if not value then
        clearCircle()
    end
    for _, control in ipairs(circleControls) do
        control:Set(value)
    end
    return
end

local Combat = Window:Tab({ Title = "Combat", Icon = "crosshair" })
local Visuals = Window:Tab({ Title = "Visuals", Icon = "eye" })
local Settings = Window:Tab({ Title = "Settings", Icon = "settings" })
Combat:Section({ Title = "AimBot", Icon = "crosshair" })
Combat:Toggle({ Title = "Enable AimBot", Value = Config.AimEnabled, Callback = function(value)
    Config.AimEnabled = value
    return
end })
Combat:Dropdown({ Title = "Mode", Desc = "Legit: 0.5x smoothing rate / Semi: 1x / Rage: 2x", Values = Config.Modes, Value = Config.Mode, Callback = function(value)
    Config.Mode = value
    return
end })
Combat:Slider({ Title = "FOV (px)", Step = 1, Value = { Min = Config.FOVMin, Max = Config.FOVMax, Default = Config.FOV }, Callback = function(value)
    Config.FOV = tonumber(value) or Config.FOV
    return
end })
Combat:Slider({ Title = "Smoothing", Step = 0.01, Value = { Min = Config.SmoothingMin, Max = Config.SmoothingMax, Default = Config.Smoothing }, Callback = function(value)
    Config.Smoothing = tonumber(value) or Config.Smoothing
    return
end })
Combat:Dropdown({ Title = "Bone", Values = Config.Bones, Value = Config.Bone, Callback = function(value)
    Config.Bone = value
    return
end })
Combat:Toggle({ Title = "Team Check", Value = Config.TeamCheck, Callback = function(value)
    Config.TeamCheck = value
    return
end })
Combat:Toggle({ Title = "Wall Check", Value = Config.WallCheck, Callback = function(value)
    Config.WallCheck = value
    return
end })
table.insert(circleControls, Combat:Toggle({ Title = "Show FOV Circle", Value = Config.ShowFOV, Callback = setCircle }))

Visuals:Section({ Title = "ESP", Icon = "scan-eye" })
for _, name in ipairs(Config.ESPOrder) do
    local feature = name
    Visuals:Toggle({ Title = feature, Value = Config.ESP[feature], Callback = function(value)
        Config.ESP[feature] = value
        clearESP()
        return
    end })
end
Visuals:Colorpicker({ Title = "ESP Color", Default = Config.ESPColor, Callback = function(value)
    Config.ESPColor = value
    return
end })

Settings:Section({ Title = "Appearance", Icon = "palette" })
local themes = {}
for name in pairs(WindUI:GetThemes()) do
    table.insert(themes, name)
end
table.sort(themes)
Settings:Dropdown({ Title = "Theme", Values = themes, Value = Config.Theme, Callback = function(value)
    if WindUI:GetThemes()[value] then
        Config.Theme = value
        WindUI:SetTheme(value)
    end
    return
end })
Settings:Section({ Title = "Aim Key & FOV", Icon = "keyboard" })
aimKeyControl = Settings:Keybind({ Title = "Aim Key", Desc = "Hold to aim. Insert toggles the window.", Value = Config.AimKey, Callback = function()
    return
end })
table.insert(circleControls, Settings:Toggle({ Title = "Show FOV Circle", Value = Config.ShowFOV, Callback = setCircle }))

table.insert(runtime.Connections, Players.PlayerRemoving:Connect(function(player)
    clearPlayer(player)
    return
end))

table.insert(runtime.Connections, RunService.RenderStepped:Connect(function(deltaTime)
    if runtime.Destroyed then
        return
    end
    local camera = Workspace.CurrentCamera
    if not camera then
        clearESP()
        clearCircle()
        return
    end
    local cursor = UserInputService:GetMouseLocation()
    if Config.ShowFOV then
        if not runtime.Circle then
            runtime.Circle = makeDrawing("Circle", { Filled = false, Thickness = Config.LineWidth, NumSides = Config.CircleSides })
        end
        runtime.Circle.Position = cursor
        runtime.Circle.Radius = Config.FOV
        runtime.Circle.Color = Config.ESPColor
        runtime.Circle.Visible = true
    end
    if Config.AimEnabled and aimHeld() then
        local target = selectTarget(camera, cursor)
        if target then
            local position = camera.CFrame.Position
            if (target.Position - position).Magnitude > Config.MinDepth then
                local rate = math.clamp(Config.Smoothing * Config.ModeSmoothing[Config.Mode], 0, 1)
                local alpha = 1 - (1 - rate) ^ (deltaTime * Config.ReferenceFPS)
                camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(position, target.Position), alpha)
            end
        end
    end
    local espEnabled = false
    for _, enabled in pairs(Config.ESP) do
        espEnabled = espEnabled or enabled
    end
    if espEnabled then
        for _, player in ipairs(getPlayers()) do
            updateESP(player, camera)
        end
    end
    return
end))

Window:SelectTab(1)
print("[AimBot/ESP] Loaded")
