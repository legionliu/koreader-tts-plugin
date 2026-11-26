--[[
    ui_player.lua - Native UI & Visual Sync for KOReader TTS Plugin
    Features:
      - Floating Control Bar anchored to bottom of screen (E-ink optimized)
      - Mini Floating Bubble mode
      - Real-time sentence highlighting with partial E-ink refresh
      - Two-way synchronization with PlaybackQueue
--]]

local ok_wc, WidgetContainer = pcall(require, "ui/widget/container/widgetcontainer")
if not ok_wc or not WidgetContainer then
    WidgetContainer = require("ui/widget/widgetcontainer")
end
local UIManager = require("ui/uimanager")

local ok_log, logger = pcall(require, "logger")
if not ok_log or not logger then
    logger = {
        warn = function(...) end,
        info = function(...) end,
        dbg = function(...) end,
        err = function(...) end,
    }
end

local ok_frame, FrameContainer = pcall(require, "ui/widget/container/framecontainer")
if not ok_frame or not FrameContainer then
    ok_frame, FrameContainer = pcall(require, "ui/widget/framecontainer")
end
if not ok_frame or not FrameContainer then
    FrameContainer = WidgetContainer
end

local ok_vg, VerticalGroup = pcall(require, "ui/widget/verticalgroup")
if not ok_vg then VerticalGroup = WidgetContainer end

local ok_hg, HorizontalGroup = pcall(require, "ui/widget/horizontalgroup")
if not ok_hg then HorizontalGroup = WidgetContainer end

local ok_btn, Button = pcall(require, "ui/widget/button")
if not ok_btn then Button = WidgetContainer end

local ok_bd, ButtonDialog = pcall(require, "ui/widget/buttondialog")
if not ok_bd or not ButtonDialog then ButtonDialog = WidgetContainer end

local ok_id, InputDialog = pcall(require, "ui/widget/inputdialog")
if not ok_id or not InputDialog then InputDialog = WidgetContainer end

local ok_text, TextWidget = pcall(require, "ui/widget/textwidget")
if not ok_text then TextWidget = WidgetContainer end

local ok_bc, BottomContainer = pcall(require, "ui/widget/container/bottomcontainer")
if not ok_bc or not BottomContainer then BottomContainer = WidgetContainer end

-- Start as the small bubble (tap its label to expand to the full toolbar)
-- Button:setText(text) without a width resets the button to its natural width, which made the
-- fixed-width toolbar buttons shrink after use. Always pass the width back in.
local function setBtnText(btn, text)
    if btn and btn.setText then
        btn:setText(text, btn.width)
    end
end

local START_MINI = true

-- Translucent card support (KOReader's AlphaContainer). Used only when opacity < 100%.
-- It paints its child into a private buffer, so children report positions relative to that buffer;
-- we remember where the container itself was painted and add that offset when hit-testing taps.
local ok_alpha, AlphaContainer = pcall(require, "ui/widget/container/alphacontainer")
local TranslucentContainer = nil
if ok_alpha and AlphaContainer and AlphaContainer.extend then
    TranslucentContainer = AlphaContainer:extend{}
    function TranslucentContainer:paintTo(bb, x, y)
        self.origin_x, self.origin_y = x, y
        AlphaContainer.paintTo(self, bb, x, y)
    end
end

local ok_hspan, HorizontalSpan = pcall(require, "ui/widget/horizontalspan")
if not ok_hspan or not HorizontalSpan then
    HorizontalSpan = WidgetContainer:extend{
        width = 0,
        getSize = function(self) return { w = self.width or 0, h = 0 } end,
    }
end

local ok_vspan, VerticalSpan = pcall(require, "ui/widget/verticalspan")
if not ok_vspan or not VerticalSpan then
    VerticalSpan = WidgetContainer:extend{
        width = 0,
        getSize = function(self) return { w = 0, h = self.width or 0 } end,
    }
end

local ok_geom, Geom = pcall(require, "ui/geometry")
if not ok_geom or not Geom then
    Geom = {
        new = function(self, o) return o or {} end,
    }
end

local ok_blit, Blitbuffer = pcall(require, "ffi/blitbuffer")
if not ok_blit or not Blitbuffer then
    Blitbuffer = {
        COLOR_WHITE  = 0xFFFFFF,
        COLOR_BLACK  = 0x000000,
        COLOR_GRAY_E = 0xEEEEEE,
    }
end

local ok_dev, Device = pcall(require, "device")
local Screen = (ok_dev and Device and Device.screen) or _G.Screen
if not Screen then
    local ok_s, S = pcall(require, "device/screen")
    Screen = ok_s and S or {
        getWidth = function() return 600 end,
        getHeight = function() return 800 end,
        scaleBySize = function(self, px) return px end,
    }
end

local ok_size, Size = pcall(require, "ui/size")
if not ok_size or not Size then
    Size = {
        border = { thin = 1, medium = 2 },
        padding = { default = 5 },
    }
end

local ok_i18n, _ = pcall(require, "src.util.i18n")
if not ok_i18n or type(_) ~= "function" then
    local ok_gettext, gt = pcall(require, "gettext")
    if ok_gettext and type(gt) == "function" then
        _ = gt
    else
        _ = function(msg) return msg end
    end
end

local ok_font, Font = pcall(require, "ui/font")
if not ok_font or not Font then
    Font = {
        getFace = function(self, name, size)
            return {
                size = size or 14,
                is_real_bold = false,
                ftsize = {
                    getHeightAndAscender = function() return size or 14 end
                }
            }
        end
    }
end

local ok_timer, SleepTimer = pcall(require, "src.service.sleep_timer")
if not ok_timer then
    SleepTimer = require("sleep_timer")
end

local ok_ch, CanvasHighlight = pcall(require, "src.ui.canvas_highlight")
if not ok_ch then
    CanvasHighlight = require("canvas_highlight")
end

local PlayerWidget = WidgetContainer:extend{
    name = "koreader_tts_player_widget",
}
PlayerWidget.__index = PlayerWidget
local UIPlayer = PlayerWidget

-- Playback speed presets for cycling
local SPEED_LEVELS = { 0.8, 1.0, 1.2, 1.5, 2.0 }

--- Initialize PlayerWidget instance
function PlayerWidget:new(opts)
    local instance = setmetatable({}, self)
    opts = opts or {}

    instance.ui = opts.ui
    instance.view = opts.view or (opts.ui and opts.ui.view)
    instance.playback_queue = opts.playback_queue
    instance.settings = opts.settings
    instance.audio_backend = opts.audio_backend
    instance.chunker = opts.chunker
    instance.highlighter = opts.highlighter or CanvasHighlight:new()
    instance.get_voice = opts.get_voice               -- function() -> voice name in use
    instance.on_voice = opts.on_voice                 -- function() -> open the voice dialog

    instance.visible = false
    instance.is_mini = START_MINI
    instance.current_highlight = nil

    instance.current_page = 1
    instance.current_index = 1
    instance.total_on_page = 1

    -- Sleep Timer integration
    instance.sleep_timer = opts.sleep_timer or SleepTimer:new{
        uimanager = UIManager,
        on_timeout = function(reason)
            if instance.playback_queue then
                instance.playback_queue:stop()
            end
            instance:hide()
            local ok_info, InfoMessage = pcall(require, "ui/widget/infomessage")
            if ok_info and InfoMessage then
                UIManager:show(InfoMessage:new{
                    text = _("Stopped reading by sleep timer."),
                    timeout = 3,
                })
            end
        end,
        on_tick = function(rem)
            if instance.sleep_timer_btn and instance.sleep_timer_btn.setText and rem % 60 == 0 then
                setBtnText(instance.sleep_timer_btn, instance.sleep_timer:getDisplayText())
            end
        end,
    }

    -- Widget references
    instance.control_bar = nil
    instance.mini_bubble = nil
    instance.title_widget = nil
    instance.play_pause_btn = nil
    instance.mini_play_btn = nil
    instance.mini_label_btn = nil
    instance.speed_btn = nil
    instance.sleep_timer_btn = nil
    instance.buffer_status_widget = nil

    return instance
end

--- Show UI player (full bar or mini bubble based on current mode)
function UIPlayer:show()
    self.visible = true
    if self.is_mini then
        self:showMiniBubble()
    else
        self:showControlBar()
    end
end

--- Hide UI player completely and clear highlights
function UIPlayer:hide()
    self.visible = false
    self.is_mini = START_MINI
    self:hideControlBar()
    self:hideMiniBubble()
    self:clearHighlight()
end

--- Toggle between full control bar and mini floating bubble
function UIPlayer:toggleMode()
    if self.is_mini then
        self.is_mini = false
        self:hideMiniBubble()
        self:showControlBar()
    else
        self.is_mini = true
        self:hideControlBar()
        self:showMiniBubble()
    end
end

--- Show Floating Control Bar anchored to bottom of screen
--- "p59, 3/6": page, and sentence position on that page. The page number tells you at a glance
-- whether a page jump took effect (the book percentage is in KOReader's own status bar).
function UIPlayer:_progressText()
    return string.format(_("p%d, %d/%d"), self.current_page or 1, self.current_index or 1, self.total_on_page or 1)
end

--- Text of the mini bubble label: "3/6 · 1.0x"
function UIPlayer:_miniLabelText(index, total, speed)
    return string.format("%d/%d · %.1fx", index or 1, total or 1, speed or 1.0)
end

function UIPlayer:_refreshTitle()
    if self.title_widget and self.title_widget.setText then
        self.title_widget:setText(self:_progressText())
    end
    self:_layoutHeaderSpaceBetween()
end

--- "Voice: Xiaoxiao" for zh-CN-XiaoxiaoNeural, "Voice: alloy" for alloy
function UIPlayer:_voiceLabel(voice)
    voice = voice or (self.get_voice and self.get_voice()) or ""
    local short = voice:gsub("^%a+%-%a+%-", ""):gsub("Neural$", "")
    if short == "" then return _("Voice") end
    return string.format(_("Voice: %s"), short)
end

--- Called by the plugin when the voice in use changes
function UIPlayer:setVoiceLabel(voice)
    self._voice_full = self:_voiceLabel(voice)
    if self.voice_btn and self.voice_btn.setText then
        setBtnText(self.voice_btn, self._voice_full)
    end
    self:_layoutHeaderSpaceBetween()
end

function UIPlayer:showControlBar()
    if self.control_bar then
        UIManager:close(self.control_bar)
    end

    local this = self
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    -- Available inner width: screen minus card padding/border and a safe margin on both sides.
    -- Every row is sized to fit this, so nothing can run off the screen edges.
    local card_pad = 8
    local card_border = Size.border.thin or 1
    local side_margin = (Screen.scaleBySize and Screen:scaleBySize(10)) or 10
    local avail_w = screen_w - 2 * (card_pad + card_border) - 2 * side_margin
    self.layout_w = avail_w
    local gap = 6
    local nav_btn_w = math.floor((avail_w - 4 * gap) / 5)
    local row3_w = avail_w - 2 * gap
    local speed_btn_w = math.floor(row3_w * 0.28)
    local sleep_btn_w = math.floor(row3_w * 0.36)
    local voice_btn_w = row3_w - speed_btn_w - sleep_btn_w

    -- 1. Row 1: Header (Progress title, Buffer status, [—], [✕])
    self.title_widget = TextWidget:new{
        text = self:_progressText(),
        face = Font:getFace("cfont", 16),
        bold = true,
    }

    -- Buffer dots: ● = sentence downloaded and ready, ○ = still to come (one per preloaded sentence)
    self.buffer_status_widget = TextWidget:new{
        text = self._buf_short or "●●",
        face = Font:getFace("cfont", 16),
    }

    self._voice_full = self:_voiceLabel()
    self.voice_btn = Button:new{
        text = self._voice_full,
        bordersize = Size.border.thin or 1,
        width = voice_btn_w,
        callback = function()
            if this.on_voice then this.on_voice() end
        end,
    }

    local btn_minimize = Button:new{
        text = "  —  ",
        bordersize = 0,
        padding = 4,
        callback = function()
            this:toggleMode()
        end,
    }
    self.btn_minimize = btn_minimize

    local btn_close = Button:new{
        text = "  ✕  ",
        bordersize = 0,
        padding = 4,
        callback = function()
            this:onClose()
        end,
    }
    self.btn_close = btn_close

    local actions_group = HorizontalGroup:new{
        align = "center",
        btn_minimize,
        HorizontalSpan:new{ width = 6 },
        btn_close,
    }
    self.header_actions = actions_group

    self.header_span1 = HorizontalSpan:new{ width = 28 }
    self.header_span2 = HorizontalSpan:new{ width = 28 }

    local header_row = HorizontalGroup:new{
        align = "center",
        self.title_widget,
        self.header_span1,
        self.buffer_status_widget,
        self.header_span2,
        actions_group,
    }
    self.header_row = header_row

    -- 2. Row 2: Navigation controls & Quick settings
    local btn_prev_page = Button:new{
        text = " |< ",
        bordersize = Size.border.thin or 1,
        width = nav_btn_w,
        padding = 6,
        callback = function()
            this:onPrevPage()
        end,
    }
    self.btn_prev_page = btn_prev_page

    local btn_prev_chunk = Button:new{
        text = " << ",
        bordersize = Size.border.thin or 1,
        width = nav_btn_w,
        padding = 6,
        callback = function()
            this:onPrevChunk()
        end,
    }
    self.btn_prev_chunk = btn_prev_chunk

    local is_playing = self.playback_queue and (self.playback_queue:getState() == "PLAYING")
    self.play_pause_btn = Button:new{
        text = is_playing and "  ||  " or "  ▶  ",
        bordersize = Size.border.thin or 1,
        width = nav_btn_w,
        padding = 10,
        callback = function()
            this:onTogglePlayPause()
        end,
    }

    local btn_next_chunk = Button:new{
        text = " >> ",
        bordersize = Size.border.thin or 1,
        width = nav_btn_w,
        padding = 6,
        callback = function()
            this:onNextChunk()
        end,
    }
    self.btn_next_chunk = btn_next_chunk

    local btn_next_page = Button:new{
        text = " >| ",
        bordersize = Size.border.thin or 1,
        width = nav_btn_w,
        padding = 6,
        callback = function()
            this:onNextPage()
        end,
    }
    self.btn_next_page = btn_next_page

    local cur_speed = self.audio_backend and self.audio_backend.speed or 1.0
    self.speed_btn = Button:new{
        text = string.format(_("Speed: %.1fx"), cur_speed),
        bordersize = Size.border.thin or 1,
        width = speed_btn_w,
        padding = 6,
        callback = function()
            this:showSpeedDialog()
        end,
    }

    self.sleep_timer_btn = Button:new{
        text = self.sleep_timer and self.sleep_timer:getDisplayText() or _("Sleep timer: Off"),
        bordersize = Size.border.thin or 1,
        width = sleep_btn_w,
        padding = 6,
        callback = function()
            this:showSleepTimerDialog()
        end,
    }

    -- Row 2: navigation buttons (5 equal-width buttons)
    local controls_row = HorizontalGroup:new{
        align = "center",
        btn_prev_page,
        HorizontalSpan:new{ width = gap },
        btn_prev_chunk,
        HorizontalSpan:new{ width = gap },
        self.play_pause_btn,
        HorizontalSpan:new{ width = gap },
        btn_next_chunk,
        HorizontalSpan:new{ width = gap },
        btn_next_page,
    }
    self.controls_row = controls_row

    -- Row 3: quick settings - speed, sleep timer, voice
    local settings_row = HorizontalGroup:new{
        align = "center",
        self.speed_btn,
        HorizontalSpan:new{ width = gap },
        self.sleep_timer_btn,
        HorizontalSpan:new{ width = gap },
        self.voice_btn,
    }
    self.settings_row = settings_row

    local content_group = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = 4 },
        header_row,
        VerticalSpan:new{ width = 8 },
        controls_row,
        VerticalSpan:new{ width = 6 },
        settings_row,
        VerticalSpan:new{ width = 4 },
    }
    self.content_group = content_group

    -- Compute space-between gap for header row before rendering
    self:_layoutHeaderSpaceBetween()

    local card = FrameContainer:new{
        margin = 0,
        bordersize = Size.border.thin or 1,
        background = Blitbuffer.COLOR_WHITE,
        padding = card_pad,
        radius = (TranslucentContainer and self:_opacity("player_opacity_full", 100) < 100) and 0 or 6,
        content_group,
    }
    self.card_container = card

    local screen_geom = (Screen and type(Screen.getSize) == "function" and Screen:getSize()) or Geom:new{ w = screen_w, h = screen_h }
    self.control_bar = BottomContainer:new{
        dimen = screen_geom,
        self:_translucent(card, self:_opacity("player_opacity_full", 100), "full_alpha"),
    }

    -- Direct hit-testing gesture handler: guarantees taps are intercepted reliably with generous touch padding
    self.control_bar.handleEvent = function(cbar, event)
        for i = #cbar, 1, -1 do
            if cbar[i] and cbar[i].handleEvent and cbar[i]:handleEvent(event) then
                return true
            end
        end

        local arg1 = event.args and event.args[1]
        local is_gesture = event.handler == "onGesture" or (type(arg1) == "table" and arg1.ges)
        if is_gesture then
            local ges = type(arg1) == "table" and arg1 or nil
            if ges and ges.pos then
                local pos = ges.pos
                if ges.ges == "tap" then
                    -- Priority 1: Play/Pause button with 20px touch margin
                    if this:_isTapOnWidget(pos, this.play_pause_btn, 20) then
                        this:onTogglePlayPause()
                        return true
                    end
                    if this:_isTapOnWidget(pos, this.btn_close, 16) then
                        this:onClose()
                        return true
                    end
                    if this:_isTapOnWidget(pos, this.btn_prev_chunk, 16) then
                        this:onPrevChunk()
                        return true
                    end
                    if this:_isTapOnWidget(pos, this.btn_next_chunk, 16) then
                        this:onNextChunk()
                        return true
                    end
                    if this:_isTapOnWidget(pos, this.btn_prev_page, 16) then
                        this:onPrevPage()
                        return true
                    end
                    if this:_isTapOnWidget(pos, this.btn_next_page, 16) then
                        this:onNextPage()
                        return true
                    end
                    if this:_isTapOnWidget(pos, this.speed_btn, 16) then
                        this:showSpeedDialog()
                        return true
                    end
                    if this:_isTapOnWidget(pos, this.sleep_timer_btn, 16) then
                        this:showSleepTimerDialog()
                        return true
                    end
                    if this:_isTapOnWidget(pos, this.voice_btn, 12) then
                        if this.on_voice then this.on_voice() end
                        return true
                    end
                    if this:_isTapOnWidget(pos, this.btn_minimize, 16) then
                        this:toggleMode()
                        return true
                    end
                end

                -- Absorb any tap or touch inside the player card frame so it never leaks to reader gestures
                if this:_isTapOnWidget(pos, this.card_container, 0) then
                    return true
                end
            end
        end
        return false
    end

    UIManager:show(self.control_bar)
    self:_updateBufferStatus()
    -- translucent: repaint the page under the card too, so leftovers of the previous toolbar
    -- (e.g. the small bubble) do not show through or add to the opacity
    if self.full_alpha then self:_setBarDirty() end
end

--- Screen rectangle of the card (BottomContainer: centered horizontally, bottom aligned)
function UIPlayer:_barRegion(card)
    if not card or not card.getSize then return nil end
    local ok, size = pcall(card.getSize, card)
    if not ok or not size or not size.w or not size.h then return nil end
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    return Geom:new{ x = math.floor((sw - size.w) / 2), y = sh - size.h, w = size.w, h = size.h }
end

--- Top edge (screen y) of the full toolbar card, used to keep sentence highlights above it
function UIPlayer:_barTop()
    local region = self:_barRegion(self.card_container)
    if region then return region.y end
    return self.card_container and self.card_container.dimen and self.card_container.dimen.y
end

--- Ask KOReader to repaint the toolbar. A translucent card must also repaint everything under it
-- ("all"): repainting only the card would blend it over its own previous pixels again and again,
-- so it would slowly turn opaque.
function UIPlayer:_setBarDirty()
    if not (UIManager and UIManager.setDirty) then return end
    if self.control_bar then
        if self.full_alpha then
            pcall(UIManager.setDirty, UIManager, "all", "ui", self:_barRegion(self.card_container))
        else
            pcall(UIManager.setDirty, UIManager, self.control_bar, "ui")
        end
    elseif self.mini_bubble then
        if self.mini_alpha then
            pcall(UIManager.setDirty, UIManager, "all", "ui", self:_barRegion(self.mini_card_container))
        else
            pcall(UIManager.setDirty, UIManager, self.mini_bubble, "ui")
        end
    end
end

--- Wrap a card in a translucent container when opacity < 100%, else return it unchanged
function UIPlayer:_translucent(card, percent, slot)
    percent = tonumber(percent) or 100
    self[slot] = nil
    if percent >= 100 or not TranslucentContainer then
        return card
    end
    local wrapper = TranslucentContainer:new{ alpha = percent / 100, card }
    self[slot] = wrapper
    return wrapper
end

function UIPlayer:_opacity(key, default)
    local v = self.settings and self.settings:get(key)
    return tonumber(v) or default
end

--- Rebuild whichever toolbar is on screen (after the opacity setting changed)
function UIPlayer:refreshBars()
    if not self.visible then return end
    if self.is_mini then
        self:hideMiniBubble()
        self:showMiniBubble()
    else
        self:hideControlBar()
        self:showControlBar()
    end
end

function UIPlayer:_isMiniWidget(widget)
    return widget ~= nil and (widget == self.mini_play_btn or widget == self.mini_label_btn
        or widget == self.mini_card_container)
end

--- Hit test a screen position against a widget's rendered dimensions
function UIPlayer:_isTapOnWidget(pos, widget, custom_pad)
    if not widget or not pos then return false end
    local d = widget.dimen or (widget[1] and widget[1].dimen)
    if not d or not d.x or not d.y or not d.w or not d.h then return false end
    local pad = custom_pad or 24
    -- Inside a translucent container, positions are relative to its private buffer
    local wrapper = self:_isMiniWidget(widget) and self.mini_alpha or self.full_alpha
    local ox = (wrapper and wrapper.origin_x) or 0
    local oy = (wrapper and wrapper.origin_y) or 0
    local x, y = d.x + ox, d.y + oy
    return pos.x >= (x - pad) and pos.x <= (x + d.w + pad)
        and pos.y >= (y - pad) and pos.y <= (y + d.h + pad)
end

--- Recalculate header row layout like CSS 'justify-content: space-between'
function UIPlayer:_layoutHeaderSpaceBetween()
    if not self.controls_row or not self.header_row or not self.header_span1 or not self.header_span2 then
        return
    end

    local function wid(w, default)
        return (w and w.getSize and w:getSize().w) or default
    end

    local total_w = self.layout_w or wid(self.controls_row, 460)
    local w_title = wid(self.title_widget, 120)
    local w_dots = wid(self.buffer_status_widget, 60)
    local w_actions = wid(self.header_actions, 60)

    local free_space = total_w - (w_title + w_dots + w_actions)
    local gap = math.max(4, math.floor(free_space / 2))

    self.header_span1.width = gap
    self.header_span2.width = gap

    if self.header_row.resetLayout then
        self.header_row:resetLayout()
    end
    if self.content_group and self.content_group.resetLayout then
        self.content_group:resetLayout()
    end
end

--- Hide Floating Control Bar
function UIPlayer:hideControlBar()
    if self.control_bar then
        UIManager:close(self.control_bar)
        self.control_bar = nil
        self.play_pause_btn = nil
        self.speed_btn = nil
        self.sleep_timer_btn = nil
        self.title_widget = nil
        self.buffer_status_widget = nil
        self.btn_minimize = nil
        self.btn_close = nil
        self.btn_prev_page = nil
        self.btn_prev_chunk = nil
        self.btn_next_chunk = nil
        self.btn_next_page = nil
        self.card_container = nil
        self.full_alpha = nil
        self.header_row = nil
        self.header_span1 = nil
        self.header_span2 = nil
        self.header_actions = nil
        self.controls_row = nil
        self.settings_row = nil
        self.content_group = nil
    end
end

--- Show Mini Floating Bubble in bottom-right corner
function UIPlayer:showMiniBubble()
    if self.mini_bubble then
        UIManager:close(self.mini_bubble)
    end

    local this = self
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    local is_playing = self.playback_queue and (self.playback_queue:getState() == "PLAYING")
    self.mini_play_btn = Button:new{
        text = is_playing and " || " or " ▶ ",
        bordersize = 0,
        padding = 4,
        callback = function()
            this:onTogglePlayPause()
        end,
    }

    local cur_speed = self.audio_backend and self.audio_backend.speed or 1.0
    self.mini_label_btn = Button:new{
        text = self:_miniLabelText(self.current_index, self.total_on_page, cur_speed),
        bordersize = 0,
        padding = 4,
        callback = function()
            -- Tap text label to restore full control bar
            this:toggleMode()
        end,
    }

    local bubble_group = HorizontalGroup:new{
        align = "center",
        self.mini_play_btn,
        HorizontalSpan:new{ width = 6 },
        self.mini_label_btn,
    }

    local card = FrameContainer:new{
        bordersize = Size.border.thin or 1,
        background = Blitbuffer.COLOR_WHITE,
        padding = 6,
        radius = (TranslucentContainer and self:_opacity("player_opacity_mini", 100) < 100) and 0 or 4,
        bubble_group,
    }
    self.mini_card_container = card

    local screen_geom = (Screen and type(Screen.getSize) == "function" and Screen:getSize()) or Geom:new{ w = screen_w, h = screen_h }
    self.mini_bubble = BottomContainer:new{
        dimen = screen_geom,
        self:_translucent(card, self:_opacity("player_opacity_mini", 100), "mini_alpha"),
    }

    self.mini_bubble.handleEvent = function(mb, event)
        for i = #mb, 1, -1 do
            if mb[i] and mb[i].handleEvent and mb[i]:handleEvent(event) then
                return true
            end
        end

        local arg1 = event.args and event.args[1]
        local is_gesture = event.handler == "onGesture" or (type(arg1) == "table" and arg1.ges)
        if is_gesture then
            local ges = type(arg1) == "table" and arg1 or nil
            if ges and ges.pos then
                local pos = ges.pos
                if ges.ges == "tap" then
                    if this:_isTapOnWidget(pos, this.mini_play_btn, 24) then
                        this:onTogglePlayPause()
                        return true
                    end
                    -- Tapping anywhere else on the mini bubble expands back to full control bar
                    if this:_isTapOnWidget(pos, this.mini_card_container, 0) then
                        this:toggleMode()
                        return true
                    end
                end

                if this:_isTapOnWidget(pos, this.mini_card_container, 0) then
                    return true
                end
            end
        end
        return false
    end

    UIManager:show(self.mini_bubble)
    if self.mini_alpha then self:_setBarDirty() end
end

--- Hide Mini Floating Bubble
function UIPlayer:hideMiniBubble()
    if self.mini_bubble then
        UIManager:close(self.mini_bubble)
        self.mini_bubble = nil
        self.mini_play_btn = nil
        self.mini_label_btn = nil
        self.mini_card_container = nil
        self.mini_alpha = nil
    end
end

-- =========================================================================
-- SENTENCE HIGHLIGHTING (E-INK FRIENDLY)
-- =========================================================================

--- Highlight current sentence using partial refresh (delegated to CanvasHighlight)
-- @param bboxes Array of bounding box tables { x, y, w, h }
-- @param mode Highlight mode: "gray" | "underline" | "none"
-- @param chunk Optional Chunk table { text, raw_text, page, ... }
function UIPlayer:highlightSentence(bboxes, mode, chunk)
    mode = mode or (self.settings and self.settings:get("highlight_mode")) or "gray"
    if self.highlighter then
        local ctx = {
            ui = self.ui,
            view = self.view or (self.ui and self.ui.view),
            document = (self.ui and self.ui.document) or (self.playback_queue and self.playback_queue.document),
            sentence_text = chunk and (chunk.raw_text or chunk.text),
            current_page = (chunk and chunk.page) or self.current_page or (self.playback_queue and self.playback_queue.current_page),
            bar_top = self:_barTop(),
        }
        self.highlighter:highlightSentence(self.view, bboxes, mode, ctx)
        self.current_highlight = self.highlighter.current_highlight
    end
end

--- Clear active sentence highlight (delegated to CanvasHighlight)
function UIPlayer:clearHighlight()
    if self.highlighter then
        self.highlighter:clearHighlight(self.view)
    end
    self.current_highlight = nil
end

-- =========================================================================
-- STATE SYNCHRONIZATION WITH PLAYBACK QUEUE
-- =========================================================================

--- Update Play/Pause icon across active widgets
function UIPlayer:_updatePlayPauseIcon()
    local is_playing = self.playback_queue and (self.playback_queue:getState() == "PLAYING")
    local label = is_playing and "  ||  " or "  ▶  "

    if self.play_pause_btn then
        setBtnText(self.play_pause_btn, label)
    end
    if self.mini_play_btn then
        setBtnText(self.mini_play_btn, is_playing and " || " or " ▶ ")
    end
    if self.control_bar and UIManager and UIManager.setDirty then
        self:_setBarDirty()
    end
    if self.mini_bubble and UIManager and UIManager.setDirty then
        self:_setBarDirty()
    end
end

--- Update buffer status indicator (●●, ●○, ○○)
function UIPlayer:_updateBufferStatus()
    if not self.playback_queue then
        return
    end

    local k = (self.settings and self.settings:get("preload_count")) or 1
    k = math.max(1, math.min(7, k))

    local ready_count = 0
    for i = 1, k do
        local slot = self.playback_queue:getSlot(i)
        if slot and slot.status == "READY" then
            ready_count = ready_count + 1
        end
    end

    -- ●●○ : how many of the preloaded sentences are ready (k = "Preload count" in settings)
    local dots = string.rep("●", ready_count) .. string.rep("○", k - ready_count)
    self._buf_short = dots
    if self.buffer_status_widget and self.buffer_status_widget.setText then
        self.buffer_status_widget:setText(dots)
        self:_layoutHeaderSpaceBetween()
    end
end

--- Event callback when current chunk changes
function UIPlayer:onChunkChange(chunk, page, index, total)
    self.current_page = page
    self.current_index = index
    self.total_on_page = total or self.total_on_page

    -- 1. Update progress labels
    self:_refreshTitle()

    local cur_speed = self.audio_backend and self.audio_backend.speed or 1.0
    if self.mini_label_btn and self.mini_label_btn.setText then
        setBtnText(self.mini_label_btn, self:_miniLabelText(index, total, cur_speed))
    end

    -- 2. Synchronize sentence highlight
    if chunk then
        self:highlightSentence(chunk.bboxes, nil, chunk)
    end

    -- 3. Update buffer & play/pause icon
    self:_updateBufferStatus()
    self:_updatePlayPauseIcon()

    -- 4. Refresh control bar UI
    if self.control_bar and UIManager.setDirty then
        self:_setBarDirty()
    elseif self.mini_bubble and UIManager.setDirty then
        self:_setBarDirty()
    end
end

--- Event callback when FSM state changes
function UIPlayer:onStateChange(old_state, new_state)
    self:_updatePlayPauseIcon()
    self:_updateBufferStatus()
end

--- Event callback when background prefetch buffer updates
function UIPlayer:onBufferChange()
    self:_updateBufferStatus()
    if self.control_bar and UIManager and UIManager.setDirty then
        self:_setBarDirty()
    end
end

--- Event callback when page turns
function UIPlayer:onPageTurn(new_page)
    self.current_page = new_page
    self:clearHighlight()
    if self.sleep_timer then
        self.sleep_timer:onPageTurn(new_page)
    end
end

--- Event callback when entire book completes
function UIPlayer:onFinished()
    self:clearHighlight()
    self:_updatePlayPauseIcon()
end

--- Event callback on error
function UIPlayer:onError(err)
    self:_updatePlayPauseIcon()
end

-- =========================================================================
-- USER ACTION HANDLERS
-- =========================================================================

--- Toggle Play / Pause
function UIPlayer:onTogglePlayPause()
    if not self.playback_queue then return end

    local now = (UIManager.getTime and UIManager:getTime()) or os.time()
    if self._last_toggle_time and (now - self._last_toggle_time) < 0.25 then
        return
    end
    self._last_toggle_time = now

    local current_state = self.playback_queue:getState()

    -- 1. If currently playing or prefetching: PAUSE IMMEDIATELY!
    if current_state == "PLAYING" or current_state == "PREFETCHING" then
        self.playback_queue:pause()
        self:_updatePlayPauseIcon()
        return
    end

    -- 2. If currently paused or idle: User taps Play
    local on_screen_page = nil
    if self.ui and type(self.ui.getCurrentPage) == "function" then
        on_screen_page = self.ui:getCurrentPage()
    elseif self.ui and self.ui.paging and self.ui.paging.current_page then
        on_screen_page = self.ui.paging.current_page
    end

    local q_page = self.playback_queue:getCurrentPage()
    if on_screen_page and on_screen_page > 0 and on_screen_page ~= q_page then
        -- User moved to another page on reader while paused: read the visible page!
        self.playback_queue:seekChunk(on_screen_page, 1)
    else
        self.playback_queue:resume()
    end
    self:_updatePlayPauseIcon()
end

--- Advance to next chunk
function UIPlayer:onNextChunk()
    if self.playback_queue then
        self.playback_queue:nextChunk()
    end
end

--- Return to previous chunk
function UIPlayer:onPrevChunk()
    if self.playback_queue then
        self.playback_queue:prevChunk()
    end
end

--- Advance to next page
function UIPlayer:onNextPage()
    if self.playback_queue then
        self.playback_queue:seekChunk(self.current_page + 1, 1)
    end
end

--- Return to previous page
function UIPlayer:onPrevPage()
    if self.playback_queue and self.current_page > 1 then
        self.playback_queue:seekChunk(self.current_page - 1, 1)
    end
end

--- Show popup dialog to choose playback speed directly (matches InputDialog in Settings)
function UIPlayer:showSpeedDialog()
    local this = self
    local cur_speed = self.audio_backend and self.audio_backend.speed or 1.0
    local input_dialog

    input_dialog = InputDialog:new{
        title = _("Reading Speed (0.5x - 2.0x)"),
        input = tostring(cur_speed),
        input_hint = "1.0",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "cancel",
                    callback = function()
                        UIManager:close(input_dialog)
                        if UIManager and UIManager.setDirty then
                            pcall(UIManager.setDirty, UIManager, nil, "ui")
                        end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local val = tonumber(input_dialog:getInputText())
                        if val then
                            val = math.max(0.5, math.min(2.0, val))
                            if this.audio_backend then
                                this.audio_backend:setSpeed(val)
                            end
                            if this.settings then
                                this.settings:set("speed", val)
                                this.settings:save()
                            end
                            if this.speed_btn and this.speed_btn.setText then
                                setBtnText(this.speed_btn, string.format(_("Speed: %.1fx"), val))
                            end
                            if this.mini_label_btn and this.mini_label_btn.setText then
                                setBtnText(this.mini_label_btn, this:_miniLabelText(this.current_index, this.total_on_page, val))
                            end
                        end
                        UIManager:close(input_dialog)
                        if this.control_bar and UIManager and UIManager.setDirty then
                            this:_setBarDirty()
                        end
                        -- Cleanly repaint uncovered screen area to avoid ghosting artifacts
                        if UIManager and UIManager.setDirty then
                            pcall(UIManager.setDirty, UIManager, nil, "ui")
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    if input_dialog.onShowKeyboard then
        input_dialog:onShowKeyboard()
    end
end

function UIPlayer:onCycleSpeed()
    local cur_speed = self.audio_backend and self.audio_backend.speed or 1.0
    local next_speed = SPEED_LEVELS[1]

    for i, s in ipairs(SPEED_LEVELS) do
        if math.abs(s - cur_speed) < 0.05 then
            next_speed = SPEED_LEVELS[(i % #SPEED_LEVELS) + 1]
            break
        end
    end

    if self.audio_backend then
        self.audio_backend:setSpeed(next_speed)
    end
    if self.settings then
        self.settings:set("speed", next_speed)
        self.settings:save()
    end

    if self.speed_btn and self.speed_btn.setText then
        setBtnText(self.speed_btn, string.format(_("Speed: %.1fx"), next_speed))
    end
    if self.mini_label_btn and self.mini_label_btn.setText then
        setBtnText(self.mini_label_btn, self:_miniLabelText(self.current_index, self.total_on_page, next_speed))
    end
end

--- Show popup dialog to choose sleep timer directly (matches vertical single-column list)
function UIPlayer:showSleepTimerDialog()
    local this = self
    if not self.sleep_timer then return end
    local cur_mode = tostring(self.sleep_timer:getMode())
    local dialog

    local function selectTimer(mode)
        this.sleep_timer:setMode(mode)
        if this.sleep_timer_btn and this.sleep_timer_btn.setText then
            setBtnText(this.sleep_timer_btn, this.sleep_timer:getDisplayText())
        end
        if dialog then
            UIManager:close(dialog)
        end
        if this.control_bar and UIManager and UIManager.setDirty then
            this:_setBarDirty()
        end
        -- Cleanly repaint uncovered screen area to avoid ghosting artifacts
        if UIManager and UIManager.setDirty then
            pcall(UIManager.setDirty, UIManager, nil, "ui")
        end
    end

    local buttons = {
        {
            {
                text = _("Turn off timer") .. (cur_mode == "0" and "  ✔" or ""),
                align = "left",
                callback = function() selectTimer("0") end,
            },
        },
        {
            {
                text = _("15 minutes") .. (cur_mode == "15" and "  ✔" or ""),
                align = "left",
                callback = function() selectTimer("15") end,
            },
        },
        {
            {
                text = _("30 minutes") .. (cur_mode == "30" and "  ✔" or ""),
                align = "left",
                callback = function() selectTimer("30") end,
            },
        },
        {
            {
                text = _("45 minutes") .. (cur_mode == "45" and "  ✔" or ""),
                align = "left",
                callback = function() selectTimer("45") end,
            },
        },
        {
            {
                text = _("When current page finishes") .. (cur_mode == "page" and "  ✔" or ""),
                align = "left",
                callback = function() selectTimer("page") end,
            },
        },
        {
            {
                text = _("Close"),
                callback = function()
                    if dialog then
                        UIManager:close(dialog)
                        if UIManager.setDirty then
                            pcall(UIManager.setDirty, UIManager, nil, "ui")
                        end
                    end
                end,
            },
        },
    }

    dialog = ButtonDialog:new{
        title = _("Sleep Timer"),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function UIPlayer:onCycleSleepTimer()
    if not self.sleep_timer then return end
    local modes = { "0", "15", "30", "45", "page" }
    local cur = tostring(self.sleep_timer:getMode())
    local next_m = modes[1]
    for i, m in ipairs(modes) do
        if m == cur then
            next_m = modes[(i % #modes) + 1]
            break
        end
    end
    self.sleep_timer:setMode(next_m)
    if self.sleep_timer_btn and self.sleep_timer_btn.setText then
        setBtnText(self.sleep_timer_btn, self.sleep_timer:getDisplayText())
    end
end

--- Close player and stop playback
function UIPlayer:onClose()
    if self.playback_queue then
        self.playback_queue:stop()
    end
    self:hide()
end

local PlayerWidget = UIPlayer
PlayerWidget.UIPlayer = PlayerWidget

return PlayerWidget
