local _, ns = ...

-- Single-switch module toggle.
local ENABLED = true
if not ENABLED then return end

-- Main thickness control: bigger inset = thicker visible border.
local BORDER_REVEAL_INSET = 1
local BORDER_TEXTURE_EXTRA_PIXELS = 0
local BORDER_TEXTURE_SCALE = 0.96
local ICON_ZOOM = 0
local RESCAN_INTERVAL = 0.20
local ROTATION_SCAN_INTERVAL = 0.08
local TRACKED_BARS_ENFORCE_INTERVAL = 0.10
-- Set false if you still run CooldownManagerCentered and only want icon skinning here.
local ENABLE_POSITIONING = true
local ENABLE_ROTATION_HIGHLIGHT = true
local ENABLE_TRACKED_BARS_BOTTOM_UP = true
local ENABLE_TRACKED_BARS_BOTTOM_LOCK = false
local SPEC_RECENTER_INTERVAL = 0.08
local SPEC_RECENTER_PASSES = 18

local MASK_PATH = [[Interface\AddOns\MyScripts\Media\Textures\csquare_mask.tga]]
local BORDER_TEXTURE_PATH = [[Interface\AddOns\MyScripts\Media\Textures\defaultEER.blp]]
-- `border_thin.blp` is not suitable here (it fills icon center on CDM buttons).

local VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
}

local TRINKET_SLOTS = {
    INVSLOT_TRINKET1,
    INVSLOT_TRINKET2,
}

local MIXIN_NAMES = {
    "CooldownViewerBuffIconItemMixin",
    "CooldownViewerEssentialItemMixin",
    "CooldownViewerUtilityItemMixin",
}

local styledButtons = setmetatable({}, { __mode = "k" })
local hookedMixins = {}
local dirtyViewers = setmetatable({}, { __mode = "k" })
local trackedBarsBottomAnchor = nil
local trackedBarsDirty = true
local trackedBarsVisibleCount = -1
local essentialDesiredCenter = nil
local essentialTrinketOverlay = nil
local pendingSpecRecenterPasses = 0
local specRecenterElapsed = 0
local wasInEditMode = false
local essentialTrinketButtons = {}
local rotationHighlightViewers = {
    EssentialCooldownViewer = true,
    UtilityCooldownViewer = true,
}
local floor = math.floor
local lastSuggestedSpellID = nil
local rotationDirty = true
local RecenterViewer
local MarkViewerDirty
local GetReferenceEssentialButton
local GetEssentialVisualOffset

local function GetCooldownSkinStore()
    MyScriptsDB = MyScriptsDB or {}
    MyScriptsDB.cooldownManagerSkin = MyScriptsDB.cooldownManagerSkin or {}
    return MyScriptsDB.cooldownManagerSkin
end

local function SaveEssentialDesiredCenter(x, y)
    essentialDesiredCenter = { x = x, y = y }
    local store = GetCooldownSkinStore()
    store.essentialDesiredCenter = { x = x, y = y }
end

local function CaptureEssentialDesiredCenterFromViewer(viewer, force)
    if not viewer or (not force and essentialDesiredCenter) then return end
    local vx, vy = viewer:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not vx or not vy or not ux or not uy then return end
    local extraCount = 0
    for i = 1, #TRINKET_SLOTS do
        local button = essentialTrinketButtons[TRINKET_SLOTS[i]]
        if button and button:IsShown() then
            extraCount = extraCount + 1
        end
    end

    local reference = GetReferenceEssentialButton(viewer)
    local size = 0
    if reference then
        local isHorizontal = viewer.isHorizontal ~= false
        size = isHorizontal and (reference:GetWidth() or 0) or (reference:GetHeight() or 0)
        local offsetX, offsetY = GetEssentialVisualOffset(isHorizontal, size, extraCount)
        local scale = viewer.GetEffectiveScale and viewer:GetEffectiveScale() or 1
        vx = vx + (offsetX * scale)
        vy = vy + (offsetY * scale)
    end

    local rx, ry = vx - ux, vy - uy
    SaveEssentialDesiredCenter(rx, ry)
end

local function GetVisibleEssentialTrinketButtons()
    local out = {}
    for i = 1, #TRINKET_SLOTS do
        local button = essentialTrinketButtons[TRINKET_SLOTS[i]]
        if button and button:IsShown() and button:IsVisible() and (button:GetAlpha() or 0) > 0 then
            out[#out + 1] = button
        end
    end
    table.sort(out, function(a, b)
        return (a._myScriptsTrinketSlot or 0) < (b._myScriptsTrinketSlot or 0)
    end)
    return out
end

local function EnsureBorder(button)
    if button._myScriptsBorder and button._myScriptsBorder.Hide then
        button._myScriptsBorder:Hide()
    end

    if not button._myScriptsDarkModeBorder then
        local border = button:CreateTexture(nil, "OVERLAY", nil, 7)
        border:SetDrawLayer("OVERLAY", 7)
        border:SetTexture(BORDER_TEXTURE_PATH)
        border:SetVertexColor(0, 0, 0, 1)
        border:SetPoint("CENTER", button, "CENTER", 0, 0)
        button._myScriptsDarkModeBorder = border
    end

    local w = button:GetWidth() or 0
    local h = button:GetHeight() or 0
    if w > 0 and h > 0 then
        local borderW = (w + BORDER_TEXTURE_EXTRA_PIXELS) * BORDER_TEXTURE_SCALE
        local borderH = (h + BORDER_TEXTURE_EXTRA_PIXELS) * BORDER_TEXTURE_SCALE
        button._myScriptsDarkModeBorder:SetSize(borderW, borderH)
    end
end

local function StyleButton(button)
    if not button then return end
    if not button.Icon or not button.Cooldown then return end
    if not button.Icon.SetTexCoord then return end

    if styledButtons[button] then
        EnsureBorder(button)
        return
    end

    button:SetScale(1)

    button.Icon:ClearAllPoints()
    button.Icon:SetPoint("TOPLEFT", button, "TOPLEFT", BORDER_REVEAL_INSET, -BORDER_REVEAL_INSET)
    button.Icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -BORDER_REVEAL_INSET, BORDER_REVEAL_INSET)
    button.Icon:SetTexCoord(ICON_ZOOM, 1 - ICON_ZOOM, ICON_ZOOM, 1 - ICON_ZOOM)

    if not button._myScriptsMask then
        local mask = button:CreateMaskTexture(nil, "ARTWORK")
        mask:SetTexture(MASK_PATH, "CLAMPTOBORDER", "CLAMPTOBORDER")
        mask:SetAllPoints(button.Icon)
        button.Icon:AddMaskTexture(mask)
        button._myScriptsMask = mask
    end

    button.Cooldown:ClearAllPoints()
    button.Cooldown:SetPoint("TOPLEFT", button, "TOPLEFT", BORDER_REVEAL_INSET, -BORDER_REVEAL_INSET)
    button.Cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -BORDER_REVEAL_INSET, BORDER_REVEAL_INSET)
    button.Cooldown:SetDrawEdge(false)
    if button.Cooldown.SetSwipeTexture then
        button.Cooldown:SetSwipeTexture(MASK_PATH)
    end

    for _, region in ipairs({ button:GetRegions() }) do
        if region and region.IsObjectType and region:IsObjectType("Texture") then
            local atlas = region.GetAtlas and region:GetAtlas() or nil
            if atlas == "UI-HUD-CoolDownManager-IconOverlay" then
                region:SetAlpha(0)
            end
        end
    end

    EnsureBorder(button)
    styledButtons[button] = true
end

local function EnsureRotationHighlight(button)
    if button._myScriptsRotationHighlight then
        return button._myScriptsRotationHighlight
    end

    local holder = CreateFrame("Frame", nil, button)
    holder:SetFrameLevel(button:GetFrameLevel() + 10)
    holder:SetPoint("CENTER", button, "CENTER", 0, 0)

    local tex = holder:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:SetPoint("CENTER", holder, "CENTER", 0, 0)
    tex:SetBlendMode("ADD")

    local usingFlipbook = false
    if tex.SetAtlas then
        usingFlipbook = tex:SetAtlas("RotationHelper_Ants_Flipbook_2x", false) == true
    end

    if not usingFlipbook then
        if tex.SetAtlas and tex:SetAtlas("UI-CooldownManager-ActiveGlow", false) then
            tex:SetVertexColor(0.20, 0.70, 1.0, 1)
        else
            tex:SetTexture(BORDER_TEXTURE_PATH)
            tex:SetVertexColor(0.20, 0.70, 1.0, 1)
        end
    end

    holder.Texture = tex
    holder.UsingFlipbook = usingFlipbook

    if usingFlipbook then
        local ag = holder:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local flip = ag:CreateAnimation("FlipBook")
        flip:SetChildKey("Texture")
        flip:SetOrder(1)
        flip:SetDuration(1.0)
        flip:SetFlipBookRows(6)
        flip:SetFlipBookColumns(5)
        flip:SetFlipBookFrames(30)
        holder.Anim = ag
    end

    holder:Hide()
    button._myScriptsRotationHighlight = holder
    return holder
end

local function UpdateRotationHighlightSize(button)
    local glow = EnsureRotationHighlight(button)
    local w = button:GetWidth() or 0
    local h = button:GetHeight() or 0
    if w <= 0 or h <= 0 then return end
    glow:SetSize(w * 1.42, h * 1.42)
    if glow.Texture then
        glow.Texture:SetSize(w * 1.42, h * 1.42)
    end
end

local function GetButtonSpellIDs(button)
    if not button or not button.cooldownID then return nil, nil end
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCooldownInfo then
        return nil, nil
    end
    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(button.cooldownID)
    if not info then return nil, nil end
    return info.spellID, info.overrideSpellID
end

local function SetRotationHighlight(button, show)
    local glow = EnsureRotationHighlight(button)
    if show then
        UpdateRotationHighlightSize(button)
        glow:Show()
        if glow.Anim and not glow.Anim:IsPlaying() then
            glow.Anim:Play()
        end
    else
        if glow.Anim and glow.Anim:IsPlaying() then
            glow.Anim:Stop()
        end
        glow:Hide()
    end
end

local function RefreshRotationHighlights(force)
    if not ENABLE_ROTATION_HIGHLIGHT then
        for viewerName in pairs(rotationHighlightViewers) do
            local viewer = _G[viewerName]
            if viewer then
                local children = { viewer:GetChildren() }
                for i = 1, #children do
                    local child = children[i]
                    if child and child._myScriptsRotationHighlight then
                        child._myScriptsRotationHighlight:Hide()
                    end
                end
            end
        end
        return
    end

    if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then
        return
    end

    local suggestedSpellID = C_AssistedCombat.GetNextCastSpell()
    if not force and not rotationDirty and suggestedSpellID == lastSuggestedSpellID then
        return
    end
    lastSuggestedSpellID = suggestedSpellID
    rotationDirty = false

    for viewerName in pairs(rotationHighlightViewers) do
        local viewer = _G[viewerName]
        if viewer then
            local children = { viewer:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                if child and child.Icon and child.Cooldown then
                    local spellID, overrideSpellID = GetButtonSpellIDs(child)
                    local show = suggestedSpellID and (spellID == suggestedSpellID or overrideSpellID == suggestedSpellID)
                    SetRotationHighlight(child, show == true)
                end
            end
        end
    end
end

local function GetVisibleButtons(viewer)
    local out = {}
    local candidates = {}
    if not viewer then return out end
    local viewerName = viewer.GetName and viewer:GetName() or ""
    local children = { viewer:GetChildren() }

    local function IsLayoutActive(child)
        if not child then return false end
        -- Avoid reading secret/protected fields (e.g. `isActive`) to prevent taint
        -- compare errors in Blizzard CDM frames.
        if viewerName == "EssentialCooldownViewer" or viewerName == "UtilityCooldownViewer" then
            if child.cooldownID == nil then
                return false
            end
            if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(child.cooldownID)
                if not info then
                    return false
                end
                return (info.spellID ~= nil) or (info.overrideSpellID ~= nil)
            end
            return true
        end

        local hasAuraInstance = child.auraInstanceID ~= nil
        local hasCooldownID = child.cooldownID ~= nil
        local hasIconTexture = child.Icon and child.Icon.GetTexture and child.Icon:GetTexture() ~= nil
        return hasAuraInstance or hasCooldownID or hasIconTexture
    end

    for i = 1, #children do
        local child = children[i]
        if child
            and child.Icon
            and child.Cooldown
            and child:IsShown()
            and child:IsVisible()
            and (child:GetAlpha() or 0) > 0
        then
            candidates[#candidates + 1] = child
            if IsLayoutActive(child) then
                out[#out + 1] = child
            end
        end
    end

    -- During spec swaps, CDM can briefly report incomplete active metadata.
    -- If Essential/Utility collapses to 0/1 active while more visible buttons exist,
    -- use visible candidates for this pass to avoid "icon 1 pinned at center" jumps.
    if (viewerName == "EssentialCooldownViewer" or viewerName == "UtilityCooldownViewer")
        and #out <= 1 and #candidates > #out
    then
        out = candidates
    end

    table.sort(out, function(a, b)
        return (a.layoutIndex or 0) < (b.layoutIndex or 0)
    end)
    return out
end

GetReferenceEssentialButton = function(viewer)
    if not viewer then return nil end
    local children = { viewer:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child
            and child.Icon
            and child.Cooldown
            and child.cooldownID ~= nil
            and child:IsShown()
            and child:IsVisible()
            and (child:GetAlpha() or 0) > 0
        then
            return child
        end
    end
    return nil
end

local function IsEquippedOnUseTrinket(slot)
    local itemID = GetInventoryItemID("player", slot)
    if not itemID then return false, nil, nil, nil end
    local spellName, spellID = GetItemSpell(itemID)
    if not spellName or not spellID then
        return false, itemID, nil, nil
    end
    local texture = GetInventoryItemTexture("player", slot)
    if not texture then
        return false, itemID, nil, nil
    end
    return true, itemID, spellID, texture
end

local function EnsureEssentialTrinketButton(slot)
    if not slot then return nil end
    if not essentialTrinketOverlay then
        essentialTrinketOverlay = CreateFrame("Frame", nil, UIParent)
        essentialTrinketOverlay:SetAllPoints(UIParent)
        essentialTrinketOverlay:SetFrameStrata("MEDIUM")
        essentialTrinketOverlay:SetFrameLevel(1)
    end
    if essentialTrinketButtons[slot] and essentialTrinketButtons[slot]:GetParent() ~= essentialTrinketOverlay then
        essentialTrinketButtons[slot]:SetParent(essentialTrinketOverlay)
    end
    if essentialTrinketButtons[slot] then
        return essentialTrinketButtons[slot]
    end

    local button = CreateFrame("Frame", nil, essentialTrinketOverlay)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(essentialTrinketOverlay:GetFrameLevel() + 5)
    button._myScriptsCustomEssential = true
    button._myScriptsTrinketSlot = slot
    button:Hide()

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0, 1, 0, 1)
    button.Icon = icon

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    button.Cooldown = cooldown

    essentialTrinketButtons[slot] = button
    return button
end

local function UpdateEssentialTrinketButtons()
    local viewer = _G.EssentialCooldownViewer
    if not viewer then return end

    local reference = GetReferenceEssentialButton(viewer)
    local width = reference and reference:GetWidth() or 0
    local height = reference and reference:GetHeight() or 0
    local scale = reference and reference:GetScale() or 1
    if width <= 0 then width = 36 end
    if height <= 0 then height = 36 end
    if not scale or scale <= 0 then scale = 1 end

    local changed = false
    for i = 1, #TRINKET_SLOTS do
        local slot = TRINKET_SLOTS[i]
        local button = EnsureEssentialTrinketButton(slot)
        local wasShown = button:IsShown()
        local isOnUse, itemID, spellID, texture = IsEquippedOnUseTrinket(slot)

        button:SetScale(scale)
        button:SetSize(width, height)

        if isOnUse then
            button.Icon:SetTexture(texture)
            local startTime, duration, enable = GetInventoryItemCooldown("player", slot)
            if button.Cooldown.SetCooldown then
                button.Cooldown:SetCooldown((enable == 0 and 0) or (startTime or 0), (enable == 0 and 0) or (duration or 0))
            end
            button._myScriptsItemID = itemID
            button._myScriptsSpellID = spellID
            button:Show()
        else
            button._myScriptsItemID = nil
            button._myScriptsSpellID = nil
            if button.Cooldown.SetCooldown then
                button.Cooldown:SetCooldown(0, 0)
            end
            button:Hide()
        end

        StyleButton(button)

        if wasShown ~= button:IsShown() then
            changed = true
        end
    end

    if changed and ENABLE_POSITIONING then
        MarkViewerDirty(viewer)
    end
end

local function QueueSpecRecenter()
    pendingSpecRecenterPasses = SPEC_RECENTER_PASSES
    specRecenterElapsed = 0
end

local function ProcessSpecRecenter(dt)
    if pendingSpecRecenterPasses <= 0 then return end
    specRecenterElapsed = specRecenterElapsed + dt
    if specRecenterElapsed < SPEC_RECENTER_INTERVAL then return end
    specRecenterElapsed = 0

    local essential = _G.EssentialCooldownViewer
    if essential then MarkViewerDirty(essential) end
    pendingSpecRecenterPasses = pendingSpecRecenterPasses - 1
end

local function IsEditModeOpen()
    if C_EditMode and C_EditMode.IsInEditMode then
        local ok, inEdit = pcall(C_EditMode.IsInEditMode)
        if ok and inEdit ~= nil then
            return inEdit == true
        end
    end
    return EditModeManagerFrame and EditModeManagerFrame:IsShown() == true
end

local function GetVisibleTrackedBars(viewer)
    local out = {}
    if not viewer then return out end

    local frames = {}
    if viewer.GetItemFrames then
        local ok, items = pcall(viewer.GetItemFrames, viewer)
        if ok and items then
            for i = 1, #items do
                frames[#frames + 1] = items[i]
            end
        end
    end
    if #frames == 0 then
        local children = { viewer:GetChildren() }
        for i = 1, #children do
            frames[#frames + 1] = children[i]
        end
    end

    for i = 1, #frames do
        local child = frames[i]
        if child and child:IsShown() and (child:GetAlpha() or 0) > 0 then
            out[#out + 1] = child
        end
    end
    table.sort(out, function(a, b)
        return (a.layoutIndex or 0) < (b.layoutIndex or 0)
    end)
    return out
end

local function EnsureTrackedBarsBottomLock(viewer)
    if not ENABLE_TRACKED_BARS_BOTTOM_LOCK or not viewer then return end

    if not trackedBarsBottomAnchor then
        local vx, vy = viewer:GetCenter()
        local vb = viewer:GetBottom()
        local ux, uy = UIParent:GetCenter()
        if not vx or not vy or not vb or not ux or not uy then return end

        trackedBarsBottomAnchor = CreateFrame("Frame", nil, UIParent)
        trackedBarsBottomAnchor:SetSize(1, 1)
        trackedBarsBottomAnchor:SetPoint("CENTER", UIParent, "CENTER", vx - ux, vb - uy)
    end

    local point, relativeTo, relativePoint, x, y = viewer:GetPoint(1)
    if point ~= "BOTTOM" or relativeTo ~= trackedBarsBottomAnchor or relativePoint ~= "CENTER" or x ~= 0 or y ~= 0 then
        viewer:ClearAllPoints()
        viewer:SetPoint("BOTTOM", trackedBarsBottomAnchor, "CENTER", 0, 0)
    end
end

local function PositionTrackedBarsBottomUp()
    if not ENABLE_TRACKED_BARS_BOTTOM_UP then return end
    local viewer = _G.BuffBarCooldownViewer
    if not viewer then return end

    EnsureTrackedBarsBottomLock(viewer)

    local bars = GetVisibleTrackedBars(viewer)
    if #bars == 0 then return end

    local spacing = viewer.childYPadding or 2
    local previous = nil
    for i = 1, #bars do
        local bar = bars[i]
        bar:ClearAllPoints()
        if previous then
            bar:SetPoint("BOTTOM", previous, "TOP", 0, spacing)
        else
            bar:SetPoint("BOTTOM", viewer, "BOTTOM", 0, 0)
        end
        previous = bar
    end
end


local function BuildRows(iconLimit, children)
    local rows = {}
    local limit = iconLimit or 0
    if limit <= 0 then
        rows[1] = children
        return rows
    end
    for i = 1, #children do
        local rowIndex = floor((i - 1) / limit) + 1
        rows[rowIndex] = rows[rowIndex] or {}
        rows[rowIndex][#rows[rowIndex] + 1] = children[i]
    end
    return rows
end

local function CenteredOffsets(count, size, padding, direction)
    if count <= 0 then return {} end
    local dir = direction or 1
    local start = (-((count - 1) * (size + padding)) * 0.5) * dir
    local out = {}
    for i = 1, count do
        out[i] = start + (i - 1) * (size + padding) * dir
    end
    return out
end

local function GetTrinketAttachGap()
    -- Each icon reveals its own dark border inside the frame by BORDER_REVEAL_INSET.
    -- If we attach frame edge-to-edge, those revealed borders still create a visible seam.
    -- Pull the trinket in by both insets so it visually abuts the last Essential icon.
    return -(BORDER_REVEAL_INSET * 2)
end

GetEssentialVisualOffset = function(isHorizontal, size, extraCount)
    if extraCount <= 0 then
        return 0, 0
    end

    local attachGap = GetTrinketAttachGap()
    local extension = extraCount * (size + attachGap)
    if isHorizontal then
        return extension * 0.5, 0
    end
    return 0, -(extension * 0.5)
end

local function InferCenters(icons)
    local pts = {}
    for i = 1, #icons do
        local cx, cy = icons[i]:GetCenter()
        if cx and cy then
            pts[#pts + 1] = { x = cx, y = cy }
        end
    end
    return pts
end

local function InferIsHorizontal(viewer, icons)
    local pts = InferCenters(icons)
    if #pts < 2 then
        return viewer.isHorizontal ~= false
    end

    local minX, maxX, minY, maxY = pts[1].x, pts[1].x, pts[1].y, pts[1].y
    for i = 2, #pts do
        local p = pts[i]
        if p.x < minX then minX = p.x end
        if p.x > maxX then maxX = p.x end
        if p.y < minY then minY = p.y end
        if p.y > maxY then maxY = p.y end
    end

    local xSpan = maxX - minX
    local ySpan = maxY - minY
    return xSpan >= ySpan
end

local function InferIconLimit(icons, isHorizontal, w, h, fallback)
    local pts = InferCenters(icons)
    if #pts == 0 then return fallback end

    local axis = {}
    for i = 1, #pts do
        axis[i] = isHorizontal and pts[i].y or pts[i].x
    end
    table.sort(axis)

    local threshold = ((isHorizontal and h or w) or 0) * 0.6
    if threshold <= 0 then threshold = 1 end

    local groups = {}
    local last = axis[1]
    local currentCount = 1
    for i = 2, #axis do
        if math.abs(axis[i] - last) <= threshold then
            currentCount = currentCount + 1
        else
            groups[#groups + 1] = currentCount
            currentCount = 1
            last = axis[i]
        end
    end
    groups[#groups + 1] = currentCount

    local maxInGroup = 1
    for i = 1, #groups do
        if groups[i] > maxInGroup then
            maxInGroup = groups[i]
        end
    end
    if maxInGroup <= 0 then
        return fallback
    end
    return maxInGroup
end

function RecenterViewer(viewer)
    local icons = GetVisibleButtons(viewer)
    local count = #icons
    if count == 0 then return end
    local viewerName = viewer.GetName and viewer:GetName() or ""
    local inEditMode = IsEditModeOpen()

    local first = icons[1]
    local w = first:GetWidth() or 0
    local h = first:GetHeight() or 0
    if w <= 0 or h <= 0 then return end

    local isHorizontal
    if viewerName == "EssentialCooldownViewer" or viewerName == "UtilityCooldownViewer" then
        isHorizontal = viewer.isHorizontal ~= false
    else
        isHorizontal = InferIsHorizontal(viewer, icons)
    end
    local iconDirection = viewer.iconDirection == 1 and "NORMAL" or "REVERSED"
    local iconDir = (iconDirection == "NORMAL") and 1 or -1

    local iconLimit = viewer.iconLimit or count
    if iconLimit <= 0 then
        iconLimit = count
    end
    if viewerName == "BuffIconCooldownViewer" then
        iconLimit = InferIconLimit(icons, isHorizontal, w, h, iconLimit)
    end
    if iconLimit <= 0 then
        iconLimit = count
    end

    local rows = BuildRows(iconLimit, icons)
    local rowCount = #rows
    if rowCount == 0 then return end

    local extraButtons = viewerName == "EssentialCooldownViewer" and GetVisibleEssentialTrinketButtons() or nil
    local extraCount = extraButtons and #extraButtons or 0

    local centerAdjustX, centerAdjustY = 0, 0
    if viewerName == "EssentialCooldownViewer" and not inEditMode then
        CaptureEssentialDesiredCenterFromViewer(viewer, false)
        if essentialDesiredCenter then
            local vx, vy = viewer:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if vx and vy and ux and uy then
                local visualOffsetX, visualOffsetY = GetEssentialVisualOffset(isHorizontal, isHorizontal and w or h, extraCount)
                local scale = viewer.GetEffectiveScale and viewer:GetEffectiveScale() or 1
                if scale <= 0 then
                    scale = 1
                end
                local currentRelX = vx - ux + (visualOffsetX * scale)
                local currentRelY = vy - uy + (visualOffsetY * scale)
                local deltaX = essentialDesiredCenter.x - currentRelX
                local deltaY = essentialDesiredCenter.y - currentRelY
                centerAdjustX = deltaX / scale
                centerAdjustY = deltaY / scale
            end
        end
    end

    local crossDir = 1
    if count > iconLimit then
        local a = icons[1]
        local b = icons[iconLimit + 1]
        if a and b then
            local ax, ay = a:GetCenter()
            local bx, by = b:GetCenter()
            if ax and ay and bx and by then
                if isHorizontal then
                    crossDir = (by - ay) >= 0 and 1 or -1
                else
                    crossDir = (bx - ax) >= 0 and 1 or -1
                end
            end
        end
    end

    if isHorizontal then
        local xPad = viewer.childXPadding or 0
        local yPad = viewer.childYPadding or xPad
        local rowStride = h + yPad
        local firstRowY = -((rowCount - 1) * rowStride * 0.5) * crossDir

        for r = 1, rowCount do
            local row = rows[r]
            local y = firstRowY + (r - 1) * rowStride * crossDir
            local xOffsets = CenteredOffsets(#row, w, xPad, iconDir)
            for i = 1, #row do
                local button = row[i]
                local x = xOffsets[i] or 0
                button:ClearAllPoints()
                button:SetPoint("CENTER", viewer, "CENTER", x + centerAdjustX, y + centerAdjustY)
            end
        end
    else
        local yPad = viewer.childYPadding or 0
        local xPad = viewer.childXPadding or yPad
        local colStride = w + xPad
        local firstColX = -((rowCount - 1) * colStride * 0.5) * crossDir
        local yDir = (iconDirection == "NORMAL") and -1 or 1

        for c = 1, rowCount do
            local col = rows[c]
            local x = firstColX + (c - 1) * colStride * crossDir
            local yOffsets = CenteredOffsets(#col, h, yPad, yDir)
            for i = 1, #col do
                local button = col[i]
                local yOffset = yOffsets[i] or 0
                button:ClearAllPoints()
                button:SetPoint("CENTER", viewer, "CENTER", x + centerAdjustX, yOffset + centerAdjustY)
            end
        end
    end

    if viewerName == "EssentialCooldownViewer" and extraButtons and #extraButtons > 0 then
        local attachGap = GetTrinketAttachGap()
        table.sort(extraButtons, function(a, b)
            return (a._myScriptsTrinketSlot or 0) < (b._myScriptsTrinketSlot or 0)
        end)

        local anchor = icons[#icons]
        if not anchor then
            anchor = viewer
        end

        for i = 1, #extraButtons do
            local button = extraButtons[i]
            button:ClearAllPoints()
            if isHorizontal then
                if i == 1 then
                    if anchor == viewer then
                        button:SetPoint("CENTER", viewer, "CENTER", centerAdjustX, centerAdjustY)
                    else
                        button:SetPoint("LEFT", anchor, "RIGHT", attachGap, 0)
                    end
                else
                    button:SetPoint("LEFT", extraButtons[i - 1], "RIGHT", attachGap, 0)
                end
            else
                if i == 1 then
                    if anchor == viewer then
                        button:SetPoint("CENTER", viewer, "CENTER", centerAdjustX, centerAdjustY)
                    else
                        button:SetPoint("TOP", anchor, "BOTTOM", 0, -attachGap)
                    end
                else
                    button:SetPoint("TOP", extraButtons[i - 1], "BOTTOM", 0, -attachGap)
                end
            end
        end
    end
end

MarkViewerDirty = function(viewer)
    if not viewer then return end
    dirtyViewers[viewer] = true
end

local function EnsureStateHooksForFrame(frame)
    if not frame or frame._myScriptsStateHooks == true then return end
    frame._myScriptsStateHooks = true

    if frame.OnActiveStateChanged then
        hooksecurefunc(frame, "OnActiveStateChanged", function(self)
            local p = self and self.GetParent and self:GetParent() or nil
            if p then MarkViewerDirty(p) end
        end)
    end
    if frame.OnUnitAuraAddedEvent then
        hooksecurefunc(frame, "OnUnitAuraAddedEvent", function(self)
            local p = self and self.GetParent and self:GetParent() or nil
            if p then MarkViewerDirty(p) end
        end)
    end
    if frame.OnUnitAuraRemovedEvent then
        hooksecurefunc(frame, "OnUnitAuraRemovedEvent", function(self)
            local p = self and self.GetParent and self:GetParent() or nil
            if p then MarkViewerDirty(p) end
        end)
    end

    frame:HookScript("OnHide", function(self)
        local p = self and self.GetParent and self:GetParent() or nil
        if p then MarkViewerDirty(p) end
    end)
    frame:HookScript("OnShow", function(self)
        local p = self and self.GetParent and self:GetParent() or nil
        if p then MarkViewerDirty(p) end
    end)
end

local function ProcessDirtyViewers()
    if not ENABLE_POSITIONING then return end
    for viewer in pairs(dirtyViewers) do
        RecenterViewer(viewer)
        dirtyViewers[viewer] = nil
    end
end

local function ApplyToAll()
    UpdateEssentialTrinketButtons()
    for i = 1, #VIEWER_NAMES do
        local viewer = _G[VIEWER_NAMES[i]]
        if viewer then
            local children = { viewer:GetChildren() }
            for j = 1, #children do
                StyleButton(children[j])
                EnsureStateHooksForFrame(children[j])
                if rotationHighlightViewers[VIEWER_NAMES[i]] then
                    UpdateRotationHighlightSize(children[j])
                end
            end
            if ENABLE_POSITIONING then
                MarkViewerDirty(viewer)
            end
        end
    end

    local buffBarViewer = _G.BuffBarCooldownViewer
    if buffBarViewer then
        local visibleCount = #GetVisibleTrackedBars(buffBarViewer)
        if visibleCount ~= trackedBarsVisibleCount then
            trackedBarsVisibleCount = visibleCount
            trackedBarsDirty = true
        end
    end
end

local function TryHookMixins()
    for i = 1, #MIXIN_NAMES do
        local mixinName = MIXIN_NAMES[i]
        if not hookedMixins[mixinName] then
            local mixin = _G[mixinName]
            if mixin and mixin.OnCooldownIDSet then
                hooksecurefunc(mixin, "OnCooldownIDSet", function(frame)
                    StyleButton(frame)
                    EnsureStateHooksForFrame(frame)
                    if frame and frame.GetParent then
                        local parent = frame:GetParent()
                        if parent and parent.GetName and rotationHighlightViewers[parent:GetName() or ""] then
                            rotationDirty = true
                            UpdateRotationHighlightSize(frame)
                        end
                        if parent and parent.GetName and parent:GetName() == "BuffBarCooldownViewer" then
                            trackedBarsDirty = true
                        end
                    end
                    local parent = frame and frame:GetParent() or nil
                    if parent and ENABLE_POSITIONING then
                        MarkViewerDirty(parent)
                    end
                end)
                hookedMixins[mixinName] = true
            end
        end
    end

    if not hookedMixins.CooldownViewerBuffBarItemMixin then
        local mixin = _G.CooldownViewerBuffBarItemMixin
        if mixin and mixin.OnCooldownIDSet then
            hooksecurefunc(mixin, "OnCooldownIDSet", function(frame)
                local parent = frame and frame.GetParent and frame:GetParent() or nil
                if parent and parent.GetName and parent:GetName() == "BuffBarCooldownViewer" then
                    trackedBarsDirty = true
                end
            end)
            hookedMixins.CooldownViewerBuffBarItemMixin = true
        end
    end
end

local driver = CreateFrame("Frame")
local elapsed = 0
local rotationElapsed = 0
local trackedBarsElapsed = 0

do
    local store = GetCooldownSkinStore()
    local desired = store.essentialDesiredCenter
    if type(desired) == "table" and type(desired.x) == "number" and type(desired.y) == "number" then
        essentialDesiredCenter = { x = desired.x, y = desired.y }
    end
end

driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("SPELLS_CHANGED")
driver:RegisterEvent("PLAYER_TALENT_UPDATE")
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
driver:RegisterEvent("TRAIT_CONFIG_UPDATED")
driver:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
driver:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
driver:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
driver:RegisterEvent("BAG_UPDATE_COOLDOWN")
driver:SetScript("OnEvent", function(_, event)
    local e = _G.EssentialCooldownViewer
    local inEditMode = IsEditModeOpen()

    if event == "PLAYER_ENTERING_WORLD" and e then
        CaptureEssentialDesiredCenterFromViewer(e, false)
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "SPELLS_CHANGED"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "PLAYER_EQUIPMENT_CHANGED"
    then
        QueueSpecRecenter()
    end
    TryHookMixins()
    ApplyToAll()
    trackedBarsDirty = true
    rotationDirty = true
    RefreshRotationHighlights(true)
    if ENABLE_POSITIONING and e and not inEditMode then
        MarkViewerDirty(e)
    end
end)

SLASH_MYSCRIPTSCDM1 = "/mscdm"
SlashCmdList.MYSCRIPTSCDM = function(msg)
    local arg = string.lower((msg or ""):match("^%s*(.-)%s*$"))
    if arg == "setcenter" then
        local viewer = _G.EssentialCooldownViewer
        if not viewer then
            if ns and ns.Print then ns.Print("MSCDM setcenter: EssentialCooldownViewer missing") end
            return
        end
        CaptureEssentialDesiredCenterFromViewer(viewer, true)
        if ns and ns.Print then
            ns.Print("MSCDM setcenter: desired center updated")
        end
        return
    end
    if ns and ns.Print then
        ns.Print("Usage: /mscdm setcenter")
    end
end

driver:SetScript("OnUpdate", function(_, dt)
    local inEditMode = IsEditModeOpen()
    if wasInEditMode and not inEditMode then
        local essential = _G.EssentialCooldownViewer
        if essential then
            CaptureEssentialDesiredCenterFromViewer(essential, true)
            if ENABLE_POSITIONING then
                MarkViewerDirty(essential)
            end
        end
    end
    wasInEditMode = inEditMode

    ProcessSpecRecenter(dt)
    ProcessDirtyViewers()
    if trackedBarsDirty then
        PositionTrackedBarsBottomUp()
        trackedBarsDirty = false
    end

    trackedBarsElapsed = trackedBarsElapsed + dt
    if trackedBarsElapsed >= TRACKED_BARS_ENFORCE_INTERVAL then
        trackedBarsElapsed = 0
        PositionTrackedBarsBottomUp()
    end

    rotationElapsed = rotationElapsed + dt
    if rotationElapsed >= ROTATION_SCAN_INTERVAL then
        rotationElapsed = 0
        RefreshRotationHighlights(false)
    end

    elapsed = elapsed + dt
    if elapsed < RESCAN_INTERVAL then return end
    elapsed = 0
    TryHookMixins()
    ApplyToAll()
end)

if AssistedCombatManager and AssistedCombatManager.UpdateAllAssistedHighlightFramesForSpell then
    hooksecurefunc(AssistedCombatManager, "UpdateAllAssistedHighlightFramesForSpell", function()
        rotationDirty = true
        RefreshRotationHighlights(false)
    end)
end

if ns and ns.Print then
    ns.Print("CooldownManagerSkin enabled.")
end
