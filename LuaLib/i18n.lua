-- i18n.lua
-- 完整的多语言管理模块

local I18N = {}
I18N.__index = I18N

-- 构造函数
function I18N.new(default_lang)
    local self = setmetatable({}, I18N)
    self.translations = {}      -- 缓存所有已加载的语言表
    self.current_lang = default_lang or "en"  -- 当前语言
    self.fallback_lang = "en"   -- 降级语言（当找不到翻译时使用）
    return self
end

-- 加载语言文件
function I18N:load_language(lang_code)
    if not self.translations[lang_code] then
        local ok, lang_table = pcall(require, lang_code)
        if ok and type(lang_table) == "table" then
            self.translations[lang_code] = lang_table
            print("Loaded language: " .. lang_code)
            return true
        else
            print("Failed to load language: " .. lang_code)
            return false
        end
    end
    return true
end

-- 预加载多个语言
function I18N:preload_languages(lang_codes)
    for _, code in ipairs(lang_codes) do
        self:load_language(code)
    end
end

-- 切换当前语言
function I18N:set_language(lang_code)
    -- 检查语言是否已加载
    if not self.translations[lang_code] then
        local success = self:load_language(lang_code)
        if not success then
            return false
        end
    end
    self.current_lang = lang_code
    print("Language switched to: " .. lang_code)
    return true
end

-- 获取当前语言
function I18N:get_language()
    return self.current_lang
end

-- 获取所有已加载的语言
function I18N:get_loaded_languages()
    local langs = {}
    for k, _ in pairs(self.translations) do
        table.insert(langs, k)
    end
    return langs
end

-- 核心翻译函数（支持嵌套键和变量插值）
function I18N:translate(key, variables)
    -- 获取当前语言的翻译表
    local lang_table = self.translations[self.current_lang]
    if not lang_table then
        -- 尝试使用降级语言
        lang_table = self.translations[self.fallback_lang]
        if not lang_table then
            return key  -- 实在找不到就返回 key 本身
        end
    end
    
    -- 解析嵌套键（例如 "menu.title"）
    local value = lang_table
    for part in string.gmatch(key, "[^%.]+") do
        value = value[part]
        if not value then
            -- 当前语言找不到，尝试降级语言
            if self.fallback_lang and self.fallback_lang ~= self.current_lang then
                local fallback_table = self.translations[self.fallback_lang]
                if fallback_table then
                    value = fallback_table
                    for fallback_part in string.gmatch(key, "[^%.]+") do
                        value = value[fallback_part]
                        if not value then
                            break
                        end
                    end
                end
            end
            if not value then
                return key
            end
            break
        end
    end
    
    -- 变量插值
    if type(value) == "string" and variables then
        for var, val in pairs(variables) do
            value = string.gsub(value, "{" .. var .. "}", tostring(val))
        end
    end
    
    return value
end

-- 简写方法
function I18N:_(key, variables)
    return self:translate(key, variables)
end

-- 检查某个 key 是否存在
function I18N:has_key(key, lang_code)
    local lang = lang_code or self.current_lang
    local lang_table = self.translations[lang]
    if not lang_table then
        return false
    end
    
    local value = lang_table
    for part in string.gmatch(key, "[^%.]+") do
        value = value[part]
        if not value then
            return false
        end
    end
    return true
end

-- 获取所有可用的翻译 key（仅当前语言）
function I18N:get_all_keys()
    local keys = {}
    local lang_table = self.translations[self.current_lang]
    if not lang_table then
        return keys
    end
    
    local function collect_keys(t, prefix)
        for k, v in pairs(t) do
            local new_key = prefix == "" and k or prefix .. "." .. k
            if type(v) == "table" then
                collect_keys(v, new_key)
            else
                table.insert(keys, new_key)
            end
        end
    end
    
    collect_keys(lang_table, "")
    return keys
end

-- 热重载某个语言（重新加载文件）
function I18N:reload_language(lang_code)
    -- 清除缓存
    self.translations[lang_code] = nil
    -- 重新加载
    return self:load_language(lang_code)
end

-- 设置降级语言
function I18N:set_fallback_language(lang_code)
    self.fallback_lang = lang_code
    self:load_language(lang_code)  -- 确保降级语言已加载
end

return I18N