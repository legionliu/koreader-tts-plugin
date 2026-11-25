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

print(string.format("\n%d/%d tests passed", passed, total))
os.exit(passed == total and 0 or 1)
