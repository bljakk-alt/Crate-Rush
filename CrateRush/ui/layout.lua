-- CrateRush
-- ui/layout.lua - Visual layout constants only. Owns no runtime truth.

local layout = {}
CrateRush.layout = layout

layout.header = {
    width = 570,
    height = 56,
    buttonSize = 32,
    iconSize = 22,
    warModeIndicatorWidth = 0,
    warModeIndicatorHeight = 0,
    leftPadding = 12,
    titleLeftGap = 16,
    titleRightGap = 12,
    closeRightPadding = 10,
    settingsCloseGap = 6,
    shardSettingsGap = 10,
    shardBadgeWidth = 158,
    shardBadgeHeight = 26,
    topArtworkHeight = 42,
    topArtworkYOffset = -18,
}

layout.timerRows = {
    width = 329,
    rowHeight = 51,
    rowSpacing = 1,
    rowTopGap = 0,
    labelLeftPadding = 26,
    labelTopPadding = 6,
    timerTextRightPadding = 14,
    timerTextWidth = 56,
    barLeftPadding = 26,
    barRightPadding = 74,
    barHeight = 13,
    barBottomPadding = 13,
    activeStripWidth = 6,
    activeStripHeight = 51,
}

layout.cockpit = {
    width = 190,
    gapFromHeader = 0,
    gapFromTimers = 0,
    cardHeight = 56,
    timingCardHeight = 56,
    syncHeight = 35,
    sectionGap = 0,
    padding = 10,
    titleHeight = 22,
}

