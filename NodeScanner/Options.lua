-- NodeScanner Options window + minimap button.

local _, ns = ...

local panel
local widgets = {}

----------------------------------------------------------------------
-- Small widget helpers (built by hand so they don't depend on templates)
----------------------------------------------------------------------
local function Check(parent, label, key, x, y, onChange)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetText(label)
    cb:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        if onChange then onChange() end
    end)
    cb.Load = function(self) self:SetChecked(ns.db[key]) end
    widgets[#widgets + 1] = cb
    return cb
end

local function Slider(parent, label, key, minV, maxV, stepV, format, x, y, onChange)
    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(190, 17)
    s:SetPoint("TOPLEFT", x, y)
    s:EnableMouse(true)
    s:SetBackdrop({
        bgFile   = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(stepV)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

    local title = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
    local function Label(v) title:SetText(label .. ": |cffffffff" .. format(v) .. "|r") end

    local loading = false
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / stepV + 0.5) * stepV
        Label(v)
        if loading then return end
        ns.db[key] = v
        if onChange then onChange() end
    end)
    s.Load = function(self)
        loading = true
        self:SetValue(ns.db[key])
        Label(ns.db[key])
        loading = false
    end
    widgets[#widgets + 1] = s
    return s
end

local function Header(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
end

local function Note(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(190)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
end

local function pct(v) return string.format("%d%%", v * 100 + 0.5) end
local function int(v) return string.format("%d", v) end
local function sec(v) return string.format("%d s", v) end

----------------------------------------------------------------------
-- Options window
----------------------------------------------------------------------
local function BuildPanel()
    panel = CreateFrame("Frame", "NodeScannerOptionsFrame", UIParent, "BackdropTemplate")
    panel:SetSize(470, 660)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()
    tinsert(UISpecialFrames, "NodeScannerOptionsFrame")

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Node Scanner " .. ns.VERSION)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Left column: window + filters
    local L = 24
    Header(panel, "Window", L, -50)
    Check(panel, "Show window", "shown", L, -70, ns.ApplyWindowSettings)
    Check(panel, "Lock window", "locked", L, -96)
    Check(panel, "Minimap button", "showButton", L, -122, function() ns.ApplyButtonSettings() end)

    Header(panel, "Show nodes", L, -160)
    Check(panel, "Herbs", "showHerb", L, -180)
    Check(panel, "Ore", "showOre", L, -206)
    Check(panel, "Treasure (Find Treasure)", "showTreasure", L, -232)

    Header(panel, "Memory", L, -270)
    Check(panel, "Remember nodes out of range", "remember", L, -290)
    Note(panel, "Off: only nodes on the minimap right now. On: keeps nodes you have seen (grey).", L + 4, -318)
    Check(panel, "Hide quest areas while scanning", "hideQuestAreas", L, -350)
    Check(panel, "Warn when Find Minerals/Herbs is off", "trackingWarning", L, -376)
    Check(panel, "Measure exact positions (slower)", "exact", L, -402)

    -- Right column: sliders
    local R = 250
    Header(panel, "Appearance", R, -50)
    Slider(panel, "Rows", "rows", 1, 10, 1, int, R, -88, ns.ApplyWindowSettings)
    Slider(panel, "Background opacity", "bgAlpha", 0, 1, 0.05, pct, R, -128, ns.ApplyWindowSettings)
    Slider(panel, "Window scale", "scale", 0.5, 2, 0.05, pct, R, -168, ns.ApplyWindowSettings)

    Header(panel, "Scanning", R, -206)
    Check(panel, "Scan automatically", "autoScan", R - 4, -224)
    Check(panel, "Also scan in combat", "scanInCombat", R - 4, -248)
    Slider(panel, "Scan every", "interval", 3, 60, 1, sec, R, -290, ns.RestartTicker)
    Slider(panel, "Search step (px, bigger = faster)", "hitPx", 3, 15, 1, int, R, -330)
    Slider(panel, "Cluster radius", "cluster", 10, 80, 5, int, R, -370)
    Slider(panel, "Frames per point", "dwell", 1, 5, 1, int, R, -410)
    Slider(panel, "Opacity while scanning", "scanAlpha", 0, 1, 0.05, pct, R, -450)
    Slider(panel, "Pause scanning near a node (yd)", "pauseYards", 0, 30, 1, int, R, -490)
    Slider(panel, "Same node within (yd)", "mergeYards", 5, 60, 5, int, R, -570)
    Slider(panel, "Max scan time", "maxScanTime", 1, 5, 0.5, function(v) return string.format("%.1f s", v) end, R, -530)

    -- Buttons
    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(130, 22)
    reset:SetPoint("BOTTOMLEFT", 24, 20)
    reset:SetText("Reset position")
    reset:SetScript("OnClick", ns.ResetWindowPosition)

    local debug = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    debug:SetSize(130, 22)
    debug:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    debug:SetText("Debug window")
    debug:SetScript("OnClick", ns.ToggleDebug)

    local scanBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scanBtn:SetSize(130, 22)
    scanBtn:SetPoint("BOTTOMLEFT", reset, "TOPLEFT", 0, 6)
    scanBtn:SetText("Scan now")
    scanBtn:SetScript("OnClick", function() ns.ScanNow(true) end)

    local logBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    logBtn:SetSize(130, 22)
    logBtn:SetPoint("LEFT", scanBtn, "RIGHT", 8, 0)
    logBtn:SetText("Scan + log")
    logBtn:SetScript("OnClick", function() ns.logNextSweep = true; ns.ScanNow(true) end)

    local defaults = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    defaults:SetSize(130, 22)
    defaults:SetPoint("LEFT", debug, "RIGHT", 8, 0)
    defaults:SetText("Defaults")
    defaults:SetScript("OnClick", function()
        for k, v in pairs(ns.defaults) do
            if k ~= "minimapAngle" then ns.db[k] = v end   -- calibration is kept
        end
        ns.ApplyWindowSettings()
        ns.ApplyButtonSettings()
        ns.RestartTicker()
        ns.RefreshOptions()
    end)

    panel:SetScript("OnShow", ns.RefreshOptions)
end

function ns.RefreshOptions()
    if not panel or not panel:IsShown() then return end
    for _, w in ipairs(widgets) do w:Load() end
end

function ns.ToggleOptions()
    if panel then panel:SetShown(not panel:IsShown()) end
end

----------------------------------------------------------------------
-- Minimap button (draggable around the minimap edge)
----------------------------------------------------------------------
local button, icon

local function UpdateButtonPosition()
    local a = math.rad(ns.db.minimapAngle)
    local r = Minimap:GetWidth() / 2 + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function BuildButton()
    button = CreateFrame("Button", "NodeScannerMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\Trade_Mining")
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            if IsControlKeyDown() then
                ns.ToggleDebug()
            else
                ns.db.locked = not ns.db.locked
                print("|cff33ff99Node Scanner|r: window " .. (ns.db.locked and "locked" or "unlocked"))
                ns.RefreshOptions()
            end
        elseif IsControlKeyDown() then
            ns.ScanNow(true)
        elseif IsShiftKeyDown() then
            ns.ToggleWindow()
        else
            ns.ToggleOptions()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local s = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            ns.db.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            UpdateButtonPosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Node Scanner")
        GameTooltip:AddLine("Left-click: options", 1, 1, 1)
        GameTooltip:AddLine("Ctrl-click: scan now", 1, 1, 1)
        GameTooltip:AddLine("Shift-click: show/hide window", 1, 1, 1)
        GameTooltip:AddLine("Right-click: " .. (ns.db.locked and "unlock" or "lock") .. " window", 1, 1, 1)
        GameTooltip:AddLine("Ctrl-right-click: debug log", 1, 1, 1)
        if ns.errorCount > 0 then
            GameTooltip:AddLine(ns.errorCount .. " new error(s) - ctrl-right-click to see", 1, 0.3, 0.3)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ns.ApplyButtonSettings()
end

function ns.ApplyButtonSettings()
    if not button then return end
    button:SetShown(ns.db.showButton)
    UpdateButtonPosition()
    ns.RefreshOptions()
end

-- Tint the icon red while there are unread errors
ns.OnError = function()
    if not icon then return end
    if ns.errorCount > 0 then
        icon:SetVertexColor(1, 0.35, 0.35)
    else
        icon:SetVertexColor(1, 1, 1)
    end
end

ns.OnInit(BuildPanel)
ns.OnInit(BuildButton)
