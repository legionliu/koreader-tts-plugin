--[[
    wakelock.lua - keep the Android CPU awake while the plugin is reading aloud,
    so playback keeps going (and the next sentence is fetched) with the screen locked.

    Uses PowerManager.PARTIAL_WAKE_LOCK via JNI (KOReader already holds the WAKE_LOCK permission).
    The lock has a safety timeout, so a crash can never leave it held forever.
    Everything is wrapped in pcall: on non-Android systems or any JNI error it silently does nothing.
--]]

local M = {}

local ok_logger, logger = pcall(require, "logger")
if not ok_logger or not logger then
    logger = { warn = function() end, info = function() end }
end

local PARTIAL_WAKE_LOCK = 1
local TIMEOUT_MS = 4 * 60 * 60 * 1000 -- auto-release after 4 hours at most

local held_ref = nil     -- JNI global ref of the WakeLock while held
local release_mid = nil

local function checkException(env)
    if env[0].ExceptionCheck(env) ~= 0 then
        env[0].ExceptionClear(env)
        return true
    end
    return false
end

local function getAndroid()
    local ok_d, Device = pcall(require, "device")
    if not ok_d or not Device or not Device.isAndroid or not Device:isAndroid() then return nil end
    local ok_a, android = pcall(require, "android")
    if not ok_a or not android or not android.jni then return nil end
    return android
end

function M.acquire()
    local android = getAndroid()
    if not android then return false end
    local ok, result = pcall(function()
        local ffi = require("ffi")
        return android.jni:context(android.app.activity.vm, function(jni)
            local env = jni.env

            -- Re-acquire on an existing lock just refreshes the timeout
            if held_ref ~= nil then
                local wl_cls = env[0].GetObjectClass(env, held_ref)
                local acq = env[0].GetMethodID(env, wl_cls, "acquire", "(J)V")
                if checkException(env) or acq == nil then return false end
                local a = ffi.new("jvalue[1]")
                a[0].j = TIMEOUT_MS
                env[0].CallVoidMethodA(env, held_ref, acq, a)
                return not checkException(env)
            end

            local act = android.app.activity.clazz
            local act_cls = env[0].GetObjectClass(env, act)
            local get_ss = env[0].GetMethodID(env, act_cls, "getSystemService",
                "(Ljava/lang/String;)Ljava/lang/Object;")
            if checkException(env) or get_ss == nil then return false end

            local a1 = ffi.new("jvalue[1]")
            a1[0].l = env[0].NewStringUTF(env, "power")
            local pm = env[0].CallObjectMethodA(env, act, get_ss, a1)
            if checkException(env) or pm == nil then return false end

            local pm_cls = env[0].GetObjectClass(env, pm)
            local new_wl = env[0].GetMethodID(env, pm_cls, "newWakeLock",
                "(ILjava/lang/String;)Landroid/os/PowerManager$WakeLock;")
            if checkException(env) or new_wl == nil then return false end

            local a2 = ffi.new("jvalue[2]")
            a2[0].i = PARTIAL_WAKE_LOCK
            a2[1].l = env[0].NewStringUTF(env, "koreader_tts:reading")
            local wl = env[0].CallObjectMethodA(env, pm, new_wl, a2)
            if checkException(env) or wl == nil then return false end

            local wl_cls = env[0].GetObjectClass(env, wl)
            local set_rc = env[0].GetMethodID(env, wl_cls, "setReferenceCounted", "(Z)V")
            if set_rc ~= nil and not checkException(env) then
                local a3 = ffi.new("jvalue[1]")
                a3[0].z = 0
                env[0].CallVoidMethodA(env, wl, set_rc, a3)
                checkException(env)
            end

            local acq = env[0].GetMethodID(env, wl_cls, "acquire", "(J)V")
            release_mid = env[0].GetMethodID(env, wl_cls, "release", "()V")
            if checkException(env) or acq == nil or release_mid == nil then return false end

            local a4 = ffi.new("jvalue[1]")
            a4[0].j = TIMEOUT_MS
            env[0].CallVoidMethodA(env, wl, acq, a4)
            if checkException(env) then return false end

            held_ref = env[0].NewGlobalRef(env, wl)
            return true
        end)
    end)
    if not ok then
        logger.warn("TTS wakelock: acquire failed: " .. tostring(result))
        return false
    end
    return result == true
end

function M.release()
    if held_ref == nil then return end
    local android = getAndroid()
    if not android then held_ref = nil return end
    local ref, mid = held_ref, release_mid
    held_ref, release_mid = nil, nil
    local ok, err = pcall(function()
        android.jni:context(android.app.activity.vm, function(jni)
            local env = jni.env
            if mid ~= nil then
                env[0].CallVoidMethod(env, ref, mid)
                checkException(env)
            end
            env[0].DeleteGlobalRef(env, ref)
        end)
    end)
    if not ok then logger.warn("TTS wakelock: release failed: " .. tostring(err)) end
end

function M.isHeld()
    return held_ref ~= nil
end

return M
