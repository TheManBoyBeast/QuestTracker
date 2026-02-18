local addonName = "QuestTracker"

local defaults = {
    fontSize = 12,
    windowAlpha = 0.8,
    bg = {r = 0, g = 0, b = 0},
    activeColor = {r = 0, g = 1, b = 0},
    doneColor = {r = 1, g = 0, b = 0},
    hideBorder = false,

    -- NEW OPTIONS
    lockWindow = false,        -- lock quest list menu in place
    hideClose = false,         -- hide the close button "X"
    hideScrollBar = false,     -- hide the scrollbar
    hideResize = false,        -- hide the bottom-right resize button

    minimapPos = 45,
    showMinimap = true,

    -- NEW: Remember window position
    -- Stored as: { point="TOPLEFT", relPoint="TOPLEFT", x=..., y=... }
    windowPos = nil,
}

local qtCategoryID

-- ==========================================
-- LOCALS / PERFORMANCE
-- ==========================================
local tinsert = table.insert
local tsort   = table.sort
local tconcat = table.concat
local wipe    = wipe

local UnitName = UnitName
local GetNumQuestLogEntries = GetNumQuestLogEntries
local GetQuestLogTitle = GetQuestLogTitle
local ExpandQuestHeader = ExpandQuestHeader
local CollapseQuestHeader = CollapseQuestHeader

-- MoP Classic compatibility: completion check
local function IsQuestCompleted(qid)
    if not qid then return false end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(qid)
    end
    if IsQuestFlaggedCompleted then
        return IsQuestFlaggedCompleted(qid)
    end
    return false
end

-- ==========================================
-- WINDOW POSITION SAVE/RESTORE
-- ==========================================
local function SaveWindowPosition()
    if not QuestTrackerSettings then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if not point then return end
    QuestTrackerSettings.windowPos = {
        point = point,
        relPoint = relPoint,
        x = x,
        y = y,
    }
end

local function RestoreWindowPosition()
    if not QuestTrackerSettings then return end

    frame:ClearAllPoints()

    local p = QuestTrackerSettings.windowPos
    if p and p.point and p.relPoint and p.x and p.y then
        frame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    else
        frame:SetPoint("CENTER")
    end
end

-- ==========================================
-- MAIN FRAME SETUP
-- ==========================================
frame = CreateFrame("Frame", "QuestTrackerFrame", UIParent, "BackdropTemplate")
frame:SetSize(250, 400)
frame:SetPoint("CENTER") -- default only; we restore saved position on ADDON_LOADED
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetResizable(true)
frame:SetClampedToScreen(true)

tinsert(UISpecialFrames, "QuestTrackerFrame")

if frame.SetResizeBounds then
    frame:SetResizeBounds(150, 100, 800, 800)
end

frame:Hide()

frame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
frame.title:SetPoint("TOP", 0, -8)
frame.title:SetText("Quest Tracker")

frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
frame.close:SetPoint("TOPRIGHT", 2, 2)
frame.close:SetScript("OnClick", function() frame:Hide() end)

-- Default drag behavior (can be disabled by lock)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveWindowPosition()
end)

-- Resize button (can be hidden; can be blocked by lock)
local rb = CreateFrame("Button", nil, frame)
rb:SetSize(16, 16)
rb:SetPoint("BOTTOMRIGHT", -2, 2)
rb:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
rb:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
rb:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
rb:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)

-- ==========================================
-- SCROLL FRAME SETUP
-- ==========================================
local scrollFrame = CreateFrame("ScrollFrame", "QuestTrackerScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 10, -30)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

local scrollBar = scrollFrame.ScrollBar or _G["QuestTrackerScrollFrameScrollBar"]

local scrollChild = CreateFrame("Frame")
scrollFrame:SetScrollChild(scrollChild)
scrollChild:SetSize(scrollFrame:GetWidth(), 100)

local text = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetPoint("TOPLEFT", 0, 0)
text:SetWidth(scrollChild:GetWidth())
text:SetJustifyH("LEFT")
text:SetJustifyV("TOP")

frame:SetScript("OnSizeChanged", function()
    local w = scrollFrame:GetWidth()
    scrollChild:SetWidth(w)
    text:SetWidth(w)
end)

-- ==========================================
-- MINIMAP BUTTON SETUP
-- ==========================================
local miniBtn = CreateFrame("Button", "QuestTrackerMinimapButton", Minimap)
miniBtn:SetSize(31, 31)
miniBtn:SetFrameLevel(8)
miniBtn:SetToplevel(true)
miniBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
miniBtn:RegisterForClicks("AnyUp")

local icon = miniBtn:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
icon:SetSize(18, 18)
icon:SetPoint("CENTER", 0, 0)

local border = miniBtn:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(52, 52)
border:SetPoint("TOPLEFT", 0, 0)

local function UpdateMinimapPosition()
    local angle = (QuestTrackerSettings and QuestTrackerSettings.minimapPos) or 45
    local rad = math.rad(angle)
    miniBtn:SetPoint(
        "TOPLEFT",
        Minimap,
        "TOPLEFT",
        52 - (80 * math.cos(rad)),
        (80 * math.sin(rad)) - 52
    )
end

local function ApplyMinimapVisibility()
    if QuestTrackerSettings and QuestTrackerSettings.showMinimap then
        miniBtn:Show()
    else
        miniBtn:Hide()
    end
end

miniBtn:SetMovable(true)
miniBtn:RegisterForDrag("LeftButton")
miniBtn:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", function()
        local xpos, ypos = GetCursorPosition()
        local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()
        xpos = xmin - xpos / Minimap:GetEffectiveScale() + 70
        ypos = ypos / Minimap:GetEffectiveScale() - ymin - 70
        QuestTrackerSettings.minimapPos = math.deg(math.atan2(ypos, xpos))
        UpdateMinimapPosition()
    end)
end)
miniBtn:SetScript("OnDragStop", function(self)
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil)
end)

miniBtn:SetScript("OnClick", function(_, button)
    if button == "LeftButton" then
        if frame:IsShown() then frame:Hide() else frame:Show() end
    elseif button == "RightButton" then
        if qtCategoryID and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(qtCategoryID)
        end
    end
end)

miniBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Quest Tracker")
    GameTooltip:AddLine("|cffFFFFFFLeft-Click:|r Toggle Window", 0, 1, 0)
    GameTooltip:AddLine("|cffFFFFFFRight-Click:|r Options", 0, 1, 0)
    GameTooltip:AddLine("|cff808080Drag to move button|r")
    GameTooltip:Show()
end)
miniBtn:SetScript("OnLeave", GameTooltip_Hide)

-- ==========================================
-- HELPERS / SETTINGS
-- ==========================================
local function RGBToHex(r, g, b)
    r = (r or 1); g = (g or 1); b = (b or 1)
    if r < 0 then r = 0 elseif r > 1 then r = 1 end
    if g < 0 then g = 0 elseif g > 1 then g = 1 end
    if b < 0 then b = 0 elseif b > 1 then b = 1 end
    return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- Option UI refs (so we can refresh checkboxes when alpha hits 0)
local lockBtn, hideCloseBtn, hideScrollBtn, hideResizeBtn

local function ApplySettings()
    local s = QuestTrackerSettings
    if not s or not s.bg then return end

    -- If fully transparent, auto-hide these UI parts (and keep settings in sync)
    if s.windowAlpha <= 0 then
        s.hideClose = true
        s.hideScrollBar = true
        s.hideResize = true

        if hideCloseBtn then hideCloseBtn:SetChecked(true) end
        if hideScrollBtn then hideScrollBtn:SetChecked(true) end
        if hideResizeBtn then hideResizeBtn:SetChecked(true) end
    end

    frame:SetBackdropColor(s.bg.r, s.bg.g, s.bg.b, s.windowAlpha)

    -- Border/Header
    if s.hideBorder then
        frame:SetBackdropBorderColor(0, 0, 0, 0)
        frame.title:Hide()
    else
        frame:SetBackdropBorderColor(1, 1, 1, 1)
        frame.title:Show()
    end

    -- Close button (X)
    if s.hideClose then
        frame.close:Hide()
    else
        frame.close:Show()
        -- Keep your old "dim X when border/header hidden"
        if s.hideBorder then
            frame.close:SetAlpha(0.2)
        else
            frame.close:SetAlpha(1)
        end
    end

    -- Scrollbar + scrollframe width
    local effectiveHideScroll = s.hideScrollBar == true
    if scrollBar then
        if effectiveHideScroll then
            scrollBar:Hide()
        else
            scrollBar:Show()
        end
    end
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", 10, -30)
    if effectiveHideScroll then
        scrollFrame:SetPoint("BOTTOMRIGHT", -10, 10)
    else
        scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)
    end

    -- Resize button
    if s.hideResize then
        rb:Hide()
    else
        rb:Show()
    end

    -- Lock window in place (no dragging / no resizing)
    if s.lockWindow then
        frame:SetMovable(false)
        frame:SetResizable(false)
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop", nil)

        -- Block resize grabber interaction even if shown
        rb:EnableMouse(false)
        rb:SetScript("OnMouseDown", nil)
        rb:SetScript("OnMouseUp", nil)
    else
        frame:SetMovable(true)
        frame:SetResizable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            SaveWindowPosition()
        end)

        rb:EnableMouse(true)
        rb:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
        rb:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
    end

    text:SetFont("Fonts\\FRIZQT__.TTF", s.fontSize, "OUTLINE")
    scrollChild:SetHeight(text:GetStringHeight() + 20)

    UpdateMinimapPosition()
    ApplyMinimapVisibility()
end

-- ==========================================
-- DATABASE
-- QuestTrackerDB = { quests = { [questID] = { title="...", chars={ [name]=1|2 } } } }
-- ==========================================
local function EnsureDB()
    QuestTrackerDB = QuestTrackerDB or {}

    -- migrate from old title-keyed DB if needed
    if QuestTrackerDB.quests == nil then
        local newDB = { quests = {} }
        for k, v in pairs(QuestTrackerDB) do
            if type(v) == "table" and v.__id then
                local qid = v.__id
                newDB.quests[qid] = newDB.quests[qid] or { title = k, chars = {} }
                for name, status in pairs(v) do
                    if name ~= "__id" and (status == 1 or status == 2) then
                        newDB.quests[qid].chars[name] = status
                    end
                end
            end
        end
        QuestTrackerDB = newDB
    end

    QuestTrackerDB.quests = QuestTrackerDB.quests or {}
end

-- ==========================================
-- UPDATE ENGINE (DEBOUNCED + CHANGE-TRACKED)
-- ==========================================
local updating = false
local pending = false
local pendingFullSweep = false

local collapsedHeaders = {}
local activeNow = {}
local prevActive = {}
local removedNow = {}

local questIDsSorted = {}
local charNamesSorted = {}
local lines = {}

local dbRevision = 0
local lastBuiltRevision = -1
local lastColorKey = ""

local function BumpRevision()
    dbRevision = dbRevision + 1
end

local function QuestHasAnyActive(chars)
    if not chars then return false end
    for _, status in pairs(chars) do
        if status == 1 then return true end
    end
    return false
end

local function ScanQuestLog()
    wipe(collapsedHeaders)
    wipe(activeNow)

    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, _, _, isHeader, isCollapsed = GetQuestLogTitle(i)
        if isHeader and isCollapsed and title then
            collapsedHeaders[title] = true
        end
    end

    ExpandQuestHeader(0)

    numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, _, _, isHeader, _, _, _, qID = GetQuestLogTitle(i)
        if title and not isHeader and qID then
            activeNow[qID] = title
        end
    end

    for i = numEntries, 1, -1 do
        local title, _, _, isHeader = GetQuestLogTitle(i)
        if isHeader and title and collapsedHeaders[title] then
            CollapseQuestHeader(i)
        end
    end
end

local function ComputeRemovedSinceLastScan()
    wipe(removedNow)

    for qid in pairs(prevActive) do
        if not activeNow[qid] then
            removedNow[qid] = true
        end
    end

    wipe(prevActive)
    for qid in pairs(activeNow) do
        prevActive[qid] = true
    end
end

local function UpdateDBOnly(fullSweep)
    EnsureDB()

    local charName = UnitName("player")
    if not charName then return end

    local quests = QuestTrackerDB.quests
    local changed = false

    -- 1) current actives -> status 1
    for qid, title in pairs(activeNow) do
        local q = quests[qid]
        if not q then
            quests[qid] = { title = title, chars = { [charName] = 1 } }
            changed = true
        else
            q.chars = q.chars or {}
            if q.title ~= title then q.title = title; changed = true end
            if q.chars[charName] ~= 1 then q.chars[charName] = 1; changed = true end
        end
    end

    -- 2) removed from this char -> completed (2) or clear
    for qid in pairs(removedNow) do
        local q = quests[qid]
        if q and q.chars then
            local newStatus = IsQuestCompleted(qid) and 2 or nil
            if q.chars[charName] ~= newStatus then
                q.chars[charName] = newStatus
                changed = true
            end
        end
    end

    -- 3) full sweep: only for quests that are active on SOMEONE
    if fullSweep then
        for qid, q in pairs(quests) do
            if q and q.chars and q.chars[charName] == nil and not activeNow[qid] then
                if QuestHasAnyActive(q.chars) and IsQuestCompleted(qid) then
                    q.chars[charName] = 2
                    changed = true
                end
            end
        end
    end

    -- 4) prune: remove any quest with NO active characters
    for qid, q in pairs(quests) do
        if not q or not q.chars or not QuestHasAnyActive(q.chars) then
            quests[qid] = nil
            changed = true
        end
    end

    if changed then BumpRevision() end
end

local function RebuildDisplay()
    if not frame:IsShown() then return end

    local s = QuestTrackerSettings
    if not s or not s.activeColor then return end

    local activeHex = RGBToHex(s.activeColor.r, s.activeColor.g, s.activeColor.b)
    local doneHex   = RGBToHex(s.doneColor.r,   s.doneColor.g,   s.doneColor.b)
    local colorKey = activeHex .. "|" .. doneHex

    -- Skip rebuilding if DB and colors are unchanged
    if lastBuiltRevision == dbRevision and lastColorKey == colorKey then
        return
    end
    lastBuiltRevision = dbRevision
    lastColorKey = colorKey

    EnsureDB()

    wipe(questIDsSorted)
    for qid in pairs(QuestTrackerDB.quests) do
        questIDsSorted[#questIDsSorted + 1] = qid
    end

    tsort(questIDsSorted, function(a, b)
        local qa = QuestTrackerDB.quests[a] and QuestTrackerDB.quests[a].title or ""
        local qb = QuestTrackerDB.quests[b] and QuestTrackerDB.quests[b].title or ""
        return qa < qb
    end)

    wipe(lines)
    local lineCount = 0

    for _, qid in ipairs(questIDsSorted) do
        local q = QuestTrackerDB.quests[qid]
        if q and q.chars then
            wipe(charNamesSorted)
            for name, status in pairs(q.chars) do
                if status == 1 or status == 2 then
                    charNamesSorted[#charNamesSorted + 1] = name
                end
            end

            if #charNamesSorted > 0 then
                tsort(charNamesSorted)

                lineCount = lineCount + 1
                lines[lineCount] = "|cffffff00" .. (q.title or ("Quest " .. tostring(qid))) .. "|r"

                for i = 1, #charNamesSorted do
                    local name = charNamesSorted[i]
                    local status = q.chars[name]
                    lineCount = lineCount + 1
                    if status == 2 then
                        lines[lineCount] = "  |cff" .. doneHex .. name .. "|r"
                    else
                        lines[lineCount] = "  |cff" .. activeHex .. name .. "|r"
                    end
                end

                lineCount = lineCount + 1
                lines[lineCount] = ""
            end
        end
    end

    if lineCount == 0 then
        text:SetText("|cff808080No quests tracked.|r")
    else
        text:SetText(tconcat(lines, "\n"))
    end

    scrollChild:SetHeight(text:GetStringHeight() + 20)
end

local function DoUpdate()
    if updating then return end
    updating = true

    local doFullSweep = pendingFullSweep
    pendingFullSweep = false

    ScanQuestLog()
    ComputeRemovedSinceLastScan()
    UpdateDBOnly(doFullSweep)
    RebuildDisplay()

    updating = false
end

local function ScheduleUpdate(fullSweep)
    if fullSweep then
        pendingFullSweep = true
    end

    if pending then return end
    pending = true

    if C_Timer and C_Timer.After then
        C_Timer.After(5, function()
            pending = false
            DoUpdate()
        end)
    else
        pending = false
        DoUpdate()
    end
end

frame:HookScript("OnShow", function()
    RebuildDisplay()
end)

-- ==========================================
-- OPTIONS MENU
-- ==========================================
local options = CreateFrame("Frame", "QTOptionsPanel")
options.name = "Quest Tracker"

local function CreateSlider(label, min, max, setting, y)
    local sl = CreateFrame("Slider", "QT" .. setting .. "Slider", options, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", 20, y)
    sl:SetMinMaxValues(min, max)
    sl:SetValueStep(setting == "fontSize" and 1 or 0.1)
    sl:SetObeyStepOnDrag(true)
    _G[sl:GetName() .. "Text"]:SetText(label)
    sl:SetScript("OnValueChanged", function(_, val)
        QuestTrackerSettings[setting] = val
        ApplySettings()
        -- force rebuild (colors/fonts changed)
        lastBuiltRevision = -1
        RebuildDisplay()
    end)
    return sl
end

local fs = CreateSlider("Font Size", 8, 30, "fontSize", -40)
local as = CreateSlider("Background Transparency", 0, 1, "windowAlpha", -90)

-- (1) Lock window checkbox directly under background transparency bar
lockBtn = CreateFrame("CheckButton", "QTLockBtn", options, "InterfaceOptionsCheckButtonTemplate")
lockBtn:SetPoint("TOPLEFT", 20, -120)
_G[lockBtn:GetName() .. "Text"]:SetText("Lock Quest List Window")
lockBtn:SetScript("OnClick", function(self)
    QuestTrackerSettings.lockWindow = self:GetChecked()
    ApplySettings()
end)

local borderBtn = CreateFrame("CheckButton", "QTBorderBtn", options, "InterfaceOptionsCheckButtonTemplate")
borderBtn:SetPoint("TOPLEFT", 20, -150)
_G[borderBtn:GetName() .. "Text"]:SetText("Hide Border & Header")
borderBtn:SetScript("OnClick", function(self)
    QuestTrackerSettings.hideBorder = self:GetChecked()
    ApplySettings()
end)

-- (2) Hide close button directly under hide border/header
hideCloseBtn = CreateFrame("CheckButton", "QTHideCloseBtn", options, "InterfaceOptionsCheckButtonTemplate")
hideCloseBtn:SetPoint("TOPLEFT", 20, -180)
_G[hideCloseBtn:GetName() .. "Text"]:SetText('Hide Close Button "X"')
hideCloseBtn:SetScript("OnClick", function(self)
    QuestTrackerSettings.hideClose = self:GetChecked()
    ApplySettings()
end)

-- (3) Hide scroll bar directly under hide close button
hideScrollBtn = CreateFrame("CheckButton", "QTHideScrollBtn", options, "InterfaceOptionsCheckButtonTemplate")
hideScrollBtn:SetPoint("TOPLEFT", 20, -210)
_G[hideScrollBtn:GetName() .. "Text"]:SetText("Hide Scroll Bar")
hideScrollBtn:SetScript("OnClick", function(self)
    QuestTrackerSettings.hideScrollBar = self:GetChecked()
    ApplySettings()
end)

-- (4) Hide resize button directly under hide scroll bar
hideResizeBtn = CreateFrame("CheckButton", "QTHideResizeBtn", options, "InterfaceOptionsCheckButtonTemplate")
hideResizeBtn:SetPoint("TOPLEFT", 20, -240)
_G[hideResizeBtn:GetName() .. "Text"]:SetText("Hide Window Scale Button")
hideResizeBtn:SetScript("OnClick", function(self)
    QuestTrackerSettings.hideResize = self:GetChecked()
    ApplySettings()
end)

local miniCheck = CreateFrame("CheckButton", "QTMiniToggle", options, "InterfaceOptionsCheckButtonTemplate")
miniCheck:SetPoint("TOPLEFT", 20, -270)
_G[miniCheck:GetName() .. "Text"]:SetText("Show Minimap Button")
miniCheck:SetScript("OnClick", function(self)
    QuestTrackerSettings.showMinimap = self:GetChecked()
    ApplyMinimapVisibility()
end)

local function CreateColorBtn(label, y, colorKey, callback)
    local btn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
    btn:SetSize(160, 24)
    btn:SetPoint("TOPLEFT", 20, y)
    btn:SetText(label)
    btn:SetScript("OnClick", function()
        local c = QuestTrackerSettings[colorKey]
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                c.r, c.g, c.b = r, g, b
                -- force rebuild (colors changed)
                lastBuiltRevision = -1
                callback()
            end,
            r = c.r, g = c.g, b = c.b,
        })
    end)
end

CreateColorBtn("Background Color", -310, "bg", ApplySettings)
CreateColorBtn("Active Quest Color", -345, "activeColor", function() RebuildDisplay() end)
CreateColorBtn("Complete Quest Color", -380, "doneColor", function() RebuildDisplay() end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(options, options.name)
    Settings.RegisterAddOnCategory(category)
    qtCategoryID = category:GetID()
end

-- ==========================================
-- EVENTS & SLASH COMMANDS
-- ==========================================
local didInitialWorldSweep = false

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("QUEST_TURNED_IN")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        if not QuestTrackerSettings or not QuestTrackerSettings.bg then
            QuestTrackerSettings = CopyTable(defaults)
        end

        -- Backfill new settings if upgrading
        if QuestTrackerSettings.lockWindow == nil then QuestTrackerSettings.lockWindow = false end
        if QuestTrackerSettings.hideClose == nil then QuestTrackerSettings.hideClose = false end
        if QuestTrackerSettings.hideScrollBar == nil then QuestTrackerSettings.hideScrollBar = false end
        if QuestTrackerSettings.hideResize == nil then QuestTrackerSettings.hideResize = false end

        if QuestTrackerSettings.showMinimap == nil then
            QuestTrackerSettings.showMinimap = true
        end

        -- Backfill position field (don’t force-center; just ensure key exists)
        if QuestTrackerSettings.windowPos == nil then
            QuestTrackerSettings.windowPos = defaults.windowPos
        end

        EnsureDB()

        fs:SetValue(QuestTrackerSettings.fontSize)
        as:SetValue(QuestTrackerSettings.windowAlpha)
        lockBtn:SetChecked(QuestTrackerSettings.lockWindow)
        borderBtn:SetChecked(QuestTrackerSettings.hideBorder)
        hideCloseBtn:SetChecked(QuestTrackerSettings.hideClose)
        hideScrollBtn:SetChecked(QuestTrackerSettings.hideScrollBar)
        hideResizeBtn:SetChecked(QuestTrackerSettings.hideResize)
        miniCheck:SetChecked(QuestTrackerSettings.showMinimap)

        -- NEW: restore window position BEFORE applying settings (no other code re-anchors it)
        RestoreWindowPosition()

        ApplySettings()

        -- do the full sweep once after you actually enter the world (more reliable timing)
        didInitialWorldSweep = false

        frame:Hide()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        if not didInitialWorldSweep then
            didInitialWorldSweep = true
            ScheduleUpdate(true)   -- one full sweep per login session
        else
            ScheduleUpdate(false)  -- later world events: cheap updates
        end
    else
        ScheduleUpdate(false)      -- quest log spam: cheap updates
    end
end)

SLASH_QT1 = "/qt"
SlashCmdList["QT"] = function()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

SLASH_QTRESET1 = "/qtreset"
SlashCmdList["QTRESET"] = function()
    QuestTrackerDB = { quests = {} }
    wipe(prevActive)
    didInitialWorldSweep = false
    lastBuiltRevision = -1
    ScheduleUpdate(true)
    print("QuestTracker: Database reset.")
end
