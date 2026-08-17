-- 自定义声调键与候选键。
-- 配置入口见 wanxiang.custom.yaml 的 custom_key_select 节点。

local M = {}

local K_ACCEPT = 1
local K_NOOP = 2

local function is_plain_key(key)
    return not (key:ctrl() or key:alt() or key:super() or key:shift())
end

local function select_candidate(ctx, index, page_size)
    if not ctx:has_menu() or ctx.composition:empty() then return false end
    local seg = ctx.composition:back()
    local menu = seg and seg.menu
    if not menu or menu:empty() then return false end

    local selected = seg.selected_index or 0
    local page_start = math.floor(selected / page_size) * page_size
    if menu:prepare(page_start + index + 1) <= page_start + index then return false end

    ctx:select(page_start + index)
    return true
end

function M.init(env)
    local config = env.engine.schema.config
    env.tone_keys = config:get_string("custom_key_select/tone_keys") or "1290"
    env.tone_codes = config:get_string("custom_key_select/tone_codes") or "7890"
    env.tone_input_codes = config:get_string("custom_key_select/tone_input_codes") or env.tone_codes
    env.tone_input_chars = {}
    for char in env.tone_input_codes:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        env.tone_input_chars[#env.tone_input_chars + 1] = char
    end
    env.strip_tones_on_return = config:get_bool("custom_key_select/strip_tones_on_return")
    env.space_select_first = config:get_bool("custom_key_select/space_select_first")
    env.page_size = config:get_int("menu/page_size") or 6
    env.left_shift_down = false
    env.right_shift_down = false
    env.left_shift_used = false
    env.right_shift_used = false
end

function M.func(key, env)
    local ctx = env.engine.context
    local repr = key:repr() or ""
    local kc = key.keycode

    local is_left_shift = repr == "Shift_L" or repr == "Release+Shift_L" or kc == 0xFFE1
    local is_right_shift = repr == "Shift_R" or repr == "Release+Shift_R" or kc == 0xFFE2
    if is_left_shift or is_right_shift then
        local side = is_left_shift and "left" or "right"
        if not key:release() then
            env[side .. "_shift_down"] = true
            env[side .. "_shift_used"] = false
            -- 不吞掉按下事件，让 Shift+字母、Shift+数字等组合键保持上档功能。
            return K_NOOP
        end

        local used = env[side .. "_shift_used"]
        env[side .. "_shift_down"] = false
        env[side .. "_shift_used"] = false
        -- 只有按下和松开之间没有使用其他键时，才把单按 Shift 当作候选键。
        if not used then
            local index = is_left_shift and 1 or 2
            if select_candidate(ctx, index, env.page_size) then return K_ACCEPT end
        end
        return K_NOOP
    end

    -- Shift 按住期间出现任何其他按键，均视为组合键；其按下和松开事件都放行。
    if env.left_shift_down then env.left_shift_used = true end
    if env.right_shift_down then env.right_shift_used = true end
    if key:release() then return K_NOOP end

    -- 有候选菜单时，空格固定提交整个列表的第 1 项，而非当前高亮项。
    if env.space_select_first and is_plain_key(key) and repr == "space"
        and ctx:has_menu() and not ctx.composition:empty() then
        local seg = ctx.composition:back()
        local menu = seg and seg.menu
        if menu and not menu:empty() and menu:prepare(1) > 0 then
            ctx:select(0)
            return K_ACCEPT
        end
    end

    -- Rime 的编码缓冲区使用 UTF-8 字节位置。普通 Backspace 只删一个字节时
    -- 会把上标声调留成残缺字符，因此在此删除光标前的完整声调字符。
    if is_plain_key(key) and repr == "BackSpace" and ctx:is_composing()
        and not ctx.composition:empty() then
        local seg = ctx.composition:back()
        local input = ctx.input or ""
        local caret = ctx.caret_pos or #input
        local left = input:sub(1, caret)
        local last = left:match("([%z\1-\127\194-\244][\128-\191]*)$") or ""
        if seg and seg:has_tag("abc") and last ~= ""
            and string.find("¹²³⁴", last, 1, true) then
            ctx:pop_input(#last)
            return K_ACCEPT
        end
    end

    -- Enter 提交原始拼音时删除词库内部声调码。
    -- 只拦截普通 Enter 且仅处理 abc 段，不影响 Ctrl+Enter 及其他功能模式。
    if env.strip_tones_on_return and is_plain_key(key) and repr == "Return"
        and ctx:is_composing() and not ctx.composition:empty() then
        local seg = ctx.composition:back()
        local input = ctx.input or ""
        if seg and seg:has_tag("abc") and input:find("[7890¹²³⁴]") then
            local raw = input:gsub("[7890¹²³⁴]", "")
            ctx:clear()
            if raw ~= "" then env.engine:commit_text(raw) end
            return K_ACCEPT
        end
    end

    -- 左右单按 Shift 分别提交当前页第 2、3 项；空格仍由 Rime 提交第 1 项。
    if not is_plain_key(key) or not ctx:is_composing() or ctx.composition:empty() then return K_NOOP end
    local seg = ctx.composition:back()
    -- 仅处理普通拼音段，避免影响 / 符号、R 数字转换等功能模式。
    if not seg or not seg:has_tag("abc") then return K_NOOP end

    -- 将用户声调键映射为万象词库内部使用的 7/8/9/0。
    local pos = env.tone_keys:find(repr, 1, true)
    if pos then
        local code = env.tone_input_chars[pos]
        if code ~= "" then
            local input = ctx.input or ""
            local caret = ctx.caret_pos or #input
            -- 与万象原来的 7/8/9/0 行为一致：音节末尾已有声调时，
            -- 新声调直接替换旧声调，无需先按退格。
            if caret == #input and input:match("[7890¹²³⁴]$") then
                local last = input:match("([%z\1-\127\194-\244][\128-\191]*)$") or ""
                ctx:pop_input(#last)
            end
            ctx:push_input(code)
            return K_ACCEPT
        end
    end

    -- 原 7、8 不再作为一、二声输入键。
    if repr == "7" or repr == "8" then return K_ACCEPT end

    return K_NOOP
end

return M
