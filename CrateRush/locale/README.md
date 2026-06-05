# CrateRush Locale System

## Current Language Support

- **English (enUS)** - Complete (Default)
- **German (deDE)** - Partial
- **Spanish (esES)** - Partial
- **French (frFR)** - Partial
- **Russian (ruRU)** - Partial

## File Structure

```
locale/
├── locale.lua   # Initialization via AceLocale-3.0
├── enUS.lua     # English (default/fallback)
├── deDE.lua     # German
├── esES.lua     # Spanish
├── frFR.lua     # French
├── ruRU.lua     # Russian
└── README.md
```

## How It Works

1. `locale.lua` initializes AceLocale-3.0
2. AceLocale automatically selects the correct language based on the WoW client locale
3. Missing translations fall back to English (enUS)

## Usage in Code

```lua
local L = CrateRush.L
someFrame:SetText(L["ADDON_TITLE"])
```

## Translation Guidelines

- Keep format placeholders: `%s`, `%d`
- Preserve WoW color codes: `|cff...`
- Do not change keys like `L["KEY_NAME"]`
