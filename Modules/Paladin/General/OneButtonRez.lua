if select(2, UnitClass("player")) ~= "PALADIN" then return end

-- Taint-safe one-button rez:
-- Use a dedicated secure button and bind your existing BottomLeft-6 key to it.
local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("UPDATE_BINDINGS")

local secureBtn = CreateFrame("Button", "MyScriptsPaladinRezButton", UIParent, "SecureActionButtonTemplate")
secureBtn:SetAttribute("type", "macro")
secureBtn:SetAttribute("macrotext", table.concat({
    "/use [mod:shift,mod:alt,@party4,dead] Redemption",
    "/use [mod:shift,mod:ctrl,@party3,dead] Redemption",
    "/use [mod:ctrl,@party2,dead] Redemption",
    "/use [mod:shift,@party1,dead] Redemption",
    "/use [nomod:shift,nomod:ctrl,mod:alt] Absolution",
    "/use [nomod:alt,combat,@mouseover,raid,help,dead][] Intercession",
    "/use [nomod:alt,nocombat,@mouseover,raid,help,dead][] Redemption",
}, "\n"))

local function Rebind()
    ClearOverrideBindings(driver)
    local bindCommand = "MULTIACTIONBAR1BUTTON6"
    local keys = { GetBindingKey(bindCommand) }
    for _, key in ipairs(keys) do
        if key then
            SetOverrideBindingClick(driver, true, key, "MyScriptsPaladinRezButton")
        end
    end
end

driver:SetScript("OnEvent", Rebind)
