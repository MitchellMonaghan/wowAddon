local _, ns = ...

if select(2, UnitClass("player")) ~= "SHAMAN" then return end

-- Riptide charge-cap tracking.
local ripTracker = CreateFrame("Frame")
ripTracker:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

local ripTimerHandle = nil
local ripCapTime = 0

local RIP_CD_BASE = 5.0
local REDUCTION = 2.0
local RIPTIDE_ID = "61295"
local REDUCTION_IDS = {
    ["73685"] = true,
    ["443454"] = true,
}

local function UpdateRipTimer()
    local now = GetTime()
    local alarmTime = ripCapTime - 3
    local delay = alarmTime - now

    if ripTimerHandle then ripTimerHandle:Cancel() end

    if delay > 0 then
        ripTimerHandle = C_Timer.NewTimer(delay, function()
            ns.Speak("Riptide")
        end)
    end
end

ripTracker:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if unit ~= "player" then return end

    local now = GetTime()
    local spellKey = tostring(spellID)

    -- Cast Riptide: add time.
    if spellKey == RIPTIDE_ID then
        if ripCapTime < now then ripCapTime = now end
        ripCapTime = ripCapTime + RIP_CD_BASE
        UpdateRipTimer()
        return
    end

    -- Ancestor procs: subtract time.
    if REDUCTION_IDS[spellKey] then
        if ripCapTime > now then
            ripCapTime = ripCapTime - REDUCTION
            if ripCapTime < now then ripCapTime = now end
            UpdateRipTimer()
        end
    end
end)
