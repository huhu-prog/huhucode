--[[
    版本：    Version 1.0
    创建日期： 2025-11-18
    创建人：   HAN

    WMS-Basis-Model-Version: V18.1

    功能：
        合箱理货是指将多个料箱中的货物合并到更少的箱子里以腾出空箱这一核心操作

    主函数:
        Generate_Bin_Consolidation_Suggestions -- 生成理货建议
    版本:
        V2.0 MDY FCL 增加优先查找批次的数据 ，同时每次查找加事务控制bin_consolidation_process
--]]

wms_cntr = require("wms_container")

local wms_bin_con = { _version = "0.2.1 " }

local INV_DETAIL_ATTRS    = {
    "S_STORER", "S_ITEM_CODE", "S_ITEM_NAME", "S_ITEM_STATE", "S_WMS_BN", "S_BATCH_NO", "S_SERIAL_NO",
    "D_PRD_DATE", "D_EXP_DATE", "S_OWNER", "S_SUPPLIER_NO", "F_QTY", "S_CELL_NO", "S_CNTR_CODE",
    "S_UDF01", "S_UDF02", "S_UDF03", "S_UDF04", "S_UDF05", "S_UDF06", "S_UDF07", "S_UDF08", "S_UDF09", "S_UDF10",
    "S_UDF11", "S_UDF12", "S_UDF13", "S_UDF14", "S_UDF15", "S_UDF16", "S_UDF17", "S_UDF18", "S_UDF19", "S_UDF20"
}
-- S_AVL_SPEC 可用料箱规格
local SKU_ATTRS           = {
    "F_WEIGHT", "F_VOLUME", "S_CTD_CODE", "S_CELL_TYPE", "S_AVL_SPEC", "S_ABCTYPE", "N_LOADING_LIMIT", "F_LOAD_CAPACITY",
    "S_COUNT_METHOD", "S_SKU_GRID_PARM"
}

local TEMP_CNTR_CELL_ATTR = {
    "S_CNTR_CODE",
    "S_CELL_NO",
    "S_CELL_CODE",
    "S_CELL_TYPE",
    "S_ITEM_CELL_TYPE",
    "F_VOLUME",
    "F_GOOD_WEIGHT",
    "F_GOOD_VOLUME",
    "N_EMPTY_FULL",
    "F_CELL_UTIL",
    "C_FORCED_FILL",
    "F_LIMIT",
    "F_REM_CAP"
}

-- 合箱理货建议前把 Container_Cell 的参数根据 INV_Detail 重新计算后插入到 Temp_Container_Cell
-- cntr 是一个容器对象 ctd -- 容器类型定义
--[[
    根据 INV_Detail 设置料箱编码 cntr_code 的料箱格中的 S_ITEM_CODE，F_QTY, F_REM_CAP (剩余容量)
    首次用于国科合箱理货算法中对料格初始化

    注意: 这个函数适配带料格的料箱
    输入参数:
                ctd -- 料箱类型定义
                ctd = {
                    mixing_attrs_def = {}       -- 混箱属性的字段定义 string / number
                    mixing_attrs = {}           -- 混箱属性（字段）
                    have_mixing_rule = false/true  -- 料箱有混箱规则，如果没有说明没限制
                    si_enable = false/true  -- 料箱格允许补料
                    si_match_attrs_def = {} -- 补料属性的字段定义 string / number
                    si_match_attrs = {} -- -- 补料属性（字段）
                    check_capacity = false/true -- 是否超重检查

                    -- 料格里符合下面条件的SKU数量可以相加

                    qty_merge = false/true  -- 料格里的货品数量合并
                    merge_attrs_def = {}   -- 合并货品数量的属性字段定义 string / number
                    merge_attrs = {}       -- 合并货品数量属性（字段）

                    grid_box_def = {}       -- 料箱中料格定义
                }
                cntr -- 料箱数据对象
--]]
local function create_temp_container_cell(strLuaDEID, ctd, cntr)
    local strCondition, nRet
    local data_objs
    local nRet, strRetInfo

    strCondition = "S_CNTR_CODE = '" .. cntr.code .. "'"
    local strOrder = ""
    if cntr.type ~= "Cell_Box" then
        return 1, "create_temp_container_cell 函数适合的料箱类型必须是料格类型!"
    end

    strCondition = "S_CNTR_CODE = '" .. cntr.code .. "'"
    nRet, data_objs = m3.QueryDataObject(strLuaDEID, "Container_Cell", strCondition, "S_CELL_NO")
    if nRet ~= 0 then
        return 2, "QueryDataObject失败!" .. data_objs
    end
    if data_objs == '' then
        return 0
    end

    local cell_list = {}
    local attrs = {}
    local obj_attrs
    for n = 1, #data_objs do
        obj_attrs = m3.KeyValueAttrsToObjAttr(data_objs[n].attrs)
        if obj_attrs == nil then
            return 1, "KeyValueAttrsToObjAttr失败!"
        end
        local cell = {
            id = data_objs[n].id,
            S_CNTR_CODE = obj_attrs.S_CNTR_CODE,
            S_CELL_NO = obj_attrs.S_CELL_NO,
            S_CELL_TYPE = obj_attrs.S_CELL_TYPE,
            F_QTY = 0,
            F_LIMIT = 0,                                    -- 容量
            F_VOLUME = lua.StrToNumber(obj_attrs.F_VOLUME), -- 料格体积
            C_FORCED_FILL = obj_attrs.C_FORCED_FILL,
            F_GOOD_VOLUME = 0,
            F_GOOD_WEIGHT = 0,
            N_EMPTY_FULL = 0
        }
        table.insert(cell_list, cell)
    end

    -- 获取 INV_Detial + SKU 中的属性
    local strTable =
    "TN_INV_Detail a LEFT JOIN TN_SKU b ON ( a.S_ITEM_CODE = b.S_ITEM_CODE and a.S_STORER = b.S_STORER )"
    -- 要查询的属性
    local strAttrs = ""
    local attr_set = {}
    local CNTR_CELL_COUNT = #CNTR_CELL_BASE_ATTRS
    for m = 1, CNTR_CELL_COUNT do
        strAttrs = strAttrs .. "a." .. CNTR_CELL_BASE_ATTRS[m] .. ","
        table.insert(attr_set, CNTR_CELL_BASE_ATTRS[m])
    end
    local UDF_ATTRS_COUNT = #UDF_ATTRS
    for m = 1, UDF_ATTRS_COUNT do
        strAttrs = strAttrs .. "a." .. UDF_ATTRS[m] .. ","
        table.insert(attr_set, UDF_ATTRS[m])
    end
    strAttrs = strAttrs .. "b.F_VOLUME, b.F_WEIGHT, b.S_CELL_TYPE, b.S_SKU_GRID_PARM, b.S_COUNT_METHOD, b.N_LOADING_LIMIT"
    table.insert(attr_set, "F_VOLUME")
    table.insert(attr_set, "F_WEIGHT")
    table.insert(attr_set, "S_CELL_TYPE")
    table.insert(attr_set, "S_SKU_GRID_PARM")
    table.insert(attr_set, "S_COUNT_METHOD")
    table.insert(attr_set, "N_LOADING_LIMIT")

    -- 入库批次也要进行排序
    strOrder = "a.S_CELL_NO, a.S_WMS_BN"
    strCondition = "a.S_CNTR_CODE = '" .. cntr.code .. "'"
    nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 2000, strCondition, strOrder)
    if nRet ~= 0 then
        return 2, "queryMultiTable 失败!" .. strRetInfo
    end

    local nCount
    local ret_data = {}
    if strRetInfo ~= '' then
        ret_data = json.decode(strRetInfo)
        nCount   = #ret_data
    else
        nCount = 0
    end
    if nCount == 0 then
        return 0
    end
    local cell_no
    local current_cell_no = ''
    local sum_volume, sum_weight, sum_qty
    local volume, weight, qty
    local good_weigth, good_volume, good_num
    local cell_type = cntr.spec

    -- 计算料箱料格的体积、重量，已经料箱格的空满状态
    -- 料格里的货品重量、体积
    sum_volume = 0
    sum_weight = 0
    sum_qty = 0
    -- 整个料箱里的货品重量、体积
    good_weigth = 0
    good_volume = 0
    good_num = 0

    local cntr_cell = {}
    local inv_detail_data = {}
    local data_obj

    for n = 1, nCount do
        nRet, data_obj = lua.GetDataAttrObj_By_StrArray(attr_set, ret_data[n])
        if nRet ~= 0 then
            return 1, data_obj
        end
        cell_no = lua.Get_StrAttrValue(data_obj.S_CELL_NO)
        if current_cell_no == '' then
            current_cell_no = cell_no
        end
        if current_cell_no ~= cell_no then
            cntr_cell.F_QTY = sum_qty
            cntr_cell.F_GOOD_VOLUME = sum_volume
            cntr_cell.F_GOOD_WEIGHT = sum_weight
            nRet, strRetInfo = wms_cntr.Set_CntrCell_Data_List(ctd, cell_list, current_cell_no, cntr_cell,
                inv_detail_data)
            if nRet ~= 0 then
                return 1, strRetInfo
            end
            sum_volume = 0
            sum_weight = 0
            sum_qty = 0
            current_cell_no = cell_no
        end

        cntr_cell.S_CELL_TYPE = cell_type
        cntr_cell.S_ITEM_CELL_TYPE = lua.Get_StrAttrValue(data_obj.S_CELL_TYPE)

        inv_detail_data = data_obj

        qty = lua.Get_NumAttrValue(data_obj.F_QTY)
        volume = lua.Get_NumAttrValue(data_obj.F_VOLUME)
        weight = lua.Get_NumAttrValue(data_obj.F_WEIGHT)

        volume = volume * qty
        weight = weight * qty

        good_weigth = good_weigth + weight
        good_volume = good_volume + volume
        good_num = good_num + qty

        sum_volume = sum_volume + volume
        sum_weight = sum_weight + weight
        sum_qty = sum_qty + qty
    end
    cntr_cell.F_QTY = sum_qty
    cntr_cell.F_GOOD_VOLUME = sum_volume
    cntr_cell.F_GOOD_WEIGHT = sum_weight

    nRet, strRetInfo = wms_cntr.Set_CntrCell_Data_List(ctd, cell_list, current_cell_no, cntr_cell, inv_detail_data)
    if nRet ~= 0 then
        return 1, strRetInfo
    end

    -- 创建 Temp_Container_Cell
    local temp_cntr_cell_data
    local temp_cntr_cell_attr_count = #TEMP_CNTR_CELL_ATTR
    for _, temp_cntr_cell in ipairs(cell_list) do
        temp_cntr_cell_data = m3.AllocObject2(strLuaDEID, "Temp_Container_Cell")

        temp_cntr_cell_data.S_TRANS_ID = lua.trim_guid_str(strLuaDEID)
        temp_cntr_cell_data.N_PRIORITY = 0
        temp_cntr_cell_data.S_FLAG = ''

        for m = 1, CNTR_CELL_COUNT do
            temp_cntr_cell_data[CNTR_CELL_BASE_ATTRS[m]] = temp_cntr_cell[CNTR_CELL_BASE_ATTRS[m]]
        end
        for m = 1, UDF_ATTRS_COUNT do
            temp_cntr_cell_data[UDF_ATTRS[m]] = temp_cntr_cell[UDF_ATTRS[m]]
        end
        for m = 1, temp_cntr_cell_attr_count do
            temp_cntr_cell_data[TEMP_CNTR_CELL_ATTR[m]] = temp_cntr_cell[TEMP_CNTR_CELL_ATTR[m]]
        end

        nRet, temp_cntr_cell_data = m3.CreateDataObj2(strLuaDEID, temp_cntr_cell_data)
        if nRet ~= 0 then
            return 1, "创建[Temp_Container_Cell]失败!" .. temp_cntr_cell_data
        end
    end

    return 0
end


--[[
    设置需要合箱处理的料箱料格记录中的信息包括
    F_QTY 数量
    F_REM_QTY 剩余数量，说明这个料格还可以放多少个货品

    输入参数:
        query_cfg = {
            ctd = ctd,
            dbtype = dbtype,
            query_table = strTable,
            condition = strCondition,
            order = strOrder
        }
--]]

local function batch_insert_temp_cell(strLuaDEID, strTable, strCondition, strOrder, prd_no)
    local nRet, strRetInfo
    --创建临时表
    local strSQL = "DROP TEMPORARY TABLE IF EXISTS TMP_CID;"
    nRet, strRetInfo = mobox.runSQL(strLuaDEID, strSQL)
    if nRet ~= 0 then
        return 1, "删除临时表失败!" .. strRetInfo
    end
    local strAttrs = "a.S_CODE, a.S_SPEC, a.S_TYPE"
    strSQL = "CREATE TEMPORARY TABLE TMP_CID AS " ..
        "SELECT " .. strAttrs .. " FROM " .. strTable .. " WHERE " .. strCondition .. " ORDER BY " .. strOrder
    --lua.DebugEx(strLuaDEID,"strSQL",strSQL)
    nRet, strRetInfo = lua.RunSQL(strLuaDEID, strSQL)
    if nRet ~= 0 then
        return 1, "系统创建临时表失败!" .. strRetInfo
    end

    --删除是否存在产品线料箱数据
    strCondition = " S_UDF01='" .. prd_no .. "'"
    nRet, strRetInfo = mobox.dbdeleteData(strLuaDEID, "Temp_Container_Cell", strCondition)
    if nRet ~= 0 then
        return 1, "删除【Temp_Container_Cell】失败!", strRetInfo
    end

    strSQL = string.format(
        [[INSERT INTO tn_temp_container_cell(S_ID,S_TRANS_ID,S_CNTR_CODE,S_CELL_NO,S_FLAG,N_PRIORITY,S_CELL_CODE,F_GOOD_WEIGHT,F_GOOD_VOLUME,N_EMPTY_FULL,S_ITEM_CELL_TYPE,F_VOLUME,C_FORCED_FILL,F_QTY,F_LIMIT,F_REM_CAP,S_CELL_TYPE,F_CELL_UTIL,S_STORER,S_ITEM_CODE,S_ITEM_STATE,S_WMS_BN,S_BATCH_NO,S_OWNER,S_SUPPLIER_NO,D_EXP_DATE,D_PRD_DATE,S_ITEM_NAME,S_UDF01)
SELECT UUID(),'%s',a.S_CNTR_CODE,a.S_CELL_NO,'',0,a.S_CELL_CODE,a.F_GOOD_WEIGHT,a.F_GOOD_VOLUME,
a.N_EMPTY_FULL,a.S_ITEM_CELL_TYPE,a.F_VOLUME,a.C_FORCED_FILL,a.F_QTY,a.F_LIMIT,a.F_REM_CAP,a.S_CELL_TYPE,a.F_CELL_UTIL,a.S_STORER,a.S_ITEM_CODE,a.S_ITEM_STATE,a.S_WMS_BN,a.S_BATCH_NO,a.S_OWNER,a.S_SUPPLIER_NO,a.D_EXP_DATE,a.D_PRD_DATE,a.S_ITEM_NAME,'%s'
FROM tn_container_cell a inner join TMP_CID b on a.S_CNTR_CODE=b.S_CODE]], lua.trim_guid_str(strLuaDEID), prd_no)
    --lua.DebugEx(strLuaDEID,"strSQL",strSQL)
    nRet, strRetInfo = lua.RunSQL(strLuaDEID, strSQL)
    if nRet ~= 0 then
        return 1, "批量插入Temp_Container_Cell失败!" .. strRetInfo
    end
    return 0, ""
end

local function data_initial(strLuaDEID, ctd, strTable, strCondition, strOrder)
    local nRet, strRetInfo
    local strAttrs = "a.S_CODE, a.S_SPEC, a.S_TYPE"

    nRet, strRetInfo = mobox.queryMultiTable2(strLuaDEID, strAttrs, strTable, 100, strCondition, strOrder)
    if nRet ~= 0 then
        return 1, "queryMultiTable2: " .. strRetInfo
    end

    if strRetInfo == '' then
        return 0
    end

    local queryInfo = json.decode(strRetInfo)
    local nPageCount = queryInfo.page_count
    local nPage = 1
    local data_list = queryInfo.data_list

    while (nPage <= nPageCount) do
        for n = 1, #data_list do
            local cntr =
            {
                code = data_list[n][1],
                spec = data_list[n][2],
                type = data_list[n][3]
            }
            nRet, strRetInfo = create_temp_container_cell(strLuaDEID, ctd, cntr)
            if nRet ~= 0 then
                return 1, strRetInfo
            end
        end

        nPage = nPage + 1
        if nPage <= nPageCount then
            -- 取下一页
            nRet, strRetInfo = mobox.queryMultiTable2(strLuaDEID, nPage)
            if nRet ~= 0 then
                return 1, "查询【容器】失败! nPage=" .. nPage .. "  " .. strRetInfo
            end
            queryInfo = json.decode(strRetInfo)
            data_list = queryInfo.data_list
        end
    end
    return 0
end

--[[
    获取一个补料料格
        输入参数:
            -- item 入库的货品信息
            -- call_out_cntr_cell == 呼出的可以补料 的 料格
--]]
local function get_si_cell(item, call_out_cntr_cell, to_cell_list)
    -- 料格剩余容量
    local si_qty = call_out_cntr_cell.rem_cap

    -- 如果计算出来的可存储数量大于 item.qty
    local qty = item.qty - item.alloc_qty
    if si_qty > qty then
        si_qty = qty
    end
    -- si_qty 补料数量
    local cell_item = {}
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
            -- to
            to_cntr_code = call_out_cntr_cell.cntr_code,
            to_cell_no = call_out_cntr_cell.cell_no,
            cell_type = call_out_cntr_cell.cell_type,
            -- sku
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
        table.insert(to_cell_list, cell_item)
    end
end

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

--[[
    呼出 cell_num 个 cell_type 类型的空料格
    输入参数:
        -- sku 需要存储的货品信息
        -- to_cntr_list  转移到的料箱（合箱操作中，泛指清空货品转移到这些料箱）
--]]
local function find_empty_cell(strLuaDEID, bc_cfg, sku, cell_type, cell_num)
    local nRet, strRetInfo
    local call_out_empty_cell_list = {}
    local need_cell_num = cell_num
    -- step1: 从 Temp_Container_Cell 查可以进行补料的料格
    local strTable = "TN_Temp_Container_Cell a LEFT JOIN TN_Container b ON a.S_CNTR_CODE = b.S_CODE " -- 联表
    -- 如果有混箱规则，需要把容器中规则定义的属性取值
    if bc_cfg.ctd.have_mixing_rule then
        strTable = strTable .. " LEFT JOIN TN_Container_Ext c ON a.S_CNTR_CODE = c.S_CNTR_CODE"
    end
    local strAttrs = "a.S_CNTR_CODE, a.S_CELL_NO, a.N_PRIORITY" -- 查询字段
    local str_value, weight, volume

    -- 剩余容量大的排前面, 优先级大的排前面, N_PRIORITY 值大的就是已经加入 to_cntr_list 的料箱
    local strOrder = "a.N_PRIORITY desc"
    local match_condition, strCondition, from_cell_no
    local ret_attr

    match_condition = ""
    for i = 1, #bc_cfg.ctd.mixing_attrs do
        str_value = sku[bc_cfg.ctd.mixing_attrs[i]]
        if str_value == nil then
            return 2,
                "容器类型定义'" ..
                bc_cfg.ctd.ctd_code .. "' matching_attrs --> " .. bc_cfg.ctd.mixing_attrs[i] .. " 没有在 SKU 中定义!"
        end
        match_condition = match_condition .. " AND c." .. bc_cfg.ctd.mixing_attrs[i] .. " = '" .. str_value .. "' "
    end

    strCondition = " a.S_TRANS_ID = '" .. lua.trim_guid_str(strLuaDEID) .. "' " ..
        " AND a.S_CELL_TYPE = '" .. cell_type .. "' AND b.S_CTD_CODE = '" .. bc_cfg.ctd.ctd_code .. "' " ..
        " AND a.C_FORCED_FILL = 'N' AND a.N_EMPTY_FULL = 0 AND b.N_LOCK_STATE = 0 AND b.C_ENABLE = 'Y' " ..
        " AND b.N_EMPTY_FULL = 1  AND b.C_FORCED_FILL = 'N'" .. match_condition

    nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 1000, strCondition, strOrder)
    if nRet ~= 0 then
        return 2, "查询【容器料格】信息失败! " .. strRetInfo
    end
    if strRetInfo == '' then
        return 0, call_out_empty_cell_list
    end

    ret_attr = json.decode(strRetInfo)
    for _, attr in ipairs(ret_attr) do
        local cntr_code = attr[1]
        local cell_no = attr[2]
        local si_qty
        local cntr_cell = {
            cell_type = cell_type, qty = 0
        }
        nRet, si_qty = wms_cntr.Get_CntrCell_Goods_Qty(bc_cfg.ctd, 0, cntr_cell, sku)
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
                -- from
                from_cntr_code = sku.S_CNTR_CODE,
                from_cell_no = sku.S_CELL_NO,
                -- to
                to_cntr_code = cntr_code,
                to_cell_no = cell_no,

                cell_type = cell_type,
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

    return 0, call_out_empty_cell_list
end

--[[
    找出可以把 cntr_sku 中的货品转移存储的料箱料格

    先查找Temp_Container_Cell中是可以进行补料的料格
    如果补料无法满足再找空料格

    找到的料箱作为to类型料箱不能作为from类型的料箱。

    输入参数:
        bc_cfg = -- 配置设置
        {
            dbtype,
            si_match_attrs  --- 补料匹配属性
        }
        cntr_sku = -- 需要移出货品的料箱，及料箱中的货品
        {
            cntr_code, ell_type ,
            cell_list = {
                {cell_no, sku_list = {}}
            }                      -- 料箱里的货品根据料格来进行组织
        }
     返回参数:
        to_cell_list  -- 需要移动到的目标料箱格列表， 如果为{} 说明当前料箱无法做移出
]]
local function find_move_to_cntr(strLuaDEID, bc_cfg, cntr_sku)
    local nRet, strRetInfo

    -- step1: 从 Temp_Container_Cell 查可以进行补料的料格
    local strTable = "TN_Temp_Container_Cell a LEFT JOIN TN_Container b ON a.S_CNTR_CODE = b.S_CODE " -- 联表
    -- 如果有混箱规则，需要把容器中规则定义的属性取值
    if bc_cfg.ctd.have_mixing_rule then
        strTable = strTable .. " LEFT JOIN TN_Container_Ext c ON a.S_CNTR_CODE = c.S_CNTR_CODE"
    end
    local strAttrs = "a.S_CNTR_CODE, a.S_CELL_NO, a.F_REM_CAP, a.N_PRIORITY, a.S_CELL_TYPE" -- 查询字段
    local str_value, weight, volume
    local si_match_attrs_count = #bc_cfg.si_match_attrs
    local si_cell = {}

    -- 剩余容量大的排前面, 优先级大的排前面
    local strOrder = "a.N_PRIORITY desc, a.F_REM_CAP desc"
    local to_cell_list = {} -- 转移到这些料格
    local match_condition, strCondition, from_cell_no
    local ret_attr

    local base_condition = "S_TRANS_ID = '" .. lua.trim_guid_str(strLuaDEID) .. "' "
    for _, cell in ipairs(cntr_sku.cell_list) do
        for _, item in ipairs(cell.sku_list) do
            -- 查找能进行补料的料箱
            match_condition = ""
            for i = 1, si_match_attrs_count do
                str_value = item[bc_cfg.si_match_attrs[i]]
                if str_value == nil then
                    return 1,
                        "容器类型定义'" ..
                        bc_cfg.ctd.ctd_code ..
                        "' matching_attrs --> " .. bc_cfg.si_match_attrs[i] .. " 没有在 item_list 中定义!"
                end
                match_condition = match_condition .. " AND a." .. bc_cfg.si_match_attrs[i] .. " = '" .. str_value .. "' "
            end

            strCondition = base_condition ..
                " AND a.C_FORCED_FILL = 'N' AND a.N_EMPTY_FULL = 1 AND b.N_LOCK_STATE = 0 AND b.C_ENABLE = 'Y' " ..
                " AND a.F_REM_CAP > 0 AND a.S_FLAG <> 'From' " .. match_condition

            -- 查找可以进行补料的料格
            nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 1000, strCondition, strOrder)
            if nRet ~= 0 then
                return 2, "查询【容器料格】信息失败! " .. strRetInfo
            end
            if strRetInfo ~= '' then
                ret_attr = json.decode(strRetInfo)

                local can_si_cntr_cell_list = {} -- 可以进行补料的料格列表
                local max_rem_cap = 0
                local max_rem_cap1 = 0           -- 已经呼出的料箱格最大剩余量
                local max_rem_cap2 = 0           -- 没有呼出的料箱格最大剩余量
                local priority = 0

                for _, attr in ipairs(ret_attr) do
                    priority = lua.Get_NumAttrValue(attr[4])
                    local si_cell = {
                        cntr_code = attr[1],
                        cell_no = attr[2],
                        rem_cap = lua.Get_NumAttrValue(attr[3]),
                        cell_type = attr[5],
                        priority = priority
                    }
                    table.insert(can_si_cntr_cell_list, si_cell)
                    max_rem_cap = max_rem_cap + si_cell.rem_cap
                    if priority == 0 then
                        max_rem_cap2 = max_rem_cap2 + si_cell.rem_cap
                    else
                        max_rem_cap1 = max_rem_cap1 + si_cell.rem_cap
                    end
                end
                -- 获取数量和 rem_cap 最匹配的料格
                -- max_rem_cap1 是已经呼出的料箱中存在适配料格可存储货品数量
                if max_rem_cap1 >= item.qty or
                    (max_rem_cap1 == 0 and max_rem_cap2 >= item.qty) then
                    for _, can_si_cell in ipairs(can_si_cntr_cell_list) do
                        if can_si_cell.rem_cap == item.qty then
                            get_si_cell(item, can_si_cell, to_cell_list)
                            break
                        end
                    end
                end

                if not item.ok then
                    for _, can_si_cell in ipairs(can_si_cntr_cell_list) do
                        get_si_cell(item, can_si_cell, to_cell_list)
                        if item.ok then
                            break
                        end
                    end
                end
            end

            -- 如果通过补料箱后没能全部转移
            local find
            if not item.ok then
                -- 找到一个或多个空料料格
                local cell_num_list = {}
                nRet, cell_num_list = wms_cntr.Get_CellNum_ToLoad_SKU(bc_cfg.ctd, item, item.qty - item.alloc_qty)
                if nRet ~= 0 then
                    return 2, cell_num_list
                end
                -- 确定空料箱格呼出的优先级 A 料箱不呼出 优先呼出料格数量少的比如  1 个料格，利用率最高的料格（最适配的cell_type）
                table.sort(cell_num_list, cell_num_sort)

                for _, cell in ipairs(cell_num_list) do
                    if cell.cell_type == 'A' then
                        -- 如何合箱需要移出的货品只能放到A料格料箱，那么说明合箱失败，可以结束这个 from 料箱的合箱处理
                        break
                    end
                    local call_out_empty_cell_list = {} -- 呼出的空料格列表
                    -- cell.cell_num 说明需要cell_type类型的料格数量
                    nRet, call_out_empty_cell_list = find_empty_cell(strLuaDEID, bc_cfg, item, cell.cell_type, cell.num)
                    if nRet ~= 0 then
                        return 2, call_out_empty_cell_list
                    end
                    for _, call_out_cell in ipairs(call_out_empty_cell_list) do
                        table.insert(to_cell_list, call_out_cell)
                    end
                    if item.ok then
                        break
                    end
                end
            end
            -- 如果货品还没有被完全转移，说明这个料箱无法转移空
            if not item.ok then
                return 0, {}
            end
        end
    end

    -- 找到了转移到的料箱料格，+ from_cntr_list 和  to_cntr_list

    return 0, to_cell_list
end

local function set_temp_container_cell_flag(strLuaDEID, cntr_code, flag, priority)
    local nRet, strRetInfo

    if priority == nil then
        priority = 0
    end
    local strUpdateSql = "S_FLAG = '" .. flag .. "', N_PRIORITY = " .. priority
    local strCondition = "S_CNTR_CODE = '" .. cntr_code .. "' AND S_TRANS_ID = '" .. lua.trim_guid_str(strLuaDEID) .. "'"
    --lua.DebugEx(strLuaDEID,"strUpdateSql",strUpdateSql)
    --lua.DebugEx(strLuaDEID,"strCondition",strCondition)
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Temp_Container_Cell", strCondition, strUpdateSql)
    if nRet ~= 0 then
        return 1, "更新【Temp_Container_Cell】信息失败!" .. strRetInfo
    end
    return 0
end

--[[
    判断料箱 cntr 是否可以把货品移出进行合箱（把料箱中的货品理空）

    输入参数: cntr -- 料箱数据对象
             bc_cfg -- 合箱配置参数
             {
                dbtype,
                si_match_attrs  --- 补料匹配属性
             }
    输出参数:
              from_cntr_list -- 理空货品的料箱列表
              {
                cntr_code,
                to_cell_list = {} -- 理货出来的这些货品到这些料格
              }
              to_cntr_list -- 合箱列表（移出的货品到这些料箱）
              {
                cntr_code
              }
--]]
local function bin_consolidation_process(strLuaDEID, bc_cfg, cntr, from_cntr_list, to_cntr_list)
    local nRet, strRetInfo

    -- 判断料箱里的货品是否有被其它业务锁定数量，如果有锁定数量的不能作为清空目标
    local strCondition = "S_CNTR_CODE = '" .. cntr.code .. "' AND F_QTY <> F_QTY_VALID"
    nRet, strRetInfo = mobox.existThisData(strLuaDEID, "INV_Detail", strCondition)
    if nRet ~= 0 then
        return 2, "existThisData 函数失败!" .. strRetInfo
    end
    -- 如果 F_QTY_VALID 不等于 F_QTY 说明料箱有货品被其它也是锁定
    if strRetInfo == 'yes' then
        return 0, "INV_Detail lock data"
    end

    -- 获取料箱在 Temp_Continaer_Cell 里的 S_FLAG 如果已经是 To 类型不需要进行合箱处理
    strCondition = "S_CNTR_CODE = '" .. cntr.code .. "' AND S_FLAG = 'To' " ..
        "AND S_TRANS_ID = '" .. lua.trim_guid_str(strLuaDEID) .. "' "

    nRet, strRetInfo = mobox.existThisData(strLuaDEID, "Temp_Container_Cell", strCondition)
    if nRet ~= 0 then
        return 2, "existThisData 函数失败!" .. strRetInfo
    end
    -- 如果 F_QTY_VALID 不等于 F_QTY 说明料箱有货品被其它也是锁定
    if strRetInfo == 'yes' then
        return 0, "Temp_Container_Cell S_FLAG = 'To' data"
    end

    -- 查询料箱里的货品
    local detail_attrs_count = #INV_DETAIL_ATTRS
    local sku_attrs_count = #SKU_ATTRS
    local strAttrs = "a.S_ID," -- 需要把 TN_INV_Detail 中的 S_ID 获取
    local attr_set = { "S_ID" }
    local strTable =
    "TN_INV_Detail a LEFT JOIN TN_SKU b ON ( a.S_ITEM_CODE = b.S_ITEM_CODE and a.S_STORER = b.S_STORER )"

    for n = 1, detail_attrs_count do
        strAttrs = strAttrs .. "a." .. INV_DETAIL_ATTRS[n] .. ","
        table.insert(attr_set, INV_DETAIL_ATTRS[n])
    end
    for n = 1, sku_attrs_count do
        strAttrs = strAttrs .. "b." .. SKU_ATTRS[n] .. ","
        table.insert(attr_set, SKU_ATTRS[n])
    end
    strAttrs = lua.trim_laster_char(strAttrs)

    -- 获取料箱中的SKU信息
    local cntr_sku = {
        cntr_code = cntr.code,
        cell_type = cntr.spec,
        cell_list = {} -- 料箱里的货品根据料格来进行组织
    }
    strCondition = "a.S_CNTR_CODE = '" .. cntr.code .. "'"
    local strOrder = "a.S_CELL_NO"
    nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 2000, strCondition, strOrder)
    if nRet ~= 0 then
        return 2, "QueryDataObject失败!" .. strRetInfo
    end
    if strRetInfo == '' then
        return 0, " not inv_datail data [wms_bn]"
    end
    local data_objects = json.decode(strRetInfo)
    -- 获取from料箱中需要移出的 SKU
    local inv_detail_data
    local success
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
        sku.cntr_code = cntr_sku.cntr_code
        sku.sku_grid_parm = {}
        if not lua.StrIsEmpty(sku.S_SKU_GRID_PARM) then
            success, sku.sku_grid_parm = pcall(json.decode, sku.S_SKU_GRID_PARM)
            if success == false then
                return 1, "SKU 编码 = '" .. sku.S_ITEM_CODE .. "' 的数据对象中 S_SKU_GRID_PARM 不符合json规范!"
            end
        end
        sku.inv_detail_id = inv_detail_data.S_ID

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

    -- 查找可以移入的料箱。
    local to_cell_list -- 转移到这些料格
    -- 设置 Temp_Continaer_Cell 中该料箱格 为 from 的S_FLAG
    nRet, strRetInfo = set_temp_container_cell_flag(strLuaDEID, cntr_sku.cntr_code, "From")
    if nRet ~= 0 then
        lua.Stop(strLuaDEID, "set_temp_container_cell_flag:" .. strRetInfo)
        return 2, strRetInfo
    end
    nRet, to_cell_list = find_move_to_cntr(strLuaDEID, bc_cfg, cntr_sku)

    if nRet ~= 0 then
        return 2, to_cell_list
    end

    local strUpdateSql, strCondition

    if lua.isTableEmpty(to_cell_list) then
        -- 料箱没有匹配到合适的料格作为移出(to)的料箱
        -- 取消料箱的 From 标识
        nRet, strRetInfo = set_temp_container_cell_flag(strLuaDEID, cntr_sku.cntr_code, "")
        if nRet ~= 0 then
            return 2, strRetInfo
        end
    else
        local from_cntr = {
            cntr_code = cntr_sku.cntr_code,
            to_cell_list = to_cell_list
        }
        table.insert(from_cntr_list, from_cntr)

        for _, to_cell in ipairs(to_cell_list) do
            local find = false
            for _, to_cntr in ipairs(to_cntr_list) do
                if to_cntr.cntr_code == to_cell.to_cntr_code then
                    find = true
                    break
                end
            end
            if not find then
                local to_cntr = { cntr_code = to_cell.to_cntr_code }
                table.insert(to_cntr_list, to_cntr)
                -- 设置 S_FLAG = 'To', 优先级=100
                nRet, strRetInfo = set_temp_container_cell_flag(strLuaDEID, to_cell.to_cntr_code, "To", 100)
                if nRet ~= 0 then
                    return 2, strRetInfo
                end
            end
            -- 设置 Temp_Container_Cell 中的 F_REM_CAP
            if to_cell.cell_picked_method == "new_call_out" then
                -- 计算 F_REM_CAP
                local limit = 0
                local rem_cap = 0
                nRet, limit = wms_cntr.Calculate_Cell_Capacity(bc_cfg.ctd, to_cell.cell_type, to_cell.sku)
                if nRet ~= 0 then
                    return 1, limit
                end
                rem_cap = limit - to_cell.qty
                strUpdateSql = "F_REM_CAP = " .. rem_cap .. ", N_EMPTY_FULL = 1"
            else
                strUpdateSql = "F_REM_CAP = F_REM_CAP - " .. to_cell.qty .. ", N_EMPTY_FULL = 1"
            end

            strCondition = "S_CELL_NO = '" ..
                to_cell.to_cell_no ..
                "' AND S_CNTR_CODE = '" .. to_cell.to_cntr_code ..
                "' AND S_TRANS_ID = '" .. lua.trim_guid_str(strLuaDEID) .. "'"
            nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Temp_Container_Cell", strCondition,
                strUpdateSql)
            if nRet ~= 0 then
                return 2, "更新【Temp_Container_Cell】信息失败!" .. strRetInfo
            end
        end
    end
    return 0, "success"
end

-- 生成理货建议
--[[
    输入参数:
    consolidation_cfg -- 合箱容器查询条件（确定这些料箱进行合箱）
            consolidation_cfg = {
            wh_code ,
            area_code,
            ctd_code,                           -- 料箱定义编码
            cntr_ext_attr = ｛
                                ｛ attr = "S_UDF01", value = ""｝,..
                             ｝                 -- 料箱扩展属性
            cntr_util,                          -- 低于这个利用率的进行合箱，如果为0或nil不考虑
            bc_num = 0                          -- 合箱数量， 0 表示没限制
        }
    输出参数:
        from_cntr_list  -- 从这些料箱移出（产生空料箱）
        to_cntr_list    -- 把 from 料箱的移到 这些料箱

    算法基本构想:
        从满足 cntr_condition, cntr_ext_condition 的料箱中找出一个有货的料格数量最少，利用率最低的料箱
        把这个料箱定义为 from 料箱, 然后把 from 料箱里的货品从允许的范围内找到 to 的料箱格

    返回值
        0   -- 成功找合箱（也许没可以合并的料箱）
        非0 -- 错误
--]]

function wms_bin_con.Generate_Bin_Consolidation_Suggestions(strLuaDEID, consolidation_cfg, from_cntr_list, to_cntr_list)
    local nRet, strRetInfo, strCondition, strOrder

    -- step1: 获取当前服务配置的数据库类型
    local lua_info
    nRet, lua_info = lua.GetLuaDEInfo(strLuaDEID)
    if nRet ~= 0 then
        return 2, "GetLuaDEInfo 失败!" .. lua_info
    end
    local dbtype = lua_info.dbtype

    -- step2: 输入参数合法性检查，并且做数据准备
    if lua.isTableEmpty(consolidation_cfg) then
        return 2, "wms_bin_con.Generate_Bin_Consolidation_Suggestions 函数中 consolidation_cfg 必须要有值!"
    end
    -- 利用率低于 util 的料箱才进行合箱 util = 0 标识忽略利用率
    local util = consolidation_cfg.cntr_util or 0
    if util >= 100 then
        util = 0
    end

    local ctd_code = consolidation_cfg.ctd_code or ''
    if ctd_code == '' then
        return 2, "wms_bin_con.Generate_Bin_Consolidation_Suggestions 函数中 consolidation_cfg.ctd_code 必须要有值!"
    end
    -- 通过容器类型定义获取补料箱呼出规则
    local ctd
    nRet, ctd = wms_cntr.GetCTDInfo(ctd_code)
    if nRet ~= 0 then
        return 2, "容器类型定义'" .. ctd_code .. "'转换数据格式! --> " .. ctd
    end

    local wh_code = consolidation_cfg.wh_code or ''
    local area_code = consolidation_cfg.area_code or ''
    if wh_code == '' then
        return 2, "wms_bin_con.Generate_Bin_Consolidation_Suggestions 函数中 consolidation_cfg.wh_code 必须要有值!"
    end
    local bc_num = consolidation_cfg.bc_num or 0
    -- 组织匹配料格的查询条件
    local si_match_attrs = ctd.si_match_attrs or {}
    if type(si_match_attrs) ~= "table" then
        return 2, "输入参数错误, ctd.si_match_attrs 必须是 table 类型!"
    end
    -- 匹配属性要加上 S_ITEM_CODE, S_STRORER, S_ITEM_STATE
    table.insert(si_match_attrs, "S_STORER")
    table.insert(si_match_attrs, "S_ITEM_CODE")
    table.insert(si_match_attrs, "S_ITEM_STATE")

    -- step3: 生成料箱查询条件
    local cntr_ext_condition = ''

    -- 如果有料箱的扩展属性要查询，需要用到联表查询，因此这里的条件要加 b.
    if consolidation_cfg.cntr_ext_attr ~= nil then
        for _, ext_attr in ipairs(consolidation_cfg.cntr_ext_attr) do
            if cntr_ext_condition ~= '' then
                cntr_ext_condition = cntr_ext_condition .. " AND "
            end
            cntr_ext_condition = cntr_ext_condition .. "b." .. ext_attr.attr .. " = '" .. ext_attr.value .. "'"
        end
    end

    -- 如果带容器的扩展属性要多表联查
    local strTable = ''
    if cntr_ext_condition ~= '' then
        strTable = [[TN_Container a INNER JOIN TN_Container_Ext b ON a.S_CODE = b.S_CNTR_CODE
        INNER JOIN TN_Loc_Container c ON a.S_CODE = c.S_CNTR_CODE
        INNER JOIN TN_Location d ON c.S_LOC_CODE = d.S_CODE
        INNER JOIN TN_AREA e ON d.S_AREA_CODE = e.S_CODE]]

        strCondition = "a.C_ENABLE = 'Y' AND a.S_CTD_CODE = '" .. ctd_code .. "'" ..
            " AND a.N_LOCK_STATE = 0 AND a.N_EMPTY_FULL = 1 AND " .. cntr_ext_condition ..
            " AND e.N_TYPE = " .. AREA_TYPE.Storage_Area .. " AND d.S_WH_CODE = '" .. wh_code .. "'"
    else
        strTable = [[TN_Container a INNER JOIN TN_Loc_Container c ON a.S_CODE = c.S_CNTR_CODE
        INNER JOIN TN_Location d ON c.S_LOC_CODE = d.S_CODE
        INNER JOIN TN_AREA e ON d.S_AREA_CODE = e.S_CODE]]
        strCondition = "a.C_ENABLE = 'Y' AND a.S_CTD_CODE = '" .. ctd_code .. "'" ..
            " AND a.N_LOCK_STATE = 0 AND a.N_EMPTY_FULL = 1 " ..
            " AND e.N_TYPE = " .. AREA_TYPE.Storage_Area .. " AND d.S_WH_CODE = '" .. wh_code .. "'"
    end
    if area_code ~= '' then
        strCondition = strCondition .. " AND c.S_AREA_CODE = '" .. area_code .. "'"
    end
    -- 查找时根据有货料格最少，料箱利用率最少的料箱
    strOrder = "a.N_MAX_CELL_NUM - a.N_EMPTY_CELL_NUM, a.F_CNTR_UTIL, a.S_ID " -- 有货的料格数小的最前面

    -- step4: 合箱理货需要的数据初始化，主要是创建 Temp_Continaer_Cell 表
    --[[nRet, strRetInfo = data_initial( strLuaDEID, ctd, strTable, strCondition, strOrder )
    if nRet ~= 0 then
        return 2, strRetInfo
    end]]
    -- 对利用率小于某一个值的料箱进行合箱
    if util > 0 then
        strCondition = strCondition .. " AND a.F_CNTR_UTIL < " .. util
    end
    --批量生成Temp_Continaer_Cell
    local prd_no = consolidation_cfg.cntr_ext_attr[1].value
    mobox.abort(strLuaDEID)
    mobox.startTransaction(strLuaDEID)
    nRet, strRetInfo = batch_insert_temp_cell(strLuaDEID, strTable, strCondition, strOrder, prd_no)
    if nRet ~= 0 then
        mobox.abort(strLuaDEID)
        return 2, "batch_insert_temp_cell: " .. strRetInfo
    end
    mobox.commit(strLuaDEID)

    --查询满足条件的temp_cell
    local strSQL = "DROP TEMPORARY TABLE IF EXISTS TMP_CNTR;"
    nRet, strRetInfo = mobox.runSQL(strLuaDEID, strSQL)
    if nRet ~= 0 then
        return 1, "删除临时表失败!" .. strRetInfo
    end

    strSQL = "CREATE TEMPORARY TABLE TMP_CNTR AS " ..
        "select S_WMS_BN from tn_temp_container_cell where S_WMS_BN<>'' AND S_UDF01='"..prd_no.."' and f_rem_Cap>0 group by S_WMS_BN having(count(*)>1)"
    nRet, strRetInfo = lua.RunSQL(strLuaDEID, strSQL)
    if nRet ~= 0 then
        return 1, "系统创建临时表失败!" .. strRetInfo
    end

    strSQL = "DROP TEMPORARY TABLE IF EXISTS TMP_CNTR2;"
    nRet, strRetInfo = mobox.runSQL(strLuaDEID, strSQL)
    if nRet ~= 0 then
        return 1, "删除临时表失败!" .. strRetInfo
    end

    strSQL = "CREATE TEMPORARY TABLE TMP_CNTR2 AS " ..
        "SELECT DISTINCT a.S_CNTR_CODE FROM tn_temp_container_cell a inner join TMP_CNTR b on a.S_WMS_BN=b.S_WMS_BN"
    nRet, strRetInfo = lua.RunSQL(strLuaDEID, strSQL)
    if nRet ~= 0 then
        return 1, "系统创建临时表失败!" .. strRetInfo
    end

    -- step5: 查找出有货料格数量最少，利用率最低的料箱进行合箱理货
    local strAttrs = "a.S_CODE, a.S_SPEC, a.S_TYPE"
    strCondition = strCondition .. " AND EXISTS (SELECT 1 FROM TMP_CNTR2 WHERE S_CNTR_CODE=a.S_CODE)"
    nRet, strRetInfo = mobox.queryMultiTable2(strLuaDEID, strAttrs, strTable, 100, strCondition, strOrder)
    if nRet ~= 0 then
        return 2, "queryMultiTable2: " .. strRetInfo
    end

    if strRetInfo == '' then
        return 0
    end

    local queryInfo = json.decode(strRetInfo)
    local nPageCount = queryInfo.page_count
    local nPage = 1
    local data_list = queryInfo.data_list
    local bc_cfg = {
        dbtype = dbtype,
        ctd = ctd,
        si_match_attrs = si_match_attrs
    }
    --lua.DebugEx(strLuaDEID,"nPageCount",nPageCount)
    while (nPage <= nPageCount) do
        for n = 1, #data_list do
            local cntr =
            {
                code = data_list[n][1],
                spec = data_list[n][2],
                type = data_list[n][3]
            }

            local find = false
            -- 查出的料箱已经是在 to_cntr_list 就不能作为清空料箱目标
            for _, to_cntr in ipairs(to_cntr_list) do
                if to_cntr.cntr_code == cntr.code then
                    find = true
                    break
                end
            end
            if not find then
                mobox.abort(strLuaDEID)
                mobox.startTransaction(strLuaDEID)
                nRet, strRetInfo = bin_consolidation_process(strLuaDEID, bc_cfg, cntr, from_cntr_list, to_cntr_list)
                if nRet > 1 then
                    mobox.abort(strLuaDEID)
                    lua.DebugEx(strLuaDEID, "合箱过程错误", "在对料箱'" .. cntr.code .. "'进行合箱处理时发生错误-->" .. strRetInfo)
                end
                mobox.commit(strLuaDEID)
                if bc_num > 0 then
                    if bc_num == #from_cntr_list then
                        return 0
                    end
                end
            end
        end

        nPage = nPage + 1
        if nPage <= nPageCount then
            -- 取下一页
            nRet, strRetInfo = mobox.queryMultiTable2(strLuaDEID, nPage)
            if nRet ~= 0 then
                return 2, "查询【容器】失败! nPage=" .. nPage .. "  " .. strRetInfo
            end
            queryInfo = json.decode(strRetInfo)
            data_list = queryInfo.data_list
        end
    end
    return 0
end

return wms_bin_con
