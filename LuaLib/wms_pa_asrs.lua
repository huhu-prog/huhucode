
--[[
    版本：     Version 1.0
    创建日期： 2026-03-12
    创建人：   XDL

        WMS Putaway Algorithms
        上架策略算法 -- 自动化立库
    功能：
        支持单、双深位
        货位高度ASRS_Get_StockLoc
        货位载重限制

    主函数： ASRS_Get_StockLocASRS_Get_StockLoc
    - 立库上架货位计算
            
    1. 获取所有可用货位
    2. 按权重排序
    3. 按列排序规则排序
    4. 返回权重最高货位

--]]
local M = {
    _version = "1.0.0"
}

-- 辅助函数：安全解析JSON
-- @function _safe_json_decode
-- @tparam string|nil json_str JSON字符串
-- @treturn table|nil 解析后的数据，失败返回nil
local function _safe_json_decode(json_str)
    if not json_str or json_str == "" then
        return nil
    end
    if not json or not json.decode then
        return nil
    end
    local success, result = pcall(json.decode, json_str)
    return success and result or nil
end

-- 辅助函数：转义SQL参数中的单引号，防止SQL注入
-- @function _escape_sql
-- @tparam string|nil value 需要转义的值
-- @treturn string 转义后的值
local function _escape_sql(value)
    if value == nil then
        return ""
    end
    return string.gsub(tostring(value), "'", "''")
end
-- 辅助函数：校验输入参数
-- @function _validate_params
-- @tparam table params 待验证的参数表
-- @tparam table required 必传参数名数组
-- @treturn boolean 验证通过返回true
-- @treturn string|nil 验证失败返回错误信息
local function _invalid_pa_cfg(params, required)
    if not params or type(params) ~= "table" then
        return false, "参数必须是 table 类型"
    end
    for _, key in ipairs(required) do
        local val = params[key]
        if not val or (type(val) == "string" and val == "") then
            return false, "缺少必要参数: " .. key
        end
    end
    return true
end

-- 本地函数：校验立库预留空位数，确保立库保留一定数量的空位作为移库等备用
-- @function _check_reserve_empty_locs
--[[ params 参数说明:
    {
        wh_code: string          -- 仓库编码
        area_code: string       -- 库区编码
        enable_limit: boolean   -- 是否启用限制
        limit_num: number       -- 限制的备用空位数
        pallet_height: number   -- 当前托盘高度, 可选
        pallet_weight: number   -- 当前托盘总重, 可选
    }
--]]
-- @treturn boolean true 校验通过
-- @treturn string|nil 错误信息，校验失败时返回
local function _check_reserve_empty_locs(strLuaDEID, params)
    local cfg = params or {}
    local wh_code = cfg.wh_code
    local area_code = cfg.area_code
    local enable_limit = cfg.enable_limit
    local limit_num = cfg.limit_num
    local pallet_height = cfg.pallet_height
    local pallet_weight = cfg.pallet_weight

    -- 如果未启用限制，直接通过
    if not enable_limit then
        return true
    end

    -- 确保限制数为正整数
    limit_num = tonumber(limit_num) or 20
    if limit_num <= 0 then
        return true
    end

    -- 构建高度和载重限制条件
    local cond = ""
    if pallet_height and pallet_height > 0 then
        cond = cond .. string.format(" AND F_HEIGHT >= %d", pallet_height)
    end
    if pallet_weight and pallet_weight > 0 then
        cond = cond .. string.format(" AND F_MAX_WEIGHT >= %d", pallet_weight)
    end

    -- 查询立库当前剩余空位数
    local nRet, strRetInfo = mobox.getDataObjCount(strLuaDEID, "Location",
        string.format("S_WH_CODE = '%s' AND S_AREA_CODE = '%s' AND N_CURRENT_NUM = 0 AND N_LOCK_STATE = 0%s",
            _escape_sql(wh_code or ""), _escape_sql(area_code or ""), cond))

    if nRet ~= 0 then
        return nil, "查询立库预留空位数失败: " .. tostring(strRetInfo)
    end

    local current_empty_count = tonumber(strRetInfo) or 0

    if current_empty_count <= limit_num then
        return nil, string.format("立库剩余可用空位数(%d)已达预留数限制(%d)，不可入库",
            current_empty_count, limit_num)
    end

    return true
end

-- 权重常量
local WEIGHT_INNER_EMPTY = 100 -- 最优：内深位空，对应外深位也空
local WEIGHT_OUTER_EMPTY = 50 -- 其次：外深位空，对应内深位有货
local WEIGHT_SINGLE_DEEP = 10 -- 备用：单深位空

-- 本地函数：构建高度和载重限制条件
-- @function _build_height_weight_condition
-- @tparam number|nil pallet_height 托盘高度
-- @tparam number|nil pallet_weight 托盘总重
-- @treturn string SQL条件字符串
local function _build_height_weight_condition(pallet_height, pallet_weight)
    local condition = ""
    if pallet_height and pallet_height > 0 then
        condition = condition .. string.format("N_HEIGHT >= %.2f", pallet_height)
    end
    if pallet_weight and pallet_weight > 0 then
        if condition ~= "" then
            condition = condition .. " AND "
        end
        condition = condition .. string.format("F_MAX_WEIGHT >= %.2f", pallet_weight)
    end
    return condition
end

-- 本地函数：构建排序规则
-- @function _build_order_rule
-- @tparam number order_method 排序方法
-- @tparam number loc_order 列排序方向
-- @treturn string SQL排序规则字符串
--[[
	order_method参数说明：
		0：按权重排序，使用 N_POS_WEIGHT 字段
		1：按层、列、排排序，即先放满层（从底层开始）, 列按从大到小或者从小到大，一层铺满后，排交替
		2：按排、列、层排序，即先放满排（从最小排开始），列按从大到小或者从小到大，从底层开始，一排放完，放另外一排
		其他值（默认3）：按列、排、层排序，即先放满列（从最小或最大列开始），层从下往上，一列铺满后，排交替
--]]
local function _build_order_rule(order_method, loc_order)
    local strOrder = "F_HEIGHT ASC, F_MAX_WEIGHT ASC"

    if order_method == 0 then
        strOrder = strOrder .. (loc_order == 2 and ", N_POS_WEIGHT DESC" or ", N_POS_WEIGHT ASC")
    elseif order_method == 1 then
        strOrder = strOrder ..
                       (loc_order == 2 and ", N_LAYER ASC, N_COL DESC, N_ROW ASC" or
                           ", N_LAYER ASC, N_COL ASC, N_ROW ASC")
    elseif order_method == 2 then
        strOrder = strOrder ..
                       (loc_order == 2 and ", N_ROW ASC, N_COL DESC, N_LAYER ASC" or
                           ", N_ROW ASC, N_COL ASC, N_LAYER ASC")
    else
        strOrder = strOrder ..
                       (loc_order == 2 and ", N_COL DESC, N_ROW ASC, N_LAYER ASC" or
                           ", N_COL ASC, N_ROW ASC, N_LAYER ASC")
    end

    return strOrder
end

-- 入口函数：立库上架货位计算
-- @function M.ASRS_Get_StockLoc
--[[ pa_cfg 参数说明:
    {
        wh_code: string           -- 仓库编码, 必传
        area_code: string         -- 库区编码, 必传
        cntr_code: string         -- 容器编码, 必传
        aisle: string|table       -- 巷道编码, 可选
        order_method: number      -- 排序方法, 默认1
        loc_order: number         -- 列排序方向, 默认1
        enable_reserve_empty: boolean  -- 启用预留空位, 可选, 默认false
        reserve_empty_count: number    -- 预留空货位数, 可选, 默认 20
    }
--]]
-- @treturn table|nil 货位结果，失败时nil
-- @treturn string|nil 错误信息，成功时nil
function M.ASRS_Get_StockLoc(strLuaDEID, pa_cfg)
    local nRet, strRetInfo

    -- 必传参数校验
    local check_ok, err = _invalid_pa_cfg(pa_cfg, {"wh_code", "area_code", "cntr_code"})
    if not check_ok then
        return nil, err
    end

    local wh_code = pa_cfg.wh_code
    local area_code = pa_cfg.area_code
    local cntr_code = pa_cfg.cntr_code
    local order_method = pa_cfg.order_method or 1
    local loc_order = pa_cfg.loc_order or 1
    local aisles = pa_cfg.aisle or nil
    local enable_reserve_empty = pa_cfg.enable_reserve_empty == true
    local reserve_empty_count = pa_cfg.reserve_empty_count or 20

    -- step 1. 获取托盘的高度和重量信息
    local pallet_height = nil
    local pallet_weight = nil

    -- cntr_code 为必传参数，已经过校验，不会为空
    if cntr_code ~= "" then
        -- 查询容器/托盘信息
        local cntr_condition = string.format("S_CODE = '%s'", _escape_sql(cntr_code))
        local cntr_nRet, cntr_objs = m3.QueryDataObject3(strLuaDEID, "Container", cntr_condition, "", 1)

        if cntr_nRet == 0 and #cntr_objs > 0 then
            local cntr_attrs = m3.KeyValueAttrsToObjAttr(cntr_objs[1].attrs) or {}
            pallet_height = lua.StrToNumber(cntr_attrs.F_HEIGHT) -- 容器高度

            pallet_weight = lua.StrToNumber(cntr_attrs.F_GOOD_WEIGHT) -- 容器重量
        else
            return nil, "未找到托盘信息或托盘为空: " .. cntr_code
        end
    end

    -- step 2. 校验立库预留空货位数量（考虑高度和载重限制）
    if enable_reserve_empty then
        local reserveRet, reserveMsg = _check_reserve_empty_locs(strLuaDEID, {
            wh_code = wh_code,
            area_code = area_code,
            enable_limit = true,
            limit_num = reserve_empty_count,
            pallet_height = pallet_height,
            pallet_weight = pallet_weight
        })

        if not reserveRet then
            return nil, "校验立库预留空位数失败: " .. reserveMsg
        end
    end

    -- 构建查询参数
    local query_params = {
        wh_code = wh_code,
        area_code = area_code,
        aisles = aisles,
        order_method = order_method,
        loc_order = loc_order,
        pallet_height = pallet_height,
        pallet_weight = pallet_weight
    }

    -- 判断巷道参数值
    local has_aisles = false
    if aisles then
        if type(aisles) == "table" and #aisles > 0 then
            has_aisles = true
        elseif type(aisles) == "string" and aisles ~= "" then
            has_aisles = true
        end
    end

    -- step 3. 指定了巷道，在指定巷道中查找
    if has_aisles then
        local result = M.Get_Highest_Weight_Location(strLuaDEID, query_params)

        if result then
            return result
        end
        return nil, "指定巷道中没有可用货位"
    end

    -- step 4. 没有指定巷道，进行巷道任务均衡和空货位均衡
    local aisle_conditions = {}
    table.insert(aisle_conditions, string.format("S_WH_CODE = '%s'", _escape_sql(wh_code)))
    if area_code ~= "" then
        table.insert(aisle_conditions, string.format("S_AREA_CODE = '%s'", _escape_sql(area_code)))
    end
    local strCondition = table.concat(aisle_conditions, " AND ")
    local aisle_objs
    nRet, aisle_objs = m3.QueryDataObject(strLuaDEID, "Aisle", strCondition, "S_AISLE_CODE")
    if nRet ~= 0 then
        return nil, "获取巷道信息失败: " .. aisle_objs
    end

    -- step 5. 为每个巷道计算任务数和空货位数，并排序
    local aisles_with_tasks = {}

    if not aisle_objs or type(aisle_objs) ~= "table" or #aisle_objs == 0 then
        return nil, "巷道列表为空"
    end

    for _, obj in ipairs(aisle_objs) do
        local attrs = m3.KeyValueAttrsToObjAttr(obj.attrs) or {}
        local aisle_code = attrs.S_AISLE_CODE
        local aisle = attrs.N_AISLE

        -- 获取巷道任务数
        strCondition = string.format("N_B_STATE < 3 AND ( S_START_AISLE_CODE = '%s' OR S_END_AISLE_CODE = '%s')",
            _escape_sql(aisle_code), _escape_sql(aisle_code))
        nRet, strRetInfo = mobox.getDataObjCount(strLuaDEID, "Task", strCondition)

        local task_num = 0
        if nRet == 0 then
            task_num = lua.StrToNumber(strRetInfo)
        end

        -- 获取巷道空货位数
        local empty_loc_conditions = {}
        table.insert(empty_loc_conditions, string.format("S_WH_CODE = '%s'", _escape_sql(wh_code)))
        -- 库区编码
        if area_code ~= "" then
            table.insert(empty_loc_conditions, string.format("S_AREA_CODE = '%s'", _escape_sql(area_code)))
        end
        -- 所属巷道
        if aisle ~= "" then
            table.insert(empty_loc_conditions, string.format("N_AISLE = '%s'", _escape_sql(aisle)))
        end
        table.insert(empty_loc_conditions, "N_CURRENT_NUM = 0")
        table.insert(empty_loc_conditions, "(N_LOCK_STATE IS NULL OR N_LOCK_STATE = 0)")
        -- （考虑高度和载重限制）
        local height_weight_cond = _build_height_weight_condition(pallet_height, pallet_weight)
        if height_weight_cond and height_weight_cond ~= "" then
            table.insert(empty_loc_conditions, height_weight_cond)
        end
        local empty_loc_condition = table.concat(empty_loc_conditions, " AND ")

        nRet, strRetInfo = mobox.getDataObjCount(strLuaDEID, "Location", empty_loc_condition)

        local empty_loc_num = 0
        if nRet == 0 then
            empty_loc_num = lua.StrToNumber(strRetInfo)
        end

        table.insert(aisles_with_tasks, {
            aisle_code = aisle,
            task_num = task_num,
            empty_loc_num = empty_loc_num
        })
    end

    -- 综合排序：优先任务数少的，任务数相同时优先空货位数多的
    table.sort(aisles_with_tasks, function(a, b)
        if a.task_num ~= b.task_num then
            return a.task_num < b.task_num -- 任务少的优先
        end
        return a.empty_loc_num > b.empty_loc_num -- 空货位多的优先
    end)

    -- step 6. 按任务数从少到多依次尝试查找货位，找到后立即返回
    for _, aisle_info in ipairs(aisles_with_tasks) do
        local aisle_code = aisle_info.aisle_code
        local query_params_single = {
            wh_code = wh_code,
            area_code = area_code,
            aisles = {aisle_code},
            order_method = order_method,
            loc_order = loc_order,
            pallet_height = pallet_height,
            pallet_weight = pallet_weight
        }

        local loc_result = M.Get_Highest_Weight_Location(strLuaDEID, query_params_single)

        if loc_result then
            return loc_result
        end
    end

    return nil, "库区内没有可用货位"
end

-- 辅助函数：获取交替排列的列顺序
-- @function get_alternate_cols
-- @tparam table colGroups 列分组表
-- @tparam number loc_order 列排序方向
-- @treturn table 排序后的列顺序
--[[
    loc_order说明:
        loc_order == 1: 列从小到大（正序）
        loc_order == 2: 列从大到小（逆序）
        loc_order == 3: 从两头往中间列交替摆放
        loc_order == 4: 从中间列往两头交替摆放
--]]
local function _get_alternate_cols(colGroups, loc_order)
    -- 获取所有列号，转换为数字排序
    local cols = {}
    for col, _ in pairs(colGroups) do
        table.insert(cols, tonumber(col) or col)
    end

    -- 按列号排序（数字排序）
    table.sort(cols, function(a, b)
        return (tonumber(a) or 0) < (tonumber(b) or 0)
    end)

    if #cols == 0 then
        return {}
    end

    local result = {}

    if loc_order == 1 then
        -- 列从小到大（正序）
        result = cols
    elseif loc_order == 2 then
        -- 列从大到小（逆序）
        for i = #cols, 1, -1 do
            table.insert(result, cols[i])
        end
    elseif loc_order == 3 then
        -- 从两头往中间列交替摆放
        -- 例如: [1,2,3,4,5] -> [1,5,2,4,3]
        local left = 1
        local right = #cols

        while left <= right do
            table.insert(result, cols[left])
            if left ~= right then
                table.insert(result, cols[right])
            end
            left = left + 1
            right = right - 1
        end
    elseif loc_order == 4 then
        -- 从中间列往两头交替摆放
        -- 例如: [1,2,3,4,5] -> [3,2,4,1,5]
        local mid = math.ceil(#cols / 2)
        -- 先放中间列
        table.insert(result, cols[mid])
        -- 然后交替从左右两边取
        local left = mid - 1
        local right = mid + 1
        while left >= 1 or right <= #cols do
            if left >= 1 then
                table.insert(result, cols[left])
                left = left - 1
            end
            if right <= #cols then
                table.insert(result, cols[right])
                right = right + 1
            end
        end
    else
        -- 默认列从小到大
        result = cols
    end

    return result
end

-- 辅助函数：交替排序货位
-- @function _alternate_sort_locations
-- @tparam table dataSet 货位数据集
-- @tparam number loc_order 列排序方向
-- @treturn table 排序后的数据集
local function _alternate_sort_locations(dataSet, loc_order)
    if #dataSet == 0 then
        return dataSet
    end

    -- 如果loc_order不是3或4，不需要交替排序，直接返回
    if loc_order ~= 3 and loc_order ~= 4 then
        return dataSet
    end

    -- 1. 先按巷道分组
    local aisleGroups = {}
    for _, item in ipairs(dataSet) do
        local aisle = item.aisle or ""
        if not aisleGroups[aisle] then
            aisleGroups[aisle] = {}
        end
        table.insert(aisleGroups[aisle], item)
    end

    -- 获取巷道顺序（保持原始传入顺序）
    local aisleList = {}
    local aisleIndexMap = {}
    local idx = 1
    for _, item in ipairs(dataSet) do
        local aisle = item.aisle or ""
        if not aisleIndexMap[aisle] then
            aisleIndexMap[aisle] = idx
            table.insert(aisleList, aisle)
            idx = idx + 1
        end
    end
    table.sort(aisleList, function(a, b)
        return aisleIndexMap[a] < aisleIndexMap[b]
    end)

    -- 2. 对每个巷道内的货位进行排序
    -- 核心逻辑：先按权重降序，权重相同时按列交替
    local sortedResults = {}
    for _, aisle in ipairs(aisleList) do
        local aisleItems = aisleGroups[aisle]
        if aisleItems and #aisleItems > 0 then
            -- 2.1 获取该巷道内的所有列（用于计算交替顺序）
            local colGroups = {}
            for _, item in ipairs(aisleItems) do
                local col = item.col or 0
                if not colGroups[col] then
                    colGroups[col] = {}
                end
            end

            -- 2.2 获取交替排列的列顺序
            local sortedCols = _get_alternate_cols(colGroups, loc_order)

            -- 2.3 创建列位置映射：col -> 在交替顺序中的位置
            local colPosition = {}
            for pos, col in ipairs(sortedCols) do
                colPosition[col] = pos
            end

            -- 2.4 排序：先按权重降序，权重相同时按列交替位置排序
            table.sort(aisleItems, function(a, b)
                -- 先按权重降序
                if a.weight ~= b.weight then
                    return a.weight > b.weight
                end
                -- 权重相同时，按列交替位置排序
                local posA = colPosition[a.col or 0] or 999
                local posB = colPosition[b.col or 0] or 999
                if posA ~= posB then
                    return posA < posB
                end
                -- 列位置也相同时，保持原始顺序
                return (a.original_idx or 0) < (b.original_idx or 0)
            end)

            -- 添加到结果
            for _, item in ipairs(aisleItems) do
                table.insert(sortedResults, item)
            end
        end
    end

    return sortedResults
end

-- 本地函数：应用交替排序
-- @function _apply_alternate_sort
-- @tparam table dataSet 货位数据集
-- @tparam number order_method 排序方法
-- @tparam number loc_order 列排序方向
-- @treturn table 排序后的数据集
local function _apply_alternate_sort(dataSet, loc_order)
    if (loc_order == 3 or loc_order == 4) and #dataSet > 0 then
        return _alternate_sort_locations(dataSet, loc_order)
    end
    return dataSet
end

-- 本地函数：使用SQL查询可用货位
-- @function _fetch_available_locations
-- @tparam table params 查询参数
--[[ params 参数说明:
    {
        wh_code: string       -- 仓库编码
        area_code: string    -- 库区编码
        aisles: string|table -- 巷道编码
        pallet_height: number -- 托盘高度, 可选
        pallet_weight: number -- 托盘重量, 可选
        order_method: number -- 排序方法, 默认1
        loc_order: number    -- 列排序方向, 默认1
    }
--]]
-- @treturn table 可用货位列表
local function _fetch_available_locations(strLuaDEID, params)
    local wh_code = params.wh_code
    local area_code = params.area_code
    local aisles = params.aisles
    local pallet_height = params.pallet_height
    local pallet_weight = params.pallet_weight
    local order_method = params.order_method or 1
    local loc_order = params.loc_order or 1

    -- 确保 aisles 是数组，去重处理
    local aisle_list = {}
    if type(aisles) == "table" then
        local seen = {}
        for _, v in ipairs(aisles) do
            if v and v ~= "" and not seen[v] then
                seen[v] = true
                table.insert(aisle_list, v)
            end
        end
    elseif type(aisles) == "string" and aisles ~= "" then
        aisle_list = {aisles}
    end

    if #aisle_list == 0 then
        return {}
    end
    -- 拼接高低位sql条件
    local height_weight_cond = _build_height_weight_condition(pallet_height, pallet_weight)
    -- 拼接排序
    local sort_field = _build_order_rule(order_method, loc_order)

    local results = {}
    local strRetInfo

    -- 获取数据库类型，只调用一次
    local lock_hint = ""
    local nRet, lua_info
    nRet, lua_info = lua.GetLuaDEInfo(strLuaDEID)
    if nRet ~= 0 then
        return nil, "GetLuaDEInfo 失败!" .. lua_info
    end

    -- 判断数据库类型 SQLServer 需要加 with (NOLOCK)
    if lua_info and lua_info.dbtype == DB_TYPE.SQLServer then
        lock_hint = " with (NOLOCK) "
    end

    for _, aisle in ipairs(aisle_list) do
        -- 使用 queryMultiTable2 查询所有可用货位
        -- 查询字段：直接获取配对货位编码，避免后续再单独查询
        local strAttrInfo = string.format(
            "loc.S_CODE,loc.N_POS,loc.N_DEEP,loc.S_AISLE_CODE,loc.N_ROW,loc.N_COL,loc.N_LAYER,loc.N_ROW_GROUP,loc.F_HEIGHT,loc.F_MAX_WEIGHT,pair_loc.N_CURRENT_NUM as pair_num,pair_loc.N_LOCK_STATE as pair_lock,pair_loc.S_CODE as pair_loc_code,pair_loc.C_ENABLE as pair_enable")

        -- 表连接，根据dbtype添加 NOLOCK 表提示
        local strFromTabInfo = string.format(
            "TN_Location loc %s LEFT JOIN TN_Location pair_loc %s ON pair_loc.S_WH_CODE = loc.S_WH_CODE AND pair_loc.S_AREA_CODE = loc.S_AREA_CODE AND pair_loc.S_AISLE_CODE = loc.S_AISLE_CODE AND pair_loc.N_ROW_GROUP = loc.N_ROW_GROUP AND pair_loc.N_COL = loc.N_COL AND pair_loc.N_LAYER = loc.N_LAYER AND ((loc.N_POS = 2 AND pair_loc.N_POS = 1) OR (loc.N_POS = 1 AND pair_loc.N_POS = 2))",
            lock_hint, lock_hint)

        -- 条件：空货位 + 高度载重 + 巷道
        local conditions = {}
        -- 库区编码
        if area_code ~= "" then
            table.insert(conditions, string.format("loc.S_AREA_CODE = '%s'", _escape_sql(area_code)))
        end
        -- 巷道编码
        if aisle ~= "" then
            table.insert(conditions, string.format("loc.N_AISLE = '%s'", _escape_sql(aisle)))
        end
        -- 固定条件：空货位 + 未锁定 + 可用
        table.insert(conditions, string.format("loc.S_WH_CODE = '%s' and loc.N_CURRENT_NUM = 0", _escape_sql(wh_code)))
        table.insert(conditions, "(loc.N_LOCK_STATE IS NULL OR loc.N_LOCK_STATE = 0)")
        table.insert(conditions, "loc.C_ENABLE = 'Y'")

        -- 高度载重条件（带loc.表别名避免字段不明确）
        if height_weight_cond and height_weight_cond ~= "" then
            local prefixed_cond = height_weight_cond:gsub("N_HEIGHT", "loc.N_HEIGHT"):gsub("F_MAX_WEIGHT", "loc.F_MAX_WEIGHT")
            table.insert(conditions, prefixed_cond)
        end

        local strCondition = table.concat(conditions, " AND ")

        -- 使用queryMultiTable2分页查询，支持超过1000条数据
        nRet, strRetInfo = mobox.queryMultiTable2(strLuaDEID, strAttrInfo, strFromTabInfo, 1000, strCondition,
            sort_field)

        if nRet ~= 0 then
            return nil, "queryMultiTable2查询失败: " .. (strRetInfo or "")
        end

        if not strRetInfo or strRetInfo == "" then
            return results
        end

        local queryInfo = _safe_json_decode(strRetInfo)
        if not queryInfo then
            return nil, "queryMultiTable2返回结果解析失败"
        end

        local nPageCount = queryInfo.page_count or 1
        local nPage = 1
        local data_list = queryInfo.data_list or {}

        while nPage <= nPageCount do
            if data_list and #data_list > 0 then
                for _, row in ipairs(data_list) do
                    -- 先收集所有数据后再计算
                    table.insert(results, {
                        aisle = row[4],
                        loc_code = row[1],
                        pos = lua.StrToNumber(row[2]),
                        deep = lua.StrToNumber(row[3]),
                        col = lua.StrToNumber(row[6]),
                        layer = lua.StrToNumber(row[7]),
                        row_group = lua.StrToNumber(row[8]),
                        pair_loc_code = row[13], -- 直接使用JOIN查询结果
                        pair_num = lua.StrToNumber(row[11]),
                        pair_lock = lua.StrToNumber(row[12]),
                        pair_enable = row[14],
                        weight = 0
                    })
                end
            end

            nPage = nPage + 1
            if nPage <= nPageCount then
                -- 取下一页
                nRet, strRetInfo = mobox.queryMultiTable2(strLuaDEID, nPage)
                if nRet ~= 0 then
                    return nil, "queryMultiTable2分页查询失败: " .. (strRetInfo or "")
                end
                queryInfo = _safe_json_decode(strRetInfo)
                if not queryInfo then
                    return nil, "queryMultiTable2第" .. nPage .. "页结果解析失败"
                end
                data_list = queryInfo.data_list or {}
            end
        end
    end
    -- 计算权重
    for _, loc in ipairs(results) do
        if loc.deep == 1 then
            -- 单深位：权重10（无作业即可）
            loc.weight = WEIGHT_SINGLE_DEEP
        elseif loc.deep == 2 and loc.pos == 2 then
            -- 双深内侧：检查外深位是否为空、无锁、且可用
            if loc.pair_num == 0 and loc.pair_lock == 0 and loc.pair_enable == "Y" then
                loc.weight = WEIGHT_INNER_EMPTY
            end
        elseif loc.deep == 2 and loc.pos == 1 then
            -- 双深外侧：检查对应内深位是否有货 或者 无货但不可用  且 无锁
            if (loc.pair_num > 0 or (loc.pair_num == 0 and loc.pair_enable ~= "Y")) and loc.pair_lock == 0 then
                loc.weight = WEIGHT_OUTER_EMPTY
            end
        end
    end

    -- 过滤掉无权重的货位，并记录原始索引以保持稳定排序
    local weighted_results = {}
    local original_idx = 0
    for _, loc in ipairs(results) do
        if loc.weight > 0 then
            original_idx = original_idx + 1
            loc.original_idx = original_idx
            table.insert(weighted_results, loc)
        end
    end
    results = weighted_results

    -- 创建巷道优先级映射（aisle_list 中 index 越小优先级越高）
    local aisle_priority = {}
    for i, aisle in ipairs(aisle_list) do
        aisle_priority[aisle] = i
    end

    -- 按权重降序排序，权重相同时优先选择巷道顺序靠前的
    table.sort(results, function(a, b)
        if a.weight ~= b.weight then
            return a.weight > b.weight
        end
        -- 巷道优先级：优先选择先传入的巷道
        local priorityA = aisle_priority[a.aisle] or 999
        local priorityB = aisle_priority[b.aisle] or 999
        if priorityA ~= priorityB then
            return priorityA < priorityB
        end
        return (a.original_idx or 0) < (b.original_idx or 0)
    end)

    -- 3.5 应用交替排序（loc_order为3或4时）- 直接调用
    if (loc_order == 3 or loc_order == 4) and #results > 0 then
        results = _apply_alternate_sort(results, loc_order)
    end

    return results
end


-- 获取巷道内可用空货位（统一查询+权重排序策略）
-- @function M.Get_Highest_Weight_Location
-- @tparam table params 配置参数
--[[ params 参数说明:
    {
        wh_code: string          -- 仓库编码
        area_code: string        -- 库区编码
        aisles: string|table    -- 巷道编码
        order_method: number    -- 排序方法, 默认1
        loc_order: number       -- 列排序方向, 默认1
        pallet_height: number   -- 托盘高度, 可选
        pallet_weight: number   -- 托盘总重, 可选
    }
--]]
--[[ 权重规则:
    100: 双深内深位(N_POS=2)，对应外深位为空无锁
    50:  双深外深位(N_POS=1)，对应内深位有货无锁
    10:  单深货位(N_DEEP=1)
    先按权重降序，再按排序规则排序，取最高权重的货位
--]]
-- @treturn table|nil 货位结果，失败时nil
-- @treturn string|nil 错误信息，成功时nil
function M.Get_Highest_Weight_Location(strLuaDEID, params)
    -- 参数校验
    local aisles = params.aisles
    if not aisles or (type(aisles) == "string" and aisles == "") or (type(aisles) == "table" and #aisles == 0) then
        return nil, "巷道参数不能为空"
    end

    local wh_code = params.wh_code
    local area_code = params.area_code
    local order_method = params.order_method or 1
    local loc_order = params.loc_order or 1
    local pallet_height = params.pallet_height
    local pallet_weight = params.pallet_weight

    -- 使用SQL查询可用货位（一次查询所有可用空货位）
    local available_locs = _fetch_available_locations(strLuaDEID, {
        wh_code = wh_code,
        area_code = area_code,
        aisles = aisles,
        order_method = order_method,
        loc_order = loc_order,
        pallet_height = pallet_height,
        pallet_weight = pallet_weight
    })

    -- 取最高权重的货位
    if available_locs and #available_locs > 0 then
        local best_loc = available_locs[1]
        return {
            wh_code = wh_code,
            area_code = area_code,
            loc_code = best_loc.loc_code,
            aisle = best_loc.aisle,
            max_height = pallet_height,
            max_weight = pallet_weight
        }
    end

    return nil, "巷道内没有合适货位"
end

return M
