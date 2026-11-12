-- Node Scanner Underlay: a stand-in map UNDER the real minimap.
--
-- While a scan moves the (invisible) real minimap away, this round map shows in its place:
-- the zone's world map art around you, your arrow and the known nodes, plus a
-- "Scanning for nodes" label above it. When the real minimap is back, it covers this again.

local _, ns = ...

local frame, mask, arrow, label, bg
local tiles, dots = {}, {}
local currentMap
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
            d:Show()
        end
    end
    for i = n + 1, #dots do dots[i]:Hide() end

    local facing = GetPlayerFacing()
    if facing and not ns.IsSecret(facing) then
        arrow:SetRotation(facing)
        arrow:Show()
    else
        arrow:Hide()
    end
end

updater:SetScript("OnUpdate", function() ns.SafeCall(Update) end)

-- A newly explored area changes the overlays: rebuild next time
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "MAP_EXPLORATION_UPDATED")     -- may not exist on every client
ev:SetScript("OnEvent", function() currentMap = nil end)

-- Called by the scanner BEFORE it moves the real minimap: take its exact place
function ns.UnderlayShow()
    if not ns.db.underlay then return end
    if not frame then Build() end
    local l, b, w, h = Minimap:GetRect()
    if not l then return end
    local s = Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * s, b * s)
    frame:SetSize(w * s, h * s)
    frame:SetFrameStrata(Minimap:GetFrameStrata())
    frame:SetFrameLevel(math.max(0, Minimap:GetFrameLevel() - 1))
    label:SetShown(ns.db.scanLabel)
    ns.SafeCall(Update)
    frame:Show()
    updater:Show()
end

-- /nscan maptest: show the stand-in map NEXT TO the real minimap for 15 s to compare
function ns.UnderlayTest()
    if not frame then Build() end
    local l, b, w, h = Minimap:GetRect()
    if not l then return end
    local s = Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale()
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
    if frame then frame:Hide() end
    updater:Hide()
end
