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

local function Refresh()
    local db = ns.db
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
            if db[ns.KIND_KEY[n.kind] or "showHerb"] then
                local east, north = n.x - px, py - n.y
                list[#list + 1] = {
                    name = n.name, east = east, north = north, approx = n.approx,
                    dist = math.sqrt(east * east + north * north),
                    old = (now - n.seen) > (db.interval * 2 + 0.5),
                }
            end
        end
        table.sort(list, function(a, b) return a.dist < b.dist end)
    end
    -- Nodes the quick check saw but the scan had no time to locate yet
    -- (minus the ones of that name already shown with a position)
    local shown = {}
    for _, n in ipairs(list) do shown[n.name] = (shown[n.name] or 0) + 1 end
    for name, c in pairs(ns.unlocated or {}) do
        local kind = ns.Classify(name)
        if kind and db[ns.KIND_KEY[kind] or "showHerb"] then
            for _ = 1, c do list[#list + 1] = { name = name, unknown = true } end
        end
    end

    for i = 1, db.rows do
        local row, n = rows[i], list[i]
        if n and n.unknown then
            row.name:SetText(n.name)
            row.name:SetTextColor(1, 0.82, 0)
            row.dist:SetText("?")
            row.arrow:Hide()
        elseif n then
            row.name:SetText(n.name)
            row.dist:SetText(string.format(n.approx and "~%d" or "%d", n.dist))
            -- remembered (not currently seen) nodes are grey
            if n.old then
                row.name:SetTextColor(0.6, 0.6, 0.6)
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

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Gathering Nodes")

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
