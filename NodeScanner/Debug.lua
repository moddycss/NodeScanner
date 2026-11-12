-- Node Scanner - created with the help of AI (Claude). MIT licensed.
-- NodeScanner Debug window: shows the log (errors, warnings, sweep details).
-- The text can be selected and copied with Ctrl+C.

local _, ns = ...

local frame, scroll, edit, everyCheck
local dirty = false

local function Fill()
    dirty = false
    edit:SetText(table.concat(ns.log, "\n"))
    C_Timer.After(0, function()
        scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
    end)
end

local function MakeButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

local function Build()
    frame = CreateFrame("Frame", "NodeScannerDebugFrame", UIParent, "BackdropTemplate")
    frame:SetSize(560, 320)
    frame:SetPoint("CENTER", 0, 100)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()
    tinsert(UISpecialFrames, "NodeScannerDebugFrame")     -- Escape closes it

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Node Scanner - Debug log")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -12, 40)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local v = self:GetVerticalScroll() - delta * 40
        v = math.max(0, math.min(v, self:GetVerticalScrollRange()))
        self:SetVerticalScroll(v)
    end)

    edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetWidth(530)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    -- Read-only: undo anything the user types
    edit:SetScript("OnTextChanged", function(_, userInput) if userInput then Fill() end end)
    scroll:SetScrollChild(edit)

    local clear = MakeButton(frame, "Clear", 70)
    clear:SetPoint("BOTTOMLEFT", 12, 10)
    clear:SetScript("OnClick", function()
        wipe(ns.log)
        ns.errorCount = 0
        if ns.OnError then ns.OnError() end
        Fill()
    end)

    local nextBtn = MakeButton(frame, "Log next sweep", 120)
    nextBtn:SetPoint("LEFT", clear, "RIGHT", 6, 0)
    nextBtn:SetScript("OnClick", function() ns.logNextSweep = true end)

    local copy = MakeButton(frame, "Select all", 90)
    copy:SetPoint("LEFT", nextBtn, "RIGHT", 6, 0)
    copy:SetScript("OnClick", function()
        edit:SetFocus()
        edit:HighlightText()
        print("|cff33ff99Node Scanner|r: press Ctrl+C to copy the log.")
    end)

    everyCheck = CreateFrame("CheckButton", nil, frame)
    everyCheck:SetSize(22, 22)
    everyCheck:SetPoint("LEFT", copy, "RIGHT", 10, 0)
    everyCheck:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    everyCheck:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    everyCheck:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    everyCheck:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    everyCheck:SetScript("OnClick", function(self) ns.db.logEverySweep = self:GetChecked() and true or false end)
    local lbl = everyCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", everyCheck, "RIGHT", 2, 0)
    lbl:SetText("Log every sweep")

    frame:SetScript("OnShow", function()
        everyCheck:SetChecked(ns.db.logEverySweep)
        ns.errorCount = 0
        if ns.OnError then ns.OnError() end
        Fill()
    end)
    frame:SetScript("OnUpdate", function() if dirty then Fill() end end)
end

ns.OnLogChanged = function() dirty = true end

function ns.ToggleDebug()
    if frame then frame:SetShown(not frame:IsShown()) end
end

ns.OnInit(Build)
