--[[
    _meta.lua - KOReader Plugin Metadata
    Plugin: koreader_tts
    Category: read
--]]

local ok, _ = pcall(require, "src.util.i18n")
if not ok or type(_) ~= "function" then
    local ok_gt, gt = pcall(require, "gettext")
    if ok_gt and type(gt) == "function" then
        _ = gt
    else
        _ = function(msg) return msg end
    end
end

return {
    name = "koreader_tts",
    fullname = _("TTS Reader"),
    description = _("Read books aloud via OpenAI-compatible REST API"),
    category = "read",
    version = "0.0.1",
}
