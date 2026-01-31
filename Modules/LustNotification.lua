local addonName, ns = ...

local lastAlertTime = 0

-- Create the frame and attach the baseline to it
MyHasteFrame = CreateFrame("Frame")
MyHasteFrame.baseline = 0 

MyHasteFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        self.baseline = UnitSpellHaste("player")
        -- ns.Print("Monitor Active.")
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        self.baseline = 0
        lastAlertTime = 0
        return
    end

    -- Process Haste Spikes on UNIT_AURA or UNIT_STATS
    if unit == "player" or event == "FORCE_TEST" then
        local currentHasteRaw = UnitSpellHaste("player")
        local now = GetTime()

        -- Only compare if we have a baseline and aren't on cooldown
        if self.baseline ~= 0 and (now - lastAlertTime) > 5 then
            local currentMult = 1 + (currentHasteRaw / 100)
            local lastMult = 1 + (self.baseline / 100)
            local ratio = currentMult / lastMult

            -- LUST (1.25+)
            if ratio >= 1.25 then
                ns.Print("LUST! Ratio: " .. string.format("%.2f", ratio))
                ns.PlaySmartSound(ns.Sounds.Lust)
                lastAlertTime = now
            -- PI (1.15 - 1.24)
            elseif ratio >= 1.15 and ratio <= 1.24 then
                ns.Print("PI! Ratio: " .. string.format("%.2f", ratio))
                ns.PlaySmartSound(ns.Sounds.PI)
                lastAlertTime = now
            end
        end

        -- Update baseline for the next event
        self.baseline = currentHasteRaw
    end
end)

MyHasteFrame:RegisterEvent("UNIT_AURA")
MyHasteFrame:RegisterEvent("UNIT_STATS")
MyHasteFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
MyHasteFrame:RegisterEvent("PLAYER_REGEN_ENABLED")