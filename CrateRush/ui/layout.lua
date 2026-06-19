-- CrateRush
-- ui/layout.lua - Visual layout constants only. Owns no runtime truth.

local layout = {}
CrateRush.layout = layout

layout.header = {
    width = 463,
    height = 45,
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
    shardBadgeWidth = 143,
    shardBadgeHeight = 26,
    topArtworkHeight = 42,
    topArtworkYOffset = -18,
}

layout.timerRows = {
    width = 329,
    rowHeight = 39,
    rowSpacing = 1,
    rowTopGap = 0,
    labelLeftPadding = 19,
    labelTopPadding = 3,
    labelYOffset = -1,
    unseenYOffset = -2,
    topRowHeight = 17,
    timerTextRightPadding = 8,
    timerTextWidth = 56,
    timerFontSize = 14,
    unseenTextWidth = 56,
    unseenTimeGap = 1,
    labelUnseenGap = 5,
    barLeftPadding = 19,
    barRightPadding = 5,
    barHeight = 8,
    barBottomPadding = 8,
    activeStripWidth = 6,
    activeStripHeight = 39,
}

layout.cockpit = {
    width = 143,
    gapFromHeader = 0,
    gapFromTimers = 0,
    cardHeight = 42,
    timingCardHeight = 42,
    syncHeight = 31,
    sectionGap = 0,
    padding = 10,
    titleHeight = 22,
    contentLabelFontSize = 9,
    contentValueFontSize = 12,
}

