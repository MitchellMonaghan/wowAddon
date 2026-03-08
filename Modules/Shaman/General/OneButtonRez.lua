if select(2, UnitClass("player")) ~= "SHAMAN" then return end

-- Taint-safe one-button rez:
-- Use a dedicated secure button and bind your existing BottomLeft-6 key to it.
local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("UPDATE_BINDINGS")

local secureBtn = CreateFrame("Button", "MyScriptsShamanRezButton", UIParent, "SecureActionButtonTemplate")
secureBtn:SetAttribute("type", "macro")
secureBtn:SetAttribute("macrotext", table.concat({
    "/use [mod:shift,mod:alt,@party4,dead] Ancestral Spirit",
    "/use [mod:shift,mod:ctrl,@party3,dead] Ancestral Spirit",
    "/use [mod:ctrl,@party2,dead] Ancestral Spirit",
    "/use [mod:shift,@party1,dead] Ancestral Spirit",
    "/use [nomod:shift,nomod:ctrl,mod:alt] Ancestral Vision",
    "/use [@mouseover,raid,help,dead][] Ancestral Spirit",
}, "\n"))

local function Rebind()
    ClearOverrideBindings(driver)
    local bindCommand = "MULTIACTIONBAR1BUTTON6"
    local keys = { GetBindingKey(bindCommand) }
    for _, key in ipairs(keys) do
        if key then
            SetOverrideBindingClick(driver, true, key, "MyScriptsShamanRezButton")
        end
    end
end

driver:SetScript("OnEvent", Rebind)
