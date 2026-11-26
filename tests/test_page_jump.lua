--[[
    tests/test_page_jump.lua - "previous page" / "next page" buttons must go to the right page

    Regression: the page turn was always a relative "+1", so "previous page" moved the screen
    FORWARD (and the reading position ended up out of sync with what was shown).
--]]
package.path = "./?.lua;./tests/?.lua;" .. package.path
local MockKOReader = require("mock_koreader")
MockKOReader.installGlobals()

local total, passed = 0, 0
local function run_test(name, fn)
    total = total + 1
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print(string.format("[TEST] %-62s ... PASS", name))
    else print(string.format("[TEST] %-62s ... FAIL", name)); print("       Error: " .. tostring(err)) end
end

local function reading_at(page)
    local KoreaderTTS = require("main")
    local pages = {}
    for i = 1, 8 do pages[i] = "Page " .. i .. " sentence one. Page " .. i .. " sentence two." end
    local doc = MockKOReader.createMockMultiPageDocument(pages, 8, "md5_jump")
    local ui = MockKOReader.createMockUI(doc)
    ui:gotoPage(page)
    local plugin = KoreaderTTS:new{ ui = ui, view = ui.view }
    plugin:init()
    plugin:onStartTTS()
    return plugin, doc
end

run_test("previous page goes back one page on screen and in the queue", function()
    local plugin, doc = reading_at(4)
    plugin.ui_player:onPrevPage()
    assert(doc:getCurrentPage() == 3, "screen page " .. tostring(doc:getCurrentPage()))
    assert(plugin.playback_queue.current_page == 3)
end)

run_test("previous page twice, then next page", function()
    local plugin, doc = reading_at(4)
    plugin.ui_player:onPrevPage()
    plugin.ui_player:onPrevPage()
    assert(doc:getCurrentPage() == 2)
    plugin.ui_player:onNextPage()
    assert(doc:getCurrentPage() == 3)
    assert(plugin.playback_queue.current_page == 3)
end)

run_test("next page goes forward exactly one page", function()
    local plugin, doc = reading_at(4)
    plugin.ui_player:onNextPage()
    assert(doc:getCurrentPage() == 5)
    assert(plugin.playback_queue.current_page == 5)
end)

run_test("previous page on the first page does nothing", function()
    local plugin, doc = reading_at(1)
    plugin.ui_player:onPrevPage()
    assert(doc:getCurrentPage() == 1)
end)

print(string.format("\n%d/%d tests passed", passed, total))
os.exit(passed == total and 0 or 1)
