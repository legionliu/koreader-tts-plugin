--[[
    src/util/l10n/vi.lua - Vietnamese translation catalog
--]]

return {
    -- Lifecycle & notification messages
    ["Auto page turn to page %d"]                                           = "Tự động lật sang trang %d",
    ["Finished reading entire text."]                                      = "Đã đọc xong toàn bộ văn bản.",
    ["Audio playback error:\n%s"]                                          = "Lỗi phát âm thanh:\n%s",
    ["Stopped reading."]                                                   = "Đã dừng đọc.",
    ["Stopped reading by sleep timer."]                                    = "Đã dừng đọc theo hẹn giờ.",

    -- Menu items
    ["▶ Read from here"]                                                   = "▶ Đọc từ đây",
    ["▶ Read from page start"]                                             = "▶ Đọc từ đầu trang này",
    ["⏯ Resume previous session (Page %d · %d)"]                           = "⏯ Đọc tiếp tục phiên trước (Trang %d · %d)",
    ["⏲ Sleep timer"]                                                      = "⏲ Hẹn giờ tắt đọc",
    ["⚙ Plugin settings"]                                                  = "⚙ Cài đặt tiện ích",
    ["Text-to-Speech"]                                                     = "Đọc bằng giọng nói",
    ["🔊 Read with Text-to-Speech"]                                        = "🔊 Đọc bằng giọng nói",

    -- Sleep timer dialog & labels
    ["Sleep Timer"]                                                        = "Hẹn giờ tắt đọc",
    ["Sleep timer set: %s"]                                                = "Đã cài đặt hẹn giờ: %s",
    ["Turn off timer"]                                                     = "Tắt hẹn giờ",
    ["Off"]                                                                = "Tắt",
    ["15 minutes"]                                                         = "15 phút",
    ["30 minutes"]                                                         = "30 phút",
    ["45 minutes"]                                                         = "45 phút",
    ["When current page finishes"]                                         = "Khi đọc hết trang hiện tại",
    ["Page end"]                                                           = "Hết trang",
    ["Chapter end"]                                                        = "Hết chương",
    ["Sleep timer: Off"]                                                   = "Hẹn giờ: Tắt",
    ["Sleep timer: Page end"]                                              = "Hẹn giờ: Hết trang",
    ["Sleep timer: Chapter end"]                                           = "Hẹn giờ: Hết chương",
    ["Sleep timer: %dm"]                                                   = "Hẹn giờ: %dp",
    ["Sleep timer: %ds"]                                                   = "Hẹn giờ: %ds",

    -- Test audio
    ["Welcome to KOReader. This is a test sentence to check server connection and audio playback."] = "Chào mừng bạn đến với KOReader. Đây là câu thử nghiệm kết nối máy chủ và kiểm tra âm thanh.",
    ["Downloading test audio...\n'%s'"]                                    = "Đang tải âm thanh thử nghiệm...\n'%s'",
    ["Server audio download error:\n%s"]                                   = "Lỗi tải âm thanh từ máy chủ:\n%s",
    ["Test audio playback finished!"]                                      = "Đã phát xong câu thử nghiệm!",
    ["Playing test audio... [%s]\n'%s'"]                                   = "Đang phát câu thử nghiệm... [%s]\n'%s'",

    -- Text selection & page preview
    ["(Empty page or no text)"]                                            = "(Trang trống hoặc không có chữ)",
    ["Text-to-Speech:\nPage: %d | Total sentences: %d\nSentence 1: %s"]   = "Đọc giọng nói:\nTrang: %d | Tổng số câu: %d\nCâu 1: %s",
    ["Downloading selected text:\n'%s'"]                                   = "Đang tải đoạn chọn:\n'%s'",
    ["Selected text download error:\n%s"]                                  = "Lỗi tải âm thanh đoạn chọn:\n%s",
    ["Playing selected text..."]                                           = "Đang phát đoạn chọn...",
    ["Finished reading selected text!"]                                    = "Đã đọc xong đoạn văn bản được chọn!",

    -- Dictionary manager
    ["Pronunciation Dictionary"]                                           = "Quản lý từ điển phát âm",
    ["Enter original word (abbreviation / difficult word)"]                 = "Nhập từ gốc (viết tắt / từ khó)",
    ["Spoken replacement for '%s'"]                                        = "Từ đọc thay thế cho '%s'",
    ["Example: Artificial Intelligence"]                                   = "Ví dụ: Trí tuệ nhân tạo",
    ["Added: %s ➔ %s"]                                                    = "Đã thêm: %s ➔ %s",
    ["Dictionary: %s ➔ %s"]                                                = "Từ điển: %s ➔ %s",
    ["Edit pronunciation"]                                                 = "Sửa từ đọc",
    ["Edit pronunciation for '%s'"]                                        = "Sửa cách đọc cho '%s'",
    ["Pronunciation updated successfully!"]                                = "Đã cập nhật cách đọc thành công!",
    ["Delete this word"]                                                   = "Xóa từ này",
    ["Deleted mapping for '%s'."]                                          = "Đã xóa mapping của '%s'.",
    ["+ Add new word"]                                                     = "+ Thêm từ mới",
    ["Reset to default dictionary"]                                        = "Khôi phục từ điển mặc định",
    ["Cleared all custom words, restored default dictionary."]             = "Đã xóa sạch từ tùy biến, khôi phục từ điển mặc định.",
    ["Back to Settings"]                                                   = "Quay lại Cài đặt",

    -- Settings
    ["Text-to-Speech Settings"]                                            = "Cài đặt đọc giọng nói",
    ["Speech Server URL"]                                                  = "Địa chỉ máy chủ âm thanh",
    ["Authentication Key (API Key)"]                                       = "Khóa xác thực (API Key)",
    ["Required for OpenAI Cloud. Leave empty for local servers."]          = "Bắt buộc khi dùng OpenAI Cloud. Để trống nếu dùng server nội bộ.",
    ["Select Voice"]                                                       = "Chọn giọng đọc",
    ["Select Audio Format"]                                                = "Chọn định dạng âm thanh",
    ["(Optional - Not set)"]                                               = "(Tùy chọn - Chưa nhập)",
    ["1. Server URL: %s"]                                                  = "1. Địa chỉ Máy chủ: %s",
    ["2. Authentication (API Key): %s"]                                    = "2. Khóa xác thực (API Key): %s",
    ["3. Default Voice: %s"]                                               = "3. Giọng đọc mặc định: %s",
    ["4. Playback Speed: %.1fx"]                                           = "4. Tốc độ đọc: %.1fx",
    ["5. Preload Count: %d sentences"]                                     = "5. Số câu tải trước: %d câu",
    ["6. Audio Format: %s"]                                                = "6. Định dạng âm thanh: %s",
    ["7. Test Audio Playback"]                                             = "7. Phát thử âm thanh",
    ["Server, Voice & Speed Settings"]                                     = "Cài đặt Máy chủ, Giọng đọc & Tốc độ",
    ["Preload Count (1 - 7)"]                                              = "Số câu tải trước (1 - 7)",
    ["Saved preload count: %d sentences"]                                  = "Đã lưu số câu đệm: %d câu",
    ["Reading Speed (0.5x - 2.0x)"]                                        = "Tốc độ đọc (0.5x - 2.0x)",
    ["Speed: %.1fx"]                                                       = "Tốc độ: %.1fx",
    ["1. Server, Voice & Speed Settings"]                                  = "1. Cài đặt Máy chủ, Giọng đọc & Tốc độ",
    ["2. Pronunciation Dictionary"]                                        = "2. Quản lý từ điển phát âm",
    ["3. Audio Cache Management"]                                          = "3. Quản lý bộ nhớ đệm âm thanh",
    ["Audio Cache Management"]                                             = "Quản lý bộ nhớ đệm âm thanh",
    ["1. Auto-clear Limit: %d MB"]                                         = "1. Giới hạn tự động xóa: %d MB",
    ["2. Clear Audio Cache Now (%.1f MB)"]                                 = "2. Xóa bộ nhớ đệm ngay (%.1f MB)",
    ["Audio Cache Limit"]                                                  = "Giới hạn bộ nhớ đệm âm thanh",
    ["%d MB (Default - Safe for all devices)"]                             = "%d MB (Mặc định - An toàn cho mọi máy)",
    ["%d MB"]                                                              = "%d MB",
    ["Saved cache limit: %d MB"]                                           = "Đã lưu giới hạn bộ nhớ đệm: %d MB",
    ["Cleared audio cache: freed %.1f MB"]                                 = "Đã xóa bộ nhớ đệm: giải phóng %.1f MB",
    ["Reset to Defaults"]                                                  = "Khôi phục mặc định",
    ["Settings restored to defaults."]                                     = "Đã khôi phục cấu hình về mặc định ban đầu.",

    -- Formats
    ["WAV (Default - Raw audio, instant playback)"]                        = "WAV (Mặc định - Âm thanh gốc, phát tức thì)",
    ["FLAC (High quality, saves 70% bandwidth)"]                           = "FLAC (Chất lượng cao, tiết kiệm 70% dung lượng)",
    ["MP3 (Common, lightweight, 90% compression)"]                         = "MP3 (Phổ biến, siêu nhẹ, nén 90%)",
    ["OPUS (Optimal, ultra-lightweight, fastest load)"]                     = "OPUS (Tối ưu nhất, siêu nhẹ, tải nhanh nhất)",

    -- Player Widget
    ["Page %d · %d/%d"]                                                    = "Trang %d · %d/%d",
    ["Buffer: %s%s"]                                                       = "Đệm: %s%s",
    ["Buffer: ●●"]                                                         = "Đệm: ●●",

    -- Common button labels
    ["Cancel"]                                                             = "Hủy",
    ["Save"]                                                               = "Lưu",
    ["Close"]                                                              = "Đóng",
    ["Back"]                                                               = "Quay lại",
    ["Next"]                                                               = "Tiếp tục",

    -- Service errors
    ["Error downloading audio from server"]                                = "Lỗi tải âm thanh từ máy chủ",
    ["Empty text"]                                                         = "Văn bản rỗng",
    ["Cannot write cache file"]                                            = "Không thể ghi file cache",
}
