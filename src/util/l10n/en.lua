--[[
    src/util/l10n/en.lua - English translation catalog (Canonical source)
--]]

return {
    -- Lifecycle & notification messages
    ["Auto page turn to page %d"]                                           = "Auto page turn to page %d",
    ["Finished reading entire text."]                                      = "Finished reading entire text.",
    ["Audio playback error:\n%s"]                                          = "Audio playback error:\n%s",
    ["Stopped reading."]                                                   = "Stopped reading.",
    ["Stopped reading by sleep timer."]                                    = "Stopped reading by sleep timer.",

    -- Menu items
    ["▶ Read from here"]                                                   = "▶ Read from here",
    ["▶ Read from page start"]                                             = "▶ Read from page start",
    ["⏯ Resume previous session (Page %d · %d)"]                           = "⏯ Resume previous session (Page %d · %d)",
    ["⏲ Sleep timer"]                                                      = "⏲ Sleep timer",
    ["⚙ Plugin settings"]                                                  = "⚙ Plugin settings",
    ["Text-to-Speech"]                                                     = "Text-to-Speech",
    ["🔊 Read with Text-to-Speech"]                                        = "🔊 Read with Text-to-Speech",

    -- Sleep timer dialog & labels
    ["Sleep Timer"]                                                        = "Sleep Timer",
    ["Sleep timer set: %s"]                                                = "Sleep timer set: %s",
    ["Turn off timer"]                                                     = "Turn off timer",
    ["Off"]                                                                = "Off",
    ["15 minutes"]                                                         = "15 minutes",
    ["30 minutes"]                                                         = "30 minutes",
    ["45 minutes"]                                                         = "45 minutes",
    ["When current page finishes"]                                         = "When current page finishes",
    ["Page end"]                                                           = "Page end",
    ["Chapter end"]                                                        = "Chapter end",
    ["Sleep timer: Off"]                                                   = "Sleep timer: Off",
    ["Sleep timer: Page end"]                                              = "Sleep timer: Page end",
    ["Sleep timer: Chapter end"]                                           = "Sleep timer: Chapter end",
    ["Sleep timer: %dm"]                                                   = "Sleep timer: %dm",
    ["Sleep timer: %ds"]                                                   = "Sleep timer: %ds",

    -- Test audio
    ["Welcome to KOReader. This is a test sentence to check server connection and audio playback."] = "Welcome to KOReader. This is a test sentence to check server connection and audio playback.",
    ["Downloading test audio...\n'%s'"]                                    = "Downloading test audio...\n'%s'",
    ["Server audio download error:\n%s"]                                   = "Server audio download error:\n%s",
    ["Test audio playback finished!"]                                      = "Test audio playback finished!",
    ["Playing test audio... [%s]\n'%s'"]                                   = "Playing test audio... [%s]\n'%s'",

    -- Text selection & page preview
    ["(Empty page or no text)"]                                            = "(Empty page or no text)",
    ["Text-to-Speech:\nPage: %d | Total sentences: %d\nSentence 1: %s"]   = "Text-to-Speech:\nPage: %d | Total sentences: %d\nSentence 1: %s",
    ["Downloading selected text:\n'%s'"]                                   = "Downloading selected text:\n'%s'",
    ["Selected text download error:\n%s"]                                  = "Selected text download error:\n%s",
    ["Playing selected text..."]                                           = "Playing selected text...",
    ["Finished reading selected text!"]                                    = "Finished reading selected text!",

    -- Dictionary manager
    ["Pronunciation Dictionary"]                                           = "Pronunciation Dictionary",
    ["Enter original word (abbreviation / difficult word)"]                 = "Enter original word (abbreviation / difficult word)",
    ["Spoken replacement for '%s'"]                                        = "Spoken replacement for '%s'",
    ["Example: Artificial Intelligence"]                                   = "Example: Artificial Intelligence",
    ["Added: %s ➔ %s"]                                                    = "Added: %s ➔ %s",
    ["Dictionary: %s ➔ %s"]                                                = "Dictionary: %s ➔ %s",
    ["Edit pronunciation"]                                                 = "Edit pronunciation",
    ["Edit pronunciation for '%s'"]                                        = "Edit pronunciation for '%s'",
    ["Pronunciation updated successfully!"]                                = "Pronunciation updated successfully!",
    ["Delete this word"]                                                   = "Delete this word",
    ["Deleted mapping for '%s'."]                                          = "Deleted mapping for '%s'.",
    ["+ Add new word"]                                                     = "+ Add new word",
    ["Reset to default dictionary"]                                        = "Reset to default dictionary",
    ["Cleared all custom words, restored default dictionary."]             = "Cleared all custom words, restored default dictionary.",
    ["Back to Settings"]                                                   = "Back to Settings",

    -- Settings
    ["Text-to-Speech Settings"]                                            = "Text-to-Speech Settings",
    ["Speech Server URL"]                                                  = "Speech Server URL",
    ["Authentication Key (API Key)"]                                       = "Authentication Key (API Key)",
    ["Required for OpenAI Cloud. Leave empty for local servers."]          = "Required for OpenAI Cloud. Leave empty for local servers.",
    ["Select Voice"]                                                       = "Select Voice",
    ["Select Audio Format"]                                                = "Select Audio Format",
    ["(Optional - Not set)"]                                               = "(Optional - Not set)",
    ["1. Server URL: %s"]                                                  = "1. Server URL: %s",
    ["2. Authentication (API Key): %s"]                                    = "2. Authentication (API Key): %s",
    ["3. Default Voice: %s"]                                               = "3. Default Voice: %s",
    ["4. Playback Speed: %.1fx"]                                           = "4. Playback Speed: %.1fx",
    ["5. Preload Count: %d sentences"]                                     = "5. Preload Count: %d sentences",
    ["6. Audio Format: %s"]                                                = "6. Audio Format: %s",
    ["7. Test Audio Playback"]                                             = "7. Test Audio Playback",
    ["Server, Voice & Speed Settings"]                                     = "Server, Voice & Speed Settings",
    ["Preload Count (1 - 7)"]                                              = "Preload Count (1 - 7)",
    ["Saved preload count: %d sentences"]                                  = "Saved preload count: %d sentences",
    ["Reading Speed (0.5x - 2.0x)"]                                        = "Reading Speed (0.5x - 2.0x)",
    ["Speed: %.1fx"]                                                       = "Speed: %.1fx",
    ["1. Server, Voice & Speed Settings"]                                  = "1. Server, Voice & Speed Settings",
    ["2. Pronunciation Dictionary"]                                        = "2. Pronunciation Dictionary",
    ["3. Audio Cache Management"]                                          = "3. Audio Cache Management",
    ["Audio Cache Management"]                                             = "Audio Cache Management",
    ["1. Auto-clear Limit: %d MB"]                                         = "1. Auto-clear Limit: %d MB",
    ["2. Clear Audio Cache Now (%.1f MB)"]                                 = "2. Clear Audio Cache Now (%.1f MB)",
    ["Audio Cache Limit"]                                                  = "Audio Cache Limit",
    ["%d MB (Default - Safe for all devices)"]                             = "%d MB (Default - Safe for all devices)",
    ["%d MB"]                                                              = "%d MB",
    ["Saved cache limit: %d MB"]                                           = "Saved cache limit: %d MB",
    ["Cleared audio cache: freed %.1f MB"]                                 = "Cleared audio cache: freed %.1f MB",
    ["Reset to Defaults"]                                                  = "Reset to Defaults",
    ["Settings restored to defaults."]                                     = "Settings restored to defaults.",

    -- Formats
    ["WAV (Default - Raw audio, instant playback)"]                        = "WAV (Default - Raw audio, instant playback)",
    ["FLAC (High quality, saves 70% bandwidth)"]                           = "FLAC (High quality, saves 70% bandwidth)",
    ["MP3 (Common, lightweight, 90% compression)"]                         = "MP3 (Common, lightweight, 90% compression)",
    ["OPUS (Optimal, ultra-lightweight, fastest load)"]                     = "OPUS (Optimal, ultra-lightweight, fastest load)",

    -- Player Widget
    ["Page %d · %d/%d"]                                                    = "Page %d · %d/%d",
    ["Buffer: %s%s"]                                                       = "Buffer: %s%s",
    ["Buffer: ●●"]                                                         = "Buffer: ●●",

    -- Common button labels
    ["Cancel"]                                                             = "Cancel",
    ["Save"]                                                               = "Save",
    ["Close"]                                                              = "Close",
    ["Back"]                                                               = "Back",
    ["Next"]                                                               = "Next",

    -- Service errors
    ["Error downloading audio from server"]                                = "Error downloading audio from server",
    ["Empty text"]                                                         = "Empty text",
    ["Cannot write cache file"]                                            = "Cannot write cache file",
}
