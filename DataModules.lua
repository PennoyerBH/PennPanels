-- Copyright (C) 2026 Pennoyer
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License.

local addonName, ns = ...
ns.PP = ns.PP or {}
local PP = ns.PP
local menuFrame = CreateFrame("Frame", "PennPanels_DataMenuFrame", UIParent, "UIDropDownMenuTemplate")

------------------------------------
--       HELPERS
------------------------------------

-- --- General Helpers ---
local function ApplySettings(textString, fontSize, fontType)
    if not textString then return end
    local db = PennPanelsDB or { textColor = {r=1, g=1, b=1} }
    
    local fontPath = fontType or "Fonts\\FRIZQT__.ttf"
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

local function MakeClickable(slot, func)
    slot:EnableMouse(true)
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and not IsShiftKeyDown() then 
            func() 
        elseif button == "RightButton" then
            ns.PP:OpenPanelMenu(self:GetParent())
        end
    end)
end

-- --- COMPATIBILITY HELPERS ---
local function GetNumFriendsUniversal()
    if C_FriendList and C_FriendList.GetNumFriends then return C_FriendList.GetNumFriends() else return GetNumFriends() end
end

local function GetFriendInfoUniversal(index)
    if C_FriendList and C_FriendList.GetFriendInfoByIndex then return C_FriendList.GetFriendInfoByIndex(index)
    else
        local name, level, class, area, connected, status, notes = GetFriendInfo(index)
        if not name then return nil end
        return { name = name, level = level, className = class, area = area, connected = connected, afk = (status == "AFK"), dnd = (status == "DND") }
    end
end

-- Safe Invite: Tries Retail API first, falls back to Classic global
local function SafeInvite(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then InviteUnit(name) end
end

-- --- SOCIAL HELPERS ---
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
    
    local numFriends = GetNumFriendsUniversal()
    for i = 1, numFriends do
        local info = GetFriendInfoUniversal(i)
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
                    dnd = accountInfo.isDND or game.isGameBusy,
                    wowProjectID = game.wowProjectID,
                    richPresence = game.richPresence -- Store rich presence for non-WoW games
                }
                
                if game.clientProgram == BNET_CLIENT_WOW then
                    if game.wowProjectID == 1 then 
                        entry.version = "Retail"
                        table.insert(friendsCache.bnetRetail, entry)
                    else 
                        entry.version = PROJECT_NAMES[game.wowProjectID] or "Classic"
                        table.insert(friendsCache.bnetClassic, entry) 
                    end
                else
                    -- For non-WoW games (App, OW, Diablo), use the client name or rich presence
                    entry.version = game.richPresence or game.clientProgram or "App"
                    table.insert(friendsCache.bnetOther, entry)
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

        local function FormatTime(seconds)
            if not seconds or seconds <= 0 then return "0m" end
            local days = math.floor(seconds / 86400)
            local hours = math.floor((seconds % 86400) / 3600)
            local minutes = math.floor((seconds % 3600) / 60)
            if days > 0 then return string.format("%dd %dh", days, hours)
            elseif hours > 0 then return string.format("%dh %dm", hours, minutes)
            else return string.format("%dm", minutes) end
        end

        local lastMinute = -1
        local function Update()
            local currentTime = date("*t")
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

        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Schedule", 1, 1, 1)
            GameTooltip:AddLine(" ")
            
            if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
                local dailyReset = C_DateAndTime.GetSecondsUntilDailyReset()
                if dailyReset and dailyReset > 0 then
                    GameTooltip:AddDoubleLine("Daily Reset", FormatTime(dailyReset), 0.8, 0.8, 0.8, 1, 1, 1)
                end
                local weeklyReset = C_DateAndTime.GetSecondsUntilWeeklyReset()
                if weeklyReset and weeklyReset > 0 then
                    GameTooltip:AddDoubleLine("Weekly Reset", FormatTime(weeklyReset), 0.8, 0.8, 0.8, 1, 1, 1)
                end
            end
            
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Server Time", GameTime_GetGameTime(true), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close the Calendar", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)

        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if not slot.ticker then slot.ticker = C_Timer.NewTicker(3, Update) end
        MakeClickable(slot, function() ToggleCalendar() end)
        C_Timer.After(0.01, Update)
    end
})
        
-- 2. GOLD
PP:RegisterDatatext("Gold", {
    OnEnable = function(slot, fontSize, fontType, valueColor)
        local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slot.text = text
        text:SetPoint("CENTER")
        ApplySettings(text, fontSize, fontType)
        
        local function Update()
            local gold = floor(GetMoney() / 10000)
            text:SetFormattedText("|cffffd700%sg|r", BreakUpLargeNumbers(gold))
        end
        
        slot:RegisterEvent("PLAYER_MONEY")
        slot:RegisterEvent("PLAYER_ENTERING_WORLD")
        slot:SetScript("OnEvent", Update)
        
        -- Update on Show to catch frame creation issues
        slot:SetScript("OnShow", Update)
        
        MakeClickable(slot, function() 
            local _, _, _, interfaceVersion = GetBuildInfo()
            if interfaceVersion >= 100000 then
                ToggleCharacter("TokenFrame") -- Retail
            else
                ToggleCharacter("PaperDollFrame") -- Classic
            end
        end)
        
        --  Use a Ticker (like Time module) to ensure persistence
        if not slot.ticker then 
            slot.ticker = C_Timer.NewTicker(2, Update)
        end
        Update()

        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            local _, _, _, interfaceVersion = GetBuildInfo()
            if interfaceVersion >= 100000 then
                GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close Currency", 0.5, 0.5, 0.5)
            else
                GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close Character", 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
         slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
})

-- 3. FRIENDS (Fixed: Class Colors, All BNet Friends, Strict Invites)
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
                    GameTooltip:AddDoubleLine(f.name .. status, f.zone, color.r, color.g, color.b, 0.7, 0.7, 0.7)
                end
                for _, f in ipairs(friendsCache.bnetRetail) do
                    local color = GetClassColor(f.className)
                    local status = f.afk and "|cffFFFF00 {AFK}|r" or f.dnd and "|cffFF0000 {DND}|r" or ""
                    GameTooltip:AddDoubleLine(f.characterName .. " ("..f.accountName..")" .. status, f.zone, color.r, color.g, color.b, 0.7, 0.7, 0.7)
                end
            end
            if #friendsCache.bnetClassic > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("World of Warcraft (Classic)", 1, 0.8, 0)
                for _, f in ipairs(friendsCache.bnetClassic) do
                    local color = GetClassColor(f.className)
                    local status = f.afk and "|cffFFFF00 {AFK}|r" or f.dnd and "|cffFF0000 {DND}|r" or ""
                    local ver = f.version and "("..f.version..")" or ""
                    local leftText = string.format("|cff%02x%02x%02x%s|r%s (%s) - %s%s", color.r*255, color.g*255, color.b*255, f.characterName, ver, f.accountName, f.version, status)
                    GameTooltip:AddDoubleLine(leftText, f.zone or "Unknown", 1, 1, 1, 0.7, 0.7, 0.7)
                end
            end
            if #friendsCache.bnetOther > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Other Games", 0.5, 0.5, 0.5)
                for _, f in ipairs(friendsCache.bnetOther) do
                    GameTooltip:AddDoubleLine(f.accountName, f.version or "App", 0.8, 0.8, 0.8, 0.5, 0.5, 0.5)
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close Friends panel", 0.7, 0.7, 0.7)
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

        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp", "Button4Up") 
        slot:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                  ToggleFriendsFrame(1) 
            elseif button == "RightButton" or button == "Button4" then
                if IsAltKeyDown() then
                    ns.PP:OpenPanelMenu(self:GetParent())
                    return
                end
                
                if GetTime() - friendsCache.lastUpdate > 1 then BuildFriendsCache() end
                
                -- Capture IDs for Strict Filtering
                local myProjectID = WOW_PROJECT_ID 

                if MenuUtil then 
                    -- RETAIL MENU LOGIC
                    MenuUtil.CreateContextMenu(self, function(_, root)
                        root:CreateTitle("Social: Friends")
                        
                        -- 1. WHISPER (Inclusive: WoW + App + Other Games)
                        local whisperMenu = root:CreateButton("Whisper")
                        
                        -- Add Realm Friends
                        for _, info in ipairs(friendsCache.wowFriends) do
                            local color = GetClassColor(info.className)
                            whisperMenu:CreateButton(string.format("|cff%02x%02x%02x%s|r", color.r*255, color.g*255, color.b*255, info.name), function() ChatFrame_SendTell(info.name) end)
                        end
                        
                        -- Add ALL Bnet Friends (Retail + Classic + App/Other)
                        local allBnet = {}
                        for _, v in ipairs(friendsCache.bnetRetail) do table.insert(allBnet, v) end
                        for _, v in ipairs(friendsCache.bnetClassic) do table.insert(allBnet, v) end
                        for _, v in ipairs(friendsCache.bnetOther) do table.insert(allBnet, v) end -- Include App/Overwatch/etc
                        
                        for _, info in ipairs(allBnet) do
                            local color = GetClassColor(info.className) -- White if no class (App users)
                            local ver = info.version and " - "..info.version or ""
                            local name = info.characterName or info.accountName
                            
                            -- Label with Class Color applied
                            local label = string.format("|cff%02x%02x%02x%s|r (%s)%s", color.r*255, color.g*255, color.b*255, name, info.accountName, ver)
                            
                            whisperMenu:CreateButton(label, function() ChatFrameUtil.SendBNetTell(info.accountName) end)
                        end

                        -- 2. INVITE (Strict ID Match Only)
                        local inviteMenu = root:CreateButton("Invite")
                        local count = 0
                        
                        -- A. Local Realm (Always matches)
                        for _, info in ipairs(friendsCache.wowFriends) do
                            if not UnitInParty(info.name) and not UnitInRaid(info.name) then
                                count = count + 1
                                local color = GetClassColor(info.className)
                                local label = string.format("|cff%02x%02x%02x%s|r", color.r*255, color.g*255, color.b*255, info.name)
                                inviteMenu:CreateButton(label, function() SafeInvite(info.name) end)
                            end
                        end

                        -- B. Battle.net (Strict Project ID Check)
                        local invBnet = {}
                        for _, v in ipairs(friendsCache.bnetRetail) do table.insert(invBnet, v) end
                        for _, v in ipairs(friendsCache.bnetClassic) do table.insert(invBnet, v) end
                        
                        for _, info in ipairs(invBnet) do
                            if info.wowProjectID == myProjectID then
                                if info.characterName and not UnitInParty(info.characterName) and not UnitInRaid(info.characterName) then
                                    count = count + 1
                                    local color = GetClassColor(info.className)
                                    local label = string.format("|cff%02x%02x%02x%s|r (%s)", color.r*255, color.g*255, color.b*255, info.characterName, info.accountName)
                                    inviteMenu:CreateButton(label, function() BNInviteFriend(info.gameID) end)
                                end
                            end
                        end

                        if count == 0 then
                            inviteMenu:SetEnabled(false)
                            inviteMenu:CreateButton("No invitable friends online")
                        end
                    end)
                else
                    -- CLASSIC/TBC FALLBACK (EasyMenu)
                    local menuList = {
                        { text = "Social: Friends", isTitle = true, notCheckable = true },
                        { text = "Whisper", hasArrow = true, notCheckable = true, menuList = {} },
                        { text = "Invite", hasArrow = true, notCheckable = true, menuList = {} }
                    }
                    
                    -- Populate Whisper (Inclusive + Colored)
                    for _, info in ipairs(friendsCache.wowFriends) do
                        local color = GetClassColor(info.className)
                        local text = string.format("|cff%02x%02x%02x%s|r", color.r*255, color.g*255, color.b*255, info.name)
                        table.insert(menuList[2].menuList, { text = text, notCheckable = true, func = function() ChatFrame_SendTell(info.name) end })
                    end
                    
                    local allBnet = {}
                    for _, v in ipairs(friendsCache.bnetRetail) do table.insert(allBnet, v) end
                    for _, v in ipairs(friendsCache.bnetClassic) do table.insert(allBnet, v) end
                    for _, v in ipairs(friendsCache.bnetOther) do table.insert(allBnet, v) end
                    
                    for _, info in ipairs(allBnet) do
                        local color = GetClassColor(info.className)
                        local ver = info.version and " - "..info.version or ""
                        local name = info.characterName or info.accountName
                        local text = string.format("|cff%02x%02x%02x%s|r (%s)%s", color.r*255, color.g*255, color.b*255, name, info.accountName, ver)
                        table.insert(menuList[2].menuList, { text = text, notCheckable = true, func = function() BNSendWhisper(info.bnetID, "") end })
                    end

                    -- Populate Invite (Strict + SafeInvite)
                    local invCount = 0
                    for _, info in ipairs(friendsCache.wowFriends) do
                        invCount = invCount + 1
                        local color = GetClassColor(info.className)
                        local text = string.format("|cff%02x%02x%02x%s|r", color.r*255, color.g*255, color.b*255, info.name)
                        table.insert(menuList[3].menuList, { text = text, notCheckable = true, func = function() SafeInvite(info.name) end })
                    end
                    
                    local invBnet = {}
                    for _, v in ipairs(friendsCache.bnetRetail) do table.insert(invBnet, v) end
                    for _, v in ipairs(friendsCache.bnetClassic) do table.insert(invBnet, v) end
                    
                    for _, info in ipairs(invBnet) do
                        if info.wowProjectID == myProjectID and info.characterName then
                            invCount = invCount + 1
                            local color = GetClassColor(info.className)
                            local text = string.format("|cff%02x%02x%02x%s|r (%s)", color.r*255, color.g*255, color.b*255, info.characterName, info.accountName)
                            table.insert(menuList[3].menuList, { text = text, notCheckable = true, func = function() BNInviteFriend(info.gameID) end })
                        end
                    end
                    
                    if invCount == 0 then
                        table.insert(menuList[3].menuList, { text = "No friends online", notCheckable = true, disabled = true })
                    end

                   EasyMenu(menuList, menuFrame, "cursor", 0, 0, "MENU")
                end
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
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
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
            GameTooltip:AddLine("|cff00ffffALT + Right-click|r for Panel Options", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)

        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp", "Button4Up")
        slot:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                ToggleGuildFrame()
            elseif (button == "RightButton" or button == "Button4") and IsInGuild() then
                 -- 1. ALT KEY CHECK: Opens Settings
                 if IsAltKeyDown() then
                    ns.PP:OpenPanelMenu(self:GetParent())
                    return
                end

                if MenuUtil then
                    -- RETAIL MENU
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
                                inviteMenu:CreateButton(label, function() SafeInvite(name) end)
                            end
                        end
                    end)
                else
                     -- CLASSIC FALLBACK
                     if GetTime() - guildCache.lastUpdate > 1 then BuildGuildCache() end
                     local myName = UnitName("player")
                     local menuList = {
                        { text = "Social: Guild", isTitle = true, notCheckable = true },
                        { text = "Whisper", hasArrow = true, notCheckable = true, menuList = {} },
                        { text = "Invite", hasArrow = true, notCheckable = true, menuList = {} }
                     }
                     
                     for _, info in ipairs(guildCache.members) do
                        local displayName = Ambiguate(info.name, "guild")
                        if info.online and displayName ~= myName then
                            local color = GetClassColor(info.class)
                            local text = string.format("|cff%02x%02x%02x%s|r", color.r*255, color.g*255, color.b*255, displayName)
                            table.insert(menuList[2].menuList, { text = text, notCheckable = true, func = function() ChatFrame_SendTell(info.name) end })
                        end
                     end
                     
                     for _, info in ipairs(guildCache.members) do
                        local displayName = Ambiguate(info.name, "guild")
                        if info.online and displayName ~= myName and not UnitInParty(info.name) and not UnitInRaid(info.name) then
                            local color = GetClassColor(info.class)
                            local text = string.format("|cff%02x%02x%02x%s|r - |cff888888%s|r", color.r*255, color.g*255, color.b*255, displayName, info.zone or "Unknown")
                            table.insert(menuList[3].menuList, { text = text, notCheckable = true, func = function() SafeInvite(info.name) end })
                        end
                     end
                     
                     -- Only call EasyMenu here, using the shared frame
                     EasyMenu(menuList, menuFrame, "cursor", 0, 0, "MENU")
                end
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
    OnEnable = function(slot, fontSize, fontType, valueColor)
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
            local hex = GetHexColor(valueColor)
            text:SetFormattedText("|cffffff00Bags:|r |c%s%d/%d|r", hex, (total - free), total)
        end
        slot:RegisterEvent("BAG_UPDATE")
        slot:SetScript("OnEvent", Update)
        MakeClickable(slot, function() ToggleAllBags() end)
        Update()

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

        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close Graphics options", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

       slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        slot:SetScript("OnClick", function(self, button)
            if button == "LeftButton" and not IsShiftKeyDown() then
                if SettingsPanel:IsShown() then
                    HideUIPanel(SettingsPanel)
                else
                    local foundID = nil
                    for i = 0, 100 do
                        local category = Settings.GetCategory(i)
                        if category and category.GetName and category:GetName() == "Graphics" then
                            foundID = i
                            break
                        end
                    end
                    if foundID then Settings.OpenToCategory(foundID)
                    else Settings.OpenToCategory(2) end
                end
            elseif button == "RightButton" then
                 ns.PP:OpenPanelMenu(self:GetParent())
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
            local colorStr = (percent >= 75) and "00ff00" or (percent >= 50) and "ffff00" or (percent >= 25) and "ff7f00" or "ff0000"
            text:SetFormattedText("Dur: |cff%s%d%%|r", colorStr, percent)
        end

        slot:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
        slot:SetScript("OnEvent", Update)
        MakeClickable(slot, function() ToggleCharacter("PaperDollFrame") end)
        Update()

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
local addonPerformanceTable = {}
PP:RegisterDatatext("Memory/CPU", {
    OnEnable = function(slot, fontSize, fontType)
        local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slot.text = text
        text:SetPoint("CENTER")
        ApplySettings(text, fontSize, fontType)
        
        local function Update()
            UpdateAddOnMemoryUsage()
            local mem = GetAddOnMemoryUsage("PennPanels")
            if mem > 1024 then text:SetFormattedText("Mem: %.2f mb", mem / 1024)
            else text:SetFormattedText("Mem: %.0f kb", mem) end
        end

        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddDoubleLine("Addon Performance", "(CPU/Mem)", 0, 1, 1, 0.5, 0.5, 0.5)
            GameTooltip:AddLine(" ")
            
            UpdateAddOnMemoryUsage()
            UpdateAddOnCPUUsage()
            
            wipe(addonPerformanceTable)
            for i = 1, C_AddOns.GetNumAddOns() do
                if C_AddOns.IsAddOnLoaded(i) then
                    local name = C_AddOns.GetAddOnInfo(i)
                    table.insert(addonPerformanceTable, {name = name, mem = GetAddOnMemoryUsage(i), cpu = GetAddOnCPUUsage(i)})
                end
            end
            table.sort(addonPerformanceTable, function(a, b) return a.cpu > b.cpu end)
            for i = 1, math.min(#addonPerformanceTable, 15) do
                local a = addonPerformanceTable[i]
                local memStr = a.mem > 1024 and string.format("%.1fmb", a.mem / 1024) or string.format("%.0fkb", a.mem)
                local cpuCol = a.cpu > 50 and "|cffff0000" or "|cffffffff"
                GameTooltip:AddDoubleLine(a.name, string.format("%s%.1fms|r |cffaaaaaa(%.1fmb)|r", cpuCol, a.cpu, a.mem/1024))
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ffffLeft-click|r to collect garbage", 0.5, 0.5, 0.5)
            GameTooltip:AddLine("To see CPU usage, type |cff00ff00/console scriptProfile 1|r and reload. Use |cff00ff000|r to disable", 0.5, 0.5, 0.5)
            GameTooltip:AddLine("|cffff00ffCPU profiling may affect game performance|r", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)

        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        slot:EnableMouse(true)
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        slot:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                collectgarbage("collect")
                print("|cff00ffffPennPanels:|r Memory garbage collected.")
            elseif button == "RightButton" then
                ns.PP:OpenPanelMenu(self:GetParent())
            end
        end)

        slot.ticker = C_Timer.NewTicker(15, Update)
        Update()
    end
})

-- 9. TALENT LOADOUT NAME (Only works in Retail)
if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
    PP:RegisterDatatext("Talent Loadout", {
        OnEnable = function(slot, fontSize, fontType)
            local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            slot.text = text
            text:SetPoint("CENTER")
            ApplySettings(text, fontSize, fontType)

            local function Update()
                local specIndex = GetSpecialization()
                if not specIndex then text:SetText("No Spec"); return end
                local specID = GetSpecializationInfo(specIndex)
                if C_ClassTalents.GetStarterBuildActive() then
                    text:SetFormattedText("|cff0070DDStarter Build|r")
                    return
                end
                local configID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
                if configID then
                    local configInfo = C_Traits.GetConfigInfo(configID)
                    if configInfo and configInfo.name then text:SetText(configInfo.name)
                    else text:SetText("No Loadout") end
                else text:SetText("Custom") end
            end

            slot:RegisterEvent("PLAYER_TALENT_UPDATE")
            slot:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
            slot:RegisterEvent("TRAIT_CONFIG_UPDATED")
            slot:RegisterEvent("PLAYER_ENTERING_WORLD")
            slot:SetScript("OnEvent", function() C_Timer.After(0.2, Update) end)

            slot:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:ClearLines()
                GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close Talents", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)
            slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

            MakeClickable(slot, function() 
                local TALENT_TAB_INDEX = 2 
                if not PlayerSpellsFrame then TogglePlayerSpellsFrame(TALENT_TAB_INDEX)
                else
                    if PlayerSpellsFrame:IsShown() and (PlayerSpellsFrame.GetTab and PlayerSpellsFrame:GetTab() == TALENT_TAB_INDEX) then
                        TogglePlayerSpellsFrame(TALENT_TAB_INDEX)
                    else ShowUIPanel(PlayerSpellsFrame); PlayerSpellsFrame:SetTab(TALENT_TAB_INDEX) end
                end
            end)
            Update()
        end
    })
end

-- 10. VOLUME
PP:RegisterDatatext("Volume", {
    OnEnable = function(slot, fontSize, fontType, valueColor)
        local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slot.text = text
        text:SetPoint("CENTER")
        ApplySettings(text, fontSize, fontType)

        local function GetVolume() return math.floor(GetCVar("Sound_MasterVolume") * 100 + 0.5) end
        local function SetVolume(val) SetCVar("Sound_MasterVolume", math.min(1, math.max(0, val / 100))) end

        local function Update()
            local vol = GetVolume()
            local isMuted = GetCVar("Sound_EnableAllSound") == "0"
            if isMuted then text:SetFormattedText("|cffff0000Muted|r")
            else 
                local hex = GetHexColor(valueColor)
                text:SetFormattedText("Vol: |c%s%d%%|r", hex, vol) 
            end
        end

        slot:EnableMouseWheel(true)
        slot:SetScript("OnMouseWheel", function(self, delta)
            local current = GetVolume()
            SetVolume(current + (delta * 5))
            Update()
        end)

        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close Audio settings", 0.5, 0.5, 0.5)
            GameTooltip:AddLine("|cff00ffffScroll|r to adjust Master Volume", 0.5, 0.5, 0.5)
            GameTooltip:AddLine("|cff00ffffRight-Click|r to Toggle Mute", 0.5, 0.5, 0.5)
            GameTooltip:AddLine("|cff00ffffALT + Right-Click|r for Panel Options", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
       slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
       slot:SetScript("OnClick", function(self, button)
            if button == "LeftButton" and not IsShiftKeyDown() then
                if SettingsPanel:IsShown() then HideUIPanel(SettingsPanel)
                else Settings.OpenToCategory(Settings.AUDIO_CATEGORY_ID) end
            elseif button == "RightButton" then
                 if IsAltKeyDown() then
                    ns.PP:OpenPanelMenu(self:GetParent())
                    return
                end
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
                        text:SetFormattedText("|cffffff00Coords:|r %d, %d", x * 100, y * 100)
                        return
                    end
                end
            end
            text:SetText("|cffffff00Coords:|r --, --")
        end

        slot.ticker = C_Timer.NewTicker(0.5, Update)

        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Coordinates", 1, 1, 1)
            GameTooltip:AddLine(GetZoneText() or "Unknown Zone", 1, 0.82, 0)
            local subzone = GetSubZoneText()
            if subzone and subzone ~= "" then GameTooltip:AddLine(subzone, 0.7, 0.7, 0.7) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ffffLeft-click|r to open/close World Map", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        MakeClickable(slot, function() ToggleWorldMap() end)
        Update()
    end,
    OnDisable = function(slot)
        if slot.ticker then slot.ticker:Cancel(); slot.ticker = nil end
    end
})


-- 12. MYTHIC+ KEY 

if C_MythicPlus then 

    local function GetKeyColor(level)
        if not level or level == 0 then return 0.7, 0.7, 0.7 end
        if level >= 10 then return 1, 0.5, 0 end        -- Orange
        if level >= 7 then return 0.64, 0.21, 0.93 end  -- Purple
        if level >= 4 then return 0, 0.44, 0.87 end     -- Blue
        if level >= 2 then return 0.12, 1, 0 end        -- Green
        return 1, 1, 1
    end

    local nameMap = {
        ["Magister's Terrace"] = "Terrace",
        ["Maisara Caverns"] = "Caverns",
        ["Nexus-Point Xenas"] = "Xenas",
        ["Windrunner Spire"] = "Spire",
        ["Algeth'ar Academy"] = "Academy",
        ["Seat of the Triumvirate"] = "Seat",
        ["Skyreach"] = "Skyreach",
        ["Pit of Saron"] = "Pit",
        ["Eco-Dome Aldani"] = "Ecodome",
        ["Tazavesh: Soleah's Gambit"] = "Gambit",
        ["Priory of the Sacred Flame"] = "Priory",
        ["Operation Floodgate"] = "Floodgate",
        ["Halls of Atonement"] = "Halls",
        ["Ara'kara, City of Echoes"] = "Ara-Kara",
        ["Ara-Kara, City of Echoes"] = "Ara-Kara",
        ["Tazavesh: Streets of Wonder"] = "Streets",
        ["The Dawnbreaker"] = "Dawn",
    }

    local function GetShortDungeonName(mapID)
        local name = C_ChallengeMode.GetMapUIInfo(mapID)
        if not name then return "?" end
        if nameMap[name] then return nameMap[name] end
        if name:find(":") then return name:match(":%s*(.+)") end
        local clean = name:gsub("^The ", "")
        return clean:match("^(%S+)") or clean
    end

    PP:RegisterDatatext("Mythic Key", {
        OnEnable = function(slot, fontSize, fontType, valueColor)
            local text = slot.text or slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            slot.text = text
            text:SetPoint("CENTER")
            ApplySettings(text, fontSize, fontType)

            local function Update()
                local keystoneLevel = C_MythicPlus.GetOwnedKeystoneLevel()
                local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()

                if keystoneLevel and keystoneLevel > 0 and mapID then
                    local shortName = GetShortDungeonName(mapID)
                    local kr, kg, kb = GetKeyColor(keystoneLevel)
                    local hex = GetHexColor(valueColor)
                    text:SetFormattedText("|cff%02x%02x%02x+%d|r |c%s%s|r", kr*255, kg*255, kb*255, keystoneLevel, hex, shortName)
                else
                    local hex = GetHexColor(valueColor)
                    text:SetFormattedText("|c%sNo Key|r", hex)
                end
            end

            slot:RegisterEvent("PLAYER_ENTERING_WORLD")
            slot:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
            slot:RegisterEvent("BAG_UPDATE")
            slot:SetScript("OnEvent", Update)

            slot:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:ClearLines()
                GameTooltip:AddLine("Mythic+ Keystone", 1, 1, 1)
                GameTooltip:AddLine(" ")

                local keystoneLevel = C_MythicPlus.GetOwnedKeystoneLevel()
                local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()

                if keystoneLevel and keystoneLevel > 0 and mapID then
                    local name = C_ChallengeMode.GetMapUIInfo(mapID)
                    local r, g, b = GetKeyColor(keystoneLevel)
                    GameTooltip:AddDoubleLine("Current Key:", string.format("|cff%02x%02x%02x+%d %s|r", r*255, g*255, b*255, keystoneLevel, name or "Unknown"), 1, 1, 1)
                else
                    GameTooltip:AddLine("No keystone in bags", 0.7, 0.7, 0.7)
                end

                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff00ffffLeft-click|r to open Premade Groups", 0.5, 0.5, 0.5)
                GameTooltip:AddLine("|cff00ffffRight-Click|r for Panel Options", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)
            slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

            slot:EnableMouse(true)
            slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            slot:SetScript("OnClick", function(self, button)
                if button == "LeftButton" then
                    if not InCombatLockdown() then
                        PVEFrame_ToggleFrame("GroupFinderFrame", LFGListPVEStub)
                    end
                elseif button == "RightButton" then
                     ns.PP:OpenPanelMenu(self:GetParent())
                end
            end)

            Update()
        end
    })
end