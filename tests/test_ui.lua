--[[
    tests/test_ui.lua - Unit tests for Presentation layer
    Tests:
      - src.ui.canvas_highlight
      - src.ui.player_widget
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
print("  UNIT TEST SUITE: PRESENTATION LAYER (src/ui/)")
print("==========================================================")

local CanvasHighlight = require("src.ui.canvas_highlight")
local PlayerWidget = require("src.ui.player_widget")
local SettingsManager = require("src.service.settings_manager")

-- 1. CanvasHighlight Tests
run_test("CanvasHighlight: Gray mode sets partial refresh dirty rects", function()
    local highlighter = CanvasHighlight:new()
    local dirty_calls = {}
    local UIManager = require("ui/uimanager")
    local old_setDirty = UIManager.setDirty
    UIManager.setDirty = function(self, view, refresh_type, rects)
        table.insert(dirty_calls, { refresh_type = refresh_type, count = #rects })
    end

    local mock_view = {
        clearHighlight = function(self) end,
        setHighlight = function(self, boxes, color) end,
    }
    local bboxes = {
        { x = 10, y = 100, w = 300, h = 25 },
        { x = 10, y = 130, w = 250, h = 25 },
    }

    highlighter:highlightSentence(mock_view, bboxes, "gray")
    assert(highlighter.current_highlight ~= nil)
    assert(#highlighter.current_highlight == 2)
    assert(#dirty_calls > 0)
    assert(dirty_calls[#dirty_calls].refresh_type == "ui", "Must use UI dirty refresh region")

    UIManager.setDirty = old_setDirty
end)

run_test("CanvasHighlight: Underline mode creates 2px bottom strip", function()
    local highlighter = CanvasHighlight:new()
    local applied_boxes = nil
    local mock_view = {
        clearHighlight = function(self) end,
        setHighlight = function(self, boxes, color)
            applied_boxes = boxes
        end,
    }
    local bboxes = { { x = 20, y = 50, w = 150, h = 30 } }
    highlighter:highlightSentence(mock_view, bboxes, "underline")

    assert(applied_boxes ~= nil)
    assert(applied_boxes[1].h == 2, "Underline height must be 2px")
    assert(applied_boxes[1].y == (50 + 30 - 2), "Underline must anchor to bottom of line")
end)

run_test("CanvasHighlight: clearHighlight clears boxes safely", function()
    local highlighter = CanvasHighlight:new()
    local cleared = false
    local mock_view = {
        clearHighlight = function(self) cleared = true end,
        setHighlight = function(self, b, c) end,
    }
    highlighter:highlightSentence(mock_view, { { x = 0, y = 0, w = 10, h = 10 } }, "gray")
    assert(highlighter.current_highlight ~= nil)

    highlighter:clearHighlight(mock_view)
    assert(cleared == true, "Must call view:clearHighlight")
    assert(highlighter.current_highlight == nil, "current_highlight must be nil after clear")
end)

-- 2. PlayerWidget Tests
run_test("PlayerWidget: Control bar and mini bubble toggle", function()
    local sm = SettingsManager:new()
    local mock_view = {
        clearHighlight = function(self) end,
        setHighlight = function(self, b, c) end,
    }
    local player = PlayerWidget:new({
        view = mock_view,
        settings = sm,
    })

    -- The player starts as the small bubble; tapping its label expands to the full control bar
    assert(player.is_mini == true)
    player:show()
    assert(player.mini_bubble ~= nil)
    assert(player.control_bar == nil)

    player:toggleMode()
    assert(player.is_mini == false)
    assert(player.control_bar ~= nil)
    assert(player.mini_bubble == nil)

    player:toggleMode()
    assert(player.is_mini == true)
    assert(player.mini_bubble ~= nil)

    -- Closing resets to the start mode, so the next reading session starts small again
    player:toggleMode()
    player:hide()
    assert(player.visible == false)
    assert(player.is_mini == true)
end)

run_test("PlayerWidget: Playback speed cycling", function()
    local sm = SettingsManager:new()
    local backend = {
        speed = 1.0,
        setSpeed = function(self, s) self.speed = s end,
    }
    local player = PlayerWidget:new({
        settings = sm,
        audio_backend = backend,
    })

    player:onCycleSpeed()
    assert(backend.speed == 1.2, "1.0x must cycle to 1.2x")

    player:onCycleSpeed()
    assert(backend.speed == 1.5, "1.2x must cycle to 1.5x")

    player:onCycleSpeed()
    assert(backend.speed == 2.0, "1.5x must cycle to 2.0x")

    player:onCycleSpeed()
    assert(backend.speed == 0.8, "2.0x must cycle back to 0.8x")

    player:onCycleSpeed()
    assert(backend.speed == 1.0, "0.8x must cycle to 1.0x")
end)

run_test("PlayerWidget: Highlighting delegation to CanvasHighlight", function()
    local mock_view = {
        clearHighlight = function(self) end,
        setHighlight = function(self, b, c) end,
    }
    local player = PlayerWidget:new({
        view = mock_view,
        settings = SettingsManager:new(),
    })
    assert(player.highlighter ~= nil, "PlayerWidget must instantiate CanvasHighlight")

    local bboxes = { { x = 5, y = 5, w = 100, h = 20 } }
    player:highlightSentence(bboxes, "gray")
    assert(player.current_highlight ~= nil)

    player:clearHighlight()
    assert(player.current_highlight == nil)
end)

-- 3. Native KOReader ViewModule & Crengine BBoxes Tests
run_test("CanvasHighlight: Native registerViewModule and paintTo overlay", function()
    local highlighter = CanvasHighlight:new()
    local registered_module = nil
    local mock_view = {
        registerViewModule = function(self, name, module)
            assert(name == "tts_highlight")
            registered_module = module
        end
    }

    local bboxes = { { x = 10, y = 20, w = 200, h = 30 } }
    highlighter:highlightSentence(mock_view, bboxes, "gray")

    assert(registered_module ~= nil, "Must register view module with KOReader ReaderView")
    assert(type(registered_module.paintTo) == "function", "Module must have paintTo method")

    -- Test gray mode darkenRect (20% dimming)
    local darkened = {}
    local mock_bb = {
        darkenRect = function(self, x, y, w, h, factor)
            table.insert(darkened, { x = x, y = y, w = w, h = h, factor = factor })
        end,
    }
    registered_module:paintTo(mock_bb, 0, 0)
    assert(#darkened == 1, "Must darken the highlight box")
    assert(darkened[1].factor == 0.2, "Must dim by 20% factor")

    -- Test underline mode paintRect (2px black bar)
    highlighter:highlightSentence(mock_view, bboxes, "underline")
    local painted = {}
    mock_bb.paintRect = function(self, x, y, w, h, color)
        table.insert(painted, { x = x, y = y, w = w, h = h, color = color })
    end
    registered_module:paintTo(mock_bb, 0, 0)
    assert(#painted == 1, "Must paint underline rect")
    assert(painted[1].h == 2, "Underline height must be 2px")
end)

run_test("CanvasHighlight: Dynamic Crengine bounding boxes calculation", function()
    local highlighter = CanvasHighlight:new()

    local mock_doc = {
        getCurrentPage = function(self) return 1 end,
        getTextFromPositions = function(self, pos0, pos1, draw)
            -- If pos0 is (0,0), return full page mock
            if pos0.x == 0 and pos0.y == 0 then
                return {
                    text = "Xin chào các bạn. Đây là câu thứ hai trong đoạn văn.",
                    pos0 = { x = 0, y = 0 },
                    pos1 = { x = 1080, y = 200 },
                }
            end
            -- Sub-query for refined coordinates
            return {
                text = "Đây là câu thứ hai trong đoạn văn.",
                pos0 = { x = 10, y = 80 },
                pos1 = { x = 500, y = 110 },
            }
        end,
        getScreenBoxesFromPositions = function(self, pos0, pos1, draw)
            if pos0.x == 0 and pos0.y == 0 then
                -- Two lines
                return {
                    { x = 10, y = 40, w = 400, h = 30 },
                    { x = 10, y = 80, w = 600, h = 30 },
                }
            end
            -- Refined boxes for second sentence
            return {
                { x = 10, y = 80, w = 490, h = 30 }
            }
        end,
    }

    local target_sentence = "Đây là câu thứ hai trong đoạn văn."
    local boxes = highlighter:computeCrengineBBoxes(mock_doc, target_sentence, 1)

    assert(boxes ~= nil, "Must resolve boxes from Crengine line map")
    assert(#boxes >= 1, "Must contain at least 1 bounding box")
    assert(boxes[1].y >= 40, "Box coordinate must match on-screen position")
end)

run_test("PlayerWidget: onChunkChange auto-resolves bboxes if chunk.bboxes is empty", function()
    local mock_doc = {
        getCurrentPage = function(self) return 1 end,
        getTextFromPositions = function(self, pos0, pos1, draw)
            return {
                text = "Học tập là việc suốt đời của mỗi con người.",
                pos0 = { x = 0, y = 0 },
                pos1 = { x = 1080, y = 100 },
            }
        end,
        getScreenBoxesFromPositions = function(self, pos0, pos1, draw)
            return {
                { x = 20, y = 60, w = 550, h = 32 }
            }
        end,
    }

    local mock_view = {
        registerViewModule = function(self, name, mod) end,
        clearHighlight = function(self) end,
    }

    local player = PlayerWidget:new({
        view = mock_view,
        ui = { view = mock_view, document = mock_doc },
        settings = SettingsManager:new(),
    })

    local empty_bbox_chunk = {
        page = 1,
        index = 1,
        text = "Học tập là việc suốt đời của mỗi con người.",
        raw_text = "Học tập là việc suốt đời của mỗi con người.",
        bboxes = {}, -- Empty from Crengine extraction!
    }

    player:onChunkChange(empty_bbox_chunk, 1, 1, 5)

    assert(player.current_highlight ~= nil, "Must automatically resolve bboxes for chunk")
    assert(#player.current_highlight == 1, "Must have 1 resolved box")
    assert(player.current_highlight[1].w >= 540, "Box width must match Crengine output")
end)

print("==========================================================")
print(string.format("  ALL %d/%d PRESENTATION TESTS PASSED!", passed_tests, total_tests))
print("==========================================================")

if passed_tests < total_tests then os.exit(1) end
