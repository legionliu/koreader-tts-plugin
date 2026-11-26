--[[
    voice_dialogs.lua - voice selection dialogs shared by the settings page and the reading toolbar.

    local VD = VoiceDialogs.new(plugin)         -- plugin = the KoreaderTTS instance
    VD:openVoiceInput{ on_done = fn }           -- language group -> voice list (saves the default voice)
    VD:openLanguageVoiceMenu(on_done)           -- "Voice by book language" presets
    VD:pickLanguageVoice(lang, opts)            -- choose the preset voice for one language
--]]

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local ButtonDialog = require("ui/widget/buttondialog")
local VoiceList = require("src.service.voice_list")
local i18n = require("src.util.i18n")
local _ = i18n

local VoiceDialogs = {}
VoiceDialogs.__index = VoiceDialogs

function VoiceDialogs.new(plugin)
    return setmetatable({ plugin = plugin }, VoiceDialogs)
end

local function vlog(msg)
    local ok_lg, lg = pcall(require, "logger")
    if ok_lg and lg and lg.warn then lg.warn(msg) end
end

local function noop() end

--- Save as the default voice (settings) and apply it to the running engine
function VoiceDialogs:saveDefaultVoice(val)
    local p = self.plugin
    p.settings:set("voice", val)
    p.settings:save()
    if p.engine and p.engine.updateConfig then
        p.engine:updateConfig({ voice = val })
    end
    if p._current_voice ~= nil then p._current_voice = val end
end

--- Free-text voice name (also the fallback when no list is available)
-- opts: on_done, on_choose(name)
function VoiceDialogs:openTextInput(opts)
    opts = opts or {}
    local on_done = opts.on_done or noop
    local on_choose = opts.on_choose or function(v) self:saveDefaultVoice(v) end
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Select Voice"),
        input = opts.current or self.plugin.settings:get("voice") or "alloy",
        input_hint = "alloy",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "cancel",
                    callback = function()
                        UIManager:close(input_dialog)
                        UIManager:nextTick(on_done)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local val = input_dialog:getInputText()
                        if val and val ~= "" then on_choose(val) end
                        UIManager:close(input_dialog)
                        UIManager:nextTick(on_done)
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

-- opts (all optional): current = voice to tick, on_choose(name_or_nil), on_done(), clear_text
function VoiceDialogs:showVoiceMenu(voices, title, opts)
    opts = opts or {}
    local Menu = require("ui/widget/menu")
    local Screen = require("device").screen
    local current = opts.current or self.plugin.settings:get("voice") or ""
    local on_choose = opts.on_choose or function(v) self:saveDefaultVoice(v) end
    local on_done = opts.on_done or noop
    local items = {}
    if opts.clear_text then
        items[#items + 1] = { text = opts.clear_text, clear = true }
    end
    for _idx, v in ipairs(voices) do
        items[#items + 1] = {
            text = ((v.name == current) and "✓ " or "") .. VoiceList.shortName(v),
            mandatory = v.language,
            voice_name = v.name,
        }
    end
    local menu
    local chosen = false
    menu = Menu:new{
        title = title,
        item_table = items,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuChoice = function(_self, item)
            if item and (item.voice_name or item.clear) then
                chosen = true
                on_choose(item.voice_name) -- nil when "clear" was chosen
                UIManager:close(menu)
                UIManager:nextTick(on_done)
            end
        end,
        close_callback = function()
            if not chosen then UIManager:nextTick(on_done) end
        end,
    }
    UIManager:show(menu)
end

--- Language group chooser, then the voice list of that group
function VoiceDialogs:openGroupDialog(all_voices, source, opts)
    opts = opts or {}
    local group_dialog
    local buttons = {}
    local function openList(list, list_title)
        UIManager:close(group_dialog)
        UIManager:nextTick(function()
            local ok_m, err_m = pcall(self.showVoiceMenu, self, list, list_title, opts)
            if not ok_m then
                vlog("TTS: voice menu error: " .. tostring(err_m))
                self:openTextInput(opts)
            end
        end)
    end
    for _idx, g in ipairs(VoiceList.GROUPS) do
        local group = VoiceList.filter(all_voices, g.id)
        if #group > 0 then
            buttons[#buttons + 1] = {{
                text = string.format("%s (%d)", g.title, #group),
                callback = function() openList(group, g.title) end,
            }}
        end
    end
    buttons[#buttons + 1] = {{
        text = string.format(_("All languages (%d)"), #all_voices),
        callback = function() openList(all_voices, _("All languages")) end,
    }}
    buttons[#buttons + 1] = {{
        text = _("Type voice name manually..."),
        callback = function()
            UIManager:close(group_dialog)
            UIManager:nextTick(function() self:openTextInput(opts) end)
        end,
    }}
    buttons[#buttons + 1] = {{
        text = _("Cancel"),
        callback = function()
            UIManager:close(group_dialog)
            UIManager:nextTick(opts.on_done or noop)
        end,
    }}
    local src_note = (source == "server") and _("Voice list loaded from server")
        or (source == "cache") and _("Server unreachable - using cached voice list")
        or _("Server unreachable - using built-in voice list")
    group_dialog = ButtonDialog:new{
        title = string.format("%s\n%s: %s", src_note, _("Current voice"),
            tostring(opts.current or self.plugin.settings:get("voice") or "")),
        buttons = buttons,
    }
    UIManager:show(group_dialog)
end

--- Load the voice list (server -> cache -> built-in) behind a short "Loading..." message
function VoiceDialogs:withVoiceList(callback)
    local p = self.plugin
    local loading = InfoMessage:new{ text = _("Loading voice list..."), timeout = 15 }
    UIManager:show(loading)
    UIManager:forceRePaint()
    UIManager:nextTick(function()
        local ok_l, voices, source, err = pcall(VoiceList.load,
            p.settings:get("server_url"), p.settings:get("api_key"), p.cache_dir, 10)
        UIManager:close(loading)
        if not ok_l or not voices or #voices == 0 then
            vlog("TTS: voice list load failed: " .. tostring(voices))
            return callback(nil)
        end
        if err then vlog("TTS: voice list fetch error: " .. tostring(err)) end
        callback(voices, source, err)
    end)
end

--- Pick any voice: language group -> list. opts: on_done, on_choose(name), current
function VoiceDialogs:openVoiceInput(opts)
    opts = opts or {}
    self:withVoiceList(function(voices, source)
        if not voices then return self:openTextInput(opts) end
        self:openGroupDialog(voices, source, opts)
    end)
end

-- ===== Voice per book language =====

function VoiceDialogs:setLanguageVoice(code, name)
    local s = self.plugin.settings
    local presets = {}
    for k, v in pairs(s:get("voice_by_language") or {}) do presets[k] = v end
    presets[code] = name -- nil removes the preset
    s:set("voice_by_language", presets)
    s:save()
end

--- Choose the preset voice for one language. opts: on_done(), on_chosen(name_or_nil)
function VoiceDialogs:pickLanguageVoice(lang, opts)
    opts = opts or {}
    local on_done = opts.on_done or noop
    self:withVoiceList(function(voices)
        local list = voices and VoiceList.filterByLang(voices, lang.code) or {}
        if #list == 0 then
            UIManager:show(InfoMessage:new{
                text = string.format(_("No %s voices found on the server."), lang.title),
                timeout = 4,
            })
            return UIManager:nextTick(on_done)
        end
        local presets = self.plugin.settings:get("voice_by_language") or {}
        local ok_m, err_m = pcall(self.showVoiceMenu, self, list, lang.title, {
            current = presets[lang.code],
            clear_text = _("(none - use the default voice)"),
            on_choose = function(name)
                self:setLanguageVoice(lang.code, name)
                if opts.on_chosen then opts.on_chosen(name) end
            end,
            on_done = on_done,
        })
        if not ok_m then
            vlog("TTS: language voice menu error: " .. tostring(err_m))
            on_done()
        end
    end)
end

--- List of languages with their preset voices + the auto-select switch
function VoiceDialogs:openLanguageVoiceMenu(on_done)
    on_done = on_done or noop
    local Menu = require("ui/widget/menu")
    local Screen = require("device").screen
    local s = self.plugin.settings
    local presets = s:get("voice_by_language") or {}
    local auto_on = s:get("auto_voice") ~= false
    local items = {
        {
            text = (auto_on and "[ON]  " or "[OFF]  ") .. _("Auto-select voice by book language"),
            toggle = true,
        },
    }
    for _idx, lang in ipairs(VoiceList.LANGUAGES) do
        local p = presets[lang.code]
        items[#items + 1] = {
            text = lang.title,
            mandatory = p and VoiceList.shortName({ name = p }) or "-",
            lang = lang,
        }
    end
    local menu
    local done = false
    local function reopen() self:openLanguageVoiceMenu(on_done) end
    menu = Menu:new{
        title = _("Voice by book language"),
        item_table = items,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuChoice = function(_self, item)
            if item and item.toggle then
                done = true
                s:set("auto_voice", not auto_on)
                s:save()
                UIManager:close(menu)
                UIManager:nextTick(reopen)
            elseif item and item.lang then
                done = true
                UIManager:close(menu)
                UIManager:nextTick(function()
                    self:pickLanguageVoice(item.lang, { on_done = reopen })
                end)
            end
        end,
        close_callback = function()
            if not done then UIManager:nextTick(on_done) end
        end,
    }
    UIManager:show(menu)
end

--- Plain list of languages; on_choose(lang) is called with the chosen { code, title }
function VoiceDialogs:chooseLanguage(on_choose, on_done, title)
    on_done = on_done or noop
    local Menu = require("ui/widget/menu")
    local Screen = require("device").screen
    local presets = self.plugin.settings:get("voice_by_language") or {}
    local items = {}
    for _idx, lang in ipairs(VoiceList.LANGUAGES) do
        local pv = presets[lang.code]
        items[#items + 1] = {
            text = ((self.plugin._book_lang == lang.code) and "✓ " or "") .. lang.title,
            mandatory = pv and VoiceList.shortName({ name = pv }) or "-",
            lang = lang,
        }
    end
    local menu
    local chosen = false
    menu = Menu:new{
        title = title or _("Book language"),
        item_table = items,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuChoice = function(_self, item)
            if item and item.lang then
                chosen = true
                UIManager:close(menu)
                UIManager:nextTick(function() on_choose(item.lang) end)
            end
        end,
        close_callback = function()
            if not chosen then UIManager:nextTick(on_done) end
        end,
    }
    UIManager:show(menu)
end

return VoiceDialogs
