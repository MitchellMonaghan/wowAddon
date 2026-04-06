local _, ns = ...

local ENABLED = true
if not ENABLED then return end

local watchedFrame = nil
local waitingForCombatEnd = false
local manageHooked = false

local function GetStore()
    MyScriptsDB = MyScriptsDB or {}
    MyScriptsDB.fpsDrag = MyScriptsDB.fpsDrag or {}
    return MyScriptsDB.fpsDrag
end

local function ResolveFPSFrame()
    local candidates = {
        _G.MainMenuBarPerformanceBarFrame,
        _G.MainMenuBarPerformanceBar,
        _G.PerformanceBarFrame,
        _G.PerformanceBar,
        _G.FramerateFrame,
        _G.FramerateLabel and _G.FramerateLabel:GetParent() or nil,
        _G.FramerateText and _G.FramerateText:GetParent() or nil,
    }

    for i = 1, #candidates do
        local frame = candidates[i]
        if frame and frame.IsObjectType and frame:IsObjectType("Frame") then
            return frame
        end
    end

    for name, obj in pairs(_G) do
        if type(name) == "string"
            and (name:find("Framerate") or name:find("PerformanceBar"))
            and type(obj) == "table"
            and obj.IsObjectType
            and obj:IsObjectType("Frame")
        then
            return obj
        end
    end
end

local function SavePoint(frame)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not point or not relativePoint then return end
    local store = GetStore()
    store.point = point
    store.relativePoint = relativePoint
    store.x = x or 0
    store.y = y or 0
end

local function ApplySavedPoint(frame)
    local store = GetStore()
    if not store.point or not store.relativePoint then return end
    if InCombatLockdown and InCombatLockdown() then
        waitingForCombatEnd = true
        return
    end
    frame:ClearAllPoints()
    frame:SetPoint(store.point, UIParent, store.relativePoint, store.x or 0, store.y or 0)
end

local function ReapplySavedPointWithRetries(frame)
    if not frame then return end
    ApplySavedPoint(frame)

    if not C_Timer or not C_Timer.After then return end
    local delays = { 0.10, 0.35, 0.75, 1.50 }
    for i = 1, #delays do
        C_Timer.After(delays[i], function()
            if frame and frame._myScriptsFPSDragHooked then
                ApplySavedPoint(frame)
            end
        end)
    end
end

local function EnableDrag(frame)
    if not frame or frame._myScriptsFPSDragHooked then return end
    frame._myScriptsFPSDragHooked = true

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame.ignoreFramePositionManager = true
    if frame.SetUserPlaced then
        frame:SetUserPlaced(true)
    end

    local dragOwner = frame
    if not frame._myScriptsFPSDragHandle then
        local handle = CreateFrame("Button", nil, frame)
        handle:SetAllPoints(frame)
        handle:SetFrameStrata(frame:GetFrameStrata())
        handle:SetFrameLevel((frame:GetFrameLevel() or 0) + 5)
        handle:EnableMouse(true)
        handle:RegisterForDrag("LeftButton")
        frame._myScriptsFPSDragHandle = handle
    end
    local handle = frame._myScriptsFPSDragHandle
    if handle then
        dragOwner = handle
    end

    dragOwner:HookScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        if InCombatLockdown and InCombatLockdown() then return end
        if not IsShiftKeyDown or not IsShiftKeyDown() then return end
        frame:StartMoving()
        frame._myScriptsFPSMoving = true
    end)

    dragOwner:HookScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        if frame._myScriptsFPSMoving then
            frame:StopMovingOrSizing()
            frame._myScriptsFPSMoving = nil
            SavePoint(frame)
        end
    end)

    dragOwner:HookScript("OnDragStart", function()
        if InCombatLockdown and InCombatLockdown() then return end
        if not IsShiftKeyDown or not IsShiftKeyDown() then return end
        frame:StartMoving()
        frame._myScriptsFPSMoving = true
    end)

    dragOwner:HookScript("OnDragStop", function()
        if frame._myScriptsFPSMoving then
            frame:StopMovingOrSizing()
            frame._myScriptsFPSMoving = nil
            SavePoint(frame)
        end
    end)

    ApplySavedPoint(frame)
    watchedFrame = frame

    if ns and ns.Print then
        local frameName = frame.GetName and frame:GetName() or "<unnamed>"
        ns.Print("FPS drag hooked: " .. tostring(frameName))
    end
end

local function EnsureManagePositionsHook()
    if manageHooked then return end
    manageHooked = true
    if type(UIParent_ManageFramePositions) == "function" then
        hooksecurefunc("UIParent_ManageFramePositions", function()
            if watchedFrame and watchedFrame._myScriptsFPSDragHooked and not watchedFrame._myScriptsFPSMoving then
                ReapplySavedPointWithRetries(watchedFrame)
            end
        end)
    end
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:SetScript("OnEvent", function(_, event)
    local frame = ResolveFPSFrame()
    if not frame then return end
    EnableDrag(frame)
    EnsureManagePositionsHook()
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
        ReapplySavedPointWithRetries(frame)
    elseif event == "PLAYER_REGEN_ENABLED" and waitingForCombatEnd then
        waitingForCombatEnd = false
        ReapplySavedPointWithRetries(frame)
    end
end)

if ns and ns.Print then
    ns.Print("FPS drag enabled. Hold SHIFT and drag the FPS monitor.")
end
