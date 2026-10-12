--[[
    src/util/i18n.lua - Internationalization (i18n) coordinator for KOReader TTS Plugin
    Base language in code is always English.
    Translates to user's preferred language (auto-detected from KOReader or explicit setting).
--]]

local i18n = {}

local ok_gettext, GetText = pcall(require, "gettext")

-- Table of translation catalogs: { [lang_code] = { [msgid] = msgstr } }
local catalogs = {}

-- Load English canonical catalog
local ok_en, en_catalog = pcall(require, "src.util.l10n.en")
if ok_en and type(en_catalog) == "table" then
    catalogs["en"] = en_catalog
end

-- Load Vietnamese catalog
local ok_vi, vi_catalog = pcall(require, "src.util.l10n.vi")
if ok_vi and type(vi_catalog) == "table" then
    catalogs["vi"] = vi_catalog
end

local settings_ref = nil
local explicit_lang = nil

--- Initialize with settings manager instance
function i18n.init(settings)
    settings_ref = settings
end

--- Manually override active language ("auto", "en", "vi")
function i18n.setLanguage(lang)
    explicit_lang = lang
end

--- Determine effective language code ("en", "vi", ...)
function i18n.getLanguage()
    -- 1. Explicit override (for tests or manual switch)
    if explicit_lang and explicit_lang ~= "auto" and explicit_lang ~= "" then
        return explicit_lang
    end

    -- 2. KOReader active language
    if ok_gettext and type(GetText) == "table" and GetText.current_lang then
        local k_lang = tostring(GetText.current_lang):lower()
        if k_lang:find("^vi") then
            return "vi"
        elseif k_lang:find("^en") or k_lang == "c" then
            return "en"
        end
    end

    -- 3. Global KOReader settings table
    if G_reader_settings and type(G_reader_settings.readSetting) == "function" then
        local k_lang = tostring(G_reader_settings:readSetting("language") or ""):lower()
        if k_lang:find("^vi") then
            return "vi"
        end
    end

    -- Default to English base language
    return "en"
end

--- Translate a message ID into the active language
function i18n.translate(msgid)
    if not msgid or msgid == "" then
        return msgid
    end

    local lang = i18n.getLanguage()
    if lang ~= "en" then
        local cat = catalogs[lang]
        if cat and cat[msgid] then
            return cat[msgid]
        end
    end

    -- Optional fallback to KOReader's core gettext if loaded
    if ok_gettext and type(GetText) == "table" and type(GetText.translation) == "table" then
        local k_trans = GetText(msgid)
        if k_trans and k_trans ~= msgid then
            return k_trans
        end
    end

    return msgid
end

-- Allow calling module directly as `_("text")`
local _M = setmetatable(i18n, {
    __call = function(_, msgid)
        return i18n.translate(msgid)
    end
})

return _M
