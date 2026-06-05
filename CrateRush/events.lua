-- CrateRush
-- events.lua — Thin WoW event handlers. Delegate only — no logic, no rendering.

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent(CrateRush.EVT.PLAYER_ENTERING_WORLD)
eventFrame:RegisterEvent(CrateRush.EVT.ZONE_CHANGED_NEW_AREA)
eventFrame:RegisterEvent(CrateRush.EVT.VIGNETTES_UPDATED)
eventFrame:RegisterEvent(CrateRush.EVT.GROUP_ROSTER_UPDATE)
eventFrame:RegisterEvent(CrateRush.EVT.CHAT_MSG_MONSTER_SAY)

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == CrateRush.EVT.PLAYER_ENTERING_WORLD then
        CrateRush.crateHandler:onPlayerEnteringWorld(...)
    elseif event == CrateRush.EVT.ZONE_CHANGED_NEW_AREA then
        CrateRush.crateHandler:onZoneChanged()
    elseif event == CrateRush.EVT.VIGNETTES_UPDATED then
        CrateRush.crateHandler:onVignettesUpdated()
    elseif event == CrateRush.EVT.GROUP_ROSTER_UPDATE then
        CrateRush.crateHandler:onGroupRosterUpdate()
    elseif event == CrateRush.EVT.CHAT_MSG_MONSTER_SAY then
        CrateRush.crateHandler:onMonsterSay(...)
    end
end)
