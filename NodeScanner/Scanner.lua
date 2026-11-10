-- NodeScanner Scanner: finds the yellow dots on the minimap.
--
-- Since client build 70862 the minimap only reports the dot under the REAL mouse cursor.
-- So, like Minimap Alert, we move the minimap under the cursor and read what it reports.
--
-- Two phases per scan (ideas taken from Minimap Alert):
--   1. Quick check: shrink the minimap to 15 % under the cursor. Then one point covers
--      nearly the whole map, so a few frames tell us IF there are any nodes.
--   2. Locate: only if the quick check found a node, sweep a grid at normal size to
--      find WHERE each node is (distance + arrow).
--
-- While scanning the minimap is made invisible: alpha, its buttons and borders, the dot
-- icons (icon scale 0), the game tooltip that pops up, and quest areas are all hidden.
-- The game needs a frame or two after each move before it reports the dot; calibration
-- measures that ("dwell") and the lowest opacity that still works.

local _, ns = ...
local mm = Minimap

local DISCOVER_SCALE = 0.15
local DISCOVER_READS = 4
local ALPHAS = { 0, 0.02, 0.15, 1 }

local job                          -- the running job (nil = idle)
local runner = CreateFrame("Frame")
runner:Hide()

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function ReadNames()
    local names = {}
    local data = C_TooltipInfo.GetMinimapMouseover()
    if not data or ns.IsSecret(data) or not data.lines then return names end
    for _, line in ipairs(data.lines) do
        local raw = ns.Clean(line.leftText)
        if raw then
            for part in raw:gmatch("[^\n]+") do         -- stacked dots come as separate lines
                local n = ns.Clean(part)
                if n then names[#names + 1] = n end
            end
        end
    end
    return names
end

local function ViewRadius()
    return C_Minimap.GetViewRadius and C_Minimap.GetViewRadius() or 233
end

----------------------------------------------------------------------
-- Making the minimap invisible and putting everything back
----------------------------------------------------------------------
local saved
local muteTooltip, muteGuard = false, false

local function KeepTooltipHidden(self)
    if muteTooltip and not muteGuard then
        muteGuard = true
        self:SetAlpha(0)
        muteGuard = false
    end
end
GameTooltip:HookScript("OnShow", KeepTooltipHidden)
hooksecurefunc(GameTooltip, "SetAlpha", KeepTooltipHidden)

local function GetIconScale()
    local setting = Enum and Enum.EditModeMinimapSetting and Enum.EditModeMinimapSetting.IconScale
    if setting and MinimapCluster and MinimapCluster.GetSettingValue then
        local ok, value = pcall(MinimapCluster.GetSettingValue, MinimapCluster, setting)
        if ok and type(value) == "number" then return value / 100 end
    end
end

local function QuestTrackingIndex()
    local filter = Enum and Enum.MinimapTrackingFilter and Enum.MinimapTrackingFilter.QuestPOIs
    if not (filter and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingFilter) then return end
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local f = C_Minimap.GetTrackingFilter(i)
        if f and f.filterID == filter then
            local info = C_Minimap.GetTrackingInfo(i)
            if info and info.active then return i end
            return
        end
    end
end

-- Frames and texts that are attached to the minimap but are not its children (for example
-- the coordinates under it) move along with it and would show up at the cursor during a
-- scan. Find them (like Minimap Alert does) and hide them while scanning.
local function IsMinimapOrChild(obj)
    local cur = obj
    for _ = 1, 20 do
        if cur == mm then return true end
        if not cur or not cur.GetParent then return false end
        local ok, parent = pcall(cur.GetParent, cur)
        if not ok then return false end
        cur = parent
    end
    return false
end

local function AnchoredToMinimap(obj)
    if not obj or not obj.GetNumPoints then return false end
    local ok, result = pcall(function()
        for i = 1, math.min(obj:GetNumPoints(), 4) do
            local _, rel = obj:GetPoint(i)
            if rel and IsMinimapOrChild(rel) then return true end
        end
        return false
    end)
    return ok and result
end

local overlayCache, overlayCacheTime = nil, 0
local function MinimapOverlays()
    if overlayCache and GetTime() - overlayCacheTime < 30 then return overlayCache end
    local list, visited = {}, {}
    local function Usable(obj)
        -- Blizzard's forbidden/protected frames must not be touched by addons
        local ok, bad = pcall(function()
            if obj.IsForbidden and obj:IsForbidden() then return true end
            if obj.IsProtected and obj:IsProtected() then return true end
            return false
        end)
        return ok and not bad
    end
    local function Consider(obj)
        if not obj or visited[obj] then return end
        visited[obj] = true
        if not Usable(obj) then return end
        if IsMinimapOrChild(obj) then return end
        if AnchoredToMinimap(obj) then list[#list + 1] = obj end
    end
    local function Kids(frame, method)
        local ok, t = pcall(function() return { frame[method](frame) } end)
        return ok and t or {}
    end
    local function Walk(frame, depth)
        if not frame or not Usable(frame) then return end
        Consider(frame)
        for _, r in ipairs(Kids(frame, "GetRegions")) do Consider(r) end
        if depth > 0 then
            for _, c in ipairs(Kids(frame, "GetChildren")) do Walk(c, depth - 1) end
        end
    end
    for _, c in ipairs(Kids(UIParent, "GetChildren")) do
        if Usable(c) then
            Consider(c)
            for _, r in ipairs(Kids(c, "GetRegions")) do Consider(r) end
        end
    end
    if MinimapCluster then Walk(MinimapCluster, 4) end
    overlayCache, overlayCacheTime = list, GetTime()
    return list
end

local function Prepare(alpha)
    if saved then return end
    local s = {
        points = {}, children = {}, regions = {},
        strata = mm:GetFrameStrata(), level = mm:GetFrameLevel(),
        alpha = mm:GetAlpha(), scale = mm:GetScale(),
        ttAlpha = GameTooltip:GetAlpha(),
        ttOwner = GameTooltip:IsShown() and GameTooltip:GetOwner() or nil,
    }
    for i = 1, mm:GetNumPoints() do s.points[i] = { mm:GetPoint(i) } end
    saved = s

    mm:SetFrameStrata("TOOLTIP")
    mm:SetAlpha(alpha)
    if mm.IsMouseClickEnabled then
        s.click = mm:IsMouseClickEnabled()
        mm:SetMouseClickEnabled(false)                   -- clicks go through to the world
    end
    for _, c in ipairs({ mm:GetChildren() }) do
        pcall(function()
            if c:IsShown() and not (c.IsForbidden and c:IsForbidden()) and not (c.IsProtected and c:IsProtected()) then
                c:Hide()
                s.children[#s.children + 1] = c
            end
        end)
    end
    for _, r in ipairs({ mm:GetRegions() }) do
        pcall(function()
            if r:IsShown() then
                r:Hide()
                s.regions[#s.regions + 1] = r
            end
        end)
    end
    if mm.SetIconScale then
        s.iconScale = GetIconScale()
        if s.iconScale then mm:SetIconScale(0) end
    end
    if ns.db.hideQuestAreas then
        s.questTracking = QuestTrackingIndex()
        if s.questTracking then C_Minimap.SetTracking(s.questTracking, false) end
    end
    s.overlays = {}
    local okList, overlays = pcall(MinimapOverlays)
    for _, o in ipairs(okList and overlays or {}) do
        pcall(function()
            if o:IsShown() then
                o:Hide()
                s.overlays[#s.overlays + 1] = o
            end
        end)
    end
    muteTooltip = true
    GameTooltip:SetAlpha(0)
end

local function Restore()
    local s = saved
    if not s then return end
    saved = nil
    -- Every step on its own, so one failure can't leave the minimap hidden
    local function try(f) local ok, err = pcall(f); if not ok then ns.Log("ERR", "Restore: %s", tostring(err)) end end
    try(function()
        mm:ClearAllPoints()
        for _, p in ipairs(s.points) do mm:SetPoint(unpack(p)) end
    end)
    try(function() mm:SetScale(s.scale) end)
    try(function() mm:SetFrameStrata(s.strata); mm:SetFrameLevel(s.level) end)
    try(function() mm:SetAlpha(s.alpha) end)
    try(function() if s.click ~= nil then mm:SetMouseClickEnabled(s.click) end end)
    for _, c in ipairs(s.children or {}) do pcall(c.Show, c) end
    for _, r in ipairs(s.regions or {}) do pcall(r.Show, r) end
    try(function() if s.iconScale then mm:SetIconScale(s.iconScale) end end)
    try(function() if s.questTracking then C_Minimap.SetTracking(s.questTracking, true) end end)
    for _, o in ipairs(s.overlays or {}) do pcall(o.Show, o) end
    muteTooltip = false
    try(function()
        if GameTooltip:IsShown() then
            local owner = GameTooltip:GetOwner()
            if owner == mm or owner == UIParent or owner ~= s.ttOwner then GameTooltip:Hide() end
        end
        GameTooltip:SetAlpha(s.ttAlpha)
    end)
end
ns.RestoreMinimap = Restore

-- Put the minimap so that the point (dx, dy) from its centre (minimap units) is under the cursor
local function Place(dx, dy)
    local es = mm:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / es - dx, cy / es - dy)
    return cx, cy
end

----------------------------------------------------------------------
-- Job runner. A job has a list of steps; each step places the minimap and is read
-- <dwell> frames later. If the mouse moved in between, the step is placed again.
----------------------------------------------------------------------
local function Stop(ok, reason)
    local j = job
    job = nil
    runner:Hide()
    Restore()
    if j and j.onDone then ns.SafeCall(function() j.onDone(ok, reason) end) end
end

local function PlaceStep(j)
    local step = j.steps[j.i]
    local sc = step.scale or saved.scale
    j.frames = 0
    if math.abs(mm:GetScale() - sc) > 1e-6 then
        mm:SetScale(sc)
        j.frames = -2          -- the game needs a couple of extra frames after a size change
    end
    j.cx, j.cy = Place(step[1], step[2])
end

local function StartJob(steps, alpha, dwell, onRead, onDone)
    if job then return false end
    job = { steps = steps, i = 1, dwell = math.max(1, dwell), onRead = onRead, onDone = onDone,
            started = debugprofilestop() }
    local ok, err = pcall(function()
        Prepare(alpha)
        PlaceStep(job)
    end)
    if not ok then
        ns.Log("ERR", "Could not start the scan: %s", tostring(err))
        Stop(false, "error while preparing")      -- Stop() also restores the minimap
        return false
    end
    runner:Show()
    return true
end

runner:SetScript("OnUpdate", function()
    local j = job
    if not j then runner:Hide(); return end
    local why = (InCombatLockdown() and not ns.db.scanInCombat) and "combat"
        or IsMouselooking() and "camera turned with the mouse"
        or (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) and "mouse button pressed"
    if why then return Stop(false, "aborted (" .. why .. ")") end
    local ok, err = pcall(function()
        j.frames = j.frames + 1
        if j.frames < j.dwell then return end

        -- The mouse moved since we placed the minimap: the reading would be for the wrong spot
        local x, y = GetCursorPosition()
        if math.abs(x - j.cx) > 0.5 or math.abs(y - j.cy) > 0.5 then
            j.moves = (j.moves or 0) + 1
            if j.moves > 300 then return Stop(false, "aborted (mouse kept moving)") end
            PlaceStep(j)
            return
        end

        local result = j.onRead(j.i, ReadNames())
        if result == "stop" then return Stop(true) end
        if type(result) == "table" then                  -- replace the remaining steps
            j.steps, j.i = result, 1
            PlaceStep(j)
            return
        end
        j.i = j.i + 1
        if j.steps[j.i] then PlaceStep(j) else Stop(true) end
    end)
    if not ok then Stop(false, err) end
end)

----------------------------------------------------------------------
-- Calibration: lowest opacity that works, and frames needed per point.
--   away (must read nothing) -> centre (player's own dot must appear) -> away (must vanish)
----------------------------------------------------------------------
local MAX_WAIT = 15

local function Measure(alpha, onResult)
    local w = mm:GetWidth()
    local phase, appear = 1, nil
    local steps = { { w * 2, 0 } }
    local result
    -- Report only after the job has finished and the minimap is restored
    local function onDone(ok, info) result = { ok, info } end
    -- dwell 1 = read every frame; we count frames ourselves
    StartJob(steps, alpha, 1, function(_, names)
        job.count = (job.count or 0) + 1
        if phase == 1 then
            if #names > 0 then onDone(false, "names while away from the cursor"); return "stop" end
            if job.count >= 3 then
                phase, job.count = 2, 0
                return { { 0, 0 } }
            end
            return { { w * 2, 0 } }
        elseif phase == 2 then
            if #names > 0 then
                appear = job.count
                phase, job.count = 3, 0
                return { { w * 2, 0 } }
            end
            if job.count >= MAX_WAIT then onDone(false, "nothing at centre"); return "stop" end
            return { { 0, 0 } }
        else
            if #names == 0 then onDone(true, math.max(appear, job.count)); return "stop" end
            if job.count >= MAX_WAIT then onDone(false, "names stayed after moving away"); return "stop" end
            return { { w * 2, 0 } }
        end
    end, function(ok, reason)
        if not ok then return onResult(false, reason) end
        if result then return onResult(result[1], result[2]) end
        onResult(false, "no result")
    end)
end

local function Calibrate(onDone)
    local index = 0
    local function TryNext()
        index = index + 1
        local alpha = ALPHAS[index]
        if not alpha then
            ns.Log("ERR", "Calibration failed at every opacity. Keep the mouse still over the game world and press 'Recalibrate'.")
            return
        end
        local name = string.format("%d%% visible", alpha * 100 + 0.5)
        Measure(alpha, function(ok, info)
            if not ok and tostring(info):find("aborted") then
                ns.Log("INFO", "Calibration paused: %s", tostring(info))
                return
            end
            if ok then
                ns.Log("INFO", "Calibration '%s': OK - the game needs %d frame(s) per point", name, info)
                ns.db.method = { alpha = alpha, dwell = info, name = name, build = ns.build, v = 4 }
                onDone()
            else
                ns.Log("INFO", "Calibration '%s': no (%s)", name, tostring(info))
                TryNext()
            end
        end)
    end
    TryNext()
end

----------------------------------------------------------------------
-- Scan
----------------------------------------------------------------------
-- A dot's hover area is about 25 x 25 minimap units, so a step of ~20 never misses one.
local function GridPoints()
    local r = mm:GetWidth() / 2
    local step = ns.db.step
    local n = math.floor(r / step)
    local points = {}
    for i = -n, n do
        for j = -n, n do
            local dx, dy = i * step, j * step
            if dx * dx + dy * dy <= r * r then points[#points + 1] = { dx, dy } end
        end
    end
    return points
end

local MERGE_YARDS = 15

local function StoreResults(hits, radius, half, confirmed, blind)
    local nodes = ns.nodes
    if blind then return 0 end                       -- the scan couldn't see: change nothing
    local now = GetTime()
    local R = ns.db.cluster / half * radius          -- cluster radius in yards

    local clusters = {}
    for _, h in ipairs(hits) do
        local found
        for _, c in ipairs(clusters) do
            if c.name == h.name then
                local ex, ey = c.sx / c.n - h.x, c.sy / c.n - h.y
                if ex * ex + ey * ey <= R * R then found = c; break end
            end
        end
        if found then
            found.sx, found.sy, found.n = found.sx + h.x, found.sy + h.y, found.n + 1
        else
            clusters[#clusters + 1] = { name = h.name, kind = h.kind, sx = h.x, sy = h.y, n = 1 }
        end
    end

    -- Without "remember", only the nodes from this scan are kept
    if not ns.db.remember then
        -- keep only the nodes this scan confirmed (known nodes it skipped measuring again)
        local keep = {}
        for _, n in ipairs(nodes) do
            if confirmed and confirmed[n] then keep[#keep + 1] = n end
        end
        wipe(nodes)
        for _, n in ipairs(keep) do nodes[#nodes + 1] = n end
    end

    for _, c in ipairs(clusters) do
        local x, y = c.sx / c.n, c.sy / c.n
        local match
        for _, n in ipairs(nodes) do
            if n.name == c.name and (n.x - x) ^ 2 + (n.y - y) ^ 2 <= ns.db.mergeYards ^ 2 then match = n; break end
        end
        if match then
            match.x, match.y, match.seen = x, y, now
        else
            nodes[#nodes + 1] = { name = c.name, kind = c.kind, x = x, y = y, seen = now }
        end
    end
    ns.lastScan = now
    return #clusters
end

-- Is the game window probably not in focus (tabbed out / mouse outside the window)?
local function GameUnfocused()
    -- 1. When the mouse leaves the window, WoW keeps the cursor stuck at the window edge
    local x, y = GetCursorPosition()
    local es = UIParent:GetEffectiveScale()
    local w, h = UIParent:GetWidth() * es, UIParent:GetHeight() * es
    if x <= 1 or y <= 1 or x >= w - 1 or y >= h - 1 then return true, "mouse is outside the game window" end
    -- 2. Tabbed out: WoW drops to its background FPS limit (if that setting is on)
    if GetCVarBool and GetCVarBool("useMaxFPSBk") then
        local bk = tonumber(GetCVar("maxFPSBk")) or 0
        local fg = GetCVarBool("useMaxFPS") and tonumber(GetCVar("maxFPS")) or 999
        if bk > 0 and bk < fg - 5 and GetFramerate() <= bk + 1 then
            return true, "game is in the background (tabbed out)"
        end
    end
    return false
end

local function CanScan()
    if job then return false, "already scanning" end
    local unfocused, why = GameUnfocused()
    if unfocused then return false, why end
    if not mm:IsVisible() then return false, "minimap hidden" end
    if not ns.db.scanInCombat and (InCombatLockdown() or UnitAffectingCombat("player")) then
        return false, "in combat"
    end
    if IsMouselooking() then return false, "camera is being turned with the mouse" end
    if mm:IsMouseOver() then return false, "cursor is on the minimap (hovering records nodes directly)" end
    -- Don't move the minimap under the cursor while you are about to click something
    if GameTooltip:IsShown() and GameTooltip:GetOwner() == UIParent and GameTooltip:GetAlpha() > 0 then
        return false, "mouse is over something in the world"
    end
    if ns.db.pauseYards > 0 then
        local _, px, py = ns.GetPlayerYards()
        if px then
            for _, n in ipairs(ns.nodes) do
                if (n.x - px) ^ 2 + (n.y - py) ^ 2 <= ns.db.pauseYards ^ 2 then
                    return false, "close to a node (paused so you can click it)"
                end
            end
        end
    end
    if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
        return false, "mouse button held"
    end
    if not C_TooltipInfo or not C_TooltipInfo.GetMinimapMouseover then
        ns.LogOnce("noapi", "ERR", "C_TooltipInfo.GetMinimapMouseover is missing")
        return false, "API missing"
    end
    return true
end

-- How a scan works (the same idea as Minimap Alert's GPS):
--   1. Count: the minimap shrunk to 15 % is smaller than one dot's hover area, so a single
--      read under the cursor lists EVERY dot on the map, one line per dot. That tells us
--      which nodes there are and how many of each.
--   2. Known nodes: test the spot where each node we already know should be (1 read).
--   3. New nodes: at normal size, walk a grid outward from the centre until we hit the
--      node, then find its edges left/right/down/up. The centre is halfway between them.
-- Every probe is one minimap placement; the coroutine below asks for them one at a time.

-- Names we failed to locate are skipped for a while (e.g. odd objects in cities)
local givenUp = {}
function ns.GiveUp(name) givenUp[name] = GetTime() + 120 end
function ns.IsGivenUp(name) return givenUp[name] and givenUp[name] > GetTime() end

-- Only look for a kind of node if it is shown in the window AND its tracking is on
function ns.WantKind(kind)
    if not ns.db[ns.KIND_KEY[kind] or "showHerb"] then return false end
    local t = ns.GatherTracking and ns.GatherTracking()
    if t and t.known[kind] and not t.active[kind] then return false end
    return true
end
local MAX_PROBES = 400
local SWEEP_STEP = 18      -- minimap units between sweep points (a dot's hover area is ~25 wide)

-- How a scan works now (everything at normal minimap size, where reads are reliable):
--   1. Known nodes: one read where each should be. HIT = still there, MISS = gone.
--   2. Rough nodes: measure the exact centre of nodes we only have a rough position for.
--   3. Sweep: continue a grid over the whole minimap from where the last scan stopped.
--      Every node it touches is added straight away with a rough position (shown "~").
-- A scan stops when its time is up; the next scan carries on.
local function DoScan()
    local mapID = ns.GetPlayerYards()
    if not mapID then return end
    if mapID ~= ns.currentMap then wipe(ns.nodes); ns.currentMap = mapID; ns.sweepIndex = 1 end

    local method = ns.db.method
    local half = mm:GetWidth() / 2
    local radius = ViewRadius()
    local S = mm:GetScale()
    local verbose = ns.logNextSweep or ns.db.logEverySweep
    ns.logNextSweep = false
    local t0 = debugprofilestop()

    local probes, anyName = 0, false
    local stats = { confirmed = 0, removed = 0, refined = 0, added = 0, swept = 0 }
    local missed = {}                                      -- known nodes that read MISS
    local hitNow = {}                                      -- known nodes that read HIT

    -- Sweep grid, nearest points first (built once per minimap size)
    if not ns.sweepGrid or ns.sweepHalf ~= half then
        local g = {}
        local n = math.floor(half / SWEEP_STEP)
        for i = -n, n do
            for j = -n, n do
                local x, y = i * SWEEP_STEP, j * SWEEP_STEP
                if x * x + y * y <= half * half then g[#g + 1] = { x, y, x * x + y * y } end
            end
        end
        table.sort(g, function(p1, p2) return p1[3] < p2[3] end)
        ns.sweepGrid, ns.sweepHalf, ns.sweepIndex = g, half, 1
    end

    local co = coroutine.create(function()
        local function Probe(dx, dy)
            probes = probes + 1
            if probes > MAX_PROBES then error("probe limit", 0) end
            if debugprofilestop() - t0 > ns.db.maxScanTime * 1000 then error("time limit", 0) end
            local names = coroutine.yield({ dx, dy, scale = S })
            if #names > 0 then anyName = true end
            return names
        end
        local function Has(names, name)
            for _, n in ipairs(names) do if n == name then return true end end
        end
        local function Hit(x, y, name) return Has(Probe(x, y), name) end

        -- Exact centre, measured in WORLD yards: before every read the world point is
        -- converted to a minimap spot from where you are right now, so riding while
        -- measuring doesn't shift the result.
        local function HitWorld(wx, wy, name)
            local _, px, py = ns.GetPlayerYards()
            if not px then return false end
            local ux, uy = (wx - px) / radius * half, (py - wy) / radius * half
            if ux * ux + uy * uy > half * half then return false end
            return Hit(ux, uy, name)
        end
        local yd = radius / half                          -- yards per minimap unit
        local function Edge(wx, wy, ex, ey, name)         -- (ex, ey) = direction east/north
            local inside, outside, t = 0, nil, 2 * yd
            while t <= 64 * yd do
                if HitWorld(wx + ex * t, wy - ey * t, name) then inside = t; t = t * 2
                else outside = t; break end
            end
            if not outside then return inside end
            for _ = 1, 2 do
                local m = (inside + outside) / 2
                if HitWorld(wx + ex * m, wy - ey * m, name) then inside = m else outside = m end
            end
            return (inside + outside) / 2
        end
        local function CentreWorld(wx, wy, name)
            local e, w = Edge(wx, wy, 1, 0, name), Edge(wx, wy, -1, 0, name)
            wx = wx + (e - w) / 2
            local n, s2 = Edge(wx, wy, 0, 1, name), Edge(wx, wy, 0, -1, name)
            wy = wy - (n - s2) / 2                        -- map y grows south
            return wx, wy
        end

        local function Offset(node)
            local _, px, py = ns.GetPlayerYards()
            if not px then return end
            return (node.x - px) / radius * half, (py - node.y) / radius * half, px, py
        end
        local function ToWorld(ux, uy)
            local _, px, py = ns.GetPlayerYards()
            if not px then return end
            return px + ux / half * radius, py - uy / half * radius
        end

        -- 1. Known nodes
        for _, node in ipairs(ns.nodes) do
            local ux, uy = Offset(node)
            if ux and ux * ux + uy * uy <= (half * 0.95) ^ 2 then
                if Hit(ux, uy, node.name) then
                    node.seen = GetTime()
                    hitNow[node] = true
                    stats.confirmed = stats.confirmed + 1
                else
                    missed[#missed + 1] = node
                end
            end
        end

        -- 2. Rough nodes: measure their exact centre
        for _, node in ipairs(ns.nodes) do
            if ns.db.exact and node.approx and hitNow[node] then
                node.x, node.y = CentreWorld(node.x, node.y, node.name)
                node.approx = nil
                stats.refined = stats.refined + 1
            end
        end

        -- 3. Sweep for new nodes, continuing where the last scan stopped
        local grid = ns.sweepGrid
        for _ = 1, #grid do
            local g = grid[ns.sweepIndex]
            ns.sweepIndex = ns.sweepIndex % #grid + 1
            stats.swept = stats.swept + 1
            local names = Probe(g[1], g[2])
            for _, name in ipairs(names) do
                local kind = ns.Classify(name)
                if kind and ns.WantKind(kind) then
                    -- already known nearby?
                    local known = false
                    for _, node in ipairs(ns.nodes) do
                        if node.name == name then
                            local ux, uy = Offset(node)
                            local claim = ns.db.mergeYards / radius * half      -- yards -> minimap units
                            if ux and (ux - g[1]) ^ 2 + (uy - g[2]) ^ 2 <= claim * claim then known = true; break end
                        end
                    end
                    if not known then
                        local wx, wy = ToWorld(g[1], g[2])
                        if wx then
                            ns.nodes[#ns.nodes + 1] = { name = name, kind = kind, x = wx, y = wy,
                                                        seen = GetTime(), approx = true }
                            stats.added = stats.added + 1
                        end
                    end
                end
            end
        end
    end)

    local timedOut = false
    local function Next(names)
        local ok, req = coroutine.resume(co, names)
        if not ok then
            if req == "time limit" or req == "probe limit" then timedOut = true
            else ns.Log("ERR", "Scan logic: %s", tostring(req)) end
            return "stop"
        end
        if coroutine.status(co) == "dead" then return "stop" end
        return { req }
    end

    local first = Next(nil)
    if first == "stop" then return end
    StartJob(first, method.alpha, method.dwell, function(_, names)
        return Next(names)
    end, function(ok, reason)
        if not ok then
            ns.stats.aborted = ns.stats.aborted + 1
            if verbose then ns.Log("WARN", "Scan stopped: %s", tostring(reason)) end
            ns.lastAbort = reason
            return
        end
        ns.stats.done = ns.stats.done + 1
        ns.lastScanDone = GetTime()

        -- Remove nodes that read MISS - unless the whole scan read nothing at all
        -- (then it probably couldn't see, e.g. right as you tabbed out)
        if anyName or #missed == 0 then
            ns.emptyStreak = 0
        else
            ns.emptyStreak = (ns.emptyStreak or 0) + 1
        end
        if anyName or (ns.emptyStreak or 0) >= 2 then
            local gone = {}
            for _, n in ipairs(missed) do gone[n] = true end
            for i = #ns.nodes, 1, -1 do
                if gone[ns.nodes[i]] then table.remove(ns.nodes, i); stats.removed = stats.removed + 1 end
            end
        end
        -- Without "remember", forget nodes that are off the minimap
        if not ns.db.remember then
            local _, px, py = ns.GetPlayerYards()
            if px then
                for i = #ns.nodes, 1, -1 do
                    local n = ns.nodes[i]
                    if (n.x - px) ^ 2 + (n.y - py) ^ 2 > radius * radius then table.remove(ns.nodes, i) end
                end
            end
        end
        ns.unlocated = nil
        if stats.confirmed + stats.removed + stats.refined + stats.added > 0 then ns.stats.found = ns.stats.found + 1 end

        if verbose or stats.added + stats.removed + stats.refined > 0 then
            ns.Log("INFO", "Scan: %d reads, %.0f ms%s | %d confirmed, %d gone, %d new (rough), %d measured, swept %d/%d",
                probes, debugprofilestop() - t0, timedOut and " (time up)" or "",
                stats.confirmed, stats.removed, stats.added, stats.refined, stats.swept, #ns.sweepGrid)
            local _, px, py = ns.GetPlayerYards()
            if px and verbose then
                for _, n in ipairs(ns.nodes) do
                    ns.Log("INFO", "  %s at %s%.0f yd", n.name, n.approx and "~" or "",
                        math.sqrt((n.x - px) ^ 2 + (n.y - py) ^ 2))
                end
            end
        end
    end)
end

function ns.ScanNow(manual)
    local ok, why = CanScan()
    if not ok then
        if manual then ns.Log("INFO", "Scan skipped: %s", why) end
        ns.stats.skipped[why] = (ns.stats.skipped[why] or 0) + 1
        return
    end
    ns.stats.started = ns.stats.started + 1
    -- No calibration: it needs something known under the cursor, and the only thing
    -- reliably there was a quest area, which we now hide. Use Minimap Alert's settings.
    ns.db.method = {
        alpha = ns.db.scanAlpha, dwell = ns.db.dwell,
        name = string.format("%d%% visible, %d frame(s) per point", ns.db.scanAlpha * 100 + 0.5, ns.db.dwell),
    }
    DoScan()
end

function ns.IsScanning() return job ~= nil end

----------------------------------------------------------------------
-- Free readings: when YOU hover the minimap, record what is under the cursor
----------------------------------------------------------------------
local hoverFrame = CreateFrame("Frame")
local hoverSince = 0
hoverFrame:SetScript("OnUpdate", function(_, elapsed)
    hoverSince = hoverSince + elapsed
    if hoverSince < 0.2 or job or not ns.db then return end
    hoverSince = 0
    if not mm:IsVisible() or not mm:IsMouseOver() then return end
    ns.SafeCall(function()
        local names = ReadNames()
        if #names == 0 then return end
        local mapID, px, py = ns.GetPlayerYards()
        if not mapID then return end
        if mapID ~= ns.currentMap then wipe(ns.nodes); ns.currentMap = mapID end
        local es = mm:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        local mx, my = mm:GetCenter()
        local half = mm:GetWidth() / 2
        local radius = ViewRadius()
        local east, north = (cx / es - mx) / half * radius, (cy / es - my) / half * radius
        local now = GetTime()
        for _, n in ipairs(names) do
            local kind = ns.Classify(n)
            if kind then
                local x, y = px + east, py - north
                -- The nearest node of that name within the "same node" distance is this one.
                -- (The cursor can be anywhere on the dot, which is ~50 yd wide in the world.)
                local match, best = nil, ns.db.mergeYards ^ 2
                for _, node in ipairs(ns.nodes) do
                    local d = (node.x - x) ^ 2 + (node.y - y) ^ 2
                    if node.name == n and d <= best then match, best = node, d end
                end
                if match then
                    match.seen = now                             -- keep its position, just confirm it
                else
                    ns.nodes[#ns.nodes + 1] = { name = n, kind = kind, x = x, y = y, seen = now, approx = true }
                end
            end
        end
    end)
end)

----------------------------------------------------------------------
-- Events: stop on combat/zoning; remove a node when you gather it
----------------------------------------------------------------------
local GATHER_SPELLS = { ["Mining"] = true, ["Herb Gathering"] = true, ["Opening"] = true,
                        ["Herbalism"] = true, ["Treasure"] = true }
local events = CreateFrame("Frame")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_LEAVING_WORLD")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
        if job and (event ~= "PLAYER_REGEN_DISABLED" or not ns.db.scanInCombat) then
            Stop(false, "aborted (" .. event .. ")")
        end
        Restore()
        return
    end
    ns.SafeCall(function()
        if ns.IsSecret(spellID) then return end
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        local name = info and info.name
        if not name or ns.IsSecret(name) or not GATHER_SPELLS[name] then return end
        local _, px, py = ns.GetPlayerYards()
        if not px then return end
        local best, bestD
        for i, n in ipairs(ns.nodes) do
            local d = (n.x - px) ^ 2 + (n.y - py) ^ 2
            if d < ns.db.mergeYards ^ 2 and (not bestD or d < bestD) then best, bestD = i, d end
        end
        if best then
            ns.Log("INFO", "Gathered %s - removed from the list", ns.nodes[best].name)
            table.remove(ns.nodes, best)
        end
    end)
end)

----------------------------------------------------------------------
-- Automatic scanning
----------------------------------------------------------------------
ns.stats = { started = 0, done = 0, aborted = 0, found = 0, skipped = {} }

-- Check twice a second. A scan runs when <interval> seconds have passed since the last
-- COMPLETED scan, so a scan that was skipped or aborted (mouse button, camera turning,
-- combat) is retried as soon as the mouse is free, instead of waiting another interval.
function ns.RestartTicker()
    if ns.ticker then ns.ticker:Cancel() end
    ns.build = select(2, GetBuildInfo())
    ns.ticker = C_Timer.NewTicker(0.5, function()
        -- Safety net: the minimap is still moved/hidden but no scan is running
        if saved and not job then
            ns.Log("WARN", "Minimap was left changed after a scan - putting it back")
            Restore()
        end
        if not ns.db.autoScan or job then return end
        if GetTime() - (ns.lastScanDone or 0) < ns.db.interval then return end
        ns.SafeCall(function() ns.ScanNow(false) end)
    end)
end

function ns.PrintStatus()
    local st = ns.stats
    ns.Log("INFO", "Status: %d scans started, %d completed, %d aborted, %d saw a node; last abort: %s",
        st.started, st.done, st.aborted, st.found, tostring(ns.lastAbort))
    local list = {}
    for why, c in pairs(st.skipped) do list[#list + 1] = why .. " x" .. c end
    ns.Log("INFO", "  skipped: %s", #list > 0 and table.concat(list, ", ") or "never")
    ns.Log("INFO", "  nodes in window: %d", #ns.nodes)
end
