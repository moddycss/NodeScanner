-- Node Scanner - created with the help of AI (Claude). MIT licensed.
-- NodeScanner main window: name - distance - arrow for the nearest nodes.

local _, ns = ...

local ROW_HEIGHT, MAX_ROWS = 18, 10
local frame
local rows = {}

local function DefaultPosition()
    frame:ClearAllPoints()
    -- Anchor to the cluster, not to Minimap itself: the scanner moves Minimap around
    local anchor = MinimapCluster or UIParent
    if anchor == UIParent then
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -240)
    else
        frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -10)
    end
end

local warning, warnText, warnKind, warnedChat

local function UpdateWarning()
    local name, kind
    if ns.db.trackingWarning then name, kind = ns.MissingTracking() end
    if name then
        warnText:SetText("|cffff4040" .. name .. " is off|r - click to turn on")
        warnKind = kind
        if not warning:IsShown() then
            warning:Show()
            frame:SetHeight(28 + ns.db.rows * ROW_HEIGHT + ROW_HEIGHT)
            if not warnedChat then
                warnedChat = true
                print("|cff33ff99Node Scanner|r: |cffff4040" .. name .. " is off.|r Click the warning in the window to turn it on.")
                PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
            end
        end
    elseif warning:IsShown() then
        warning:Hide()
        warnedChat = false
        frame:SetHeight(28 + ns.db.rows * ROW_HEIGHT)
    end
end

local titleText, lastTitle

local KIND_TEXT = { ore = "Mining node", herb = "Herb", treasure = "Treasure" }
local DIRS = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }

-- Blue dot drawn ON TOP of the real minimap at the hovered node's position
local marker
local function UpdateMarker()
    local node = ns.hoverNode
    if not node or not ns.db then marker:Hide(); return end
    local _, px, py = ns.GetPlayerYards()
    if not px or not Minimap:IsVisible() then marker:Hide(); return end
    local mmS, uiS = Minimap:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    if not cx then marker:Hide(); return end
    local half = Minimap:GetWidth() / 2
    local radius = C_Minimap.GetViewRadius and C_Minimap.GetViewRadius() or 233
    local ux, uy = (node.x - px) / radius * half, (py - node.y) / radius * half
    local d = math.sqrt(ux * ux + uy * uy)
    local edge = half - 6
    if d > edge then ux, uy = ux / d * edge, uy / d * edge end   -- off the map: sit on the edge
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (cx + ux) * mmS / uiS, (cy + uy) * mmS / uiS)
    marker:Show()
end

local function BuildMarker()
    marker = CreateFrame("Frame", nil, UIParent)
    marker:SetSize(12, 12)
    marker:SetFrameStrata("HIGH")
    local t = marker:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetTexture("Interface\\AddOns\\NodeScanner\\Media\\NodeDot")
    t:SetVertexColor(0.25, 0.6, 1)                       -- blue
    marker:Hide()
    marker:SetScript("OnUpdate", function() ns.SafeCall(UpdateMarker) end)
end

local function ShowNodeTooltip(owner, e)
    if not e or e.unknown or not e.node then return end
    local n = e.node
    ns.hoverNode = n
    if not marker then BuildMarker() end
    UpdateMarker()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local r, g, b = ns.NodeColor(n.name)
    GameTooltip:AddLine(n.name, r or 1, g or 0.82, b or 0)
    local kind = KIND_TEXT[n.kind]
    if ns.IsCreatureKind(n.kind) then
        kind = ns.TRACKER[n.kind].label .. string.format(" - %d with this name nearby, showing the nearest", e.count or 1)
    end
    local item = ns.NodeItem and ns.NodeItem(n.name)
    local itemName = item and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)
    if kind then
        GameTooltip:AddLine(kind .. (itemName and (" - gives " .. itemName) or ""), 1, 1, 1)
    end
    -- compass direction from you to the node
    local angle = math.deg(math.atan2(e.east, e.north)) % 360
    local dir = DIRS[math.floor((angle + 22.5) / 45) % 8 + 1]
    GameTooltip:AddLine(string.format("%s%d yd %s", e.approx and "~" or "", e.dist, dir), 0.9, 0.9, 0.9)
    GameTooltip:AddLine(e.approx and "Rough position (within ~25 yd)" or "Exact position", 0.6, 0.6, 0.6)
    local ago = GetTime() - (n.seen or GetTime())
    GameTooltip:AddLine(ago < 2 and "Confirmed just now" or string.format("Last confirmed %d s ago", ago), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function Refresh()
    local db = ns.db
    local where = ns.PausedWhere and ns.PausedWhere()
    local t = where and ("Gathering Nodes |cff999999- paused (" .. where .. ")|r") or "Gathering Nodes"
    if ns.DISCONTINUED then t = "Gathering Nodes |cffff6060- discontinued (blocked by the game)|r" end
    if t ~= lastTitle then titleText:SetText(t); lastTitle = t end
    local _, px, py = ns.GetPlayerYards()

    local facing = GetPlayerFacing()
    if facing == nil or ns.IsSecret(facing) then
        facing = nil
        ns.LogOnce("facing", "WARN", "GetPlayerFacing() gave no value - arrows hidden")
    else
        ns.ClearOnce("facing")
    end

    local list = {}
    if px then
        local now = GetTime()
        for _, n in ipairs(ns.nodes) do
            if ns.ShowKind(n.kind) then
                local east, north = n.x - px, py - n.y
                list[#list + 1] = {
                    name = n.name, east = east, north = north, approx = n.approx, node = n,
                    dist = math.sqrt(east * east + north * north),
                    -- grey when not confirmed for a while (with herb/ore switching each
                    -- kind is only checked every other scan)
                    old = (now - n.seen) > (db.interval * 4 + 1),
                }
            end
        end
        table.sort(list, function(a, b) return a.dist < b.dist end)

        -- Mobs/NPCs: one line per name, pointing at the nearest one, with the count
        local grouped, firstOf = {}, {}
        for _, e in ipairs(list) do
            if ns.IsCreatureKind(e.node.kind) then
                local f = firstOf[e.name]
                if f then
                    f.count = f.count + 1                 -- list is sorted: the first one is nearest
                else
                    e.count, e.creature = 1, true
                    firstOf[e.name] = e
                    grouped[#grouped + 1] = e
                end
            else
                grouped[#grouped + 1] = e
            end
        end
        list = grouped
    end
    -- Nodes the quick check saw but the scan had no time to locate yet
    -- (minus the ones of that name already shown with a position)
    local shown = {}
    for _, n in ipairs(list) do shown[n.name] = (shown[n.name] or 0) + 1 end
    for name, c in pairs(ns.unlocated or {}) do
        local kind = ns.Classify(name)
        if kind and ns.ShowKind(kind) then
            for _ = 1, c do list[#list + 1] = { name = name, unknown = true } end
        end
    end

    for i = 1, db.rows do
        local row, n = rows[i], list[i]
        row.entry = n
        if n and n.unknown then
            row.name:SetText(n.name)
            row.name:SetTextColor(1, 0.82, 0)
            row.dist:SetText("?")
            row.arrow:Hide()
        elseif n then
            row.name:SetText(n.creature and string.format("%s (%d)", n.name, n.count) or n.name)
            row.dist:SetText(string.format(n.approx and "~%d" or "%d", n.dist))
            -- remembered (not currently seen) nodes are grey
            if n.old and not n.creature then
                row.name:SetTextColor(0.6, 0.6, 0.6)
            elseif n.creature then
                row.name:SetTextColor(1, 0.55, 0.45)        -- mobs / NPCs: light red
            else
                -- colour of the ore/herb rarity (white, green, blue, ...); chests stay gold
                local r, g, b = ns.NodeColor(n.name)
                if r then row.name:SetTextColor(r, g, b) else row.name:SetTextColor(1, 0.82, 0) end
            end
            if facing then
                -- 0 = arrow points straight ahead in the direction you are facing
                row.arrow:SetRotation(math.atan2(-n.east, n.north) - facing)
                row.arrow:Show()
            else
                row.arrow:Hide()
            end
        else
            row.name:SetTextColor(0.6, 0.6, 0.6)
            row.name:SetText(i == 1 and "No nodes nearby" or "")
            row.dist:SetText("")
            row.arrow:Hide()
        end
    end
end

local function Build()
    frame = CreateFrame("Frame", "NodeScannerFrame", UIParent, "BackdropTemplate")
    frame:SetWidth(230)
    frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not ns.db.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.pos = { point, relPoint, x, y }
    end)

    titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("TOPLEFT", 10, -8)
    titleText:SetText("Gathering Nodes")

    for i = 1, MAX_ROWS do
        local row = {}
        local y = -22 - (i - 1) * ROW_HEIGHT
        row.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", 10, y)
        row.name:SetWidth(150)
        row.name:SetJustifyH("LEFT")
        row.dist = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.dist:SetPoint("TOPRIGHT", -32, y)
        row.dist:SetJustifyH("RIGHT")
        row.arrow = frame:CreateTexture(nil, "OVERLAY")
        row.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
        row.arrow:SetSize(20, 20)
        row.arrow:SetPoint("TOPRIGHT", -8, y + 2)

        -- Invisible hover area over the row: tooltip with what the node is
        row.hover = CreateFrame("Frame", nil, frame)
        row.hover:SetPoint("TOPLEFT", 6, y + 2)
        row.hover:SetPoint("TOPRIGHT", -6, y + 2)
        row.hover:SetHeight(ROW_HEIGHT)
        row.hover:SetScript("OnEnter", function(self) ShowNodeTooltip(self, row.entry) end)
        row.hover:SetScript("OnLeave", function()
            GameTooltip:Hide()
            ns.hoverNode = nil
            if marker then marker:Hide() end
        end)
        -- let clicks and dragging the window still work through the row
        if row.hover.SetPropagateMouseClicks then row.hover:SetPropagateMouseClicks(true) end
        rows[i] = row
    end

    -- Warning line under the rows: tracking is off
    warning = CreateFrame("Button", nil, frame)
    warning:SetHeight(ROW_HEIGHT)
    warning:SetPoint("BOTTOMLEFT", 6, 6)
    warning:SetPoint("BOTTOMRIGHT", -6, 6)
    warnText = warning:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    warnText:SetPoint("LEFT", 4, 0)
    warning:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    warning:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        ns.EnableTracking(warnKind)
    end)
    warning:Hide()

    local p = ns.db.pos
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        DefaultPosition()
    end

    -- Arrows update 20 times per second; the minimap is swept on the ticker in Core
    local since, warnSince = 0, 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since >= 0.05 then
            since = 0
            ns.SafeCall(Refresh)
        end
        warnSince = warnSince + elapsed
        if warnSince >= 0.5 then
            warnSince = 0
            ns.SafeCall(UpdateWarning)
        end
    end)

    ns.ApplyWindowSettings()
end

function ns.ApplyWindowSettings()
    if not frame then return end
    local db = ns.db
    frame:SetHeight(28 + db.rows * ROW_HEIGHT + ((warning and warning:IsShown()) and ROW_HEIGHT or 0))
    frame:SetBackdropColor(0, 0, 0, db.bgAlpha)
    frame:SetBackdropBorderColor(0.8, 0.8, 0.8, math.min(1, db.bgAlpha + 0.4))
    frame:SetScale(db.scale)
    for i, row in ipairs(rows) do
        local show = i <= db.rows
        row.name:SetShown(show)
        row.dist:SetShown(show)
        if not show then row.arrow:Hide() end
    end
    frame:SetShown(db.shown)
end

function ns.ResetWindowPosition()
    ns.db.pos = nil
    if frame then DefaultPosition() end
end

function ns.ToggleWindow()
    ns.db.shown = not ns.db.shown
    if frame then frame:SetShown(ns.db.shown) end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

ns.OnInit(Build)
