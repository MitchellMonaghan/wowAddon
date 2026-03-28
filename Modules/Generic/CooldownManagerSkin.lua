local _, ns = ...

-- Single-switch module toggle.
local ENABLED = true
if not ENABLED then return end

-- Main thickness control: bigger inset = thicker visible border.
local BORDER_REVEAL_INSET = 1
local BORDER_TEXTURE_EXTRA_PIXELS = 0
local BORDER_TEXTURE_SCALE = 0.96
local ICON_ZOOM = 0.08
local RESCAN_INTERVAL = 0.20
-- Set false if you still run CooldownManagerCentered and only want icon skinning here.
local ENABLE_POSITIONING = true

local MASK_PATH = [[Interface\AddOns\MyScripts\Media\Textures\csquare_mask.tga]]
local SWIPE_MASK_PATH = [[Interface\AddOns\CooldownManagerCentered\Media\Art\Square]]
local BORDER_TEXTURE_PATH = [[Interface\AddOns\MyScripts\Media\Textures\defaultEER.blp]]
-- `border_thin.blp` is not suitable here (it fills icon center on CDM buttons).

local VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
}

local MIXIN_NAMES = {
    "CooldownViewerBuffIconItemMixin",
    "CooldownViewerEssentialItemMixin",
    "CooldownViewerUtilityItemMixin",
}

local styledButtons = setmetatable({}, { __mode = "k" })
local hookedMixins = {}
local dirtyViewers = setmetatable({}, { __mode = "k" })
local viewerVisibleCounts = setmetatable({}, { __mode = "k" })
local floor = math.floor

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
    if not button or styledButtons[button] then return end
    if not button.Icon or not button.Cooldown then return end
    if not button.Icon.SetTexCoord then return end

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
        button.Cooldown:SetSwipeTexture(SWIPE_MASK_PATH)
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

local function GetVisibleButtons(viewer)
    local out = {}
    if not viewer then return out end
    local children = { viewer:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child and child.Icon and child.Cooldown and child:IsShown() and (child:GetAlpha() or 0) > 0 then
            out[#out + 1] = child
        end
    end
    table.sort(out, function(a, b)
        return (a.layoutIndex or 0) < (b.layoutIndex or 0)
    end)
    return out
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

local function RecenterViewer(viewer)
    local icons = GetVisibleButtons(viewer)
    local count = #icons
    if count == 0 then return end

    local first = icons[1]
    local w = first:GetWidth() or 0
    local h = first:GetHeight() or 0
    if w <= 0 or h <= 0 then return end

    local isHorizontal = InferIsHorizontal(viewer, icons)
    local iconDirection = viewer.iconDirection == 1 and "NORMAL" or "REVERSED"
    local iconDir = (iconDirection == "NORMAL") and 1 or -1

    local iconLimit = viewer.iconLimit or count
    if iconLimit <= 0 then
        iconLimit = count
    end
    iconLimit = InferIconLimit(icons, isHorizontal, w, h, iconLimit)
    if iconLimit <= 0 then
        iconLimit = count
    end

    local rows = BuildRows(iconLimit, icons)
    local rowCount = #rows
    if rowCount == 0 then return end

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
                button:ClearAllPoints()
                button:SetPoint("CENTER", viewer, "CENTER", xOffsets[i] or 0, y)
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
                button:ClearAllPoints()
                button:SetPoint("CENTER", viewer, "CENTER", x, yOffsets[i] or 0)
            end
        end
    end
end

local function MarkViewerDirty(viewer)
    if not viewer then return end
    dirtyViewers[viewer] = true
end

local function ProcessDirtyViewers()
    if not ENABLE_POSITIONING then return end
    for viewer in pairs(dirtyViewers) do
        RecenterViewer(viewer)
        dirtyViewers[viewer] = nil
    end
end

local function ApplyToAll()
    for i = 1, #VIEWER_NAMES do
        local viewer = _G[VIEWER_NAMES[i]]
        if viewer then
            local children = { viewer:GetChildren() }
            for j = 1, #children do
                StyleButton(children[j])
            end
            if ENABLE_POSITIONING then
                local visibleCount = #GetVisibleButtons(viewer)
                if viewerVisibleCounts[viewer] ~= visibleCount then
                    viewerVisibleCounts[viewer] = visibleCount
                    MarkViewerDirty(viewer)
                end
            end
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
                    local parent = frame and frame:GetParent() or nil
                    if parent and ENABLE_POSITIONING then
                        MarkViewerDirty(parent)
                    end
                end)
                hookedMixins[mixinName] = true
            end
        end
    end
end

local driver = CreateFrame("Frame")
local elapsed = 0

driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("SPELLS_CHANGED")
driver:SetScript("OnEvent", function()
    TryHookMixins()
    ApplyToAll()
    if ENABLE_POSITIONING then
        for i = 1, #VIEWER_NAMES do
            MarkViewerDirty(_G[VIEWER_NAMES[i]])
        end
    end
end)

driver:SetScript("OnUpdate", function(_, dt)
    ProcessDirtyViewers()

    elapsed = elapsed + dt
    if elapsed < RESCAN_INTERVAL then return end
    elapsed = 0
    TryHookMixins()
    ApplyToAll()
end)

if ns and ns.Print then
    ns.Print("CooldownManagerSkin enabled.")
end
