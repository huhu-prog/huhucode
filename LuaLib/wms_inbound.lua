--[[
    版本：     Version 2.1
    创建日期： 2024-7-26
    修改日期:  2026-6-17
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    功能：
        所有和入库相关的函数

    外部函数一览：
        wms_in.Pre_Alloc_CNTR_Cancel             -- 预分配容器取消，组盘状态设为取消，明细状态改为3，回退来源业务取消数量
        wms_in.CreateInspectionOrder             -- 通过收货单创建检验单及验单明细，并指定仓库检验区
        wms_in.After_Pac_Finish                  -- 预分配容器回库后处理，判断入库单是否可以完成
        wms_in.Pre_Alloc_CNTR_PostProcess        -- 预分配容器入库后处理，检查明细完成状态并创建入库作业、增加库存量
        wms_in.InboundWave_Finish_PostProce      -- 入库波次完成后，将波次明细中的入库/取消数量批分到入库明细

    更改说明：
    AI CHECK:
        2026-06-17   单行if改为多行结构，添加标准 @function/@tparam/@treturn 注解，添加外部函数一览
        
--]]

wms_base = require("wms_base")
wms_wh   = require("wms_wh")
wms_op = require("wms_operation")
wms_cntr = require("wms_container")

local wms_in = {_version = "0.2.1"}

--[[ 
    预分配容器取消
    -- 组盘【Pre_Alloc_Container】状态设置为 6/取消 同时
    -- 预分配容器明细【Pre_Alloc_CNTR_Detail】状态改为 3
    -- 来源业务数据中的取消数量+ 预分配容器明细中的数量
    @function wms_in.Pre_Alloc_CNTR_Cancel
    @tparam string strLuaDEID Lua数据交换区句柄
    @tparam table pac_obj 预分配容器对象
    @treturn number nRet 0: 成功，非零失败
    @treturn string 失败时的错误信息
--]]
function wms_in.Pre_Alloc_CNTR_Cancel( strLuaDEID, pac_obj )
    local n, nRet, strRetInfo
    -- 组盘已经完成或取消状态不需要再做 取消
    if pac_obj.b_state > 1 then
        return 0
    end

    -- 6 表示'取消'
    local strUpdateSql = "N_B_STATE = 6"
    local strCondition = "S_PAC_NO = '"..pac_obj.pac_no.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Pre_Alloc_Container", strCondition, strUpdateSql )
    if nRet ~= 0 then
        return 1, "更新【预分配容器】信息失败!"..strRetInfo
    end
    -- 更新 Pre_Alloc_CNTR_Detail 中的状态
    strUpdateSql = "N_B_STATE = 3"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Pre_Alloc_CNTR_Detail", strCondition, strUpdateSql )
    if nRet ~= 0 then
        return 1, "更新【预分配容器明细】信息失败!"..strRetInfo
    end

    -- 查询预分配容器明细
    local data_objects
    nRet, data_objects = m3.QueryDataObject(strLuaDEID, "Pre_Alloc_CNTR_Detail", strCondition, "N_BS_ROW_NO" )
    if nRet ~= 0 then
        return 2, "QueryDataObject失败!"..data_objects
    end
    if data_objects == '' then
        return 0
    end

    local obj_attrs
    local strSetAttr
    for n = 1, #data_objects do
        obj_attrs = m3.KeyValueAttrsToObjAttr(data_objects[n].attrs)

        -- 根据业务来源加 F_ACC_I_QTY/累计入库数量
        if obj_attrs.S_BS_TYPE == "Inbound_Order" then
            if obj_attrs.S_BS_NO ~= nil and obj_attrs.S_BS_NO ~= '' then
                strCondition = "S_IO_NO = '"..obj_attrs.S_BS_NO.."' AND N_ROW_NO = "..obj_attrs.N_BS_ROW_NO
                strSetAttr = "F_ACC_C_QTY = F_ACC_C_QTY + "..obj_attrs.F_QTY
                nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Inbound_Detail", strCondition, strSetAttr )
                if nRet ~= 0 then
                    return 1, "设置【Inbound_Detail】累计入库数量失败!"..strRetInfo
                end
            end
        elseif obj_attrs.S_BS_TYPE == 'Inbound_Wave' then
            if obj_attrs.S_BS_NO ~= nil and obj_attrs.S_BS_NO ~= '' then
                strCondition = "S_WAVE_NO = '"..obj_attrs.S_BS_NO.."' AND N_ROW_NO = "..obj_attrs.N_BS_ROW_NO
                strSetAttr = "F_ACC_C_QTY = F_ACC_C_QTY + "..obj_attrs.F_QTY
                nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "IW_Detail", strCondition, strSetAttr )
                if nRet ~= 0 then
                    return 1, "设置【IW_Detail】累计入库数量失败!"..strRetInfo
                end
            end
        end      
    end
    return 0
end

--[[
    通过收货单创建检验单及验单明细，并指定仓库检验区
    @function wms_in.CreateInspectionOrder
    @tparam string strLuaDEID Lua数据交换区句柄
    @tparam table receipt_obj 收货单对象
    @tparam string inspection_area 检验区
    @treturn number nRet 0: 成功，非零失败
    @treturn string 失败时的错误信息
--]]
function wms_in.CreateInspectionOrder( strLuaDEID, receipt_obj, inspection_area )
    local strCondition, nRet, strRetInfo

    -- step1 创建检验单
    local inspection = m3.AllocObject(strLuaDEID,"Inspect_Order")
    local ret_obj
    local n, area_items

    inspection.wms_op_no = receipt_obj.no
    inspection.inspect_type = 1                  -- 收货检
    inspection.factory = receipt_obj.factory
    inspection.bs_type = receipt_obj.bs_type
    inspection.bs_no = receipt_obj.bs_no
    inspection.wh_code = receipt_obj.wh_code             

    -- 获取检验区
    -- 获取仓库检验区可以看成是逻辑上的检验区)
    nRet,area_items = wms_wh.GetArea( strLuaDEID, wh_code, 3 )
    if nRet ~= 0 then
        return 1, area_items
    end    
    local n = #area_items
    if n == 1 then 
        inspection_area = area_items[1]
    elseif n > 1 then
    end
    inspection.area_code = inspection_area

    nRet, ret_obj = m3.CreateDataObj( strLuaDEID, inspection )
    if nRet ~= 0 then
        return 1, "创建【检验单】失败! "..ret_obj
    end
    local strNo = ret_obj.no
    if strNo == nil or strNo == '' then
        return 1, "创建【检验单】后获取的验单号为空或 nil! "
    end

    -- step2: 获取收货单明细生成验单明细
    local strOrder = 'N_ROW_NO'
    strCondition = "S_RECEIPT_NO = '"..receipt_obj.no.."'"
    nRet, strRetInfo = mobox.queryDataObjAttr( strLuaDEID, "Receipt_Detail", strCondition, strOrder, "S_ITEM_CODE", "S_ITEM_NAME","S_ITEM_SPEC","N_ITEM_STATE",
                                               "S_BATCH_NO", "S_SERIAL_NO", "F_QTY", "S_UOM", "S_BATCH_NO", "S_SERIAL_NO" )
    if nRet ~= 0 then
        return 1, "获取【收货单明细】失败! "..strRetInfo
    end

    local retObjs = json.decode( strRetInfo )
    local nObjs =  #retObjs    
    local n, nMaxAttr
    local attrs
    local receipt_detail

    for n = 1, nObjs do
        attrs = retObjs[n].attrs
        nMaxAttr = #attrs
        nRet, receipt_detail = m3.ObjAttrStrToLuaObj( "Receipt_Detail", lua.table2str(attrs) )
        if nRet ~= 0 then
            return 1, "m3.ObjAttrStrToLuaObj(Receipt_Detail) 失败! "..receipt_detail
        end

        attrs[nMaxAttr+1] = lua.KeyValueObj( "S_INSPECT_NO", strNo )
        nRet, strRetInfo = mobox.createDataObj( strLuaDEID, "Inspect_Detail", lua.table2str(attrs) )
        if nRet ~= 0 then
            return 1, "创建【检验单明细】失败! "..strRetInfo
        end
    end    

    return 0
end

--[[ 
    预分配容器回库后处理, 入库任务完成，判断入库单是否可以完成
    @function wms_in.After_Pac_Finish
    @tparam string strLuaDEID Lua数据交换区句柄
    @tparam string pac_no 预分配容器流水号
    @treturn number nRet 0: 成功，非零失败
    @treturn string 失败时的错误信息
--]]
function wms_in.After_Pac_Finish( strLuaDEID, pac_no )
    local nRet, strRetInfo

    if pac_no == nil or pac_no == '' then 
        return 1, "wms_in.After_Pac_Finish 函数中 pac_no 必须有值!"
    end

    -- 获取 Pre_Alloc_CNTR_Detail
    local strOrder = ''
    local strCondition = "S_PAC_NO = '"..pac_no.."'"

    nRet, strRetInfo = mobox.queryDataObjAttr( strLuaDEID, "Pre_Alloc_CNTR_Detail", strCondition, strOrder )
    if nRet ~= 0 then
        return 1, "获取【预分配容器明细】失败! "..strRetInfo
    end
    if strRetInfo == '' then 
        return 0
    end

    local retObjs = json.decode( strRetInfo )
    local n
    local pac_detail = {}

    for n = 1, #retObjs do
        nRet, pac_detail = m3.ObjAttrStrToLuaObj( "Pre_Alloc_CNTR_Detail", lua.table2str(retObjs[n].attrs) )
        if nRet ~= 0 then
            return 1, "m3.ObjAttrStrToLuaObj(Pre_Alloc_CNTR_Detail) 失败! "..pac_detail
        end
        -- 根据业务来源加 F_ACC_I_QTY/累计入库数量
        if pac_detail.bs_type == "Inbound_Order" then
            if pac_detail.bs_no ~= nil and pac_detail.bs_no ~= '' then
                strCondition = "S_IO_NO = '"..pac_detail.bs_no.."' AND N_ROW_NO  = "..pac_detail.bs_row_no
                local strSetAttr = "F_ACC_I_QTY = F_ACC_I_QTY +"..pac_detail.act_qty
                if lua.equation( 0, pac_detail.cancel_qty ) == false then
                    strSetAttr = strSetAttr..", F_ACC_C_QTY = F_ACC_C_QTY + "..pac_detail.cancel_qty
                end
                nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Inbound_Detail", strCondition, strSetAttr )
                if nRet ~= 0 then
                    return 1, "设置【Inbound_Detail】累计入库数量失败!"..strRetInfo
                end
            end
        end
        if pac_detail.bs_type == 'Inbound_Wave' then
            if pac_detail.bs_no ~= nil and pac_detail.bs_no ~= '' then
                strCondition = "S_WAVE_NO = '"..pac_detail.bs_no.."' AND N_ROW_NO = "..pac_detail.bs_row_no
                local strSetAttr = "F_ACC_I_QTY = F_ACC_I_QTY +"..pac_detail.act_qty
                if lua.equation( 0, pac_detail.cancel_qty ) == false then
                    strSetAttr = strSetAttr..", F_ACC_C_QTY = F_ACC_C_QTY + "..pac_detail.cancel_qty
                end
                nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "IW_Detail", strCondition, strSetAttr )
                if nRet ~= 0 then
                    return 1, "设置【IW_Detail】累计入库数量失败!"..strRetInfo
                end
            end
        end        
    end    
    return 0
end

--[[
    预分配容器入库后处理程序
    -- 检查预分配容器流水号 pac_no 下的预分配容器明细是否已完成（码盘完成），
    -- 如果完成则创建入库作业。适用预分配料箱入库作业场景。
    -- 增加库存量
    -- 判断入库的商品是否可以和目前料箱里的货品进行合并，如果可以合并数量

    @function wms_in.Pre_Alloc_CNTR_PostProcess
    @tparam string strLuaDEID Lua数据交换区句柄
    @tparam string pac_no 预分配容器流水号
    @tparam string station 站台编码
    @tparam string cntr_code 容器编码
    @tparam bool lock_end_loc 是否锁定入库的目标货位
    @tparam string goback_event 预分配料箱回库处理脚本
    @tparam string inbound_post_event 预分配料箱入库后脚本处理
    @treturn number nRet 0: 创建了入库作业，非零失败
    @treturn table operation 创建的入库作业对象

    备注: 从[prj_base.Pre_Alloc_CNTR_PostProcess] 复制过来的代码，把 action 部分剥离提高了代码的共用性
--]]
function wms_in.Pre_Alloc_CNTR_PostProcess( strLuaDEID, pac_no, station, cntr_code, lock_end_loc, goback_event, inbound_post_event )
    local nRet, strRetInfo
    
    if lock_end_loc == nil then lock_end_loc = true end
    if lua.StrIsEmpty( pac_no ) then
        return 2, "预分配料箱流水号必须有值!"
    end

    -- 检查一下当前料箱的入库任务是否已经全部完成，如果完成就创建一个【货品入库】作业
    -- N_B_STATE = 1/Palletizing 表示可执行的入库任务
    local strCondition = "S_PAC_NO = '"..pac_no.."' AND N_B_STATE = "..PAC_DETAIL_STATE.Palletizing       
    nRet, strRetInfo = mobox.getDataObjCount( strLuaDEID, "Pre_Alloc_CNTR_Detail", strCondition )
    if nRet ~= 0 then
        return 2, strRetInfo
    end
    local nCount = lua.StrToNumber( strRetInfo )  

    if goback_event == nil then goback_event = '' end
    if inbound_post_event == nil then inbound_post_event = '' end

    local operation = {}    

    if nCount == 0 then
        -- ***
        -- 判断是否有相同预分配容器的入库作业，这是严重的数据错误，这里加一个判断 N_TYPE = 1/Run 是执行的意思
        strCondition = "S_CARRY_CB_NO = '"..pac_no.."' AND N_TYPE = "..OPERATION_STATE.Run.." AND S_CARRY_CB_CLS = 'Pre_Alloc_Container'"
        nRet, strRetInfo = mobox.existThisData( strLuaDEID, "Operation", strCondition )
        if nRet ~= 0 then
            return 2, strRetInfo
        end
        -- 如果该车辆编码的动作已经在队列，返回，不做处理
        if strRetInfo == "yes" then 
            return  2, "容器号'"..cntr_code.."'不能重复创建货品入库作业!"
        end

        -- 获取【预分配容器】中定义的回库作业定义
        local pac
        nRet, pac = m3.GetDataObjectByKey(strLuaDEID, "Pre_Alloc_Container", "S_PAC_NO", pac_no )
        if nRet ~= 0 then
            return 1, "无法获取编码 = '"..pac_no.."' 的预分配容器!"
        end
        if lua.StrIsEmpty( pac.back_op_name ) then
            return 1, "【预分配容器】对象中 S_BACK_OP_NAME 必须有值!"
        end

        -- 容器里加入货品明细，如果容器有混箱规则，系统会在容器的扩展属性表加混箱值，通过这些值可以计算入库货位
        local container, cntr_loc_code
        nRet, container, cntr_loc_code = wms_cntr.GetInfo_Location( strLuaDEID, cntr_code )
        if nRet ~= 0 then 
            return 2, "获取【容器】信息失败! " .. container 
        end 

        local ctd       -- 容器类型定义
        nRet, ctd = wms_cntr.GetCTDInfo( container.ctd_code )
        if nRet ~= 0 then
            return 2, ctd
        end 

        -- 预分配容器入库完成后
        nRet, strRetInfo = wms_in.After_Pac_Finish( strLuaDEID, pac_no )        
        if nRet ~= 0 then  
            return  2, "wms_in.After_Pac_Finish 失败!"..strRetInfo
        end    

        -- 加库存量 INV_Detail 加【预分配容器明细】中的内容
        nRet, strRetInfo = wms_inv.Add_INV_Detail_By_PAC_Detail( strLuaDEID, ctd, cntr_code, pac_no, container.position )
        if nRet ~= 0 then
            return 2, 'wms_inv.Add_INV_Detail_By_PAC_Detail!'..strRetInfo
        end
        
        --【预分配容器】, 状态 = 3/PalletOK （码盘完成）
        local strUpdateSql = "N_B_STATE = "..PAC_STATE.PalletOK
        strCondition = "S_PAC_NO = '"..pac_no.."'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Pre_Alloc_Container", strCondition, strUpdateSql )
        if nRet ~= 0 then  
            return 2, "更新【预分配容器】状态失败!"..strRetInfo 
        end  
        -- 增加一个后台进程对预分配料箱进行回库处理（启动回库作业）
        if goback_event ~= '' then
            local add_wfp = {
                wfp_type = 1,
                cls = "Pre_Alloc_Container",
                obj_id = pac.id,
                obj_name = "预分配料箱'"..pac_no.."'-->回库处理",
                trigger_event = goback_event
            }
            nRet, strRetInfo = m3.AddSysWFP( strLuaDEID, add_wfp )
            if nRet ~= 0 then 
                return 2, "AddSysWFP失败!"..strRetInfo  
            end  
        end

        -- 增加一个后台进程对预分配料箱入库后对入库单的数据影响进行处理
        if inbound_post_event ~= '' then
            local add_wfp = {
                wfp_type = 1,
                cls = "Pre_Alloc_Container",
                obj_id = pac.id,
                obj_name = "预分配料箱'"..pac_no.."'-->回库处理",
                trigger_event = inbound_post_event
            }
            nRet, strRetInfo = m3.AddSysWFP( strLuaDEID, add_wfp )
            if nRet ~= 0 then 
                return 2, "AddSysWFP失败!"..strRetInfo  
            end  
        end        
    end   

    return 0, operation  
end

-- 入库波次完成后需要把入库波次明细中的入库数量批分到入库明细中的 F_ACC_I_QTY，F_ACC_C_QTY
-- 否则以入库单进行回报时会没有入库数量
-- @function wms_base.InboundWave_Finish_PostProce
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string wave_no 波次号
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string 失败时的错误信息
function wms_in.InboundWave_Finish_PostProce( strLuaDEID, wave_no )
    local nRet, strRetInfo, n, m

    if lua.StrIsEmpty( wave_no ) then
        return 1, "wms_base.InboundWave_Finish_PostProce 函数中 wave_no 不能为空!" 
    end

    local iw_detail_objs
    local strCondition = "S_WAVE_NO = '"..wave_no.."'"
    nRet, iw_detail_objs = m3.QueryDataObject(strLuaDEID, "IW_Detail", strCondition, "N_ROW_NO" )
    if nRet ~= 0 then
        return 1, "QueryDataObject失败!"..iw_detail_objs
    end

    if iw_detail_objs == '' then
        return 0
    end
    
    -- 获取入库单明细里的数量
    local inbound_order_objs
    nRet, inbound_order_objs = m3.QueryDataObject(strLuaDEID, "Inbound_Order", strCondition, "S_NO" )
    if nRet ~= 0 then
        return 1, "QueryDataObject失败!"..inbound_order_objs
    end

    if inbound_order_objs == '' then
        return 0
    end
    local io_no_set = {}        -- 入库单号
    local obj_attrs
    for n = 1, #inbound_order_objs do
        obj_attrs  = m3.KeyValueAttrsToObjAttr(inbound_order_objs[n].attrs)
        table.insert( io_no_set, obj_attrs.S_NO )
    end

    local io_detail_objs
    strCondition = "S_IO_NO IN ("..lua.strArray2string( io_no_set )..")"
    nRet, io_detail_objs = m3.QueryDataObject(strLuaDEID, "Inbound_Detail", strCondition, "S_ITEM_CODE" )
    if nRet ~= 0 then
        return 1, "QueryDataObject失败!"..io_detail_objs
    end

    if io_detail_objs == '' then
        return 0
    end
    local nCount = #io_detail_objs
    local io_detail_list = {}
    local qty, x_value

    for n = 1, nCount do
        obj_attrs = m3.KeyValueAttrsToObjAttr(io_detail_objs[n].attrs) 
        if obj_attrs == nil then
            return 1, "m3.KeyValueAttrsToObjAttr失败!"
        end
        local io_detail = {
            id = io_detail_objs[n].id,
            item_code = obj_attrs.S_ITEM_CODE,
            qty = lua.Get_NumAttrValue( obj_attrs.F_QTY ),
            in_qty = 0, cancel_qty = 0, ok = false
        }
        table.insert( io_detail_list, io_detail )
    end

    local cancel_qty, in_qty
    for n = 1, #iw_detail_objs do
        obj_attrs  = m3.KeyValueAttrsToObjAttr(iw_detail_objs[n].attrs)  
        -- 入库数量
        in_qty = lua.Get_NumAttrValue( obj_attrs.F_ACC_I_QTY )  
        -- 取消数量
        cancel_qty = lua.Get_NumAttrValue( obj_attrs.F_ACC_C_QTY )  
        -- 把 in_qty, cancel_qty 批分到 Inbound_Detail
        for m = 1, nCount do
            if io_detail_list[m].ok == false then
                if io_detail_list[m].item_code == obj_attrs.S_ITEM_CODE then
                    -- 批分入库数量
                    if in_qty > 0 then                        
                        x_value = io_detail_list[m].qty - io_detail_list[m].in_qty - io_detail_list[m].cancel_qty  -- 可以批分的入库数量
                        if in_qty > x_value then
                            qty = x_value
                        else
                            qty = in_qty
                        end
                        in_qty = in_qty - qty
                        io_detail_list[m].in_qty = io_detail_list[m].in_qty + qty 
                    end
                    -- 批分取消数量
                    if cancel_qty > 0 then                        
                        x_value = io_detail_list[m].qty - io_detail_list[m].in_qty - io_detail_list[m].cancel_qty  -- 可以批分的取消数量
                        if cancel_qty > x_value then
                            qty = x_value
                        else
                            qty = cancel_qty
                        end
                        cancel_qty = cancel_qty - qty
                        io_detail_list[m].cancel_qty = io_detail_list[m].cancel_qty + qty 
                    end
                    if io_detail_list[m].qty == (io_detail_list[m].in_qty+io_detail_list[m].cancel_qty) then
                        io_detail_list[m].ok = true
                    end
                end
            end
            if in_qty == 0 and cancel_qty == 0 then
                break
            end
        end
    end

    -- 更新入库单明细中的入库数量，取消数量
    local strSetAttr
    for n = 1, nCount do
        strCondition = "S_ID = '"..io_detail_list[n].id.."'"
        strSetAttr = "F_ACC_I_QTY = "..io_detail_list[n].in_qty..", F_ACC_C_QTY = "..io_detail_list[n].cancel_qty
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Inbound_Detail", strCondition, strSetAttr )
        if nRet ~= 0 then
            return 1, "updateDataAttrByCondition(Inbound_Detail)失败"..strRetInfo
        end
    end
    return 0
end

return wms_in
