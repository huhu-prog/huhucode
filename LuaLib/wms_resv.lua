--[[
    版本：     Version 3.0
    创建日期： 2026-3-26
    修改日期:  2026-6-19
    创建人：   HAN

    WMS-Basis-Model-Version: V19.3

    名称:   wms_resv
    说明:   和库存预留操作相关（人工拣货分配操作）

    【库存预留】
        _Create_ResvDetail   — 创建库存预留明细
        _Finish_Reservation  — 完成库存预留，库存预留转为真正的库存分配
        _Cancel_Reservation  — 取消库存预留

    更改记录:
        2026-3-26  HAN  创建
        2026-6-19        整理函数清单，统一注释格式

    AI CHECK:
        -- 20260619
--]]

wms_base = require ("wms_base")
wms_inv  = require ("wms_inventory")
wms_out = require("wms_outbound")

local wms_resv = {_version = "0.2.1"}

-- 创建库存预留明细
-- @function wms_resv._Create_ResvDetail
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table parameter 输入参数, 必须有值
-- @tparam table inv_detail_data 库存明细, 必须有值
-- @treturn table|nil 创建的INV_Reservation_Detail数据对象, nil
-- @treturn string|nil 错误信息，成功时 nil
--[[
    parameter = {
        resv_no,    -- 库存预留单号
        bs_type,    -- 来源单类型
        bs_no,      -- 来源单编码
        bs_row_no,  -- 来源单行号
        qty         -- 预留数量 
    }
--]]
function wms_resv._Create_ResvDetail( strLuaDEID, parameter, inv_detail_data )
    local nRet, strRetInfo

    -- 输入参数检查
    if parameter == nil or type(parameter) ~= "table" then
        return nil, "wms_resv._Create_ResvDetail 函数中 parameter 参数不能为空, 必须是table类型"
    end
    if inv_detail_data == nil or type(inv_detail_data) ~= "table" then
        return nil, "wms_resv._Create_ResvDetail 函数中 inv_detail_data 参数不能为空, 必须是table类型"
    end
    local inv_detail_id = lua.Get_StrAttrValue( inv_detail_data.id )
    if inv_detail_id == '' then
        return nil, "wms_resv._Create_ResvDetail 函数中 inv_detail_data.id 参数不能为空"
    end 

    local resv_no = lua.Get_StrAttrValue( parameter.resv_no )
    if resv_no == '' then
        return nil, "wms_resv._Create_ResvDetail 函数中 parameter.resv_no 参数不能为空"
    end   
    local qty = lua.Get_NumAttrValue( parameter.qty )
    if qty <= 0 then
        return nil, "wms_resv._Create_ResvDetail 函数中 parameter.qty 参数不能为空且必须大于0"
    end
    local bs_type = lua.Get_StrAttrValue( parameter.bs_type )
    if bs_type == '' then
        return nil, "wms_resv._Create_ResvDetail 函数中 parameter.bs_type 参数不能为空"
    end 
    local bs_no = lua.Get_StrAttrValue( parameter.bs_no )
    if bs_no == '' then
        return nil, "wms_resv._Create_ResvDetail 函数中 parameter.bs_no 参数不能为空"
    end     
    local bs_row_no = lua.Get_NumAttrValue( parameter.bs_row_no )
    if bs_row_no <= 0 then
        return nil, "wms_resv._Create_ResvDetail 函数中 parameter.bs_row_no 参数不能为空且必须大于0"
    end

    -- 获取库存预留单数据对象
    local strCondition, strSetAttr
    local resv_data
    strCondition = "S_NO = '"..resv_no.."'"
    nRet, resv_data = m3.GetDataObjByCondition2( strLuaDEID, "INV_Reservation", strCondition )    
    if nRet ~= 0 then
        return nil, resv_data
    end
    -- 判断库存预留单的状态，如果状态不等于0（预占中），不能继续做下面的这些操作
    local n_state = lua.Get_NumAttrValue( resv_data.N_B_STATE )
    if n_state ~= INV_RESV_STATE.Alloc then
        if n_state == INV_RESV_STATE.Release then
            return nil, "手工配盘的操作已经超时，请先点击取消后重新开始配盘!"
        end
        return nil, "库存预留单状态不正确，当前状态为："..n_state
    end
    -- INV_Detail 加预分配（软锁定），考虑到预分配数量可能大于可用数量（被别人用掉），所以需要先判断可用数量是否大于预分配数量
    strCondition = "S_ID = '"..inv_detail_id.."' AND ( F_QTY_VALID > "..qty.." OR ( "..qty.." - F_QTY_VALID ) <= 0.001)"    
    strSetAttr = "F_PRE_ALLOC_QTY = F_PRE_ALLOC_QTY + "..qty
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "INV_Detail", strCondition, strSetAttr )
    if nRet ~= 0 then 
        return nil, "更新【INV_Detail】信息失败!"..strRetInfo
    end    
    
    local inv_resv_detail = {}
    -- 出库单明细/出库波次明细 加累计配盘数量
    if bs_type == "Outbound_Order" then
        strCondition = "S_OO_NO = '"..bs_no.."' AND N_ROW_NO = "..bs_row_no
        strSetAttr = "F_ACC_D_QTY = F_ACC_D_QTY + "..qty
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Outbound_Detail", strCondition, strSetAttr )
        if nRet ~= 0 then 
            return nil, "更新【Outbound_Detail】信息失败!"..strRetInfo
        end         
    elseif bs_type == "Outbound_Wave" then
        strCondition = "S_WAVE_NO = '"..bs_no.."' AND N_ROW_NO = "..bs_row_no
        strSetAttr = "F_ACC_D_QTY = F_ACC_D_QTY + "..qty
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "OW_Detail", strCondition, strSetAttr )
        if nRet ~= 0 then 
            return nil, "更新【OW_Detail】信息失败!"..strRetInfo
        end          
    else
        return nil, "parameter中的bs_type来源类型不支持!"
    end

    -- 创建库存预留明细
    inv_resv_detail = m3.AllocObject2( strLuaDEID, "INV_Reservation_Detail" )
    inv_resv_detail.S_INV_RESV_NO = resv_no
    for m = 1, #ITEM_BASE_ATTRS2 do
        inv_resv_detail[ITEM_BASE_ATTRS2[m]] = inv_detail_data[ITEM_BASE_ATTRS2[m]]
    end
    for m = 1, #UDF_ATTRS do
        inv_resv_detail[UDF_ATTRS[m]] = inv_detail_data[UDF_ATTRS[m]]
    end
    inv_resv_detail.S_CNTR_CODE = inv_detail_data.S_CNTR_CODE
    inv_resv_detail.S_CELL_NO = inv_detail_data.S_CELL_NO

    inv_resv_detail.S_BS_TYPE = bs_type
    inv_resv_detail.S_BS_NO = bs_no
    inv_resv_detail.N_BS_ROW_NO = bs_row_no
    inv_resv_detail.F_RESV_QTY = qty
    inv_resv_detail.G_INV_DETAIL_ID = inv_detail_id

    nRet, inv_resv_detail = m3.CreateDataObj2(strLuaDEID, inv_resv_detail)
    if nRet ~= 0 then
        return nil, "创建【INV_Reservation_Detail】失败!" .. inv_resv_detail
    end
    
    return inv_resv_detail
end

-- 把库存预留明细对象中设定的库存预分配量变成分配量
-- @function resv_detail_lock
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table resv_detail_data 库存预留明细对象, 必须有值配盘参数, 必须有值
-- @treturn boolean 操作是否成功
-- @treturn string|nil 错误信息，成功时 nil
local function resv_detail_lock( strLuaDEID, resv_detail_data )
    local inv_detail_id = resv_detail_data.G_INV_DETAIL_ID or ''
    if inv_detail_id == '' then
        return nil, "库存预分配明细中的 G_INV_DETAIL_ID 不能为空"
    end
    local inv_detail_data, nRet
    local strCondition = "S_ID = '"..inv_detail_id.."'"
    nRet, inv_detail_data = m3.GetDataObjByCondition2( strLuaDEID, "INV_Detail", strCondition )    
    if nRet ~= 0 then
        return nil, inv_detail_data
    end    
    inv_detail_data.S_ID = inv_detail_id
    local qty = lua.Get_NumAttrValue( resv_detail_data.F_RESV_QTY )
    local bs_type = lua.Get_StrAttrValue( resv_detail_data.S_BS_TYPE )
    local bs_no = lua.Get_StrAttrValue( resv_detail_data.S_BS_NO )

    local success, err = wms_inv._INV_Detail_Pre_Alloc_Lock( strLuaDEID, inv_detail_data, qty, bs_type, bs_no)  
    if success == nil then
        return nil, err
    end
    return true
end

-- 完成库存预留,库存预留转为真正的库存分配
-- @function wms_resv._Finish_Reservation
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table parameter 配盘参数, 必须有值
-- @tparam string resv_no 库存预留单编码, 必须有值
-- @treturn boolean 操作是否成功
-- @treturn string|nil 错误信息，成功时 nil
--[[
        parameter = {
                    station  -- 分拣站台, 可以为空
                    bs_type --（Outbound_Order/Outbound_Wave） 
                    bs_no -- 波次号/出库单号
                    factory -- 工厂标识
                    cntr_out_op_def -- 容器出库作业定义
                    cntr_back_op_def -- 容器回库作业定义

                    -- 下面两个属性不是必须有值
                    exit_area_code -- 出库口接驳区，有些情况是没 exit_loc 的
                    exit_loc -- 出库出口货位，货位对象{ area_code, code }                    
                }

--]]
function wms_resv._Finish_Reservation( strLuaDEID, parameter, resv_no )
    local nRet, strRetInfo

    -- 输入参数检查
    if parameter == nil or type(parameter) ~= "table" then
        return nil, "wms_resv._Finish_Reservation 函数中 parameter 参数不能为空, 必须是table类型"
    end
    local resv_no = lua.Get_StrAttrValue( resv_no )
    if resv_no == '' then
        return nil, "wms_resv._Finish_Reservation 函数中 resv_no 参数不能为空"
    end   
    -- 获取库存预留单数据对象
    local strCondition, strSetAttr
    local resv_data
    strCondition = "S_NO = '"..resv_no.."'"
    nRet, resv_data = m3.GetDataObjByCondition2( strLuaDEID, "INV_Reservation", strCondition )    
    if nRet ~= 0 then
        return nil, resv_data
    end
    -- 判断库存预留单的状态，如果状态不等于0（预占中），不能继续做下面的这些操作
    local n_state = lua.Get_NumAttrValue( resv_data.N_B_STATE )
    if n_state ~= INV_RESV_STATE.Alloc then
        return nil, "库存预留单状态不正确，当前状态为："..n_state.."/"..INV_RESV_STATE_CN[n_state]
    end  
    
    -- 判断预出库单中的 bs_type/bs_no 属性是否相符
    local bs_type = lua.Get_StrAttrValue( resv_data.S_BS_TYPE )
    local bs_no = lua.Get_StrAttrValue( resv_data.S_BS_NO )
    if bs_type ~= parameter.bs_type or bs_no ~= parameter.bs_no then
        return nil, "库存预留单中的 bs_type/bs_no 属性与预出库单中的 bs_type/bs_no 属性不相符"
    end
    
    -- 库存预留单/明细的状态（改成 Locked）
    local cur_time = os.date("%Y-%m-%d %H:%M:%S")
    strCondition = "S_NO = '"..resv_no.."'"
    strSetAttr = "N_B_STATE = "..INV_RESV_STATE.Locked..", T_LOCKED_AT = '"..cur_time.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "INV_Reservation", strCondition, strSetAttr )
    if nRet ~= 0 then 
        return nil, "更新【INV_Reservation】信息失败!"..strRetInfo
    end  
    strCondition = "S_INV_RESV_NO = '"..resv_no.."'"
    strSetAttr = "N_B_STATE = "..INV_RESV_STATE.Locked
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "INV_Reservation_Detail", strCondition, strSetAttr )
    if nRet ~= 0 then 
        return nil, "更新【INV_Reservation_Detail】信息失败!"..strRetInfo
    end       
    
    -- 获取库存预留单明细数据对象
    local data_objs
    strCondition = "S_INV_RESV_NO = '"..resv_no.."'"
    local strOrder = "S_CNTR_CODE"
    nRet, data_objs = m3.QueryDataObject(strLuaDEID, "INV_Reservation_Detail", strCondition, strOrder )
    if nRet ~= 0 then 
        return nil, data_objs 
    end
    local resv_detail_data, success, err
    local DC_DETAIL_ATTRS_COUNT = #DC_DETAIL_ATTRS

    if data_objs ~= '' then
        local find, cntr_code
        local d_cntr_list = {}
        local d_cntr_detail_list = {}

        for i = 1, #data_objs do
            resv_detail_data = m3.KeyValueAttrsToObjAttr(data_objs[i].attrs)
            if resv_detail_data == nil then
                return nil, "转换对象属性失败"
            end
            -- 预分配量改成分配量
            success, err = resv_detail_lock( strLuaDEID, resv_detail_data )
            if success == nil then 
                return nil, err 
            end

            -- 生成 Distribution_CNTR 和 Distribution_CNTR_Detail
            find = false
            cntr_code = resv_detail_data.S_CNTR_CODE or ''
            if cntr_code == '' then
                return nil, "库存预留明细中的容器编码不能为空!"
            end
            for m = 1, #d_cntr_list do
                if ( lua.Normalize_String( d_cntr_list[m].S_CNTR_CODE ) == lua.Normalize_String( cntr_code ) ) then
                    find = true 
                    break 
                end
            end
            if not find then
                -- 初始化【配盘】容器信息
                local distribution_cntr =  m3.AllocObject2(strLuaDEID, "Distribution_CNTR")
                distribution_cntr.S_FACTORY = parameter.factory
                distribution_cntr.S_BS_TYPE = resv_data.S_BS_TYPE
                distribution_cntr.S_BS_NO = resv_data.S_BS_NO
                distribution_cntr.S_OUT_OP_NAME = parameter.cntr_out_op_def or ''
                distribution_cntr.S_BACK_OP_NAME = parameter.cntr_back_op_def or ''

                distribution_cntr.S_CNTR_CODE = cntr_code
                distribution_cntr.N_B_STATE = DIST_CNTR_STATE.PrePickingOK
                --[[
                考虑到料箱的位置会变化，因此改成中启动的时候再检查一下料箱的位置
                distribution_cntr.S_WH_CODE = resv_detail_data.S_WH_CODE
                distribution_cntr.S_AREA_CODE = resv_detail_data.S_AREA_CODE
                distribution_cntr.S_LOC_CODE = resv_detail_data.S_LOC_CODE  
                --]]
                distribution_cntr.S_EXIT_AREA_CODE = ''
                distribution_cntr.S_EXIT_LOC_CODE = ''
                distribution_cntr.S_STATION_NO = parameter.station
                distribution_cntr.S_DC_NO = ""                          -- 配盘号

                if lua.isTableEmpty( parameter.exit_loc ) then
                    distribution_cntr.S_EXIT_AREA_CODE = parameter.exit_area_code
                    distribution_cntr.S_EXIT_LOC_CODE = ''
                else
                    distribution_cntr.S_EXIT_AREA_CODE = parameter.exit_loc.area_code
                    distribution_cntr.S_EXIT_LOC_CODE = parameter.exit_loc.code                       
                end            
                table.insert( d_cntr_list, distribution_cntr )                
            end

            -- 生产配盘明细
            local d_cntr_detail = m3.AllocObject2(strLuaDEID, "Distribution_CNTR_Detail")

            d_cntr_detail.G_INV_DETAIL_ID = resv_detail_data.G_INV_DETAIL_ID

            d_cntr_detail.S_PUT_WALL_NO = ''            -- 播种墙位置(location)
            d_cntr_detail.S_MATCH_RULE = ''              -- 货品出库匹配规则
            d_cntr_detail.S_STATION_NO = parameter.station

            for m = 1, DC_DETAIL_ATTRS_COUNT do
                d_cntr_detail[DC_DETAIL_ATTRS[m]] = resv_detail_data[DC_DETAIL_ATTRS[m]]
            end

            d_cntr_detail.F_QTY = resv_detail_data.F_RESV_QTY     
            d_cntr_detail.S_BS_TYPE = resv_detail_data.S_BS_TYPE
            d_cntr_detail.S_BS_NO = resv_detail_data.S_BS_NO
            d_cntr_detail.N_BS_ROW_NO = resv_detail_data.N_BS_ROW_NO    
            
            table.insert( d_cntr_detail_list, d_cntr_detail )            
        end

        -- 创建配盘
        nRet, strRetInfo = wms_out.Creat_Distribution_list( strLuaDEID, d_cntr_list, d_cntr_detail_list  )
        if nRet ~= 0 then
            return nil,"wms_out.Creat_Distribution_list 发生错误，!"..strRetInfo
        end         
    end    

    -- 如果出库单拣货分配的库存不足，生产缺件清单
    local strOrder
    data_objs = ''
    if parameter.bs_type == "Outbound_Wave" then
        -- 先删除缺件清单
        strCondition = "S_WO_NO = '" .. parameter.bs_no .."'"
        nRet, strRetInfo = mobox.dbdeleteData(strLuaDEID, "Shortage_Detail", strCondition)
        if nRet ~= 0 then 
            return nil, "删除 Shortage_Detail 时发生错误，!"..strRetInfo
        end   
    
        strCondition = "S_WAVE_NO = '"..parameter.bs_no.."' AND F_QTY > F_ACC_D_QTY"
        strOrder = "N_ROW_NO"
        nRet, data_objs = m3.QueryDataObject(strLuaDEID, "OW_Detail", strCondition, strOrder )
        if nRet ~= 0 then 
            return nil, data_objs 
        end
    elseif parameter.bs_type == "Outbound_Order" then
        -- 先删除缺件清单
        strCondition = "S_OO_NO = '" .. parameter.bs_no .."'"
        nRet, strRetInfo = mobox.dbdeleteData(strLuaDEID, "Shortage_Detail", strCondition)
        if nRet ~= 0 then 
            return nil, "删除 Shortage_Detail 时发生错误，!"..strRetInfo
        end  
        
        strCondition = "S_OO_NO = '"..parameter.bs_no.."' AND F_QTY > F_ACC_D_QTY"
        strOrder = "N_ROW_NO"
        nRet, data_objs = m3.QueryDataObject(strLuaDEID, "Outbound_Detail", strCondition, strOrder )
        if nRet ~= 0 then 
            return nil, data_objs 
        end
    end

    strSetAttr = "C_SHORTAGE = 'N'"
    if data_objs ~= '' then
        local shortage_list = {}
        local detail_data, qty, d_qty

        for i = 1, #data_objs do
            detail_data = m3.KeyValueAttrsToObjAttr(data_objs[i].attrs)
            if detail_data == nil then
                return nil, "转换对象属性失败"
            end    
            qty = lua.Get_NumAttrValue( detail_data.F_QTY )
            d_qty = lua.Get_NumAttrValue( detail_data.F_ACC_D_QTY )

            local shortage = {
                bs_type = parameter.bs_type,
                bs_no = parameter.bs_no,
                qty = qty - d_qty,
                item_detail = detail_data                       -- IW_Detail/Outbound_Detail
            }
            table.insert( shortage_list, shortage )     
        end

        strSetAttr = "C_SHORTAGE = 'Y'"
        local success, err = wms_out._Create_Shortage_Detail( strLuaDEID, shortage_list  )
        if success == nil then
            return nil, "wms_out._Create_Shortage_Detail 发生错误，!"..err
        end 
    end

    if parameter.bs_type == "Outbound_Wave" then
        -- 出库波次业务状态设置为 配货完成
        strSetAttr = strSetAttr..", N_B_STATE = "..OW_STATE.AllocOK               
        strCondition = "S_WAVE_NO = '"..parameter.bs_no.."'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Outbound_Wave", strCondition, strSetAttr )
        if nRet ~= 0 then 
            return nil, "跟新【Outbound_Wave】信息失败!"..strRetInfo
        end
    elseif parameter.bs_type == "Outbound_Order" then
        -- 出库单/出库波次业务状态设置为 配货完成
        strSetAttr = strSetAttr..", N_B_STATE = "..OUTBOUND_ORDER_STATE.AllocOK                
        strCondition = "S_NO = '"..parameter.bs_no.."'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Outbound_Order", strCondition, strSetAttr )
        if nRet ~= 0 then 
            return nil, "跟新【Outbound_Order】信息失败!"..strRetInfo
        end
    end

    return true
end

-- 取消库存预留
-- @function wms_resv._Cancel_Reservation
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string resv_no 库存预留单编码, 必须有值
-- @treturn boolean 操作是否成功
-- @treturn string|nil 错误信息，成功时 nil

function wms_resv._Cancel_Reservation( strLuaDEID, resv_no )
    local nRet, strRetInfo

    -- 输入参数检查
    if resv_no == '' or resv_no == nil then
        return nil, "wms_resv._Cancel_Reservation 函数中 resv_no 参数不能为空"
    end   
    -- 获取库存预留单数据对象
    local strCondition, strSetAttr
    local resv_data
    strCondition = "S_NO = '"..resv_no.."'"
    nRet, resv_data = m3.GetDataObjByCondition2( strLuaDEID, "INV_Reservation", strCondition )    
    if nRet ~= 0 then
        return nil, resv_data
    end
    -- 判断库存预留单的状态，如果状态不等于0（预占中），不能继续做下面的这些操作
    local n_state = lua.Get_NumAttrValue( resv_data.N_B_STATE )
    if n_state ~= INV_RESV_STATE.Alloc then
        return nil, "库存预留单状态不正确,不能取消，当前状态为："..n_state.."/"..INV_RESV_STATE_CN[n_state]
    end   
    
    local bs_type = lua.Get_StrAttrValue( resv_data.S_BS_TYPE )
    local bs_no = lua.Get_StrAttrValue( resv_data.S_BS_NO )
    if bs_type == '' or bs_no == '' then
        return nil, "库存预留单中的 bs_type/bs_no 属性为空!"
    end
  
    -- 库存预留单/明细的状态（改成 Cancel ）
    local cur_time = os.date("%Y-%m-%d %H:%M:%S")
    strCondition = "S_NO = '"..resv_no.."'"
    strSetAttr = "N_B_STATE = "..INV_RESV_STATE.Cancel..", T_RELEASE_AT = '"..cur_time.."', S_RELEASE_REASON = '用户取消'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "INV_Reservation", strCondition, strSetAttr )
    if nRet ~= 0 then 
        return nil, "更新【INV_Reservation】信息失败!"..strRetInfo
    end  
    strCondition = "S_INV_RESV_NO = '"..resv_no.."'"
    strSetAttr = "N_B_STATE = "..INV_RESV_STATE.Cancel
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "INV_Reservation_Detail", strCondition, strSetAttr )
    if nRet ~= 0 then 
        return nil, "更新【INV_Reservation_Detail】信息失败!"..strRetInfo
    end   
    
  -- 获取库存预留单明细数据对象
    local data_objs
    strCondition = "S_INV_RESV_NO = '"..resv_no.."'"
    local strOrder = "S_CNTR_CODE"
    nRet, data_objs = m3.QueryDataObject(strLuaDEID, "INV_Reservation_Detail", strCondition, strOrder )
    if nRet ~= 0 then 
        return nil, data_objs 
    end
    local resv_detail_data, qty, bs_row_no

    if data_objs ~= '' then
        for i = 1, #data_objs do
            resv_detail_data = m3.KeyValueAttrsToObjAttr(data_objs[i].attrs)
            if resv_detail_data == nil then
                return nil, "转换对象属性失败"
            end
            qty = lua.Get_NumAttrValue( resv_detail_data.F_RESV_QTY )
            bs_row_no = lua.Get_NumAttrValue( resv_detail_data.N_BS_ROW_NO )
            if qty > 0 then
                -- 减出库单明细这里累计配盘数量
                if bs_type == "Outbound_Order" then
                    strCondition = "S_OO_NO = '"..bs_no.."' AND N_ROW_NO = "..bs_row_no
                    strSetAttr = "F_ACC_D_QTY = F_ACC_D_QTY - "..qty
                    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Outbound_Detail", strCondition, strSetAttr )
                    if nRet ~= 0 then 
                        return nil, "更新【Outbound_Detail】信息失败!"..strRetInfo
                    end         
                elseif bs_type == "Outbound_Wave" then
                    strCondition = "S_WAVE_NO = '"..bs_no.."' AND N_ROW_NO = "..bs_row_no
                    strSetAttr = "F_ACC_D_QTY = F_ACC_D_QTY - "..qty
                    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "OW_Detail", strCondition, strSetAttr )
                    if nRet ~= 0 then 
                        return nil, "更新【OW_Detail】信息失败!"..strRetInfo
                    end          
                end    
                -- 减 INV_Detail 中的 F_PRE_ALLOC_QTY
                local inv_detail_id = resv_detail_data.G_INV_DETAIL_ID or ''
                if inv_detail_id ~= '' then
                    strCondition = "S_ID = '"..inv_detail_id.."' AND F_PRE_ALLOC_QTY >= "..qty
                    strSetAttr = "F_PRE_ALLOC_QTY = F_PRE_ALLOC_QTY - "..qty
                    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "INV_Detail", strCondition, strSetAttr )
                    if nRet ~= 0 then 
                        return nil, "更新【INV_Detail】信息失败!"..strRetInfo
                    end      
                end
            end
        end
    end
    return true
end

return wms_resv