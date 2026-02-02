-- Copyright (C) 2026 Pennoyer
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License.

local addonName, ns = ...
ns.PP = ns.PP or {}
local PP = ns.PP

local function ApplySettings(textString, fontSize, fontType)
    if not textString then return end
    local db = PennPanelsDB or { textColor = {r=1, g=1, b=1} }
    
    local fontPath = fontType or "Interface\\AddOns\\PennPanels\\Fonts\\Standard.ttf"
    local _, _, fontFlags = textString:GetFont()
    
    textString:SetText("")
    textString:SetFontObject("GameFontNormal")
    textString:SetFont(fontPath, fontSize or 12, fontFlags or "")
    
    local currentFont = textString:GetFont()
    if not currentFont then
        textString:SetFont("Fonts\\FRIZQT__.TTF", fontSize or 12, fontFlags or "")
    end
    
    if db.textColor then
        textString:SetTextColor(db.textColor.r, db.textColor.g, db.textColor.b)
    end
end

local function GetHexColor(colorTable)
    local c = colorTable or {r=1, g=1, b=1}
    return string.format("ff%02x%02x%02x", c.r*255, c.g*255, c.b*255)
end

-- Strictly filter for LeftButton to prevent overlapping with the right-click menu
local function MakeClickable(slot, func)
    slot:EnableMouse(true)
    slot:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not IsShiftKeyDown() then 
            func() 
        end
    end)
end

------------------------------------
--       SOCIAL HELPERS
------------------------------------
local friendsCache = { wowFriends = {}, bnetRetail = {}, bnetClassic = {}, bnetOther = {}, lastUpdate = 0 }
local guildCache = { members = {}, lastUpdate = 0 }
local PROJECT_NAMES = { [1] = "Retail", [2] = "Classic", [5] = "TBC", [11] = "Wrath", [14] = "Cata" }

local unlocalizedClasses = {}
for token, localized in pairs(LOCALIZED_CLASS_NAMES_MALE) do unlocalizedClasses[localized] = token end
for token, localized in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do unlocalizedClasses[localized] = token end

local function GetClassColor(className)
    if not className then return {r=1, g=1, b=1} end
    local token = unlocalizedClasses[className] or className
    return RAID_CLASS_COLORS[token] or {r=1, g=1, b=1}
end

local function BuildFriendsCache()
    wipe(friendsCache.wowFriends); wipe(friendsCache.bnetRetail); wipe(friendsCache.bnetClassic); wipe(friendsCache.bnetOther)
    for i = 1, C_FriendList.GetNumFriends() do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.connected then
            table.insert(friendsCache.wowFriends, { 
                name = info.name, level = info.level, className = info.className, 
                zone = info.area, afk = info.afk, dnd = info.dnd, guid = info.guid
            })
        end
    end
    if BNConnected() then
        for i = 1, BNGetNumFriends() do
            local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
            if accountInfo and accountInfo.gameAccountInfo.isOnline then
                local game = accountInfo.gameAccountInfo
                local entry = { 
                    accountName = accountInfo.accountName, 
                    bnetID = accountInfo.bnetAccountID,
                    gameID = game.gameAccountID,
                    characterName = game.characterName, 
                    className = game.className, 
                    zone = game.areaName, 
                    client = game.clientProgram,
                    afk = accountInfo.isAFK or game.isGameAFK, 
                    dnd = accountInfo.isDND or game.isGameBusy
                }
                if game.clientProgram == BNET_CLIENT_WOW then
                    if game.wowProjectID == 1 then table.insert(friendsCache.bnetRetail, entry)
                    else entry.version = PROJECT_NAMES[game.wowProjectID] or "Classic"; table.insert(friendsCache.bnetClassic, entry) end
                else
                    entry.richPresence = game.richPresence or game.clientProgram; table.insert(friendsCache.bnetOther, entry)
                end
            end
        end
    end
    friendsCache.lastUpdate = GetTime()
end

local function BuildGuildCache()
    wipe(guildCache.members)
    if not IsInGuild() then return end
    local total = GetNumGuildMembers()
    for i = 1, total do
        local name, rank, _, _, _, zone, _, _, connected, status, class, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        if name and (connected or status ~= 0) then 
            table.insert(guildCache.members, {
                name = name, rank = rank, class = class, zone = zone, status = status, guid = guid, online = connected
            })
        end
    end
    guildCache.lastUpdate = GetTime()
end

------------------------------------
--       DATA MODULES
------------------------------------

-- 1. TIME
PP:RegisterDatatext("Time", {
    OnEnable = function(slot, fontSize, fontType)
        local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slot.text = text
        text:SetPoint("CENTER")
        ApplySettings(text, fontSize, fontType)

        -- Helper to format seconds into "Xd Xh Xm"
        local function FormatTime(seconds)
            if not seconds or seconds <= 0 then return "0m" end
            local days = math.floor(seconds / 86400)
            local hours = math.floor((seconds % 86400) / 3600)
            local minutes = math.floor((seconds % 3600) / 60)
            if days > 0 then return string.format("%dd %dh", days, hours)
            elseif hours > 0 then return string.format("%dh %dm", hours, minutes)
            else return string.format("%dm", minutes) end
        end

        --Only update the UI text when the minute changes
        local lastMinute = -1
        local function Update()
            local currentTime = date("*t") -- Gets local table: hour, min, sec, etc.
            
            if currentTime.min ~= lastMinute then
                local h = currentTime.hour
                local m = currentTime.min
                local suffix = (h >= 12) and "pm" or "am"
                
                h = h % 12
                if h == 0 then h = 12 end
                
                text:SetFormattedText("%d:%02d%s", h, m, suffix)
                lastMinute = m
            end
        end

        -- Tooltip: Reset Timers and Server Time
        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Schedule", 1, 1, 1)
            GameTooltip:AddLine(" ")

            -- 1. Daily Reset
            local dailyReset = C_DateAndTime.GetSecondsUntilDailyReset()
            if dailyReset and dailyReset > 0 then
                GameTooltip:AddDoubleLine("Daily Reset", FormatTime(dailyReset), 0.8, 0.8, 0.8, 1, 1, 1)
            end

            -- 2. Weekly Reset
            local weeklyReset = C_DateAndTime.GetSecondsUntilWeeklyReset()
            if weeklyReset and weeklyReset > 0 then
                GameTooltip:AddDoubleLine("Weekly Reset", FormatTime(weeklyReset), 0.8, 0.8, 0.8, 1, 1, 1)
            end

            -- 3. Server Time
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Server Time", GameTime_GetGameTime(true), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close the Calendar", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)

        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Check every 3s for the minute flip
        if not slot.ticker then slot.ticker = C_Timer.NewTicker(3, Update) end
        
        -- Calendar opens on click
        MakeClickable(slot, function() 
            ToggleCalendar() 
        end)
        
        C_Timer.After(0.01, Update)
    end
})
        
-- 2. GOLD
PP:RegisterDatatext("Gold", {
    OnEnable = function(slot, fontSize, fontType)
        local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slot.text = text
        text:SetPoint("CENTER")
        ApplySettings(text, fontSize, fontType)
        local function Update()
            local gold = floor(GetMoney() / 10000)
            text:SetFormattedText("|cffffd700%sg|r", BreakUpLargeNumbers(gold))
        end
        slot:RegisterEvent("PLAYER_MONEY")
        slot:SetScript("OnEvent", Update)
        MakeClickable(slot, function() ToggleCharacter("TokenFrame") end)
        Update()
        C_Timer.After(2, Update) --fixes bug showing 0g on logging in

         -- Tooltip to inform the user of the click action
        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close the Currency tab", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
         slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
})

-- 3. FRIENDS
PP:RegisterDatatext("Friends", {
    OnEnable = function(slot, fontSize, fontType, valueColor) 
        local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slot.text = text
        text:SetPoint("CENTER")
        ApplySettings(text, fontSize, fontType)

        local function Update()
            local _, onlineBNet = BNGetNumFriends()
            local hex = GetHexColor(valueColor) 
            text:SetFormattedText("|cff00bfffFriends:|r |c%s%d|r", hex, onlineBNet or 0)
        end

        slot:SetScript("OnEnter", function(self)
            if GetTime() - friendsCache.lastUpdate > 5 then BuildFriendsCache() end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM") 
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Friends List", 1, 1, 1)


            if #friendsCache.bnetRetail > 0 or #friendsCache.wowFriends > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("World of Warcraft (Retail)", 1, 1, 1)
                for _, f in ipairs(friendsCache.wowFriends) do
                    local color = GetClassColor(f.className)
                    local status = f.afk and "|cffFFFF00 {AFK}|r" or f.dnd and "|cffFF0000 {DND}|r" or ""
                    local inGroup = (UnitInParty(f.name) or UnitInRaid(f.name)) and "|cffaaaaaa*|r" or ""
                    GameTooltip:AddDoubleLine(f.name .. inGroup .. status, f.zone, color.r, color.g, color.b, 0.7, 0.7, 0.7)
                end
                for _, f in ipairs(friendsCache.bnetRetail) do
                    local color = GetClassColor(f.className)
                    local status = f.afk and "|cffFFFF00 {AFK}|r" or f.dnd and "|cffFF0000 {DND}|r" or ""
                    local inGroup = (UnitInParty(f.characterName) or UnitInRaid(f.characterName)) and "|cffaaaaaa*|r" or ""
                    GameTooltip:AddDoubleLine(f.characterName .. inGroup .. " ("..f.accountName..")" .. status, f.zone, color.r, color.g, color.b, 0.7, 0.7, 0.7)
                end
            end

            if #friendsCache.bnetClassic > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("World of Warcraft (Classic)", 1, 0.8, 0)
                for _, f in ipairs(friendsCache.bnetClassic) do
                    local color = GetClassColor(f.className)
                    local status = f.afk and "|cffFFFF00 {AFK}|r" or f.dnd and "|cffFF0000 {DND}|r" or ""
                    local inGroup = (UnitInParty(f.characterName) or UnitInRaid(f.characterName)) and "|cffaaaaaa*|r" or ""
                    local leftText = string.format("|cff%02x%02x%02x%s|r%s (%s) - %s%s", color.r*255, color.g*255, color.b*255, f.characterName, inGroup, f.accountName, f.version, status)
                    GameTooltip:AddDoubleLine(leftText, f.zone or "Unknown", 1, 1, 1, 0.7, 0.7, 0.7)
                end
            end

            if #friendsCache.bnetOther > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Other Games", 0.5, 0.5, 0.5)
                for _, f in ipairs(friendsCache.bnetOther) do
                    local status = f.afk and "|cffFFFF00 {AFK}|r" or f.dnd and "|cffFF0000 {DND}|r" or ""
                    GameTooltip:AddDoubleLine(f.accountName .. status, f.richPresence, 0.8, 0.8, 0.8, 0.5, 0.5, 0.5)
                end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close Friends panel", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("|cff00ffffRight-click|r for Whisper/Invite Menu", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("|cff00ffffHOLD Right-click|r for Options", 0.7, 0.7, 0.7)
            end

            GameTooltip:Show()
        end)

        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        slot:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
        slot:RegisterEvent("BN_FRIEND_ACCOUNT_OFFLINE")
        slot:RegisterEvent("FRIENDLIST_UPDATE") 
        slot:RegisterEvent("PLAYER_ENTERING_WORLD")
        
        slot:SetScript("OnEvent", function()
            friendsCache.lastUpdate = 0 
            Update()
        end)

        -- Shield the background panel during right-clicks to prevent the Options menu from popping
        slot:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" or button == "Button4" then
                self:SetPropagateMouseClicks(false)
            end
        end)

        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp", "Button4Up") 
        slot:SetScript("OnClick", function(self, button)
            self:SetPropagateMouseClicks(true)

            if button == "LeftButton" then
                  ToggleFriendsFrame(1) 
            elseif button == "RightButton" or button == "Button4" then
                if GetTime() - friendsCache.lastUpdate > 1 then BuildFriendsCache() end
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle("Social: Friends")
                    
                    local whisperMenu = root:CreateButton("Whisper")
                    local hasRetail = false
                    for _, info in ipairs(friendsCache.wowFriends) do
                        hasRetail = true
                        local color = GetClassColor(info.className)
                        whisperMenu:CreateButton(string.format("|cff%02x%02x%02x%s|r", color.r*255, color.g*255, color.b*255, info.name), function() ChatFrame_SendTell(info.name) end)
                    end
                    for _, info in ipairs(friendsCache.bnetRetail) do
                        hasRetail = true
                        local color = GetClassColor(info.className)
                        whisperMenu:CreateButton(string.format("|cff%02x%02x%02x%s|r (%s)", color.r*255, color.g*255, color.b*255, info.characterName, info.accountName), function() ChatFrameUtil.SendBNetTell(info.accountName) end)
                    end

                    if hasRetail and #friendsCache.bnetClassic > 0 then whisperMenu:CreateDivider() end
                    for _, info in ipairs(friendsCache.bnetClassic) do
                        local color = GetClassColor(info.className)
                        whisperMenu:CreateButton(string.format("|cff%02x%02x%02x%s|r (%s) - %s", color.r*255, color.g*255, color.b*255, info.characterName, info.accountName, info.version), function() ChatFrameUtil.SendBNetTell(info.accountName) end)
                    end

                    if (#friendsCache.bnetClassic > 0 or hasRetail) and #friendsCache.bnetOther > 0 then whisperMenu:CreateDivider() end
                    for _, info in ipairs(friendsCache.bnetOther) do
                        whisperMenu:CreateButton(info.accountName .. " |cff888888(" .. info.richPresence .. ")|r", function() ChatFrameUtil.SendBNetTell(info.accountName) end)
                    end

                    local inviteMenu = root:CreateButton("Invite")
                    for _, info in ipairs(friendsCache.bnetRetail) do
                        if info.characterName and not UnitInParty(info.characterName) and not UnitInRaid(info.characterName) then
                            local color = GetClassColor(info.className)
                            local label = string.format("|cff%02x%02x%02x%s|r (%s) - |cff888888%s|r", color.r*255, color.g*255, color.b*255, info.characterName, info.accountName, info.zone or "Unknown")
                            local invID = info.gameID
                            inviteMenu:CreateButton(label, function() BNInviteFriend(invID) end)
                        end
                    end
                end)
            end
        end)
        Update()
        C_Timer.After(2, Update)
    end
})

-- 4. GUILD
PP:RegisterDatatext("Guild", {
    OnEnable = function(slot, fontSize, fontType, valueColor)
        local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slot.text = text
        text:SetPoint("CENTER")
        ApplySettings(text, fontSize, fontType)

        local function Update()
            if not IsInGuild() then
                text:SetText("No Guild")
                return
            end
            C_GuildInfo.GuildRoster()
            local _, online = GetNumGuildMembers()
            local hex = GetHexColor(valueColor)
            text:SetFormattedText("|cff00ff00Guild:|r |c%s%d|r", hex, online or 0)
        end

        slot:SetScript("OnEnter", function(self)
            if not IsInGuild() then return end
            if GetTime() - guildCache.lastUpdate > 5 then BuildGuildCache() end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM") 
            GameTooltip:ClearLines()
            local guildName = GetGuildInfo("player")
            GameTooltip:AddLine(guildName or "Guild", 1, 1, 1)
            local motd = GetGuildRosterMOTD()
            if motd and motd ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("MOTD:", 1, 0.8, 0)
                GameTooltip:AddLine(motd, 0.8, 0.8, 0.8, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Online Members", 1, 1, 1)
            for _, info in ipairs(guildCache.members) do
                local color = GetClassColor(info.class)
                local status = info.status == 1 and "|cffFFFF00 {AFK}|r" or info.status == 2 and "|cffFF0000 {DND}|r" or ""
                local inGroup = (UnitInParty(info.name) or UnitInRaid(info.name)) and "|cffaaaaaa*|r" or ""
                local leftText = string.format("|cff%02x%02x%02x%s|r%s%s |cffffffff- %s|r", color.r*255, color.g*255, color.b*255, Ambiguate(info.name, "guild"), inGroup, status, info.rank or "Member")
                GameTooltip:AddDoubleLine(leftText, info.zone or "Unknown", 1, 1, 1, 0.7, 0.7, 0.7)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close Guild panel", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("|cff00ffffRight-click|r for Whisper/Invite Menu", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("|cff00ffffHOLD Right-click|r for Options", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)

        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Shield the background panel during right-clicks to prevent menu conflicts
        slot:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" or button == "Button4" then
                self:SetPropagateMouseClicks(false)
            end
        end)

        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp", "Button4Up")
        slot:SetScript("OnClick", function(self, button)
            -- Restore propagation immediately
            self:SetPropagateMouseClicks(true)

            if button == "LeftButton" then
                ToggleGuildFrame()
            -- Menu Bind: Plain Right Click OR Button 4 (Shift no longer required)
            elseif (button == "RightButton" or button == "Button4") and IsInGuild() then
                if GetTime() - guildCache.lastUpdate > 1 then BuildGuildCache() end
                local myName = UnitName("player")
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle("Social: Guild")
                    local whisperMenu = root:CreateButton("Whisper")
                    for _, info in ipairs(guildCache.members) do
                        local displayName = Ambiguate(info.name, "guild")
                        if info.online and displayName ~= myName then
                            local color = GetClassColor(info.class)
                            local name = info.name
                            whisperMenu:CreateButton(string.format("|cff%02x%02x%02x%s|r", color.r*255, color.g*255, color.b*255, displayName), function() ChatFrame_SendTell(name) end)
                        end
                    end
                    local inviteMenu = root:CreateButton("Invite")
                    for _, info in ipairs(guildCache.members) do
                        local displayName = Ambiguate(info.name, "guild")
                        if info.online and displayName ~= myName and not UnitInParty(info.name) and not UnitInRaid(info.name) then
                            local color = GetClassColor(info.class)
                            local label = string.format("|cff%02x%02x%02x%s|r - |cff888888%s|r", color.r*255, color.g*255, color.b*255, displayName, info.zone or "Unknown")
                            local name = info.name
                            inviteMenu:CreateButton(label, function() C_PartyInfo.InviteUnit(name) end)
                        end
                    end
                end)
            end
        end)

        slot:RegisterEvent("GUILD_ROSTER_UPDATE")
        slot:RegisterEvent("PLAYER_GUILD_UPDATE")
        slot:RegisterEvent("PLAYER_ENTERING_WORLD")
        slot:SetScript("OnEvent", function(self, event, unit)
            if event == "PLAYER_GUILD_UPDATE" and unit and unit ~= "player" then return end
            guildCache.lastUpdate = 0 
            Update()
        end)
        Update()
        C_Timer.After(2, Update)
    end
})

-- 5. BAGS
PP:RegisterDatatext("Bags", {
    OnEnable = function(slot, fontSize, fontType)
        local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slot.text = text
        text:SetPoint("CENTER")
        ApplySettings(text, fontSize, fontType)
        local function Update()
            local free, total = 0, 0
            for i = 0, 4 do
                local freeSlots, bagType = C_Container.GetContainerNumFreeSlots(i)
                if bagType == 0 then
                    free = free + freeSlots
                    total = total + C_Container.GetContainerNumSlots(i)
                end
            end
            text:SetFormattedText("|cffffff00Bags:|r %d/%d", (total - free), total)
        end
        slot:RegisterEvent("BAG_UPDATE")
        slot:SetScript("OnEvent", Update)
        MakeClickable(slot, function() ToggleAllBags() end)
        Update()

         -- Tooltip to inform the user of the click action
        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close Bags", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    
})

-- 6. SYSTEM
PP:RegisterDatatext("FPS/Ping", {
    OnEnable = function(slot, fontSize, fontType)
        local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slot.text = text
        text:SetPoint("CENTER")
        ApplySettings(text, fontSize, fontType)
        
        local function Update()
            local fps = floor(GetFramerate())
            local _, _, _, latency = GetNetStats()
            text:SetFormattedText("FPS: %d MS: %d", fps, latency)
        end

        -- Tooltip to inform the user of the click action
        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close Graphics options", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Shield the background panel from the 12.0 "Pressed" state lock
        slot:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                self:SetPropagateMouseClicks(false) 
            end
        end)

        --Click to open/close Graphics menu
       slot:RegisterForClicks("LeftButtonUp")
        slot:SetScript("OnClick", function(self, button)
            self:SetPropagateMouseClicks(true)

            if button == "LeftButton" and not IsShiftKeyDown() then
                if SettingsPanel:IsShown() then
                    HideUIPanel(SettingsPanel)
                else
                    local graphicsCategory = Settings.GetCategory("Graphics")
                    if graphicsCategory then
                        Settings.OpenToCategory(graphicsCategory:GetID())
                    else
                        Settings.OpenToCategory(Settings.VIDEO_CATEGORY_ID)
                    end
                end
            end
        end)

        if not slot.ticker then slot.ticker = C_Timer.NewTicker(2, Update) end
        Update()
    end
})

-- 7. DURABILITY
PP:RegisterDatatext("Durability", {
    OnEnable = function(slot, fontSize, fontType)
        local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slot.text = text
        text:SetPoint("CENTER")
        ApplySettings(text, fontSize, fontType)

        local function Update()
            local total, current = 0, 0
            for i = 1, 18 do
                local dur, maxDur = GetInventoryItemDurability(i)
                if dur then total = total + maxDur; current = current + dur end
            end
            
            local percent = (total > 0) and floor((current / total) * 100) or 100
            
            -- Determine Color based on durability level
            local colorStr
            if percent >= 75 then
                colorStr = "00ff00" -- Green (75%+)
            elseif percent >= 50 then
                colorStr = "ffff00" -- Yellow (50% to 74%)
            elseif percent >= 25 then
                colorStr = "ff7f00" -- Orange (25% to 49%)
            else
                colorStr = "ff0000" -- Red (0% to 24%)
            end
            
            -- Apply formatting with the dynamic hex color
            text:SetFormattedText("Dur: |cff%s%d%%|r", colorStr, percent)
        end

        slot:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
        slot:SetScript("OnEvent", Update)

        -- Left click opens Character/Armor screen
        MakeClickable(slot, function() 
            ToggleCharacter("PaperDollFrame") 
        end)

        Update()

         -- Tooltip to inform the user of the click action
        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close the Character panel", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
    
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
})

-- 8. ADDON MEMORY & CPU
PP:RegisterDatatext("Memory/CPU", {
    OnEnable = function(slot, fontSize, fontType)
        local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slot.text = text
        text:SetPoint("CENTER")
        ApplySettings(text, fontSize, fontType)
        
        local function Update()
            UpdateAddOnMemoryUsage()
            local mem = GetAddOnMemoryUsage(addonName)
            if mem > 1024 then
                text:SetFormattedText("Mem: %.2f mb", mem / 1024)
            else
                text:SetFormattedText("Mem: %.0f kb", mem)
            end
        end

        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddDoubleLine("Addon Performance", "(CPU/Mem)", 0, 1, 1, 0.5, 0.5, 0.5)
            GameTooltip:AddLine(" ")
            UpdateAddOnMemoryUsage()
            UpdateAddOnCPUUsage()
            local addons = {}
            for i = 1, C_AddOns.GetNumAddOns() do
                if C_AddOns.IsAddOnLoaded(i) then
                    local name = C_AddOns.GetAddOnInfo(i)
                    local mem = GetAddOnMemoryUsage(i)
                    local cpu = GetAddOnCPUUsage(i)
                    table.insert(addons, {name = name, mem = mem, cpu = cpu})
                end
            end
            table.sort(addons, function(a, b) return a.cpu > b.cpu end)
            for i = 1, math.min(#addons, 15) do
                local a = addons[i]
                local memStr = a.mem > 1024 and string.format("%.1fmb", a.mem / 1024) or string.format("%.0fkb", a.mem)
                local cpuStr = string.format("%.1fms", a.cpu)
                local cpuCol = a.cpu > 50 and "|cffff0000" or "|cffffffff"
                GameTooltip:AddDoubleLine(a.name, cpuCol..cpuStr.." |r|cffaaaaaa("..memStr..")|r")
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ffffLeft-click|r to collect garbage", 0.5, 0.5, 0.5)
            GameTooltip:AddLine("For CPU Usage, use |cff00ff00/console scriptProfile 1|r and |cff00ff00reload|r. Use |cff00ff000|r to disable again.", 0.5, 0.5, 0.5)
            GameTooltip:AddLine("|cffff00ffCPU Profiling may affect game performance.|r", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)

        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        slot:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                collectgarbage("collect")
                Update()
                print("|cff00ffffPennPanels:|r Memory garbage collected.")
            end
        end)

        if not slot.ticker then slot.ticker = C_Timer.NewTicker(15, Update) end
        Update()
    end
})

-- 9. TALENT LOADOUT NAME
PP:RegisterDatatext("Talent Loadout", {
    OnEnable = function(slot, fontSize, fontType)
        local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slot.text = text
        text:SetPoint("CENTER")
        ApplySettings(text, fontSize, fontType)

        local function Update()
            local specIndex = GetSpecialization()
            if not specIndex then 
                text:SetText("No Spec")
                return 
            end

            local specID = GetSpecializationInfo(specIndex)
            local r, g, b = 1, 1, 1 -- Default white

            -- 1. Check for Starter Build
            if C_ClassTalents.GetStarterBuildActive() then
                text:SetFormattedText("|cff0070DDStarter Build|r")
                return
            end

            -- 2. Get the ID of the last selected saved loadout
            local configID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
            if configID then
                local configInfo = C_Traits.GetConfigInfo(configID)
                if configInfo and configInfo.name then
                    -- Display the name you gave your talent profile (e.g., "Raid")
                    text:SetText(configInfo.name)
                else
                    text:SetText("No Loadout")
                end
            else
                text:SetText("Custom")
            end
        end

        -- Events to trigger an update when talents or specs change
        slot:RegisterEvent("PLAYER_TALENT_UPDATE")
        slot:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        slot:RegisterEvent("TRAIT_CONFIG_UPDATED")
        slot:RegisterEvent("PLAYER_ENTERING_WORLD")
        
        slot:SetScript("OnEvent", function()
            -- Small delay to let the API update after a change
            C_Timer.After(0.2, Update)
        end)

        -- Tooltip to inform the user of the click action
        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close Talents", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        --Open Talents on Left click
   MakeClickable(slot, function() 
    local TALENT_TAB_INDEX = 2 
    
    -- If the frame is not even loaded, load it securely to the talent tab
    if not PlayerSpellsFrame then
        TogglePlayerSpellsFrame(TALENT_TAB_INDEX)
    else
        -- If already open on the talent tab, close it securely
        if PlayerSpellsFrame:IsShown() and (PlayerSpellsFrame.GetTab and PlayerSpellsFrame:GetTab() == TALENT_TAB_INDEX) then
            TogglePlayerSpellsFrame(TALENT_TAB_INDEX)
        else
            -- If closed or on another tab, open/switch to talents securely
            ShowUIPanel(PlayerSpellsFrame)
            PlayerSpellsFrame:SetTab(TALENT_TAB_INDEX)
        end
    end
end)
        
        Update()
    end
})

-- 10. VOLUME
PP:RegisterDatatext("Volume", {
    OnEnable = function(slot, fontSize, fontType)
        local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slot.text = text
        text:SetPoint("CENTER")
        ApplySettings(text, fontSize, fontType)

        -- Helper to get/set volume percentages (0-100)
        local function GetVolume() return math.floor(GetCVar("Sound_MasterVolume") * 100 + 0.5) end
        local function SetVolume(val) SetCVar("Sound_MasterVolume", math.min(1, math.max(0, val / 100))) end

        local function Update()
            local vol = GetVolume()
            local isMuted = GetCVar("Sound_EnableAllSound") == "0"
            
            if isMuted then
                text:SetFormattedText("|cffff0000Muted|r")
            else
                -- Color logic: Yellow if low, White otherwise
                local color = "ffffff"
                text:SetFormattedText("Vol: |cff%s%d%%|r", color, vol)
            end
        end

        -- Enable Mouse Wheel for Scrolling
        slot:EnableMouseWheel(true)
        slot:SetScript("OnMouseWheel", function(self, delta)
            local current = GetVolume()
            SetVolume(current + (delta * 5)) -- Adjusts by 5% per click
            Update()
        end)

        -- Tooltip showing various levels
        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close Audio settings", 0.5, 0.5, 0.5)
            GameTooltip:AddLine("|cff00ffffScroll|r to adjust Master Volume", 0.5, 0.5, 0.5)
            GameTooltip:AddLine("|cff00ffffRight-Click|r to Toggle Mute", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        
        slot:SetScript("OnMouseDown", function(self, button)
            -- This stops the "Down" event from traveling up to PennPanels background
            self:SetPropagateMouseClicks(false) 
        end)

       slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
       slot:SetScript("OnClick", function(self, button)
            self:SetPropagateMouseClicks(true)

            if button == "LeftButton" and not IsShiftKeyDown() then
                if SettingsPanel:IsShown() then
                    HideUIPanel(SettingsPanel) -- Standard secure way to close
                else
                    Settings.OpenToCategory(Settings.AUDIO_CATEGORY_ID)
                end
            elseif button == "RightButton" then
                local current = GetCVar("Sound_EnableAllSound")
                SetCVar("Sound_EnableAllSound", current == "1" and "0" or "1")
                Update()
            end
        end)
        Update()
    end
})

-- 11. COORDINATES
PP:RegisterDatatext("Coordinates", {
    OnEnable = function(slot, fontSize, fontType)
        local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slot.text = text
        text:SetPoint("CENTER")
        ApplySettings(text, fontSize, fontType)

        local function Update()
            local mapID = C_Map.GetBestMapForUnit("player")
            
            if mapID then
                local pos = C_Map.GetPlayerMapPosition(mapID, "player")
                if pos and pos.GetXY then
                    local x, y = pos:GetXY()
                    if x and y then
                        -- Formatting to two decimal places (e.g., 45, 12)
                        text:SetFormattedText("|cffffff00Coords:|r %d, %d", x * 100, y * 100)
                        return
                    end
                end
            end
            -- Fallback for instances or unmapped areas
            text:SetText("|cffffff00Coords:|r --, --")
        end

        -- Update every 0.5 seconds for smooth movement tracking
        slot.ticker = C_Timer.NewTicker(0.5, Update)

        -- Tooltip setup
        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Coordinates", 1, 1, 1)
            GameTooltip:AddLine(GetZoneText() or "Unknown Zone", 1, 0.82, 0)
            
            local subzone = GetSubZoneText()
            if subzone and subzone ~= "" then
                GameTooltip:AddLine(subzone, 0.7, 0.7, 0.7)
            end
            
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close World Map", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Click to open Map
        slot:SetScript("OnClick", function()
            ToggleWorldMap()
        end)

        Update()
    end,
    
    OnDisable = function(slot)
        if slot.ticker then
            slot.ticker:Cancel()
            slot.ticker = nil
        end
    end
})
