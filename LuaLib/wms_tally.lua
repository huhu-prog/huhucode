--[[
    版本：     Version 3.0
    创建日期： 2025-8-20
    修改日期:  2026-6-19
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    名称:   wms_tally
    应用:   用于理货相关的操作

    ——————————————————————————————————
    导出函数列表（共 2 个）:
    ——————————————————————————————————

    【合箱建议】
        Consolidation_Process       — 生成合箱建议

    【理货状态】
        Set_Tally_IWPC_StateOutOK  — 设置理货料箱出库完成状态

    ——————————————————————————————————

    更改记录:
        2025-8-20    HAN  创建
        V2.0 FCL 20250910 修改作业完成后更新理货单明细状态的条件, INV_DETAIL_ATTRS 增加 S_WMS_BN
        2026-6-19         整理函数注释，添加 @tparam/@treturn 注解

    AI CHECK:
        -- 20260619
--]]

wms_cntr = require("wms_container")

local wms_tally = { _version = "0.2.1" }

local MAX_CONS_CNTR_NUM = 12 -- 最多合箱出几个空料箱
local INV_DETAIL_ATTRS = {
    "S_STORER", "S_ITEM_CODE", "S_ITEM_NAME", "S_ITEM_STATE", "S_WMS_BN", "S_BATCH_NO", "S_SERIAL_NO",
    "D_PRD_DATE", "D_EXP_DATE", "S_OWNER", "S_SUPPLIER_NO", "F_QTY", "S_CELL_NO", "S_CNTR_CODE",
    "S_UDF01", "S_UDF02", "S_UDF03", "S_UDF04", "S_UDF05", "S_UDF06", "S_UDF07", "S_UDF08", "S_UDF09", "S_UDF10",
    "S_UDF11", "S_UDF12", "S_UDF13", "S_UDF14", "S_UDF15", "S_UDF16", "S_UDF17", "S_UDF18", "S_UDF19", "S_UDF20"
}
-- S_AVL_SPEC 可用料箱规格
local SKU_ATTRS = {
    "F_WEIGHT", "F_VOLUME", "S_CTD_CODE", "S_CELL_TYPE", "S_AVL_SPEC", "S_ABCTYPE", "N_LOADING_LIMIT", "F_LOAD_CAPACITY",
    "S_COUNT_METHOD", "S_SKU_GRID_PARM"
}


-- 呼叫 cell_num 个 cell_type 类型的空料格
-- 先将货品 sku 分配到已有的 to_cntr_list 空料格中，不足时再查询数据库呼出新料格
-- @function get_empty_cell
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table cfg 配置设置 {ctd, dbtype, wh_condition}
-- @tparam table sku 需要存储的货品信息
-- @tparam string cell_type 料格类型
-- @tparam number cell_num 需要的料格数量
-- @tparam table from_cntr_list 转移来源料箱列表
-- @tparam table to_cntr_list 转移目标料箱列表
-- @treturn number nRet 0: 成功，1: 找不到合适料格，2: 错误
-- @treturn table/string result 成功返回 call_out_empty_cell_list，失败返回错误信息
local function get_empty_cell(strLuaDEID, cfg, sku, cell_type, cell_num, from_cntr_list, to_cntr_list)
    local nRet, strRetInfo
    local call_out_empty_cell_list = {}
    local find, weight,volume

    -- 首先判断当前已经 在 呼出列表中的 to_cntr_list 中是否有空料格能满足需求
    for n = 1, cell_num do
        find = false
        for _, to_cntr in ipairs(to_cntr_list) do
            if to_cntr.cell_type == cell_type then
                for _, empty_cell in ipairs(to_cntr.empty_cell_list) do
                    if empty_cell.from_cntr_code == '' then
                        find = true

                        local si_qty
                        local cntr_cell = {
                            cell_type = cell_type, qty = 0
                        }
                        nRet, si_qty = wms_cntr.Get_CntrCell_Goods_Qty(cfg.ctd, 0, cntr_cell, sku)
                        if nRet ~= 0 then
                            return 2, si_qty
                        end

                        local qty = sku.qty - sku.alloc_qty
                        if si_qty > qty then
                            si_qty = qty
                        end

                        local call_out_cell = {}
                        if si_qty > 0 then
                            sku.alloc_qty = sku.alloc_qty + si_qty
                            if lua.equation(sku.alloc_qty, sku.qty) then
                                sku.ok = true -- 表示已经全部分配了料箱
                            end

                            -- 把分配掉的si_qty个货品加到补料呼出的容器里
                            weight = lua.Get_NumAttrValue(sku.F_WEIGHT)
                            volume = lua.Get_NumAttrValue(sku.F_VOLUME)

                            call_out_cell = {
                                from_cntr_code = sku.S_CNTR_CODE,
                                from_cell_no = sku.S_CELL_NO,
                                cntr_code = cntr_cell.cntr_code,
                                cell_type = cntr_cell.cell_type,
                                cell_no = empty_cell.cell_no,
                                item_code = sku.S_ITEM_CODE,
                                item_name = sku.S_ITEM_NAME,
                                qty = si_qty,
                                sum_volume = si_qty * volume,
                                sum_weight = si_qty * weight,
                                weight = weight,
                                volume = volume,
                                sku = sku,
                                cell_picked_method = ""
                            }
                            table.insert(call_out_empty_cell_list, call_out_cell)
                        end
                        break
                    end
                end
            end
            if find then
                break
            end
        end
        if not find then
            break
        end
    end

    local need_cell_num = cell_num - #call_out_empty_cell_list
    if need_cell_num == 0 then
        return 0, call_out_empty_cell_list
    end

    -- 呼出新的料格
    local str_loc_where = cfg.wh_condition
    local strTable = "TN_Container_Cell a LEFT JOIN TN_Container b ON a.S_CNTR_CODE = b.S_CODE " -- 联表
    local strAttrs = "a.S_CNTR_CODE, a.S_CELL_NO"                                                -- 查询字段

    -- 如果有混箱规则，需要把容器中规则定义的属性取值
    if cfg.ctd.have_mixing_rule then
        strTable = strTable .. " LEFT JOIN TN_Container_Ext c ON a.S_CNTR_CODE = c.S_CNTR_CODE"
    end

    local match_condition = ""
    local str_value, strCondition
    for i = 1, #cfg.ctd.mixing_attrs do
        str_value = sku[cfg.ctd.mixing_attrs[i]]
        if str_value == nil then
            return 2, "容器类型定义'" .. cfg.ctd.ctd_code .. "' matching_attrs --> " ..
            cfg.ctd.mixing_attrs[i] .. " 没有在 SKU 中定义!"
        end
        match_condition = match_condition .. " AND c." .. cfg.ctd.mixing_attrs[i] .. " = '" .. str_value .. "' "
    end

    -- 查询出仓库里同一货品未满的料格, 查 Container_Cell 表
    -- 注： a.N_EMPTY_FULL = 0 表示料格必须是空料格 b.N_EMPTY_FULL = 1 说明料箱不是空的料箱（合箱的目的是为了多出空料箱） b.N_LOCK_STATE = 0 表示料箱没锁
    -- C_FORCED_FILL = 'N' 说明没被强制置满
    -- a.S_STATE <> 'Abnormal' 料格有异常
    if cfg.dbtype == DB_TYPE.SQLServer then
        strCondition = "a.S_CELL_TYPE = '" ..
            cell_type ..
            "' AND b.S_CTD_CODE = '" ..
            cfg.ctd.ctd_code ..
            "' AND a.S_CNTR_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where " ..
            str_loc_where .. ")) " ..
            " AND a.C_FORCED_FILL = 'N' AND a.N_EMPTY_FULL = 0 AND b.N_LOCK_STATE = 0 AND b.C_ENABLE = 'Y' AND b.N_EMPTY_FULL = 1  AND b.C_FORCED_FILL = 'N'" ..
            " AND a.S_STATE <> 'Abnormal'" .. match_condition
    else
        strCondition = "a.S_CELL_TYPE = '" ..
            cell_type ..
            "' AND b.S_CTD_CODE = '" ..
            cfg.ctd.ctd_code ..
            "' AND a.S_CNTR_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where " ..
            str_loc_where .. ")) " ..
            " AND a.C_FORCED_FILL = 'N' AND a.N_EMPTY_FULL = 0 AND b.N_LOCK_STATE = 0 AND b.C_ENABLE = 'Y' AND b.N_EMPTY_FULL = 1  AND b.C_FORCED_FILL = 'N'" ..
            " AND a.S_STATE <> 'Abnormal'" .. match_condition
    end

    nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 1000, strCondition, strOrder)
    if nRet ~= 0 then
        return 2, "查询【容器料格】信息失败! " .. strRetInfo
    end

    local ret_attr
    if strRetInfo ~= '' then
        ret_attr = json.decode(strRetInfo)

        for _, attr in ipairs(ret_attr) do
            local cntr_code = attr[1]
            local cell_no = attr[2]
            local find = false

            -- 查找处理的料箱，不能在 from 的队列，也不能在 to 的队列
            if sku.cntr_code == cntr_code then
                find = true
            else
                -- 不能在 from_cntr_list 中
                for _, cntr in ipairs(from_cntr_list) do
                    if cntr.cntr_code == cntr_code then
                        find = true
                        break
                    end
                end
                if not find then
                    -- 不能在 to_cntr_list 中
                    for _, cntr in ipairs(to_cntr_list) do
                        if cntr.cntr_code == cntr_code then
                            find = true
                            break
                        end
                    end
                end
            end

            if not find then
                local si_qty
                local cntr_cell = {
                    cell_type = cell_type, qty = 0
                }
                nRet, si_qty = wms_cntr.Get_CntrCell_Goods_Qty(cfg.ctd, 0, cntr_cell, sku)
                if nRet ~= 0 then
                    return 2, si_qty
                end

                -- 如果计算出来的可存储数量大于 sku.qty
                local qty = sku.qty - sku.alloc_qty
                if si_qty > qty then
                    si_qty = qty
                end

                local call_out_cell = {}
                if si_qty > 0 then
                    sku.alloc_qty = sku.alloc_qty + si_qty
                    if lua.equation(sku.alloc_qty, sku.qty) then
                        sku.ok = true -- 表示已经全部分配了料箱
                    end

                    -- 把分配掉的si_qty个货品加到补料呼出的容器里
                    weight = lua.Get_NumAttrValue(sku.F_WEIGHT)
                    volume = lua.Get_NumAttrValue(sku.F_VOLUME)

                    call_out_cell = {
                        from_cntr_code = sku.S_CNTR_CODE,
                        from_cell_no = sku.S_CELL_NO,

                        cntr_code = cntr_code,
                        cell_type = cell_type,
                        cell_no = cell_no,
                        item_code = sku.S_ITEM_CODE,
                        item_name = sku.S_ITEM_NAME,
                        qty = si_qty,
                        sum_volume = si_qty * volume,
                        sum_weight = si_qty * weight,
                        weight = weight,
                        volume = volume,
                        sku = sku,
                        cell_picked_method = "new_call_out"
                    }
                    table.insert(call_out_empty_cell_list, call_out_cell)
                    need_cell_num = need_cell_num - 1
                end
                if need_cell_num == 0 then
                    break
                end
            end
        end
    end

    if need_cell_num == 0 then
        return 0, call_out_empty_cell_list
    end
    return 1
end

-- 料格数量排序（table.sort 比较函数），料格数少的优先，同数量时类型值大的优先
-- @function cell_num_sort
-- @tparam table cell1 {num, cell_type}
-- @tparam table cell2 {num, cell_type}
-- @treturn boolean cell1优先返回true，否则false
local function cell_num_sort(cell1, cell2)
    if cell1.num < cell2.num then
        return true
    elseif cell1.num == cell2.num then
        if cell1.cell_type > cell2.cell_type then
            return true
        end
    end
    return false
end

-- 获取一个补料料格
-- 根据查询到的容器料格数据（call_out_cntr_cell）计算该料格能补入多少货品
-- @function get_si_cell
-- @tparam table cfg 配置设置 {ctd, ...}
-- @tparam table item 入库的货品信息
-- @tparam table call_out_cntr_cell 呼出的可补料料格数据数组
-- @tparam table to_cntr_list 转移目标料箱列表
-- @treturn number nRet 0: 成功，2: 错误
-- @treturn table/string result 成功返回补料 cell_item 对象，失败返回错误信息
local function get_si_cell(cfg, item, call_out_cntr_cell, to_cntr_list)
    local cntr_cell = {}
    local cntr_good_weight = 0
    local ext_attr_index = 8

    cntr_cell.cntr_code = call_out_cntr_cell[1]
    cntr_cell.cell_no = call_out_cntr_cell[2]
    cntr_cell.wms_bn = call_out_cntr_cell[3]
    cntr_cell.good_volume = lua.StrToNumber(call_out_cntr_cell[4])   -- 料格已经存放的货品体积累计值
    cntr_cell.cell_type = call_out_cntr_cell[5]                      -- 料格类型 A/B/C/D/E
    cntr_good_weight = lua.StrToNumber(call_out_cntr_cell[6])        -- 容器当前存储货品重量
    cntr_cell.good_weight = lua.StrToNumber(call_out_cntr_cell[7])
    cntr_cell.qty = lua.StrToNumber(call_out_cntr_cell[8])

    -- 要判断一下是否已经被本次合箱操作分配货品移到这个料格，因此需要调整 cntr_cell.qty
    --[[
    for _, to_cntr in ipairs( to_cntr_list ) do
        if to_cntr.cntr_code == cntr_cell.cntr_code then
            for _, cell in ipairs( to_cntr.cell_list ) do
                if cell.cell_no == cntr_cell.cell_no then
                    cntr_cell.qty = cntr_cell.qty + cell.qty
                    break
                end
            end
            break
        end
    end
    ]]

    -- 计算一下料格能分配多少个货品 si_qty
    local nRet, si_qty = wms_cntr.Get_CntrCell_Goods_Qty(cfg.ctd, cntr_good_weight, cntr_cell, item)
    if nRet ~= 0 then
        return 2, si_qty
    end
    -- 如果计算出来的可存储数量大于 item.qty
    local qty = item.qty - item.alloc_qty
    if si_qty > qty then
        si_qty = qty
    end
    -- si_qty 补料数量
    local cell_item = {}
    local weight, volume

    if si_qty > 0 then
        item.alloc_qty = item.alloc_qty + si_qty
        if lua.equation(item.alloc_qty, item.qty) then
            item.ok = true -- 表示已经全部分配了料箱
        end

        -- 把分配掉的si_qty个货品加到补料呼出的容器里
        weight = lua.Get_NumAttrValue(item.F_WEIGHT)
        volume = lua.Get_NumAttrValue(item.F_VOLUME)

        cell_item = {
            from_cntr_code = item.S_CNTR_CODE,
            from_cell_no = item.S_CELL_NO,
            cntr_code = cntr_cell.cntr_code,
            cell_type = cntr_cell.cell_type,
            cell_no = cntr_cell.cell_no,
            item_code = item.S_ITEM_CODE,
            item_name = item.S_ITEM_NAME,
            qty = si_qty,
            sum_volume = si_qty * volume,
            sum_weight = si_qty * weight,
            weight = weight,
            volume = volume,
            sku = item,
            cell_picked_method = "supplement" -- 料格被选中作为合箱to料格的方法  supplement --补料
        }
    end
    return 0, cell_item
end

--[[
    找出可以把当前料箱中的货品转移存储的料箱料格
    先查找库存中是否有可以进行补料的料格，如果当前 from 料格里的数量完全能补进to的料格即可认为命中这个料箱，
    命中料箱作为to类型料箱不能作为from类型的料箱。
    如果 to 的料格因为数量上的限制不能完全吸收 from 料格里的 SKU 数量，需要拆分，目前系统不支持，建议单独找一个空料格作为to料箱
    输入参数:
        cfg = -- 配置设置
        {
            ctd = ctd,
            dbtype,
            wh_condition = wh_condition
        }
        cntr_sku = -- 需要移出货品的料箱，及料箱中的货品
        {
            cntr_code, ell_type ,
            cell_list = {
            {cell_no, sku_list = {}}
            }                      -- 料箱里的货品根据料格来进行组织
        }
]]

-- 找出可以把当前料箱中的货品转移存储的料箱料格
-- 先查找库存中是否有可进行补料的料格，如不足再呼叫空料格；命中料箱作为 to 类型料箱不能作为 from 类型
-- @function seek_move_to_cntr
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table cfg 配置设置
-- @tparam table cntr_sku 需要移出货品的料箱及货品信息
-- @tparam table from_cntr_list 转移来源料箱列表
-- @tparam table to_cntr_list 转移目标料箱列表
-- @treturn number nRet 0: 成功，1: 无法合箱，2: 错误
-- @treturn table/string result 成功返回 to_cell_list，失败返回错误信息
local function seek_move_to_cntr(strLuaDEID, cfg, cntr_sku, from_cntr_list, to_cntr_list)
    -- 组织匹配料格的查询条件
    local si_match_attrs = cfg.ctd.si_match_attrs or {}
    --lua.DebugEx(strLuaDEID,"si_match_attrs",si_match_attrs)
    if type(si_match_attrs) ~= "table" then
        return 2, "输入参数错误, cfg.ctd.si_match_attrs 必须是 table 类型!"
    end
    -- 匹配属性要加上 S_ITEM_CODE, S_STRORER, S_ITEM_STATE
    -- 匹配属性要加上 S_ITEM_CODE, S_STRORER, S_ITEM_STATE
    if not lua.IsInTable( "S_STORER", si_match_attrs ) then
        table.insert( si_match_attrs, "S_STORER" )
    end
    if not lua.IsInTable( "S_ITEM_STATE", si_match_attrs ) then
        table.insert( si_match_attrs, "S_ITEM_STATE" )
    end 
    if not lua.IsInTable( "S_ITEM_CODE", si_match_attrs ) then
        table.insert( si_match_attrs, "S_ITEM_CODE" )
    end  

    local str_loc_where = cfg.wh_condition
    local strTable = "TN_Container_Cell a LEFT JOIN TN_Container b ON a.S_CNTR_CODE = b.S_CODE " -- 联表
    -- 如果有混箱规则，需要把容器中规则定义的属性取值
    if cfg.ctd.have_mixing_rule then
        strTable = strTable .. " LEFT JOIN TN_Container_Ext c ON a.S_CNTR_CODE = c.S_CNTR_CODE"
    end

    local strAttrs =
    "a.S_CNTR_CODE, a.S_CELL_NO, a.S_WMS_BN, a.F_GOOD_VOLUME, b.S_SPEC, b.F_GOOD_WEIGHT, a.F_GOOD_WEIGHT, a.F_QTY"                  -- 查询字段
    local str_value, match_condition, strCondition
    local si_match_attrs_count = #si_match_attrs
    local si_cell = {}

    -- 容器的利用率高，料格的利用率低的排前面
    -- 容器利用率高排前面的目的是希望把货品补充到快满的料格
    local strOrder = "b.F_CNTR_UTIL desc, a.F_CELL_UTIL"
    local to_cell_list = {} -- 转移到这些料格
    local from_cell_no
    local ret_attr, nRet, strRetInfo

    for _, cell in ipairs(cntr_sku.cell_list) do
        for _, item in ipairs(cell.sku_list) do
            from_cell_no = cell.cell_no
            -- 查找能进行补料的料箱
            match_condition = ""
            for i = 1, si_match_attrs_count do
                str_value = item[si_match_attrs[i]]
                if str_value == nil then
                    return 1,
                        "容器类型定义'" .. cfg.ctd.ctd_code ..
                        "' matching_attrs --> " .. si_match_attrs[i] .. " 没有在 item_list 中定义!"
                end
                match_condition = match_condition .. " AND a." .. si_match_attrs[i] .. " = '" .. str_value .. "' "
            end

            -- 查询出仓库里同一货品未满的料格, 查 Container_Cell 表
            -- 注： N_EMPTY_FULL = 1 表示料格有货未满格 N_LOCK_STATE = 0 表示料格没锁
            -- a.S_STATE <> 'Abnormal' 料格有异常
            if cfg.dbtype == DB_TYPE.SQLServer then
                strCondition = "b.S_CTD_CODE = '" ..
                    cfg.ctd.ctd_code ..
                    "' AND a.S_CNTR_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where " ..
                    str_loc_where .. ")) " ..
                    " AND a.C_FORCED_FILL = 'N' AND a.N_EMPTY_FULL = 1 AND b.N_LOCK_STATE = 0 AND b.C_ENABLE = 'Y' AND b.N_EMPTY_FULL < 2  AND b.C_FORCED_FILL = 'N'" ..
                    " AND a.S_STATE <> 'Abnormal'" .. match_condition
            else
                strCondition = "b.S_CTD_CODE = '" ..
                    cfg.ctd.ctd_code ..
                    "' AND a.S_CNTR_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where " ..
                    str_loc_where .. ")) " ..
                    " AND a.C_FORCED_FILL = 'N' AND a.N_EMPTY_FULL = 1 AND b.N_LOCK_STATE = 0 AND b.C_ENABLE = 'Y' AND b.N_EMPTY_FULL < 2  AND b.C_FORCED_FILL = 'N'" ..
                    " AND a.S_STATE <> 'Abnormal'" .. match_condition
            end

            --lua.DebugEx(strLuaDEID,"strCondition",strCondition)
            nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 1000, strCondition, strOrder)
            if nRet ~= 0 then
                return 2, "查询【容器料格】信息失败! " .. strRetInfo
            end
            if strRetInfo ~= '' then
                ret_attr = json.decode(strRetInfo)

                for _, attr in ipairs(ret_attr) do
                    -- 如果料箱是在 from_cntr_list 中要跳过, 这些是要清空的料箱不嗯作为补料料箱
                    local cntr_code = attr[1]
                    local find = false
                    if cntr_sku.cntr_code == cntr_code then
                        find = true
                    else
                        -- 不能在 from_cntr_list 中
                        for _, cntr in ipairs(from_cntr_list) do
                            if cntr.cntr_code == cntr_code then
                                find = true
                                break
                            end
                        end
                        -- 并且不能在 to_cntr_list 里，目前算法不支持
                        if not find then
                            for _, cntr in ipairs(to_cntr_list) do
                                if cntr.cntr_code == cntr_code then
                                    find = true
                                    break
                                end
                            end
                        end
                    end
                    -- 料箱不在 from_cntr_list 中，可以用做转移到的料箱
                    if not find then
                        nRet, si_cell = get_si_cell(cfg, item, attr, to_cntr_list)
                        if nRet ~= 0 then
                            return 2, si_cell
                        end
                        -- 命中一个可以进行补料的料格
                        if not lua.isTableEmpty(si_cell) then
                            -- 判断补料箱是否在 to_cntr_list
                            find = false
                            for _, cntr in ipairs(to_cntr_list) do
                                if cntr.cntr_code == si_cell.cntr_code then
                                    find = true
                                    break
                                end
                            end
                            if not find then
                                local empty_cell_list
                                nRet, empty_cell_list = wms_cntr.Get_Empty_CellList(strLuaDEID, si_cell.cntr_code)
                                if nRet ~= 0 then
                                    return 2, empty_cell_list
                                end
                                local to_cntr = {
                                    cntr_code = si_cell.cntr_code,
                                    empty_cell_list = empty_cell_list
                                }
                                table.insert(to_cntr_list, to_cntr)
                            end
                            table.insert(to_cell_list, si_cell)
                        end
                        if item.ok then
                            break
                        end
                    end
                end
            end
            -- 如果通过补料箱后没能全部转移
            if not item.ok then
                -- 找到一个或多个空料料格
                local cell_num_list
                nRet, cell_num_list = wms_cntr.Get_CellNum_ToLoad_SKU(cfg.ctd, item, item.qty - item.alloc_qty)
                if nRet ~= 0 then
                    return 2, cell_num_list
                end
                
                -- 优先呼出料格数量少的比如  1 个料格，利用率最高的料格（最适配的cell_type）
                table.sort(cell_num_list, cell_num_sort)

                for _, cell in ipairs(cell_num_list) do
                    -- 确定空料箱格呼出的优先级 A 料箱不呼出, 因为A是一格料箱，如果要一个A类型的空料格就是呼出一个空料箱
                    -- 这对合箱业务不符合逻辑
                    if cell.cell_type == 'A' then
                        -- 如何合箱需要移出的货品只能放到A料格料箱，那么说明合箱失败，可以结束这个 from 料箱的合箱处理
                        break
                    end
                    local call_out_empty_cell_list = {}
                    -- cell.cell_num 说明需要cell_type类型的料格数量
                    nRet, call_out_empty_cell_list = get_empty_cell(strLuaDEID, cfg, item, cell.cell_type, cell.num,
                        from_cntr_list, to_cntr_list)

                    if nRet == 1 then
                        -- 匹配不到可以移动的料箱料格
                        return 1
                    end
                    if nRet ~= 0 then
                        return 2, call_out_empty_cell_list
                    end
                    if not lua.isTableEmpty(call_out_empty_cell_list) then
                        for _, call_out_cell in ipairs(call_out_empty_cell_list) do
                            if call_out_cell.cell_picked_method == 'new_call_out' then
                                -- 新呼出的料格
                                local empty_cell_list
                                nRet, empty_cell_list = wms_cntr.Get_Empty_CellList(strLuaDEID, call_out_cell.cntr_code)
                                if nRet ~= 0 then
                                    return 2, empty_cell_list
                                end
                                for _, cell in ipairs(empty_cell_list) do
                                    cell.from_cntr_code = ''
                                    if cell.cell_no == call_out_cell.cell_no then
                                        cell.from_cntr_code = cntr_sku.cntr_code
                                    end
                                end
                                local to_cntr = {
                                    cntr_code = call_out_cell.cntr_code,
                                    empty_cell_list = empty_cell_list
                                }
                                table.insert(to_cntr_list, to_cntr)
                            else
                                -- 如果是从本次合箱的 to_cntr_list 找的的料格，需要在 empty_cell_list 这里打标记
                                --[[
                                **** 下面的代码逻辑有问题，不是很清楚需要后面梳理一下， empty_cell ???
                                for _, to_cntr in ipairs(to_cntr_list) do
                                    if to_cntr.cntr_code == empty_cell.cntr_code then
                                        for i = 1, #to_cntr.empty_cell_list do
                                            if to_cntr.empty_cell_list[i].cell_no == empty_cell.cell_no then
                                                to_cntr.empty_cell_list[i].from_cntr_code = cntr_sku.cntr_code
                                                break
                                            end
                                        end
                                        break
                                    end
                                end
                                --]]
                            end
                            table.insert(to_cell_list, call_out_cell)
                        end
                        break
                    end
                end

                -- 如果货品还没有被完全转移，说明这个料箱无法转移空
                if not item.ok then
                    return 1, "无法进行合箱" -- 返回说明这个料格的货品无法进行合箱
                end
            end
        end
    end

    -- 找到了转移到的料箱料格，+ from_cntr_list 和  to_cntr_list

    return 0, to_cell_list
end

--[[
    生成合箱建议, 注意不是 Cell_Box类型的不适合这个算法
    名称: 生成合箱建议


    基础算法:
        输入参数:

        tally_consolidation_cfg = {
            wh_code ,
            area_code,
            ctd_code,                           -- 料箱定义编码
            cntr_ext_attr,                      -- 料箱扩展属性
            cntr_util,                          -- 低于这个利用率的进行合箱
            cc_num                              -- 合箱数量
        }

        -- 找到仓库里的尾箱（利用率比较低或只有一个料格有货，空料格数量比较多）
        -- 尾箱里的货品可以转移到仓库里已经存储的料箱（不能重新用一个空料箱）


    输出:   from_cntr_list  -- 从这些料箱移出（产生空料箱） to_cntr_list -- 把 from 料箱的移到 这些料箱

    算法基本构想:
        从满足 wh_condition, cntr_ext_condition 的料箱中找出一个有货的料格数量最少，利用率最低的料箱
        把这个料箱定义为 目标空料箱
    返回值
        0 -- 成功找到一个合箱
        1 -- 找不到
        2 -- 错误
--]]
-- 生成合箱建议
-- 找到仓库里利用率低的尾箱，将其货品转移到已有的料箱或呼出空料格，产生空料箱
-- 注意: Cell_Box 类型不适合这个算法
-- @function wms_tally.Consolidation_Process
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table tally_consolidation_cfg 合箱配置 {wh_code, area_code, ctd_code, cntr_ext_attr, cntr_util, cc_num}
-- @tparam table from_cntr_list 输出: 转移来源料箱列表
-- @tparam table to_cntr_list 输出: 转移目标料箱列表
-- @treturn number nRet 0: 成功，1: 找不到合箱，2: 错误
-- @treturn string/table result 失败时为错误信息
function wms_tally.Consolidation_Process(strLuaDEID, tally_consolidation_cfg, from_cntr_list, to_cntr_list)
    local nRet, strRetInfo, strCondition, strOrder

    local lua_info
    nRet, lua_info = lua.GetLuaDEInfo(strLuaDEID)
    if nRet ~= 0 then
        return 2, "GetLuaDEInfo 失败!" .. lua_info
    end
    local dbtype = lua_info.dbtype

    if lua.isTableEmpty(tally_consolidation_cfg) then
        return 2, "wms_tally.Consolidation_Process 函数中 tally_consolidation_cfg 必须要有值!"
    end

    local ctd_code = tally_consolidation_cfg.ctd_code or ''
    if ctd_code == '' then
        return 2, "wms_tally.Consolidation_Process 函数中 tally_consolidation_cfg.ctd_code 必须要有值!"
    end

    local wh_code = tally_consolidation_cfg.wh_code or ''
    local area_code = tally_consolidation_cfg.area_code or ''

    if wh_code == '' then
        return 2, "wms_tally.Consolidation_Process 函数中 tally_consolidation_cfg.wh_code 必须要有值!"
    end

    local cc_num = tally_consolidation_cfg.cc_num or 0
    if cc_num == 0 then
        cc_num = MAX_CONS_CNTR_NUM
    end
    if cc_num > MAX_CONS_CNTR_NUM then
        cc_num = MAX_CONS_CNTR_NUM
    end
    local wh_condition = " S_WH_CODE = '" .. wh_code .. "'"
    if area_code ~= '' then
        wh_condition = wh_condition .. " AND S_AREA_CODE = '" .. area_code .. "'"
    end
    local cntr_ext_condition = ''
    -- 如果有料箱的扩展属性要查询，需要用到联表查询，因此这里的条件要加 b.
    if tally_consolidation_cfg.cntr_ext_attr ~= nil then
        for _, ext_attr in ipairs(tally_consolidation_cfg.cntr_ext_attr) do
            if cntr_ext_condition ~= '' then
                cntr_ext_condition = cntr_ext_condition .. " AND "
            end
            cntr_ext_condition = cntr_ext_condition .. "b." .. ext_attr.attr .. " = '" .. ext_attr.value .. "'"
        end
    end

    -- 通过容器类型定义获取补料箱呼出规则
    local ctd
    nRet, ctd = wms_cntr.GetCTDInfo(ctd_code)
    if nRet ~= 0 then
        return 2, "容器类型定义'" .. ctd_code .. "'转换数据格式! --> " .. ctd
    end
    local cfg = {
        ctd = ctd,
        dbtype = dbtype,
        wh_condition = wh_condition
    }
    local cntr_objs
    local have_ext_data = false

    -- 如果带容器的扩展属性要多表联查
    -- step1: 查找带货料格最少，料箱利用率最少的料箱
    if cntr_ext_condition ~= '' then
        local strTable = [[TN_Container a INNER JOIN TN_Container_Ext b ON a.S_CODE = b.S_CNTR_CODE
        INNER JOIN TN_Loc_Container c ON a.S_CODE=c.S_CNTR_CODE
        INNER JOIN TN_Location d ON c.S_LOC_CODE=d.S_CODE
        INNER JOIN TN_AREA e ON d.S_AREA_CODE=e.S_CODE]]
        local strAttrs = "a.S_CODE, a.S_SPEC"

        have_ext_data = true
        strCondition = "a.C_ENABLE = 'Y' AND a.S_CTD_CODE = '" ..
        ctd_code ..
        "' AND a.N_LOCK_STATE = 0 AND a.N_EMPTY_FULL = 1 AND " ..
        cntr_ext_condition .. " AND e.N_TYPE=" .. AREA_TYPE.Storage_Area
        --[[if dbtype == DB_TYPE.SQLServer then
            strCondition = strCondition.." AND a.S_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where "..wh_condition..")) "
        else
            strCondition = strCondition.." AND a.S_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where "..wh_condition..")) "
        end]]

        strOrder = "a.N_MAX_CELL_NUM - a.N_EMPTY_CELL_NUM, a.F_CNTR_UTIL" -- 有货的料格数小的最前面
        nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 200, strCondition, strOrder)
        if nRet ~= 0 then
            return 2, "查询料箱失败!" .. strRetInfo
        end
        if strRetInfo == '' then
            return 1
        end
        cntr_objs = json.decode(strRetInfo)
    else
        -- 料箱启用，并且是有货的没有被锁，等于指定的料箱类型定义
        strCondition = "C_ENABLE = 'Y' AND S_CTD_CODE = '" .. ctd_code .. "' AND N_LOCK_STATE = 0 AND N_EMPTY_FULL = 1"
        if dbtype == DB_TYPE.SQLServer then
            strCondition = strCondition ..
            " AND S_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where " ..
            wh_condition .. ")) "
        else
            strCondition = strCondition ..
            " AND S_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where " ..
            wh_condition .. ")) "
        end
        strOrder = "N_MAX_CELL_NUM - N_EMPTY_CELL_NUM, F_CNTR_UTIL" -- 有货的料格数小的最前面
        nRet, cntr_objs = m3.QueryDataObject(strLuaDEID, "Container", strCondition, strOrder)
        if nRet ~= 0 then
            return 2, "查询料箱失败!" .. strRetInfo
        end
        if cntr_objs == '' then
            return 0
        end
    end

    -- step2: 遍历查找出来的利用率最低的，有货料格数量最少的料箱
    local inv_detail_data

    -- 要查询的属性
    local detail_attrs_count = #INV_DETAIL_ATTRS
    local sku_attrs_count = #SKU_ATTRS
    local strAttrs = "a.S_ID," -- 需要把 TN_INV_Detail 中的 S_ID 获取
    local attr_set = { "S_ID" }
    local strTable = "TN_INV_Detail a LEFT JOIN TN_SKU b ON ( a.S_ITEM_CODE = b.S_ITEM_CODE and a.S_STORER = b.S_STORER )"

    for n = 1, detail_attrs_count do
        strAttrs = strAttrs .. "a." .. INV_DETAIL_ATTRS[n] .. ","
        table.insert(attr_set, INV_DETAIL_ATTRS[n])
    end
    for n = 1, sku_attrs_count do
        strAttrs = strAttrs .. "b." .. SKU_ATTRS[n] .. ","
        table.insert(attr_set, SKU_ATTRS[n])
    end
    strAttrs = lua.trim_laster_char(strAttrs)

    local success
    for _, cntr in ipairs(cntr_objs) do
        local cntr_data = {}
        if have_ext_data then
            cntr_data.S_CODE = cntr[1] -- 料箱编码
            cntr_data.S_SPEC = cntr[2] -- 料箱规格
        else
            cntr_data = m3.KeyValueAttrsToObjAttr(cntr.attrs)
        end

        -- MDF BY WHB @20251024 如果from的料箱已经在to的列表中，不能作为from的料箱
        local find = false
        for _, to_cntr in ipairs(to_cntr_list) do
            if to_cntr.cntr_code == cntr_data.S_CODE then
                find = true
                break
            end
        end
        if not find then
            -- 获取料箱中的SKU
            strCondition = "a.S_CNTR_CODE = '" .. cntr_data.S_CODE .. "' AND a.F_QTY_VALID>0"
            strOrder = "a.S_CELL_NO"

            nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 2000, strCondition, strOrder)
            if nRet ~= 0 then
                return 2, "QueryDataObject失败!" .. strRetInfo
            end

            local cntr_sku = {
                cntr_code = cntr_data.S_CODE,
                cell_type = cntr_data.S_SPEC,
                cell_list = {} -- 料箱里的货品根据料格来进行组织
            }
            if strRetInfo ~= '' then
                local data_objects = json.decode(strRetInfo)
                -- 获取from料箱列 SKU
                for _, data_obj in ipairs(data_objects) do
                    nRet, inv_detail_data = lua.GetDataAttrObj_By_StrArray(attr_set, data_obj)
                    if nRet ~= 0 then
                        return 2, inv_detail_data
                    end
                    -- 获取需要理出的货品属性
                    local sku = {}
                    for m = 1, detail_attrs_count do
                        sku[INV_DETAIL_ATTRS[m]] = inv_detail_data[INV_DETAIL_ATTRS[m]]
                    end
                    for m = 1, sku_attrs_count do
                        sku[SKU_ATTRS[m]] = inv_detail_data[SKU_ATTRS[m]]
                    end
                    sku.qty = lua.Get_NumAttrValue(sku.F_QTY)
                    sku.alloc_qty = 0
                    sku.ok = false
                    sku.cntr_cell_list = {} -- 预分配的料格列表
                    sku.sku_grid_parm = ''
                    sku.cntr_code = cntr_sku.cntr_code
                    sku.inv_detail_id = inv_detail_data.S_ID

                    if not lua.StrIsEmpty(sku.S_SKU_GRID_PARM) then
                        success, sku.sku_grid_parm = pcall(json.decode, sku.S_SKU_GRID_PARM)
                        if success == false then
                            return 2, "SKU 编码 = '" .. sku.S_ITEM_CODE .. "' 的数据对象中 S_SKU_GRID_PARM 不符合json规范!"
                        end
                    end

                    -- 加入 cntr_sku 的料格列表
                    find = false
                    for _, cell in ipairs(cntr_sku.cell_list) do
                        if cell.cell_no == sku.S_CELL_NO then
                            table.insert(cell.sku_list, sku)
                            find = true
                            break
                        end
                    end
                    if not find then
                        local cell = {
                            cell_no = sku.S_CELL_NO,
                            sku_list = {}
                        }
                        table.insert(cell.sku_list, sku)
                        table.insert(cntr_sku.cell_list, cell)
                    end
                end

                -- 先查找库存中是否有可以进行补料的料格，如果当前 from 料格里的数量完全能补进to的料格即可认为命中这个料箱，
                -- 命中料箱作为to类型料箱不能作为from类型的料箱。
                -- 如果 to 的料格因为数量上的限制不能完全吸收 from 料格里的 SKU 数量，需要拆分，目前系统不支持，建议单独找一个空料格作为to料箱
                local to_cell_list -- 转移到这些料格
                nRet, to_cell_list = seek_move_to_cntr(strLuaDEID, cfg, cntr_sku, from_cntr_list, to_cntr_list)
                if nRet ~= 0 then
                    -- 是否被占用的 空料箱格
                    for _, to_cntr in ipairs(to_cntr_list) do
                        for i = 1, #to_cntr.empty_cell_list do
                            if to_cntr.empty_cell_list[i].from_cntr_code == cntr_sku.cntr_code then
                                to_cntr.empty_cell_list[i].from_cntr_code = ''
                            end
                        end
                    end
                    if nRet > 1 then
                        return 2, to_cell_list
                    end
                else
                    -- 成功找到可以存储理出去货品的料箱格
                    local from_cntr = {
                        cntr_code = cntr_sku.cntr_code,
                        cell_type = cntr_sku.cell_type,
                        to_cell_list = to_cell_list
                    }
                    table.insert(from_cntr_list, from_cntr)

                    if #from_cntr_list == cc_num then
                        return 0
                    end
                end
            end
        end
    end
    return 0
end

-- 设置理货料箱出库完成
-- 更新 IWP_Container 状态为出库完成，根据 master 标记分别更新 Tally_Detail 的 from/to 状态，所有料箱到位后更新理货明细为运行中
-- @function wms_tally.Set_Tally_IWPC_StateOutOK
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table iwpc_obj IWP_Container 数据对象 {iwpc_no, master}
-- @tparam string cntr_code 料箱编码
-- @tparam string end_loc_code 终点货位编码
-- @treturn number nRet 0: 成功，2: 错误
-- @treturn string strRetInfo 失败时为错误信息
function wms_tally.Set_Tally_IWPC_StateOutOK(strLuaDEID, iwpc_obj, cntr_code, end_loc_code)
    local nRet, strRetInfo
    local strUpdateSql, strCondition

    strUpdateSql = "N_B_STATE = " .. IWPC_STATE.OutOK
    strCondition = "S_IWPC_NO = '" .. iwpc_obj.iwpc_no .. "'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "IWP_Container", strCondition, strUpdateSql)
    if nRet ~= 0 then
        return 2, "更新【IWP_Container】信息失败!" .. strRetInfo
    end

    -- 合箱理货需要两个料箱都到站台才能开始作业，因此要判断一下 当前 到站台料箱的 是否是 C_MASTER
    if iwpc_obj.master == 'Y' then
        -- 说明到站台的是 需要 移出货品的 料箱
        strUpdateSql = "N_FROM_CNTR_STATE = 1, S_LOC_CODE = '" .. end_loc_code .. "'"
        strCondition = "S_IWP_NO = '" .. iwpc_obj.iwp_no .. "' AND S_CNTR_CODE = '" .. cntr_code .. "'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Tally_Detail", strCondition, strUpdateSql)
        if nRet ~= 0 then
            return 2, "更新【Tally_Detail】信息失败!" .. strRetInfo
        end
    else
        -- 这个是货品移入的料箱，可能会有多个 主料箱（货品移出）
        strUpdateSql = "N_TO_CNTR_STATE = 1, S_TO_LOC_CODE = '" .. end_loc_code .. "'"
        strCondition = "S_IWP_NO = '" .. iwpc_obj.iwp_no .. "' AND S_TO_CNTR_CODE = '" .. cntr_code .. "'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Tally_Detail", strCondition, strUpdateSql)
        if nRet ~= 0 then
            return 2, "更新【Tally_Detail】信息失败!" .. strRetInfo
        end
    end
    strUpdateSql = "N_B_STATE = " .. TALLY_DETAIL_STATE.Run
    -- MDF BY HAN @20251016 + AND N_B_STATE = 0
    strCondition = "S_IWP_NO = '" ..
    iwpc_obj.iwp_no .. "' AND N_TO_CNTR_STATE = 1 AND N_FROM_CNTR_STATE = 1 AND N_B_STATE = 0"
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Tally_Detail", strCondition, strUpdateSql)
    if nRet ~= 0 then
        return 2, "更新【Tally_Detail】信息失败!" .. strRetInfo
    end
    return 0
end

--[[
    理货类型的 库内作业关联容器 IWP_Container 作业完成后，根据 Tally_Detail的 数量 影响 量表，INV_Detail
    会产生 MOVE-IN、MOVE-OUT

    输入参数:
        iwpc_obj -- IWP_Container 数据对象（lua）
    主要功能:
        -- 从 from 的料箱料格里 扣减 货品数量
        -- 加 to 料箱料格里的货品数量
]]
--[[
function wms_tally.Tally_IWP_CNTR_PostProcess( strLuaDEID, iwpc_obj )
    local nRet, strRetInfo

    if ( lua.isTableEmpty(iwpc_obj) ) then
        return 1, "wms_tally.Tally_IWP_CNTR_PostProcess 函数中 iwpc_obj 必须有值!"
    end

    local container
    nRet, container = wms_cntr.GetInfo( strLuaDEID, iwpc_obj.cntr_code )
    if nRet ~= 0 then
        return 2, "获取【容器】信息失败! " .. container
    end
    local ctd
    nRet, ctd = wms_cntr.GetCTDInfo( container.ctd_code )
    if nRet ~= 0 then
        return 2, "容器类型定义'"..ctd_code.."'转换数据格式! --> "..ctd
    end

    -- 获取 Pre_Alloc_CNTR_Detail
    local strOrder = ''
    local strCondition = "S_IWPC_NO = '"..iwpc_obj.iwpc_no.."'"

    nRet, strRetInfo = mobox.queryDataObjAttr( strLuaDEID, "Tally_Detail", strCondition, strOrder )
    if nRet ~= 0 then
        return 1, "获取【Tally_Detail】失败! "..strRetInfo
    end
    if strRetInfo == '' then
        lua.Warning( strLuaDEID, debug.getinfo(1), "理货作业流水号'"..iwpc_obj.iwpc_no.."'的理货明细为空!" )
        return 1, "理货作业流水号'"..iwpc_obj.iwpc_no.."'的理货明细为空!"
    end

    local retObjs = json.decode( strRetInfo )
    local n
    local tally_detail_data = {}
    local days = os.date("%Y%m%d")
    local strSetAttr

    for n = 1, #retObjs do
        nRet, tally_detail_data = m3.ObjAttrToObjJson( "Tally_Detail", lua.table2str(retObjs[n].attrs) )
        if nRet ~= 0 then
            return 1, "m3.ObjAttrToObjJson 失败! "..tally_detail
        end
        -- 库存量表变化
        if ( tally_detail_data.G_INV_DETAIL_ID ~= '' ) then
            nRet, strRetInfo = wms_inv.Tally_Detail_Process( strLuaDEID, ctd, tally_detail_data )
            if ( nRet ~= 0 )  then
                return 1, "wms_inv.Tally_Detail_Process 失败! "..strRetInfo
            end
        end
    end

    -- 清理 F_QTY = 0 的 INV_Detai
    strCondition = "F_QTY = 0"
    nRet, strRetInfo = mobox.dbdeleteData(strLuaDEID, "INV_Detail", strCondition)
    if nRet ~= 0 then
        return 1, "删除【INV_Detail】失败!"..strRetInfo
    end

    return 0
end
]]

return wms_tally
