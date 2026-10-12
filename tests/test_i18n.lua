--[[
    tests/test_i18n.lua - Unit tests for i18n localization coordinator
    Tests:
      - src.util.i18n
      - src.util.l10n.vi
--]]

package.path = "./?.lua;./tests/?.lua;" .. package.path

local MockKOReader = require("mock_koreader")
MockKOReader.installGlobals()

local total_tests = 0
local passed_tests = 0

local function run_test(name, fn)
    total_tests = total_tests + 1
    local ok, err = pcall(fn)
    if ok then
        passed_tests = passed_tests + 1
        print(string.format("[TEST] %-52s ... PASS", name))
    else
        print(string.format("[TEST] %-52s ... FAIL", name))
        print("       Error: " .. tostring(err))
    end
end

print("==========================================================")
print("  UNIT TEST SUITE: LOCALIZATION & I18N (src/util/)")
print("==========================================================")

local i18n = require("src.util.i18n")
local SettingsManager = require("src.service.settings_manager")

run_test("i18n: default English returns base string", function()
    i18n.setLanguage("en")
    assert(i18n.getLanguage() == "en")
    assert(i18n("▶ Read from here") == "▶ Read from here")
    assert(i18n("Speed: %.1fx") == "Speed: %.1fx")
    assert(i18n("Unknown string xyz") == "Unknown string xyz")
end)

run_test("i18n: Vietnamese catalog translation", function()
    i18n.setLanguage("vi")
    assert(i18n.getLanguage() == "vi")
    assert(i18n("▶ Read from here") == "▶ Đọc từ đây")
    assert(i18n("⚙ Plugin settings") == "⚙ Cài đặt tiện ích")
    assert(i18n("Sleep timer: Off") == "Hẹn giờ: Tắt")
    assert(i18n("Cancel") == "Hủy")
    assert(i18n("Save") == "Lưu")
    assert(i18n("Server, Voice & Speed Settings") == "Cài đặt Máy chủ, Giọng đọc & Tốc độ")
end)

run_test("i18n: unknown string in Vietnamese falls back to original", function()
    i18n.setLanguage("vi")
    local untranslated = "A brand new untranslated feature"
    assert(i18n(untranslated) == untranslated)
end)

run_test("i18n: explicit language override", function()
    i18n.setLanguage("en")
    assert(i18n.getLanguage() == "en")
    assert(i18n("▶ Read from here") == "▶ Read from here")

    i18n.setLanguage("vi")
    assert(i18n.getLanguage() == "vi")
    assert(i18n("▶ Read from here") == "▶ Đọc từ đây")

    i18n.setLanguage(nil)
end)

run_test("i18n: auto language resolution from G_reader_settings", function()
    i18n.setLanguage(nil)

    _G.G_reader_settings = {
        readSetting = function(self, k)
            if k == "language" then return "vi_VN" end
            return nil
        end
    }
    assert(i18n.getLanguage() == "vi")
    assert(i18n("▶ Read from here") == "▶ Đọc từ đây")

    _G.G_reader_settings = {
        readSetting = function(self, k)
            if k == "language" then return "en_US" end
            return nil
        end
    }
    assert(i18n.getLanguage() == "en")
    assert(i18n("▶ Read from here") == "▶ Read from here")
    _G.G_reader_settings = nil
end)

run_test("i18n: catalog parity check between EN and VI", function()
    local en = require("src.util.l10n.en")
    local vi = require("src.util.l10n.vi")

    local missing_in_vi = 0
    for k, _ in pairs(en) do
        if not vi[k] then
            print("       Missing in VI: " .. tostring(k))
            missing_in_vi = missing_in_vi + 1
        end
    end
    assert(missing_in_vi == 0, string.format("All EN keys must have VI translation (found %d missing)", missing_in_vi))

    local missing_in_en = 0
    for k, _ in pairs(vi) do
        if not en[k] then
            print("       Missing in EN: " .. tostring(k))
            missing_in_en = missing_in_en + 1
        end
    end
    assert(missing_in_en == 0, string.format("All VI keys must have EN catalog entry (found %d missing)", missing_in_en))
end)

print("==========================================================")
print(string.format("  ALL %d/%d I18N TESTS PASSED!", passed_tests, total_tests))
print("==========================================================")

if passed_tests < total_tests then os.exit(1) end
