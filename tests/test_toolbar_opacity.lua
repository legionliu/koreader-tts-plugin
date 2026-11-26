--[[
    tests/test_toolbar_opacity.lua - translucent toolbar (KOReader's AlphaContainer)

    A stub AlphaContainer is registered before the plugin loads, so the translucent code path runs.
--]]
package.path = "./?.lua;./tests/?.lua;" .. package.path

package.preload["ui/widget/container/alphacontainer"] = function()
    local A = {}
    A.__index = A
    function A:extend(t) t = t or {}; t.__index = t; return setmetatable(t, { __index = self }) end
    function A:new(t) return setmetatable(t, self) end
    function A:paintTo(bb, x, y) self.painted_at = { x, y } end
    return A
end

local MockKOReader = require("mock_koreader")
MockKOReader.installGlobals()

local total, passed = 0, 0
local function run_test(name, fn)
    total = total + 1
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print(string.format("[TEST] %-62s ... PASS", name))
    else print(string.format("[TEST] %-62s ... FAIL", name)); print("       Error: " .. tostring(err)) end
end

local function new_player()
    local KoreaderTTS = require("main")
    local doc = MockKOReader.createMockMultiPageDocument({ "Hello world. This is page one." }, 10, "md5_alpha")
    local ui = MockKOReader.createMockUI(doc)
    local plugin = KoreaderTTS:new{ ui = ui, view = ui.view }
    plugin:init()
    return plugin, plugin.ui_player
end

run_test("small bubble and full toolbar use the configured opacity", function()
    local plugin, p = new_player()
    p:show()
    assert(p.mini_alpha and math.abs(p.mini_alpha.alpha - 0.90) < 1e-9)
    p:toggleMode()
    assert(p.full_alpha and math.abs(p.full_alpha.alpha - 0.85) < 1e-9)
    assert(p.control_bar[1] == p.full_alpha)
end)

run_test("taps are mapped through the translucent container's origin", function()
    local plugin, p = new_player()
    p:show()
    p:toggleMode()
    p.full_alpha:paintTo(nil, 0, 700)
    p.play_pause_btn.dimen = { x = 400, y = 100, w = 120, h = 60 }
    assert(p:_isTapOnWidget({ x = 450, y = 810 }, p.play_pause_btn, 0) == true)
    assert(p:_isTapOnWidget({ x = 450, y = 110 }, p.play_pause_btn, 0) == false)
end)

run_test("100% opacity uses the plain card, and refreshBars applies a change", function()
    local plugin, p = new_player()
    p:show()
    p:toggleMode()
    assert(p.full_alpha ~= nil)
    plugin.settings:set("player_opacity_full", 100)
    p:refreshBars()
    assert(p.full_alpha == nil and p.control_bar ~= nil)
end)

run_test("refreshBars keeps the small bubble when it is the active toolbar", function()
    local plugin, p = new_player()
    p:show()
    plugin.settings:set("player_opacity_mini", 60)
    p:refreshBars()
    assert(p.is_mini == true and p.mini_bubble ~= nil)
    assert(math.abs(p.mini_alpha.alpha - 0.60) < 1e-9)
end)

run_test("buttons keep their fixed width when their label changes", function()
    local plugin, p = new_player()
    p:show()
    p:toggleMode()
    -- behave like KOReader's Button: setText() without a width resets it to the natural width
    local function koreader_like(btn)
        btn.setText = function(self, text, width) self.text = text; self.width = width end
    end
    koreader_like(p.play_pause_btn)
    koreader_like(p.speed_btn)
    local w_play, w_speed = p.play_pause_btn.width, p.speed_btn.width
    assert(w_play and w_speed, "toolbar buttons must have a fixed width")
    p:_updatePlayPauseIcon()
    p:onCycleSpeed()
    assert(p.play_pause_btn.width == w_play, "play/pause shrank")
    assert(p.speed_btn.width == w_speed, "speed button shrank")
end)

run_test("translucent toolbar repaints everything under it (no alpha build-up)", function()
    local plugin, p = new_player()
    local UIManager = require("ui/uimanager")
    p:show()
    p:toggleMode()
    p.card_container.getSize = function() return { w = 800, h = 300 } end
    UIManager._dirty_calls = {}
    p:_setBarDirty()
    assert(UIManager._dirty_calls[#UIManager._dirty_calls].widget == "all")
    -- opaque toolbar: only the toolbar itself
    plugin.settings:set("player_opacity_full", 100)
    p:refreshBars()
    p.card_container.getSize = function() return { w = 800, h = 300 } end
    UIManager._dirty_calls = {}
    p:_setBarDirty()
    assert(UIManager._dirty_calls[#UIManager._dirty_calls].widget == p.control_bar)
end)

run_test("highlight clipping uses the real screen position of the toolbar top", function()
    local plugin, p = new_player()
    p:show()
    p:toggleMode()
    p.card_container.getSize = function() return { w = 800, h = 300 } end
    -- inside a translucent container dimen.y is relative to a private buffer (0), not the screen
    p.card_container.dimen = { x = 0, y = 0, w = 800, h = 300 }
    assert(p:_barTop() == _G.Screen:getHeight() - 300, tostring(p:_barTop()))
end)

print(string.format("\n%d/%d tests passed", passed, total))
os.exit(passed == total and 0 or 1)
