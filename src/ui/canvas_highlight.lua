--[[
    canvas_highlight.lua - Canvas Highlighting & Partial E-ink Refresh Engine
    Project: KOReader TTS Plugin
    Layer: Presentation / UI
    Features:
      - Native KOReader ViewModule registration (paintTo hook)
      - Crisp, non-intrusive e-ink styling (darkenRect 20% gray, underline 2px, invert)
      - Dynamic Crengine (EPUB) & MuPDF (PDF) sentence bounding box resolution
      - Cached line maps for zero-overhead per-sentence queries
      - Clean E-ink partial refresh without full-page flashing
--]]

local ok_blit, Blitbuffer = pcall(require, "ffi/blitbuffer")
if not ok_blit or not Blitbuffer then
    Blitbuffer = {
        COLOR_WHITE  = 0xFFFFFF,
        COLOR_BLACK  = 0x000000,
        COLOR_GRAY_E = 0xEEEEEE,
    }
end

local ok_device, Device = pcall(require, "device")
local Screen = (ok_device and Device and Device.screen) or _G.Screen

local ok_uimanager, UIManager = pcall(require, "ui/uimanager")
if not ok_uimanager or not UIManager then
    UIManager = {}
end

--- Normalizes whitespace and common Unicode punctuation for robust text matching
local function normalizeForMatching(s)
    if not s or type(s) ~= "string" then return "" end
    return s
        :gsub("[\n\r]+", " ")
        :gsub("%s+", " ")
        :gsub("\226\128[\152-\155]", "'")
        :gsub("\226\128[\156-\159]", '"')
        :gsub("\194\171", '"')
        :gsub("\194\187", '"')
        :gsub("\226\128[\147-\148]", "-")
        :gsub("\226\128\166", "...")
        :gsub("\194\160", " ")
        :gsub("\194\173", "")
        :gsub("\226\128[\139\169]", "")
        :gsub("\239\187\191", "")
        :gsub("''+", "'")
        :gsub("^%s+", ""):gsub("%s+$", "")
end

--- Computes union bounding box for given arrays of rects
local function boxesUnionRegion(arrays, screen_w, screen_h)
    local min_x, min_y, max_x, max_y
    for _, arr in ipairs(arrays) do
        if arr then
            for _, b in ipairs(arr) do
                if b and b.x and b.y and b.w and b.h and b.w > 0 and b.h > 0 then
                    local x2, y2 = b.x + b.w, b.y + b.h
                    if not min_x or b.x < min_x then min_x = b.x end
                    if not min_y or b.y < min_y then min_y = b.y end
                    if not max_x or x2 > max_x then max_x = x2 end
                    if not max_y or y2 > max_y then max_y = y2 end
                end
            end
        end
    end
    if not min_x then return nil end
    local sw = screen_w or 1080
    local sh = screen_h or 2400
    min_x = math.max(0, min_x)
    min_y = math.max(0, min_y)
    max_x = math.min(sw, max_x)
    max_y = math.min(sh, max_y)
    if max_x <= min_x or max_y <= min_y then return nil end

    local ok_geom, Geom = pcall(require, "ui/geometry")
    if ok_geom and Geom and Geom.new then
        return Geom:new{ x = min_x, y = min_y, w = max_x - min_x, h = max_y - min_y }
    end
    return { x = min_x, y = min_y, w = max_x - min_x, h = max_y - min_y }
end

local CanvasHighlight = {}
CanvasHighlight.__index = CanvasHighlight

--- Creates a new CanvasHighlight instance.
function CanvasHighlight:new()
    local instance = setmetatable({}, self)
    instance.current_highlight = nil
    instance.mode = "gray"
    instance._last_boxes = nil
    instance._view_module_registered = false
    instance._line_cache = nil
    instance.ui = nil
    return instance
end

--- Highlights sentence bounding boxes with partial E-ink refresh.
-- @param view Document view object (ReaderView)
-- @param bboxes Array of bounding boxes { x, y, w, h } (optional, computed if missing)
-- @param mode Highlight mode: "gray" | "underline" | "invert" | "none"
-- @param context Optional table { ui, document, sentence_text, current_page, bar_top }
function CanvasHighlight:highlightSentence(view, bboxes, mode, context)
    mode = mode or "gray"
    self.mode = mode
    if context and context.ui then
        self.ui = context.ui
    end

    if mode == "none" then
        self:clearHighlight(view)
        return
    end

    if not view and not (self.ui and self.ui.view) then
        return
    end
    local target_view = view or (self.ui and self.ui.view)

    -- Always clear native Crengine selection to prevent stale ghost highlights
    if context and context.document and type(context.document.clearSelection) == "function" then
        pcall(context.document.clearSelection, context.document)
    elseif self.ui and self.ui.document and type(self.ui.document.clearSelection) == "function" then
        pcall(self.ui.document.clearSelection, self.ui.document)
    end

    -- Register native KOReader view module if not already hooked
    self:_ensureViewModule(target_view)

    -- Resolve bounding boxes dynamically if not provided
    local target_boxes = bboxes
    if (not target_boxes or #target_boxes == 0) and context and context.document and context.sentence_text then
        target_boxes = self:computeCrengineBBoxes(context.document, context.sentence_text, context.current_page)
    end

    if not target_boxes or #target_boxes == 0 then
        self:clearHighlight(target_view)
        return
    end

    -- Underline mode style adjustment
    local highlight_boxes = target_boxes
    if mode == "underline" then
        highlight_boxes = {}
        for _, b in ipairs(target_boxes) do
            table.insert(highlight_boxes, {
                x = b.x,
                y = b.y + math.max(0, b.h - 2),
                w = b.w,
                h = 2,
            })
        end
    end

    -- Support legacy mock view with setHighlight callback if present
    if target_view and type(target_view.setHighlight) == "function" then
        local color = (mode == "underline") and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY_E
        pcall(target_view.setHighlight, target_view, highlight_boxes, color)
    end

    self.current_highlight = highlight_boxes
    local bar_top = context and context.bar_top
    self:_refreshHighlight(highlight_boxes, target_view, bar_top)
end

--- Clears active highlight on view.
-- @param view Document view object
function CanvasHighlight:clearHighlight(view)
    local target_view = view or (self.ui and self.ui.view)
    if self.ui and self.ui.document and type(self.ui.document.clearSelection) == "function" then
        pcall(self.ui.document.clearSelection, self.ui.document)
    end
    if self.current_highlight then
        local old_boxes = self.current_highlight
        self.current_highlight = nil

        if target_view and type(target_view.clearHighlight) == "function" then
            pcall(target_view.clearHighlight, target_view)
        end

        self:_refreshHighlight(nil, target_view)
    end
    self._last_boxes = nil
end

--- Ensures our view module is registered with KOReader's ReaderView
function CanvasHighlight:_ensureViewModule(view)
    if self._view_module_registered then return end
    if not view or type(view.registerViewModule) ~= "function" then return end

    local this = self
    local module = {
        paintTo = function(_, bb, x, y)
            this:_paintOverlay(bb, x, y)
        end
    }
    pcall(view.registerViewModule, view, "tts_highlight", module)
    self._view_module_registered = true
end

--- Hook called by KOReader ReaderView after document content is painted
-- @param bb BlitBuffer Screen framebuffer
function CanvasHighlight:_paintOverlay(bb, _x, _y)
    local boxes = self.current_highlight
    if not boxes or #boxes == 0 or not bb then return end

    local sw = 1080
    local sh = 2400
    if Screen and type(Screen.getWidth) == "function" then
        sw = Screen:getWidth()
        sh = Screen:getHeight()
    end

    local style = self.mode or "gray"
    local line_w = 2
    if Screen and type(Screen.scaleBySize) == "function" then
        local ok_s, sw_val = pcall(Screen.scaleBySize, Screen, 2)
        if ok_s and sw_val then line_w = sw_val end
    end

    for _, box in ipairs(boxes) do
        local bx = math.max(0, box.x)
        local by = math.max(0, box.y)
        local bw = math.min(box.w - (bx - box.x), sw - bx)
        local bh = math.min(box.h - (by - box.y), sh - by)
        if bw > 0 and bh > 0 then
            if style == "underline" then
                if type(bb.paintRect) == "function" then
                    bb:paintRect(bx, by + bh - line_w, bw, line_w, Blitbuffer.COLOR_BLACK)
                end
            elseif style == "invert" then
                if type(bb.invertRect) == "function" then
                    pcall(bb.invertRect, bb, bx, by, bw, bh)
                end
            else
                -- "gray" mode: Match KOReader's native darkenRect (20% dimming)
                if type(bb.darkenRect) == "function" then
                    bb:darkenRect(bx, by, bw, bh, 0.2)
                elseif type(bb.paintRect) == "function" then
                    bb:paintRect(bx, by, bw, bh, Blitbuffer.COLOR_GRAY_E)
                end
            end
        end
    end
end

--- Triggers partial E-ink refresh covering previous and new highlight boxes
function CanvasHighlight:_refreshHighlight(new_boxes, view, bar_top)
    local sw = 1080
    local sh = 2400
    if Screen and type(Screen.getWidth) == "function" then
        sw = Screen:getWidth()
        sh = Screen:getHeight()
    end

    local arrays = {}
    if self._last_boxes and #self._last_boxes > 0 then
        table.insert(arrays, self._last_boxes)
    end
    if new_boxes and #new_boxes > 0 then
        table.insert(arrays, new_boxes)
    end

    local region = boxesUnionRegion(arrays, sw, sh)
    if region then
        if bar_top and region.y + region.h > bar_top then
            region.h = math.max(0, bar_top - region.y)
        end
        if region.h > 0 and UIManager and type(UIManager.setDirty) == "function" then
            pcall(UIManager.setDirty, UIManager, "all", "ui", region)
        end
    end

    self._last_boxes = new_boxes
end

--- Computes on-screen bounding boxes for a sentence using Crengine APIs
-- @param doc CreDocument instance
-- @param sentence_text Sentence text string
-- @param current_page Page number (optional)
-- @return table|nil Array of { x, y, w, h } boxes
function CanvasHighlight:computeCrengineBBoxes(doc, sentence_text, current_page)
    if not doc or type(doc.getTextFromPositions) ~= "function" then
        return nil
    end
    if not sentence_text or sentence_text == "" then
        return nil
    end

    local sw = 1080
    local sh = 2400
    if Screen and type(Screen.getWidth) == "function" then
        sw = Screen:getWidth()
        sh = Screen:getHeight()
    end

    local page = current_page
    if not page and type(doc.getCurrentPage) == "function" then
        page = doc:getCurrentPage()
    end
    page = page or 0

    local line_map = self._line_cache
    if not line_map or line_map.page ~= page or line_map.sw ~= sw or line_map.sh ~= sh then
        line_map = self:_buildCrengineLineMap(doc, sw, sh, page)
        self._line_cache = line_map
    end

    if not line_map or not line_map.built_text or line_map.n == 0 then
        return nil
    end

    return self:_matchSentenceOnLineMap(doc, line_map, sentence_text)
end

--- Builds and caches line map for the current page
function CanvasHighlight:_buildCrengineLineMap(doc, sw, sh, page)
    local ok_full, full_res = pcall(doc.getTextFromPositions, doc,
        { x = 0, y = 0 },
        { x = sw, y = sh },
        false
    )
    if not ok_full or not full_res or not full_res.pos0 or not full_res.pos1 then
        return nil
    end

    local sboxes = nil
    if type(doc.getScreenBoxesFromPositions) == "function" then
        pcall(function()
            sboxes = doc:getScreenBoxesFromPositions(full_res.pos0, full_res.pos1, false)
        end)
    end
    if not sboxes or #sboxes == 0 then
        return nil
    end

    local n = #sboxes
    local line_texts = {}
    local pad = 8
    for i = 1, n do
        local box = sboxes[i]
        local ok_line, r = pcall(doc.getTextFromPositions, doc,
            { x = math.max(0, box.x - pad), y = box.y + math.floor(box.h / 2) },
            { x = math.min(sw - 1, box.x + box.w - 1 + pad), y = box.y + math.floor(box.h / 2) },
            false
        )
        line_texts[i] = (ok_line and r and r.text) and normalizeForMatching(r.text) or ""
    end

    if doc and type(doc.clearSelection) == "function" then
        pcall(doc.clearSelection, doc)
    end

    local full_norm = normalizeForMatching(full_res.text or "")
    local built_text = ""
    local cum = { [0] = 0 }
    if full_norm ~= "" then
        built_text = full_norm
        local search = 1
        for i = 1, n do
            local lt = line_texts[i]
            if lt ~= "" then
                local p = built_text:find(lt, search, true)
                if p then
                    cum[i] = p + #lt - 1
                    search = p + 1
                else
                    cum[i] = cum[i - 1] + #lt
                end
            else
                cum[i] = cum[i - 1]
            end
        end
        if cum[n] < #built_text then
            cum[n] = #built_text
        end
    else
        for i = 1, n do
            local lt = line_texts[i]
            if i > 1 and lt ~= "" then built_text = built_text .. " " end
            built_text = built_text .. lt
            cum[i] = #built_text
        end
    end

    return {
        sw = sw,
        sh = sh,
        page = page,
        built_text = built_text,
        cum = cum,
        sboxes = sboxes,
        n = n,
    }
end

--- Matches sentence against line map and returns bounding boxes
function CanvasHighlight:_matchSentenceOnLineMap(doc, line_map, sentence_text)
    local sent_text = normalizeForMatching(sentence_text)
    if sent_text == "" then return nil end

    local built_text = line_map.built_text
    local vis_start, vis_end = built_text:find(sent_text, 1, true)

    if not vis_start then
        local words = {}
        for w in sent_text:gmatch("%S+") do
            table.insert(words, w)
        end
        if #words >= 2 then
            local prefix = words[1] .. " " .. words[2]
            if #words >= 3 then prefix = prefix .. " " .. words[3] end
            vis_start = built_text:find(prefix, 1, true)
            if vis_start then
                local suffix = words[#words - 1] .. " " .. words[#words]
                local _, s_end = built_text:find(suffix, vis_start, true)
                if s_end then
                    vis_end = s_end
                else
                    vis_end = math.min(#built_text, vis_start + #sent_text - 1)
                end
            end
        end
    end

    if not vis_start or not vis_end then
        return nil
    end

    local cum = line_map.cum
    local n = line_map.n
    local start_line = 1
    for i = 1, n do
        if cum[i] >= vis_start then
            start_line = i
            break
        end
    end

    local end_line = n
    for i = start_line, n do
        if cum[i] >= vis_end then
            end_line = i
            break
        end
    end

    local sb = line_map.sboxes[start_line]
    local eb = line_map.sboxes[end_line]
    if not sb or not eb then return nil end

    local function estimateX(box, line_idx, char_off)
        local total = cum[line_idx] - cum[line_idx - 1]
        if total <= 0 then return box.x end
        local x = box.x + math.floor((char_off / total) * box.w)
        return math.max(box.x, math.min(box.x + box.w - 1, x))
    end

    local sl_off = vis_start - cum[start_line - 1]
    local el_off = vis_end - cum[end_line - 1]
    local start_x = estimateX(sb, start_line, math.max(0, sl_off - 1))
    local end_x   = estimateX(eb, end_line, el_off)
    local start_y = sb.y + math.floor(sb.h / 2)
    local end_y   = eb.y + math.floor(eb.h / 2)

    local want_text = built_text:sub(vis_start, vis_end)
    if want_text == "" then want_text = sent_text end
    local want_len = #want_text

    local function querySelection(sx, sy, ex, ey)
        local ok, r = pcall(doc.getTextFromPositions, doc,
            { x = sx, y = sy }, { x = ex, y = ey }, false)
        if not ok or not r or not r.text then return "" end
        return normalizeForMatching(r.text)
    end

    local first_word = want_text:match("^%s*(%S+)")
    local last_word  = want_text:match("(%S+)%s*$")

    -- ── Phase 2: Binary-search refinement for start_x ────────────
    if first_word then
        local lo = sb.x
        local hi = math.min(sb.x + sb.w - 1, start_x + math.floor(sb.w * 0.4))
        local best_x = start_x
        for _ = 1, 10 do
            if hi < lo then break end
            local mid = math.floor((lo + hi) / 2)
            local mid_text = querySelection(mid, start_y, end_x, end_y)
            local w = mid_text:match("^%s*(%S+)")
            if w == first_word then
                best_x = mid
                hi = mid - 1
            elseif mid_text:find(first_word, 1, true) then
                lo = mid + 1
            else
                hi = mid - 1
            end
        end
        start_x = best_x
    end

    -- ── Phase 3: Binary-search refinement for end_x ──────────────
    if last_word then
        local lo = (start_line == end_line) and start_x or eb.x
        local hi = eb.x + eb.w - 1
        local best_x = end_x
        for _ = 1, 10 do
            if hi < lo then break end
            local mid = math.floor((lo + hi) / 2)
            local mid_text = querySelection(start_x, start_y, mid, end_y)
            local w = mid_text:match("(%S+)%s*$")
            if w == last_word then
                best_x = mid
                lo = mid + 1
            elseif mid_text:find(last_word, 1, true) then
                hi = mid - 1
            else
                lo = mid + 1
            end
        end
        end_x = best_x
    end

    -- ── Guard: only use Crengine boxes if text length matches want_len ──
    local ok_q, r = pcall(doc.getTextFromPositions, doc,
        { x = start_x, y = start_y },
        { x = end_x,   y = end_y },
        false
    )
    if doc and type(doc.clearSelection) == "function" then
        pcall(doc.clearSelection, doc)
    end

    if ok_q and r and r.pos0 and r.pos1 then
        local cre_text = (r.text and normalizeForMatching(r.text)) or ""
        local len_ok = #cre_text >= (want_len - 2) and #cre_text <= (want_len + 6)
        if len_ok and type(doc.getScreenBoxesFromPositions) == "function" then
            local cre_boxes = nil
            pcall(function()
                cre_boxes = doc:getScreenBoxesFromPositions(r.pos0, r.pos1, false)
            end)
            if cre_boxes and #cre_boxes > 0 then
                local res = {}
                for idx, cb in ipairs(cre_boxes) do
                    if cb.w and cb.h and cb.w > 0 and cb.h > 0 then
                        local bx = cb.x
                        local by = cb.y
                        local bw = cb.w
                        local bh = cb.h

                        -- First line: clamp left edge to start_x
                        if idx == 1 then
                            if bx < start_x then
                                bw = math.max(10, (bx + bw) - start_x)
                                bx = start_x
                            end
                        end

                        -- Last line: clamp right edge to end_x so it NEVER bleeds into next sentence
                        if idx == #cre_boxes then
                            if (bx + bw) > end_x then
                                bw = math.max(10, end_x - bx)
                            end
                        end

                        if bw > 0 and bh > 0 then
                            table.insert(res, { x = bx, y = by, w = bw, h = bh })
                        end
                    end
                end
                if #res > 0 then
                    return res
                end
            end
        end
    end

    -- Geometric line-box fallback
    local boxes = {}
    for i = start_line, end_line do
        local lbox = line_map.sboxes[i]
        if lbox and lbox.w > 0 and lbox.h > 0 then
            local bx = lbox.x
            local bw = lbox.w
            if start_line == end_line then
                bx = start_x
                bw = math.max(10, end_x - start_x)
            elseif i == start_line then
                bx = start_x
                bw = math.max(10, (lbox.x + lbox.w) - start_x)
            elseif i == end_line then
                bx = lbox.x
                bw = math.max(10, end_x - lbox.x)
            end
            table.insert(boxes, { x = bx, y = lbox.y, w = bw, h = lbox.h })
        end
    end

    return #boxes > 0 and boxes or nil
end

return CanvasHighlight
