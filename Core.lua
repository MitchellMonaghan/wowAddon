local addonName, ns = ...

ns.MediaPath = "Interface\\AddOns\\MyScripts\\Media\\"
ns.Sounds = {
    Lust   = 556000,
    PI     = 568534,
    LowHP  = ns.MediaPath .. "PowerAurasMedia\\Sounds\\Gasp.ogg",
    Death  = ns.MediaPath .. "Sounds\\igQuestFailed.ogg",
}
ns.Icons = {
    Logo   = ns.MediaPath .. "AddonLogo.tga",
}

function ns.Speak(text)
    local voice = TextToSpeech_GetSelectedVoice(Enum.TtsVoiceType.Standard)
    if not voice then return end
    TextToSpeech_Speak(text, voice)
end

function ns.PlaySmartSound(soundData)
    if not soundData then return end

    PlaySoundFile(soundData, "Master")
end

function ns.Print(msg)
    print("|cff00ff00[MyScripts]|r " .. tostring(msg))
end

ns.Print("Core Loaded. Modules initializing...")