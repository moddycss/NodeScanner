-- Node Scanner Underlay: a stand-in map UNDER the real minimap.
--
-- While a scan moves the (invisible) real minimap away, this round map shows in its place:
-- the zone's world map art around you, your arrow and the known nodes, plus a
-- "Scanning for nodes" label above it. When the real minimap is back, it covers this again.

local _, ns = ...

local frame, mask, arrow, label, bg
local tiles, dots = {}, {}
local currentMap
local replacing = false            -- "Always use the stand-in map" is active
local updater = CreateFrame("Frame")
updater:Hide()

local function Build()
    frame = CreateFrame("Frame", "NodeScannerUnderlay", UIParent)
    frame:Hide()

    mask = frame:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(frame)

    bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0.08, 0.08, 0.06, 1)
    bg:AddMaskTexture(mask)

    arrow = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrow:SetSize(28, 28)
    arrow:SetPoint("CENTER")

    label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", frame, "TOP", 0, 4)
    label:SetText("Scanning for nodes")
end

-- Zone map art tiles (from the game's own world map textures)
local function LoadArt(mapID)
    for _, t in ipairs(tiles) do t:Hide() end
    currentMap = mapID
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
    local info = layers and layers[1]
    if not info then return nil end
    local textures = C_Map.GetMapArtLayerTextures(mapID, 1) or {}
    local cols = math.ceil(info.layerWidth / info.tileWidth)
    for i, fileID in ipairs(textures) do
        local t = tiles[i]
        if not t then
            t = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
            t:AddMaskTexture(mask)
            tiles[i] = t
        end
        t:SetTexture(fileID)
        t.col, t.row = (i - 1) % cols, math.floor((i - 1) / cols)
        t:Show()
    end
    frame.art = info
    frame.tileCount = #textures

    -- Explored areas: in Classic-style maps the base art is mostly empty and every explored
    -- area is its own overlay image (same as Blizzard's world map fog of war)
    for _, t in ipairs(frame.overlays or {}) do t:Hide() end
    frame.overlays = frame.overlays or {}
    local n = 0
    local explored = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
        and C_MapExplorationInfo.GetExploredMapTextures(mapID)
    local TILE = 256
    for _, e in ipairs(explored or {}) do
        if not e.isShownByMouseOver and e.fileDataIDs then
            local wide = math.ceil(e.textureWidth / TILE)
            local tall = math.ceil(e.textureHeight / TILE)
            for j = 1, tall do
                local ph = (j < tall) and TILE or (e.textureHeight % TILE)
                if ph == 0 then ph = TILE end
                local fh = 16
                while fh < ph do fh = fh * 2 end
                for k = 1, wide do
                    local pw = (k < wide) and TILE or (e.textureWidth % TILE)
                    if pw == 0 then pw = TILE end
                    local fw = 16
                    while fw < pw do fw = fw * 2 end
                    local fid = e.fileDataIDs[(j - 1) * wide + k]
                    if fid then
                        n = n + 1
                        local t = frame.overlays[n]
                        if not t then
                            t = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
                            t:AddMaskTexture(mask)
                            frame.overlays[n] = t
                        end
                        t:SetTexture(fid, nil, nil, "TRILINEAR")
                        t:SetTexCoord(0, pw / fw, 0, ph / fh)
                        t.ax, t.ay = e.offsetX + TILE * (k - 1), e.offsetY + TILE * (j - 1)
                        t.aw, t.ah = pw, ph
                        t:Show()
                    end
                end
            end
        end
    end
    frame.overlayCount = n
end

-- Real minimap terrain: the game's own minimap images, picked by world position.
-- The continents are a 64 x 64 grid of 533.33-yard squares (see MinimapTiles.lua).
local TILE_YARDS = 1600 / 3
local terrain = {}
local function DrawTerrain(mapID, unitsPerYard)
    local tbl = ns.MinimapTiles
    if not (tbl and C_Map.GetWorldPosFromMapPos) then return false end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return false end
    local ok, cont, wpos = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos)
    if not ok or not cont or not wpos or not tbl[cont] then return false end
    local wx, wy = wpos:GetXY()                      -- world x = north, world y = west
    local gx, gy = 32 - wy / TILE_YARDS, 32 - wx / TILE_YARDS
    local size = TILE_YARDS * unitsPerYard
    local n = 0
    for ty = math.floor(gy) - 1, math.floor(gy) + 1 do
        for tx = math.floor(gx) - 1, math.floor(gx) + 1 do
            local fid = tx >= 0 and tx < 64 and ty >= 0 and ty < 64 and tbl[cont][ty * 64 + tx]
            if fid then
                n = n + 1
                local t = terrain[n]
                if not t then
                    t = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
                    t:AddMaskTexture(mask)
                    terrain[n] = t
                end
                t:SetTexture(fid)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", frame, "CENTER", (tx - gx) * size, -(ty - gy) * size)
                t:SetSize(size, size)
                t:Show()
            end
        end
    end
    for i = n + 1, #terrain do terrain[i]:Hide() end
    return n > 0
end

local function Update()
    local mapID, px, py = ns.GetPlayerYards()
    if not mapID then return end
    if mapID ~= currentMap then LoadArt(mapID) end
    local w, h = C_Map.GetMapWorldSize(mapID)
    local half = frame:GetWidth() / 2
    local radius = C_Minimap.GetViewRadius and C_Minimap.GetViewRadius() or 233
    local unitsPerYard = half / radius

    -- Real minimap terrain if we have it for this continent, else the world map art
    local hasTerrain = ns.db.minimapTerrain and DrawTerrain(mapID, unitsPerYard)
    if not hasTerrain then for _, t in ipairs(terrain) do t:Hide() end end
    for i = 1, frame.tileCount or 0 do tiles[i]:SetShown(not hasTerrain) end
    for i = 1, frame.overlayCount or 0 do frame.overlays[i]:SetShown(not hasTerrain) end
    frame.mode = hasTerrain and "minimap terrain" or "world map art"

    -- Map art: art pixels -> screen units
    local art = frame.art
    if not hasTerrain and art and w and w > 0 then
        local artPerYard = art.layerWidth / w
        local k = unitsPerYard / artPerYard
        local ax, ay = px * artPerYard, py * (art.layerHeight / h)   -- player in art pixels
        for i = 1, frame.tileCount or 0 do
            local t = tiles[i]
            local x0, y0 = t.col * art.tileWidth, t.row * art.tileHeight
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", frame, "CENTER", (x0 - ax) * k, -(y0 - ay) * k)
            t:SetSize(art.tileWidth * k, art.tileHeight * k)
        end
        for i = 1, frame.overlayCount or 0 do
            local t = frame.overlays[i]
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", frame, "CENTER", (t.ax - ax) * k, -(t.ay - ay) * k)
            t:SetSize(t.aw * k, t.ah * k)
        end
    end

    -- Known nodes as yellow dots, like on the real minimap
    local n = 0
    for _, node in ipairs(ns.nodes) do
        local ex, ny = (node.x - px) * unitsPerYard, (py - node.y) * unitsPerYard
        if ex * ex + ny * ny <= (half - 4) ^ 2 then
            n = n + 1
            local d = dots[n]
            if not d then
                -- Round dot like the minimap's node dot (white texture, coloured yellow)
                d = frame:CreateTexture(nil, "ARTWORK")
                d:SetTexture("Interface\\AddOns\\NodeScanner\\Media\\NodeDot")
                d:SetSize(10, 10)
                d:AddMaskTexture(mask)
                dots[n] = d
            end
            if node.kind == "treasure" then
                d:SetVertexColor(0.2, 1, 0.2)                -- treasure: green
            elseif ns.IsCreatureKind(node.kind) then
                d:SetVertexColor(1, 0.3, 0.25)               -- mobs / NPCs: red
            else
                d:SetVertexColor(1, 0.82, 0)                 -- yellow, like the real minimap
            end
            d:ClearAllPoints()
            d:SetPoint("CENTER", frame, "CENTER", ex, ny)
            d.ex, d.ny, d.node = ex, ny, node
            d:Show()
        end
    end
    for i = n + 1, #dots do dots[i]:Hide() end
    frame.dotCount = n

    local facing = GetPlayerFacing()
    if facing and not ns.IsSecret(facing) then
        arrow:SetRotation(facing)
        arrow:Show()
    else
        arrow:Hide()
    end
end

----------------------------------------------------------------------
-- Tooltips for our dots, like the minimap's own: when the real minimap is hidden for good,
-- its dots can't be seen, and our (rough) dot may not sit exactly on the real one.
-- The real minimap's tooltip wins whenever it has something to say.
----------------------------------------------------------------------
local ownTip = false
local anchorType = "ANCHOR_LEFT"          -- learned from the minimap's own tooltip
local HOVER = 7                            -- UI units around a dot

local function HideOwnTip()
    if ownTip and GameTooltip:GetOwner() == frame then GameTooltip:Hide() end
    ownTip = false
end

local function UpdateTooltip()
    if not (replacing and frame:IsShown()) or (ns.IsScanning and ns.IsScanning()) then
        HideOwnTip(); return
    end
    -- the minimap's own tooltip: let it be, and learn where it puts itself
    if GameTooltip:IsShown() and GameTooltip:GetOwner() == Minimap then
        local a = GameTooltip.GetAnchorType and GameTooltip:GetAnchorType()
        if a and a ~= "ANCHOR_NONE" then anchorType = a end
        ownTip = false
        return
    end
    if not frame:IsMouseOver() then HideOwnTip(); return end
    local real = C_TooltipInfo.GetMinimapMouseover()
    if real and not ns.IsSecret(real) and real.lines and #real.lines > 0 then
        HideOwnTip()                         -- the game shows its own tooltip now
        return
    end
    local cx, cy = GetCursorPosition()
    local s = frame:GetEffectiveScale()
    local fx, fy = frame:GetCenter()
    cx, cy = cx / s - fx, cy / s - fy
    local names, seenName = {}, {}
    for i = 1, frame.dotCount or 0 do
        local d = dots[i]
        if (d.ex - cx) ^ 2 + (d.ny - cy) ^ 2 <= HOVER * HOVER and d.node then
            local name = d.node.name
            if not seenName[name] then seenName[name] = true; names[#names + 1] = name end
        end
    end
    if #names == 0 then HideOwnTip(); return end
    local text = table.concat(names, "\n")
    -- owned by our map (same place and size as the minimap): the minimap would hide a
    -- tooltip it owns when it has nothing under the mouse itself
    if ownTip == text and GameTooltip:IsShown() and GameTooltip:GetOwner() == frame then return end
    GameTooltip:SetOwner(frame, anchorType)
    GameTooltip:SetText(text, 1, 1, 1)
    GameTooltip:Show()
    ownTip = text
end

updater:SetScript("OnUpdate", function()
    ns.SafeCall(Update)
    ns.SafeCall(UpdateTooltip)
end)

-- A newly explored area changes the overlays: rebuild next time
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "MAP_EXPLORATION_UPDATED")     -- may not exist on every client
ev:SetScript("OnEvent", function() currentMap = nil end)

-- Copies of the real minimap's own pieces: border, sun/moon, tracking button, mail icon,
-- coordinates ... Same texture/text, size and position, so the stand-in map looks like the
-- minimap. Two groups:
--   kids  = everything inside the minimap frame (hidden while scanning; in "replace" mode the
--           whole real minimap is invisible, so these copies are what you see)
--   over  = things attached to the minimap from outside (also hidden while scanning)
-- The real buttons stay where they are, so clicking a copy clicks the real (invisible) one.
local groups = { kids = { tex = {}, fs = {}, masks = {}, frames = {} },
                 over = { tex = {}, fs = {}, masks = {}, frames = {} } }

-- Stacking order of the copies: every copy sits in the SAME strata and frame level as the
-- real piece it copies. Then the real buttons that stay visible during a scan (e.g. the
-- sun/moon and the tracking button) are still drawn above the copied ring, as normal.
local STRATA_NAMES = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN",
                       "FULLSCREEN_DIALOG", "TOOLTIP" }
local STRATA = {}
for i, n in ipairs(STRATA_NAMES) do STRATA[n] = i end

local function Container(g, key)
    local c = g.frames[key]
    if not c then
        c = CreateFrame("Frame", nil, frame)
        c:SetAllPoints(frame)
        g.frames[key] = c
    end
    local strata = frame.testMode and "HIGH" or STRATA_NAMES[math.floor(key / 100000)] or "LOW"
    c:SetFrameStrata(strata)
    c:SetFrameLevel(key % 100000)
    c:Show()
    return c
end

local function CloneInto(g, roots)
    for _, t in ipairs(g.tex) do t:Hide() end
    for _, f in ipairs(g.fs) do f:Hide() end
    for _, c in pairs(g.frames) do c:Hide() end
    g.nt, g.nf, g.nm = 0, 0, 0
    local l0, b0, w0 = Minimap:GetRect()
    if not l0 then return end
    local uiS = UIParent:GetEffectiveScale()
    local k0 = Minimap:GetEffectiveScale() / uiS
    l0, b0, w0 = l0 * k0, b0 * k0, w0 * k0
    local baseLevel = Minimap:GetFrameLevel()
    local seen = {}

    local function Rect(region)
        local l, b, w, h = region:GetRect()
        if not l or w <= 0 or h <= 0 then return end
        local k = region:GetEffectiveScale() / uiS
        return l * k - l0, b * k - b0, w * k, h * k
    end
    local function LevelOf(region)
        local p = region.GetParent and region:GetParent()
        local strata = p and p.GetFrameStrata and p:GetFrameStrata() or "LOW"
        local level = p and p.GetFrameLevel and p:GetFrameLevel() or baseLevel
        return (STRATA[strata] or 2) * 100000 + math.min(level, 9999)
    end

    local function CopyTexture(region)
        local layer, sub = region:GetDrawLayer()
        if layer == "HIGHLIGHT" then return end              -- only shown on mouseover
        local x, y, w, h = Rect(region)
        if not x then return end
        local big = w >= w0 * 0.6
        if big and not ns.db.underlayBorder then return end
        local atlas = region.GetAtlas and region:GetAtlas()
        local tex = region:GetTexture()
        if not atlas and not tex then return end
        g.nt = g.nt + 1
        local c = g.tex[g.nt]
        if not c then c = frame:CreateTexture(); g.tex[g.nt] = c end
        c:SetParent(Container(g, LevelOf(region)))
        c:SetDrawLayer(layer or "ARTWORK", sub or 0)
        for i = c:GetNumMaskTextures(), 1, -1 do c:RemoveMaskTexture(c:GetMaskTexture(i)) end
        if atlas then c:SetAtlas(atlas) else c:SetTexture(tex) end
        c:SetTexCoord(region:GetTexCoord())
        c:SetVertexColor(region:GetVertexColor())
        c:SetAlpha(region:GetAlpha())
        c:SetBlendMode(region:GetBlendMode())
        pcall(function() c:SetRotation(region:GetRotation()) end)
        c:ClearAllPoints()
        c:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, y)
        c:SetSize(w, h)
        -- round icons are cut out with a mask: copy that too
        pcall(function()
            for i = 1, region:GetNumMaskTextures() do
                local m = region:GetMaskTexture(i)
                local mx, my, mw, mh = Rect(m)
                local mt = m.GetTexture and m:GetTexture()
                if mx and mt then
                    g.nm = g.nm + 1
                    local cm = g.masks[g.nm]
                    if not cm then cm = frame:CreateMaskTexture(); g.masks[g.nm] = cm end
                    cm:SetTexture(mt, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    cm:ClearAllPoints()
                    cm:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", mx, my)
                    cm:SetSize(mw, mh)
                    c:AddMaskTexture(cm)
                end
            end
        end)
        c:Show()
    end

    local function CopyText(region)
        local text = region:GetText()
        if not text or text == "" then return end
        local x, y, w, h = Rect(region)
        if not x then return end
        g.nf = g.nf + 1
        local c = g.fs[g.nf]
        if not c then c = frame:CreateFontString(); g.fs[g.nf] = c end
        c:SetParent(Container(g, LevelOf(region)))
        local layer, sub = region:GetDrawLayer()
        c:SetDrawLayer(layer or "OVERLAY", sub or 0)
        local font, size, flags = region:GetFont()
        if not font then return end
        c:SetFont(font, size * region:GetEffectiveScale() / uiS, flags)
        c:SetTextColor(region:GetTextColor())
        c:SetShadowColor(region:GetShadowColor())
        c:SetShadowOffset(region:GetShadowOffset())
        c:SetJustifyH(region:GetJustifyH())
        c:SetJustifyV(region:GetJustifyV())
        c:SetAlpha(region:GetAlpha())
        c:ClearAllPoints()
        c:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, y)
        c:SetSize(w + 2, h)
        c:SetText(text)
        c:Show()
    end

    local function Copy(region)
        if seen[region] then return end
        seen[region] = true
        pcall(function()
            if not region:IsShown() then return end
            local kind = region:GetObjectType()
            if kind == "Texture" then CopyTexture(region)
            elseif kind == "FontString" then CopyText(region) end
        end)
    end
    local function Walk(f, depth)
        if not f or seen[f] then return end
        local okUse = pcall(function()
            if f.IsForbidden and f:IsForbidden() then error("forbidden") end
        end)
        if not okUse then return end
        local name = f.GetName and f:GetName()
        if name == "NodeScannerUnderlay" then return end
        local ot = f.GetObjectType and f:GetObjectType()
        if ot == "Texture" or ot == "FontString" then Copy(f); return end
        if not f.GetRegions then return end
        seen[f] = true
        if not f:IsShown() then return end
        for _, r in ipairs({ f:GetRegions() }) do Copy(r) end
        if depth > 0 then
            for _, c in ipairs({ f:GetChildren() }) do Walk(c, depth - 1) end
        end
    end
    for _, root in ipairs(roots) do pcall(Walk, root, 4) end
end

local function CloneKids()
    -- the minimap's own regions and child frames (not the minimap frame itself twice)
    CloneInto(groups.kids, { Minimap })
end
local function CloneOverlays()
    local list = ns.MinimapOverlays and ns.MinimapOverlays() or {}
    CloneInto(groups.over, list)
end
local function CloneAll()
    ns.SafeCall(CloneKids)
    ns.SafeCall(CloneOverlays)
end
local function HideGroup(g)
    for _, c in pairs(g.frames) do c:Hide() end
end

----------------------------------------------------------------------
-- "Replace the minimap": the stand-in map is shown all the time and the real minimap is
-- made invisible (it stays in its place, so mouseover tooltips, clicks, zoom and its
-- buttons still work - you just see our copies). Only where we have minimap terrain
-- (Eastern Kingdoms and Kalimdor, outdoors); everywhere else the real minimap is shown.
----------------------------------------------------------------------
local function PlaceAtMinimap()
    local l, b, w, h = Minimap:GetRect()
    if not l then return false end
    frame.testMode = false
    local s = Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * s, b * s)
    frame:SetSize(w * s, h * s)
    frame:SetFrameStrata(Minimap:GetFrameStrata())
    frame:SetFrameLevel(math.max(0, Minimap:GetFrameLevel() - 1))
    return true
end

local function StopReplacing()
    if not replacing then return end
    if ns.IsScanning and ns.IsScanning() then return end   -- after the scan
    replacing = false
    HideOwnTip()
    Minimap:SetAlpha(1)
    if frame then frame:Hide() end
    updater:Hide()
end

function ns.ReplaceActive() return replacing end

local function ReplaceTick()
    if ns.IsScanning and ns.IsScanning() then return end        -- the scan owns the minimap now
    local want = ns.db and ns.db.replaceMinimap and ns.db.underlay
        and ns.db.minimapTerrain and not IsIndoors()
    if not want then StopReplacing(); return end
    if not frame then Build() end
    if not PlaceAtMinimap() then return end
    label:Hide()
    ns.SafeCall(Update)
    if frame.mode ~= "minimap terrain" then StopReplacing(); return end   -- no terrain here
    ns.SafeCall(CloneKids)
    HideGroup(groups.over)
    frame:Show()
    updater:Show()
    if Minimap:GetAlpha() > 0 then Minimap:SetAlpha(0) end
    replacing = true
end
C_Timer.NewTicker(0.2, function() ns.SafeCall(ReplaceTick) end)

-- Called by the scanner BEFORE it moves the real minimap: take its exact place
function ns.UnderlayShow()
    if not ns.db.underlay then return end
    if not frame then Build() end
    if not PlaceAtMinimap() then return end
    label:SetShown(ns.db.scanLabel)
    -- copy the minimap's pieces before the scanner hides them
    CloneAll()
    ns.SafeCall(Update)
    frame:Show()
    updater:Show()
end

-- /nscan maptest: show the stand-in map NEXT TO the real minimap for 15 s to compare
function ns.UnderlayTest()
    if not frame then Build() end
    if replacing then print("|cff33ff99Node Scanner|r: map test is not needed - the minimap is replaced"); return end
    local l, b, w, h = Minimap:GetRect()
    if not l then return end
    local s = Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale()
    frame.testMode = true
    frame:SetFrameStrata("HIGH")
    CloneAll()
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", l * s - 20, b * s)
    frame:SetSize(w * s, h * s)
    frame:SetFrameStrata("HIGH")
    label:SetText("Stand-in map (test)")
    label:Show()
    ns.SafeCall(Update)
    frame:Show()
    updater:Show()
    ns.Log("INFO", "Map test: showing %s", frame.mode or "?")
    print("|cff33ff99Node Scanner|r: map test - left of your minimap for 15 s (" .. (frame.mode or "?") .. ")")
    C_Timer.After(15, function()
        label:SetText("Scanning for nodes")
        if not (ns.IsScanning and ns.IsScanning()) then ns.UnderlayHide() end
    end)
end

-- Called when the real minimap is back
function ns.UnderlayHide()
    if replacing and ns.db.replaceMinimap then
        if label then label:Hide() end
        HideGroup(groups.over)          -- the real ones are back
        if frame then PlaceAtMinimap() end
        return
    end
    if frame then frame:Hide() end
    updater:Hide()
end

-- Options: switching modes
function ns.ApplyMapMode()
    if not ns.db.replaceMinimap then StopReplacing() end
    ns.SafeCall(ReplaceTick)
end
