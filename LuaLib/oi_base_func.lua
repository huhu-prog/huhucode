--[[
    版本：     Version 3.0
    创建日期： 2021-9-3
    修改日期:  2026-6-13
    创建人：   HAN

    名称: oi_base_func

    功能：
        一些常用的 Lua 函数封装

    ==============================================================================
    函数索引：
    ==============================================================================

    【字符串处理】
    split                 字符串根据分隔符分割为数组
    trim                  取消字符串前后的空格
    trim_quotation_mark   取消字符串前后的双引号
    trim_guid_str         取消 GUID 字符串前后的花括号 {}
    trim_str_head_end     取消字符串头尾各一个字符
    trim_laster_char      取消字符串最后面的一个符号
    strArray2string       字符串数组转成 'A','B' 形式（可用于 SQL 查询）
    TrimStrHead           截掉字符串开头的某个指定字符
    strFill               字符串前面填充指定字符到指定长度
    FormatJsonString      JSON 字符串转义：双引号 -> \"
    FormatSQLString       SQL 字符串转义：单引号 -> 双引号
    Normalize_String      取消字符串前后空格并转小写

    【表/数组操作】
    table2str             表转成 JSON 形式的字符串
    table_merge           把 t2 数组追加到 t1 尾部（修改原表）
    isTableEmpty          判断表是否为空（nil/空串/非 table/空表均视为空）
    GetTableCount         获取数组 table 的长度
    IsInTable             判断 value 是否在数组 tbl 中
    IsTableEmpty          判断表是否为空表
    Add_StrArray          向字符串数组中追加一个值，已存在则忽略
    AddArray              数组中追加一个值，已存在则忽略
    table_copy            浅拷贝表（⚠ 不建议使用，建议用 table_deepcopy）
    table_deepcopy        深拷贝表（递归复制所有层级，含元表）
    MakeConstantTable     创建只读常量表（通过元表禁止写入）
    GetDataAttrObj_By_StrArray  根据属性名数组和值数组构造键值对表

    【类型判断/转换】
    equation              浮点数相等判断（误差 < 0.000001）
    StrIsEmpty            判断字符串是否为无效值（nil/空串/非字符串）
    StrToNumber           字符串转数值，空字符串返回 0
    Get_StrAttrValue      安全获取字符串属性值（nil 时返回空串）
    Get_NumAttrValue      安全获取数值属性值（nil/空串返回 0）
    Get_BoolAttrValue     安全获取布尔属性值（nil/空串返回 false）
    YesNo2Bool            把字符 Y 转成 true，N 转成 false
    DecrementChar         字符减 1（ASCII 码减 1）
    IncrementalChar       字符加 1（ASCII 码加 1）

    【日期时间】
    getNewDate            日期时间的加减计算
    dateDiff              计算两个日期之间的天数（date1 - date2）
    time_diff             计算两个日期差几天（⚠ 已废弃 HAN 2024-2-11，请用 dateDiff）
    getWeekNum            根据年月日获取是星期几（1-7，周一=1）
    toTimestamp           把日期时间字符串转成 os.time 时间戳
    DateTimeIsBefore      比较两个日期时间字符串的先后
    DayFormatConversion   日期格式统一转换（/ -. 分隔均转为 yyyy-mm-dd）
    DayFormatConversion2  日期格式转换：yyyymmdd -> yyyy-mm-dd
    Regular_Datetime      规整日期时间格式：2024-1-20 8:20:1 -> 2024-01-20 08:20:01
    GetYearMonthDay       根据日期字符串获取年月日
    CalculateWeekNumber   计算某天是星期几
    month_to_quarter      输入月份返回是第几个季度

    【日志/调试】
    WriteLog              输出日志文件
    Debug                 调试日志输出（⚠ 已废弃 HAN 2024-2-11，请用 DebugEx）
    DebugEx               调试日志输出
    WCSDebugEx            WCS 调试日志输出
    Warning               输出 Lua 脚本执行时的警告信息
    Error                 输出错误信息并抛出 error（⚠ 已废弃 HAN 2024-2-11）

    【流程控制】
    Wait                  条件不具备时的等待处理（返回值 4）
    Stop                  设置 mobox.stopProgram 终止脚本执行
    GetBackgroundScript_Result  获取后台脚本执行结果（轮询等待）

    【其他】
    guid                  生成一个 GUID 字符串
    proJsonStrNode        JSON 字符串预处理（⚠ 已废弃 HAN 2024-2-11）
    KeyValueObj           返回 {attr, value} 键值对对象（⚠ 已废弃 HAN 2024-2-11）
    GetLuaDEInfo          获取 Lua 数据交换区信息并解码为 table
    RunSQL                执行多条 SQL 语句（以分号分隔）
    Have_Duplicates_Data  检查数据对象中指定属性是否存在重复记录
    callFunctionByName    根据模块名和函数名动态调用函数（支持可变参数）

    AI CHECK:
        -- 20260613

--]]
local json  = require ("json")

local lua = {_version = "0.1.1"} -- 定义一个空表，用于存储模块的函数和变量

-- 字符串根据分隔符 reps 分割为数组
-- @function lua.split
-- @tparam string str 待分割的字符串
-- @tparam string reps 分隔符
-- @treturn table 字符串数组
function lua.split( str,reps )
    local resultStrList = {}

    if ( reps == nil or reps == '' ) then return "" end
    if ( str == nil or str == '' ) then return resultStrList end
    -- 转义分隔符中可能被误当作Lua正则元字符的符号（] 、 - 、 ^ 、 %）
    local escaped_reps = string.gsub( reps, "([%]%-%^%%])", "%%%1" )
    string.gsub( str,'[^'..escaped_reps..']+',function ( w )
                 table.insert(resultStrList,w) end )
    return resultStrList
end

-- 表转成 JSON 形式的字符串
-- @function lua.table2str
-- @tparam table t 要转换的表
-- @treturn string JSON 字符串
function lua.table2str(t)
    local function serialize(tbl)
        local tmp = {}
        local has_non_int_key = false  -- 标记是否存在非整数键
        for k, v in pairs(tbl) do
            local k_type = type(k)
            if k_type ~= "number" or k ~= math.floor(k) or k < 1 then
                has_non_int_key = true  -- 存在非数组键，视为对象
            end
            local v_type = type(v)
            if ( v_type == "string" ) then
                v = string.gsub(v,'\\',"\\\\")
                v = string.gsub(v,'"','\\"')
            end
            local key = (k_type == "string" and "\"" .. k .. "\":")
                or (k_type == "number" and "")
            local value = (v_type == "table" and serialize(v))
                or (v_type == "boolean" and tostring(v))
                or (v_type == "string" and "\"" .. v .. "\"")
                or (v_type == "number" and v)
            tmp[#tmp + 1] = key and value and tostring(key) .. tostring(value) or nil
        end
        if has_non_int_key or #tbl == 0 then
            return "{" .. table.concat(tmp, ",") .. "}"
        else
            return "[" .. table.concat(tmp, ",") .. "]"
        end
    end
    assert(type(t) == "table")
    return serialize(t)
end

-- 表转成 JSON 形式的字符串（带字段优先级白名单）
-- @function lua.table2str_sorted
-- @tparam table t 要转换的表
-- @tparam[opt] table priority 字段优先级白名单，如 { S_ITEM_CODE = 1, F_QTY = 2 }
--               数字越小越靠前；未在白名单中的字段按字典序排在后面；整数键按数值升序排最前
-- @treturn string JSON 字符串
function lua.table2str_sorted(t, priority)
    -- 白名单比较函数
    local function cmp_key(a, b)
        local pa = priority and priority[a]
        local pb = priority and priority[b]
        if pa and pb then return pa < pb end  -- 都在白名单：按白名单顺序
        if pa then return true  end           -- 仅 a 在白名单：a 在前
        if pb then return false end           -- 仅 b 在白名单：b 在前
        return tostring(a) < tostring(b)      -- 都不在白名单：字典序
    end

    local function serialize(tbl, seen)
        seen = seen or {}
        if seen[tbl] then return '"[circular ref]"' end
        seen[tbl] = true

        local tmp = {}
        local has_non_int_key = false
        -- 收集并排序 key：整数键升序在前，字符串键按白名单优先级
        local num_keys, str_keys = {}, {}
        for k in pairs(tbl) do
            local k_type = type(k)
            if k_type == "number" and k == math.floor(k) and k >= 1 then
                num_keys[#num_keys + 1] = k
            else
                str_keys[#str_keys + 1] = k
                has_non_int_key = true
            end
        end
        table.sort(num_keys)
        table.sort(str_keys, cmp_key)
        local ordered = {}
        for _, k in ipairs(num_keys) do ordered[#ordered + 1] = k end
        for _, k in ipairs(str_keys) do ordered[#ordered + 1] = k end

        for _, k in ipairs(ordered) do
            local v = tbl[k]
            local v_type = type(v)
            if v_type == "string" then
                v = string.gsub(v, '\\', "\\\\")
                v = string.gsub(v, '"', '\\"')
            end
            local key = (type(k) == "string" and '"' .. k .. '":') or ""
            local value
            if v_type == "table" then
                value = serialize(v, seen)
            elseif v_type == "string" then
                value = '"' .. v .. '"'
            else
                value = tostring(v)  -- number / boolean / function / userdata
            end
            tmp[#tmp + 1] = key .. value
        end
        seen[tbl] = nil

        if has_non_int_key or #tbl == 0 then
            return "{" .. table.concat(tmp, ",") .. "}"
        else
            return "[" .. table.concat(tmp, ",") .. "]"
        end
    end

    assert(type(t) == "table")
    return serialize(t)
end

-- 把 t2 数组追加到 t1 尾部（修改原表）
-- @function lua.table_merge
-- @tparam table t1 目标数组
-- @tparam table t2 源数组
function lua.table_merge( t1, t2 )
    local n
    for n = 1, #t2 do
        table.insert( t1, t2[n] )
    end
end

-- 判断表是否为空（nil/空串/非 table/空表均视为空）
-- @function lua.isTableEmpty
-- @tparam any t 要判断的值
-- @treturn boolean true=为空
function lua.isTableEmpty(t) return type(t) ~= "table" or t == '' or t == nil or next(t) == nil end

-- 获取数组 table 的长度
-- @function lua.GetTableCount
-- @tparam table t 数组
-- @treturn number 长度
function lua.GetTableCount( t )
    if ( t == nil or type(t) ~= "table" ) then return 0 end
    return #t
end

-- 取消字符串前后的空格
-- @function lua.trim
-- @tparam string strbuf 待处理的字符串
-- @treturn string 去除前后空格后的字符串
function lua.trim( strbuf )
    if strbuf == nil or strbuf == '' then 
        return "" 
    end
    return (strbuf:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 取消字符串前后的双引号（如 "ABC" -> ABC）
-- @function lua.trim_quotation_mark
-- @tparam string strbuf 待处理的字符串
-- @treturn string 去除引号后的字符串
function lua.trim_quotation_mark( strbuf )
    if ( strbuf == nil ) then error( "trim_quotation_mark 函数的输入参数不能为 nil!") end
    if ( strbuf == '' ) then return "" end
    return string.gsub(strbuf, '^["]*([^"].*[^"])["]*$', "%1")
end

-- 取消 GUID 字符串前后的花括号 {}（如 {XXX-XXX} -> XXX-XXX）
-- @function lua.trim_guid_str
-- @tparam string strvalue GUID 字符串
-- @treturn string 去除花括号后的字符串
function lua.trim_guid_str( strvalue )
    if ( strvalue == nil or strvalue == '' ) then return "" end
    local nSize =  string.len( strvalue )

    if ( nSize ~= 38 ) then
        return strvalue
    end
    strvalue = string.sub( strvalue, 1, nSize-1 )
    strvalue = string.sub( strvalue, 2, -1 )
    return strvalue
end

-- 取消字符串头尾各一个字符（如 ["A","B"] -> "A","B"）
-- @function lua.trim_str_head_end
-- @tparam string strvalue 待处理的字符串
-- @treturn string 去除头尾后的字符串
function lua.trim_str_head_end( strvalue )
    if ( strvalue == nil or strvalue == '' ) then return "" end
    local nSize =  string.len( strvalue )

    if ( nSize < 2 ) then return strvalue end
    strvalue = string.sub( strvalue, 1, nSize-1 )
    strvalue = string.sub( strvalue, 2, -1 )
    return strvalue
end

-- 取消字符串最后面的一个符号
-- @function lua.trim_laster_char
-- @tparam string strBuf 待处理的字符串
-- @treturn string 去除最后一个字符后的字符串
function lua.trim_laster_char( strBuf )
    if ( strBuf == nil ) then return "" end
    local nSize = string.len(strBuf)
    if ( nSize == 0) then
        return ''
    end
    return string.sub( strBuf, 1, nSize-1 )
end

-- 把一个字符串数组 ["A","B"] 转成 'A','B' 形式(可用于SQL查询)
-- @function lua.strArray2string
-- @tparam table t 字符串数组
-- @treturn string 拼接后的字符串
function lua.strArray2string(t)
    local ret_str = ''
    for _,v in pairs(t) do
        ret_str = ret_str.."'"..v.."',"
    end
    return lua.trim_laster_char( ret_str )
end

-- 判断 value 是否在数组 tbl 中
-- @function lua.IsInTable
-- @tparam any value 要查找的值
-- @tparam table tbl 数组表
-- @treturn boolean true=存在
function lua.IsInTable(value, tbl)
    for _,v in pairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

-- 判断表是否为空表（nil/非 table/空表均视为空）
-- @function lua.IsTableEmpty
-- @tparam any t 要判断的值
-- @treturn boolean true=为空
function lua.IsTableEmpty(t)
    if type(t) ~= "table" then
        return true
    end
    if t == nil or next(t) == nil then
        return true
    else
        return false
    end
end

-- 向字符串数组中追加一个值，已存在则忽略
-- @function lua.Add_StrArray
-- @tparam table strArray 字符串数组（会被修改）
-- @tparam string strValue 要追加的字符串
function lua.Add_StrArray( strArray, strValue )
    local n

    if ( type(strArray) ~= "table" ) then return end
    if ( strValue == nil or strValue == '' ) then return end

    for n = 1, #strArray do
        if (strArray[n] == strValue ) then return end
    end
    table.insert( strArray, strValue )
end

-- 浮点数相等判断（误差 < 0.000001）
-- @function lua.equation
-- @tparam number f1 浮点数1
-- @tparam number f2 浮点数2
-- @treturn boolean true=相等
function lua.equation( f1, f2 )
    return math.abs( f1 - f2 ) < 0.000001
end

-- 日期时间的加减计算
-- @function lua.getNewDate
-- @tparam string srcDateTime 源日期时间，格式 yyyymmddHHMMSS
-- @tparam number interval 加减值
-- @tparam string dateUnit 计算单位（DAY/HOUR/MINUTE/SECOND）
-- @treturn table os.date("*t") 格式的时间表
function lua.getNewDate( srcDateTime, interval, dateUnit )
    local Y = string.sub(srcDateTime,1,4)
    local M = string.sub(srcDateTime,5,6)
    local D = string.sub(srcDateTime,7,8)
    local H = string.sub(srcDateTime,9,10)
    local MM = string.sub(srcDateTime,11,12)
    local SS = string.sub(srcDateTime,13,14)

    local dt1 = os.time{year=Y, month=M, day=D, hour=H,min=MM,sec=SS}
    local ofset=0

    if dateUnit =='DAY' then
        ofset = 60 *60 * 24 * interval
    elseif dateUnit == 'HOUR' then
        ofset = 60 *60 * interval
    elseif dateUnit == 'MINUTE' then
        ofset = 60 * interval
    elseif dateUnit == 'SECOND' then
        ofset = interval
    end
    local newTime = os.date("*t", dt1 + tonumber(ofset))
    return newTime
end

-- 计算两个日期之间的天数（date1 - date2）
-- @function lua.dateDiff
-- @tparam number date1 日期1，格式 yyyymmdd
-- @tparam number date2 日期2，格式 yyyymmdd
-- @treturn number 天数差
function lua.dateDiff(date1,date2)
    local day1 = {};
    local day2 = {};
    local numDay1;
    local numDay2;

    if date1 < 19700101 or date2 < 19700101 then
        return 0;
    end
    day1.year,day1.month,day1.day = string.match(date1,"(%d%d%d%d)(%d%d)(%d%d)");
    day2.year,day2.month,day2.day = string.match(date2,"(%d%d%d%d)(%d%d)(%d%d)");
    numDay1 = os.time(day1);
    numDay2 = os.time(day2);

    return (numDay1-numDay2)/(3600*24)
end

-- 根据年月日获取是星期几（1-7，周一=1）
-- @function lua.getWeekNum
-- @tparam string strDate 日期，格式 yyyy-m-d
-- @treturn number 星期几（1-7）
function lua.getWeekNum(strDate)
    if ( strDate == '' or strDate == nil ) then return 0 end

    local ymd = lua.split(strDate,"-")
    if ( ymd == nil or #ymd ~= 3 ) then
        return 0
    end
    local t = os.time({year=tostring(ymd[1]),month=tostring(ymd[2]),day=tostring(ymd[3])})
    local weekNum = os.date("*t",t).wday  -1
    if weekNum == 0 then
        weekNum = 7
    end
    return weekNum
end

-- 把日期时间字符串转成 os.time 时间戳
-- @function lua.toTimestamp
-- @tparam string dateStr 日期时间，格式 yyyy-mm-dd HH:MM:SS
-- @treturn number os.time 时间戳
function lua.toTimestamp(dateStr)
    local pattern = "(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)"
    local year, month, day, hour, min, sec = dateStr:match(pattern)
    return os.time({day=day, month=month, year=year, hour=hour, min=min, sec=sec})
end

-- 比较两个日期时间字符串的先后
-- @function lua.DateTimeIsBefore
-- @tparam string dateStr1 日期时间1
-- @tparam string dateStr2 日期时间2
-- @treturn boolean true=dateStr1 早于 dateStr2
function lua.DateTimeIsBefore( dateStr1, dateStr2 )
    local timestamp1 = lua.toTimestamp(dateStr1)
    local timestamp2 = lua.toTimestamp(dateStr2)
    return timestamp1 < timestamp2
end

-- 日期格式转换：2021/9/2、2021-9-2、2021.9.2 统一转 2021-09-02
-- @function lua.DayFormatConversion
-- @tparam string strDay 输入的日期字符串
-- @treturn number nRet 0=成功，1=格式错误
-- @treturn string strDays 格式化后的日期（yyyy-mm-dd）
function lua.DayFormatConversion( strDay )
    local seg = {}
    seg = lua.split( strDay, '/' )
    local nCount

    nCount = #seg
    if ( nCount == 1 ) then
        seg = lua.split( strDay, '-' )
        nCount = #seg
        if ( nCount == 1 ) then
            seg = lua.split( strDay, '.' )
            nCount = #seg
        end
    end

    if ( nCount ~= 3 ) then
        return 1, "日期格式不正确!"
    end
    local nYear = tonumber( seg[1] )
    local nMonth = tonumber( seg[2] )
    local nDay = tonumber( seg[3] )
    local strDays = string.format( '%d-%02d-%02d', nYear, nMonth, nDay )
    return 0, strDays
end

-- 规整日期时间格式：2024-1-20 8:20:1 -> 2024-01-20 08:20:01
-- @function lua.Regular_Datetime
-- @tparam string str_datetime 待规整的日期时间字符串
-- @treturn number nRet 0=成功，1=格式错误
-- @treturn string str 规整后的日期时间
function lua.Regular_Datetime( str_datetime )
    local pattern = "(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)"
    local year, month, day, hour, min, sec = str_datetime:match(pattern)
    if (year == nil) then
        return 1, "输入格式非法,格式要求是:   2024-11-30 8:20:1"
    end
    return 0, string.format( '%d-%02d-%02d %02d:%02d:%02d', year, month, day, hour, min, sec )
end

-- 日期格式转换：20210902 -> 2021-09-02
-- @function lua.DayFormatConversion2
-- @tparam string strDay 格式为 yyyymmdd 的日期
-- @treturn number nRet 0=成功，1=格式错误
-- @treturn string strNewDay 格式化后的日期（yyyy-mm-dd）
function lua.DayFormatConversion2( strDay )
     local nSize = string.len( strDay )

     if ( nSize ~= 8 ) then
         return 1, "日期格式不正确!"
     end

     local strYear = string.sub( strDay, 1, nSize-4 )
     local strMonth = string.sub( strDay, 5, 6 )
     local strDayPart = string.sub( strDay, 7, 8 )

     local nYear = tonumber( strYear )
     local nMonth = tonumber( strMonth )
     local nDay = tonumber( strDayPart )
     local strNewDay = string.format( '%d-%02d-%02d', nYear, nMonth, nDay )
     return 0, strNewDay
 end

-- 计算某天是星期几
-- @function lua.CalculateWeekNumber
-- @tparam number nYear 年
-- @tparam number nMonth 月
-- @tparam number nDay 日
-- @treturn string 周数（os.date "%W"）
function lua.CalculateWeekNumber( nYear, nMonth, nDay )
     return os.date("%W",os.date(os.time{year=nYear,month=nMonth,day=nDay}))
 end

-- 生成一个 GUID 字符串
-- @function lua.guid
-- @treturn string GUID 格式的字符串
function lua.guid()
     local seed={'e','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'}
     local tb={}
     for i=1,32 do
         table.insert(tb,seed[math.random(1,16)])
     end
     local sid=table.concat(tb)
     return string.format('%s-%s-%s-%s-%s',
         string.sub(sid,1,8),
         string.sub(sid,9,12),
         string.sub(sid,13,16),
         string.sub(sid,17,20),
         string.sub(sid,21,32)
     )
end

-- 根据输入的字符串获取年月日
-- @function lua.GetYearMonthDay
-- @tparam string strDay 日期，格式 yyyy-mm-dd
-- @treturn number nRet 0=成功，2=失败
-- @treturn number year 年
-- @treturn number month 月
-- @treturn number day 日
function lua.GetYearMonthDay( strDay )
    local seg = {}

    if ( strDay == '' or strDay == nil ) then
        return 2, "GetYearMonthDay 输入参数不能为空!","",""
    end
    seg = lua.split( strDay, "-" )
    if ( #seg ~= 3 ) then
        return 2, "GetYearMonthDay 格式非法!"..strDay,"",""
    end
    return 0, tonumber( seg[1] ), tonumber( seg[2] ), tonumber( seg[3] )
end

-- 计算两个日期差几天（⚠ 建议取消 HAN 2024-2-11，请用 lua.dateDiff）
-- @function lua.time_diff
-- @tparam number start_time 起始时间戳
-- @tparam number end_time 结束时间戳
-- @treturn number 天数差
function lua.time_diff(start_time, end_time)
    local t1 = os.date("%Y%m%d", start_time)
    local t2 = os.date("%Y%m%d", end_time)
    local day1 = {}
    local day2 = {}
    day1.year,day1.month,day1.day = string.match(t1,"(%d%d%d%d)(%d%d)(%d%d)")
    day2.year,day2.month,day2.day = string.match(t2,"(%d%d%d%d)(%d%d)(%d%d)")
    local numDay1 = os.time(day1)
    local numDay2 = os.time(day2)
    return (numDay2 - numDay1)/(3600*24)
end

-- 数组中追加一个值，已存在则忽略
-- @function lua.AddArray
-- @tparam table array 目标数组（会被修改）
-- @tparam any value 要追加的值
function lua.AddArray( array, value )
    local exist = false

    for _,v in pairs(array) do
        if ( v == value ) then
            exist = true
            break
        end
    end
    if not exist then
        table.insert( array, value )
    end
end

-- 从完整路径中提取文件名
-- @function lua.getFileNameInPath
-- @tparam string strPathFileName 完整文件路径
-- @treturn number nRet 0=成功，1=格式错误
-- @treturn string fileName 文件名
function lua.getFileNameInPath ( strPathFileName )
    local ts = string.reverse( strPathFileName )
    local i = string.find ( ts, "/" )

    if ( i == 0 or i == nil ) then
        return 1, "文件名格式不符合要求!"
    end

    local nSize = string.len(ts)
    local m = nSize - i + 1

    return 0, string.sub(strPathFileName, m+1, nSize)
end

-- JSON 字符串预处理：替换双引号为单引号、<> 替换为《》、按长度截断
-- 不推荐使用，建议取消: HAN 2024-2-11
-- @function lua.proJsonStrNode
-- @tparam string strJson 输入的 JSON 字符串
-- @tparam number nLen 允许的最大长度
-- @treturn string 处理后的字符串
function lua.proJsonStrNode( strJson, nLen )
    -- 把字符串中的"取消，用'替换
    strJson = string.gsub(strJson, '"',"'")
    -- 返回信息中<T>的处理把 <> 替换
    strJson = string.gsub(strJson, '<',"《")
    strJson = string.gsub(strJson, '>',"》")
    if (#strJson > nLen ) then
        strJson = string.sub( strJson, 1, nLen )
    end
    return  strJson
end
-- JSON 字符串转义：把双引号 " 转义为 \"
-- @function lua.FormatJsonString
-- @tparam string strJson 待转义的字符串
-- @treturn string 转义后的字符串
function lua.FormatJsonString( strJson )
    return string.gsub(strJson, '"','\\\"')
end

-- SQL 字符串转义：把单引号 ' 替换为双引号 "
-- @function lua.FormatSQLString
-- @tparam string strSQL 待转义的字符串
-- @treturn string 转义后的字符串
function lua.FormatSQLString( strSQL )
    return string.gsub(strSQL, "'",'"')
end

-- 返回 { attr = "xxx", value = "xxx" } 键值对对象
-- 不推荐使用，建议取消: HAN 2024-2-11
-- @function lua.KeyValueObj
-- @tparam string strAttr 属性名
-- @tparam any strValue 属性值
-- @treturn table 键值对表
function lua.KeyValueObj( strAttr, strValue )
    local key_value = {}

    strAttr = lua.trim( strAttr )
    key_value.attr = strAttr
    key_value.value = tostring(strValue)

    return key_value
end


-- 截掉字符串开头的某个指定字符（如 000232G090 开头去掉 0）
-- @function lua.TrimStrHead
-- @tparam string str 输入字符串
-- @tparam string trim_char 需要截掉的字符
-- @treturn string 处理后的字符串
function lua.TrimStrHead( str, trim_char )
    local n,nCount, m
    local ascii = string.byte( trim_char )

    nCount = string.len(str)
    m = 0

    if (string.byte( str,1) == ascii) then
        for n = 2, nCount do
            if (string.byte( str,n ) ~= ascii ) then
                m = n
                break
            end
        end
        if ( m ~= 0 ) then
            str = string.sub( str, m, -1)
        end
    end
    return str
end

-- 字符串前面填充指定字符到指定长度
-- @function lua.strFill
-- @tparam string str 输入字符串
-- @tparam number nLen 目标长度
-- @tparam string cFill 填充字符
-- @treturn string 填充后的字符串
function lua.strFill( str, nLen, cFill )
    local nSize = #str
    if nSize >= nLen then 
        return str 
    end
    return string.rep(cFill, nLen - nSize) .. str
end

-- 输入月份返回是第几个季度
-- @function lua.month_to_quarter
-- @tparam number month 月份（1-12）
-- @treturn number 季度（1-4），无效月份返回 -1
function lua.month_to_quarter(month)
    if month < 1 or month > 12 then
        return -1 -- 无效的月份
    elseif month >= 1 and month <= 3 then
        return 1 -- 第一季度
    elseif month >= 4 and month <= 6 then
        return 2 -- 第二季度
    elseif month >= 7 and month <= 9 then
        return 3 -- 第三季度
    else
        return 4 -- 第四季度
    end
end

-- 字符串转数值，空字符串返回 0
-- @function lua.StrToNumber
-- @tparam string|number strValue 输入值
-- @treturn number 转换后的数值
function lua.StrToNumber( strValue )
     if ( strValue == '' or strValue == nil ) then return 0 end
     return tonumber( strValue )
 end

-- 安全获取字符串属性值（nil 时返回空串）
-- @function lua.Get_StrAttrValue
-- @tparam any value 属性值
-- @treturn string 字符串值
function lua.Get_StrAttrValue( value )
     if ( value == nil ) then return "" end
     return value
 end

-- 安全获取数值属性值（nil/空串返回 0）
-- @function lua.Get_NumAttrValue
-- @tparam any value 属性值
-- @treturn number 数值
function lua.Get_NumAttrValue( value )
     if ( value == '' or value == nil ) then return 0 end
     local attr_type = type(value)
     if ( attr_type == "number" ) then return value end
     if ( attr_type == "string") then return tonumber( value ) end
     return 0
 end

-- 安全获取布尔属性值（nil/空串返回 false）
-- @function lua.Get_BoolAttrValue
-- @tparam any value 属性值
-- @treturn boolean 布尔值
function lua.Get_BoolAttrValue( value )
    if ( value == '' or value == nil ) then return false end
    if ( type(value) == "boolean" ) then return value end
    return false
end

-- 输出日志文件
-- @function lua.WriteLog
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string logType 日志类型（警告/错误）
-- @tparam string lua_file 文件名
-- @tparam number line 行号
-- @tparam string key 键
-- @tparam string value 值
function lua.WriteLog(strLuaDEID, logType, lua_file, line, key, value)
    local nRet, strRetInfo

    if ( value == nil ) then value = '' end
    nRet, strRetInfo = mobox.getLuaDEInfo(strLuaDEID)

    if (nRet ~= 0 or strRetInfo == '') then return end
    local lua_info, success
    success, lua_info = pcall( json.decode, strRetInfo)
    if ( success == false ) then return end

    -- local curTime = mobox.getCurTime_MS()

    local strLog = strLuaDEID.."|"..logType.."|"..lua_info.class_name.."|"..lua_info.event_source.."|"..
                   lua_info.event_name.."|"..lua_info.event_code.."|"..lua_file.."|"..line.."|"..
                   lua_info.user_name.."|"..key.."|"..value

    nRet = mobox.writeLuaLog( strLog )
end

-- 从 debug.getinfo 对象中提取文件名和行号（内部函数）
-- @function get_filename_line
-- @tparam table debug_info debug.getinfo 返回的表
-- @treturn number line 行号
-- @treturn string lua_file 文件名
local function get_filename_line( debug_info )
    local line = 0
    local lua_file = ''

    if (debug_info == nil or type(debug_info) ~= "table" ) then
        return 0,""
    else
        local pos1, pos2
        line = debug_info.currentline
        if (line == nil) then line = 0 end
        lua_file = debug_info.short_src
        pos1, pos2 = string.find(lua_file, ".lua")
        if (lua_file == nil or pos1 == nil) then lua_file = '' end
    end
    return  line, lua_file
end

-- 条件不具备时的等待处理：设置返回值为 4（等待后续处理）
-- @function lua.Wait
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strMsg 提示消息
function lua.Wait( strLuaDEID, strMsg )
   -- 4 条件不具备，等待后续处理
   mobox.setInfo( strLuaDEID, strMsg )
   -- 0  返回值是字符串
   mobox.returnValue( strLuaDEID, 0, "", 4 )
end

-- 调试日志输出（需传入 debug.getinfo 对象）
-- 不推荐使用，建议取消: HAN 2024-2-11
-- @function lua.Debug
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table debug_info debug.getinfo 对象
-- @tparam string key 键
-- @tparam any value 值
function lua.Debug( strLuaDEID, debug_info, key, value )
    local line = 0
    local lua_file = ''

    if ( value == nil ) then value = "nil" end
    if ( key == nil ) then key = "nil" end

    if( type(value) == "table"  and value.cls ~= nil ) then
        local nRet
        nRet, value = mobox.formatLuaJson( lua.table2str(value) )
    end

    local value_type = type(value)
    if ( value_type == "boolean") then
        if ( value ) then
            value = "true"
        else
            value = "false"
        end
    elseif ( value_type == "table") then
        value = lua.table2str( value )
    end

    line, lua_file = get_filename_line( debug_info )
    local nRet, strRetInfo

    nRet, strRetInfo = mobox.getLuaDEInfo(strLuaDEID)
    if (nRet ~= 0 or strRetInfo == '') then error( "WriteLog 函数调用 getLuaDEInfo 失败!"..strRetInfo  ) end
    local lua_info, success
    success, lua_info = pcall( json.decode, strRetInfo)
    if ( success == false ) then return end
    -- 如果设置了不显示Debug信息，马上返回
    if (lua_info.gen_lua_log == 0 ) then return end
    local class_name = lua_info.class_name or ''
    local event_source = lua_info.event_source or ''
    local event_name = lua_info.event_name or ''
    local event_code = lua_info.event_code or ''

    -- local curTime = mobox.getCurTime_MS()
    local strLog = strLuaDEID.."|调试|"..class_name.."|"..event_source.."|"..event_name.."|"..event_code.."|"..lua_file.."|"..
                   line.."|"..lua_info.user_name.."|"..key.."|"..value
    nRet = mobox.writeLuaLog( strLog )

end

-- 调试日志输出
-- @function lua.DebugEx
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string key 键
-- @tparam any value 值
-- @tparam string module_name 模块名（可选）
function lua.DebugEx( strLuaDEID, key, value, module_name )
    local line = 0
    local lua_file = ''
    local nRet, strRetInfo

    if ( value == nil ) then value = "nil" end
    if ( key == nil ) then key = "nil" end
    if module_name == nil then module_name = '' end

    nRet, strRetInfo = mobox.getLuaDEInfo(strLuaDEID)
    if (nRet ~= 0 or strRetInfo == '') then return end
    local lua_info, success
    success, lua_info = pcall( json.decode, strRetInfo)
    if ( success == false ) then return end
    if ( lua_info.gen_lua_info == 0 ) then return end

    local debug_info = debug.getinfo(2)
    if( type(value) == "table"  and value.cls ~= nil ) then
        local nRet
        nRet, value = mobox.formatLuaJson( lua.table2str(value) )
    end

    local value_type = type(value)
    if ( value_type == "boolean") then
        if ( value ) then
            value = "true"
        else
            value = "false"
        end
    elseif ( value_type == "table") then
        value = lua.table2str( value )
    end

    line, lua_file = get_filename_line( debug_info )

    local class_name = lua_info.class_name or ''
    local event_source = lua_info.event_source or ''
    local event_name = lua_info.event_name or ''
    local event_code = lua_info.event_code or ''
    local strLog = strLuaDEID.."|调试|"..class_name.."|"..event_source.."|"..event_name.."|"..event_code.."|"..lua_file.."|"..
                   line.."|"..lua_info.user_name.."|"..key.."|"..value.."|"..module_name
    nRet = mobox.writeLuaLog( strLog )

end

-- WCS 调试日志输出
-- @function lua.WCSDebugEx
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string key 键
-- @tparam any value 值
function lua.WCSDebugEx( strLuaDEID, key, value )
    local line = 0
    local lua_file = ''
    local nRet, strRetInfo

    if ( value == nil ) then value = "nil" end
    if ( key == nil ) then key = "nil" end

    nRet, strRetInfo = mobox.getLuaDEInfo(strLuaDEID)
    if (nRet ~= 0 or strRetInfo == '') then return end
    local lua_info, success
    success, lua_info = pcall( json.decode, strRetInfo)
    if ( success == false ) then return end
    if ( lua_info.gen_lua_info == 0 ) then return end

    local debug_info = debug.getinfo(2)
    if( type(value) == "table" and value.cls ~= nil ) then
        local nRet
        nRet, value = mobox.formatLuaJson( lua.table2str(value) )
    end
    if ( value == nil ) then value = "nil" end

    local value_type = type(value)
    if ( value_type == "boolean") then
        if ( value ) then
            value = "true"
        else
            value = "false"
        end
    elseif ( value_type == "table") then
        value = lua.table2str( value )
    end

    line, lua_file = get_filename_line( debug_info )
    local strLog = strLuaDEID.."|调试|"..lua_info.class_name.."|"..lua_info.event_source.."|"..lua_info.event_name.."|"..lua_info.event_code.."|"..lua_file.."|"..line.."|"..lua_info.user_name.."|"..key.."|"..value
    nRet = wms.wms_WriteWCSLog( strLog )

end

-- 设置 mobox.stopProgram 终止脚本执行
-- @function lua.Stop
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string msg 终止原因
function lua.Stop( strLuaDEID, msg )
    local line = 0
    local lua_file = ''
    local nRet, strRetInfo

    nRet, strRetInfo = mobox.getLuaDEInfo(strLuaDEID)
    if (nRet ~= 0 or strRetInfo == '') then return end
    local lua_info, success
    success, lua_info = pcall( json.decode, strRetInfo)
    if ( success == false ) then return end

    local debug_info = debug.getinfo(2)

    line, lua_file = get_filename_line( debug_info )
    local str_msg = "在编码'"..lua_info.event_code.."' 名称:',"..lua_info.event_name.."'的脚本中第("..line..")行终止执行，原因:"..msg
    mobox.stopProgram( strLuaDEID, msg )
    lua.WriteLog( strLuaDEID, "警告", lua_file, line, "", str_msg )
end


-- 输出 Lua 脚本执行时的警告信息
-- @function lua.Warning
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table debug_info debug.getinfo 对象
-- @tparam string warnInfo 警告信息
function lua.Warning( strLuaDEID, debug_info, warnInfo )
    local line = 0
    local lua_file = ''

    line, lua_file = get_filename_line( debug_info )
    lua.WriteLog( strLuaDEID, "警告", lua_file, line, "", warnInfo)
end

-- 输出 Lua 脚本执行时的错误信息并抛出 error
-- 不推荐使用，建议取消: HAN 2024-2-11
-- @function lua.Error
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table debug_info debug.getinfo 对象
-- @tparam string errorInfo 错误信息
function lua.Error( strLuaDEID, debug_info, errorInfo )
    local line = 0
    local lua_file = ''

    line, lua_file = get_filename_line( debug_info )
    lua.WriteLog( strLuaDEID, "错误", lua_file, line, "", errorInfo)
    error( errorInfo )
end

-- 把字符 Y 转成 true，N 转成 false
-- @function lua.YesNo2Bool
-- @tparam string strYesNo 输入字符
-- @treturn boolean true/false
function lua.YesNo2Bool( strYesNo )
    if ( strYesNo == nil or strYesNo == '' ) then return false end
    if ( strYesNo == 'Y' ) then
        return true
    elseif ( strYesNo == 'N') then
        return false
    end
    return false
end

-- 判断字符串是否为无效值（nil/空串/非字符串）
-- @function lua.StrIsEmpty
-- @tparam any strValue 要判断的值
-- @treturn boolean true=为空或无效
function lua.StrIsEmpty( strValue )
    if ( strValue == nil or strValue == '' or type( strValue ) ~= "string" ) then
        return true
    else
        return false
    end
end

-- 字符减 1（ASCII 码减 1）
-- @function lua.DecrementChar
-- @tparam string char 输入字符
-- @treturn string 减 1 后的字符
function lua.DecrementChar(char)
    local ascii = string.byte(char) - 1
    return string.char(ascii)
end

-- 字符加 1（ASCII 码加 1）
-- @function lua.IncrementalChar
-- @tparam string char 输入字符
-- @treturn string 加 1 后的字符
function lua.IncrementalChar(char)
    local ascii = string.byte(char) + 1
    return string.char(ascii)
end

-- 创建只读常量表（通过元表禁止写入）
-- @function lua.MakeConstantTable
-- @tparam table t 源表
-- @treturn table 只读代理表
function lua.MakeConstantTable(t)
    local proxy = {}
    local mt = {
        -- 元方法：用于访问表中的值
        __index = t,
        -- 元方法：当尝试修改表中的值时，抛出错误
        __newindex = function(t, k, v)
            error("attempt to update a read-only table", 2)
        end
    }
    setmetatable(proxy, mt)
    return proxy
end

-- 根据属性名数组和值数组构造键值对表（如 {S_ITEM_CODE, S_QTY} + {A, 10} -> {S_ITEM_CODE="A", S_QTY=10}）
-- @function lua.GetDataAttrObj_By_StrArray
-- @tparam table attr_set 属性名数组
-- @tparam table value_set 值数组
-- @treturn number nRet 0=成功，1=失败
-- @treturn table data_attr 键值对表
function lua.GetDataAttrObj_By_StrArray( attr_set, value_set )
    local nRet, strRetInfo
    local data_attr = {}

    if ( attr_set == nil or type(attr_set) ~= "table" ) then
        return 1, "GetDataAttrObj_By_StrArray 输入参数 attr_set 不合规!"
    end
    if ( value_set == nil or type(value_set) ~= "table" ) then
        return 1, "GetDataAttrObj_By_StrArray 输入参数 value_set 不合规!"
    end
    local attr_count = #attr_set
    local value_count = #value_set

    if ( attr_count ~= value_count ) then
        return 1, "GetDataAttrObj_By_StrArray 输入的属性和值的数量不一致!"
    end

    for n = 1, attr_count do
        data_attr[attr_set[n]] = value_set[n]
    end
    return 0, data_attr
end

-- 获取 Lua 数据交换区信息并解码为 table
-- @function lua.GetLuaDEInfo
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number nRet 0=成功，1=失败
-- @treturn table|string 成功时返回 lua_info 表，失败时返回错误信息
function lua.GetLuaDEInfo( strLuaDEID )
    local nRet, strRetInfo

    nRet, strRetInfo = mobox.getLuaDEInfo(strLuaDEID)
    if nRet ~= 0 or strRetInfo == '' then
        return 1, strRetInfo
    end
    local lua_info, success
    success, lua_info = pcall( json.decode, strRetInfo )
    if success == false then
        return 1, "获取 Lua 数据交换区信息失败!"
    end
    return 0, lua_info
end

-- 执行多条 SQL 语句（以分号分隔）
-- @function lua.RunSQL
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strSQL SQL 语句（可用分号分隔多条）
-- @treturn number nRet 0=成功，1=失败
-- @treturn string strRetInfo 失败时的错误信息
function lua.RunSQL( strLuaDEID, strSQL )
    local nRet, strRetInfo
    local seg_sql = lua.split( strSQL, ";" )

    for _, sql in pairs( seg_sql ) do
        nRet, strRetInfo = mobox.runSQL( strLuaDEID, sql )
        if nRet ~= 0 then
            return 1, strRetInfo
        end
    end

    return 0
end

-- 检查数据对象中指定属性是否存在重复记录
-- @function lua.Have_Duplicates_Data
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cls_id 数据类标识
-- @tparam table data_attrs 需要判重的属性数组（如 {"A","B"}）
-- @tparam string condition 查询条件（可选）
-- @treturn number nRet 0=成功，1=失败
-- @treturn boolean hasDuplicates true=存在重复
function lua.Have_Duplicates_Data( strLuaDEID, cls_id, data_attrs, condition )
    local nRet, strRetInfo


    if lua.StrIsEmpty( cls_id ) then
        return 1, "函数 lua.Have_Duplicates_Data 中 cls_id 必须有值!"
    end
    if lua.IsTableEmpty( data_attrs ) then
        return 1, "函数 lua.Have_Duplicates_Data 中 data_attrs 必须有值，而且必须table类型!"
    end
    if condition == nil then condition = '' end
    local group_attrs = ''
    for _, attr in ipairs( data_attrs ) do
        group_attrs = group_attrs..attr..","
    end
    group_attrs = lua.trim_laster_char( group_attrs )

    local strCondition = condition.."GROUP BY "..group_attrs.." HAVING COUNT(*) > 1"
    local attrs = {}
    table.insert( attrs, "1 AS result")
    local tab_name = "TN_"..cls_id

    nRet, strRetInfo = mobox.queryTable( strLuaDEID, tab_name, json.encode(attrs), 100, strCondition )
    if nRet == 0 then
        local ret_value = json.decode( strRetInfo )

        if lua.isTableEmpty( ret_value ) then
            -- 不存在相同 Key attrs相同的数据集合
            return 0, false
        else
            return 0, true
        end
    end
    return 1, strRetInfo
end

-- 获取后台脚本执行结果（轮询等待）
-- @function lua.GetBackgroundScript_Result
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string proc_id 后台脚本进程 ID
-- @tparam number wait_time 等待最大时间（分钟），默认 1
-- @treturn number nRet 0=成功，1=超时，2=失败
-- @treturn string result 成功时返回解码后的结果
function lua.GetBackgroundScript_Result( strLuaDEID, proc_id, wait_time )
    --通过 pro_id 获取后台线程计算库位结果
    if wait_time == nil then
        wait_time = 1
    end

    local WAIT = wait_time*300   --1次是200毫秒，1分钟是60*5
    local n =  1
    local nRet, strRetInfo

    while ( n < WAIT ) do
        nRet, strRetInfo = mobox.getBackendScriptProcResult( proc_id )

        if nRet == 0 then
            -- 后台脚本还没处理完成
            mobox.sleep( 200 )  -- 等待200毫秒
            n = n + 1
        elseif nRet == 1 then
            -- 成功
            local result = json.decode( strRetInfo )
            return 0, result
        else
            return 2, strRetInfo
        end
    end
    return 1, "后台脚本超时!"
end

-- 取消字符串前后空格并转小写
-- @function lua.Normalize_String
-- @tparam string str 待处理的字符串
-- @treturn string 处理后的字符串
function lua.Normalize_String( str )
    return type(str) == "string" and string.lower(string.match(str,"^%s*(.-)%s*$")) or str
end

-- 浅拷贝表（一级属性复制） 不建议使用，建议用 table_deepcopy
-- @function lua.table_copy
-- @tparam table tbl copy的table
-- @treturn table copy
function lua.table_copy(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end

    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = v
    end
    return copy
end

-- 深拷贝表（递归复制所有层级，含元表）
-- @function lua.table_deepcopy
-- @tparam any tbl 要深拷贝的值
-- @treturn any 深拷贝后的值
function lua.table_deepcopy(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end

    local copy = {}
    for k, v in pairs(tbl) do
        copy[lua.table_deepcopy(k)] = lua.table_deepcopy(v)
    end
    setmetatable(copy, lua.table_deepcopy(getmetatable(tbl)))
    return copy
end

-- 根据模块名和函数名动态调用函数（支持可变参数）
-- @function lua.callFunctionByName
-- @tparam string moduleName 全局模块名
-- @tparam string funcName 函数名
-- @tparam ... 传给目标函数的参数
-- @treturn number nRet 0=成功，1=模块/函数不存在
-- @treturn any result 目标函数的返回值
function lua.callFunctionByName(moduleName, funcName, ...)
    local module = _G[moduleName]

    if module == nil then
        return 1, "模块 '" .. moduleName .. "' 不存在"
    end
    local func = module[funcName]

    if func then
        local nRet, strRetInfo = func(...)
        return nRet, strRetInfo
    else
        return 1, "函数 '" .. funcName .. "' 不存在"
    end
end

return lua