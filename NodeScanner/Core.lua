-- NodeScanner Core: settings, logging, node names, player position, slash commands.
-- The actual minimap scanning lives in Scanner.lua.

local ADDON_NAME, ns = ...
ns.VERSION = "1.2.2.4"   -- WoWpatch.Release.Major.Minor

ns.defaults = {
    shown         = true,   -- main window visible
    locked        = false,
    rows          = 5,
    bgAlpha       = 0.5,
    scale         = 1.0,
    interval      = 10,     -- seconds between automatic scans
    step          = 20,     -- distance between scan points in minimap units (smaller = slower scan)
    cluster       = 30,     -- hits of the same name closer than this (minimap units) = one node
    autoScan      = true,   -- scan automatically every <interval> seconds
    scanInCombat  = false,
    scanDungeon   = false,  -- "Also scan in ..." (off = pause there)
    scanRaid      = false,
    scanBattleground = false,
    scanArena     = false,
    scanIndoors   = false,
    pauseAtMinimap = true,  -- pause while the mouse is at the minimap
    pauseResting  = false,  -- pause in rested areas (inns, cities)
    pauseUI       = true,   -- pause while the mouse is over the interface
    pauseTooltip  = true,   -- pause while a game tooltip is shown
    pauseWindows  = true,   -- pause while a game window is open (talents, flight map ...)
    hideQuestAreas = true,  -- turn quest areas off during a scan (they ignore opacity)
    alwaysLocate  = false,  -- run the grid even when the quick check found nothing (debug)
    scanAlpha     = 0,      -- minimap opacity while scanning (Minimap Alert uses 0)
    dwell         = 2,      -- frames to wait at each scan point before reading
    -- (hitPx, cluster: settings of the old scan method, no longer used)
    hitPx         = 6,      -- grid step in screen pixels when looking for a new node (Minimap Alert uses 6)
    pauseYards    = 10,     -- no scanning this close to a known node, so you can click it
    nodeBudget    = 200,
    maxScanTime   = 2,
    mergeYards    = 30,     -- nodes of the same name closer than this are the same node
    swapTracking  = true,   -- (kept for older settings)
    -- "Track" row (trackX) and "Scan together" row (togetherX) - see TRACKERS below.
    -- Herbs/ore/treasure are on by default, creature types off.
    trackHerb     = true,
    trackOre      = true,
    trackTreasure = true,   -- keeps Find Treasure on (it stacks with herbs/ore)
    creatureExpire = 45,    -- seconds a mob/NPC stays in the list without being seen again
    muteSwap      = true,   -- mute the switch sound
    minimapTerrain = true,  -- stand-in map uses the real minimap terrain images
    underlay      = true,
    underlayBorder = true,  -- copy the minimap's border onto the stand-in map   -- show a stand-in map where the minimap is while it scans
    replaceMinimap = false, -- off: stand-in map only while scanning; on: always our map
    scanLabel     = true,   -- "Scanning for nodes" above the minimap while scanning
    exact         = false,  -- measure exact node positions (slower); off = rough is enough
      -- seconds; a scan never runs longer than this    -- max reads spent looking for one new node before giving up
    trackingWarning = true, -- warn when Find Minerals / Find Herbs / Find Treasure is off
    remember      = false,  -- keep nodes that are no longer seen on the minimap
    showHerb      = true,
    showOre       = true,
    showTreasure  = true,
    showButton    = true,
    minimapAngle  = 225,
    logEverySweep = false,
}

ns.nodes = {}
ns.initHooks = {}
function ns.OnInit(fn) ns.initHooks[#ns.initHooks + 1] = fn end

----------------------------------------------------------------------
-- Logging (shown in the debug window)
----------------------------------------------------------------------
ns.log = {}
ns.errorCount = 0
local MAX_LOG = 500
local lastMsg, repeatCount = nil, 0
local once = {}
local warnedChat = false

function ns.Log(level, fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    local line = date("%H:%M:%S") .. " [" .. level .. "] " .. msg
    if msg == lastMsg then
        repeatCount = repeatCount + 1
        ns.log[#ns.log] = line .. "  (x" .. repeatCount .. ")"
    else
        lastMsg, repeatCount = msg, 1
        ns.log[#ns.log + 1] = line
        if #ns.log > MAX_LOG then table.remove(ns.log, 1) end
    end
    if level == "ERR" then
        ns.errorCount = ns.errorCount + 1
        -- Never leave the minimap moved or hidden after an error
        if ns.RestoreMinimap and not (ns.IsScanning and ns.IsScanning()) then pcall(ns.RestoreMinimap) end
        if not warnedChat then
            warnedChat = true
            print("|cff33ff99Node Scanner|r: an error occurred - type |cffffff00/nscan debug|r to see it.")
        end
        if ns.OnError then ns.OnError() end
    end
    if ns.OnLogChanged then ns.OnLogChanged() end
end

-- Log a message only once until ns.ClearOnce(key) is called (for per-frame checks)
function ns.LogOnce(key, level, fmt, ...)
    if once[key] then return end
    once[key] = true
    ns.Log(level, fmt, ...)
end
function ns.ClearOnce(key) once[key] = nil end

local function ErrorHandler(e)
    return tostring(e) .. (debugstack and ("\n" .. debugstack(2, 4, 0)) or "")
end

function ns.SafeCall(fn)
    local ok, err = xpcall(fn, ErrorHandler)
    if not ok then ns.Log("ERR", "%s", err) end
    return ok
end

-- Node colour = rarity of the item it gives (Copper Ore = white, Silver Ore = green, ...)
local NODE_ITEM = {
    -- ore
    ["copper vein"] = 2770, ["tin vein"] = 2771, ["silver vein"] = 2775, ["iron deposit"] = 2772,
    ["gold vein"] = 2776, ["mithril deposit"] = 3858, ["truesilver deposit"] = 7911,
    ["small thorium vein"] = 10620, ["rich thorium vein"] = 10620, ["dark iron deposit"] = 11370,
    ["incendicite mineral vein"] = 3340, ["lesser bloodstone deposit"] = 4278,
    ["indurium mineral vein"] = 5833,
    -- herbs
    ["peacebloom"] = 2447, ["silverleaf"] = 765, ["earthroot"] = 2449, ["mageroyal"] = 785,
    ["briarthorn"] = 2450, ["stranglekelp"] = 3820, ["bruiseweed"] = 2453, ["wild steelbloom"] = 3355,
    ["grave moss"] = 3369, ["kingsblood"] = 3356, ["liferoot"] = 3357, ["fadeleaf"] = 3818,
    ["goldthorn"] = 3821, ["khadgar's whisker"] = 3358, ["wintersbite"] = 3819, ["firebloom"] = 4625,
    ["purple lotus"] = 8831, ["arthas' tears"] = 8836, ["sungrass"] = 8838, ["blindweed"] = 8839,
    ["ghost mushroom"] = 8845, ["gromsblood"] = 8846, ["golden sansam"] = 13464, ["dreamfoil"] = 13463,
    ["mountain silversage"] = 13465, ["plaguebloom"] = 13466, ["icecap"] = 13467, ["black lotus"] = 13468,
}
-- Used only until the game has loaded the item (1 = common/white, 2 = uncommon/green)
local FALLBACK_QUALITY = { [2775] = 2, [2776] = 2, [7911] = 2 }

function ns.NodeItem(name)
    return NODE_ITEM[name:lower():gsub("^ooze covered ", "")]
end

local qualityCache = {}
function ns.NodeColor(name)
    local key = name:lower():gsub("^ooze covered ", "")
    local item = NODE_ITEM[key]
    if not item then return nil end                     -- unknown node / chest: default colour
    local q = qualityCache[item]
    if not q and C_Item and C_Item.GetItemQualityByID then
        q = C_Item.GetItemQualityByID(item)
        if q then
            qualityCache[item] = q
        elseif C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(item)        -- ask the game; next refresh has it
        end
    end
    q = q or FALLBACK_QUALITY[item] or 1
    local r, g, b
    if C_Item and C_Item.GetItemQualityColor then
        r, g, b = C_Item.GetItemQualityColor(q)
    elseif ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
        local c = ITEM_QUALITY_COLORS[q]
        r, g, b = c.r, c.g, c.b
    end
    return r, g, b
end

function ns.IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

----------------------------------------------------------------------
-- Which names are gathering nodes?
----------------------------------------------------------------------
local HERBS = {}
for _, n in ipairs({
    "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn",
    "Stranglekelp", "Bruiseweed", "Wild Steelbloom", "Grave Moss", "Kingsblood",
    "Liferoot", "Fadeleaf", "Goldthorn", "Khadgar's Whisker", "Wintersbite",
    "Firebloom", "Purple Lotus", "Arthas' Tears", "Sungrass", "Blindweed",
    "Ghost Mushroom", "Gromsblood", "Golden Sansam", "Dreamfoil",
    "Mountain Silversage", "Plaguebloom", "Icecap", "Black Lotus",
}) do HERBS[n:lower()] = true end

ns.KIND_KEY = { herb = "showHerb", ore = "showOre", treasure = "showTreasure" }

-- Returns "herb", "ore", "treasure" or nil
function ns.Classify(name)
    local l = name:lower()
    local extra = ns.db and ns.db.extra[l]
    if extra then return extra == true and "herb" or extra end
    if HERBS[l] then return "herb" end
    if l:find("vein$") or l:find("deposit$") then return "ore" end
    if l == "giant clam" or l:find("chest$") or l:find("footlocker$")
        or l:find("strongbox$") or l:find("trunk$") then return "treasure" end
    return nil
end

-- Strip colour codes and icons from tooltip text
function ns.Clean(text)
    if type(text) ~= "string" or ns.IsSecret(text) then return nil end
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    return text
end

----------------------------------------------------------------------
-- Gathering tracking (Find Minerals / Find Herbs / Find Treasure)
----------------------------------------------------------------------
-- Every tracking type Node Scanner can use.
--   key      = settings suffix (trackX / togetherX)
--   spells   = all spells that give this tracking (class versions count as the same type)
--   stacks   = can be on together with another tracking (Find Treasure on Forever)
--   creature = dots are NPCs/mobs (grouped by name in the window)
local TRACKERS = {
    { kind = "herb",      key = "Herb",       label = "Herbs",      spells = { 2383 },        names = { "Find Herbs" } },
    { kind = "ore",       key = "Ore",        label = "Ore",        spells = { 2580 },        names = { "Find Minerals" } },
    { kind = "treasure",  key = "Treasure",   label = "Treasure",   spells = { 2481 },        names = { "Find Treasure" }, stacks = true },
    { kind = "beast",     key = "Beasts",     label = "Beasts",     spells = { 1494 },        names = { "Track Beasts" },     creature = true },
    { kind = "humanoid",  key = "Humanoids",  label = "Humanoids",  spells = { 19883, 5225 }, names = { "Track Humanoids" },  creature = true },
    { kind = "undead",    key = "Undead",     label = "Undead",     spells = { 19884, 5502 }, names = { "Track Undead", "Sense Undead" }, creature = true },
    { kind = "demon",     key = "Demons",     label = "Demons",     spells = { 19878, 5500 }, names = { "Track Demons", "Sense Demons" }, creature = true },
    { kind = "elemental", key = "Elementals", label = "Elementals", spells = { 19880 },       names = { "Track Elementals" }, creature = true },
    { kind = "giant",     key = "Giants",     label = "Giants",     spells = { 19882 },       names = { "Track Giants" },     creature = true },
    { kind = "dragonkin", key = "Dragonkin",  label = "Dragonkin",  spells = { 19879 },       names = { "Track Dragonkin" },  creature = true },
    { kind = "hidden",    key = "Hidden",     label = "Hidden",     spells = { 19885 },       names = { "Track Hidden" },     creature = true },
}
ns.TRACKERS = TRACKERS
ns.TRACKER = {}
for _, tr in ipairs(TRACKERS) do ns.TRACKER[tr.kind] = tr end

function ns.IsCreatureKind(kind) return kind and ns.TRACKER[kind] and ns.TRACKER[kind].creature or false end

-- Is this kind shown in the window? (creatures: always; nodes: the Show nodes ticks)
function ns.ShowKind(kind)
    if ns.IsCreatureKind(kind) then return true end
    return ns.db[ns.KIND_KEY[kind] or "showHerb"]
end

local trackCache, trackTime = nil, 0
function ns.GatherTracking()
    if trackCache and GetTime() - trackTime < 0.5 then return trackCache end
    local t = { known = {}, active = {}, index = {}, names = {} }
    if C_Minimap and C_Minimap.GetNumTrackingTypes then
        for i = 1, C_Minimap.GetNumTrackingTypes() do
            local a, _, c, _, _, f = C_Minimap.GetTrackingInfo(i)
            local name, active, spellID
            if type(a) == "table" then
                name, active, spellID = a.name, a.active, a.spellID
            else
                name, active, spellID = a, c, f
            end
            if not ns.IsSecret(name) then
                for _, tr in ipairs(TRACKERS) do
                    local match = false
                    for _, id in ipairs(tr.spells) do if spellID == id then match = true end end
                    for _, n in ipairs(tr.names) do if name == n then match = true end end
                    if match then
                        t.known[tr.kind] = true
                        t.index[tr.kind] = i
                        t.names[tr.kind] = name
                        if active then t.active[tr.kind] = true end
                    end
                end
            end
        end
    end
    trackCache, trackTime = t, GetTime()
    return t
end

-- Returns the name of the tracker to suggest, or nil when gathering tracking is fine
function ns.MissingTracking()
    local t = ns.GatherTracking()
    local anyKnown = false
    -- Any non-stacking tracking that is on (herbs, ore, or a creature type from the
    -- rotation) is fine - Node Scanner itself switches between them
    for _, tr in ipairs(TRACKERS) do
        if t.known[tr.kind] and t.active[tr.kind] and not tr.stacks then return nil end
    end
    for _, tr in ipairs(TRACKERS) do
        if t.known[tr.kind] and (tr.kind == "herb" or tr.kind == "ore" or tr.kind == "treasure") then
            anyKnown = true
        end
    end
    if not anyKnown then return nil end
    -- only Find Treasure known (or active): fine if it is on
    if t.active.treasure and not t.known.ore and not t.known.herb then return nil end
    local want = ns.db.lastTracking
    if not want or not t.known[want] then
        want = t.known.ore and "ore" or t.known.herb and "herb" or "treasure"
    end
    if t.active[want] then return nil end
    return t.names[want], want
end

function ns.EnableTracking(kind)
    local t = ns.GatherTracking()
    local i = kind and t.index[kind]
    if i and C_Minimap.SetTracking then
        C_Minimap.SetTracking(i, true)
        trackCache = nil
    end
end

----------------------------------------------------------------------
-- Player position in yards within the current zone map
----------------------------------------------------------------------
function ns.GetPlayerYards()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        ns.LogOnce("nomap", "WARN", "No map for the player (instance or loading?)")
        return nil
    end
    ns.ClearOnce("nomap")
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then
        ns.LogOnce("nopos", "WARN", "No player position on map %d", mapID)
        return nil
    end
    ns.ClearOnce("nopos")
    local x, y = pos:GetXY()
    local width, height = C_Map.GetMapWorldSize(mapID)
    if ns.IsSecret(x) or not width or width == 0 then
        ns.LogOnce("nosize", "WARN", "Map %d has no world size / position is secret", mapID)
        return nil
    end
    ns.ClearOnce("nosize")
    -- x grows east, y grows SOUTH
    return mapID, x * width, y * height
end

----------------------------------------------------------------------
-- Startup
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")

    NodeScannerDB = NodeScannerDB or {}
    local db = NodeScannerDB
    for k, v in pairs(ns.defaults) do
        if db[k] == nil then db[k] = v end
    end
    db.extra = db.extra or {}
    db.priority, db.priorityAlert = nil, nil                                  -- 0.9.0 settings
    if db.mergeYards == 55 and not db.back092 then db.mergeYards = 30 end    -- undo 0.9.3 default
    db.back092 = true
    if db.nodeBudget == 120 then db.nodeBudget = 200 end                    -- 0.6.0 value
    if not db.v050 then db.hitPx = 6; db.v050 = true end                    -- 0.5.0: new meaning
    db.grid = nil                                                             -- v0.3.0 setting
    db.softCursor = nil                                                       -- v0.2 setting
    if db.interval < 3 then db.interval = ns.defaults.interval end           -- v0.2 used 1 s
    if db.hidden ~= nil then db.shown = not db.hidden; db.hidden = nil end   -- v0.1 setting
    ns.db = db

    for _, fn in ipairs(ns.initHooks) do ns.SafeCall(fn) end
    -- Sound effects left muted by a tracking switch that was interrupted (/reload, crash)
    if db.sfxMuted then SetCVar("Sound_EnableSFX", "1"); db.sfxMuted = nil end
    -- Quest areas left off by an earlier scan (crash, /reload mid-scan, or v0.6.1): turn back on.
    -- "fixQuestOnce" also turns them on once for everyone updating from older versions.
    if not db.fixQuestOnce then db.questPending = true; db.fixQuestOnce = true end
    if db.questPending then
        C_Timer.After(2, function() ns.SafeCall(function() ns.RestoreQuestAreas() end) end)
    end
    ns.RestartTicker()

    local version, build, _, toc = GetBuildInfo()
    ns.Log("INFO", "Node Scanner %s loaded. Client %s (build %s), interface %s",
        ns.VERSION, tostring(version), tostring(build), tostring(toc))
end)

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
SLASH_NODESCANNER1 = "/nscan"
SLASH_NODESCANNER2 = "/na"
SlashCmdList.NODESCANNER = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "debug" then
        ns.ToggleDebug()
    elseif cmd == "options" or cmd == "config" then
        ns.ToggleOptions()
    elseif cmd == "scan" then
        ns.logNextSweep = true
        ns.ScanNow(true)
    elseif cmd == "reset" then
        if ns.RestoreMinimap then ns.RestoreMinimap() end
        print("|cff33ff99Node Scanner|r: minimap put back.")
    elseif cmd == "maptest" then
        ns.UnderlayTest()
    elseif cmd == "status" then
        ns.PrintStatus()
        ns.ToggleDebug()
    elseif cmd == "button" then
        ns.db.showButton = true
        ns.ApplyButtonSettings()
    elseif cmd == "add" and rest ~= "" then
        local name, kind = rest:match("^(.-)%s+(herb)$")
        if not name then name, kind = rest:match("^(.-)%s+(ore)$") end
        if not name then name, kind = rest:match("^(.-)%s+(treasure)$") end
        name, kind = name or rest, kind or "herb"
        ns.db.extra[name:lower()] = kind
        print("|cff33ff99Node Scanner|r: added '" .. name .. "' as " .. kind .. ".")
    elseif cmd == "" then
        ns.ToggleWindow()
    else
        print("|cff33ff99Node Scanner|r commands: /nscan (window), /nscan options, /nscan debug, /nscan scan, /nscan status, /nscan reset, /nscan maptest, /nscan button, /nscan add <name> [herb|ore|treasure]")
    end
end
