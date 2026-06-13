-- CrateRush
-- events.lua - Thin WoW event handlers. Delegate only; no logic, no rendering.

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent(CrateRush.EVT.PLAYER_ENTERING_WORLD)
eventFrame:RegisterEvent(CrateRush.EVT.ZONE_CHANGED_NEW_AREA)
eventFrame:RegisterEvent(CrateRush.EVT.VIGNETTES_UPDATED)
eventFrame:RegisterEvent(CrateRush.EVT.GROUP_ROSTER_UPDATE)
eventFrame:RegisterEvent(CrateRush.EVT.PLAYER_FLAGS_CHANGED)
eventFrame:RegisterEvent(CrateRush.EVT.NPC_ANNOUNCEMENT)
eventFrame:RegisterEvent(CrateRush.EVT.NAME_PLATE_UNIT_ADDED)

local function dispatchEnemyPresence(event, ...)
    if CrateRush.enemyPresence and CrateRush.enemyPresence.onEvent then
        CrateRush.enemyPresence:onEvent(event, ...)
    end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == CrateRush.EVT.PLAYER_ENTERING_WORLD then
        if CrateRush.playerContext and CrateRush.playerContext.onPlayerEnteringWorld then
            CrateRush.playerContext:onPlayerEnteringWorld(...)
        end
        if CrateRush.comms and CrateRush.comms.onPlayerEnteringWorld then
            CrateRush.comms:onPlayerEnteringWorld(...)
        end
        CrateRush.crateHandler:onPlayerEnteringWorld(...)
        dispatchEnemyPresence(event, ...)
    elseif event == CrateRush.EVT.ZONE_CHANGED_NEW_AREA then
        if CrateRush.playerContext and CrateRush.playerContext.onZoneChanged then
            CrateRush.playerContext:onZoneChanged(...)
        end
        dispatchEnemyPresence(event, ...)
        CrateRush.crateHandler:onZoneChanged()
    elseif event == CrateRush.EVT.VIGNETTES_UPDATED then
        CrateRush.crateHandler:onVignettesUpdated()
    elseif event == CrateRush.EVT.GROUP_ROSTER_UPDATE then
        if CrateRush.comms and CrateRush.comms.onGroupRosterUpdate then
            CrateRush.comms:onGroupRosterUpdate(...)
        end
        CrateRush.crateHandler:onGroupRosterUpdate()
        dispatchEnemyPresence(event, ...)
    elseif event == CrateRush.EVT.PLAYER_FLAGS_CHANGED then
        if CrateRush.playerContext and CrateRush.playerContext.onPlayerFlagsChanged then
            CrateRush.playerContext:onPlayerFlagsChanged(...)
        end
        if CrateRush.comms and CrateRush.comms.refreshProtocolContext then
            CrateRush.comms:refreshProtocolContext("player_flags_changed")
        end
        dispatchEnemyPresence(event, ...)
    elseif event == CrateRush.EVT.NPC_ANNOUNCEMENT then
        CrateRush.crateHandler:onNpcAnnouncement(...)
    elseif event == CrateRush.EVT.NAME_PLATE_UNIT_ADDED then
        dispatchEnemyPresence(event, ...)
    end
end)