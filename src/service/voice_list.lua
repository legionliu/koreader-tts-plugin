--[[
    voice_list.lua - fetch / cache / group the voice list of an OpenAI-compatible TTS server
    (tested against travisvn/openai-edge-tts: GET <base>/v1/voices/all)
--]]

local M = {}

-- Which language groups the picker offers (prefix match on the voice's language / name).
M.GROUPS = {
    { id = "zh", title = "Chinese 中文", prefix = "^zh%-" },
    { id = "en", title = "English",      prefix = "^en%-" },
    { id = "ru", title = "Russian",      prefix = "^ru%-" },
}

-- Languages offered in "Voice by book language" (code = ISO 639-1, matches the voice-name prefix)
M.LANGUAGES = {
    { code = "zh", title = "Chinese 中文" },
    { code = "en", title = "English" },
    { code = "ru", title = "Russian" },
    { code = "ja", title = "Japanese" },
    { code = "ko", title = "Korean" },
    { code = "fr", title = "French" },
    { code = "de", title = "German" },
    { code = "es", title = "Spanish" },
    { code = "vi", title = "Vietnamese" },
}

--- voices whose language/name starts with "<code>-" (e.g. "zh" -> zh-CN, zh-TW, zh-HK ...)
function M.filterByLang(list, code)
    local out = {}
    local prefix = "^" .. code .. "%-"
    for _, v in ipairs(list) do
        if (v.language or ""):find(prefix) or v.name:find(prefix) then out[#out + 1] = v end
    end
    return out
end

-- Built-in fallback (used only if the server list can't be fetched and nothing is cached).
local BUILTIN = {
    { "zh-CN", "Xiaoxiao", "Female" }, { "zh-CN", "Xiaoyi", "Female" },
    { "zh-CN", "Yunjian", "Male" },    { "zh-CN", "Yunxi", "Male" },
    { "zh-CN", "Yunxia", "Male" },     { "zh-CN", "Yunyang", "Male" },
    { "zh-CN", "liaoning-Xiaobei", "Female" }, { "zh-CN", "shaanxi-Xiaoni", "Female" },
    { "zh-TW", "HsiaoChen", "Female" }, { "zh-TW", "HsiaoYu", "Female" }, { "zh-TW", "YunJhe", "Male" },
    { "zh-HK", "HiuGaai", "Female" },  { "zh-HK", "HiuMaan", "Female" }, { "zh-HK", "WanLung", "Male" },
    { "en-US", "Ava", "Female" }, { "en-US", "Emma", "Female" }, { "en-US", "Aria", "Female" },
    { "en-US", "Jenny", "Female" }, { "en-US", "Michelle", "Female" }, { "en-US", "AvaMultilingual", "Female" },
    { "en-US", "Andrew", "Male" }, { "en-US", "Brian", "Male" }, { "en-US", "Christopher", "Male" },
    { "en-US", "Eric", "Male" }, { "en-US", "Guy", "Male" }, { "en-US", "Roger", "Male" },
    { "en-US", "AndrewMultilingual", "Male" }, { "en-US", "BrianMultilingual", "Male" },
    { "en-GB", "Libby", "Female" }, { "en-GB", "Maisie", "Female" }, { "en-GB", "Sonia", "Female" },
    { "en-GB", "Ryan", "Male" }, { "en-GB", "Thomas", "Male" },
    { "en-AU", "Natasha", "Female" }, { "en-AU", "William", "Male" },
    { "en-CA", "Clara", "Female" }, { "en-CA", "Liam", "Male" },
    { "en-IN", "Neerja", "Female" }, { "en-IN", "Prabhat", "Male" },
    { "ru-RU", "Svetlana", "Female" }, { "ru-RU", "Dmitry", "Male" },
}

function M.builtin()
    local list = {}
    for _, e in ipairs(BUILTIN) do
        list[#list + 1] = { name = e[1] .. "-" .. e[2] .. "Neural", language = e[1], gender = e[3] }
    end
    return list
end

--- "https://host:8000/v1/audio/speech" -> "https://host:8000/v1/voices/all"
function M.voicesUrl(server_url)
    if type(server_url) ~= "string" or server_url == "" then return nil end
    local base = server_url:gsub("/+$", ""):gsub("/audio/speech$", "")
    if base:find("/v1$") then
        return base .. "/voices/all"
    end
    return base .. "/v1/voices/all"
end

--- Tolerant parser: no JSON library needed. Accepts {"voices":[{name|id, language, gender}, ...]}
function M.parse(body)
    local list, seen = {}, {}
    if type(body) ~= "string" then return list end
    for obj in body:gmatch("{[^{}]*}") do
        local name = obj:match('"name"%s*:%s*"([^"]+)"') or obj:match('"id"%s*:%s*"([^"]+)"')
        if name and not seen[name] then
            seen[name] = true
            local lang = obj:match('"language"%s*:%s*"([^"]+)"') or name:match("^(%a+%-%a+)%-")
            local gender = obj:match('"gender"%s*:%s*"([^"]+)"')
            list[#list + 1] = { name = name, language = lang or "other", gender = gender }
        end
    end
    return list
end

local LANG_ORDER = { "zh-CN", "zh-TW", "zh-HK", "en-US", "en-GB", "en-AU", "en-CA", "en-IN", "ru-RU" }
local function lang_rank(lang)
    for i, l in ipairs(LANG_ORDER) do if l == lang then return i end end
    return 100
end

function M.sort(list)
    table.sort(list, function(a, b)
        local ra, rb = lang_rank(a.language), lang_rank(b.language)
        if ra ~= rb then return ra < rb end
        if a.language ~= b.language then return a.language < b.language end
        return a.name < b.name
    end)
    return list
end

--- voices belonging to group id ("zh","en","ru") or "all"
function M.filter(list, group_id)
    if group_id == "all" then return list end
    local prefix
    for _, g in ipairs(M.GROUPS) do if g.id == group_id then prefix = g.prefix end end
    local out = {}
    for _, v in ipairs(list) do
        if prefix and ((v.language or ""):find(prefix) or v.name:find(prefix)) then out[#out + 1] = v end
    end
    return out
end

--- "zh-CN-XiaoxiaoNeural" -> "Xiaoxiao (F)"
function M.shortName(v)
    local n = v.name:gsub("^%a+%-%a+%-", ""):gsub("Neural$", "")
    local g = (v.gender == "Female" and " (F)") or (v.gender == "Male" and " (M)") or ""
    return n .. g
end

-- ---------------------------------------------------------------- HTTP / cache
local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
end

local function write_file(path, data)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

--- blocking GET (short timeout). Returns body or nil, err. Overridable for tests: M.http_get = fn
function M.http_get(url, api_key, timeout)
    local ok_h, http = pcall(require, "socket.http")
    local ok_l, ltn12 = pcall(require, "ltn12")
    if not (ok_h and ok_l) then return nil, "socket.http unavailable" end
    local client = http
    if url:match("^https://") then
        local ok_s, https = pcall(require, "ssl.https")
        if not ok_s then return nil, "ssl.https unavailable" end
        client = https
    end
    local headers = {}
    if api_key and api_key ~= "" then headers["Authorization"] = "Bearer " .. api_key end
    local chunks = {}
    local old_timeout = http.TIMEOUT
    http.TIMEOUT = timeout or 10
    local ok, r1, code = pcall(client.request, {
        url = url, method = "GET", headers = headers, sink = ltn12.sink.table(chunks),
    })
    http.TIMEOUT = old_timeout
    if not ok then return nil, tostring(r1) end
    if code ~= 200 then return nil, "HTTP " .. tostring(code) end
    return table.concat(chunks)
end

--- Returns list, source ("server" | "cache" | "builtin"), err
function M.load(server_url, api_key, cache_dir, timeout)
    local cache_path = (cache_dir or "cache/tts") .. "_voices.json"
    local url = M.voicesUrl(server_url)
    local err
    if url then
        local body, e = M.http_get(url, api_key, timeout or 10)
        if body then
            local list = M.parse(body)
            if #list > 0 then
                write_file(cache_path, body)
                return M.sort(list), "server"
            end
            e = "empty voice list"
        end
        err = e
    end
    local cached = read_file(cache_path)
    if cached then
        local list = M.parse(cached)
        if #list > 0 then return M.sort(list), "cache", err end
    end
    return M.sort(M.builtin()), "builtin", err
end

return M
