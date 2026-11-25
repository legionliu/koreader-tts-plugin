--[[
    document_chunker.lua - Text extraction, sanitization, and sentence chunking module
    Project: KOReader TTS Plugin
    Layer: Application Service
    Compatible with Crengine (EPUB/MOBI) and MuPDF (PDF).
    Implements 3-tier sentence chunking & pronunciation dictionary normalization.
--]]

local ok_settings, Settings = pcall(require, "src.service.settings_manager")
if not ok_settings then
    Settings = require("settings")
end

local TextChunker = {}
TextChunker.__index = TextChunker

local DEFAULT_MIN_CHARS = 120
local DEFAULT_MAX_CHARS = 300

-- ===========================================================================
-- CJK punctuation configuration  --  EDIT THESE LISTS to add your own symbols.
-- Each entry must be ONE character (CJK punctuation is 3 bytes in UTF-8; that's fine).
-- ===========================================================================
local CJK_PUNCT = {
    -- Marks that END a sentence (the text is split right after them)
    sentence_end = { "。", "！", "？", "‼", "⁇", "⁈", "⁉", "…" },
    -- Closing marks that stay attached to the sentence they close, e.g.  。”  ？）  。」
    closers = { "”", "’", "」", "』", "）", "》", "】", "〉", "］", "｝", "〕", "〗" },
    -- Soft break points, only used when ONE sentence is longer than max_chunk_chars.
    -- Groups are tried in order; inside a group the right-most mark that fits wins.
    clause_groups = {
        { ",", "，", "、" },
        { ";", "；" },
        { ":", "：" },
        { "—", "―", "-" },   -- em dash (——is two of these), horizontal bar, hyphen
    },
}

local function toSet(list)
    local set = {}
    for _, ch in ipairs(list) do set[ch] = true end
    return set
end
local SENT_END = toSet(CJK_PUNCT.sentence_end)
local CLOSERS = toSet(CJK_PUNCT.closers)
local CLAUSE_GROUPS = {}
for _, group in ipairs(CJK_PUNCT.clause_groups) do
    table.insert(CLAUSE_GROUPS, toSet(group))
end
local ASCII_TAIL = { ['"'] = true, ["'"] = true, ["?"] = true, ["!"] = true }

-- UTF-8 helpers (LuaJIT in KOReader has no utf8 library)
local function charLen(b)
    if b < 0xC0 then return 1 elseif b < 0xE0 then return 2 elseif b < 0xF0 then return 3 else return 4 end
end
local function charAt(str, i)
    local b = str:byte(i)
    if not b then return "" end
    return str:sub(i, i + charLen(b) - 1)
end
--- the character that ends right before byte position i
local function prevChar(str, i)
    if i <= 1 then return "" end
    local j = i - 1
    while j > 1 do
        local b = str:byte(j)
        if b >= 0x80 and b < 0xC0 then j = j - 1 else break end
    end
    return str:sub(j, i - 1)
end
--- Han / kana / CJK punctuation / full-width forms (no spaces are used around these)
local function isCJK(ch)
    local b = ch:byte(1)
    return b ~= nil and ((b >= 0xE3 and b <= 0xE9) or b == 0xEF)
end
--- join two text pieces; no space is inserted next to CJK characters
local function joinText(a, b)
    if a == "" then return b end
    if b == "" then return a end
    if isCJK(prevChar(a, #a + 1)) or isCJK(charAt(b, 1)) then
        return a .. b
    end
    return a .. " " .. b
end

--- Initialize TextChunker instance
-- @param options Config table: min_chars, max_chars, filter_footnotes, custom_mappings
function TextChunker:new(options)
    local opts = options or {}
    local instance = setmetatable({}, self)
    instance.min_chars = opts.min_chars
        or (opts.settings and opts.settings:get("min_chunk_chars"))
        or DEFAULT_MIN_CHARS
    instance.max_chars = opts.max_chars
        or (opts.settings and opts.settings:get("max_chunk_chars"))
        or DEFAULT_MAX_CHARS
    instance.filter_footnotes = (opts.filter_footnotes ~= false)
    instance.custom_mappings = opts.custom_mappings or {}
    instance.settings = opts.settings
    instance._stitched_heads = {}
    return instance
end

--- Sanitize raw text: strip footnotes, standalone page numbers, and soft hyphens
-- @param raw_text Raw document text string
-- @return string Cleaned text string
function TextChunker:sanitize(raw_text)
    if not raw_text or type(raw_text) ~= "string" or raw_text == "" then
        return ""
    end

    local text = raw_text

    -- 1. Strip soft hyphens (UTF-8 0xC2 0xAD)
    text = text:gsub("\194\173", "")

    -- 2. Normalize non-breaking spaces (UTF-8 0xC2 0xA0) to standard spaces
    text = text:gsub("\194\160", " ")

    -- 3. Strip standalone page numbers at headers or footers
    text = text:gsub("^%s*%d+%s*[\r\n]+", "")
    text = text:gsub("[\r\n]+%s*%d+%s*$", "")
    text = text:gsub("[\r\n]+%s*%d+%s*/%s*%d+%s*[\r\n]+", " ")

    -- 4. Strip footnote markers: [1], [12], (1), *, †, ‡ (replace with space to prevent glued words)
    if self.filter_footnotes then
        text = text:gsub("%[%d+%]", " ")
        text = text:gsub("%(%d+%)", " ")
        text = text:gsub("%*+", " ")
        text = text:gsub("†", " ")
        text = text:gsub("‡", " ")
    end

    -- 5. Normalize ellipsis: '...' to '…'
    text = text:gsub("%.%.%.+", "…")

    -- 6. Collapse consecutive whitespace and linebreaks into a single space
    text = text:gsub("[\r\n]+", " ")
    text = text:gsub("%s+", " ")

    -- 7. Trim leading and trailing whitespace
    text = text:gsub("^%s+", ""):gsub("%s+$", "")

    return text
end

--- Normalize abbreviations / hard words using pronunciation dictionary
-- @param text Text string to normalize
-- @param custom_dict Additional custom dictionary mappings (optional)
-- @return string Normalized text string ready for TTS
function TextChunker:normalizePronunciation(text, custom_dict)
    if not text or type(text) ~= "string" or text == "" then
        return ""
    end

    -- Merge default dictionary from Settings and custom mappings
    local mappings = {}
    if Settings and Settings.DEFAULT_PRONUNCIATION_MAP then
        for k, v in pairs(Settings.DEFAULT_PRONUNCIATION_MAP) do
            mappings[k] = v
        end
    end
    if self.custom_mappings then
        for k, v in pairs(self.custom_mappings) do
            mappings[k] = v
        end
    end
    if custom_dict then
        for k, v in pairs(custom_dict) do
            mappings[k] = v
        end
    end

    local result = text

    -- Iterate through dictionary mappings with word boundary checks
    for orig, replacement in pairs(mappings) do
        if orig and orig ~= "" and replacement then
            -- Escape Lua pattern special characters in original word
            local escaped_orig = orig:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")

            -- If original word ends with a period (e.g. TP., TS., v.v.)
            if orig:sub(-1) == "." then
                -- Match at start of sentence
                result = result:gsub("^" .. escaped_orig .. "(%s+)", replacement .. "%1")
                result = result:gsub("^" .. escaped_orig .. "$", replacement)
                -- Match after whitespace or opening punctuation
                result = result:gsub("([%s%(\"“])" .. escaped_orig .. "(%s+)", "%1" .. replacement .. "%2")
                result = result:gsub("([%s%(\"“])" .. escaped_orig .. "$", "%1" .. replacement)
                result = result:gsub("([%s%(\"“])" .. escaped_orig .. "([%,%;%:…])", "%1" .. replacement .. "%2")
            else
                -- Standard abbreviation without period (e.g. ĐH, CNTT, AI, NXB)
                result = result:gsub("^" .. escaped_orig .. "(%s+)", replacement .. "%1")
                result = result:gsub("^" .. escaped_orig .. "$", replacement)
                result = result:gsub("([%s%(\"“%[%'%-%,])" .. escaped_orig .. "(%s+)", "%1" .. replacement .. "%2")
                result = result:gsub("([%s%(\"“%[%'%-%,])" .. escaped_orig .. "$", "%1" .. replacement)
                result = result:gsub("([%s%(\"“%[%'%-%,])" .. escaped_orig .. "([%.%?%!%,%;%:…%)\"”%s])", "%1" .. replacement .. "%2")
            end
        end
    end

    return result
end

--- Split a long sentence (> max_chars) at natural punctuation near the middle (Tier 3)
-- @param sentence Long sentence string
-- @param max_limit Maximum character threshold
-- @return table Array of shorter sentence chunks
local function splitLongSentence(sentence, max_limit)
    if #sentence <= max_limit then
        return { sentence }
    end

    local chunks = {}
    local remaining = sentence

    while #remaining > max_limit do
        -- largest prefix <= max_limit bytes that ends on a character boundary
        local cut = max_limit
        while cut > 1 do
            local nb = remaining:byte(cut + 1)
            if nb and nb >= 0x80 and nb < 0xC0 then cut = cut - 1 else break end
        end
        local search_sub = remaining:sub(1, cut)

        -- Find natural split point: comma / semicolon / colon / dash groups (ASCII + CJK)
        local split_pos = nil
        for _, group in ipairs(CLAUSE_GROUPS) do
            local best = nil
            local k = 1
            while k <= #search_sub do
                local ch = charAt(search_sub, k)
                if group[ch] and k >= 20 then
                    best = k + #ch - 1
                end
                k = k + #ch
            end
            if best then
                split_pos = best
                -- keep doubled marks together (e.g. the Chinese dash ——)
                local last_ch = prevChar(remaining, split_pos + 1)
                while charAt(remaining, split_pos + 1) == last_ch and last_ch ~= "," do
                    split_pos = split_pos + #last_ch
                end
                break
            end
        end

        -- Fallback: split at space nearest to limit
        if not split_pos then
            local space_idx = nil
            local cur = 1
            while true do
                local found = search_sub:find(" ", cur, true)
                if not found or found > cut then break end
                if found >= 20 then
                    space_idx = found
                end
                cur = found + 1
            end
            split_pos = space_idx
        end

        -- Hard split fallback (always on a character boundary)
        if not split_pos then
            split_pos = cut
        end

        local part1 = remaining:sub(1, split_pos):gsub("^%s+", ""):gsub("%s+$", "")
        local part2 = remaining:sub(split_pos + 1):gsub("^%s+", ""):gsub("%s+$", "")

        if #part1 > 0 then
            table.insert(chunks, part1)
        end
        remaining = part2
    end

    if #remaining > 0 then
        table.insert(chunks, remaining)
    end

    return chunks
end

--- Split sanitized text into sentences using 3-tier algorithm
-- @param text Sanitized text string
-- @return table Array of sentence strings
function TextChunker:splitSentences(text)
    if not text or type(text) ~= "string" or text == "" then
        return {}
    end

    local raw_sentences = {}
    local len = #text
    local start_idx = 1
    local in_quotes = false
    local quote_char = nil

    local i = 1
    while i <= len do
        local c = text:sub(i, i)
        local next_c = (i < len) and text:sub(i + 1, i + 1) or ""

        -- Track dialogue quotes open/close state
        if c == '"' or c == '“' or c == '”' then
            if not in_quotes then
                in_quotes = true
                quote_char = c
            else
                in_quotes = false
                quote_char = nil
            end
        end

        -- CJK sentence terminators (。！？ …): always a boundary, closing marks stay attached
        local cjk_end = nil
        if text:byte(i) >= 0xE0 then
            local ch = charAt(text, i)
            if SENT_END[ch] then
                local after = charAt(text, i + #ch)
                -- "…" is only a boundary inside CJK text (keeps English "Well… I think" intact)
                if ch ~= "…" or isCJK(prevChar(text, i)) or isCJK(after) or CLOSERS[after] then
                    cjk_end = i + #ch - 1
                end
            end
        end

        if cjk_end then
            local e = cjk_end
            while e < len do
                local nxt = charAt(text, e + 1)
                if SENT_END[nxt] or CLOSERS[nxt] or ASCII_TAIL[nxt] then
                    e = e + #nxt
                else
                    break
                end
            end
            local s = text:sub(start_idx, e):gsub("^%s+", ""):gsub("%s+$", "")
            if #s > 0 then
                table.insert(raw_sentences, s)
            end
            i = e + 1
            start_idx = i
        else
            -- Check sentence terminators: . ? ! …
            local is_delimiter = false
            if (c == "." or c == "?" or c == "!" or c == "…") then
                -- Ignore periods in decimal numbers (e.g. 3.14, 10.5)
                local prev_c = (i > 1) and text:sub(i - 1, i - 1) or ""
                local is_decimal = (c == "." and prev_c:match("%d") and next_c:match("%d"))

                -- Ignore periods in known abbreviations (TP., TS., ThS., GS., v.v.)
                local is_abbrev = false
                if c == "." then
                    local check_window = text:sub(math.max(1, i - 10), i)
                    local prev_word = check_window:match("([%a%.]+)%.$")
                    if prev_word then
                        local lower_pw = prev_word:lower()
                        local KNOWN_ABBREVS = {
                            ["tp"] = true, ["ts"] = true, ["ths"] = true, ["pgs"] = true,
                            ["gs"] = true, ["bs"] = true, ["v.v"] = true, ["nxb"] = true,
                            ["ks"] = true, ["dr"] = true, ["mr"] = true, ["mrs"] = true,
                            ["ms"] = true, ["prof"] = true,
                        }
                        if KNOWN_ABBREVS[lower_pw] or (prev_word:match("^%u+$") and #prev_word <= 4) then
                            is_abbrev = true
                        end
                    end
                end

                if not is_decimal and not is_abbrev then
                    -- Delimiter is valid if outside quotes or immediately followed by closing quote/space
                    if not in_quotes or next_c == '"' or next_c == '”' or next_c == ' ' or next_c == "" then
                        is_delimiter = true
                    end
                end
            end

            if is_delimiter then
                -- Collect contiguous punctuation marks (e.g. !?, ..., !!!)
                local end_idx = i
                while end_idx < len do
                    local peek = text:sub(end_idx + 1, end_idx + 1)
                    if peek == "." or peek == "?" or peek == "!" or peek == "…" or peek == '"' or peek == '”' then
                        end_idx = end_idx + 1
                    else
                        break
                    end
                end

                local s = text:sub(start_idx, end_idx):gsub("^%s+", ""):gsub("%s+$", "")
                if #s > 0 then
                    table.insert(raw_sentences, s)
                end

                i = end_idx + 1
                start_idx = i
            else
                i = i + 1
            end
        end
    end

    -- Append trailing text if not terminated with punctuation
    if start_idx <= len then
        local tail = text:sub(start_idx, len):gsub("^%s+", ""):gsub("%s+$", "")
        if #tail > 0 then
            table.insert(raw_sentences, tail)
        end
    end

    if #raw_sentences == 0 then
        return {}
    end

    -- TIER 2: Merge short chunks (< min_chars) into next chunk (Anti-fragmentation)
    local merged_sentences = {}
    local buffer = ""

    for idx, s in ipairs(raw_sentences) do
        if #buffer > 0 then
            buffer = joinText(buffer, s)
        else
            buffer = s
        end

        if #buffer >= self.min_chars or idx == #raw_sentences then
            table.insert(merged_sentences, buffer)
            buffer = ""
        end
    end

    if #buffer > 0 then
        if #merged_sentences > 0 then
            merged_sentences[#merged_sentences] = joinText(merged_sentences[#merged_sentences], buffer)
        else
            table.insert(merged_sentences, buffer)
        end
    end

    -- TIER 3: Safety Split sentences longer than max_chars at natural punctuation
    local final_sentences = {}
    for _, s in ipairs(merged_sentences) do
        if #s > self.max_chars then
            local splits = splitLongSentence(s, self.max_chars)
            for _, sub_s in ipairs(splits) do
                if #sub_s > 0 then
                    table.insert(final_sentences, sub_s)
                end
            end
        else
            table.insert(final_sentences, s)
        end
    end

    return final_sentences
end

--- Extract raw text from page via Document Engine (Hybrid Strategy)
-- Supports both Crengine (EPUB/MOBI) and MuPDF (PDF)
-- @param document KOReader self.ui.document object (or mock)
-- @param page_num Page number (1-based)
-- @param ui KOReader self.ui object (optional)
-- @return string raw text, table word bounding boxes
function TextChunker:extractRawPageText(document, page_num, ui)
    if not document then
        return "", {}
    end

    local text = ""
    local word_boxes = {}

    local function extractTextAndBoxes(res)
        if not res then return nil, nil end
        if type(res) == "string" and #res > 0 then
            return res, {}
        elseif type(res) == "table" then
            local t = res.text
            local b = res.word_boxes or res.boxes or {}
            if type(t) == "string" and #t > 0 then
                return t, b
            end
        end
        return nil, nil
    end

    local cur = (ui and type(ui.getCurrentPage) == "function" and ui:getCurrentPage())
        or (ui and ui.paging and ui.paging.current_page)
        or (document and type(document.getCurrentPage) == "function" and document:getCurrentPage())

    local is_current_page = true
    if cur and cur > 0 and page_num and cur ~= page_num then
        is_current_page = false
    end

    -- 1. Crengine on-screen text extraction (handles visible page and peeking next page via internal gotoPage)
    if type(document.getTextFromPositions) == "function" then
        local ok_d, Device = pcall(require, "device")
        local Screen = (ok_d and Device and Device.screen) or (ui and ui.screen) or _G.Screen
        local sw = (Screen and type(Screen.getWidth) == "function" and Screen:getWidth())
            or (ui and ui.screen and ui.screen:getWidth()) or 1080
        local sh = (Screen and type(Screen.getHeight) == "function" and Screen:getHeight())
            or (ui and ui.screen and ui.screen:getHeight()) or 2400

        local saved_page = nil
        if not is_current_page and type(document.gotoPage) == "function" and type(document.getCurrentPage) == "function" then
            saved_page = document:getCurrentPage()
            pcall(document.gotoPage, document, page_num, true)
        end

        local ok, res = pcall(document.getTextFromPositions, document, {x = 0, y = 0}, {x = sw, y = sh}, false)

        if saved_page then
            pcall(document.gotoPage, document, saved_page, true)
        end

        if type(document.clearSelection) == "function" then
            pcall(document.clearSelection, document)
        end

        if ok and res then
            local t, b = extractTextAndBoxes(res)
            if t and #t > 0 then
                if (not b or #b == 0) and type(document.getWordBBoxes) == "function" then
                    local ok_wb, wbs = pcall(document.getWordBBoxes, document, page_num)
                    if ok_wb and wbs then b = wbs end
                end
                return t, b or {}
            end
        end
    end

    -- 2. PDF / DjVu structured word boxes (paged mode)
    if (ui and ui.paging) or (type(document.getTextBoxes) == "function") then
        local ok, page_boxes = pcall(document.getTextBoxes, document, page_num)
        if ok and page_boxes and page_boxes[1] then
            local lines = {}
            local all_wbs = {}
            for _, line in ipairs(page_boxes) do
                local words = {}
                for _, wb in ipairs(line) do
                    if wb.word and wb.word ~= "" then
                        table.insert(words, wb.word)
                        table.insert(all_wbs, wb)
                    end
                end
                if #words > 0 then
                    table.insert(lines, table.concat(words, " "))
                end
            end
            if #lines > 0 then
                return table.concat(lines, "\n"), all_wbs
            end
        end
    end

    -- 3. Try MuPDF API: getPageText & getTextWordBoxes
    local ok_mupdf, res_text = pcall(function()
        if type(document.getPageText) == "function" then
            return document:getPageText(page_num)
        end
    end)
    if ok_mupdf and type(res_text) == "string" and #res_text > 0 then
        text = res_text
        pcall(function()
            if type(document.getTextWordBoxes) == "function" then
                word_boxes = document:getTextWordBoxes(page_num) or {}
            end
        end)
        return text, word_boxes
    end

    -- 4. Try Crengine XPointer API: getPageXPointer & getTextFromXPointers (exact page bounds)
    local ok_xp, res_xp = pcall(function()
        if type(document.getPageXPointer) == "function" and type(document.getTextFromXPointers) == "function" then
            local xp0 = document:getPageXPointer(page_num)
            if xp0 then
                local xp1 = document:getPageXPointer(page_num + 1)
                if xp1 then
                    return document:getTextFromXPointers(xp0, xp1)
                elseif type(document.getTextFromXPointer) == "function" then
                    return document:getTextFromXPointer(xp0)
                else
                    return document:getTextFromXPointers(xp0, xp0)
                end
            end
        end
    end)
    if ok_xp and res_xp then
        local t, b = extractTextAndBoxes(res_xp)
        if t and #t > 0 then
            return t, b or {}
        end
    end

    -- 5. Crengine peek next view in rolling mode if page_num != current_page (fallback only)
    if not is_current_page and ui and ui.rolling and type(document.getCurrentPos) == "function" and type(document.gotoPos) == "function" and type(document.getTextFromPositions) == "function" then
        local ok_d, Device = pcall(require, "device")
        local Screen = (ok_d and Device and Device.screen) or (ui and ui.screen) or _G.Screen
        local sw = (Screen and type(Screen.getWidth) == "function" and Screen:getWidth())
            or (ui and ui.screen and ui.screen:getWidth()) or 1080
        local sh = (Screen and type(Screen.getHeight) == "function" and Screen:getHeight())
            or (ui and ui.screen and ui.screen:getHeight()) or 2400
        local cur = (ui and type(ui.getCurrentPage) == "function" and ui:getCurrentPage()) or page_num
        local ok_peek, peek_res = pcall(function()
            local saved_pos = document:getCurrentPos()
            local next_pos = saved_pos + (page_num - cur) * sh
            document:gotoPos(next_pos)
            local ok_res, res = pcall(document.getTextFromPositions, document, {x = 0, y = 0}, {x = sw, y = sh}, false)
            document:gotoPos(saved_pos)
            if type(document.clearSelection) == "function" then
                pcall(document.clearSelection, document)
            end
            if ok_res and res then
                return extractTextAndBoxes(res)
            end
        end)
        if ok_peek and peek_res and #peek_res > 0 then
            return peek_res, {}
        end
    end

    -- 6. Generic fallbacks: getTextFromPositions(page_num) or getText(page_num)
    local ok_cre, res_cre = pcall(function()
        if type(document.getTextFromPositions) == "function" then
            return document:getTextFromPositions(page_num)
        end
    end)
    if ok_cre and res_cre then
        local t, b = extractTextAndBoxes(res_cre)
        if t and #t > 0 then
            return t, b or {}
        end
    end

    if type(document.getText) == "function" then
        pcall(function()
            local t = document:getText(page_num)
            if t and type(t) == "string" and #t > 0 then
                text = t
            end
        end)
    end

    local ok_l, logger = pcall(require, "logger")
    if ok_l and logger and logger.dbg then
        logger.dbg(string.format("[TTS Chunker] target_page=%s, ui_cur=%s, is_curr=%s, len=%d, text=%s",
            tostring(page_num), tostring(cur), tostring(is_current_page), #(text or ""), (text or ""):sub(1, 60):gsub("[\r\n]+", " ")))
    end

    return text or "", word_boxes or {}
end

--- Map sentence position to word bounding boxes on the page
-- @param raw_sentence Raw sentence string
-- @param full_text Full page text string
-- @param word_boxes Array of word bounding boxes on the page
-- @param search_offset Search start offset in full_text
-- @return table matched bounding boxes, number end offset
local function mapSentenceToBBoxes(raw_sentence, full_text, word_boxes, search_offset)
    if not word_boxes or #word_boxes == 0 or not full_text or #full_text == 0 then
        return {}, search_offset
    end

    local s_start, s_end = full_text:find(raw_sentence, search_offset, true)
    if not s_start then
        local first_words = raw_sentence:match("^%s*([^%s]+%s+[^%s]+)")
        if first_words then
            s_start = full_text:find(first_words, search_offset, true)
            if s_start then
                local last_words = raw_sentence:match("([^%s]+%s+[^%s]+)%s*$")
                if last_words then
                    local _, l_end = full_text:find(last_words, s_start, true)
                    if l_end then
                        s_end = l_end
                    end
                end
                if not s_end then
                    s_end = s_start + #raw_sentence - 1
                end
            end
        end
    end

    if not s_start then
        return {}, search_offset
    end

    local matched_bboxes = {}
    for _, wb in ipairs(word_boxes) do
        if wb.char_start and wb.char_end then
            if wb.char_start >= s_start and wb.char_end <= s_end then
                table.insert(matched_bboxes, {
                    x = wb.x, y = wb.y, w = wb.w, h = wb.h
                })
            end
        elseif wb.x and wb.y and wb.w and wb.h then
            table.insert(matched_bboxes, {
                x = wb.x, y = wb.y, w = wb.w, h = wb.h
            })
        end
    end

    return matched_bboxes, (s_end or search_offset)
end

--- Checks if a text snippet ends with a sentence terminator (. ? ! : … " ”)
local function hasSentenceTerminator(s)
    if not s or s == "" then return true end
    local trimmed = s:gsub("%s+$", "")
    if #trimmed == 0 then return true end
    local c1 = trimmed:sub(-1)
    if c1 == "." or c1 == "?" or c1 == "!" or c1 == ":" or c1 == '"' or c1 == "'" then
        return true
    end
    if #trimmed >= 3 then
        local c3 = trimmed:sub(-3)
        if c3 == "…" or c3 == "”" or c3 == "\226\128\157" or c3 == "\226\128\166" then
            return true
        end
    end
    -- CJK: skip trailing closing marks (）」》 ...), then look for 。！？ … or ：
    local k = #trimmed + 1
    for _ = 1, 8 do
        local pc = prevChar(trimmed, k)
        if pc == "" then break end
        if CLOSERS[pc] or pc == '"' or pc == "'" then
            k = k - #pc
        else
            if SENT_END[pc] or pc == "：" then return true end
            break
        end
    end
    return false
end

--- Extracts the head of a sentence (up to the first terminator) from the beginning of a page
local function findSentenceHead(text)
    if not text or text == "" then return "", "" end
    local len = #text
    local i = 1
    while i <= len do
        local c = text:sub(i, i)
        local is_term = (c == "." or c == "?" or c == "!" or c == ":")
        if not is_term and i + 2 <= len then
            local c3 = text:sub(i, i + 2)
            if c3 == "…" or c3 == "”" or c3 == "\226\128\157" or c3 == "\226\128\166" then
                is_term = true
                i = i + 2
            end
        end

        if not is_term and c:byte() >= 0xE0 then
            local ch = charAt(text, i)
            if SENT_END[ch] or ch == "：" then
                is_term = true
                i = i + #ch - 1
            end
        end

        if is_term then
            local end_idx = i
            while end_idx < len do
                local peek1 = text:sub(end_idx + 1, end_idx + 1)
                local peek_ch = charAt(text, end_idx + 1)
                if peek1 == "." or peek1 == "?" or peek1 == "!" or peek1 == ":" or peek1 == '"' or peek1 == "'" then
                    end_idx = end_idx + 1
                elseif SENT_END[peek_ch] or CLOSERS[peek_ch] then
                    end_idx = end_idx + #peek_ch
                elseif end_idx + 3 <= len then
                    local peek3 = text:sub(end_idx + 1, end_idx + 3)
                    if peek3 == "”" or peek3 == "…" or peek3 == "’" or peek3 == "\226\128\157" or peek3 == "\226\128\166" or peek3 == "\226\128\153" then
                        end_idx = end_idx + 3
                    else
                        break
                    end
                else
                    break
                end
            end
            local head = text:sub(1, end_idx):gsub("^%s+", ""):gsub("%s+$", "")
            local remainder = text:sub(end_idx + 1):gsub("^%s+", "")
            return head, remainder
        end
        i = i + 1
    end
    return text, ""
end

--- Extract and chunk full page content from document engine
-- Returns array of Chunk tables with Bounding Boxes
-- @param document KOReader self.ui.document
-- @param page_num Current page number
-- @param ui KOReader self.ui (optional)
-- @return table Array of Chunk objects
function TextChunker:extractPageChunks(document, page_num, ui)
    local raw_page_text, word_boxes = self:extractRawPageText(document, page_num, ui)
    local ok_l, logger = pcall(require, "logger")
    if ok_l and logger and logger.dbg then
        logger.dbg(string.format("[TTS Chunker] page=%s, raw_len=%d, snippet=%s",
            tostring(page_num), #(raw_page_text or ""), (raw_page_text or ""):sub(1, 80):gsub("[\r\n]+", " ")))
    end
    if not raw_page_text or raw_page_text == "" then
        return {}
    end

    -- 1. Sanitize text
    local cleaned_text = self:sanitize(raw_page_text)
    if cleaned_text == "" then
        return {}
    end

    -- 1.1 Strip head that was already stitched into the previous page (check cleaned text first to avoid header interference)
    self._stitched_heads = self._stitched_heads or {}
    local head_to_strip = self._stitched_heads[page_num]
    if head_to_strip and head_to_strip ~= "" then
        self._stitched_heads[page_num] = nil
        local esc = head_to_strip:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        local pat = "^%s*" .. esc .. "%s*"
        if cleaned_text:match(pat) then
            cleaned_text = cleaned_text:gsub(pat, "", 1)
        elseif raw_page_text:match(pat) then
            raw_page_text = raw_page_text:gsub(pat, "", 1)
            cleaned_text = self:sanitize(raw_page_text)
        end
    end

    -- 2. 3-tier sentence chunking
    local sentences = self:splitSentences(cleaned_text)
    local chunks = {}
    local offset = 1
    local chunk_idx = 1

    for _, sentence in ipairs(sentences) do
        -- 3. Pronunciation dictionary normalization for TTS
        local tts_text = self:normalizePronunciation(sentence)
        local trimmed = tts_text:gsub("^%s+", ""):gsub("%s+$", "")

        -- Filter out empty or whitespace-only chunks to prevent server HTTP 400 errors
        if #trimmed > 0 and trimmed:match("%S") then
            -- 4. Bounding box mapping
            local bboxes, new_offset = mapSentenceToBBoxes(sentence, raw_page_text, word_boxes, offset)
            offset = new_offset

            table.insert(chunks, {
                index       = chunk_idx,
                page        = page_num,
                text        = trimmed,        -- Text sent to TTS server (normalized & trimmed)
                raw_text    = sentence,       -- Original page text
                start_pos   = offset,
                end_pos     = offset + #sentence,
                char_count  = #trimmed,
                bboxes      = bboxes or {},   -- Highlighting bounding boxes
            })
            chunk_idx = chunk_idx + 1
        end
    end

    -- 5. Cross-page sentence stitching (stitch incomplete last sentence with next page's head)
    if #chunks > 0 and document then
        local last_chunk = chunks[#chunks]
        if not hasSentenceTerminator(last_chunk.raw_text) then
            local next_raw_text, _ = self:extractRawPageText(document, page_num + 1, ui)
            if next_raw_text and #next_raw_text > 0 then
                local cleaned_next = self:sanitize(next_raw_text)
                local head, _ = findSentenceHead(cleaned_next)
                local ok_l, logger = pcall(require, "logger")
                if ok_l and logger and logger.warn then
                    logger.warn(string.format("[TTS STITCH DEBUG] page=%d, last_raw='%s', next_raw='%s', head='%s'",
                        page_num, tostring(last_chunk.raw_text), tostring(cleaned_next:sub(1, 60)), tostring(head)))
                end
                if head and #head > 0 and #head < 250 then
                    local is_hyphen = last_chunk.raw_text:match("%-%s*$")
                    local stitched_raw
                    if is_hyphen then
                        stitched_raw = last_chunk.raw_text:gsub("%-%s*$", "") .. head
                    else
                        -- Prevent word duplication if Crengine repeats the boundary word on page N+1
                        local last_w = last_chunk.raw_text:match("(%S+)%s*$")
                        local first_w = head:match("^%s*(%S+)")
                        if last_w and first_w and last_w:lower() == first_w:lower() then
                            head = head:gsub("^%s*" .. first_w:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. "%s*", "")
                        end
                        stitched_raw = joinText(last_chunk.raw_text, head)
                    end

                    local tts_text = self:normalizePronunciation(stitched_raw)
                    local trimmed = tts_text:gsub("^%s+", ""):gsub("%s+$", "")

                    last_chunk.raw_text = stitched_raw
                    last_chunk.text = trimmed
                    last_chunk.char_count = #trimmed
                    last_chunk.stitched = true
                    last_chunk.stitched_next_page = page_num + 1
                    last_chunk.stitched_head = head

                    self._stitched_heads[page_num + 1] = head
                end
            end
        end
    end

    return chunks
end

-- Export module and constants
TextChunker.DEFAULT_MIN_CHARS = DEFAULT_MIN_CHARS
TextChunker.DEFAULT_MAX_CHARS = DEFAULT_MAX_CHARS

return TextChunker
