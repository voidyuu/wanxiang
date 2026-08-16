-- 自定义声调键与候选键。
-- 配置入口见 wanxiang.custom.yaml 的 custom_key_select 节点。

local M = {}

local K_ACCEPT = 1
local K_NOOP = 2

local function is_plain_key(key)
    return not (key:ctrl() or key:alt() or key:super() or key:shift())
end

local function select_and_confirm(ctx, index, page_size)
    if not ctx:has_menu() or ctx.composition:empty() then return false end
    local seg = ctx.composition:back()
    local menu = seg and seg.menu
    if not menu or menu:empty() then return false end

    local selected = seg.selected_index or 0
    local page_start = math.floor(selected / page_size) * page_size
    if menu:prepare(page_start + index + 1) <= page_start + index then return false end

    ctx:select(page_start + index)
    ctx:confirm_current_selection()
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
    env.page_size = config:get_int("menu/page_size") or 6
end

function M.func(key, env)
    local ctx = env.engine.context
    local repr = key:repr() or ""
    local kc = key.keycode

    -- Squirrel 将“单独按 Shift”在松键时交给输入法处理。
    -- 按下阶段只吞掉事件，松开阶段再提交对应候选，避免触发两次。
    local is_left_shift = repr == "Shift_L" or repr == "Release+Shift_L" or kc == 0xFFE1
    local is_right_shift = repr == "Shift_R" or repr == "Release+Shift_R" or kc == 0xFFE2
    if is_left_shift or is_right_shift then
        if not key:release() then return K_ACCEPT end
        local index = is_left_shift and 1 or 2
        return select_and_confirm(ctx, index, env.page_size) and K_ACCEPT or K_NOOP
    end

    if key:release() then return K_NOOP end

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

    -- 左右 Shift 分别提交当前页第 2、3 项；空格仍由 Rime 提交第 1 项。
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
