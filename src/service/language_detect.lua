--[[
    language_detect.lua - decide which language a book / page is in, so the plugin can pick
    the voice you set up for that language.

    1. The script of the text being read (Han / kana / Hangul / Cyrillic) is decisive - it is
       what you actually hear, and book metadata is often missing or wrong.
    2. For Latin-script text, the book's metadata language (dc:language) tells French from English etc.
    3. If there is no usable text, fall back to metadata, then to the typography language setting.
--]]

local M = {}

local MIN_LETTERS = 20

local function decode(s, i)
    local b = s:byte(i)
    if b < 0x80 then return b, 1 end
    if b >= 0xF0 then
        return (b % 8) * 262144 + ((s:byte(i + 1) or 0) % 64) * 4096
            + ((s:byte(i + 2) or 0) % 64) * 64 + ((s:byte(i + 3) or 0) % 64), 4
    elseif b >= 0xE0 then
        return (b % 16) * 4096 + ((s:byte(i + 1) or 0) % 64) * 64 + ((s:byte(i + 2) or 0) % 64), 3
    elseif b >= 0xC0 then
        return (b % 32) * 64 + ((s:byte(i + 1) or 0) % 64), 2
    end
    return 0xFFFD, 1
end

--- Count letters per script in a text sample.
function M.count(sample)
    local c = { han = 0, kana = 0, hangul = 0, cyrillic = 0, latin = 0 }
    if type(sample) ~= "string" then return c end
    local i, n = 1, #sample
    while i <= n do
        local cp, len = decode(sample, i)
        if (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF)
            or (cp >= 0xF900 and cp <= 0xFAFF) or (cp >= 0x20000 and cp <= 0x2A6DF) then
            c.han = c.han + 1
        elseif (cp >= 0x3040 and cp <= 0x30FF) or (cp >= 0x31F0 and cp <= 0x31FF) then
            c.kana = c.kana + 1
        elseif (cp >= 0xAC00 and cp <= 0xD7AF) or (cp >= 0x1100 and cp <= 0x11FF) then
            c.hangul = c.hangul + 1
        elseif cp >= 0x0400 and cp <= 0x04FF then
            c.cyrillic = c.cyrillic + 1
        elseif (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122)
            or (cp >= 0xC0 and cp <= 0x24F and cp ~= 0xD7 and cp ~= 0xF7) then
            c.latin = c.latin + 1
        end
        i = i + len
    end
    return c
end

--- "zh" | "ja" | "ko" | "ru" | "latin" | nil (not enough text)
function M.detectScript(sample)
    local c = M.count(sample)
    local total = c.han + c.kana + c.hangul + c.cyrillic + c.latin
    if total < MIN_LETTERS then return nil end
    if c.kana / total >= 0.05 and (c.kana + c.han) / total >= 0.3 then return "ja" end
    if c.hangul / total >= 0.3 then return "ko" end
    if c.han / total >= 0.3 then return "zh" end
    if c.cyrillic / total >= 0.5 then return "ru" end
    return "latin"
end

local ISO3 = {
    zho = "zh", chi = "zh", chs = "zh", cht = "zh", eng = "en", rus = "ru", jpn = "ja", kor = "ko",
    fra = "fr", fre = "fr", deu = "de", ger = "de", spa = "es", vie = "vi",
}
local NONLATIN = { zh = true, ja = true, ko = true, ru = true }

--- "zh-CN" / "zh_Hans" / "eng" / "en-US" -> "zh" / "zh" / "en" / "en"; nil for unknown ("und", "")
function M.fromTag(tag)
    if type(tag) ~= "string" then return nil end
    local base = tag:lower():match("^%s*(%a+)")
    if not base or base == "und" or base == "mul" or base == "zxx" then return nil end
    return ISO3[base] or (#base == 2 and base) or nil
end

--- @return code ("zh","en",...) or nil, source ("text" | "metadata" | "typography")
function M.resolve(sample, meta_tag, typography_tag)
    local script = M.detectScript(sample)
    if script and script ~= "latin" then return script, "text" end

    local meta = M.fromTag(meta_tag)
    local typo = M.fromTag(typography_tag)
    if script == "latin" then
        if meta and not NONLATIN[meta] then return meta, "metadata" end
        if typo and not NONLATIN[typo] then return typo, "typography" end
        return "en", "text"
    end
    if meta then return meta, "metadata" end
    if typo then return typo, "typography" end
    return nil
end

return M
