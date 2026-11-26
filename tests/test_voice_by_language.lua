--[[
    tests/test_voice_by_language.lua - language detection + automatic voice per book language
--]]
package.path = "./?.lua;./tests/?.lua;" .. package.path
local MockKOReader = require("mock_koreader")
MockKOReader.installGlobals()

local total, passed = 0, 0
local function run_test(name, fn)
    total = total + 1
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print(string.format("[TEST] %-60s ... PASS", name))
    else print(string.format("[TEST] %-60s ... FAIL", name)); print("       Error: " .. tostring(err)) end
end

local LD = require("src.service.language_detect")
local VoiceList = require("src.service.voice_list")

local ZH = "他走进房间，看见桌上放着一封信。“你来了？”母亲问道。他没有回答，只是点了点头。"
local EN = "The quick brown fox jumps over the lazy dog. It was a long road, but he kept walking until the sun set."
local RU = "Он вошёл в комнату и увидел на столе письмо. «Ты пришёл?» — спросила мать."

run_test("language_detect: script decides for Chinese / Russian / English", function()
    assert(LD.resolve(ZH, "en", nil) == "zh", "metadata says en but text is Chinese")
    assert(LD.resolve(RU, nil, nil) == "ru")
    assert(LD.resolve(EN, "en-US", nil) == "en")
end)

run_test("language_detect: Latin text uses metadata to tell languages apart", function()
    assert(LD.resolve("Il entra dans la pièce et vit une lettre sur la table.", "fra", nil) == "fr")
    assert(LD.resolve(EN, "zh-CN", nil) == "en", "non-Latin metadata must not override Latin text")
end)

run_test("language_detect: no text falls back to metadata, then nil", function()
    assert(LD.resolve("", "zh-Hans", nil) == "zh")
    assert(LD.resolve("", "und", nil) == nil)
end)

run_test("voice_list: filterByLang matches all regions", function()
    local zh = VoiceList.filterByLang(VoiceList.builtin(), "zh")
    assert(#zh >= 10)
    for _, v in ipairs(zh) do assert(v.name:find("^zh%-")) end
end)

local function plugin_for(pages, props, presets, auto)
    local KoreaderTTS = require("main")
    local doc = MockKOReader.createMockMultiPageDocument(pages, #pages, "md5_vbl_test")
    local ui = MockKOReader.createMockUI(doc)
    ui.doc_props = props
    local plugin = KoreaderTTS:new{ ui = ui, view = ui.view }
    plugin:init()
    plugin.settings:set("voice_by_language", presets)
    plugin.settings:set("auto_voice", auto ~= false)
    plugin.engine = { calls = {}, updateConfig = function(self, c) self.calls[#self.calls + 1] = c end }
    return plugin
end

local PRESETS = { zh = "zh-CN-XiaoxiaoNeural", en = "en-US-AvaNeural" }

run_test("onStartTTS: Chinese book switches to the Chinese voice", function()
    local p = plugin_for({ ZH, ZH }, { language = "en" }, PRESETS)
    p:onStartTTS()
    assert(p.engine.calls[#p.engine.calls].voice == "zh-CN-XiaoxiaoNeural")
end)

run_test("onStartTTS: English book switches to the English voice", function()
    local p = plugin_for({ EN, EN }, { language = "en-US" }, PRESETS)
    p:onStartTTS()
    assert(p.engine.calls[#p.engine.calls].voice == "en-US-AvaNeural")
end)

run_test("onStartTTS: language without a preset keeps the default voice", function()
    local p = plugin_for({ RU, RU }, { language = "ru" }, PRESETS)
    p:onStartTTS()
    assert(#p.engine.calls == 0)
end)

run_test("onStartTTS: auto voice OFF changes nothing", function()
    local p = plugin_for({ ZH, ZH }, { language = "zh" }, PRESETS, false)
    p:onStartTTS()
    assert(#p.engine.calls == 0)
end)

run_test("onStartTTS: default voice stays untouched in settings", function()
    local p = plugin_for({ ZH, ZH }, { language = "zh" }, PRESETS)
    local before = p.settings:get("voice")
    p:onStartTTS()
    assert(p.settings:get("voice") == before)
end)

local function shown_plugin()
    local KoreaderTTS = require("main")
    local doc = MockKOReader.createMockMultiPageDocument({ "Hello world. This is page one of the book.", "Page two text." }, 320, "md5_hdr")
    local ui = MockKOReader.createMockUI(doc)
    local plugin = KoreaderTTS:new{ ui = ui, view = ui.view }
    plugin:init()
    plugin.ui_player:show()
    return plugin
end

run_test("player: starts as the small bubble and expands on demand", function()
    local p = shown_plugin()
    assert(p.ui_player.is_mini == true and p.ui_player.mini_bubble ~= nil)
    assert(p.ui_player.control_bar == nil)
    p.ui_player:toggleMode()
    assert(p.ui_player.control_bar ~= nil and p.ui_player.mini_bubble == nil)
end)

run_test("player header: shows page and sentence progress as 'p56, 3/6'", function()
    local p = shown_plugin()
    p.ui_player:toggleMode()
    p.ui_player:onChunkChange(nil, 56, 3, 6)
    assert(p.ui_player.title_widget.text == "p56, 3/6", p.ui_player.title_widget.text)
end)

run_test("player header: buffer dots are shown (one per preloaded sentence)", function()
    local p = shown_plugin()
    p.settings:set("preload_count", 3)
    p.ui_player:toggleMode()
    p.ui_player:_updateBufferStatus()
    local t = p.ui_player.buffer_status_widget.text
    assert(t:match("^[●○]+$"), t)
    assert(#t == 3 * 3, t) -- three dots, 3 bytes each
end)

run_test("mini bubble: label keeps the sentence progress and speed", function()
    local p = shown_plugin()
    p.ui_player:onChunkChange(nil, 56, 3, 6)
    assert(p.ui_player.mini_label_btn.text == "3/6 · 1.0x", p.ui_player.mini_label_btn.text)
end)

run_test("player header: voice button shows the short voice name and follows changes", function()
    local p = shown_plugin()
    p.ui_player:toggleMode()
    p:_setReadingVoice("zh-CN-XiaoxiaoNeural")
    assert(p.ui_player.voice_btn.text == "Voice: Xiaoxiao", p.ui_player.voice_btn.text)
    p:_setReadingVoice("alloy")
    assert(p.ui_player.voice_btn.text == "Voice: alloy", p.ui_player.voice_btn.text)
end)

run_test("opacity settings: clamped to 30..100 and defaults apply", function()
    local p = shown_plugin()
    assert(p.settings:get("player_opacity_full") == 85 and p.settings:get("player_opacity_mini") == 90)
    p.settings:set("player_opacity_full", 5)
    assert(p.settings:get("player_opacity_full") == 30)
    p.settings:set("player_opacity_mini", 250)
    assert(p.settings:get("player_opacity_mini") == 100)
end)

run_test("opacity 100%: card is used directly (no translucent wrapper)", function()
    local p = shown_plugin()
    p.settings:set("player_opacity_full", 100)
    p.ui_player:toggleMode()
    assert(p.ui_player.full_alpha == nil)
end)

run_test("tap positions inside a translucent container are offset by where it was painted", function()
    local p = shown_plugin()
    local player = p.ui_player
    local widget = { dimen = { x = 10, y = 20, w = 50, h = 30 } }
    -- no wrapper: coordinates are screen coordinates
    assert(player:_isTapOnWidget({ x = 15, y = 25 }, widget, 0) == true)
    assert(player:_isTapOnWidget({ x = 115, y = 525 }, widget, 0) == false)
    -- wrapper painted at (100, 500): the widget's real screen position is (110, 520)
    player.full_alpha = { origin_x = 100, origin_y = 500 }
    assert(player:_isTapOnWidget({ x = 115, y = 525 }, widget, 0) == true)
    assert(player:_isTapOnWidget({ x = 15, y = 25 }, widget, 0) == false)
end)

run_test("reading voice dialog: opens with detected language and voice", function()
    local p = shown_plugin()
    p._book_lang, p._book_lang_source = "zh", "text"
    p:showReadingVoiceDialog()
end)

run_test("book language override sticks and selects that language's preset", function()
    local p = plugin_for({ EN, EN }, { language = "en" }, PRESETS)
    p._lang_override = "zh"
    p:onStartTTS()
    assert(p._book_lang == "zh" and p._book_lang_source == "manual")
    assert(p.engine.calls[#p.engine.calls].voice == "zh-CN-XiaoxiaoNeural")
end)

run_test("language is tracked even when no presets are set", function()
    local p = plugin_for({ ZH, ZH }, { language = "en" }, {})
    p:onStartTTS()
    assert(p._book_lang == "zh" and p._book_lang_source == "text")
    assert(#p.engine.calls == 0)
end)

print(string.format("\n%d/%d tests passed", passed, total))
os.exit(passed == total and 0 or 1)
