--[[
    版本：     Version 3.0
    创建日期： 2025-5-16
    修改日期:  2026-6-19
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    名称:   wms_inventory
    功能：  和库存量表相关的操作（增删改查、锁定/解锁、移库、盘点调整、出库取消等）

    ——————————————————————————————————
    导出函数列表（共 18 个）:
    ——————————————————————————————————

    【库存量增删改查】
        After_CntrLoc_Binding      — 容器和货位绑定后创建库存量及交易日志
        After_CntrLoc_UnBinding    — 容器和货位解绑后删除库存量及交易日志
        INV_Detail_Delete          — 强制清空指定容器里的库存量
        INV_Detail_Exist           — 判断容器里是否存在库存量
        Add_INV_Detail_Qty         — 根据条件增加库存量（⚠ 谨慎使用）
        Reduce_INV_Detail_Qty      — 根据条件逐条扣减库存量
        Add_INV_Detail_By_PAC_Detail — 预分配容器明细写入库存量

    【分配与锁定】
        INV_Detail_Add_AllocQty    — 增加预分配量
        _INV_Detail_Pre_Alloc_Lock — 预分配量锁定为正式分配量
        INV_Detail_Add_MoveQty     — 增加移库数量

    【库存移动】
        Move                       — 库存量货位移动

    【出库与取消】
        INV_Detail_Out             — 分拣出库扣减库存量及分配量
        INV_Detail_SplitOut        — 分批扣减库存量
        DC_Detail_Cancel           — 配盘明细取消恢复分配量
        Distribution_CNTR_Cancel   — 分拣出库配盘取消

    【盘点调整与理货】
        INV_Detail_Add_Qty_By_ADJ  — 盘点调整增加数量
        INV_Detail_Reduce_Qty_By_ADJ — 盘点调整减少数量
        Tally_Detail_Process       — 理货任务完成后库存量处理

    ——————————————————————————————————
        INV_Detail_Hold             -- 库存冻结
        INV_Detail_UnHold           -- 库存解冻 

    更改记录:
        2025-5-16  HAN  创建
        2026-6-19        整理函数清单，统一注释格式

    AI CHECK:
        -- 20260619
--]]

--+-----------------------------------------------------------------------------+
--| 注意: wms_inv 是比较底层的业务逻辑处理层，不能再加其它和 wms_xxx 相关的 require  |
--+-----------------------------------------------------------------------------+
wms_base = require("wms_base")

local wms_inv = { _version = "0.2.1" }

-- 在指定的料箱料格中加入一个货品（新建或合并），同时生成 INV_TXN_Log
-- 若 ctd 定义了 qty_merge，则在写入前先查找可合并的存量记录
-- @function wms_inv.Add_Merga_INV_Detail_Qty
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table ctd 容器类型定义表, 含 qty_merge、merge_attrs_def 等
-- @tparam string cntr_code 料箱编码, 必须有值
-- @tparam string cell_no 料格号, 可为空字符串
-- @tparam table loc 当前货位数据对象, 含 wh_code/area_code/code
-- @tparam table item_detail_data 入库货品数据对象
-- @tparam number qty 入库数量
-- @tparam string add_log_type S_LOG_TYPE 值（"IN"/"ADD-IN"/"MOVE-IN" 等）
-- @treturn number nRet 0=成功, 非0=失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.Add_Merga_INV_Detail_Qty(strLuaDEID, ctd, cntr_code, cell_no, loc, item_detail_data, qty, add_log_type)
    -- MDF BY HAN AT 20250722 合并数量
    local new_detail = true
    local inv_detail_id = ''
    local cur_qty = 0
    local nRet, strRetInfo

    if type(qty) == "string" then
        qty = tonumber(qty)
    end
    if cell_no == nil then cell_no = '' end

    if ctd.qty_merge then
        -- 数量要合并
        -- 先根据CTD中的定义组合查询条件，是否有符合条件的 INV 存在
        local merge_condition = "S_CNTR_CODE = '" ..
            cntr_code .. "' AND S_ITEM_CODE = '" .. item_detail_data.S_ITEM_CODE .. "' " ..
            "AND S_CELL_NO = '" .. cell_no .. "' " ..
            "AND S_STORER = '" .. item_detail_data.S_STORER ..
            "' AND S_ITEM_STATE = '" .. item_detail_data.S_ITEM_STATE .. "'"
        local str_value
        for i = 1, #ctd.merge_attrs_def do
            str_value = item_detail_data[ctd.merge_attrs_def[i].attr] or ''
            if str_value ~= '' then
                if ctd.merge_attrs_def[i].type == "string" then
                    merge_condition = merge_condition .. " AND " .. ctd.merge_attrs_def[i].attr ..
                    " = '" .. str_value .. "' "
                else
                    merge_condition = merge_condition .. " AND " .. ctd.merge_attrs_def[i].attr .. " = " .. str_value
                end
            end
        end
        -- 如果不存在返回 = 1
        local inv_detail
        nRet, inv_detail = m3.GetDataObjByCondition(strLuaDEID, "INV_Detail", merge_condition)

        if nRet == 0 then
            cur_qty = inv_detail.qty
            inv_detail_id = inv_detail.id
            local strUpdateSql = "F_QTY = F_QTY + " .. qty
            local strCondition = "S_ID = '" .. inv_detail.id .. "'"
            nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "INV_Detail", strCondition, strUpdateSql)
            if nRet ~= 0 then
                return 2, "更新【INV_Detail】信息失败!" .. strRetInfo
            end
            new_detail = false
        else
            cur_qty = 0
        end
    end

    if new_detail then
        local curTime = os.date("%Y-%m-%d %H:%M:%S")
        -- 创建库存量表
        local inv_detail_data = m3.AllocObject2(strLuaDEID, "INV_Detail")
        inv_detail_data.T_INBOUND_TIME = curTime
        for m = 1, #PAC_DETAIL_BASE_ATTRS do
            inv_detail_data[PAC_DETAIL_BASE_ATTRS[m]] = item_detail_data[PAC_DETAIL_BASE_ATTRS[m]]
        end
        for m = 1, #UDF_ATTRS do
            inv_detail_data[UDF_ATTRS[m]] = item_detail_data[UDF_ATTRS[m]]
        end
        inv_detail_data.S_WH_CODE = loc.wh_code
        inv_detail_data.S_AREA_CODE = loc.area_code
        inv_detail_data.S_LOC_CODE = loc.code
        inv_detail_data.F_QTY = qty
        inv_detail_data.S_CNTR_CODE = cntr_code
        inv_detail_data.S_CELL_NO = cell_no
        nRet, inv_detail_data = m3.CreateDataObj2(strLuaDEID, inv_detail_data)
        if nRet ~= 0 then
            return 1, "创建【库存量表】失败!" .. inv_detail_data
        end
        inv_detail_id = inv_detail_data.id
    end

    -- 创建库存交易日志
    cur_qty = cur_qty + qty
    local inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")
    -- CheckOK
    for m = 1, #INV_TXT_LOG_ATTRS do
        inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = item_detail_data[INV_TXT_LOG_ATTRS[m]]
    end
    for m = 1, #UDF_ATTRS do
        inv_txn_log_data[UDF_ATTRS[m]] = item_detail_data[UDF_ATTRS[m]]
    end


    inv_txn_log_data.S_WH_CODE = loc.wh_code
    inv_txn_log_data.S_AREA_CODE = loc.area_code
    inv_txn_log_data.S_LOC_CODE = loc.code
    inv_txn_log_data.S_CNTR_CODE = cntr_code
    inv_txn_log_data.S_LOG_TYPE = add_log_type
    inv_txn_log_data.C_SYMBOL = "+"
    inv_txn_log_data.G_INV_DETAIL_ID = inv_detail_id
    -- MDF BY HAN @20250829
    inv_txn_log_data.F_CUR_QTY = cur_qty

    nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
    if nRet ~= 0 then
        return 1, "创建【库存交易日志】失败!" .. inv_txn_log_data
    end
    lua.DebugEx(strLuaDEID, "inv_txn_log_data", inv_txn_log_data)
    return 0
end

-- 对入库/出库明细进行基础字段检查，若无 S_ITEM_STATE/S_STORER 则用缺省值补齐
-- 检查: S_ITEM_CODE 必须非空, F_QTY > 0
-- @function item_detail_data_check
-- @tparam table item_detail_data 待检查的货品明细数据对象
-- @tparam string default_storer 缺省货主
-- @tparam string default_item_state 缺省货品状态
-- @treturn boolean ok true=通过, false=未通过
-- @treturn string errMsg 未通过时的错误信息
local function item_detail_data_check(item_detail_data, default_storer, default_item_state)
    -- 数据检查
    if lua.StrIsEmpty(item_detail_data.S_ITEM_CODE) then
        return false, "创建【库存量表】前检查没通过! S_ITEM_CODE 为空"
    end
    if lua.StrIsEmpty(item_detail_data.S_ITEM_STATE) then
        if default_item_state == '' then
            return false, "数据检查没通过! S_ITEM_STATE 为空并且没设置默认货品状态常量 WMS_Default_ItemState 没定义!"
        end
        item_detail_data.S_ITEM_STATE = default_item_state
    end
    if lua.StrIsEmpty(item_detail_data.S_STORER) then
        if default_storer == '' then
            return false, "数据检查没通过! S_STORER 为空并且没设置默认货主常量 WMS_Default_Storer 没定义!"
        end
        item_detail_data.S_STORER = default_storer
    end
    if lua.Get_NumAttrValue(item_detail_data.F_QTY) <= 0 then
        return false, "数据检查没通过! S_ITEM_CODE ='" .. item_detail_data.S_ITEM_CODE .. "' 的数量属性 F_QTY 不能 <= 0!"
    end
    return true
end

-- 容器和货位绑定后，根据 INB_Pallet_Detail（码盘明细）创建 INV_Detail 及 INV_TXN_Log
-- @function wms_inv.After_CntrLoc_Binding
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table inb_pallet 码盘对象, { ibp_no: 码盘单号, cntr_code: 容器编码 }
-- @tparam string loc_code 货位编码, 必须有值且非空
-- @treturn number nRet 0=成功, 1=参数错误, 2=操作失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.After_CntrLoc_Binding(strLuaDEID, inb_pallet, loc_code)
    local nRet, strRetInfo

    if inb_pallet == nil or type(inb_pallet) ~= "table" then
        return 1, "After_CntrLoc_Binding 函数输入参数错误 inb_pallet 为空或不合规"
    end
    if loc_code == nil or loc_code == '' then
        return 1, "After_CntrLoc_Binding 函数输入参数错误 loc_code 不能为空!"
    end

    local loc
    nRet, loc = wms_wh.GetLocInfo(loc_code)
    if nRet ~= 0 then
        return 1, "获取货位'" .. loc_code .. "'信息失败! " .. loc
    end

    -- 查询【INB_Pallet_Detail】
    local strOrder = ""
    local data_objects
    local strCondition = "S_IBP_NO = '" .. inb_pallet.ibp_no .. "'"
    nRet, data_objects = m3.QueryDataObject(strLuaDEID, "INB_Pallet_Detail", strCondition, strOrder)
    if nRet ~= 0 then
        return 2, "QueryDataObject失败!" .. data_objects
    end
    if data_objects == '' then
        return 0
    end

    local base_attr_count
    local inv_detail_data
    local inv_txn_log_data
    local item_detail_data
    local check_is_ok

    -- 缺省值设置
    local default_storer = '' -- 默认货主
    nRet, default_storer = wms_base.Get_sConst2("WMS_Default_Storer")
    if nRet ~= 0 then
        default_storer = ''
    end
    local default_item_state = '' -- 默认货品状态
    nRet, default_item_state = wms_base.Get_sConst2("WMS_Default_ItemState")
    if nRet ~= 0 then
        default_item_state = ''
    end

    base_attr_count = #INV_DETAIL_BASE_ATTRS
    local curTime = os.date("%Y-%m-%d %H:%M:%S")
    local inv_txt_log_attr_count = #INV_TXT_LOG_ATTRS

    for n = 1, #data_objects do
        item_detail_data = m3.KeyValueAttrsToObjAttr(data_objects[n].attrs)
        if item_detail_data == nil then
            return 2, "KeyValueAttrsToObjAttr 失败!"
        end
        check_is_ok, strRetInfo = item_detail_data_check(item_detail_data, default_storer, default_item_state)
        if not check_is_ok then
            return 1, strRetInfo
        end
        -- 创建库存量表
        inv_detail_data = m3.AllocObject2(strLuaDEID, "INV_Detail")
        inv_detail_data.S_WH_CODE = loc.wh_code
        inv_detail_data.S_AREA_CODE = loc.area_code
        inv_detail_data.S_LOC_CODE = loc.code
        inv_detail_data.S_CNTR_CODE = inb_pallet.cntr_code
        inv_detail_data.T_INBOUND_TIME = curTime

        -- CheckOK
        -- 如果码盘明细中没明确来源单类型
        if item_detail_data.S_BS_TYPE == nil or item_detail_data.S_BS_TYPE == '' then
            item_detail_data.S_BS_TYPE = "Inbound_Palletization"
            item_detail_data.S_BS_NO = inb_pallet.ibp_no
        end
        for m = 1, base_attr_count do
            inv_detail_data[INV_DETAIL_BASE_ATTRS[m]] = item_detail_data[INV_DETAIL_BASE_ATTRS[m]]
        end
        for m = 1, #UDF_ATTRS do
            inv_detail_data[UDF_ATTRS[m]] = item_detail_data[UDF_ATTRS[m]]
        end

        nRet, inv_detail_data = m3.CreateDataObj2(strLuaDEID, inv_detail_data)
        if nRet ~= 0 then
            return 1, "创建【库存量表】失败!" .. inv_detail_data
        end

        -- 创建库存交易日志
        inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")
        if inv_txn_log_data == nil then
            return 2, "AllocObject2 失败!"
        end
        inv_txn_log_data.S_WH_CODE = loc.wh_code
        inv_txn_log_data.S_AREA_CODE = loc.area_code
        inv_txn_log_data.S_LOC_CODE = loc.code
        inv_txn_log_data.S_CNTR_CODE = inb_pallet.cntr_code
        inv_txn_log_data.S_LOG_TYPE = "IN"
        inv_txn_log_data.C_SYMBOL = "+"
        inv_txn_log_data.G_INV_DETAIL_ID = inv_detail_data.id
        -- CheckOK
        for m = 1, inv_txt_log_attr_count do
            inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = item_detail_data[INV_TXT_LOG_ATTRS[m]]
        end
        for m = 1, #UDF_ATTRS do
            inv_txn_log_data[UDF_ATTRS[m]] = item_detail_data[UDF_ATTRS[m]]
        end

        -- MDF BY HAN @20250829
        inv_txn_log_data.F_CUR_QTY = inv_txn_log_data.F_QTY

        nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
        if nRet ~= 0 then
            return 1, "创建【库存交易日志】失败!" .. inv_txn_log_data
        end
    end
    return 0
end

-- @function wms_inv.After_CntrLoc_UnBinding
-- 容器和货位解绑后，删除该容器下所有 INV_Detail 记录并生成 INV_TXN_Log
-- 解绑前校验：若任一记录的 F_QTY > F_QTY_VALID（有业务锁定），则拒绝解绑
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值且非空
-- @tparam string str_note 备注
-- @treturn number nRet 0=成功, 1=有记录被锁定无法解绑, 2=操作失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.After_CntrLoc_UnBinding(strLuaDEID, cntr_code, str_note)
    local nRet, strRetInfo

    if cntr_code == nil or cntr_code == '' then
        return 2, "After_CntrLoc_UnBinding 函数输入参数错误 cntr_code 不能为空!"
    end

    -- 查询【INV_Detail】
    local strOrder = ""
    local strCondition = "S_CNTR_CODE = '" .. cntr_code .. "'"
    local data_objects
    nRet, data_objects = m3.QueryDataObject(strLuaDEID, "INV_Detail", strCondition, strOrder)
    if nRet ~= 0 then
        return 2, "QueryDataObject失败!" .. data_objects
    end
    if data_objects == '' then
        return 0
    end

    local udf_attr_count, inv_txt_log_attr_count
    local inv_detail_data
    local inv_txn_log_data
    local qty, valid_qty

    udf_attr_count = #UDF_ATTRS
    inv_txt_log_attr_count = #INV_TXT_LOG_ATTRS

    for n = 1, #data_objects do
        inv_detail_data = m3.KeyValueAttrsToObjAttr(data_objects[n].attrs)
        if inv_detail_data == nil then
            return 1, "KeyValueAttrsToObjAttr失败!"
        end
        -- MDF BY HAN @2025-12-24
        -- 判断一下是否有存在分配量，冻结量，移动量，如果有不能进行解绑
        qty = lua.Get_NumAttrValue( inv_detail_data.F_QTY )
        valid_qty = lua.Get_NumAttrValue( inv_detail_data.F_QTY_VALID )
        if qty > valid_qty then
            return 1, "容器中货品'" .. inv_detail_data.S_ITEM_CODE.."'存在被其它业务锁定的数量, 不能解绑!"
        end

        -- 创建库存交易日志
        inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")
        if inv_txn_log_data == nil then
            return 2, "AllocObject2 失败!"
        end
        inv_txn_log_data.S_WH_CODE = inv_detail_data.S_WH_CODE
        inv_txn_log_data.S_AREA_CODE = inv_detail_data.S_AREA_CODE
        inv_txn_log_data.S_LOC_CODE = inv_detail_data.S_LOC_CODE
        inv_txn_log_data.S_CNTR_CODE = cntr_code
        inv_txn_log_data.S_LOG_TYPE = "OUT"
        inv_txn_log_data.C_SYMBOL = "-"
        inv_txn_log_data.S_NOTE = str_note
        inv_txn_log_data.G_INV_DETAIL_ID = data_objects[n].id

        --CheckOK
        for m = 1, inv_txt_log_attr_count do
            inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = inv_detail_data[INV_TXT_LOG_ATTRS[m]]
        end
        for m = 1, udf_attr_count do
            inv_txn_log_data[UDF_ATTRS[m]] = inv_detail_data[UDF_ATTRS[m]]
        end

        inv_txn_log_data.F_QTY = -lua.Get_NumAttrValue(inv_txn_log_data.F_QTY)
        inv_txn_log_data.S_BS_TYPE = "UnBinding"
        inv_txn_log_data.S_BS_NO = ""
        inv_txn_log_data.N_BS_ROW_NO = 0
        -- MDF BY HAN @20250829
        inv_txn_log_data.F_CUR_QTY = 0

        nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
        if nRet ~= 0 then
            return 2, "创建【库存交易日志】失败!" .. inv_txn_log_data
        end
    end
    -- 删除 INV_Detail
    strCondition = "S_CNTR_CODE = '" .. cntr_code .. "'"
    nRet, strRetInfo = mobox.dbdeleteData(strLuaDEID, "INV_Detail", strCondition)
    if nRet ~= 0 then
        return 2, "删除【INV_Detail】失败!" .. strRetInfo
    end

    return 0
end

-- @function wms_inv.Move
-- 库存量货位移动：将该容器所有 INV_Detail 的货位从 from 更新为 to
-- 分别生成 MOVE-OUT 和 MOVE-IN 两条 INV_TXN_Log
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值且非空
-- @tparam string from 移库起始货位编码
-- @tparam string to 移库终点货位编码
-- @tparam table ext_parameter 扩展参数, { bs_type, bs_no, bs_row_no, note, p_cntr_code }
-- @treturn number nRet 0=成功, 非0=失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.Move(strLuaDEID, cntr_code, from, to, ext_parameter)
    local nRet, strRetInfo
    local loc_from, loc_to

    if cntr_code == nil or cntr_code == '' then
        return 1, "wms_inv.Move 函数输入参数错误 cntr_code 不能为空!"
    end
    if from == nil or from == '' then
        return 1, "wms_inv.Move 函数输入参数错误 from 不能为空!"
    end
    nRet, loc_from = wms_wh.GetLocInfo(from)
    if nRet ~= 0 then
        return 1, "获取货位'" .. from .. "'信息失败! " .. loc_from
    end

    if to == nil or to == '' then
        return 1, "wms_inv.Move 函数输入参数错误 to 不能为空!"
    end
    nRet, loc_to = wms_wh.GetLocInfo(to)
    if nRet ~= 0 then
        return 1, "获取货位'" .. to .. "'信息失败! " .. loc_to
    end

    if ext_parameter == nil then ext_parameter = {} end
    local note = ''
    local bs_type = ''
    local bs_no = ''
    local bs_row_no = 0
    local p_cntr_code = ''

    if not lua.isTableEmpty(ext_parameter) then
        note = ext_parameter.note or ''
        bs_type = ext_parameter.bs_type or ''
        bs_no = ext_parameter.bs_no or ''
        bs_row_no = ext_parameter.bs_row_no or 0
        p_cntr_code = ext_parameter.p_cntr_code or ''
    end

    -- 查询【INV_Detail】
    -- local strCondition = "S_CNTR_CODE = '" .. cntr_code .. "' AND S_LOC_CODE = '" .. from .. "'"
    -- MDF BY HAN @20251203
    -- 项目端反馈 货位可能不准确，因此用 S_LOC_CODE 查询会失败，取消货位查询条件
    local strCondition = "S_CNTR_CODE = '" .. cntr_code .. "'"
    local strOrder = ""
    local data_objects
    nRet, data_objects = m3.QueryDataObject(strLuaDEID, "INV_Detail", strCondition, strOrder)
    if nRet ~= 0 then
        return 2, "QueryDataObject失败!" .. data_objects
    end
    if data_objects == '' then
        return 0
    end

    local inv_txt_log_attr_count, udf_attr_count
    local inv_detail_data
    local inv_txn_log_data

    inv_txt_log_attr_count = #INV_TXT_LOG_ATTRS
    udf_attr_count = #UDF_ATTRS

    for n = 1, #data_objects do
        inv_detail_data = m3.KeyValueAttrsToObjAttr(data_objects[n].attrs)
        if inv_detail_data == nil then
            return 1, "KeyValueAttrsToObjAttr失败!"
        end

        -- 创建库存交易日志
        -- 从from库位移出
        inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")
        if inv_txn_log_data == nil then
            return 2, "AllocObject2 失败!"
        end        
        inv_txn_log_data.S_WH_CODE = loc_from.wh_code
        inv_txn_log_data.S_AREA_CODE = loc_from.area_code
        inv_txn_log_data.S_LOC_CODE = loc_from.code
        inv_txn_log_data.S_CNTR_CODE = cntr_code
        inv_txn_log_data.S_LOG_TYPE = "MOVE-OUT"
        inv_txn_log_data.C_SYMBOL = "-"
        inv_txn_log_data.G_INV_DETAIL_ID = data_objects[n].id

        -- CheckOK
        for m = 1, inv_txt_log_attr_count do
            inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = inv_detail_data[INV_TXT_LOG_ATTRS[m]]
        end
        for m = 1, udf_attr_count do
            inv_txn_log_data[UDF_ATTRS[m]] = inv_detail_data[UDF_ATTRS[m]]
        end
        -- MDF BY HAN @20250829
        inv_txn_log_data.F_CUR_QTY = 0

        inv_txn_log_data.F_QTY = -lua.Get_NumAttrValue(inv_txn_log_data.F_QTY)
        inv_txn_log_data.S_BS_TYPE = bs_type
        inv_txn_log_data.S_BS_NO = bs_no
        inv_txn_log_data.N_BS_ROW_NO = bs_row_no
        inv_txn_log_data.S_NOTE = note
        nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
        if nRet ~= 0 then
            return 1, "创建【库存交易日志】失败!" .. inv_txn_log_data
        end

        -- 移到to库位
        inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")
        if inv_txn_log_data == nil then
            return 2, "AllocObject2 失败!"
        end        
        inv_txn_log_data.S_WH_CODE = loc_to.wh_code
        inv_txn_log_data.S_AREA_CODE = loc_to.area_code
        inv_txn_log_data.S_LOC_CODE = loc_to.code
        inv_txn_log_data.S_CNTR_CODE = cntr_code
        inv_txn_log_data.S_LOG_TYPE = "MOVE-IN"
        inv_txn_log_data.G_INV_DETAIL_ID = data_objects[n].id
        inv_txn_log_data.C_SYMBOL = "+"

        -- CheckOK
        for m = 1, inv_txt_log_attr_count do
            inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = inv_detail_data[INV_TXT_LOG_ATTRS[m]]
        end
        for m = 1, udf_attr_count do
            inv_txn_log_data[UDF_ATTRS[m]] = inv_detail_data[UDF_ATTRS[m]]
        end
        -- MDF BY HAN @20250829
        inv_txn_log_data.F_CUR_QTY = inv_txn_log_data.F_QTY

        inv_txn_log_data.S_BS_TYPE = bs_type
        inv_txn_log_data.S_BS_NO = bs_no
        inv_txn_log_data.N_BS_ROW_NO = bs_row_no
        inv_txn_log_data.S_NOTE = note

        nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
        if nRet ~= 0 then
            return 1, "创建【库存交易日志】失败!" .. inv_txn_log_data
        end
    end

    --更新 INV_Detail
    -- strCondition = "S_CNTR_CODE = '" .. cntr_code .. "' AND S_LOC_CODE = '" .. from .. "'"
    -- MDF BY HAN @20251203
    -- 项目端反馈 货位可能不准确，因此用 S_LOC_CODE 查询会失败，取消货位查询条件
    strCondition = "S_CNTR_CODE = '" .. cntr_code .. "'"

    local strUpdateSql = "S_WH_CODE = '" ..
    loc_to.wh_code .. "', S_AREA_CODE = '" .. loc_to.area_code .. "', S_LOC_CODE = '" .. loc_to.code .. "'"
    -- MDF BY HAN @20260727
    if ext_parameter.p_cntr_code ~= nil then
        strUpdateSql = strUpdateSql .. ", P_CNTR_CODE = '" .. p_cntr_code .. "'"
    end

    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "INV_Detail", strCondition, strUpdateSql)
    if nRet ~= 0 then
        return 2, "更新[INV_Detail]信息失败!" .. strRetInfo
    end
    return 0
end

-- @function inv_detail_update
-- 更新单条 INV_Detail 记录（通过 updateDataObj 触发变更事件）
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table inv_detail INV_Detail 对象, 必须含 .id
-- @treturn number nRet 0=成功, 非0=失败
-- @treturn string strRetInfo 成功时返回 "ok", 失败时为错误信息
local function inv_detail_update( strLuaDEID, inv_detail )
    if  inv_detail.id == nil or inv_detail.id == ''  then
        return 1, "调用 inv_detail_update 函数时参数不正确, ID不能为空!"
    end
    local nRet, strAttrs
    nRet, strAttrs = mobox.objJsonToObjAttr( "INV_Detail", lua.table2str(inv_detail))
    if nRet ~= 0 then
        return nRet, strAttrs
    end

    local strUpdate = '[{"id":"'..inv_detail.id..'","attrs":'..strAttrs..'}]'
    local strRetInfo

    nRet, strRetInfo = mobox.updateDataObj( strLuaDEID, "INV_Detail", strUpdate, 1 )
    if  nRet ~= 0  then
        return nRet, strRetInfo
    end
    return 0, "ok"
end
-- @function wms_inv.Reduce_INV_Detail_Qty
-- 根据 strCondition 查询并逐条扣减 INV_Detail 的数量（F_QTY）
-- 若扣减后 F_QTY <= 0，则删除该条 INV_Detail 记录
-- 每条变更均生成对应的 INV_TXN_Log （ADJ-OUT）
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值且非空
-- @tparam string strCondition 查询条件（WHERE 子句, 不带 WHERE 关键字）
-- @tparam string strOrder 排序
-- @tparam number qty 本次扣减总数量, 必须为 number 类型且 > 0
-- @tparam table ext_parameter 扩展参数, { bs_type, bs_no, bs_row_no, note }
-- @treturn number nRet 0=成功, 1=无匹配记录(none), 2=失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.Reduce_INV_Detail_Qty(strLuaDEID, cntr_code, strCondition, strOrder, qty, ext_parameter)
    local nRet, strRetInfo

    if cntr_code == nil or cntr_code == '' then
        return 1, "Reduce_INV_Detail_Qty 函数中 cntr_code 不能为空!"
    end
    if strCondition == nil or strCondition == '' then
        return 1, "Reduce_INV_Detail_Qty 函数中 strCondition 不能为空!"
    end
    if type(qty) ~= "number" then
        return 1, "Reduce_INV_Detail_Qty 函数中 qty 必须是数值类型!"
    end
    if qty <= 0 then
        return 1, "Reduce_INV_Detail_Qty 函数中 qty 必须大于0!"
    end

    local note = ''
    local bs_type = ''
    local bs_no = ''
    local bs_row_no = 0

    if not lua.isTableEmpty(ext_parameter) then
        note = ext_parameter.note or ''
        bs_type = ext_parameter.bs_type or ''
        bs_no = ext_parameter.bs_no or ''
        bs_row_no = ext_parameter.bs_row_no or 0
    end

    local data_objects
    nRet, data_objects = m3.QueryDataObject(strLuaDEID, "INV_Detail", strCondition, strOrder)
    if nRet ~= 0 then
        return 2, "QueryDataObject失败!" .. data_objects
    end
    if data_objects == '' then
        return 0
    end

    local inv_detail_data
    local value
    local inv_txn_log_data
    local udf_attr_count, inv_txt_log_attr_count

    inv_txt_log_attr_count = #INV_TXT_LOG_ATTRS
    udf_attr_count = #UDF_ATTRS

    for n = 1, #data_objects do
        inv_detail_data = m3.KeyValueAttrsToObjAttr(data_objects[n].attrs)
        if inv_detail_data == nil then
            return 1, "KeyValueAttrsToObjAttr失败!"
        end
        inv_detail_data.id = lua.trim_guid_str( data_objects[n].id )
        inv_detail_data.cls = "INV_Detail"
        value = lua.Get_NumAttrValue(inv_detail_data.F_QTY)

        if qty >= value then
            -- 创建 INV_Log
            inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")
            if inv_txn_log_data == nil then
                return 2, "AllocObject2 失败!"
            end            
            inv_txn_log_data.S_WH_CODE = inv_detail_data.S_WH_CODE
            inv_txn_log_data.S_AREA_CODE = inv_detail_data.S_AREA_CODE
            inv_txn_log_data.S_LOC_CODE = inv_detail_data.S_LOC_CODE
            inv_txn_log_data.S_CNTR_CODE = cntr_code
            inv_txn_log_data.S_LOG_TYPE = "ADJ-OUT"
            inv_txn_log_data.C_SYMBOL = "-"
            inv_txn_log_data.S_NOTE = note
            inv_txn_log_data.G_INV_DETAIL_ID = data_objects[n].id

            -- CheckOK
            for m = 1, inv_txt_log_attr_count do
                inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = inv_detail_data[INV_TXT_LOG_ATTRS[m]]
            end
            for m = 1, udf_attr_count do
                inv_txn_log_data[UDF_ATTRS[m]] = inv_detail_data[UDF_ATTRS[m]]
            end

            -- MDF BY HAN @20250829
            inv_txn_log_data.F_CUR_QTY = 0
            inv_txn_log_data.F_QTY = -lua.Get_NumAttrValue(inv_txn_log_data.F_QTY)
            inv_txn_log_data.S_BS_TYPE = bs_type
            inv_txn_log_data.S_BS_NO = bs_no
            inv_txn_log_data.N_BS_ROW_NO = bs_row_no

            -- 删除 INV_Detail
            strCondition = "S_ID = '" .. data_objects[n].id .. "'"
            nRet, strRetInfo = mobox.deleteDataObject(strLuaDEID, "INV_Detail", strCondition)
            if nRet ~= 0 then
                return 1, "删除相关的【INV_Detail】失败!  " .. strRetInfo
            end

            nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
            if nRet ~= 0 then
                return 1, "创建【库存交易日志】失败!" .. inv_txn_log_data
            end
            if qty == value then 
                goto done 
            end
        else
            -- 减少 INV_Detail 中的数量
            -- 创建 INV_Log
            inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")
            if inv_txn_log_data == nil then
                return 2, "AllocObject2 失败!"
            end            
            inv_txn_log_data.S_WH_CODE = inv_detail_data.S_WH_CODE
            inv_txn_log_data.S_AREA_CODE = inv_detail_data.S_AREA_CODE
            inv_txn_log_data.S_LOC_CODE = inv_detail_data.S_LOC_CODE
            inv_txn_log_data.S_CNTR_CODE = cntr_code
            inv_txn_log_data.S_LOG_TYPE = "ADJ-OUT"
            inv_txn_log_data.C_SYMBOL = "-"
            inv_txn_log_data.S_NOTE = note
            inv_txn_log_data.G_INV_DETAIL_ID = data_objects[n].id
            --CheckOK
            for m = 1, inv_txt_log_attr_count do
                inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = inv_detail_data[INV_TXT_LOG_ATTRS[m]]
            end
            for m = 1, udf_attr_count do
                inv_txn_log_data[UDF_ATTRS[m]] = inv_detail_data[UDF_ATTRS[m]]
            end

            -- MDF BY HAN @20250829
            inv_txn_log_data.F_CUR_QTY = value - qty
            inv_txn_log_data.F_QTY = -qty
            inv_txn_log_data.S_BS_TYPE = ""
            inv_txn_log_data.S_BS_NO = ""
            inv_txn_log_data.N_BS_ROW_NO = 0

            inv_detail_data.F_QTY = value - qty
            nRet, strRetInfo = inv_detail_update(strLuaDEID, inv_detail_data)
            if nRet ~= 0 then 
                return 1, "inv_detail_update 失败!  " .. strRetInfo 
            end
            nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
            if nRet ~= 0 then
                return 1, "创建【库存交易日志】失败!" .. inv_txn_log_data
            end
            goto done
        end
        qty = qty - value
    end

    ::done::
    return 0, ""
end

-- ⚠ 谨慎使用！根据条件对匹配的第一条 INV_Detail 加数量（F_QTY）一般用中盘点调整库存数量
-- @function wms_inv.Add_INV_Detail_Qty
-- 生成 INV_TXN_Log（S_LOG_TYPE="ADJ-IN"）
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值且非空
-- @tparam string strCondition 查询条件（WHERE 子句, 不带 WHERE 关键字）
-- @tparam string strOrder 排序
-- @tparam number qty 增加数量, 必须为 number 类型且 > 0
-- @tparam table ext_parameter 扩展参数, { bs_type, bs_no, bs_row_no, note, udf_attr }
-- @treturn number nRet 0=成功, 1=无匹配记录(none), 2=失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.Add_INV_Detail_Qty(strLuaDEID, cntr_code, strCondition, strOrder, qty, ext_parameter)
    local nRet, strRetInfo

    if cntr_code == nil or cntr_code == '' then
        return 1, "Add_INV_Detail_Qty 函数中 cntr_code 不能为空!"
    end
    if strCondition == nil or strCondition == '' then
        return 1, "Add_INV_Detail_Qty 函数中 strCondition 不能为空!"
    end
    if type(qty) ~= "number" then
        return 1, "Add_INV_Detail_Qty 函数中 qty 必须是数值类型!"
    end
    if qty <= 0 then
        return 1, "Add_INV_Detail_Qty 函数中 qty 必须大于0!"
    end
    local note = ''
    local bs_type = ''
    local bs_no = ''
    local bs_row_no = 0

    if not lua.isTableEmpty(ext_parameter) then
        note = ext_parameter.note or ''
        bs_type = ext_parameter.bs_type or ''
        bs_no = ext_parameter.bs_no or ''
        bs_row_no = ext_parameter.bs_row_no or 0
    end

    local data_objects
    nRet, data_objects = m3.QueryDataObject(strLuaDEID, "INV_Detail", strCondition, strOrder)
    if nRet ~= 0 then 
        return 2, "QueryDataObject失败!" .. data_objects 
    end
    if data_objects == '' then
        return 0
    end

    local inv_detail_data = m3.KeyValueAttrsToObjAttr(data_objects[1].attrs)
    if inv_detail_data == nil then
        return 1, "KeyValueAttrsToObjAttr失败!"
    end
    local cur_qty = lua.Get_NumAttrValue(inv_detail_data.F_QTY)
    local strUpdateCondition = "S_ID = '" .. data_objects[1].id .. "'"
    local strSetAttr = "F_QTY = F_QTY + " .. qty
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "INV_Detail", strUpdateCondition, strSetAttr)
    if nRet ~= 0 then
        return 2, "更新【容器货品明细】信息失败!" .. strRetInfo
    end

    local inv_txn_log_data
    -- 创建 INV_Log
    inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")
    inv_txn_log_data.S_WH_CODE = inv_detail_data.S_WH_CODE
    inv_txn_log_data.S_AREA_CODE = inv_detail_data.S_AREA_CODE
    inv_txn_log_data.S_LOC_CODE = inv_detail_data.S_LOC_CODE
    inv_txn_log_data.S_CNTR_CODE = cntr_code
    inv_txn_log_data.S_LOG_TYPE = "ADJ-IN"
    inv_txn_log_data.C_SYMBOL = "+"
    inv_txn_log_data.S_NOTE = note
    inv_txn_log_data.G_INV_DETAIL_ID = data_objects[1].id
    -- CheckOK
    for m = 1, #INV_TXT_LOG_ATTRS do
        inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = inv_detail_data[INV_TXT_LOG_ATTRS[m]]
    end
    for m = 1, #UDF_ATTRS do
        inv_txn_log_data[UDF_ATTRS[m]] = inv_detail_data[UDF_ATTRS[m]]
    end

    -- MDF BY HAN @20250829
    inv_txn_log_data.F_CUR_QTY = cur_qty + qty
    inv_txn_log_data.F_QTY = qty
    inv_txn_log_data.S_BS_TYPE = bs_type
    inv_txn_log_data.S_BS_NO = bs_no
    inv_txn_log_data.N_BS_ROW_NO = bs_row_no

    nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
    if nRet ~= 0 then
        return 1, "创建【库存交易日志】失败!" .. inv_txn_log_data
    end

    return 0, ""
end

-- @function wms_inv.Add_INV_Detail_By_PAC_Detail
-- 把预分配容器明细（Pre_Alloc_CNTR_Detail）写入 INV_Detail
-- 适用料箱带料格的预分配入库场景；可通过容器类型定义的 merge_attrs 合并数量
-- 写入后处理强制置满的料格
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table ctd 容器类型定义
-- @tparam string cntr_code 容器编码, 必须有值且非空
-- @tparam string pac_no 预分配容器流水号, 必须有值且非空
-- @tparam string loc_code 当前货位编码
-- @treturn number nRet 0=成功, 1=参数错误, 2=操作失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.Add_INV_Detail_By_PAC_Detail(strLuaDEID, ctd, cntr_code, pac_no, loc_code)
    local nRet, strRetInfo

    if pac_no == nil or pac_no == '' then
        return 1, "wms_inv.Add_INV_Detail_By_PAC_Detail 函数中 pac_no 必须有值!"
    end
    if cntr_code == nil or cntr_code == '' then
        return 1, "wms_inv.Add_INV_Detail_By_PAC_Detail 函数中 cntr_code 必须有值!"
    end

    if ctd == nil or type(ctd) ~= "table" then
        return 1, "wms_inv.Add_INV_Detail_By_PAC_Detail 函数中 ctd 必须有值!"
    end

    local loc
    nRet, loc = wms_wh.GetLocInfo(loc_code)
    if nRet ~= 0 then
        return 1, "获取货位'" .. loc_code .. "'信息失败! " .. loc
    end
    local forced_fill_cell = {} -- 强制置满的料格


    -- 查询【Pre_Alloc_CNTR_Detail】
    local strOrder = ""
    local strCondition = "S_PAC_NO = '" .. pac_no .. "'"
    local data_objects
    nRet, data_objects = m3.QueryDataObject(strLuaDEID, "Pre_Alloc_CNTR_Detail", strCondition, strOrder)
    if nRet ~= 0 then
        return 2, "QueryDataObject失败!" .. data_objects
    end
    if data_objects == '' then
        return 0
    end

    local item_detail_data
    local check_is_ok

    -- 缺省值设置
    local default_storer = '' -- 默认货主
    nRet, default_storer = wms_base.Get_sConst2("WMS_Default_Storer")
    if nRet ~= 0 then
        default_storer = ''
    end
    local default_item_state = '' -- 默认货品状态
    nRet, default_item_state = wms_base.Get_sConst2("WMS_Default_ItemState")
    if nRet ~= 0 then
        default_item_state = ''
    end

    for n = 1, #data_objects do
        item_detail_data = m3.KeyValueAttrsToObjAttr(data_objects[n].attrs)
        if item_detail_data == nil then
            return 1, "KeyValueAttrsToObjAttr失败!"
        end
        if item_detail_data.C_FORCED_FILL == 'Y' then
            table.insert(forced_fill_cell, item_detail_data.S_CELL_NO)
        end
        check_is_ok, strRetInfo = item_detail_data_check(item_detail_data, default_storer, default_item_state)
        if not check_is_ok then
            return 1, strRetInfo
        end

        if lua.Get_NumAttrValue(item_detail_data.F_ACT_QTY) > 0 then
            nRet, strRetInfo = wms_inv.Add_Merga_INV_Detail_Qty(strLuaDEID, ctd, cntr_code, item_detail_data.S_CELL_NO, loc,
                                                  item_detail_data, item_detail_data.F_ACT_QTY, "IN")
            if nRet ~= 0 then
                return 2, strRetInfo
            end
        end
    end

    local nCount = #forced_fill_cell
    if nCount == 0 then
        return 0
    end

    -- 设置料格强制置满属性
    local str_cell_no = lua.strArray2string(forced_fill_cell)
    if str_cell_no == '' then
        return 0
    end
    local strCondition, srtSetAttr
    strCondition = " S_CELL_NO IN (" .. str_cell_no .. ") AND S_CNTR_CODE = '" .. cntr_code .. "'"
    srtSetAttr = "C_FORCED_FILL = 'Y', N_EMPTY_FULL = 2"
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Container_Cell", strCondition, srtSetAttr)
    if nRet ~= 0 then
        lua.Warning(strLuaDEID, debug.getinfo(1), "更新【容器箱格】信息失败! condition = " .. strCondition)
        return 2, "更新【容器箱格】信息失败!" .. strRetInfo
    end

    return 0
end

-- @function wms_inv.INV_Detail_Add_AllocQty
-- 对指定 INV_Detail 增加预分配量（F_ALLOC_QTY），生成 INV_Lock_Log（S_LOG_TYPE="allocate"）
-- 条件: F_QTY_VALID > qty 或差值可忽略
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table inv_detail_data 库存量表对象, 需含 S_ID
-- @tparam number qty 分配量, > 0
-- @tparam string bs_type 业务类型
-- @tparam string bs_no 业务单号
-- @treturn number nRet 0=成功, 1=可分配量不足, 2=操作失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.INV_Detail_Add_AllocQty(strLuaDEID, inv_detail_data, qty, bs_type, bs_no)
    local nRet, strRetInfo
    local strCondition
    local inv_detail_id = inv_detail_data.S_ID or ''

    if inv_detail_id == '' then
        return 1, "wms_inv.INV_Detail_Add_AllocQty 函数失败! inv_detail_data 中S_ID为空!"
    end
    if qty <= 0 or qty == nil then
        return 1, "wms_inv.INV_Detail_Add_AllocQty 函数失败! qty 必须大于 0!"
    end

    strCondition = "S_ID = '" .. inv_detail_data.S_ID .. "' AND ( F_QTY_VALID > "..qty.." OR ( "..qty.." - F_QTY_VALID ) <= 0.001)"    
    local strSetAttr = "F_ALLOC_QTY = F_ALLOC_QTY + " .. qty
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "INV_Detail", strCondition, strSetAttr)
    if nRet ~= 0 then
        return 2, "设置【INV_Detail】数量分配量信息失败!" .. strRetInfo
    end

    -- 创建库存锁定日志

    local inv_lock_log_data = m3.AllocObject2(strLuaDEID, "INV_Lock_Log")

    for m = 1, #INV_LOG_BASE_ATTRS do
        inv_lock_log_data[INV_LOG_BASE_ATTRS[m]] = inv_detail_data[INV_LOG_BASE_ATTRS[m]]
    end
    inv_lock_log_data.S_LOG_TYPE = "allocate" -- 订单分配库存量
    inv_lock_log_data.F_QTY = qty
    inv_lock_log_data.S_BS_TYPE = bs_type
    inv_lock_log_data.S_BS_NO = bs_no
    inv_lock_log_data.G_INV_DETAIL_ID = inv_detail_data.S_ID

    nRet, inv_lock_log_data = m3.CreateDataObj2(strLuaDEID, inv_lock_log_data)
    if nRet ~= 0 then
        return 1, "创建【库存锁定日志】失败!" .. inv_lock_log_data
    end
    return 0
end

-- 库存量表中预分配量锁定变成分配量
-- @function wms_inv._INV_Detail_Pre_Alloc_Lock
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table inv_detail_data 库存量表对象, 必须有值
-- @tparam float qty 库存预留数量, 必须有值
-- @tparam string bs_type 来源类型, 必须有值
-- @tparam string bs_no 来源单编码, 必须有值
-- @treturn boolean 操作是否成功
-- @treturn string|nil 错误信息，成功时 nil
function wms_inv._INV_Detail_Pre_Alloc_Lock(strLuaDEID, inv_detail_data, qty, bs_type, bs_no)
    local nRet, strRetInfo
    local strCondition
    local inv_detail_id = inv_detail_data.S_ID or ''

    if inv_detail_id == '' then
        return nil, "wms_inv._INV_Detail_Pre_Alloc_Lock 函数失败! inv_detail_data 中S_ID为空!"
    end
    if qty <= 0 or qty == nil then
        return nil, "wms_inv._INV_Detail_Pre_Alloc_Lock 函数失败! qty 必须大于 0!"
    end

    strCondition = "S_ID = '" .. inv_detail_data.S_ID .. "' AND F_PRE_ALLOC_QTY >= "..qty
    local strSetAttr = "F_ALLOC_QTY = F_ALLOC_QTY + " .. qty..", F_PRE_ALLOC_QTY = F_PRE_ALLOC_QTY - "..qty
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "INV_Detail", strCondition, strSetAttr)
    if nRet ~= 0 then
        return nil, "设置【INV_Detail】数量分配量信息失败!" .. strRetInfo
    end

    -- 创建库存锁定日志

    local inv_lock_log_data = m3.AllocObject2(strLuaDEID, "INV_Lock_Log")

    for m = 1, #INV_LOG_BASE_ATTRS do
        inv_lock_log_data[INV_LOG_BASE_ATTRS[m]] = inv_detail_data[INV_LOG_BASE_ATTRS[m]]
    end
    inv_lock_log_data.S_LOG_TYPE = "allocate" -- 订单分配库存量
    inv_lock_log_data.F_QTY = qty
    inv_lock_log_data.S_BS_TYPE = bs_type
    inv_lock_log_data.S_BS_NO = bs_no
    inv_lock_log_data.G_INV_DETAIL_ID = inv_detail_data.S_ID

    nRet, inv_lock_log_data = m3.CreateDataObj2(strLuaDEID, inv_lock_log_data)
    if nRet ~= 0 then
        return nil, "创建【库存锁定日志】失败!" .. inv_lock_log_data
    end
    return true
end

-- @function create_inv_detail_allocate_out_log
-- 创建出库（分配出库）的 INV_TXN_Log + INV_Lock_Log
-- 日志类型: 交易日志 S_LOG_TYPE="OUT", 锁日志 S_LOG_TYPE="allocate_release"
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table dc_detail 配盘明细数据对象
-- @tparam table inv_detail_data 库存量表对象
-- @tparam number qty 本次扣减的库存数量
-- @tparam number alloc_qty 本次释放的分配量
-- @tparam table ext_parameter 扩展参数, { bs_type, bs_no, bs_row_no, note, out_inv_txn_udf_attrs }
-- @treturn number nRet 0=成功, 非0=失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
local function create_inv_detail_allocate_out_log(strLuaDEID, dc_detail, inv_detail_data, qty, alloc_qty, ext_parameter)
    local nRet
    local note = ''
    local bs_type = ''
    local bs_no = ''
    local bs_row_no = 0
    local out_inv_txn_udf_attrs = {}

    if not lua.isTableEmpty(ext_parameter) then
        note = ext_parameter.note or ''
        bs_type = ext_parameter.bs_type or ''
        bs_no = ext_parameter.bs_no or ''
        bs_row_no = ext_parameter.bs_row_no or 0
        out_inv_txn_udf_attrs = ext_parameter.out_inv_txn_udf_attrs or {}
    end

    -- 创建库存交易日志
    local inv_txn_log_data
    inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")

    -- CheckOK
    for m = 1, #INV_TXT_LOG_ATTRS do
        inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = inv_detail_data[INV_TXT_LOG_ATTRS[m]]
    end
    for m = 1, #UDF_ATTRS do
        inv_txn_log_data[UDF_ATTRS[m]] = inv_detail_data[UDF_ATTRS[m]]
    end
    for _, udf_attr in ipairs(out_inv_txn_udf_attrs) do
        inv_txn_log_data[udf_attr] = dc_detail[udf_attr.lua]
    end

    local cur_qty = lua.Get_NumAttrValue(inv_detail_data.F_QTY)
    inv_txn_log_data.F_QTY = -qty
    inv_txn_log_data.F_CUR_QTY = cur_qty - qty
    inv_txn_log_data.S_NOTE = note
    inv_txn_log_data.S_WH_CODE = inv_detail_data.S_WH_CODE
    inv_txn_log_data.S_AREA_CODE = inv_detail_data.S_AREA_CODE
    inv_txn_log_data.S_LOC_CODE = inv_detail_data.S_LOC_CODE
    inv_txn_log_data.S_LOG_TYPE = "OUT"
    inv_txn_log_data.C_SYMBOL = "-"
    inv_txn_log_data.G_INV_DETAIL_ID = inv_detail_data.id

    -- CheckOK
    inv_txn_log_data.S_BS_TYPE = bs_type
    inv_txn_log_data.S_BS_NO = bs_no
    inv_txn_log_data.N_BS_ROW_NO = bs_row_no

    nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
    if nRet ~= 0 then
        return 1, "创建【库存交易日志】失败!" .. inv_txn_log_data
    end

    -- 创建库存锁定日志
    local inv_lock_log_data = m3.AllocObject2(strLuaDEID, "INV_Lock_Log")

    for m = 1, #INV_LOG_BASE_ATTRS do
        inv_lock_log_data[INV_LOG_BASE_ATTRS[m]] = inv_detail_data[INV_LOG_BASE_ATTRS[m]]
    end
    inv_lock_log_data.S_LOG_TYPE = "allocate_release" -- 订单分配库存量释放
    inv_lock_log_data.F_QTY = -alloc_qty
    inv_lock_log_data.S_BS_TYPE = bs_type
    inv_lock_log_data.S_BS_NO = bs_no
    inv_lock_log_data.G_INV_DETAIL_ID = inv_detail_data.id
    nRet, inv_lock_log_data = m3.CreateDataObj2(strLuaDEID, inv_lock_log_data)
    if nRet ~= 0 then
        return 1, "创建【库存锁定日志】失败!" .. inv_lock_log_data
    end
    return 0
end

-- @function create_inv_detail_move_out_log
-- 创建移库出库的 INV_TXN_Log + INV_Lock_Log
-- 日志类型: 交易日志 S_LOG_TYPE="MOVE-OUT", 锁日志 S_LOG_TYPE="hold_release"
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table inv_detail_data 库存量表对象
-- @tparam number qty 本次扣减的库存数量
-- @tparam number alloc_qty 本次释放的移库占用数量
-- @tparam table ext_parameter 扩展参数, { bs_type, bs_no, bs_row_no, note }
-- @treturn number nRet 0=成功, 非0=失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
local function create_inv_detail_move_out_log(strLuaDEID, inv_detail_data, qty, alloc_qty, ext_parameter)
    local nRet
    local note = ''
    local bs_type = ''
    local bs_no = ''

    if not lua.isTableEmpty(ext_parameter) then
        note = ext_parameter.note or ''
        bs_type = ext_parameter.bs_type or ''
        bs_no = ext_parameter.bs_no or ''
    end

    -- 创建库存交易日志
    local inv_txn_log_data
    inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")

    -- CheckOK
    for m = 1, #INV_TXT_LOG_ATTRS do
        inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = inv_detail_data[INV_TXT_LOG_ATTRS[m]]
    end
    for m = 1, #UDF_ATTRS do
        inv_txn_log_data[UDF_ATTRS[m]] = inv_detail_data[UDF_ATTRS[m]]
    end

    local cur_qty = lua.Get_NumAttrValue(inv_detail_data.F_QTY)
    inv_txn_log_data.F_QTY = -qty
    inv_txn_log_data.F_CUR_QTY = cur_qty - qty
    inv_txn_log_data.S_NOTE = note
    inv_txn_log_data.S_WH_CODE = inv_detail_data.S_WH_CODE
    inv_txn_log_data.S_AREA_CODE = inv_detail_data.S_AREA_CODE
    inv_txn_log_data.S_LOC_CODE = inv_detail_data.S_LOC_CODE
    inv_txn_log_data.S_LOG_TYPE = "MOVE-OUT"
    inv_txn_log_data.C_SYMBOL = "-"
    inv_txn_log_data.G_INV_DETAIL_ID = inv_detail_data.id

    -- CheckOK
    inv_txn_log_data.S_BS_TYPE = bs_type
    inv_txn_log_data.S_BS_NO = bs_no

    nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
    if nRet ~= 0 then
        return 1, "创建【库存交易日志】失败!" .. inv_txn_log_data
    end

    -- 创建库存锁定日志
    local inv_lock_log_data = m3.AllocObject2(strLuaDEID, "INV_Lock_Log")

    for m = 1, #INV_LOG_BASE_ATTRS do
        inv_lock_log_data[INV_LOG_BASE_ATTRS[m]] = inv_detail_data[INV_LOG_BASE_ATTRS[m]]
    end
    inv_lock_log_data.S_LOG_TYPE = "hold_release" -- 移库占用释放
    inv_lock_log_data.F_QTY = -alloc_qty
    inv_lock_log_data.S_BS_TYPE = bs_type
    inv_lock_log_data.S_BS_NO = bs_no
    inv_lock_log_data.G_INV_DETAIL_ID = inv_detail_data.id
    nRet, inv_lock_log_data = m3.CreateDataObj2(strLuaDEID, inv_lock_log_data)
    if nRet ~= 0 then
        return 1, "创建【库存锁定日志】失败!" .. inv_lock_log_data
    end
    return 0
end

-- @function wms_inv.INV_Detail_Out
-- 分拣出库扣减库存量、分配量
-- 如果出库量少于计划出库量说明出库异常，创建出库业务异常记录（INV_Transfer_Anomaly）
-- 并把该条 INV_Detail 标记为异常
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table dc_detail 配盘明细, { inv_detail_id, acc_p_qty, qty:分配量, ... }
-- @tparam table ext_parameter 扩展参数, { bs_type, bs_no, bs_row_no, note, out_inv_txn_udf_attrs }
-- @treturn number nRet 0=成功, 非0=失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.INV_Detail_Out(strLuaDEID, dc_detail, ext_parameter)
    local nRet, strRetInfo, strCondition
    local inv_detail_id = dc_detail.inv_detail_id
    local qty = dc_detail.acc_p_qty
    local alloc_qty = dc_detail.qty

    if inv_detail_id == '' or inv_detail_id == nil then
        return 2, "wms_inv.Allocate_Qty_Out 函数中 参数 inv_detail_id 不能为空!"
    end

    local inv_detail_data
    nRet, inv_detail_data = m3.GetDataObject2(strLuaDEID, "INV_Detail", inv_detail_id)
    if nRet ~= 0 then
        return 2, inv_detail_data
    end

    if ext_parameter == nil then 
        ext_parameter = {} 
    end

    strCondition = "S_ID = '" .. inv_detail_id .. "'"
    local strSetAttr = "F_QTY = F_QTY-" .. qty .. ", F_ALLOC_QTY = F_ALLOC_QTY-" .. alloc_qty
    if alloc_qty > qty then
        if dc_detail.anomaly <= 0 then
            return 2, "没有输入异常原因!"
        end 
        strSetAttr = strSetAttr .. ", S_ITEM_STATE = 'ERROR'"
        
        -- 因为输入的 dc_detail 是 lua 变量的json，需要转换成 数据类字段构成的json
        local str_json
        nRet, str_json = mobox.luaJsonToObjJson( "Distribution_CNTR_Detail", lua.table2str(dc_detail) )
        if nRet ~= 0 then
            return 2, "luaJsonToObjJson数据转换格式错!"..str_json
        end
       
        local success
        local dc_detail_data
        success, dc_detail_data = pcall( json.decode, str_json )
        if success == false then 
            return 2, "luaJsonToObjJson 返回结果是非法的JSON格式!"
        end
    
        -- 创建 INV_Transfer_Anomaly
        local inv_transfer_anomaly
        inv_transfer_anomaly = m3.AllocObject2(strLuaDEID, "INV_Transfer_Anomaly")

        for m = 1, #INV_TRANS_ANOMALY_ATTRS do
            inv_transfer_anomaly[INV_TRANS_ANOMALY_ATTRS[m]] = dc_detail_data[INV_TRANS_ANOMALY_ATTRS[m]]
        end

        inv_transfer_anomaly.F_QTY = alloc_qty - qty
        inv_transfer_anomaly.S_TRANSFER_TYPE = 'OUT'
        local wave_no = dc_detail_data.S_WAVE_NO or ''
        if wave_no ~= '' then
            -- 说明是出库波次产生的差异
            inv_transfer_anomaly.S_WAVE_NO = wave_no
            inv_transfer_anomaly.N_WAVE_ROW_NO = dc_detail_data.N_WAVE_ROW_NO
        end
        inv_transfer_anomaly.S_BS_TYPE = dc_detail_data.S_BS_TYPE
        inv_transfer_anomaly.S_BS_NO = dc_detail_data.S_BS_NO
        inv_transfer_anomaly.N_BS_ROW_NO = dc_detail_data.N_BS_ROW_NO            

        inv_transfer_anomaly.G_INV_DETAIL_ID = inv_detail_data.id
        inv_transfer_anomaly.S_DC_NO = dc_detail.dc_no
        inv_transfer_anomaly.N_ANOMALY_TYPE = dc_detail.anomaly
        inv_transfer_anomaly.S_ANOMALY_TYPE = ANOMALY_TYPE_CN[dc_detail.anomaly] or ''
        nRet, inv_transfer_anomaly = m3.CreateDataObj2(strLuaDEID, inv_transfer_anomaly)
        if nRet ~= 0 then
            return 2, "创建【库内移动业务异常记录】失败!" .. inv_transfer_anomaly
        end
    end
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "INV_Detail", strCondition, strSetAttr)
    if nRet ~= 0 then
        return 2, "设置【INV_Detail】数量分配量信息失败!" .. strRetInfo
    end

    nRet, strRetInfo = create_inv_detail_allocate_out_log(strLuaDEID, dc_detail, inv_detail_data, qty, alloc_qty,
        ext_parameter)
    if nRet ~= 0 then
        return 2, strRetInfo
    end
    return 0
end

-- @function wms_inv.INV_Detail_SplitOut
-- 根据输入的 strCondition 扣减 INV_Detail 中某数量和分配量, 会有多条 INV_Detail 需要分批
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table dc_detail 配盘明细数据对象
-- @tparam string strCondition 查询条件（WHERE 子句）
-- @tparam string strOrder 排序
-- @tparam number qty 实际出库数量
-- @tparam number alloc_qty 分配量
-- @tparam table ext_parameter 扩展参数, { bs_type, bs_no, bs_row_no, note, out_inv_txn_udf_attrs }
-- @treturn number nRet 0=成功, 非0=失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.INV_Detail_SplitOut(strLuaDEID, dc_detail, strCondition, strOrder, qty, alloc_qty, ext_parameter)
    local nRet, strRetInfo

    if dc_detail == '' or dc_detail == nil then
        return 2, "函数 wms_inv.INV_Detail_SplitOut 里 dc_detail 不能为空!"
    end

    if strCondition == '' or strCondition == nil then
        return 2, "函数 wms_inv.INV_Detail_SplitOut 里strCondition 不能为空!"
    end
    if strOrder == nil then strOrder = '' end

    local inv_detail_objs
    nRet, inv_detail_objs = m3.QueryDataObject(strLuaDEID, "INV_Detail", strCondition, strOrder)
    if nRet ~= 0 then
        return 2, "查询 INV_Detail 失败! " .. inv_detail_objs
    end
    if inv_detail_objs == '' then
        return 0
    end

    local inv_detail_data
    local strSetAttr, inv_detail_qty, inv_detail_alloc_qty
    local strSetQtyAttr, strSetAllocQtyAttr
    local Q, AQ

    for n = 1, #inv_detail_objs do
        inv_detail_data = m3.KeyValueAttrsToObjAttr(inv_detail_objs[n].attrs)
        if inv_detail_data == nil then
            return 2, "KeyValueAttrsToObjAttr 数据转换失败!"
        end
        inv_detail_data.id = lua.trim_guid_str(inv_detail_objs[n].id)
        inv_detail_qty = lua.Get_NumAttrValue(inv_detail_data.F_QTY)
        inv_detail_alloc_qty = lua.Get_NumAttrValue(inv_detail_data.F_ALLOC_QTY)

        strSetAttr = ''
        Q = 0
        AQ = 0
        if qty > 0 then
            if inv_detail_qty < qty then
                strSetQtyAttr = "F_QTY = F_QTY-" .. inv_detail_qty
                qty = qty - inv_detail_qty
                Q = inv_detail_qty
            else
                strSetQtyAttr = "F_QTY = F_QTY-" .. qty
                Q = qty
                qty = 0
            end
            strSetAttr = strSetQtyAttr
        end

        if alloc_qty > 0 then
            if inv_detail_alloc_qty < alloc_qty then
                strSetAllocQtyAttr = "F_ALLOC_QTY = F_ALLOC_QTY-" .. inv_detail_alloc_qty
                AQ = inv_detail_alloc_qty
                alloc_qty = alloc_qty - inv_detail_alloc_qty
            else
                strSetAllocQtyAttr = "F_ALLOC_QTY = F_ALLOC_QTY-" .. alloc_qty
                AQ = alloc_qty
                alloc_qty = 0
            end
            if strSetAttr ~= '' then strSetAttr = strSetAttr .. "," end
            strSetAttr = strSetAttr .. strSetAllocQtyAttr
        end

        if strSetAttr == '' then break end

        strCondition = "S_ID = '" .. inv_detail_data.id .. "'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "INV_Detail", strCondition, strSetAttr)
        if nRet ~= 0 then
            return 2, "设置【INV_Detail】数量分配量信息失败!" .. strRetInfo
        end
        -- 创建日志
        nRet, strRetInfo = create_inv_detail_allocate_out_log(strLuaDEID, dc_detail, inv_detail_data, Q, AQ,
            ext_parameter)
        if nRet ~= 0 then
            return 2, strRetInfo
        end
    end
    return 0
end

-- @function wms_inv.DC_Detail_Cancel
-- 配盘明细取消：恢复 INV_Detail 中已分配的 F_ALLOC_QTY，生成 INV_Lock_Log（allocate_cancel）
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table dc_detail_data 配盘明细数据对象, 需含 G_INV_DETAIL_ID, F_QTY
-- @tparam string str_note 备注
-- @treturn number nRet 0=成功, 非0=失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.DC_Detail_Cancel( strLuaDEID, dc_detail_data, str_note )
    local inv_detail_id = dc_detail_data.G_INV_DETAIL_ID or ''
    local qty = lua.Get_NumAttrValue(dc_detail_data.F_QTY)
    if qty < 0 then
        return 1, "配盘号='" .. dc_detail_data.S_DC_NO .. "'的配盘明细中 F_QTY 有负数!"
    end
    if str_note == nil then str_note = '' end

    local strSetAttr, strCondition, nRet, strRetInfo    

    -- 下面这段代码在 2026-4-26 恢复，原来被注释
    if inv_detail_id ~= '' then
        strSetAttr = "F_ALLOC_QTY = F_ALLOC_QTY-" .. qty
        strCondition = "S_ID = '" .. inv_detail_id .. "' AND F_ALLOC_QTY >= "..qty
        nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "INV_Detail", strCondition, strSetAttr)
        if nRet ~= 0 then
            return 2, "设置【INV_Detail】数量分配量信息失败!" .. strRetInfo
        end
        local inv_detail_data
        nRet, inv_detail_data = m3.GetDataObject2(strLuaDEID, "INV_Detail", inv_detail_id)
        if nRet ~= 0 then
            return 2, inv_detail_data
        end

        -- 创建库存锁定日志
        local inv_lock_log_data = m3.AllocObject2(strLuaDEID, "INV_Lock_Log")
        for m = 1, #INV_LOG_BASE_ATTRS do
            inv_lock_log_data[INV_LOG_BASE_ATTRS[m]] = inv_detail_data[INV_LOG_BASE_ATTRS[m]]
        end

        inv_lock_log_data.S_LOG_TYPE = "allocate_cancel" -- 订单分配库存量取消
        inv_lock_log_data.F_QTY = qty
        inv_lock_log_data.S_NOTE = str_note
        inv_lock_log_data.G_INV_DETAIL_ID = inv_detail_id
        nRet, inv_lock_log_data = m3.CreateDataObj2(strLuaDEID, inv_lock_log_data)
        if nRet ~= 0 then
            return 2, "创建【库存锁定日志】失败!" .. inv_lock_log_data
        end
    end

    -- 更新累计配盘数量
    local bs_type = dc_detail_data.S_BS_TYPE or ''
    local bs_no = dc_detail_data.S_BS_NO or ''
    local wave_no = dc_detail_data.S_WAVE_NO or ''
    local bs_row_no = lua.Get_NumAttrValue(dc_detail_data.N_BS_ROW_NO)
    local strUpdateSql
    if bs_no ~= '' and bs_row_no > 0 then
        if bs_type == "Outbound_Order" then
            strCondition = "S_OO_NO = '" .. bs_no .. "' AND N_ROW_NO = " .. bs_row_no
            strUpdateSql = "F_ACC_D_QTY = F_ACC_D_QTY - " .. qty
            nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Outbound_Detail", strCondition,
                                                                strUpdateSql)
            if nRet ~= 0 then
                return 2, "更新【Outbound_Detail】信息失败!" .. strRetInfo
            end
            if wave_no ~= '' then
                local wave_row_no = lua.Get_NumAttrValue(dc_detail_data.N_WAVE_ROW_NO)
                if wave_row_no > 0 then
                    strCondition = "S_WAVE_NO = '" .. wave_no .. "' AND N_ROW_NO = " .. wave_row_no
                    strUpdateSql = "F_ACC_D_QTY = F_ACC_D_QTY - " .. qty
                    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "OW_Detail", strCondition, strUpdateSql)
                    if nRet ~= 0 then
                        return 2, "更新【OW_Detail】信息失败!" .. strRetInfo
                    end
                end
            end

        elseif bs_type == "Outbound_Wave" then
            strCondition = "S_WAVE_NO = '" .. bs_no .. "' AND N_ROW_NO = " .. bs_row_no
            strUpdateSql = "F_ACC_D_QTY = F_ACC_D_QTY - " .. qty
            nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "OW_Detail", strCondition, strUpdateSql)
            if nRet ~= 0 then
                return 2, "更新【OW_Detail】信息失败!" .. strRetInfo
            end
        end
    end   
    return 0
end
-- @function wms_inv.Distribution_CNTR_Cancel
-- 分拣出库的配盘取消处理程序
-- INV_Detail 减去配盘相关的明细中的分配量, INV_Lock_Log 新增记录（allocate_cancel）
-- 来源业务中的明细表中 F_ACC_D_QTY 累计配货数量也需要减去
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string dc_no 配盘对象编码, 必须有值且非空
-- @treturn number nRet 0=成功, 1=参数错误, 2=操作失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.Distribution_CNTR_Cancel(strLuaDEID, dc_no)
    local nRet, strRetInfo

    if lua.StrIsEmpty(dc_no) then
        return 1, "wms_inv.Distribution_CNTR_Cancel 函数中的输入参数 dc_no 必须有值，不能为空!"
    end

    -- 获取【配盘明细】
    local data_objects
    local strUpdateSql
    local strCondition = "S_DC_NO = '" .. dc_no .. "'"
    nRet, data_objects = m3.QueryDataObject(strLuaDEID, "Distribution_CNTR_Detail", strCondition)
    if nRet ~= 0 then
        return 2, "QueryDataObject失败!" .. data_objects
    end
    if data_objects == '' then
        return 0
    end

    local dc_detail_data
    for _, data in ipairs(data_objects) do
        dc_detail_data = m3.KeyValueAttrsToObjAttr(data.attrs)
        if dc_detail_data == nil then
            return 2, "配盘号='" .. dc_no .. "'的配盘明细中 m3.KeyValueAttrsToObjAttr 失败!"
        end
        local str_note = "出库单'" .. dc_detail_data.S_BS_NO .. "'取消"
        nRet, strRetInfo = wms_inv.DC_Detail_Cancel( strLuaDEID, dc_detail_data, str_note )
        if nRet ~= 0 then
            return nRet, strRetInfo
        end
    end
    -- Distribution_CNTR 的状态改为 取消
    strCondition = "S_DC_NO = '" .. dc_no .. "'"
    strUpdateSql = "N_B_STATE = " .. DIST_CNTR_STATE.Cancel
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Distribution_CNTR", strCondition, strUpdateSql)
    if nRet ~= 0 then
        return 2, "更新 Distribution_CNTR 状态失败!" .. strRetInfo
    end
    -- Distribution_CNTR_Detail 的状态改为 取消
    strCondition = "S_DC_NO = '" .. dc_no .. "'"
    strUpdateSql = "N_B_STATE = " .. DC_DETAIL_STATE.Cancel
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Distribution_CNTR_Detail", strCondition, strUpdateSql)
    if nRet ~= 0 then
        return 2, "更新 Distribution_CNTR_Detail 状态失败!" .. strRetInfo
    end
    return 0
end

-- @function wms_inv.Tally_Detail_Process
-- Tally_Detail 理货任务完成后对库存量的处理
-- 源端扣减 F_QTY 和 F_QTY_MOVE, 生成 MOVE-OUT 日志; 目标端累加 F_QTY, 生成 MOVE-IN 日志
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table ctd 容器类型定义
-- @tparam table tally_detail_data 理货明细数据对象, 需含 G_INV_DETAIL_ID, F_QTY, S_TO_CNTR_CODE, S_TO_CELL_NO, S_IWP_NO 等
-- @treturn number nRet 0=成功, 非0=失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.Tally_Detail_Process(strLuaDEID, ctd, tally_detail_data)
    local nRet, strRetInfo, strCondition
    local inv_detail_id = tally_detail_data.G_INV_DETAIL_ID
    local qty = lua.Get_NumAttrValue(tally_detail_data.F_QTY)

    if inv_detail_id == '' or inv_detail_id == nil then
        return 2, "wms_inv.Tally_Detail_Process 函数中 参数 inv_detail_id 不能为空!"
    end

    local inv_detail_data
    nRet, inv_detail_data = m3.GetDataObject2(strLuaDEID, "INV_Detail", inv_detail_id)
    if nRet ~= 0 then
        return 2, inv_detail_data
    end

    strCondition = "S_ID = '" .. inv_detail_id .. "' AND F_QTY >= "..qty.." AND F_QTY_MOVE >= "..qty
    local strSetAttr = "F_QTY = F_QTY - " .. qty .. ", F_QTY_MOVE = F_QTY_MOVE - " .. qty
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "INV_Detail", strCondition, strSetAttr)
    if nRet ~= 0 then
        return 2, "设置【INV_Detail】数量信息失败!" .. strRetInfo
    end
    if tonumber( strRetInfo ) ~= 1 then
        return 2, "设置【INV_Detail】数量信息失败! 库存数量不足!"
    end

    local loc
    nRet, loc = wms_wh.GetLocInfo(tally_detail_data.S_TO_LOC_CODE)
    if nRet ~= 0 then
        return 2, "获取货位'" .. tally_detail_data.S_TO_LOC_CODE .. "'信息失败! " .. loc
    end

    local ext_parameter = { bs_type = "IW_Process", bs_no = tally_detail_data.S_IWP_NO }
    nRet, strRetInfo = create_inv_detail_move_out_log(strLuaDEID, inv_detail_data, qty, qty, ext_parameter)
    if nRet ~= 0 then
        return 2, " create_inv_detail_move_out_log 失败! " .. strRetInfo
    end

    -- 加下面的属性是为了在生成库存交易日志里设置 业务来源属性
    tally_detail_data.S_BS_TYPE = "IW_Process"
    tally_detail_data.S_BS_NO = tally_detail_data.S_IWP_NO

    nRet, strRetInfo = wms_inv.Add_Merga_INV_Detail_Qty(strLuaDEID, ctd, tally_detail_data.S_TO_CNTR_CODE,
                                                        tally_detail_data.S_TO_CELL_NO,
                                                        loc, tally_detail_data, tally_detail_data.F_QTY, "MOVE-IN")
    if nRet ~= 0 then
        return 2, strRetInfo
    end
    return 0
end

-- 库存量加移库数量（F_QTY_MOVE），生成 INV_Lock_Log（S_LOG_TYPE="hold"）
-- @function wms_inv.INV_Detail_Add_MoveQty
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table inv_detail_data 需要移动的库存量记录对象, 需含 S_ID
-- @tparam number qty 移库数量, > 0
-- @tparam string bs_type 产生移库的业务类型
-- @tparam string bs_no 业务单号
-- @treturn number nRet 0=成功, 1=可移库量不足, 2=操作失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.INV_Detail_Add_MoveQty(strLuaDEID, inv_detail_data, qty, bs_type, bs_no)
    local nRet, strRetInfo
    local strCondition
    local inv_detail_id = inv_detail_data.S_ID or ''

    if inv_detail_id == '' then
        return 1, "wms_inv.INV_Detail_Add_MoveQty 函数失败! inv_detail_data 中 S_ID 为空!"
    end
    if qty <= 0 or qty == nil then
        return 1, "wms_inv.INV_Detail_Add_MoveQty 函数失败! qty 必须大于 0!"
    end

    strCondition = "S_ID = '" .. inv_detail_id .. "'"
    local strSetAttr = "F_QTY_MOVE = F_QTY_MOVE+" .. qty
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "INV_Detail", strCondition, strSetAttr)
    if nRet ~= 0 then
        return 2, "设置【INV_Detail】数量分配量信息失败!" .. strRetInfo
    end

    -- 创建库存锁定日志
    local inv_lock_log_data = m3.AllocObject2(strLuaDEID, "INV_Lock_Log")

    for m = 1, #INV_LOG_BASE_ATTRS do
        inv_lock_log_data[INV_LOG_BASE_ATTRS[m]] = inv_detail_data[INV_LOG_BASE_ATTRS[m]]
    end
    inv_lock_log_data.S_LOG_TYPE = "hold" -- 移库占用
    inv_lock_log_data.F_QTY = qty
    inv_lock_log_data.S_BS_TYPE = bs_type
    inv_lock_log_data.S_BS_NO = bs_no
    inv_lock_log_data.G_INV_DETAIL_ID = inv_detail_id

    nRet, inv_lock_log_data = m3.CreateDataObj2(strLuaDEID, inv_lock_log_data)
    if nRet ~= 0 then
        return 1, "创建【库存锁定日志】失败!" .. inv_lock_log_data
    end
    return 0
end

-- @function wms_inv.INV_Detail_Add_Qty_By_ADJ
-- 库存量加数量（一般用于盘点数量调整），生成 INV_TXN_Log（S_LOG_TYPE="ADJ-IN"）
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table inv_detail_data 需要调整的库存量记录对象, 需含 .id
-- @tparam number qty 调整数量, > 0
-- @tparam string bs_type 产生调整的业务类型
-- @tparam string bs_no 业务单号
-- @treturn number nRet 0=成功, 非0=失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.INV_Detail_Add_Qty_By_ADJ(strLuaDEID, inv_detail_data, qty, bs_type, bs_no)
    local nRet, strRetInfo
    local strCondition

    if inv_detail_data == nil then
        return 1, "wms_inv.INV_Detail_Add_Qty_By_ADJ 函数失败! inv_detail_data 必须有值!"
    end
    
    local inv_detail_id = inv_detail_data.id or ''
    if inv_detail_id == '' then
        return 1, "wms_inv.INV_Detail_Add_Qty_By_ADJ 函数失败! inv_detail_data.id 必须有值!"
    end
    if qty <= 0 or qty == nil then
        return 1, "wms_inv.INV_Detail_Add_Qty_By_ADJ 函数失败! qty 必须大于 0!"
    end

    strCondition = "S_ID = '" .. inv_detail_id .. "'"
    local strSetAttr = "F_QTY = F_QTY + " .. qty
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "INV_Detail", strCondition, strSetAttr)
    if nRet ~= 0 then
        return 2, "设置【INV_Detail】数量分配量信息失败!" .. strRetInfo
    end

    -- 创建 INV_Log
    local inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")
    inv_txn_log_data.S_WH_CODE = inv_detail_data.S_WH_CODE
    inv_txn_log_data.S_AREA_CODE = inv_detail_data.S_AREA_CODE
    inv_txn_log_data.S_LOC_CODE = inv_detail_data.S_LOC_CODE
    inv_txn_log_data.S_CNTR_CODE = inv_detail_data.S_CNTR_CODE
    inv_txn_log_data.S_LOG_TYPE = "ADJ-IN"
    inv_txn_log_data.C_SYMBOL = "+"
    inv_txn_log_data.G_INV_DETAIL_ID = inv_detail_id

    for m = 1, #INV_TXT_LOG_ATTRS do
        inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = inv_detail_data[INV_TXT_LOG_ATTRS[m]]
    end
    for m = 1, #UDF_ATTRS do
        inv_txn_log_data[UDF_ATTRS[m]] = inv_detail_data[UDF_ATTRS[m]]
    end
    local cur_qty = lua.Get_NumAttrValue( inv_detail_data.F_QTY )
    inv_txn_log_data.F_CUR_QTY = qty + cur_qty
    inv_txn_log_data.F_QTY = qty
    inv_txn_log_data.S_BS_TYPE = bs_type
    inv_txn_log_data.S_BS_NO = bs_no
    nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
    if nRet ~= 0 then
        return 1, "创建【库存交易日志】失败!" .. inv_txn_log_data
    end
    return 0
end

-- @function wms_inv.INV_Detail_Reduce_Qty_By_ADJ
-- 库存量减数量（一般用于盘点数量调整），生成 INV_TXN_Log（S_LOG_TYPE="ADJ-OUT"）
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table inv_detail_data 需要调整的库存量记录对象, 需含 .id
-- @tparam number qty 调整数量, > 0
-- @tparam string bs_type 产生调整的业务类型
-- @tparam string bs_no 业务单号
-- @treturn number nRet 0=成功, 非0=失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.INV_Detail_Reduce_Qty_By_ADJ(strLuaDEID, inv_detail_data, qty, bs_type, bs_no)
    local nRet, strRetInfo
    local strCondition

    if inv_detail_data == nil then
        return 1, "wms_inv.INV_Detail_Reduce_Qty_By_ADJ 函数失败! inv_detail_data 必须有值!"
    end
    
    local inv_detail_id = inv_detail_data.id or ''
    if inv_detail_id == '' then
        return 1, "wms_inv.INV_Detail_Reduce_Qty_By_ADJ 函数失败! inv_detail_data.id 必须有值!"
    end
    if qty <= 0 or qty == nil then
        return 1, "wms_inv.INV_Detail_Reduce_Qty_By_ADJ 函数失败! qty 必须大于 0!"
    end

    strCondition = "S_ID = '" .. inv_detail_id .. "' AND F_QTY >= " .. qty
    local strSetAttr = "F_QTY = F_QTY - " .. qty
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "INV_Detail", strCondition, strSetAttr)
    if nRet ~= 0 then
        return 2, "设置【INV_Detail】数量分配量信息失败!" .. strRetInfo
    end

    -- 创建 INV_TXN_Log
    local inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")
    inv_txn_log_data.S_WH_CODE = inv_detail_data.S_WH_CODE
    inv_txn_log_data.S_AREA_CODE = inv_detail_data.S_AREA_CODE
    inv_txn_log_data.S_LOC_CODE = inv_detail_data.S_LOC_CODE
    inv_txn_log_data.S_CNTR_CODE = inv_detail_data.S_CNTR_CODE
    inv_txn_log_data.S_LOG_TYPE = "ADJ-OUT"
    inv_txn_log_data.C_SYMBOL = "-"
    inv_txn_log_data.G_INV_DETAIL_ID = inv_detail_id

    for m = 1, #INV_TXT_LOG_ATTRS do
        inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = inv_detail_data[INV_TXT_LOG_ATTRS[m]]
    end
    for m = 1, #UDF_ATTRS do
        inv_txn_log_data[UDF_ATTRS[m]] = inv_detail_data[UDF_ATTRS[m]]
    end
    local cur_qty = lua.Get_NumAttrValue( inv_detail_data.F_QTY )
    inv_txn_log_data.F_CUR_QTY = cur_qty - qty
    inv_txn_log_data.F_QTY = qty
    inv_txn_log_data.S_BS_TYPE = bs_type
    inv_txn_log_data.S_BS_NO = bs_no
    nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
    if nRet ~= 0 then
        return 1, "创建【库存交易日志】失败!" .. inv_txn_log_data
    end
    return 0
end

-- 强制清空(删除)指定容器里的货品（库存量），生成 INV_TXN_Log
-- @function wms_inv.INV_Detail_Delete
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值且非空
-- @tparam string str_note 备注
-- @treturn number nRet 0=成功, 1=参数错误, 2=操作失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.INV_Detail_Delete(strLuaDEID, cntr_code, str_note)
    local nRet, strRetInfo

    if cntr_code == nil or cntr_code == '' then
        return 1, "INV_Detail_Delete 函数输入参数错误 cntr_code 不能为空!"
    end

    -- 查询【INV_Detail】
    local strOrder = ""
    local strCondition = "S_CNTR_CODE = '" .. cntr_code .. "'"
    local data_objects
    nRet, data_objects = m3.QueryDataObject(strLuaDEID, "INV_Detail", strCondition, strOrder)
    if nRet ~= 0 then 
        return 2, "QueryDataObject失败!" .. data_objects 
    end
    if data_objects == '' then
        return 0
    end

    local udf_attr_count
    local inv_detail_data
    local inv_txn_log_data

    udf_attr_count = #UDF_ATTRS
    for n = 1, #data_objects do
        inv_detail_data = m3.KeyValueAttrsToObjAttr(data_objects[n].attrs)
        if inv_detail_data == nil then
            return 1, "KeyValueAttrsToObjAttr 函数失败!"
        end
        -- 创建库存交易日志
        inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")
        if inv_txn_log_data == nil then
            return 2, "AllocObject2 失败!"
        end      
        inv_txn_log_data.S_WH_CODE = inv_detail_data.S_WH_CODE
        inv_txn_log_data.S_AREA_CODE = inv_detail_data.S_AREA_CODE
        inv_txn_log_data.S_LOC_CODE = inv_detail_data.S_LOC_CODE
        inv_txn_log_data.S_CNTR_CODE = cntr_code
        inv_txn_log_data.S_LOG_TYPE = "Delete"
        inv_txn_log_data.C_SYMBOL = "-"
        inv_txn_log_data.S_NOTE = str_note
        inv_txn_log_data.G_INV_DETAIL_ID = data_objects[n].id

        --CheckOK
        for m = 1, #INV_TXT_LOG_ATTRS do
            inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = inv_detail_data[INV_TXT_LOG_ATTRS[m]]
        end
        for m = 1, udf_attr_count do
            inv_txn_log_data[UDF_ATTRS[m]] = inv_detail_data[UDF_ATTRS[m]]
        end

        inv_txn_log_data.F_QTY = -lua.Get_NumAttrValue(inv_txn_log_data.F_QTY)
        inv_txn_log_data.S_BS_TYPE = "Force Delete"
        inv_txn_log_data.S_BS_NO = ""
        inv_txn_log_data.N_BS_ROW_NO = 0
        inv_txn_log_data.F_CUR_QTY = 0

        nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
        if nRet ~= 0 then
            return 1, "创建【库存交易日志】失败!" .. inv_txn_log_data
        end
    end
    -- 删除 INV_Detail
    strCondition = "S_CNTR_CODE = '" .. cntr_code .. "'"
    nRet, strRetInfo = mobox.dbdeleteData(strLuaDEID, "INV_Detail", strCondition)
    if nRet ~= 0 then
        return 2, "删除【INV_Detail】失败!" .. strRetInfo
    end

    return 0
end

-- 判断容器里是否有库存量
-- @function wms_inv.INV_Detail_Exist
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值boolean
-- @tparam string cntr_code 容器编码, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn boolean exist 成功时返回是否存在，失败时返回错误信息
function wms_inv.INV_Detail_Exist(strLuaDEID, cntr_code)
    local nRet, strRetInfo

    if cntr_code == nil or cntr_code == ''  then
        return 1, "INV_Detail_Exist 函数输入参数错误 cntr_code 不能为空!"
    end
    
    local strCondition = "S_CNTR_CODE = '" .. cntr_code .. "'"
    nRet, strRetInfo = mobox.existThisData(strLuaDEID, "INV_Detail", strCondition)
    if nRet ~= 0 then 
        return 2, "在检查 INV_Detail 否存在时失败! " .. strRetInfo
    end
    if strRetInfo == 'yes' then
        return 0, true
    end
    return 0, false
end

-- @function wms_inv.INV_Detail_Hold
-- 冻结库存量，生成 INV_TXN_Log（S_LOG_TYPE="HOLD"）
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table inv_detail_data 需要调整的库存量记录对象, 需含 .id
-- @tparam number qty 调整数量, > 0
-- @tparam string bs_type 产生调整的业务类型
-- @tparam string bs_no 业务单号
-- @treturn number nRet 0=成功, 非0=失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.INV_Detail_Hold(strLuaDEID, inv_detail_data, qty, bs_type, bs_no)
    local nRet, strRetInfo
    local strCondition

    if inv_detail_data == nil then
        return 1, "wms_inv.INV_Detail_Add_Qty_By_ADJ 函数失败! inv_detail_data 必须有值!"
    end
    
    local inv_detail_id = inv_detail_data.id or ''
    if inv_detail_id == '' then
        return 1, "wms_inv.INV_Detail_Add_Qty_By_ADJ 函数失败! inv_detail_data.id 必须有值!"
    end
    if qty <= 0 or qty == nil then
        return 1, "wms_inv.INV_Detail_Add_Qty_By_ADJ 函数失败! qty 必须大于 0!"
    end

    strCondition = "S_ID = '" .. inv_detail_id .. "'"
    local strSetAttr = "F_QTY_FREEZE = F_QTY_FREEZE + " .. qty
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "INV_Detail", strCondition, strSetAttr)
    if nRet ~= 0 then
        return 2, "设置【INV_Detail】数量分配量信息失败!" .. strRetInfo
    end

    -- 创建 INV_Log
    local inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")
    inv_txn_log_data.S_WH_CODE = inv_detail_data.S_WH_CODE
    inv_txn_log_data.S_AREA_CODE = inv_detail_data.S_AREA_CODE
    inv_txn_log_data.S_LOC_CODE = inv_detail_data.S_LOC_CODE
    inv_txn_log_data.S_CNTR_CODE = inv_detail_data.S_CNTR_CODE
    inv_txn_log_data.S_LOG_TYPE = "HOLD"
    inv_txn_log_data.C_SYMBOL = "-"
    inv_txn_log_data.G_INV_DETAIL_ID = inv_detail_id

    for m = 1, #INV_TXT_LOG_ATTRS do
        inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = inv_detail_data[INV_TXT_LOG_ATTRS[m]]
    end
    for m = 1, #UDF_ATTRS do
        inv_txn_log_data[UDF_ATTRS[m]] = inv_detail_data[UDF_ATTRS[m]]
    end
    local cur_qty = lua.Get_NumAttrValue( inv_detail_data.F_QTY )
    inv_txn_log_data.F_CUR_QTY = qty + cur_qty
    inv_txn_log_data.F_QTY = qty
    inv_txn_log_data.S_BS_TYPE = bs_type
    inv_txn_log_data.S_BS_NO = bs_no
    nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
    if nRet ~= 0 then
        return 1, "创建【库存交易日志】失败!" .. inv_txn_log_data
    end
    return 0
end

-- @function wms_inv.INV_Detail_UnHold
-- 释放冻结库存，生成 INV_TXN_Log（S_LOG_TYPE="UN-HOLD"）
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table inv_detail_data 需要调整的库存量记录对象, 需含 .id
-- @tparam number qty 调整数量, > 0
-- @tparam string bs_type 产生调整的业务类型
-- @tparam string bs_no 业务单号
-- @treturn number nRet 0=成功, 非0=失败
-- @treturn string strRetInfo 成功时为空串, 失败时为错误信息
function wms_inv.INV_Detail_UnHold(strLuaDEID, inv_detail_data, qty, bs_type, bs_no)
    local nRet, strRetInfo
    local strCondition

    if inv_detail_data == nil then
        return 1, "wms_inv.INV_Detail_Reduce_Qty_By_ADJ 函数失败! inv_detail_data 必须有值!"
    end
    
    local inv_detail_id = inv_detail_data.id or ''
    if inv_detail_id == '' then
        return 1, "wms_inv.INV_Detail_Reduce_Qty_By_ADJ 函数失败! inv_detail_data.id 必须有值!"
    end
    if qty <= 0 or qty == nil then
        return 1, "wms_inv.INV_Detail_Reduce_Qty_By_ADJ 函数失败! qty 必须大于 0!"
    end

    strCondition = "S_ID = '" .. inv_detail_id .. "' AND F_QTY_FREEZE >= " .. qty
    local strSetAttr = "F_QTY_FREEZE = F_QTY_FREEZE - " .. qty
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "INV_Detail", strCondition, strSetAttr)
    if nRet ~= 0 then
        return 2, "设置【INV_Detail】数量分配量信息失败!" .. strRetInfo
    end

    -- 创建 INV_TXN_Log
    local inv_txn_log_data = m3.AllocObject2(strLuaDEID, "INV_TXN_Log")
    inv_txn_log_data.S_WH_CODE = inv_detail_data.S_WH_CODE
    inv_txn_log_data.S_AREA_CODE = inv_detail_data.S_AREA_CODE
    inv_txn_log_data.S_LOC_CODE = inv_detail_data.S_LOC_CODE
    inv_txn_log_data.S_CNTR_CODE = inv_detail_data.S_CNTR_CODE
    inv_txn_log_data.S_LOG_TYPE = "UN-HOLD"
    inv_txn_log_data.C_SYMBOL = "+"
    inv_txn_log_data.G_INV_DETAIL_ID = inv_detail_id

    for m = 1, #INV_TXT_LOG_ATTRS do
        inv_txn_log_data[INV_TXT_LOG_ATTRS[m]] = inv_detail_data[INV_TXT_LOG_ATTRS[m]]
    end
    for m = 1, #UDF_ATTRS do
        inv_txn_log_data[UDF_ATTRS[m]] = inv_detail_data[UDF_ATTRS[m]]
    end
    local cur_qty = lua.Get_NumAttrValue( inv_detail_data.F_QTY )
    inv_txn_log_data.F_CUR_QTY = cur_qty - qty
    inv_txn_log_data.F_QTY = qty
    inv_txn_log_data.S_BS_TYPE = bs_type
    inv_txn_log_data.S_BS_NO = bs_no
    nRet, inv_txn_log_data = m3.CreateDataObj2(strLuaDEID, inv_txn_log_data)
    if nRet ~= 0 then
        return 1, "创建【库存交易日志】失败!" .. inv_txn_log_data
    end
    return 0
end

return wms_inv
