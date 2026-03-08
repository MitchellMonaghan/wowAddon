local _, ns = ...

if select(2, UnitClass("player")) ~= "SHAMAN" then return end

-- Healing Stream Tracking
local hstTracker = CreateFrame("Frame")
hstTracker:RegisterEvent("PLAYER_ENTERING_WORLD")
hstTracker:RegisterEvent("SPELLS_CHANGED")
hstTracker:RegisterEvent("PLAYER_TALENT_UPDATE")
hstTracker:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

-- Track the estimated time when we reach full charges again.
local hstTimerHandle = nil
local timeToCap = 0
local TRACKED_NAMES = {
    "Healing Stream Totem",
    "Storm Stream Totem",
    "Surging Totem",
}

local TRACKED_IDS = {}

local function ResolveSpellIDKey(token)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(token)
        if info and info.spellID then
            return tostring(info.spellID)
        end
    end

    if GetSpellInfo then
        local _, _, _, _, _, _, spellID = GetSpellInfo(token)
        if spellID then
            return tostring(spellID)
        end
    end

    return nil
end

local function RebuildTrackedIDs()
    TRACKED_IDS = {
        ["5394"] = true,   -- Healing Stream Totem fallback
        ["430191"] = true, -- Surging Totem fallback
    }

    for _, name in ipairs(TRACKED_NAMES) do
        local key = ResolveSpellIDKey(name)
        if key then
            TRACKED_IDS[key] = true
        end
    end
end

local function HandleTrackedCast()
    local now = GetTime()
    local cdDuration = 20

    if timeToCap < now then
        timeToCap = now
    end

    timeToCap = timeToCap + cdDuration

    local alarmTime = timeToCap - 3
    local delay = alarmTime - now

    if hstTimerHandle then hstTimerHandle:Cancel() end

    if delay > 0 then
        hstTimerHandle = C_Timer.NewTimer(delay, function()
            ns.Speak("Healing Stream")
        end)
    end
end

hstTracker:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
        RebuildTrackedIDs()
        return
    end

    -- HST/Storm Stream/Surging Totem from player.
    if unit ~= "player" then return end
    local spellKey = tostring(spellID)
    if not TRACKED_IDS[spellKey] then return end

    HandleTrackedCast()
end)

RebuildTrackedIDs()
