-- Copyright (C) 2026 Pennoyer
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License.

local addonName, ns = ...
ns.PP = ns.PP or {}
local PP = ns.PP
PP.registry = PP.registry or {}

local visibleSlots = {}
local slotWidths = {}

local BackdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil

function PP:RegisterDatatext(id, definition)
    PP.registry[id] = definition
end

local defaults = {
    textColor = {r=1, g=1, b=1},
    panels = {
        ["MainPanel"] = {
            width = 450, height = 25,
            fontSize = 12,
            alpha = 1.0, 
            fontType = "Interface\\AddOns\\PennPanels\\Fonts\\ARIALN.ttf",
            position = {"CENTER", "UIParent", "CENTER", 0, 0},
            slots = {"Time", "Gold"} 
        }
    }
}

-----------------------------------------------------------------
-- Drawing the Panel, Moving Panel, Right Click Options
-----------------------------------------------------------------

function PP:RefreshPanel(panel, skipEnable)
    if not panel or not panel.panelID then return end
    local id = panel.panelID
    local config = PennPanelsDB.panels[id]
    
    panel.slots = panel.slots or {}
    local num = #config.slots
    
    -- 1. Initial Setup and Measurement
    local totalTextWidth = 0
    wipe(visibleSlots) -- Reuse static table
    wipe(slotWidths)   -- Reuse static table

    for i, dtID in ipairs(config.slots) do
        local slot = panel.slots[i]
        if not slot then
            slot = CreateFrame("Button", nil, panel)
            panel.slots[i] = slot
        end

        slot:SetParent(panel)
        slot:Show()
        slot:SetHeight(config.height)

       -- Apply font/size settings even during a skipEnable refresh
        if PP.registry[dtID] then
            if not skipEnable then
                -- Full restart: Clear scripts and events
                slot:UnregisterAllEvents()
                slot:SetScript("OnEvent", nil)
                slot:SetScript("OnUpdate", nil)
                PP.registry[dtID].OnEnable(slot, config.fontSize or 12, config.fontType or "Fonts\\FRIZQT__.ttf", config.valueColor)
            else
                -- Layout Only: Just update the font size/style visually
                if slot.text then
                    local fontPath = config.fontType or "Interface\\AddOns\\PennPanels\\Fonts\\ARIALN.ttf"
                    local _, _, flags = slot.text:GetFont()
                    slot.text:SetFont(fontPath, config.fontSize or 12, flags or "")
                end
            end
        end

        local textW = (slot.text and slot.text:GetStringWidth()) or 35
        local hitboxW = math.max(50, textW + 10) 
        
        slot:SetWidth(hitboxW)
        slotWidths[i] = hitboxW
        totalTextWidth = totalTextWidth + hitboxW
        table.insert(visibleSlots, slot)
    end

    -- Hide orphaned slots from previous larger configurations
    for i = num + 1, #panel.slots do
        panel.slots[i]:Hide()
    end

    -- 2. Layout Logic
    if num == 2 then
        local segmentWidth = config.width / 2
        for i, slot in ipairs(visibleSlots) do
            slot:ClearAllPoints()
            slot:SetWidth(segmentWidth) 
            slot:SetPoint("CENTER", panel, "LEFT", (i - 0.5) * segmentWidth, 0)
            if slot.text then
                slot.text:ClearAllPoints()
                slot.text:SetPoint("CENTER", slot, "CENTER", 0, 0)
            end
        end
    else
        local usableWidth = config.width - 30
        local finalGap = math.min(40, (num > 1) and (usableWidth - totalTextWidth) / (num - 1) or 0)
        local currentX = (config.width - (totalTextWidth + (finalGap * (num - 1)))) / 2

        for i, slot in ipairs(visibleSlots) do
            slot:ClearAllPoints()
            slot:SetPoint("LEFT", panel, "LEFT", currentX, 0)
            if slot.text then
                slot.text:ClearAllPoints()
                slot.text:SetPoint("CENTER", slot, "CENTER", 0, 0)
            end
            currentX = currentX + slotWidths[i] + finalGap
        end
    end
end

function PP:CreatePanel(id, config)
    local panel = _G["PP_Panel_"..id] or CreateFrame("Frame", "PP_Panel_" .. id, UIParent, BackdropTemplate)
    panel.panelID = id
    panel:SetSize(config.width, config.height)
    panel:SetPoint(unpack(config.position))
    
    -- Keep text from fading when using opacity slider
    panel:SetAlpha(1.0)

    -- 2. CREATE DYNAMIC BACKGROUND (Single instance)
    if not panel.bg then
        panel.bg = panel:CreateTexture(nil, "BACKGROUND")
        panel.bg:SetAllPoints()
    end
    
    --  Use a standard texture that supports VertexColor tinting
    panel.bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    
    -- Apply saved transparency (Tinting black 0,0,0 with alpha)
    panel.bg:SetVertexColor(0, 0, 0, config.alpha or 0.8)

    -- Thin black border around each panel
    panel:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8", 
        edgeSize = 1,
    })
    panel:SetBackdropBorderColor(0, 0, 0, 1)

    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    
    -- Moving panel with Shift + Left Click
    panel:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    panel:SetScript("OnDragStop", function(self) 
        self:StopMovingOrSizing() 
        local p, _, rp, x, y = self:GetPoint()
        PennPanelsDB.panels[id].position = {p, "UIParent", rp, x, y}
    end)


    -- Panel Menu on Right Click    
 	panel:SetScript("OnMouseDown", function(self, button)
        -- FAIL-SAFE: If a menu is open, the game might have missed a MouseUp
        if SettingsPanel:IsShown() then
            self:StopMovingOrSizing()
        end
       if button == "RightButton" then
        -- Check if any of the slots being hovered is the Volume slot
        for _, slot in ipairs(self.slots) do
            if slot:IsMouseOver() then
                -- Check the text to see if it's the Volume or Muted module
                if slot.text and slot.text:GetText() then
                    local txt = slot.text:GetText()
                    if txt:find("Vol") or txt:find("Muted") then
                        return -- Exit and let the Volume module handle its own click
                    end
                end
            end
        end

            MenuUtil.CreateContextMenu(self, function(owner, root)
                root:CreateTitle("PennPanels: " .. id)
                
                -- Module Management
                local add = root:CreateButton("Add Module")
                for key, _ in pairs(PP.registry) do
                    add:CreateButton(key, function()
                        table.insert(PennPanelsDB.panels[id].slots, key)
                        PP:RefreshPanel(panel)
                    end)
                end
                
                local rem = root:CreateButton("Remove Module")
                for i, key in ipairs(PennPanelsDB.panels[id].slots) do
                    rem:CreateButton(key, function()
                        table.remove(PennPanelsDB.panels[id].slots, i)
                        PP:RefreshPanel(panel)
                    end)
                end

                root:CreateButton("Addon Options", function() 
                    if PP.optionsCategoryID then Settings.OpenToCategory(PP.optionsCategoryID)
                    else Settings.OpenToCategory("PennPanels") end
                end)
                
                root:CreateDivider()
                local spacer = root:CreateButton(" ")
                spacer:SetEnabled(false) 
                
                root:CreateButton("|cffff0000Delete Panel|r", function()
                    PennPanelsDB.panels[id] = nil
                    panel:Hide()
                end)
            end) 
        end 
    end)

    PP:RefreshPanel(panel)
end

-----------------------------------------------------------------
-- Loading Logic - Options to Change Appearance of the Bars
-----------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, name)
    if name == addonName then
        PennPanelsDB = PennPanelsDB or defaults
        for k, v in pairs(defaults) do
            if PennPanelsDB[k] == nil then PennPanelsDB[k] = v end
        end

        local category = Settings.RegisterVerticalLayoutCategory("PennPanels")
        PP.settingsCategory = category

        -- 1. FONT SIZE SLIDERS
        Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", {name = "Panel Fonts"})
        for panelID, config in pairs(PennPanelsDB.panels) do
            local fontSetting = Settings.RegisterAddOnSetting(category, "PP_Font_"..panelID, "fontSize", config, Settings.VarType.Number, "Font Size: "..panelID, 12)
            fontSetting:SetValueChangedCallback(function(setting, value)
                config.fontSize = value
                local panelFrame = _G["PP_Panel_"..panelID]
                --Pass 'true' to recalculate hitboxes without restarting tickers
                if panelFrame then PP:RefreshPanel(panelFrame, true) end
            end)
            local fontSliderOptions = Settings.CreateSliderOptions(8, 24, 1)
            fontSliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            Settings.CreateSlider(category, fontSetting, fontSliderOptions, "Adjust font size")
        end

       -- 2. WIDTH SLIDERS
        Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", {name = "Panel Widths"})
        for panelID, config in pairs(PennPanelsDB.panels) do
            local widthSetting = Settings.RegisterAddOnSetting(category, "PP_Width_"..panelID, "width", config, Settings.VarType.Number, "Width: "..panelID, 300)
            widthSetting:SetValueChangedCallback(function(setting, value)
                if not PennPanelsDB.panels[panelID] then return end 
                config.width = value 
                local panelFrame = _G["PP_Panel_"..panelID]
                if panelFrame then 
                    panelFrame:SetWidth(value) 
                    --Pass 'true' to skip module re-initialization
                    PP:RefreshPanel(panelFrame, true) 
                end
            end)

            local widthSliderOptions = Settings.CreateSliderOptions(100, 1000, 1)
            widthSliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            Settings.CreateSlider(category, widthSetting, widthSliderOptions, "Adjust width in increments of 1 (Max 800)")
        end

        -- 3. HEIGHT SLIDERS
        Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", {name = "Panel Heights"})
        for panelID, config in pairs(PennPanelsDB.panels) do
            local heightSetting = Settings.RegisterAddOnSetting(category, "PP_Height_"..panelID, "height", config, Settings.VarType.Number, "Height: "..panelID, 25)
            heightSetting:SetValueChangedCallback(function(setting, value)
                config.height = value 
                local panelFrame = _G["PP_Panel_"..panelID]
                if panelFrame then 
                    panelFrame:SetHeight(value)
                    --Pass 'true' to skip module re-initialization
                    PP:RefreshPanel(panelFrame, true) 
                end
            end)
            local heightSliderOptions = Settings.CreateSliderOptions(10, 100, 1)
            heightSliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            Settings.CreateSlider(category, heightSetting, heightSliderOptions, "Adjust height")
        end

        -- 4. FONT TYPE SELECTION
        Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", {name = "Panel Font Styles"})
        local fontOptions = {
            {name = "Accidental Presidency", value = "Interface\\AddOns\\PennPanels\\Fonts\\accid___.ttf"},
            {name = "Arial Narrow", value = "Interface\\AddOns\\PennPanels\\Fonts\\ARIALN.TTF"},
            {name = "Atkinson", value = "Interface\\AddOns\\PennPanels\\Fonts\\AtkinsonHyperlegibleNext-Regular.otf"},
            {name = "Diablo", value = "Interface\\AddOns\\PennPanels\\Fonts\\DiabloHeavy.ttf"},
            {name = "Expressway", value = "Interface\\AddOns\\PennPanels\\Fonts\\expressway.otf"},
            {name = "Fritz Quadrata", value = "Interface\\AddOns\\PennPanels\\Fonts\\FrizQuadrataRegular.otf"},
            {name = "Poppins", value = "Interface\\AddOns\\PennPanels\\Fonts\\Poppins-SemiBold.ttf"},
            {name = "Roboto", value = "Interface\\AddOns\\PennPanels\\Fonts\\RobotoCondensed-Bold.ttf"},
        }

        for panelID, config in pairs(PennPanelsDB.panels) do
            config.fontType = config.fontType or "Interface\\AddOns\\PennPanels\\Fonts\\ARIALN.ttf"
            local fontTypeSetting = Settings.RegisterAddOnSetting(category, "PP_FontType_"..panelID, "fontType", config, Settings.VarType.String, "Style: "..panelID, "Interface\\AddOns\\PennPanels\\Fonts\\ARIALN.ttf")
            
            fontTypeSetting:SetValueChangedCallback(function(setting, value)
                config.fontType = value
                local panelFrame = _G["PP_Panel_"..panelID]
                if panelFrame then PP:RefreshPanel(panelFrame) end
            end)

            local function GetOptionsTable()
                local container = Settings.CreateControlTextContainer()
                for _, font in ipairs(fontOptions) do container:Add(font.value, font.name) end
                return container:GetData()
            end

            local initializer = Settings.CreateElementInitializer("SettingsDropdownControlTemplate", {
                setting = fontTypeSetting,
                options = GetOptionsTable,
                tooltip = "Change font style for "..panelID,
            })
            Settings.RegisterInitializer(category, initializer)
        end

      -- 5. OPACITY SLIDERS
    Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", {name = "Panel Opacity"})
    for panelID, config in pairs(PennPanelsDB.panels) do
    config.alpha = config.alpha or 1.0
    local alphaSetting = Settings.RegisterAddOnSetting(category, "PP_Alpha_"..panelID, "alpha", config, Settings.VarType.Number, "Opacity: "..panelID, 1.0)
    
    alphaSetting:SetValueChangedCallback(function(setting, value)
        config.alpha = value 
        local panelFrame = _G["PP_Panel_"..panelID]
        if panelFrame and panelFrame.bg then 
            panelFrame.bg:SetVertexColor(0, 0, 0, value)
            --Pass 'true' to keep layout stable without restarting modules
            PP:RefreshPanel(panelFrame, true) 
        end
    end)

    local alphaSliderOptions = Settings.CreateSliderOptions(0.1, 1.0, 0.05)
    alphaSliderOptions:SetLabelFormatter(function(value) return "" end)
    Settings.CreateSlider(category, alphaSetting, alphaSliderOptions, "Adjust background opacity")
    end

    --  6. INSTRUCTIONS / HELP TEXT 
        Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", {name = "PennPanels Commands & Help"})
        
        local helpLines = {
            "|cffffd700Slash Commands:|r",
            "• /pp or /pennpanels - Open options.",
            "• /pp new [name] - Create new panel.",
            "Reload after creating a new panel for its settings to appear here.",
            "Give a name for the panel to better track it in the options, e.g. /pp new Bottom Panel.",
            "This way it is easier to track which bar you're changing settings for.",
            "|cffffd700Interactions:|r",
            "• Shift + Left Click & Drag - Move panel.",
            "• Left click opens various tabs/panels.",
            "• Right Click - Quick menu (or Hold Right Click for Guild/Friends).",
            "|cffffd700Other Info:|r",
            "• Hover over module to see tooltips with more info.",
            "• When changing font, you may need to adjust size/width/height. It won't autoformat to fit",
        }

        for _, line in ipairs(helpLines) do
            local initializer = Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", {
                name = "|cffffffff" .. line .. "|r" 
            })
            Settings.RegisterInitializer(category, initializer)
        end

        -- 7. FINALIZATION
        Settings.RegisterAddOnCategory(category)
        PP.optionsCategoryID = category:GetID()

        for id, config in pairs(PennPanelsDB.panels) do
            PP:CreatePanel(id, config)
        end
    end 
end) 

-- Slash / commands
SLASH_PP1 = "/pp"
SLASH_PP2 = "/pennpanels"

SlashCmdList["PP"] = function(msg)
    msg = (msg or ""):lower():trim()
    
    if msg:find("^new") then
        local name = msg:sub(5):trim()
        name = (name ~= "") and name or "Panel" .. math.random(100)
        PennPanelsDB.panels[name] = { 
            width = 300, height = 25, fontSize = 12, 
            position = {"CENTER", "UIParent", "CENTER", 0, 0}, 
            slots = {"Time"} 
        }
        PP:CreatePanel(name, PennPanelsDB.panels[name])

    elseif msg == "" or msg == "options" or msg == "config" then
        if PP.optionsCategoryID then 
            Settings.OpenToCategory(PP.optionsCategoryID) 
        end
    end
end
