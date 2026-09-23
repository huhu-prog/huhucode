--[[
    版本：     V2.0
    创建日期： 2025-1-26
    修改日期： 2026-6-17
    创建人：   HAN

    功能：
        和出库相关的所有操作，包括配盘、分拣、拣料箱、出库波次、缺件等

    ——————————————————————————————————
    导出函数列表（共 19 个）:
    ——————————————————————————————————

    【拣货规则/匹配规则】
        Get_OutboudOrder_MatchPickin_Rule       — 根据出库单号获取拣货规则、匹配规则及弱化策略
        Get_OutboudOrder_MatchPickin_Rule2      — 根据出库单数据对象获取拣货规则、匹配规则及弱化策略
        Get_Outbound_Wave_MatchPickin_Rule      — 根据出库波次号获取拣货规则、匹配规则及弱化策略

    【出库单】
        Get_Outbound_Detail_list                — 根据出库单编码获取出库单明细列表
        Sum_outbound_detail                     — 汇总出库单货品明细（相同货品数量累加）
        Shipping_Order_CheckState               — 检查发货单明细配盘是否全部完成（未完成）

    【配盘/分拣】
        Distribution                            — 给单个SKU分配库存生成配盘明细（核心函数）
        Distribution_Procedure                  — 出库分拣标准配货算法（核心函数）
        Split_Wave_DC_Detail                    — 波次配盘明细按出库单批分（核心函数）
        Check_Distribution_WholeOut             — 检测配盘是否为整托出
        Creat_Distribution_list                 — 创建配盘及配盘明细数据对象

    【配盘后处理】
        Distribution_CNTR_Detail_PostProcess    — 配盘明细后处理（更新量表/INV_Detail等）（核心函数）
        _Post_Picking_Operations                — 分拣后处理（回库事件/出库完成事件/异常处理）（核心函数）

    【拣料箱】
        Split_CD_Detial_ByPickingBox            — 按体积将配盘明细批分到拣料箱
        Creat_Picking_CNTR_Detail               — 创建拣料箱及拣料箱明细

    【出库波次】
        Create_Outbound_Wave                    — 根据出库单创建出库波次（核心函数）

    【缺件/检查】
        _Create_Shortage_Detail                 — 创建缺件清单
        _Check_INV_Alloc                        — 检查出库单/出库波次手工配盘结果

    【其他】
        Create_SOO_ByMaterial                   — 根据物料/货品号创建指定出库作业（未完成）

    ——————————————————————————————————

    更改记录:
    2025-1-26  HAN  创建
    2026-6-17  AI   统一为全部函数补充LDoc格式文档注释，更新文件头函数清单

    AI CHECK:
        -- 20260617 21:54
--]]

wms_cntr = require ("wms_container")
wms_wh   = require ("wms_wh")

local wms_out = {_version = "0.1.1"}

-- 从货主设置中获取拣货规则、匹配规则及匹配弱化策略
-- @function get_storer_match_picking_rule
-- @tparam string order_match_rule 订单匹配规则
-- @tparam string order_picking_rule 订单拣货规则
-- @tparam string order_mr_weaken 订单匹配属性弱化策略 Y/N
-- @tparam string storer 货主代码
-- @treturn number 0=成功
-- @treturn string default_match_rule 最终匹配规则
-- @treturn string default_picking_rule 最终拣货规则
-- @treturn string default_mr_weaken 是否启用匹配属性弱化策略 Y/N
local function get_storer_match_picking_rule( order_match_rule, order_picking_rule,  order_mr_weaken, storer )
    local nRet, storer_data
    local match_rule, picking_rule, mr_weaken = '','',''
    local default_picking_rule = ''
    local default_match_rule = ''
    local default_mr_weaken = ''        -- 是否启用匹配属性弱化策略
    
    if storer == '' then
        nRet, match_rule = wms_base.Get_sConst2("WMS_Default_Match_Rule")
        if nRet ~= 0 then
            match_rule = ''
        end
        nRet, picking_rule = wms_base.Get_sConst2("WMS_Default_Picking_Rule")
        if nRet ~= 0 then
            picking_rule = ''
        end        
        nRet, mr_weaken = wms_base.Get_sConst2("WMS_Default_MR_Weaken")
        if nRet ~= 0 then
            mr_weaken = ''
        end        
    else
        nRet, storer_data = m3.GetDataFromCache( "Storer", storer )
        if  nRet ~= 0  then
            return 2, storer_data
        end  
        match_rule = storer_data.S_MATCH_RULE or ''
        picking_rule = storer_data.S_PICKING_RULE or ''
        mr_weaken = storer_data.C_MR_WEAKEN or ''
    end

    if order_match_rule ~= '' then
        default_match_rule = order_match_rule    
    else
        default_match_rule = match_rule
    end   

    if order_picking_rule ~= '' then
        default_picking_rule = order_picking_rule    
    else
        default_picking_rule = picking_rule
    end   

    if order_mr_weaken ~= '' then
        default_mr_weaken = order_mr_weaken    
    else
        default_mr_weaken = mr_weaken
    end   
    
    return 0, default_match_rule, default_picking_rule, default_mr_weaken         
end
-- 根据出库单号获取拣货规则、匹配规则及是否启用匹配弱化策略
-- 从出库单和货主设置中合并出最终的拣货规则和匹配规则（出库单优先）
-- @function wms_out.Get_OutboudOrder_MatchPickin_Rule
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string oo_no 出库单号, 必须有值
-- @treturn number 0=成功, 1=参数错误, 2=查询失败
-- @treturn string default_match_rule 匹配规则
-- @treturn string default_picking_rule 拣货规则
-- @treturn string default_mr_weaken 是否启用匹配属性弱化策略 Y/N
function wms_out.Get_OutboudOrder_MatchPickin_Rule( strLuaDEID, oo_no )
    local nRet
    -- 获取出库单的拣货规则，匹配规则
    local outbound_order
    local default_picking_rule = ''
    local default_match_rule = ''
    local default_mr_weaken = ''        -- 是否启用匹配属性弱化策略

    if lua.StrIsEmpty( oo_no ) then
        return 1, "wms_out.Get_OutboudOrder_MatchPickin_Rule 函数输入参数不合规, oo_no 必须有值!"
    end
    local strCondition = "S_NO = '"..oo_no.."'"
    nRet, outbound_order = m3.GetDataObjByCondition(strLuaDEID, "Outbound_Order", strCondition)
    if nRet ~= 0 then
        return 2, "获取出库单信息失败!" .. outbound_order
    end    
    local order_match_rule =  outbound_order.match_rule or ''
    local order_picking_rule = outbound_order.picking_rule or ''
    local order_mr_weaken = outbound_order.mr_weaken or ''
    local storer = outbound_order.storer or ''

    nRet, default_match_rule, default_picking_rule, default_mr_weaken = get_storer_match_picking_rule( order_match_rule, order_picking_rule,  order_mr_weaken, storer )
    if nRet ~= 0 then
        return 2, default_match_rule
    end
    return 0, default_match_rule, default_picking_rule, default_mr_weaken         
end

-- 根据出库单数据对象获取拣货规则、匹配规则及是否启用匹配弱化策略
-- 与 Get_OutboudOrder_MatchPickin_Rule 功能相同，差别在于输入参数为出库单数据对象而非出库单号
-- @function wms_out.Get_OutboudOrder_MatchPickin_Rule2
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table outbound_order 出库单数据对象, 必须包含 match_rule, picking_rule, mr_weaken, storer 属性
-- @treturn number 0=成功, 1=参数错误, 2=查询失败
-- @treturn string default_match_rule 匹配规则
-- @treturn string default_picking_rule 拣货规则
-- @treturn string default_mr_weaken 是否启用匹配属性弱化策略 Y/N
function wms_out.Get_OutboudOrder_MatchPickin_Rule2( strLuaDEID, outbound_order )
    local nRet
    -- 获取出库单的拣货规则，匹配规则

    local default_picking_rule = ''
    local default_match_rule = ''
    local default_mr_weaken = ''        -- 是否启用匹配属性弱化策略

    if lua.isTableEmpty( outbound_order ) then
        return 1, "wms_out.Get_OutboudOrder_MatchPickin_Rule2 函数输入参数不合规, outbound_order 必须有值!"
    end
  
    local order_match_rule =  outbound_order.match_rule or ''
    local order_picking_rule =  outbound_order.picking_rule or ''
    local order_mr_weaken =  outbound_order.mr_weaken or ''
    local storer = outbound_order.storer or ''

    nRet, default_match_rule, default_picking_rule, default_mr_weaken = get_storer_match_picking_rule( order_match_rule, order_picking_rule,  order_mr_weaken, storer )
    if nRet ~= 0 then
        return 2, default_match_rule
    end
    return 0, default_match_rule, default_picking_rule, default_mr_weaken         
end

-- 根据出库波次号获取拣货规则、匹配规则及是否启用匹配弱化策略
-- 从出库波次和货主设置中合并出最终的拣货规则和匹配规则（波次优先）
-- @function wms_out.Get_Outbound_Wave_MatchPickin_Rule
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string ow_no 出库波次号, 必须有值
-- @treturn number 0=成功, 1=参数错误, 2=查询失败
-- @treturn string default_match_rule 匹配规则
-- @treturn string default_picking_rule 拣货规则
-- @treturn string default_mr_weaken 是否启用匹配属性弱化策略 Y/N
function wms_out.Get_Outbound_Wave_MatchPickin_Rule( strLuaDEID, ow_no )
    local nRet
    -- 获取出库单的拣货规则，匹配规则
    local outbound_wave
    local default_picking_rule = ''
    local default_match_rule = ''
    local default_mr_weaken = ''        -- 是否启用匹配属性弱化策略

    if lua.StrIsEmpty( ow_no ) then
        return 1, "wms_out.Get_Outbound_Wave_MatchPickin_Rule 函数输入参数不合规, ow_no 必须有值!"
    end
    local strCondition = "S_WAVE_NO = '"..ow_no.."'"
    nRet, outbound_wave = m3.GetDataObjByCondition(strLuaDEID, "Outbound_Wave", strCondition)
    if nRet ~= 0 then
        return 2, "获取出库单信息失败!" .. outbound_wave
    end    
    local order_match_rule =  outbound_wave.match_rule or ''
    local order_picking_rule = outbound_wave.picking_rule or ''
    local order_mr_weaken = outbound_wave.mr_weaken or ''
    local storer = outbound_wave.storer or ''
    nRet, default_match_rule, default_picking_rule, default_mr_weaken = get_storer_match_picking_rule( order_match_rule, order_picking_rule,  order_mr_weaken, storer )
    if nRet ~= 0 then
        return 2, default_match_rule
    end
    return 0, default_match_rule, default_picking_rule, default_mr_weaken        
end

-- 检查发货单明细的配盘是否全部完成
-- 如果所有明细的配货量(ACC_D_QTY) >= 需求量(QTY)，则更新发货单状态为已完成(N_B_STATE=1)
-- ** 此函数尚未完成实现，暂不可用 **
-- @function wms_out.Shipping_Order_CheckState
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string shipping_no 发货单号, 必须有值
-- @treturn number 0=成功, 1=失败
-- @treturn string|nil 错误信息, 成功时 nil
--[[
-- 没用，以后有时间完善
function wms_out.Shipping_Order_CheckState ( strLuaDEID, shipping_no ) 
    local n, nRet, strRetInfo

    -- 获取【发货单明细】
    local strCondition = "S_SHIPPING_NO = '"..shipping_no.."'"
    local strOrder = ""
    local data_objs
    local distribution_finish = true

    nRet, data_objs = m3.QueryDataObject( strLuaDEID, "Shipping_Detail", strCondition, strOrder )
    if nRet ~= 0 then
        return 1, "获取【Shipping_Detail】信息失败! " .. data_objs
    end
    local obj_attrs
    local qty, acc_d_qty

    for n = 1, #data_objs do
        obj_attrs = m3.KeyValueAttrsToObjAttr(data_objs[n].attrs)
        qty = lua.StrToNumber( obj_attrs.F_QTY )
        acc_d_qty = lua.StrToNumber( obj_attrs.F_ACC_D_QTY )
        if   qty > acc_d_qty  then
            distribution_finish = false
            break
        end
    end
    if  distribution_finish  then
        local strUpdateSql = "N_B_STATE = 1"
        strCondition = "S_NO = '"..shipping_no.."'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Shipping_Order", strCondition, strUpdateSql )
        if nRet ~= 0 then
            return 1, "更新【发货单】信息失败!"..strRetInfo
        end
    end
    return 0
end 
]]

-- 检测配盘是否为整托出
-- 判断依据：容器中所有货品的库存数量是否都小于等于本次配盘的出库数量
-- @function wms_out.Check_Distribution_WholeOut
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table distribution_cntr 配盘数据对象, 必须包含 dc_no 和 cntr_code 属性
-- @treturn number 0=成功, 1=参数不合规, 2=查询失败
-- @treturn string "yes"=整托出, "no"=非整托出, 或错误信息
function wms_out.Check_Distribution_WholeOut( strLuaDEID, distribution_cntr )
    local nRet
    
    if  distribution_cntr == nil or type(distribution_cntr) ~= 'table'  then
        return 1, "wms_out.Check_Distribution_WholeOut 函数中 distribution 不能为空,必须为table!"
    end

    -- 获取【配盘明细】
    local data_objects
    local strCondition = "S_DC_NO = '"..distribution_cntr.dc_no.."'"
    nRet, data_objects = m3.QueryDataObject(strLuaDEID, "Distribution_CNTR_Detail", strCondition, "S_ITEM_CODE" )
    if nRet ~= 0 then
        return 2, "QueryDataObject失败!"..data_objects
    end
    if data_objects == '' then
        return 0, "no"
    end
    local dc_detail = {}
    for n = 1, #data_objects do
        dc_detail[n] = m3.KeyValueAttrsToObjAttr(data_objects[n].attrs)
    end

    -- 获取【INV_Detail】
    strCondition = "S_CNTR_CODE = '"..distribution_cntr.cntr_code.."'"
    nRet, data_objects = m3.QueryDataObject(strLuaDEID, "INV_Detail", strCondition, "S_ITEM_CODE" )
    if nRet ~= 0 then
        return 2, "QueryDataObject失败!"..data_objects
    end
    if data_objects == '' then
        return 0, "no"
    end
    local obj_attrs

    if  #data_objects > #dc_detail  then 
        -- 如果容器中的货品条数 > 配盘明细 肯定不是整托出
        return 0, "no"
    end

    -- 遍历 容器货品明细 判断：inv_detail.qty - dc_detail.qty = 0
    local inv_detail_qty, dc_detail_qty
    local count = #dc_detail
    for n = 1, #data_objects do
        obj_attrs = m3.KeyValueAttrsToObjAttr(data_objects[n].attrs)
        if obj_attrs == nil then
            return 1, "m3.KeyValueAttrsToObjAttr失败!"
        end
        inv_detail_qty = lua.StrToNumber( obj_attrs.F_QTY )
        -- 从【Distribution_CNTR_Detail】找到 cg_detial.S_ID 相同的 配盘明细
        for i = 1, count do
            if dc_detail[i].G_INV_DETAIL_ID == data_objects[n].id then
                dc_detail_qty = lua.StrToNumber( dc_detail[i].F_QTY )
                if  inv_detail_qty > dc_detail_qty  then
                    -- 如果容器货品中的数量大于本次配盘出库数量，说明出不完，不是整托出
                    return 0, "no"
                end
                break
            end
        end
    end
    return 0, "yes"
end

-- 获取出库单明细列表
-- 支持单个或多个出库单编码，返回匹配的出库单明细对象列表
-- @function wms_out.Get_Outbound_Detail_list
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table oo_no_set 出库单编码数组 {"OO010","OO012",...}, 不能为空
-- @treturn number 0=成功, 1=参数错误或查询失败
-- @treturn table outbound_detail_list 出库单明细列表 table
function wms_out.Get_Outbound_Detail_list( strLuaDEID, oo_no_set )
    local nRet, strRetInfo
    local where, nCount
    local outbound_detail_list = {}

    nCount = #oo_no_set
    if  nCount == 0  then
        return 1, "出库单编码不能为空!"
    end
    if  nCount == 1  then
        where = " S_OO_NO = '"..oo_no_set[1].."'"
    else
        where = " S_OO_NO IN ("
        for n = 1, nCount do
            where = where.."'"..oo_no_set[n].."',"
        end
        where = lua.trim_laster_char( where )..")"
    end

    local strOrder = "S_ITEM_CODE"
    
    nRet, strRetInfo = mobox.queryDataObjAttr( strLuaDEID, "Outbound_Detail", where, strOrder )
    if nRet ~= 0 then
        return 1, "获取【发货单明细】失败! "..strRetInfo
    end
    -- 如果没有满足条件的出库单明细就直接返回
    if strRetInfo == '' then
        return 0, outbound_detail_list
    end

    local retObjs = json.decode( strRetInfo )
    local outbound_detail

    for n = 1, #retObjs do
        nRet, outbound_detail = m3.ObjAttrStrToLuaObj( "Outbound_Detail", lua.table2str(retObjs[n].attrs) )   
        table.insert( outbound_detail_list, outbound_detail )
    end 
    return 0, outbound_detail_list
end

-- 获取出库波次明细的合并明细列表
-- 查询波次明细的 compose_list 属性，用于配盘明细的批次分配
-- @function get_wave_detail_compose
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string wave_no 出库波次号
-- @tparam number row_no 波次明细行号
-- @treturn number 0=成功, 其他值=失败
-- @treturn table|string compose_list 合并明细列表或错误信息
local function get_wave_detail_compose( strLuaDEID, wave_no, row_no )
    local strCondition
    local nRet, data_objs
    local compose_list = {}

    strCondition = "S_WAVE_NO = '"..wave_no.."' AND N_WAVE_ROW_NO = "..row_no
    nRet, data_objs = m3.QueryDataObject(strLuaDEID, "Outbound_Detail", strCondition, "S_OO_NO" )
    if nRet ~= 0 then 
        return 2, "QueryDataObject失败!"..data_objs 
    end   
    local detail_attrs
    for n = 1, #data_objs do
        detail_attrs = m3.KeyValueAttrsToObjAttr(data_objs[n].attrs)
        if detail_attrs == nil then
            return 1, "转换属性失败!"
        end  
        local compose = {
            oo_no = detail_attrs.S_OO_NO,
            row_no = lua.Get_NumAttrValue( detail_attrs.N_ROW_NO ),
            qty = lua.Get_NumAttrValue( detail_attrs.F_QTY ),
            alloc_qty = 0,
            detail_attrs = detail_attrs
        }
        table.insert( compose_list, compose )
    end
    return 0, compose_list
end

-- 将出库波次的配盘明细根据出库单进行批分
-- 对于波次合并场景，将汇总的配盘明细按比例拆分回各个出库单；未合并场景直接复制并关联对应出库单
-- @function wms_out.Split_Wave_DC_Detail
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string wave_no 出库波次号, 必须有值
-- @tparam table dc_detail_data_list 配盘明细列表
-- @treturn number 0=成功, 1=失败
-- @treturn table 重新批分后的配盘明细列表, 或错误信息字符串
function wms_out.Split_Wave_DC_Detail( strLuaDEID, wave_no, dc_detail_data_list )
    local nRet, strRetInfo
    local ow_detail_list = {}
    local new_dc_detail_list = {}
  
    if wave_no == nil or wave_no == '' then
        return 1, "wms_out.Split_Wave_DC_Detail 输入参数 wave_no 必须有值!"
    end
    if lua.IsTableEmpty( dc_detail_data_list ) then
        return 1, "wms_out.Split_Wave_DC_Detail 输入参数 dc_detail_data_list 必须有值!"
    end

    -- 获取波次出库明细
    local strCondition = "S_WAVE_NO = '"..wave_no.."'"
    local queryInfo
    nRet, queryInfo = m3.QueryDataObjAttr2(strLuaDEID, "OW_Detail", strCondition, "N_ROW_NO" )
    if nRet ~= 0 then 
        return 2, "QueryDataObjAttr2 失败!"..queryInfo 
    end  

    local nPageCount = queryInfo.pageCount
    local nPage = 1
    local dataSet = queryInfo.dataSet       -- 查询出来的数据集
    local ow_detail
    local row_no
    while (nPage <= nPageCount) do
        for n = 1, #dataSet do
            ow_detail = m3.KeyValueAttrsToObjAttr(dataSet[n].attrs)
            if ow_detail == nil then
                return 1, "m3.KeyValueAttrsToObjAttr 转换失败!"
            end
            row_no = lua.Get_NumAttrValue( ow_detail.N_ROW_NO )
            if row_no <= 0 then
                return 2, "出库波次明细中行号非法!"
            end
            ow_detail.compose_list = {}     -- 合并的出库单明细
            ow_detail_list[row_no] = ow_detail
        end        

        nPage = nPage + 1
        if  nPage <= nPageCount  then
            -- 取下一页
            nRet, strRetInfo = mobox.queryDataObjAttr2( strLuaDEID, nPage)
            if  nRet ~= 0  then
                lua.Stop( strLuaDEID, "queryDataObjAttr2失败! nPage="..nPage.."  "..strRetInfo )
                return
            end 
            queryInfo = json.decode(strRetInfo) 
            dataSet = queryInfo.dataSet              
        end
    end    
  
    -- 开始批分
    local qty, split_qty
    local compose_list
    local dc_detail_base_attrs_count = #DC_DETAIL_BASE_ATTRS

    for _, dc_detail in ipairs( dc_detail_data_list ) do
        -- row_no 出库波次明细行号
        row_no = lua.Get_NumAttrValue( dc_detail.N_BS_ROW_NO )
        if row_no <= 0 then
            return 3, "出库波次明细行号不能为空!"
        end
        ow_detail = ow_detail_list[row_no]
        if ow_detail == nil then
            return 2, "出库波次明细不存在! 行号 = "..row_no
        end
        if ow_detail.S_OO_NO == '' then
            -- 说明有合并
            qty = lua.Get_NumAttrValue( dc_detail.F_QTY )   
            if lua.isTableEmpty( ow_detail.compose_list ) then
                nRet, compose_list = get_wave_detail_compose( strLuaDEID, wave_no, row_no )
                if nRet ~= 0 then
                    return 2, "get_wave_detail_compose 失败!"..compose_list
                end
                ow_detail.compose_list = compose_list
            end
            -- 把 qty 这个量批分给 compos_list 里的出库单明细
            for _, compose in ipairs( ow_detail.compose_list ) do
                local can_alloc_qty = compose.qty - compose.alloc_qty

                if can_alloc_qty > 0 then
                    if qty > can_alloc_qty then
                        compose.alloc_qty = compose.qty
                        qty = qty - can_alloc_qty
                        split_qty = can_alloc_qty
                    else
                        compose.alloc_qty = compose.alloc_qty + qty
                        split_qty = qty
                        qty = 0
                    end

                    -- 新建dc_detail
                    local new_dc_detail = lua.table_deepcopy( dc_detail )
                    for i = 1, dc_detail_base_attrs_count do
                        new_dc_detail[DC_DETAIL_BASE_ATTRS[i]] = compose.detail_attrs[DC_DETAIL_BASE_ATTRS[i]]
                    end                    
                    new_dc_detail.S_BS_TYPE = "Outbound_Order"
                    new_dc_detail.S_BS_NO = compose.oo_no
                    new_dc_detail.N_BS_ROW_NO = compose.row_no
                    new_dc_detail.S_WAVE_NO = wave_no    
                    new_dc_detail.N_WAVE_ROW_NO = row_no
                    new_dc_detail.F_QTY = split_qty
                    table.insert( new_dc_detail_list, new_dc_detail )    
                    
                end

                if qty == 0 then
                    break
                end
            end

            if qty > 0 then
                return 2, "出库波次明细行 "..row_no.." 批分失败!"
            end
        else
            -- 不需要批分的出库波次明细
            local new_dc_detail = lua.table_deepcopy( dc_detail )

            new_dc_detail.S_BS_TYPE = "Outbound_Order"
            new_dc_detail.S_BS_NO = ow_detail.S_OO_NO
            new_dc_detail.N_BS_ROW_NO = ow_detail.N_OO_ROW_NO
            new_dc_detail.S_WAVE_NO = wave_no    
            new_dc_detail.N_WAVE_ROW_NO = row_no

            table.insert( new_dc_detail_list, new_dc_detail )
        end
    end
    return 0, new_dc_detail_list
end

-- 匹配容器中存储的货品明细，执行配盘分配逻辑
-- 核心匹配函数：遍历库存容器，按拣货规则和匹配规则将出库需求分配到容器中，支持外深位优先、空闲容器优先等特殊优先级策略
-- @function inv_match
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table|nil special_priority 特殊优先级配置 {
--   front_location_first = true/false -- 外深位优先（双深位仓库使用）
--   no_operation_first = true/false -- 没作业的容器优先
-- }
-- @tparam table parameter 配盘参数
-- @tparam table item 出库单明细数据对象
-- @tparam string strTable 库存明细表名
-- @tparam string strAttrs 查询属性列表
-- @tparam string strCondition 查询条件
-- @tparam string inv_order 库存排序规则
-- @tparam table d_cntr_list 配盘链表
-- @tparam table d_cntr_detail_list 配盘明细链表
-- @tparam table in_op_cntr_list 作业中容器列表
-- @treturn number 0=匹配完成
local function inv_match( strLuaDEID, special_priority, parameter, item, strTable, strAttrs, strCondition, 
                          inv_order, d_cntr_list, d_cntr_detail_list, in_op_cntr_list )
    local nRet, strRetInfo, strUpdateSql

    -- 默认不设置深位优先
    local front_location_first = false
    if special_priority ~= nil then
        if special_priority.front_location_first ~= nil and type(special_priority.front_location_first) == "boolean" then
            front_location_first = special_priority.front_location_first
        end
    end
    -- 默认不设置没作业的容器优先命中
    local no_operation_first = false
    if special_priority ~= nil then
        if special_priority.no_operation_first ~= nil and type(special_priority.no_operation_first) == "boolean" then
            no_operation_first = special_priority.no_operation_first
        end
    end
    
    -- step2.2 多表联查获取容器货品信息
    nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 1000, strCondition, inv_order )  
    if nRet ~= 0 then 
        return 2, "查询【容器货品明细】信息失败! " .. strRetInfo  
    end
    local inv_detail_set
    local INV_DETAIL_BASE_ATTRS_COUNT = #INV_DETAIL_BASE_ATTRS
    local UDF_ATTRS_COUNT = #UDF_ATTRS    
    local DC_DETAIL_ATTRS_COUNT = #DC_DETAIL_ATTRS
    local cntr_code
    local index, qty, need_qty, bFind

    if strRetInfo ~= '' then
        local out_inv_txn_udfattr_def = parameter.out_inv_txn_udfattr_def or {}
        inv_detail_set = json.decode(strRetInfo)  

        -- 数据转化 inv_detail_set --> inv_detail_data_set
        local inv_detail_data_set = {}
        local order = 1
        for _, inv_detail in ipairs( inv_detail_set ) do
            -- 获取查询获取的 INV_Detail 中的属性 和 strAttr的顺序有关系
            local inv_detail_data = {}
            inv_detail_data.S_ID = inv_detail[1]
            inv_detail_data.S_WH_CODE = inv_detail[2]
            inv_detail_data.S_AREA_CODE = inv_detail[3]
            inv_detail_data.S_LOC_CODE = inv_detail[4]
            inv_detail_data.pos = 1         -- 深位信息 1 -- 外深位 2 -- 内深位（如果单深位仓库，则pos=1）
            inv_detail_data.order = order
            order = order + 1
            index = 5
            for m = 1, INV_DETAIL_BASE_ATTRS_COUNT do
                inv_detail_data[INV_DETAIL_BASE_ATTRS[m]] = inv_detail[index]
                index = index + 1
            end
            for m = 1, UDF_ATTRS_COUNT do
                inv_detail_data[UDF_ATTRS[m]] = inv_detail[index]
                index = index + 1                    
            end
            table.insert( inv_detail_data_set, inv_detail_data )
        end

        -- 如果是双深位仓库，出库分拣时要优先考虑外深位
        if front_location_first then
            local loc
            for _, inv_detail_data in ipairs( inv_detail_data_set ) do 
                -- 获取货位信息直接从内存获取
                nRet, loc = wms_wh.GetLocInfo( inv_detail_data.S_LOC_CODE )
                if nRet ~= 0 then
                    return 2, "获取货位'"..inv_detail_data.S_LOC_CODE.."'信息失败!"..loc
                end
                inv_detail_data.pos = lua.Get_NumAttrValue( loc.pos )
                -- 获取分拣规则中进行排序的字段值值
                local order_attr_value = ""
                for _, attr in ipairs( parameter.picking_rule_attrs ) do
                    order_attr_value = order_attr_value..inv_detail_data[attr].."-"
                end
                inv_detail_data.order_attr_value = lua.trim_laster_char( order_attr_value )
            end     
            -- 相同的 order_attr_value 排序值一样
            order = 1
            local order_attr_value = ''
            for _, inv_detail_data in ipairs( inv_detail_data_set ) do 
                if order_attr_value == '' then
                    inv_detail_data.order = order
                    order_attr_value = inv_detail_data.order_attr_value
                elseif inv_detail_data.order_attr_value == order_attr_value then
                    inv_detail_data.order = order
                else
                    order = order + 1
                    inv_detail_data.order = order
                    order_attr_value = inv_detail_data.order_attr_value 
                end
            end

            -- 根据 order_attr_value + pos 进行排序，外深位pos=1，内深位=2, 排序后相同的order_attr_value外深位会在前面
            table.sort( inv_detail_data_set, function(a, b)
                                                if a.order == b.order then
                                                    return a.pos < b.pos
                                                else
                                                    return a.order < b.order
                                                end
                                             end
                    )    
        end
        -- 如果要判断没作业的料箱优先
        if no_operation_first then
            for _, inv_detail_data in ipairs( inv_detail_data_set ) do 
                if lua.IsInTable( inv_detail_data.S_CNTR_CODE, in_op_cntr_list ) then
                    inv_detail_data.op = 1      -- 料箱有作业在做
                else
                    inv_detail_data.op = 2      -- 料箱没作业在做
                end
            end
            -- 排序，有作业的靠后
            table.sort( inv_detail_data_set, function(a, b)
                                                if a.order == b.order then
                                                    if a.pos == b.pos then
                                                        return a.op > b.op  -- 没作业的料箱优先
                                                    else
                                                        return a.pos < b.pos
                                                    end
                                                else
                                                    return a.order < b.order
                                                end
                                             end
                    ) 
        end
        -- step2.3 根据出库数量遍历2.2获取的容器货品信息进行数量批分
        -- item.qty --> 需要出库的数量  item.alloc_qty --> 已经配货数量
        for _, inv_detail_data in ipairs( inv_detail_data_set ) do
            -- step2.3.1 配货数量已经到达出库数量
            if  lua.equation( item.qty, item.alloc_qty )  then 
                break 
            end

            -- 容器中可用于配货的数量
            qty = lua.StrToNumber( inv_detail_data.F_QTY_VALID )
            need_qty = item.qty - item.alloc_qty   

            -- 把容器加入 配货容器 清单
            -- step2.3.3  检查一下容器是否已经在 d_cntr_list, 如果不存在要把 容器加入 d_cntr_lis
            cntr_code = inv_detail_data.S_CNTR_CODE
            bFind = false
            for i = 1, #d_cntr_list do
                if  lua.Normalize_String( d_cntr_list[i].S_CNTR_CODE ) == lua.Normalize_String( cntr_code )  then
                    bFind = true 
                    break 
                end
            end
            if  bFind == false  then
                -- 初始化【配盘】容器信息
                local distribution_cntr =  m3.AllocObject2(strLuaDEID, "Distribution_CNTR")
                distribution_cntr.S_FACTORY = parameter.factory
                distribution_cntr.S_BS_TYPE = parameter.bs_type
                distribution_cntr.S_BS_NO = parameter.bs_no
                distribution_cntr.S_OUT_OP_NAME = parameter.cntr_out_op_def or ''
                distribution_cntr.S_BACK_OP_NAME = parameter.cntr_back_op_def or ''

                distribution_cntr.S_CNTR_CODE = cntr_code
                distribution_cntr.N_B_STATE = DIST_CNTR_STATE.PrePickingOK
                distribution_cntr.S_WH_CODE = inv_detail_data.S_WH_CODE
                distribution_cntr.S_AREA_CODE = inv_detail_data.S_AREA_CODE
                distribution_cntr.S_LOC_CODE = inv_detail_data.S_LOC_CODE               
                distribution_cntr.S_EXIT_AREA_CODE = ''
                distribution_cntr.S_EXIT_LOC_CODE = ''
                distribution_cntr.S_STATION_NO = parameter.station or ''
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

            -- step2.3.4 批分容器配盘数量
            local d_qty
            if  need_qty > qty  then
                d_qty = qty
            else
                d_qty = need_qty
            end
            if  d_qty > 0  then 
                item.alloc_qty = item.alloc_qty + d_qty
                -- step2.3.5 生成 配盘明细并且加入配盘明细清单
                local d_cntr_detail = m3.AllocObject2(strLuaDEID, "Distribution_CNTR_Detail")

                d_cntr_detail.G_INV_DETAIL_ID = inv_detail_data.S_ID
                d_cntr_detail.S_PICK_BOX_CODE = item.S_PICK_BOX_CODE              -- 拣料箱编码
                d_cntr_detail.S_PUT_WALL_NO = item.S_PUT_WALL_NO                  -- 播种墙位置(location)
                d_cntr_detail.S_MATCH_RULE = item.S_MATCH_RULE                    -- 货品出库匹配规则
                d_cntr_detail.S_STATION_NO = parameter.station

                for m = 1, DC_DETAIL_ATTRS_COUNT do
                    d_cntr_detail[DC_DETAIL_ATTRS[m]] = inv_detail_data[DC_DETAIL_ATTRS[m]]
                end

                -- 如果有定义 出库交易日志 特别属性设置的，需要把相关的扩展属性换成 出库单明细里的属性
                for _, udf_attr in ipairs( out_inv_txn_udfattr_def ) do
                    d_cntr_detail[udf_attr] = item[udf_attr]
                end

                d_cntr_detail.F_QTY = d_qty     
                -- V3.0 
                d_cntr_detail.S_BS_TYPE = parameter.bs_type
                d_cntr_detail.S_BS_NO = parameter.bs_no
                d_cntr_detail.N_BS_ROW_NO = item.N_ROW_NO                 
                if parameter.bs_type == "Outbound_Wave" then
                    if parameter.sorting then
                        -- 根据出库单进行分拣
                        if not parameter.qty_sum then
                            d_cntr_detail.S_BS_TYPE = "Outbound_Order"
                            d_cntr_detail.S_BS_NO = item.S_OO_NO
                            d_cntr_detail.N_BS_ROW_NO = item.N_OO_ROW_NO
                            d_cntr_detail.S_WAVE_NO = parameter.bs_no
                            d_cntr_detail.N_WAVE_ROW_NO = item.N_ROW_NO
                        end
                    end
                end
                table.insert( d_cntr_detail_list, d_cntr_detail )

                -- INV_Detail 的 + F_ALLOC_QTY，并且创建库存锁定日志
                nRet, strRetInfo = wms_inv.INV_Detail_Add_AllocQty( strLuaDEID, inv_detail_data, d_qty, parameter.bs_type, parameter.bs_no )
                if nRet ~= 0 then 
                    return 2, "wms_inv.INV_Detail_Add_AllocQty 失败!"..strRetInfo
                end
                -- 因为有些配盘是异常出库造成的配盘，这个时候出库单你的配盘数量已经在上一次配盘中进行了分配
                if not parameter.anomaly_distribution then
                    -- 如果是正常的配盘需要给出库单加配盘数量
                    -- 入库单明细/入库波次明细 货品的累计配货数量 + d_qty
                    if parameter.bs_type == "Outbound_Wave" then
                        strCondition = "S_WAVE_NO = '"..parameter.bs_no.."' AND N_ROW_NO = "..item.N_ROW_NO
                        strUpdateSql = "F_ACC_D_QTY = F_ACC_D_QTY + "..d_qty
                        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "OW_Detail", strCondition, strUpdateSql )
                        if  nRet ~= 0  then  
                            return 2, "更新【波次明细】信息失败!"..strRetInfo  
                        end   

                        -- 如果 S_OO_NO. N_OO_ROW_NO 有值说明出库波次没合并出库明细
                        local oo_no = item.S_OO_NO or ''
                        local oo_row_no = lua.StrToNumber( item.N_OO_ROW_NO )
                        if oo_no ~= '' and oo_row_no > 0 then
                            strCondition = "S_OO_NO = '"..oo_no.."' AND N_ROW_NO = "..oo_row_no
                            strUpdateSql = "F_ACC_D_QTY = F_ACC_D_QTY + "..d_qty
                            nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Outbound_Detail", strCondition, strUpdateSql )
                            if nRet ~= 0 then  
                                return 2, "更新【入库单明细】信息失败!"..strRetInfo  
                            end                              
                        end

                    elseif parameter.bs_type == "Outbound_Order" then
                        strCondition = "S_OO_NO = '"..parameter.bs_no.."' AND N_ROW_NO = "..item.N_ROW_NO
                        strUpdateSql = "F_ACC_D_QTY = F_ACC_D_QTY + "..d_qty
                        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Outbound_Detail", strCondition, strUpdateSql )
                        if  nRet ~= 0  then  
                            return 2, "更新【入库单明细】信息失败!"..strRetInfo  
                        end                           
                    end
                end
            end
        end          
    end
    return 0
end

-- 生成库存明细匹配的 SQL 条件语句
-- 根据货品和匹配属性构建 WHERE 条件，支持属性值为空时的特殊匹配逻辑
-- @function get_inv_detail_match_sql
-- @tparam table item 货品明细数据对象
-- @tparam table match_attrs 匹配属性列表
-- @tparam number attrs_count 属性数量
-- @tparam boolean attr_null_in_condition 是否允许属性值为空时仍参与匹配
-- @treturn string item_sql 生成的 SQL 条件语句
local function get_inv_detail_match_sql( item, match_attrs, attrs_count, attr_null_in_condition )
    local value
    local item_sql =  " a.S_ITEM_CODE = '"..item.S_ITEM_CODE.."' AND a.S_ITEM_STATE = '"..item.S_ITEM_STATE.."' AND a.S_STORER = '"..item.S_STORER.."' "

    if attrs_count == 0 then
        return item_sql
    end

    local is_null_in_cond
    for n = 1, attrs_count do
        -- 匹配规则里的属性没值就不做判断，比如批次号为空的就不做判断
        local attr = match_attrs[n]
        value = item[attr] or ''
        if value ~= '' then
            item_sql = item_sql.." AND a."..attr.." = '"..item[attr].."' "
        else
            -- MDF BY HAN @20251107 判断值为空的时候是否一定要判断
            is_null_in_cond = attr_null_in_condition[attr] or false
            if is_null_in_cond then
                item_sql = item_sql.." AND a."..attr.." = '' "
            end            
        end
    end
    return item_sql
end

-- 通过弱化匹配规则进行配盘处理
-- 当常规匹配规则无法满足配盘需求时，逐步放宽匹配规则（弱化策略）进行二次匹配
-- @function do_distribution_by_weaken_match_rule
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table parameter 配盘参数
-- @tparam table item 出库单明细数据对象
-- @tparam string strTable 库存表名
-- @tparam string strAttrs 查询属性列表
-- @tparam string str_loc_where 库位过滤条件
-- @tparam string default_match_rule 默认匹配规则
-- @tparam string default_picking_rule 默认拣货规则
-- @tparam table d_cntr_list 配盘链表
-- @tparam table d_cntr_detail_list 配盘明细链表
-- @tparam table in_op_cntr_list 作业中容器列表
-- @treturn number 0=处理完成
local function do_distribution_by_weaken_match_rule( strLuaDEID, parameter, item, strTable, strAttrs, str_loc_where, 
                                                     default_match_rule, default_picking_rule, 
                                                     d_cntr_list, d_cntr_detail_list, in_op_cntr_list )
    local nRet, strRetInfo
    local match_rule, picking_rule
    local lua_info
    nRet, lua_info = lua.GetLuaDEInfo( strLuaDEID )
    if nRet ~= 0 then
        return 1, "GetLuaDEInfo 失败!"..lua_info
    end

    -- 获取匹配策略
    match_rule = item.S_MATCH_RULE or ''
    if match_rule == '' then
        match_rule = default_match_rule
    end
    if match_rule == '' then
        return 0
    end
    local match_attrs = lua.split( match_rule, ';' )
    -- 特殊优先级
    local special_priority = {
            front_location_first = parameter.front_location_first or false,   -- 是否启用外深位库位优先
            no_operation_first = parameter.no_operation_first or false,
    }

    -- MDF BY HAN @20251107
    nRet, strRetInfo = mobox.getClassAttrDef( "INV_detail", lua.table2str( match_attrs ))
    if nRet ~= 0 then
        return 1, strRetInfo
    end
    if strRetInfo == '' then
        return 1, "getClassAttrDef 函数返回空值!"
    end
    local success, attr_def_set
    success, attr_def_set = pcall( json.decode, strRetInfo )
    if not success then
        return 1, "getClassAttrDef 函数返回的字符串格式不对!"..strRetInfo
    end
    local attr_null_in_condition = {}
    for _, attr_def in ipairs( attr_def_set ) do
        attr_null_in_condition[attr_def.name] = attr_def.is_null_in_cond
    end
    
    local nCount = #match_attrs
    -- 拣货规则
    picking_rule = item.S_PICKING_RULE or ''
    if picking_rule == '' then
        picking_rule = default_picking_rule
    end    
    
    -- 弱化匹配规则的意思是通过减少匹配属性来进行 配盘 查询
    local inv_condition = ''
    local nRet, inv_order, picking_rule_attrs = wms_base.Get_INV_Detail_QueryOrder( picking_rule )
    if nRet ~= 0 then
        return 1, inv_order
    end
    local strCondition = ''
    for n = 1, nCount do
        -- 减少 n 个匹配属性，最后面的先弱化
        m = nCount - n
        -- 获取库存货品匹配条件
        inv_condition = get_inv_detail_match_sql( item, match_attrs, m, attr_null_in_condition )

        -- b.C_ENABLE 容器没禁用 a.F_QTY_VALID 可用量大于0
        -- AND b.N_LOCK_STATE = 0 容器没有锁定
        -- MDF BY HAN @20260909 取消 b.N_LOCK_STATE = 0 对枷锁的容器也可以进行分配
        if lua_info.dbtype == DB_TYPE.SQLServer then
            strCondition = inv_condition.." AND b.C_DISTRIBUTION = 'Y' AND b.C_ENABLE = 'Y' AND a.F_QTY_VALID > 0 "..
                            "AND a.S_CNTR_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where "..str_loc_where..")) "
        else
            strCondition = inv_condition.." AND b.C_DISTRIBUTION = 'Y' AND b.C_ENABLE = 'Y' AND a.F_QTY_VALID > 0 "..
                            "AND a.S_CNTR_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where "..str_loc_where..")) "
        end

        nRet, strRetInfo = inv_match( strLuaDEID, special_priority, parameter, item, strTable, strAttrs, strCondition, 
                                      inv_order, d_cntr_list, d_cntr_detail_list, in_op_cntr_list )
        if nRet ~= 0 then
            return 1, strRetInfo
        end
        if item.qty == item.alloc_qty then
            return 0
        end
    end
    return 0      
end

-- 分拣出库核心函数：给单个SKU分配库存生成配盘明细
-- 根据匹配规则（match_rule）和拣货规则（picking_rule）从库存中查找匹配的库存明细，
-- 优先从已命中料箱中分配，不足时再从仓库库区中匹配
-- @function wms_out.Distribution
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table parameter 参数集合, 包含 wh_code, area_code, station, exit_area_code, exit_loc, aisle, bs_type, bs_no, factory, cntr_out_op_def, cntr_back_op_def, have_put_wall_no, anomaly_distribution, out_inv_txn_udfattr_def, front_location_first, qty_sum, sorting 等
-- @tparam table item 出库单明细数据对象（SKU）, 包含 S_MATCH_RULE, S_PICKING_RULE, qty, alloc_qty 等
-- @tparam string strTable 查询的数据表（多表联查SQL）
-- @tparam string strAttrs 需要查询的属性
-- @tparam string str_loc_where 库位查询条件
-- @tparam string default_match_rule 默认匹配规则
-- @tparam string default_picking_rule 默认拣货规则
-- @tparam table d_cntr_list 当前已命中的料箱列表
-- @tparam table d_cntr_detail_list 当前已命中的配盘明细列表
-- @tparam table in_op_cntr_list 当前正在操作的料箱列表, 可为空
-- @treturn number 0=分配完成, 1=失败
-- @treturn string|nil 错误信息, 成功时 nil
function wms_out.Distribution( strLuaDEID, parameter, item, strTable, strAttrs, str_loc_where, 
                               default_match_rule, default_picking_rule, d_cntr_list, d_cntr_detail_list, in_op_cntr_list )
    local nRet, strRetInfo
    local strCondition, match_rule, str_picking_rule

    if in_op_cntr_list == nil then
        in_op_cntr_list = {}
    end

    -- step2.1 组织查询条件
    -- 获取匹配策略
    match_rule = item.S_MATCH_RULE or ''
    if match_rule == '' then
        match_rule = default_match_rule
    end
    -- 拣货规则
    str_picking_rule = item.S_PICKING_RULE or ''
    if str_picking_rule == '' then
        str_picking_rule = default_picking_rule
    end

    local inv_condition

    if parameter.special_match_function == nil then
        nRet, inv_condition = wms_base.Get_INV_Detail_MatchSql( item, match_rule )
        if nRet ~= 0 then
            return 1, inv_condition
        end
    else
        -- 有特殊匹配函数
        local module = parameter.special_match_function.module_name or ''
        local function_name = parameter.special_match_function.function_name or ''

        nRet, inv_condition = lua.callFunctionByName( module, function_name, parameter.bs_object_data, item, match_rule )
        if nRet ~= 0 then
            return 1, inv_condition
        end
    end

    local nRet, inv_order, picking_rule_attrs = wms_base.Get_INV_Detail_QueryOrder( str_picking_rule )
    if nRet ~= 0 then
        return 1, inv_order
    end
    
    -- 特殊优先级
    local special_priority = {
            front_location_first = parameter.front_location_first or false,  -- 是否启用外深位库位优先
            no_operation_first = parameter.no_operation_first or false,
    }
    -- 在参数里加拣货顺序
    parameter.picking_rule_attrs = picking_rule_attrs

    -- MDF BY HAN @20251105 先查一下当前已经命中的料箱里是否有合适的货品可以出库分拣
    -- 获取当前已经命中的料箱编码集合
    local str_cntr_no_set = ''
    for _, cntr in ipairs( d_cntr_list ) do
        str_cntr_no_set = str_cntr_no_set.."'"..cntr.S_CNTR_CODE.."',"
    end
    str_cntr_no_set = lua.trim_laster_char( str_cntr_no_set )
    if str_cntr_no_set ~= '' then
        -- AND b.N_LOCK_STATE = 0 容器没有锁定
        strCondition = inv_condition.." AND b.C_DISTRIBUTION = 'Y' AND b.C_ENABLE = 'Y' AND a.F_QTY_VALID > 0 AND b.N_LOCK_STATE = 0 AND a.S_CNTR_CODE IN ("..str_cntr_no_set..")"
        nRet, strRetInfo = inv_match( strLuaDEID, nil, parameter, item, strTable, strAttrs, strCondition, 
                                      inv_order, d_cntr_list, d_cntr_detail_list, in_op_cntr_list )
        if nRet ~= 0 then
            return 1, strRetInfo
        end
    end
    
    local lua_info
    nRet, lua_info = lua.GetLuaDEInfo( strLuaDEID )
    if nRet ~= 0 then
        return 1, "GetLuaDEInfo 失败!"..lua_info
    end
    
    if item.qty > item.alloc_qty then
        -- b.C_ENABLE 容器没禁用 a.F_QTY_VALID 可用量大于0
        -- AND b.N_LOCK_STATE = 0 容器没有锁定
        if lua_info.dbtype == DB_TYPE.SQLServer then
            strCondition = inv_condition.." AND b.C_DISTRIBUTION = 'Y' AND b.C_ENABLE = 'Y' AND a.F_QTY_VALID > 0 AND b.N_LOCK_STATE = 0 "..
                        "AND a.S_CNTR_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where "..str_loc_where..")) "
        else
            strCondition = inv_condition.." AND b.C_DISTRIBUTION = 'Y' AND b.C_ENABLE = 'Y' AND a.F_QTY_VALID > 0 AND b.N_LOCK_STATE = 0 "..
                        "AND a.S_CNTR_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where "..str_loc_where..")) "
        end
        nRet, strRetInfo = inv_match( strLuaDEID, special_priority, parameter, item, strTable, strAttrs, strCondition, 
                                    inv_order, d_cntr_list, d_cntr_detail_list, in_op_cntr_list )
        if nRet ~= 0 then
            return 1, strRetInfo
        end
    end
    return 0  
end

--[[ 

  出库分拣标准配货算法 ****

  说明： 
    根据 parameter 的业务来源类型和来源编码获取需要出库的货品清单 item_lits
    遍历 item_list 从库存中找出匹配的库存明细进行预分配，生成 d_cntr_detail_list 配盘明细（出库任务）
    如果有缺件 保存 在shortage_list


    注意：item_list中的 item(SKU) 参与查询条件的属性-- S_PICKING_RULE, S_MATCH_RULE 中定义的规则进行

    parameter = {
                    -- MDF BY HAN @20260830 仓库范围
                    warehouse_scope = {
                            mode = "Single" -- 单仓库、  "Multi" -- 多仓库、  "Sequence" -- 按顺序模式
                            wh_code_set = { "WH001", "WH002" } -- 仓库范围
                    }

                    wh_code, -- 仓库编码
                    area_code = "A01,A02" -- 支持多库区,可以为空
                    station  -- 分拣站台, 可以为空
                    exit_area_code -- 出库口接驳区，有些情况是没 exit_loc 的
                    exit_loc -- 出库出口货位，货位对象{ area_code, code }
                    aisle -- 可用巷道，一般用在单个仓库、库区的情况

                    -- MDF BY HAN @2025603 启用巷道任务均衡
                    aisle_lb -- 启用巷道任务均衡

                    bs_type --（Outbound_Order/Outbound_Wave） 
                    bs_no -- 波次号/出库单号

                    factory -- 工厂标识
                    cntr_out_op_def -- 容器出库作业定义
                    cntr_back_op_def -- 容器回库作业定义
                    have_put_wall_no -- 播种墙格口必须有值（默认false）
                    anomaly_distribution -- true 表示是出库异常后再次配盘
                    out_inv_txn_udfattr_def = { "S_UDF01","S_UDF02"}      -- 说明这些属性要用出库单明细中的值
                    front_location_first -- bool true表示外深位优先，一般用在双深位仓库的配盘中
                    no_operation_first -- bool 优先匹配没有作业的料箱
                    area_distribution -- bool true 表示只查 Area中 C_DISTRIBUTION = Y 的库区

                    -- MDF BY HAN @20260601 特殊的匹配条件
                    special_match_function = { module_name = "xxxx", function_name = "xxxx" } -- 一般为nil或空，如果有特殊的匹配条件时 执行这个函数生成特殊匹配条件
                    bs_object_data -- 出库单/波次单数据对象( 用在外部函数调用时的输出参数 )


                }

返回: 
    d_cntr_list 配盘/Distribution_CNTR  
    d_cntr_detail_list 配盘明细/Distribution_CNTR_Detail
    shortage_list -- 缺件清单
    更改记录:

]]

-- 出库分拣标准配货算法
-- 根据 parameter 的业务来源类型和来源编码获取出库货品清单，
-- 遍历货品清单从库存中匹配库存明细进行预分配，
-- 生成配盘明细（出库任务），未完全分配的货品记录在 shortage_list 中
-- @function wms_out.Distribution_Procedure
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table parameter 参数集合见说明
-- @tparam table d_cntr_list 配盘列表（Distribution_CNTR）, 作为输出参数
-- @tparam table d_cntr_detail_list 配盘明细列表（Distribution_CNTR_Detail）, 作为输出参数
-- @tparam table shortage_list 缺件清单, 作为输出参数
-- @treturn number 0=成功, 1=参数错误, 2=执行失败
-- @treturn string|nil 错误信息, 成功时 nil
function wms_out.Distribution_Procedure( strLuaDEID, parameter, d_cntr_list, d_cntr_detail_list, shortage_list ) 
    local nRet, strRetInfo, strCondition
    local str_loc_where = ''
    local no_operation_first = parameter.no_operation_first or false

    -- step1：输入参数判断
    if  parameter == nil or type(parameter) ~= "table" then 
        return 1, "输入参数错误， parameter 必须有值且必须是 table 类型"  
    end
    if parameter.have_put_wall_no == nil then
        parameter.have_put_wall_no = false
    end
    if parameter.warehouse_scope == nil then
        if  parameter.wh_code == nil or parameter.wh_code == ''  then
            return 1, "输入参数错误， parameter.wh_code必须有值"
        end
        parameter.warehouse_scope = {
            mode = "Single",
            wh_code_set = { parameter.wh_code }
        }
    else
        if type( parameter.warehouse_scope) ~= "table" then
            return 1, "输入参数错误， parameter.warehouse_scope 必须是 table 类型"
        end
    end
    -- 如果设置仓库检索范围不是单仓库，则需要检查仓库范围是否有值
    if parameter.warehouse_scope.mode ~= "Single" then
        if parameter.warehouse_scope.wh_code_set == nil or #parameter.warehouse_scope.wh_code_set == 0 then
            return 1, "输入参数错误， parameter.warehouse_scope.wh_code_set 必须有值"
        end
        if #parameter.warehouse_scope.wh_code_set == 1 then
            parameter.warehouse_scope.mode = "Single"
            parameter.wh_code = parameter.warehouse_scope.wh_code_set[1]
        end
    else
        parameter.wh_code = parameter.warehouse_scope.wh_code_set[1]
    end
    if  parameter.bs_type == nil or parameter.bs_type == ''  then
        return 1, "输入参数错误， parameter.bs_type 必须有值"
    end
    if  parameter.bs_no == nil or parameter.bs_no == ''  then
        return 1, "输入参数错误， parameter.bs_no 必须有值"
    end      
    
    local default_match_rule = ''               -- 默认缺省的匹配规则
    local default_picking_rule = ''
    local default_mr_weaken = ''                -- 是否启用匹配弱化策略（找不到货的时候可以减少匹配属性）

    -- 获取入库货品清单 item_list
    local data_objs
    local out_wave_obj = nil
    if parameter.bs_type == "Outbound_Wave" then
        -- 获取出库波次对象，获取属性 是否汇总，是否分播
        strCondition = "S_WAVE_NO = '"..parameter.bs_no.."'"
        nRet, out_wave_obj = m3.GetDataObjByCondition(strLuaDEID, "Outbound_Wave", strCondition )
        if nRet ~= 0 then
            return 2, "GetDataObjByCondition失败!"..out_wave_obj
        end
        if out_wave_obj.qty_sum == nil then
            return 2, "Outbound_Wave 数据模型中缺少 lua 变量为 qty_sum 的属性定义!"
        end
        if out_wave_obj.sorting == nil then
            return 2, "Outbound_Wave 数据模型中缺少 lua 变量为 sorting 的属性定义!"
        end        
        parameter.qty_sum = ( out_wave_obj.qty_sum == 'Y' )
        parameter.sorting = ( out_wave_obj.sorting == 'Y' )

        strCondition = "S_WAVE_NO = '"..parameter.bs_no.."' AND F_QTY > F_ACC_D_QTY"
        -- 注意 出库波次 没 order 和 storer 的match_rule 这些都是 Detail 里
        nRet, data_objs = m3.QueryDataObject(strLuaDEID, "OW_Detail", strCondition, "N_ROW_NO" )
        if nRet ~= 0 then 
            return 2, "QueryDataObject失败!"..data_objs 
        end

        -- 获取出库单波次的拣货规则，匹配规则
        nRet, default_match_rule, default_picking_rule, default_mr_weaken  = wms_out.Get_Outbound_Wave_MatchPickin_Rule( strLuaDEID, parameter.bs_no )
        if nRet ~= 0 then
            return 2, "获取出库波次匹配规则、拣货规则失败!" .. default_match_rule
        end 

    elseif parameter.bs_type == "Outbound_Order" then
        strCondition = "S_OO_NO = '"..parameter.bs_no.."'  AND F_QTY > F_ACC_D_QTY"
        nRet, data_objs = m3.QueryDataObject(strLuaDEID, "Outbound_Detail", strCondition, "N_ROW_NO" )
        if nRet ~= 0 then 
            return 2, "QueryDataObject失败!"..data_objs 
        end    
        
        -- 获取出库单的拣货规则，匹配规则
        nRet, default_match_rule, default_picking_rule, default_mr_weaken  = wms_out.Get_OutboudOrder_MatchPickin_Rule( strLuaDEID, parameter.bs_no )
        if nRet ~= 0 then
            return 2, "获取出库单匹配规则、拣货规则失败!" .. default_match_rule
        end    
    else
         return 1, "输入参数错误， parameter.bs_type 不合规!"
    end
    if data_objs == '' then 
        -- 设置错误信息
        return 1, "编号号'"..parameter.bs_no.."'的'"..parameter.bs_type.."'为空!"
    end

    -- 如果要做没作业的容器优先，需要先装载当前正在作业状态的料箱
    local in_op_cntr_list = {}  -- 在作业里的料箱
    if no_operation_first then
        if parameter.warehouse_scope.mode == "Single" then
            in_op_cntr_list, strRetInfo = wms_cntr._Get_Bin_Under_Operation( strLuaDEID, parameter.warehouse_scope.wh_code_set[1] )
        else
            in_op_cntr_list, strRetInfo = wms_cntr._Get_Bin_Under_Operation( strLuaDEID, parameter.warehouse_scope.wh_code_set )
        end
        if in_op_cntr_list == nil then
            return 1, "获取正在作业的料箱失败!"..strRetInfo
        end
    end
    local OUT_DETAIL_ATTR_COUNT = #OUTBOUND_DETAIL_BASE_ATTRS
    local UDF_ATTRS_COUNT = #UDF_ATTRS
    local item_list = {}
    local detail_attrs

    for n = 1, #data_objs do
        detail_attrs = m3.KeyValueAttrsToObjAttr(data_objs[n].attrs)
        if detail_attrs == nil then
            return 1, "转换属性失败!"
        end
        local item = {}
        for m = 1, OUT_DETAIL_ATTR_COUNT do
            item[OUTBOUND_DETAIL_BASE_ATTRS[m]] = detail_attrs[OUTBOUND_DETAIL_BASE_ATTRS[m]]
        end
        for m = 1, UDF_ATTRS_COUNT do
            item[UDF_ATTRS[m]] = detail_attrs[UDF_ATTRS[m]]
        end  
        -- V3.0 
        if parameter.bs_type == "Outbound_Wave" then
            item.S_OO_NO = detail_attrs.S_OO_NO
            item.N_OO_ROW_NO = detail_attrs.N_OO_ROW_NO
        end

        -- F_ACC_D_QTY 已经配盘的数量
        item.qty = lua.Get_NumAttrValue( detail_attrs.F_QTY ) - lua.Get_NumAttrValue( detail_attrs.F_ACC_D_QTY )
        if item.qty > 0 then
            item.alloc_qty = 0
            table.insert( item_list, item )
        end
    end        
    if lua.isTableEmpty( item_list ) then
        return 0
    end

    -- 拣货策略和匹配策略确定，如果 Detail 里有定义就根据Detail里的定义，没有就从 Order 上找，Order上没有就从 货主这里找
    -- 从 INV_Detail 中分配数量
    local strTable = "TN_INV_Detail a LEFT JOIN TN_Container b ON a.S_CNTR_CODE = b.S_CODE"
    -- MDF BY HAN @20260722
    local lua_info
    nRet, lua_info = lua.GetLuaDEInfo( strLuaDEID )
    if nRet ~= 0 then
        return 1, "GetLuaDEInfo 失败!"..lua_info
    end    
    -- TN_INV_Detail 不采用NOLOCK的目的就是要保证库存量数据的准确性，防止库存量数据被其他线程修改
    if lua_info.dbtype == DB_TYPE.SQLServer then
        strTable = "TN_INV_Detail a LEFT JOIN TN_Container b WITH (NOLOCK) ON a.S_CNTR_CODE = b.S_CODE"
    else
        strTable = "TN_INV_Detail a LEFT JOIN TN_Container b ON a.S_CNTR_CODE = b.S_CODE"
    end

    local strAttrs ='a.S_ID,a.S_WH_CODE,a.S_AREA_CODE,a.S_LOC_CODE,'
    local INV_DETAIL_BASE_ATTRS_COUNT = #INV_DETAIL_BASE_ATTRS
    local attr_set = {}
    for m = 1, INV_DETAIL_BASE_ATTRS_COUNT do
        strAttrs = strAttrs.."a."..INV_DETAIL_BASE_ATTRS[m]..","
        table.insert( attr_set, INV_DETAIL_BASE_ATTRS[m] )
    end
    for m = 1, UDF_ATTRS_COUNT do
        strAttrs = strAttrs.."a."..UDF_ATTRS[m]..","
        table.insert( attr_set, UDF_ATTRS[m] )
    end
    strAttrs = lua.trim_laster_char( strAttrs )
  
    if parameter.warehouse_scope.mode == "Single" then
        str_loc_where = "C_ENABLE = 'Y' AND S_WH_CODE = '"..parameter.wh_code.."'"
        if  parameter.area_code ~= nil and parameter.area_code ~= '' then
            local seg = lua.split( parameter.area_code, "," ) 
            if #seg == 1 then
                str_loc_where = str_loc_where.." AND S_AREA_CODE = '"..parameter.area_code.."'"
            else
                local area_code_set = ''
                for _, val in ipairs( seg ) do
                    area_code_set = area_code_set.."'"..val.."',"
                end
                area_code_set = lua.trim_laster_char( area_code_set )
                str_loc_where = str_loc_where.." AND S_AREA_CODE IN ("..area_code_set..")"
            end
        else
            -- 如果没指定库区，通常就是查仓库中的所有库区
            -- 如果 area_distribution = true 说明需要加对库区的过滤
            local area_distribution = parameter.area_distribution or false

            if area_distribution then
                local area_condition = " AND S_AREA_CODE IN ( select S_CODE from TN_Area where S_WH_CODE = '"..parameter.wh_code.."' and C_DISTRIBUTION = 'Y' )"
                str_loc_where = str_loc_where..area_condition
            end
        end
        -- step2： 遍历待出库货品清单
        for _, item in ipairs( item_list ) do
            nRet, strRetInfo = wms_out.Distribution( strLuaDEID, parameter, item, strTable, strAttrs, str_loc_where, 
                                                    default_match_rule, default_picking_rule, 
                                                    d_cntr_list, d_cntr_detail_list, in_op_cntr_list )
            if nRet ~= 0 then
                return 2, strRetInfo
            end
        end        
    elseif parameter.warehouse_scope.mode == "Multi" then
        local str_wh_codes = table.concat( parameter.warehouse_scope.wh_code_set, "','" )
        str_loc_where = "C_ENABLE = 'Y' AND S_WH_CODE IN ("..str_wh_codes..")"
        -- step2： 遍历待出库货品清单
        for _, item in ipairs( item_list ) do
            nRet, strRetInfo = wms_out.Distribution( strLuaDEID, parameter, item, strTable, strAttrs, str_loc_where, 
                                                    default_match_rule, default_picking_rule, 
                                                    d_cntr_list, d_cntr_detail_list, in_op_cntr_list )
            if nRet ~= 0 then
                return 2, strRetInfo
            end
        end        
    else
        -- Sequence
        -- 按顺序依次进行匹配
        for _, wh_code in ipairs( parameter.warehouse_scope.wh_code_set ) do
            str_loc_where = "C_ENABLE = 'Y' AND S_WH_CODE = '"..wh_code.."'"
            -- step2： 遍历待出库货品清单
            for _, item in ipairs( item_list ) do
                nRet, strRetInfo = wms_out.Distribution( strLuaDEID, parameter, item, strTable, strAttrs, str_loc_where, 
                                                        default_match_rule, default_picking_rule, 
                                                        d_cntr_list, d_cntr_detail_list, in_op_cntr_list )
                if nRet ~= 0 then
                    return 2, strRetInfo
                end
            end
        end
    end


    -- step3 检查一下是否有未分配完成的货品，如果有生成缺件清单
    local alloc_is_ok = true
    local mr_weaken             -- 是否启用匹配弱化
    local strUpdateSql
    
    for _, item in ipairs( item_list ) do
        if item.qty > item.alloc_qty then    
            -- MDF BY HAN 20251021 判断是否启用匹配弱化
            mr_weaken = item.C_MR_WEAKEN or ''
            if mr_weaken == '' then
                mr_weaken = default_mr_weaken
            end
            if mr_weaken == 'Y' then
                -- 通过减少匹配属性再次进行配盘
                if parameter.warehouse_scope.mode == "Sequence" then
                    for _, wh_code in ipairs( parameter.warehouse_scope.wh_code_set ) do
                        str_loc_where = "C_ENABLE = 'Y' AND S_WH_CODE = '"..wh_code.."'"
                        nRet,strRetInfo  = do_distribution_by_weaken_match_rule( strLuaDEID, parameter, item, strTable, strAttrs, str_loc_where, 
                                                        default_match_rule, default_picking_rule, 
                                                        d_cntr_list, d_cntr_detail_list, in_op_cntr_list)
                        if nRet ~= 0 then
                            return 2, strRetInfo
                        end
                    end
                else
                    nRet,strRetInfo  = do_distribution_by_weaken_match_rule( strLuaDEID, parameter, item, strTable, strAttrs, str_loc_where, 
                                                                            default_match_rule, default_picking_rule, 
                                                                            d_cntr_list, d_cntr_detail_list, in_op_cntr_list)
                    if nRet ~= 0 then
                        return 2, strRetInfo
                    end
                end
            end
            -- 加入缺件清单
            if item.qty > item.alloc_qty then    
                alloc_is_ok = false
                local shortage = {
                    bs_type = parameter.bs_type,
                    bs_no = parameter.bs_no,
                    qty = item.qty - item.alloc_qty,
                    item_detail = item                       -- IW_Detail/Outbound_Detail
                }
                table.insert( shortage_list, shortage ) 
            end
        end
    end

    -- 如果出库单明细中已经全部分配完成
    if alloc_is_ok then
        -- 更新出库单、出库波次的状态为 -- 配货完成
        if parameter.bs_type == "Outbound_Wave" then
            strCondition = "S_WAVE_NO = '"..parameter.bs_no.."'"
            strUpdateSql = "N_B_STATE = "..OUTBOUND_ORDER_STATE.AllocOK
            nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Outbound_Wave", strCondition, strUpdateSql )
            if  nRet ~= 0  then  
                return 2, "更新【出库波次】信息失败!"..strRetInfo  
            end   
        elseif parameter.bs_type == "Outbound_Order" then
            strCondition = "S_NO = '"..parameter.bs_no.."'"
            strUpdateSql = "N_B_STATE = "..OUTBOUND_ORDER_STATE.AllocOK
            nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Outbound_Order", strCondition, strUpdateSql )
            if  nRet ~= 0  then  
                return 2, "更新【出库单】信息失败!"..strRetInfo  
            end                           
        end        
    end

    return 0
end

-- 检测配盘是否为整托出
-- 判断依据：库存明细中的数量减去配盘明细中的数量后，所有明细都为 0 即认为是整托出
-- @function check_distribution_whole_out
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table distribution_cntr 配盘数据对象 [Distribution_CNTR], 必须有值
-- @tparam table d_cntr_detail_list 配盘明细链表
-- @treturn number 0=检测完成, >0=参数错误
-- @treturn string "yes"=整托出, "no"=非整托出, 或错误信息
local function check_distribution_whole_out( strLuaDEID, distribution_cntr, d_cntr_detail_list )
    local nRet
    
    if distribution_cntr == nil or type(distribution_cntr) ~= 'table'  then
        return 1, "check_distribution_whole_out 函数中 distribution_cntr 不能为空,必须为table!"
    end

    -- 获取【配盘明细】
    local dc_detail_list = {}
    for _, dc_detail in ipairs( d_cntr_detail_list ) do
        if  distribution_cntr.S_CNTR_CODE == dc_detail.S_CNTR_CODE  then
            table.insert( dc_detail_list, dc_detail )
        end
    end

    -- 获取【INV_Detail】
    local data_objects
    local strCondition = "S_CNTR_CODE = '"..distribution_cntr.S_CNTR_CODE.."'"
    nRet, data_objects = m3.QueryDataObject(strLuaDEID, "INV_Detail", strCondition, "S_ITEM_CODE" )
    if nRet ~= 0 then 
        return 2, "QueryDataObject失败!"..data_objects 
    end
    if data_objects == '' then 
        return 0, "no" 
    end
    if #data_objects > #dc_detail_list  then 
        -- 如果容器中的货品条数 > 配盘明细 肯定不是整托出
        return 0, "no"
    end

    -- 遍历 容器货品明细 判断：inv_detail.qty - dc_detail.qty = 0
    local inv_detail_qty, dc_detail_qty
    local count = #dc_detail_list
    local obj_attrs
    for n = 1, #data_objects do
        obj_attrs = m3.KeyValueAttrsToObjAttr(data_objects[n].attrs)
        if obj_attrs == nil then
            return 2, "KeyValueAttrsToObjAttr失败!"
        end
        inv_detail_qty = lua.StrToNumber( obj_attrs.F_QTY )
        -- 从【Distribution_CNTR_Detail】找到 G_INV_DETAIL_ID 相同的 配盘明细
        for i = 1, count do
            if dc_detail_list[i].G_INV_DETAIL_ID == data_objects[n].id then
                dc_detail_qty = lua.StrToNumber( dc_detail_list[i].F_QTY )
                inv_detail_qty = inv_detail_qty - dc_detail_qty
            end
        end
        if inv_detail_qty > 0 then
            return 0, "no"
        end
    end
    return 0, "yes"
end

-- 创建配盘及配盘明细数据对象
-- 遍历配盘链表创建 Distribution_CNTR，并检测整托出标记和人工库区状态；遍历配盘明细链表创建 Distribution_CNTR_Detail
-- @function wms_out.Creat_Distribution_list
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table d_cntr_list 配盘链表 [Distribution_CNTR 数据对象], 必须有值
-- @tparam table d_cntr_detail_list 配盘明细链表 [{S_ITEM_CODE, S_ITEM_NAME, S_CNTR_CODE,...}], 必须有值
-- @treturn number 0=创建成功, 1=创建失败, 2=查询库区信息失败
-- @treturn string|nil 错误信息, 成功时 nil
function wms_out.Creat_Distribution_list( strLuaDEID, d_cntr_list, d_cntr_detail_list  )
    local nRet, strRetInfo
    local nCount = #d_cntr_list
    local distribution_cntr

    for n = 1, nCount do
        -- MDF BY HAN @20251111
        -- 检测是否整托出
        nRet, strRetInfo = check_distribution_whole_out( strLuaDEID, d_cntr_list[n], d_cntr_detail_list )
        if  nRet ~= 0  then 
            return nRet, strRetInfo 
        end    
        if  strRetInfo == "yes"  then
            d_cntr_list[n].C_WHOLE_OUT = 'Y'
        end  
        
        -- 如果配盘在人工库区，配盘状态设置为 出库完成
        local area_manual = false
        local area_code = d_cntr_list[n].S_AREA_CODE or ''
        if area_code ~= '' then
            local area
            nRet, area = wms_wh.GetAreaInfo3( area_code )
            if nRet ~= 0 then
                return 2, "获取库区'"..area_code.."'信息失败!"
            end
            if area.C_MANUAL ~= nil then
                area_manual = ( area.C_MANUAL == 'Y' )
            end
        end
        if area_manual then
            -- 人工库区的处理逻辑, 拣货任务不需要料箱搬运直接可以进行分拣
            d_cntr_list[n].N_B_STATE = DIST_CNTR_STATE.OutOK
        end
        
        nRet, distribution_cntr = m3.CreateDataObj2( strLuaDEID, d_cntr_list[n] )
        if  nRet ~= 0  then 
            return 1, '创建【配盘】对象失败!'..distribution_cntr 
        end
        d_cntr_list[n].S_DC_NO = distribution_cntr.S_DC_NO
    end    
    local dc_no

    -- step3 创建【配盘明细/Distribution_CNTR_Detail】
    local area_code
    for _, dc_detail in ipairs( d_cntr_detail_list ) do
        -- 通过容器编码获取 配盘号
        dc_no = ""
        area_code = ''
        for n = 1, nCount do 
            if  d_cntr_list[n].S_CNTR_CODE == dc_detail.S_CNTR_CODE  then
                dc_no = d_cntr_list[n].S_DC_NO
                area_code = d_cntr_list[n].S_AREA_CODE
                break
            end
        end
        if  dc_no == ''  then
            return 1, "容器'"..dc_detail.S_CNTR_CODE.."' 无法定位到【配盘】!"
        end
        -- 判断配盘料箱的库区是否是人工库区
        local area_manual = false
        if area_code ~= '' then
            local area
            nRet, area = wms_wh.GetAreaInfo3( area_code )
            if nRet ~= 0 then
                return 2, "获取库区'"..area_code.."'信息失败!"
            end
            if area.C_MANUAL ~= nil then
                area_manual = ( area.C_MANUAL == 'Y' )
            end
        end
        if area_manual then
            -- 人工库区的处理逻辑, 拣货任务不需要料箱搬运直接可以进行分拣
            dc_detail.N_B_STATE = DC_DETAIL_STATE.CanDoPicking
        end
        dc_detail.S_DC_NO = dc_no
        nRet, dc_detail = m3.CreateDataObj2( strLuaDEID, dc_detail )
        if nRet ~= 0 then 
            return 1, '创建【配盘明细】对象失败!'..dc_detail 
        end  
    end
    return 0
end

-- 汇总出库单明细信息
-- 将出库单中的货品明细加入汇总链表，相同货品编码数量累加
-- @function wms_out.Sum_outbound_detail
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string strOONo 出库单号, 必须有值
-- @tparam table sum_outbound_detail 出库波次明细汇总链表 [{item_name, item_code, qty, weight, volume, cell_type}]
-- @treturn number 0=成功, 1=失败
-- @treturn table outbound_detail_info 出库单明细汇总信息 {total_qty, total_weight, total_volume}, 或错误信息字符串
function wms_out.Sum_outbound_detail( strLuaDEID, strOONo, sum_outbound_detail )
    local nRet
    local strCondition
    local data_objs
    local outbound_detail_info = {
        total_qty = 0, total_weight = 0, total_volume = 0
    }

    strCondition = "S_OO_NO = '"..strOONo.."'"
    nRet, data_objs = m3.QueryDataObject(strLuaDEID, "Outbound_Detail", strCondition, "N_ROW_NO" )
    if nRet ~= 0 then
        return 2, "QueryDataObject失败!"..data_objs
    end
    if data_objs == '' then
        return 0, outbound_detail_info
    end
    
    local item_code, qty, weight, volume
    local detail_attrs
    local bFind

    for n = 1, #data_objs do
        detail_attrs = m3.KeyValueAttrsToObjAttr(data_objs[n].attrs)
        if detail_attrs == nil then
            return 2, "KeyValueAttrsToObjAttr失败!"
        end
        item_code = lua.Get_StrAttrValue( detail_attrs.S_ITEM_CODE )
        qty = lua.StrToNumber( detail_attrs.F_QTY )
        weight = lua.StrToNumber( detail_attrs.F_WEIGHT )
        volume = lua.StrToNumber( detail_attrs.F_VOLUME )

        if  item_code ~= '' and qty > 0  then

            outbound_detail_info.total_qty = outbound_detail_info.total_qty + qty
            outbound_detail_info.total_weight = outbound_detail_info.total_weight + qty*weight
            outbound_detail_info.total_volume = outbound_detail_info.total_volume + qty*volume

            bFind = false
            for m = 1, #sum_outbound_detail do
                if sum_outbound_detail[m].item_code == item_code then
                    bFind = true
                    sum_outbound_detail[m].qty = sum_outbound_detail[m].qty + qty
                    break
                end
            end
            if  bFind == false  then
                local out_item = {
                    item_code = item_code,
                    item_name = lua.Get_StrAttrValue( detail_attrs.S_ITEM_NAME ),
                    qty = qty,
                    alloc_qty = 0,
                    weight = weight,
                    volume = volume,
                    cell_type = lua.Get_StrAttrValue( detail_attrs.S_CELL_TYPE )
                }
                table.insert( sum_outbound_detail, out_item )
            end
        end
    end
    return 0, outbound_detail_info
end


-- 配盘明细后处理程序
-- 分拣出库后，根据配盘明细的分拣结果更新量表、INV_Detail，
-- 包括减少配量和存量、更新来源单号累计出库数量、生成拣料箱明细等
-- @function wms_out.Distribution_CNTR_Detail_PostProcess
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string wh_code 仓库编码, 必须有值
-- @tparam string area_code 库区编码, 可为空
-- @tparam string loc_code 货位编码, 可为空
-- @tparam string dc_no 配盘容器号, 必须有值
-- @tparam string picking_box_code 拣料箱编码, 可为空
-- @tparam table|nil cfg 配置参数, 可为空 {cancel=true/false}
-- @treturn number 0=成功, 1=失败
-- @treturn string|nil 错误信息, 成功时 nil
function wms_out.Distribution_CNTR_Detail_PostProcess( strLuaDEID, wh_code, area_code, loc_code, dc_no, picking_box_code, cfg )
    local nRet, strRetInfo

    if  dc_no == nil or dc_no == ''  then 
        return 1, "wms_out.Distribution_CNTR_Detail_PostProcess 函数中 dc_no 必须有值!" 
    end
    if picking_box_code == nil then
        picking_box_code = ''
    end


    if  wh_code == '' or wh_code == nil  then 
        return 1, "wms_out.Distribution_CNTR_Detail_PostProcess 函数中仓库编码必须有值!"
    end
    if area_code == nil then
        area_code = ''
    end
    if loc_code == nil then
        loc_code = ''
    end
    local cancel = false    -- 是否启用取消数量（当出库数量大于实际拣货数量时，把差额作为取消数量）
    if cfg ~= nil then
        cancel = cfg.cancel or false
    end

    -- 获取 Pre_Alloc_CNTR_Detail
    local strOrder = ''
    local strCondition = "S_DC_NO = '"..dc_no.."'"

    nRet, strRetInfo = mobox.queryDataObjAttr( strLuaDEID, "Distribution_CNTR_Detail", strCondition, strOrder )
    if nRet ~= 0 then
        return 1, "获取【配盘明细】失败! "..strRetInfo
    end
    if  strRetInfo == ''  then 
        lua.Warning( strLuaDEID, debug.getinfo(1), "配盘号'"..dc_no.."'的明细为空!" )
        return 1, "配盘号'"..dc_no.."'的明细为空!"
    end

    local dc_detail_list = json.decode( strRetInfo )
    local dc_detail = {}
    local strSetAttr

    -- 这里是需要把出库单中的某些 UDF 属性带入到 INV_TXN_Log 中
    local out_inv_txn_udf_attrs = {}
    nRet, strRetInfo = wms_base.Get_sConst2( "WMS_OUT_INV_TXN_UDF_ATTRS" )
    if nRet == 0 then
        local success
        success, out_inv_txn_udf_attrs = pcall( json.decode, strRetInfo )
        if  success == false  then
            return 2, " 常量 WMS_OUT_INV_TXN_UDF_ATTRS 中的定义不是一个标准的Json字符串!"
        end
    end

    -- 获取存储量变化数据 并且创建 上下架记录
    for n = 1, #dc_detail_list do
        nRet, dc_detail = m3.ObjAttrStrToLuaObj( "Distribution_CNTR_Detail", lua.table2str(dc_detail_list[n].attrs) )
        if nRet ~= 0 then 
            return 1, "m3.ObjAttrStrToLuaObj 失败! "..dc_detail 
        end
        -- 更新容器料格中的强制置满标记 C_FORCED_FILL = N
        strCondition = "S_CNTR_CODE = '"..dc_detail.cntr_code.."' AND S_CELL_NO = '"..dc_detail.cell_no.."'"
        strSetAttr = "C_FORCED_FILL = 'N'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Container_Cell", strCondition, strSetAttr )
        if nRet ~= 0 then 
            return 1, "设置【Container_Cell】属性失败!"..strRetInfo 
        end     

        local ext_parameter = {
            bs_type = dc_detail.bs_type,
            bs_no = dc_detail.bs_no,
            bs_row_no = dc_detail.bs_row_no,
            out_inv_txn_udf_attrs = out_inv_txn_udf_attrs
        }        

        -- 减库存量表
        if  dc_detail.inv_detail_id ~= ''  then
            -- 配盘明细没有合并
            nRet, strRetInfo = wms_inv.INV_Detail_Out( strLuaDEID, dc_detail, ext_parameter )
            if  nRet ~= 0   then 
                return 1, "wms_inv.INV_Detail_Out 失败! "..strRetInfo 
            end
        else
            -- ??? 有事件要改进成和 INV_Detail_Out( strLuaDEID, dc_detail ) 一样
            -- 配盘明细是合并 INV_Detail 的因此需要把计划出库数量，实际出库数量批分到 INV_Detail 上
            strOrder = "S_BATCH_NO"
            strCondition = "S_CNTR_CODE = '"..dc_detail.cntr_code.."' AND S_CELL_NO = '"..dc_detail.cell_no.."'"
            nRet, strRetInfo = wms_inv.INV_Detail_SplitOut( strLuaDEID, dc_detail, strCondition, strOrder, dc_detail.acc_p_qty, dc_detail.qty, ext_parameter )
            if nRet ~= 0  then 
                return 1, "wms_inv.INV_Detail_SplitOut 失败! "..strRetInfo 
            end            
        end

        -- 如果来源类型 = Outbound_Order 更新出库单的累计出库数量
        local cancel_qty = dc_detail.qty - dc_detail.acc_p_qty

        if  dc_detail.bs_type == "Outbound_Order"  then
            if  dc_detail.bs_no ~= nil and dc_detail.bs_no ~= ''  then
                strCondition = "S_OO_NO = '"..dc_detail.bs_no.."' AND N_ROW_NO = "..dc_detail.bs_row_no
                strSetAttr = "F_ACC_O_QTY = F_ACC_O_QTY +"..dc_detail.acc_p_qty
                -- MDY BY HAN @20250812 增加了异常处理记录，出库操作会继续补料出库，因此这里不适合加上关闭数量
                -- MDY BY HAN @20251201 加一个cfg.cancel 变量来控制是否采用取消数量
                if  cancel and lua.equation( 0, cancel_qty ) == false  then
                    strSetAttr = strSetAttr..", F_ACC_C_QTY = F_ACC_C_QTY + "..cancel_qty
                end     
            
                nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Outbound_Detail", strCondition, strSetAttr )
                if nRet ~= 0 then 
                    return 1, "设置【Outbound_Detail】累计出库数量失败!"..strRetInfo 
                end
                -- V3.0 如果配盘明细中带出库波次
                if dc_detail.wave_no ~= '' and dc_detail.wave_row_no > 0 then 
                    strCondition = "S_WAVE_NO = '"..dc_detail.wave_no.."' AND N_ROW_NO = "..dc_detail.wave_row_no
                    strSetAttr = "F_ACC_O_QTY = F_ACC_O_QTY +"..dc_detail.acc_p_qty
                    if  cancel and lua.equation( 0, cancel_qty ) == false  then
                        strSetAttr = strSetAttr..", F_ACC_C_QTY = F_ACC_C_QTY + "..cancel_qty
                    end     
                        
                    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "OW_Detail", strCondition, strSetAttr )
                    if nRet ~= 0 then 
                        return 1, "设置【OW_Detail】累计出库数量失败!"..strRetInfo 
                    end                      
                end
            end
        elseif  dc_detail.bs_type == 'Outbound_Wave'  then
            -- 出库波次不需要根据出库单进行分拣出库
            if  dc_detail.bs_no ~= nil and dc_detail.bs_no ~= ''  then
                strCondition = "S_WAVE_NO = '"..dc_detail.bs_no.."' AND N_ROW_NO = "..dc_detail.bs_row_no
                strSetAttr = "F_ACC_O_QTY = F_ACC_O_QTY +"..dc_detail.acc_p_qty
                -- MDY BY HAN @20250812 增加了异常处理记录，出库操作会继续补料出库，因此这里不适合加上关闭数量
                -- MDY BY HAN @20251201 加一个cfg.cancel 变量来控制是否采用取消数量
                if  cancel and lua.equation( 0, cancel_qty ) == false  then
                    strSetAttr = strSetAttr..", F_ACC_C_QTY = F_ACC_C_QTY + "..cancel_qty
                end     
                      
                nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "OW_Detail", strCondition, strSetAttr )
                if nRet ~= 0 then 
                    return 1, "设置【OW_Detail】累计出库数量失败!"..strRetInfo 
                end  
            end
        end 
        
        -- 如果有拣料箱插入拣料箱明细
        if picking_box_code ~= '' then
            local dc_detail_id = lua.trim_guid_str( dc_detail_list[n].id )
            local dc_detail_data = {}
            nRet, dc_detail_data = m3.ObjAttrToObjJson( "Distribution_CNTR_Detail", lua.table2str(dc_detail_list[n].attrs) )
            if nRet ~= 0 then
                return 1, "objAttrToObjJson 失败! "..dc_detail_data
            end
            -- 获取料箱
            nRet, cntr = wms_cntr.GetInfo( strLuaDEID, picking_box_code )
            if nRet ~= 0 or cntr == '' then 
                return 1, "拣料箱'"..picking_box_code.."'不存在!"
            end
            -- 获取当前激活的可用的料箱箱    
            strCondition = "S_CNTR_CODE = '"..picking_box_code.."' AND N_B_STATE = "..PICKING_CNTR_STATE.WaitPicking
            nRet, picking_cntr = m3.GetDataObjByCondition( strLuaDEID,"Picking_CNTR", strCondition )   
            if nRet == 1 then
                -- 不存在创建一个
                picking_cntr = m3.AllocObject( strLuaDEID, "Picking_CNTR" )
                if picking_cntr == nil then
                    return 1, "m3.AllocObject 失败! "
                end
                picking_cntr.b_state = PICKING_CNTR_STATE.WaitPicking
                picking_cntr.cntr_code = picking_box_code
                picking_cntr.bs_type = dc_detail.bs_type
                picking_cntr.bs_no = dc_detail.bs_no
                picking_cntr.station = dc_detail.station
                picking_cntr.loc_code = dc_detail.put_wall_no
                nRet, picking_cntr = m3.CreateDataObj( strLuaDEID, picking_cntr )
                if nRet ~= 0  then 
                    return 2, "创建【拣料箱】失败!"..picking_cntr 
                end  
            elseif nRet ~= 0 then
                return 2, picking_cntr
            end      
        
            local pc_detail_data = m3.AllocObject2( strLuaDEID, "Picking_CNTR_Detail" )
            pc_detail_data.S_PC_NO = picking_cntr.pc_no
            -- 获取行号
            local row_no
            nRet,row_no = mobox.getSerialMaxNumber( "行号", pc_detail_data.S_PC_NO )
            if nRet ~= 0 then
                return 1,  "获取拣料箱明细行号时失败!"..row_no
            end
            pc_detail_data.N_ROW_NO = row_no

            for m = 1, #DC_DETAIL_ATTRS do
                pc_detail_data[DC_DETAIL_ATTRS[m]] = dc_detail_data[DC_DETAIL_ATTRS[m]]
            end
            pc_detail_data.S_CNTR_CODE = picking_box_code
            pc_detail_data.F_QTY = dc_detail.acc_p_qty
            pc_detail_data.F_PLAN_QTY = dc_detail.qty
            pc_detail_data.G_DC_DETAIL_ID = dc_detail_id
            pc_detail_data.S_STATION_NO = dc_detail.station
            nRet, pc_detail_data = m3.CreateDataObj2( strLuaDEID, pc_detail_data )
            if nRet ~= 0  then 
                return 2, "创建【拣料箱明细】失败!"..pc_detail_data 
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

-- 根据物料/货品号创建指定出库作业（可能会有多个容器）
-- SOO -- Specify Outbound Operation
-- ** 此函数尚未完成实现，暂不可用 **
-- @function wms_out.Create_SOO_ByMaterial
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string station 分拣站台, 必须有值
-- @tparam string so_no 指定出库指令号, 必须有值
-- @tparam string area_code 库区编码, 必须有值
-- @tparam string item_code 物料货品编码, 必须有值
-- @tparam string to_loc_code 出库口货位, 必须有值
-- @tparam string op_def_name 作业类型
-- @tparam string source_sys 来源系统
-- @treturn number 0=成功, 1=失败
-- @treturn string|nil 错误信息, 成功时 nil
--[[
下面代码还不完整，等下次完善指定出库的时候再来完善
function wms_out.Create_SOO_ByMaterial( strLuaDEID, station, so_no, area_code, item_code, to_loc_code, op_def_name, source_sys )
    local nRet, strRetInfo, n

    -- step1：输入参数合法性检查
    if so_no == nil or so_no == '' then
        return 1, "so_no 必须有值!"
    end
    if area_code == nil or area_code == '' then
        return 1, "area_code 必须有值!"
    end
    if source_sys == nil then
        source_sys = ""
    end
    if item_code == nil or item_code == '' then
        return 1, "item_code 必须有值!"
    end
    if to_loc_code == nil or to_loc_code == '' then
        return 1, "loc_code 必须有值!"
    end
    if station == nil or station == '' then
        return 1, "station 必须有值!"
    end

    local lua_info
    nRet, lua_info = lua.GetLuaDEInfo( strLuaDEID )
    if nRet ~= 0 then
        return 1, "GetLuaDEInfo 失败!"..lua_info
    end

    -- 判断目标货位是否正确
    local to_loc
    nRet, to_loc = wms_wh.GetLocInfo( to_loc_code )
    if nRet ~= 0 then
        return 1, '获取货位信息失败! '..to_loc
    end

    -- 通过货品找出货品所在容器
    local str_good_condition
    local success, queryInfo, dataSet
    local nPage, nPageCount
    local cntr_code

    if lua_info.dbtype == DB_TYPE.SQLServer then
        str_good_condition = "S_ITEM_CODE = '"..item_code.."' AND S_CNTR_CODE in "..
                            "(select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE in (select S_CODE from TN_Location with (NOLOCK) where S_AREA_CODE = '"..area_code.."'))"
    else
        str_good_condition = "S_ITEM_CODE = '"..item_code.."' AND S_CNTR_CODE in "..
                             "(select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE in (select S_CODE from TN_Location where S_AREA_CODE = '"..area_code.."'))"
    end

    -- 查询有该货品的容器编号
    -- 获取货品所在容器（考虑到有比较极端情况容器数量大于1000因此采用 queryDataObjAttr2 ）        
    nRet, strRetInfo = mobox.queryDataObjAttr2( strLuaDEID, "INV_Detail", str_good_condition, strOrder, 100, "S_CNTR_CODE" )
    if nRet ~= 0 then
        return 1, "queryDataObjAttr2: "..strRetInfo
    end
    if strRetInfo == '' then
        return 0
    end

    success, queryInfo = pcall( json.decode, strRetInfo )
    if success == false then
        return 2, "queryDataObjAttr2 返回结果啊非法的JSON格式!"
    end

    nPageCount = queryInfo.pageCount
    nPage = 1
    dataSet = queryInfo.dataSet       -- 查询出来的数据集
    local count = 0
    while (nPage <= nPageCount) do
        for i = 1, #dataSet do
            cntr_code = dataSet[i].attrs[1].value
            nRet, strRetInfo = create_so_cntr_operation( strLuaDEID, station, so_no, cntr_code, to_loc, item_code, source_sys )
            if  nRet ~= 0   then  
                return 1, "create_so_cntr_operation! ".. strRetInfo 
            end
            count = count + 1
        end

        nPage = nPage + 1
        if  nPage <= nPageCount  then
            -- 取下一页
            nRet, strRetInfo = mobox.queryDataObjAttr2( strLuaDEID, nPage)
            if  nRet ~= 0  then
                return 2, "queryDataObjAttr2失败! nPage="..nPage.."  "..strRetInfo
            end 
            queryInfo = json.decode(strRetInfo) 
            dataSet = queryInfo.dataSet 
        end
    end    

    -- 设置 Specify_Outbound 状态为执行 N_B_STATE = 2 执行中
    local strUpdateSql = "N_B_STATE = 2, N_CNTR_TOTAL = "..count
    local strCondition = "S_SO_NO = '"..so_no.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Specify_Outbound", strCondition, strUpdateSql )
    if  nRet ~= 0  then  
        return 2, "更新【Specify_Outbound】信息失败!"..strRetInfo
    end               
    return 0
end
--]]

-- 配盘明细按体积排序函数（table.sort 回调），体积大的放前面
-- @function dc_detail_sort_by_volume
-- @tparam table t1 配盘明细对象1 (需含 volume, qty 属性)
-- @tparam table t2 配盘明细对象2 (需含 volume, qty 属性)
-- @treturn boolean t1 总体积是否大于 t2
local function dc_detail_sort_by_volume( t1, t2 )
    return t1.volume*t1.qty > t2.volume*t2.qty 
end

-- 拣料箱按体积排序函数（table.sort 回调），体积大的放前面
-- @function picking_box_sort_by_volume
-- @tparam table t1 拣料箱对象1 (需含 box_volume 属性)
-- @tparam table t2 拣料箱对象2 (需含 box_volume 属性)
-- @treturn boolean t1 箱体体积是否大于 t2
local function picking_box_sort_by_volume( t1, t2 )
    return t1.box_volume> t2.box_volume 
end

-- 将配盘明细按体积批分到拣料箱中
-- 体积大的货品优先分配，拣料箱按剩余容积排列
-- @function wms_out.Split_CD_Detial_ByPickingBox
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table d_cntr_detail_list 配盘明细列表（需包含 volume, qty, item_code 等属性）
-- @tparam string picking_box_code 拣料箱编码, 多个拣料箱用 ; 分隔
-- @tparam table new_d_cntr_detail_list 批分结果列表, 作为输出参数
-- @treturn number 0=成功, 1=分配失败（体积过大无法放入拣料箱）
-- @treturn string|nil 错误信息, 成功时 nil
function wms_out.Split_CD_Detial_ByPickingBox( strLuaDEID, d_cntr_detail_list, picking_box_code, new_d_cntr_detail_list )

    local seg = lua.split( picking_box_code, ";" )   


    -- 初始化拣料箱
    local picking_box_list = {}
    local box_volume = wms_base.Get_nConst( strLuaDEID, "拣料箱体积")       -- ???
    local pick_box_num = #seg
    for n = 1, pick_box_num do  
        local picking_box = {
            picking_box_code = seg[n],
            box_volume = box_volume,
        }  
        table.insert( picking_box_list, picking_box )
    end

    -- 把体积大的放前面
    table.sort( d_cntr_detail_list, dc_detail_sort_by_volume )

    -- 批分到不同的拣料箱
    local find, volume, qty, need_split_qty

    for n = 1, #d_cntr_detail_list do
        find = false
        volume = d_cntr_detail_list[n].qty*d_cntr_detail_list[n].volume
        for m = 1, pick_box_num do
            if  volume <= picking_box_list[m].box_volume  then
                d_cntr_detail_list[n].pick_box_code = picking_box_list[m].picking_box_code
                picking_box_list[m].box_volume = picking_box_list[m].box_volume - volume
                find = true
                break
            end
        end
        if  find  then
            table.insert( new_d_cntr_detail_list, d_cntr_detail_list[n] )
        else
            -- 需要批分，把一条【配盘明细】根据拣料箱
            need_split_qty = d_cntr_detail_list[n].qty       -- 需要批分的数量

            for m = 1, pick_box_num do
                if  picking_box_list[m].box_volume > 0  then
                    qty = math.floor( picking_box_list[m].box_volume/ d_cntr_detail_list[n].volume )
                    if  need_split_qty < qty  then
                        qty = need_split_qty
                    end
                    need_split_qty = need_split_qty - qty

                    local d_cntr_detail = {
                        item_code = d_cntr_detail_list[n].item_code,
                        item_name = d_cntr_detail_list[n].item_name,
                        cntr_code = d_cntr_detail_list[n].cntr_code,
                        batch_no = d_cntr_detail_list[n].batch_no,
                        cell_no = d_cntr_detail_list[n].cell_no,
                        station = d_cntr_detail_list[n].station,
    
                        serial_no = d_cntr_detail_list[n].serial_no,
                        item_spec = d_cntr_detail_list[n].item_spec,
                        end_user = d_cntr_detail_list[n].end_user,
                        owner = d_cntr_detail_list[n].owner,        
                        uom = d_cntr_detail_list[n].uom,     
                        volume = d_cntr_detail_list[n].volume,  
                        weight = d_cntr_detail_list[n].weight,                          
                        wh_code = d_cntr_detail_list[n].wh_code,                 
                        area_code = d_cntr_detail_list[n].area_code,                 
                        loc_code = d_cntr_detail_list[n].loc_code,                 
    
                        inv_detail_id = d_cntr_detail_list[n].inv_detail_id,
                        bs_type = d_cntr_detail_list[n].bs_type,
                        bs_no = d_cntr_detail_list[n].bs_no,
                        bs_row_no = d_cntr_detail_list[n].bs_row_no,
                        wave_no = d_cntr_detail_list[n].wave_no,
                        wave_cls_id = d_cntr_detail_list[n].wave_cls_id,

                        pick_box_code = picking_box_list[m].picking_box_code,
                        qty = qty
                    }
                    picking_box_list[m].box_volume = picking_box_list[m].box_volume - qty*d_cntr_detail_list[n].volume
                    table.insert( new_d_cntr_detail_list, d_cntr_detail )
                end
                if  need_split_qty == 0  then
                    break
                end
            end

            -- 如果还有 need_split_qty 说明无法分配拣货箱，这是有问题的需要报警
            if  need_split_qty > 0  then
                return 1, "货品'"..d_cntr_detail_list[n].item_code.."'因为体积的原因无法分配拣料箱!"
            end
        end

        -- 把拣料箱可用容积最大的放前面
        table.sort( picking_box_list, picking_box_sort_by_volume )
    end
    return 0
end

-- 根据配盘明细创建拣料箱/拣料箱明细
-- 如果拣料箱不存在则先创建，然后创建拣料箱明细记录
-- @function wms_out.Creat_Picking_CNTR_Detail
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string dc_detail_id 配盘明细标识（Distribution_CNTR_Detail.S_ID）, 必须有值
-- @tparam number qty 拣料数量, 必须有值且大于0
-- @tparam string pc_code 拣料箱编码, 必须有值
-- @tparam string pc_cell_no 拣料箱料格号, 可为空
-- @tparam table|nil ext_parameter 扩展参数 {picking_cntr_must_binding_loc=true/false}, 可为空
-- @treturn number 0=成功, 1=参数错误, 2=创建失败
-- @treturn table pc_detail_data Picking_CNTR_Detail 数据对象（数据库表属性模式）, 或错误信息字符串
function wms_out.Creat_Picking_CNTR_Detail( strLuaDEID, dc_detail_id, qty, pc_code, pc_cell_no, ext_parameter )
    local nRet
    local pc_detail_data = {}

    if dc_detail_id == nil or dc_detail_id == '' then
        return 1, "wms_out.Creat_Picking_CNTR_Detail 输入参数中 dc_detail_id 必须有值！"
    end
    if pc_code == nil or pc_code == '' then
        return 1, "wms_out.Creat_Picking_CNTR_Detail 输入参数中 pc_code 必须有值!"
    end  
    if qty == nil or qty <= 0 then
        return 1, "wms_out.Creat_Picking_CNTR_Detail 输入参数中 qty 不合规!"
    end   
    if pc_cell_no == nil then
        pc_cell_no = ''
    end

    -- MDF BY HAN @20251030
    local picking_cntr_must_binding_loc = true      -- 拣料箱必须绑定货位
    if ext_parameter ~= nil and type(ext_parameter) == "table" then
        picking_cntr_must_binding_loc = ext_parameter.picking_cntr_must_binding_loc
        if picking_cntr_must_binding_loc == nil then
            picking_cntr_must_binding_loc = true
        end
    end

    -- 获取配盘明细对象
    local dc_detail_data
    dc_detail_id = lua.trim_guid_str( dc_detail_id )
    nRet, dc_detail_data = m3.GetDataObject2( strLuaDEID, "Distribution_CNTR_Detail", dc_detail_id ) 
    if  nRet ~= 0  then 
        lua.Stop( strLuaDEID, dc_detail_data )
        return
    end 

    -- 首先检查一下是否存在没封箱的【拣料箱】，如果不存在需要先创建
    local picking_cntr  
    local strCondition = "N_B_STATE = "..PICKING_CNTR_STATE.WaitPicking.." AND S_CNTR_CODE = '"..pc_code.."'"
    nRet, picking_cntr = m3.GetDataObjByCondition( strLuaDEID, "Picking_CNTR", strCondition )
    if  nRet == 1  then  
        -- 不存在需要新增【拣料箱】
        local loc_code = ''
        if picking_cntr_must_binding_loc then
            nRet, loc_code = wms_cntr.Get_Container_Loc( strLuaDEID, pc_code )
            if nRet ~= 0 or loc_code == '' then
                return 1, "wms_cntr.Get_Container_Loc 失败!"..loc_code
            end
        end
        picking_cntr = m3.AllocObject( strLuaDEID, "Picking_CNTR" )
        picking_cntr.b_state = PICKING_CNTR_STATE.WaitPicking
        picking_cntr.cntr_code = pc_code
        picking_cntr.bs_type = dc_detail_data.S_BS_TYPE
        picking_cntr.bs_no = dc_detail_data.S_BS_NO
        picking_cntr.station = dc_detail_data.S_STATION_NO
        picking_cntr.loc_code = loc_code
        nRet, picking_cntr = m3.CreateDataObj(strLuaDEID, picking_cntr)
        if nRet ~= 0  then 
            return 2, "创建【拣料箱】失败!"..picking_cntr 
        end   
    elseif nRet ~= 0 then
        return 2, picking_cntr
    end      

    pc_detail_data = m3.AllocObject2( strLuaDEID, "Picking_CNTR_Detail" )
    pc_detail_data.S_PC_NO = picking_cntr.pc_no
    for m = 1, #DC_DETAIL_ATTRS do
        pc_detail_data[DC_DETAIL_ATTRS[m]] = dc_detail_data[DC_DETAIL_ATTRS[m]]
    end
    pc_detail_data.S_CNTR_CODE = pc_code
    pc_detail_data.S_CELL_NO = pc_cell_no
    pc_detail_data.F_QTY = qty
    pc_detail_data.G_DC_DETAIL_ID = dc_detail_id
    nRet, pc_detail_data = m3.CreateDataObj2( strLuaDEID, pc_detail_data)
    if nRet ~= 0  then 
        return 2, "创建【拣料箱明细】失败!"..pc_detail_data 
    end 

    return 0, pc_detail_data
end

-- 根据选中的出库单创建出库波次
-- 支持相同匹配规则的SKU数量合并（C_QTY_SUM='Y'）和分播（C_SORTING='Y'）
-- @function wms_out.Create_Outbound_Wave
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table ow_data 出库波次数据对象（AllocObject2 生成）, 包含 S_WH_CODE, C_QTY_SUM, C_SORTING, S_MATCH_RULE 等属性, 必须有值
-- @tparam table oo_no_set 出库单编码数组 {"oo1","oo2",...}, 不能为空
-- @treturn number 0=成功, 1=参数错误, 2=创建失败
-- @treturn table ow_data 创建成功后的出库波次数据对象, 或错误信息字符串
function wms_out.Create_Outbound_Wave( strLuaDEID, ow_data, oo_no_set  )
    local nRet, strRetInfo

    if lua.IsTableEmpty( oo_no_set ) then
        return 1,"Create_Outbound_Wave 函数的输入参数 oo_no_set 必须有值!"
    end

    -- 获取出库波次对象中的匹配规则分拣规则
    local ow_match_rule =  ow_data.S_MATCH_RULE or ''

    -- 创建出库波次
    nRet, ow_data = m3.CreateDataObj2( strLuaDEID, ow_data )
    if nRet ~= 0 then 
        return 2, '创建【出库波次】对象失败!'..ow_data
    end  
    -- 获取出库波次号
    local ow_no = ow_data.S_WAVE_NO
    local qty_sum = ( ow_data.C_QTY_SUM == 'Y' )        -- true 表示要合并相同SKU数量
    local strUpdateSql, strCondition
    local oo_detail_list = {}
    -- 创建 OW_Compose
    for _, oo_no in ipairs(oo_no_set) do
        local ow_compose_data = m3.AllocObject2( strLuaDEID, "OW_Compose" )
        ow_compose_data.S_WAVE_NO = ow_no
        ow_compose_data.S_OO_NO = oo_no
        nRet, ow_compose_data = m3.CreateDataObj2(strLuaDEID, ow_compose_data)
        if nRet ~= 0 then
            return 2, '创建【OW_Compose】对象失败!' .. strRetInfo
        end

        -- 更新出库单对象中的 S_WAVE_NO 属性
        strUpdateSql = "S_WAVE_NO = '"..ow_no.."'"
        strCondition = "S_NO = '"..oo_no.."'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Outbound_Order", strCondition, strUpdateSql )
        if nRet ~= 0 then  
            return 2, "更新【出库单】信息失败!"..strRetInfo
        end 
        
        -- 获取出库单明细
        local oo_detail = {}
        strCondition = "S_OO_NO = '"..oo_no.."'"

        nRet, oo_detail = m3.QueryDataObject(strLuaDEID, "Outbound_Detail", strCondition, "N_ROW_NO" )
        if nRet ~= 0 then 
            return 2, oo_detail 
        end
        if  oo_detail ~= '' then
            for i = 1, #oo_detail do
                local object_attr = m3.KeyValueAttrsToObjAttr(oo_detail[i].attrs)
                if object_attr == nil then
                    return 1, "转换对象属性失败!"
                end
                object_attr.qty = lua.Get_NumAttrValue( object_attr.F_QTY )
                table.insert( oo_detail_list, object_attr )
            end
        end        
    end
    
    local ow_detail_base_attrs_count = #OW_DETAIL_BASE_ATTRS
    local udf_attrs_count = #UDF_ATTRS

    if not qty_sum then
        local row = 1
        for _, oo_detail in ipairs( oo_detail_list ) do
            local ow_detail_data = m3.AllocObject2( strLuaDEID, "OW_Detail" )
            for m = 1, ow_detail_base_attrs_count do
                ow_detail_data[OW_DETAIL_BASE_ATTRS[m]] = oo_detail[OW_DETAIL_BASE_ATTRS[m]]
            end
            for m = 1, udf_attrs_count do
                ow_detail_data[UDF_ATTRS[m]] = oo_detail[UDF_ATTRS[m]]
            end 
            ow_detail_data.S_WAVE_NO = ow_no
            ow_detail_data.N_ROW_NO = row
            row = row + 1
            ow_detail_data.S_OO_NO = oo_detail.S_OO_NO
            ow_detail_data.N_OO_ROW_NO = oo_detail.N_ROW_NO
            nRet, ow_detail_data = m3.CreateDataObj2(strLuaDEID, ow_detail_data)
            if nRet ~= 0 then
                return 2, '创建【OW_Detail】对象失败!' .. ow_detail_data
            end            
        end
    else
        -- 相同匹配规则的SKU数量需要合并 ( S_MATCH_RULE 中的属性值一样 )

        -- step1 数据准备
        -- 获取出库单对象属性定义
        local oo_obj_list = {}
        for _, oo_no in ipairs(oo_no_set) do
            local outbound_order
            strCondition = "S_NO = '"..oo_no.."'"
            nRet, outbound_order = m3.GetDataObjByCondition(strLuaDEID, "Outbound_Order", strCondition)
            if nRet ~= 0 then
                return 2, "获取出库单信息失败!" .. outbound_order
            end     
            oo_obj_list[oo_no] = outbound_order
        end

        -- step2 遍历 oo_detail_list 进行相同货品数量合并
        local oo_match_rule, oo_picking_rule, oo_mr_weaken
        local ow_detail_list = {}
        local find

        -- 遍历出库单里所有出库单明细
        for _, oo_detail in ipairs( oo_detail_list ) do  
            -- 获取SKU的匹配规则
            -- 如果SKU本身有定义匹配规则，那么先采用SKU的，没有采用出库单的，出库单没有采用出库波次的
            local oo_obj = oo_obj_list[oo_detail.S_OO_NO]
            if oo_obj == nil then
                return 2, "出库单'"..oo_detail.oo_no.."'数据异常!"
            end
            nRet, oo_match_rule, oo_picking_rule, oo_mr_weaken = wms_out.Get_OutboudOrder_MatchPickin_Rule2( strLuaDEID, oo_obj.outbound_order )
            if nRet ~= 0 then
                return 2, "获取匹配规则失败!"..oo_match_rule
            end
            local match_attrs = oo_detail.match_rule or ''
            if match_attrs == '' then
                match_attrs = oo_match_rule
            end
            if match_attrs == '' then
                match_attrs = ow_match_rule
            end

            --把匹配规则属性字符串，转变成 {"attr1","attrs2",...}
            local seg_attrs = {}
            if match_attrs ~= '' then
                seg_attrs = lua.split( match_attrs, ';' )
            end
            -- 匹配属性要加上 S_ITEM_CODE, S_STRORER, S_ITEM_STATE
            if not lua.IsInTable( "S_STORER", seg_attrs ) then
                table.insert( seg_attrs, "S_STORER" )
            end
            if not lua.IsInTable( "S_ITEM_STATE", seg_attrs ) then
                table.insert( seg_attrs, "S_ITEM_STATE" )
            end 
            if not lua.IsInTable( "S_ITEM_CODE", seg_attrs ) then
                table.insert( seg_attrs, "S_ITEM_CODE" )
            end 

            -- 检查一下ow_detail_list中是否有存在可以合并的SKU
            find = false
            local match_attr_count = #seg_attrs
            for _, ow_detail in ipairs(ow_detail_list) do
                -- 先判断 S_ITEM_CODE 这样效率高一些
                for n = match_attr_count, 1, -1 do
                    if  ow_detail[seg_attrs[n]] ~= oo_detail[seg_attrs[n]]  then
                        find = false
                        break
                    end
                end 
                if find then
                    ow_detail.qty = ow_detail.qty + oo_detail.qty
                    local compose = {
                        oo_no = oo_detail.S_OO_NO,
                        row_no = oo_detail.N_ROW_NO
                    }
                    ow_detail.S_OO_NO = ''
                    ow_detail.N_OO_ROW_NO = 0
                    table.insert( ow_detail.compose_list, compose )
                    break
                end
            end

            if not find then
                local ow_detail = lua.table_deepcopy( oo_detail )
                ow_detail.compose_list = {}
                local compose = {
                    oo_no = oo_detail.S_OO_NO,
                    row_no = oo_detail.N_ROW_NO
                }     
                table.insert( ow_detail.compose_list, compose )
                ow_detail.S_OO_ON = oo_detail.S_OO_NO
                ow_detail.N_OO_ROW_NO = oo_detail.N_ROW_NO               
                table.insert( ow_detail_list, ow_detail )
            end
        end

        -- 生成 OW_Detail 并且更新 
        local row = 1
        for _, ow_detail in ipairs( ow_detail_list ) do
            local ow_detail_data = m3.AllocObject2( strLuaDEID, "OW_Detail" )
            for m = 1, ow_detail_base_attrs_count do
                ow_detail_data[OW_DETAIL_BASE_ATTRS[m]] = ow_detail[OW_DETAIL_BASE_ATTRS[m]]
            end
            for m = 1, udf_attrs_count do
                ow_detail_data[UDF_ATTRS[m]] = ow_detail[UDF_ATTRS[m]]
            end 
            ow_detail_data.S_WAVE_NO = ow_no
            ow_detail_data.N_ROW_NO = row

            ow_detail_data.S_OO_NO = ow_detail.S_OO_NO
            ow_detail_data.N_OO_ROW_NO = ow_detail.N_ROW_NO
            nRet, ow_detail_data = m3.CreateDataObj2(strLuaDEID, ow_detail_data)
            if nRet ~= 0 then
                return 2, '创建【OW_Detail】对象失败!' .. ow_detail_data
            end  

            -- 更新 Outbound_Detail 中的出库波次信息
            for _, compose in ipairs( ow_detail.compose_list ) do
                strUpdateSql = "S_WAVE_NO = '"..ow_no.."', N_WAVE_ROW_NO = "..row
                strCondition = "S_OO_NO = '"..compose.oo_no.."' AND N_ROW_NO = "..compose.row_no
                nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Outbound_Detail", strCondition, strUpdateSql )
                if nRet ~= 0 then  
                    return 2, "更新【出库单明细】信息失败!"..strRetInfo
                end                 
            end
            row = row + 1            
        end        
    
    end
    return 0, ow_data

end

-- 校验分拣操作入口参数 (_Post_Picking_Operations 的子函数)
-- 检查 parameter 是否为 table，以及 cntr_code/loc_code/dc_no/bs_no 等必填字段是否存在
-- @function check_ppo_parameter
-- @tparam table|nil parameter 分拣输入参数 {
--   cntr_code -- 容器编码 (必填)
--   loc_code -- 容器货位 (必填)
--   dc_no -- 配盘流水号 (必填)
--   bs_no -- 播种流水号 (必填)
-- }
-- @treturn boolean true=校验通过
-- @treturn string|nil 错误信息, 成功时 nil
local function check_ppo_parameter( parameter )
    if parameter == nil or type(parameter) ~= "table" then
        return false, "分拣输入参数 parameter 不能为空! 并且必须是 table 类型!"
    end
    if parameter.cntr_code == nil or parameter.cntr_code == "" then
        return false, "容器代码 cntr_code 不能为空!"
    end
    if parameter.loc_code == nil or parameter.loc_code == "" then
        return false, "容器货位 loc_code 不能为空!"
    end 
    if parameter.dc_no == nil or parameter.dc_no == "" then
        return false, "配盘流水号 dc_no 不能为空!"
    end   
    if parameter.bs_no == nil or parameter.bs_no == "" then
        return false, "播种流水号 bs_no 不能为空!"
    end      
    return true
end

-- 校验分拣配置参数 (_Post_Picking_Operations 的子函数)
-- 检查 picking_cfg 是否为 table，并对其中的事件配置字段进行类型校验和默认值设置
-- @function check_ppo_picking_cfg
-- @tparam table|nil picking_cfg 分拣配置参数 {
--   anomaly_handle_event -- 出库异常处理事件 (string, 可选, 默认"")
--   go_back_event -- 回库事件 (string, 可选, 默认"")
--   post_outbound_event -- 出库完成后事件 (string, 可选, 默认"")
-- }
-- @treturn boolean true=校验通过
-- @treturn string|nil 错误信息, 成功时 nil
local function check_ppo_picking_cfg( picking_cfg )
    if picking_cfg == nil or type(picking_cfg) ~= "table" then
        return false, "分拣配置参数 picking_cfg 不能为空! 并且必须是 table 类型!"
    end   

    if picking_cfg.anomaly_handle_event == nil then
        picking_cfg.anomaly_handle_event = ""
    end
    if type(picking_cfg.anomaly_handle_event) ~= "string" then
        return false, "分拣配置参数 picking_cfg.anomaly_handle_event 必须是 string 类型!"
    end      

    if picking_cfg.go_back_event == nil then
        picking_cfg.go_back_event = ""
    end
    if type(picking_cfg.go_back_event) ~= "string" then
        return false, "分拣配置参数 picking_cfg.go_back_event 必须是 string 类型!"
    end  

    if picking_cfg.post_outbound_event == nil then
        picking_cfg.post_outbound_event = ""
    end
    if type(picking_cfg.post_outbound_event) ~= "string" then
        return false, "分拣配置参数 picking_cfg.post_outbound_event 必须是 string 类型!"
    end
    return true
end

-- 检查 action_set 是否为 table 且非空
-- @function check_ppo_action_set
-- @tparam table|nil action_set 动作集配置数组, 不能为空
-- @treturn boolean true=校验通过
-- @treturn string|nil 错误信息, 成功时 nil
local function check_ppo_action_set( action_set )
    if action_set == nil or type(action_set) ~= "table" then
        return false, "动作集配置参数 action_set 不能为空! 并且必须是 table 类型!"
    end
    if #action_set == 0 then
        return false, "动作集配置参数 action_set 不能为空!"
    end
    return true
end

--[[
    核心函数: 用在分拣任务完成后调用

    检查当前正在分拣的料箱容器 dc_no (配盘容器) 下面的 detail 是否已经完成处理完成，
    如果完成处理表示该容器分拣完成，把【配盘/Distribution_CNTR】设置为WaitBack（等待回库）
    并且触发:
        -- 料箱回库事件
        -- 料箱出库完成后事件
    输入参数：
        parameter --   分拣输入面板的参数 (加了 picking_box_code 拣料箱)
                    {
                        cntr_code -- 分拣容器编码
                        loc_code -- 分拣容器当前货位
                        dc_no -- Distribution_CNTR 配盘容器流水号
                        bs_no -- 来源单号
                        picking_box_code -- 拣料箱编码（分拣出来的货品放这个容器）
                    }
        picking_cfg -- 分拣操作配置参数
        {
            anomaly_handle_event -- 出库异常处理事件
            go_back_event -- 回库事件，如果有值就触发
            get_putway_loc_first = true/false false -- 表示在在创建回库作业时候先不计算回库货位
            cross_station_path_limit = true  -- 表示跨站台搬运的时候不是所有站台都可以连通
            post_outbound_event -- 出库完成后事件
            empty_cntr_handling_mode -- "unbind/goback/prompt/trigger_event"
            empty_cntr_handle_event -- 空箱处理事件用于
        }
        action_set -- 动作集配置参数
        {
        -- 主页面刷新动作
            {
                action_type = "refresh_master_panel",
                value = {
                    sub_page = {"当前任务"}
                }
            },
        -- 分拣输入页面刷新动作
            {
                action_type = "set_dlg_attr",
                value = {
                    {
                        attr = "S_ITEM_CODE",
                        value = ""
                    }, 
                    ...
                }
            }
        -- 分拣播种等显示页面刷新动作
            {
                action_type = "refresh_related_panel",
                value = {
                    {
                        panel_name = "播种墙显示",
                        input_parameter = {
                            cell_no = "",
                            loc_code = ""
                        }
                    }, 
                    {
                        panel_name = "拣料箱显示",
                        input_parameter = {
                            loc_code = ''
                        }
                    }
                }
            },
            ...

    返回值：
        action_list -- 动作集, nil
        err -- 错误信息
]]
-- 配盘数据对象分拣后处理程序 等同于以前的 Distribution_CNTR_PostProcess
-- @function wms_out._Post_Picking_Operations
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table parameter 分拣输入页面的参数, 必须有值
-- @tparam table picking_cfg 分拣操作配置参数, 必须有值
-- @tparam table action_set 动作集配置参数, 必须有值
-- @treturn table|nil action nil
-- @treturn string|nil 错误信息，成功时 nil
function wms_out._Post_Picking_Operations( strLuaDEID, parameter, picking_cfg, action_set )
    local nRet, strRetInfo
    local strCondition, strUpdateSql

    -- 检查输入参数是否合规
    local bRet, strErr = check_ppo_parameter(parameter)
    if not bRet then
        return nil, strErr
    end
    bRet, strErr = check_ppo_picking_cfg(picking_cfg)
    if not bRet then
        return nil, strErr
    end    
    bRet, strErr = check_ppo_action_set(action_set)
    if not bRet then
        return nil, strErr
    end      
    
    -- 容器有分拣出库后, 设置容器强制置满标记 C_FORCED_FILL = 'N'
    strCondition = "S_CODE = '" .. parameter.cntr_code .. "'"
    strUpdateSql = "C_FORCED_FILL = 'N'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Container", strCondition, strUpdateSql)
    if nRet ~= 0 then
        return nil, "更新【Container】信息失败!" .. strRetInfo
    end

    -- 当前的配盘中已经没有需要执行的出库任务
    local action = {}
    table.insert( action, action_set[1] )

    -- 检查当前料箱的分拣出库任务是否已经全部完成
    -- N_B_STATE = 1 表示可以执行的入库任务（未完成的分拣任务）
    local wave_no = parameter.wave_no or ''
    if wave_no ~= '' then
        strCondition = "S_CNTR_CODE = '" .. parameter.cntr_code .. "' AND N_B_STATE = 1 AND S_WAVE_NO = '" .. wave_no .. "'"
    else
        strCondition = "S_CNTR_CODE = '" .. parameter.cntr_code .. "' AND N_B_STATE = 1 AND S_BS_NO = '" .. parameter.bs_no .. "'"
    end

    nRet, strRetInfo = mobox.getDataObjCount(strLuaDEID, "Distribution_CNTR_Detail", strCondition)
    if nRet ~= 0 then
        return nil, strRetInfo
    end
    local nCount = lua.StrToNumber(strRetInfo)
    
    -- 料箱的分拣任务是否已经完成
    if nCount == 0 then
        -- 已经全部完成
        -- 获取配盘数据对象dc
        local dc
        nRet, dc = m3.GetDataObjectByKey(strLuaDEID, "Distribution_CNTR", "S_DC_NO", parameter.dc_no)
        if nRet ~= 0 then
            return nil, "无法获取编码 = '" .. parameter.dc_no .. "' 的【配盘】!"
        end
        -- 是否有定义回库作业类型
        if lua.StrIsEmpty(dc.back_op_name) then
            return nil, "【配盘】对象中 S_BACK_OP_NAME 必须有值!"
        end

        -- 获取容器的货位信息
        local loc
        nRet, loc = wms_wh.GetLocInfo(parameter.loc_code)
        if nRet ~= 0 then
            return nil, '获取货位信息失败! 货位 -->[' .. parameter.loc_code .. "] 原因: " .. loc
        end

        -- sbp01:配盘明细分拣后处理
        nRet, strRetInfo = wms_out.Distribution_CNTR_Detail_PostProcess(strLuaDEID, loc.wh_code, loc.area_code,
                                                parameter.loc_code, parameter.dc_no, parameter.picking_box_code)
        if nRet ~= 0 then
            return nil, 'wms_out.Distribution_CNTR_Detail_PostProcess!' .. strRetInfo
        end

        -- 如果需要出库异常处理（数量不足）需要补货
        if picking_cfg.anomaly_handle_event ~= '' then
            local data_objs, obj_attrs

            strCondition = "S_DC_NO = '" .. parameter.dc_no .. "' AND N_B_STATE = 0"
            nRet, data_objs = m3.QueryDataObject(strLuaDEID, "INV_Transfer_Anomaly", strCondition, "S_NO")
            if nRet ~= 0 then
                return nil, "QueryDataObject失败!" .. data_objs
            end
            if data_objs ~= '' then
                for n = 1, #data_objs do

                    obj_attrs = m3.KeyValueAttrsToObjAttr(data_objs[n].attrs)
                    if obj_attrs == nil then
                        return nil, "KeyValueAttrsToObjAttr转换失败!"
                    end
                    local add_wfp = {
                        wfp_type = 1, -- 触发数据对象事件（指定数据对象标识）
                        cls = "INV_Transfer_Anomaly",
                        obj_id = data_objs[n].id,
                        obj_name = "出库异常记录'" .. obj_attrs.S_NO .. "'-->出库异常处理",
                        trigger_event = picking_cfg.anomaly_handle_event
                    }
                    nRet, strRetInfo = m3.AddSysWFP(strLuaDEID, add_wfp)
                    if nRet ~= 0 then
                        return nil, "AddSysWFP失败!" .. strRetInfo
                    end
                end
            end
        end

        -- 配盘状态设置为拣货完成
        strUpdateSql = "N_B_STATE = " .. DIST_CNTR_STATE.PickingOK
        strCondition = "S_ID = '" .. dc.id .. "'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Distribution_CNTR", strCondition, strUpdateSql)
        if nRet ~= 0 then
            return nil, "更新【配盘】信息失败!" .. strRetInfo
        end

        --重置料箱信息
        local container
        nRet, container = wms_cntr.GetInfo( strLuaDEID, parameter.cntr_code )
        if nRet ~= 0 then 
            return nil, "获取【容器】信息失败! " .. container
        end      
        -- Reset料箱，如果料箱里没有货品，料箱会会变成空料箱
        nRet, strRetInfo = wms_cntr.Reset( strLuaDEID, container )
        if nRet ~= 0 then 
            return nil, "重置【容器】失败! " .. strRetInfo
        end 
        -- 空容器?
        if container.empty_full == EMPTY_FULL.Empty then
            -- 获取站台的空料箱处理策略
            local station_data
            nRet, station_data = m3.GetDataFromCache( "Machine_Station", dc.station )
            if nRet ~= 0 then
                return nil,  "获取站台信息失败! "..station_data
            end                
            
            -- C_EC_GOBACK = 'Y' 表示空料箱回库
            if station_data.C_EC_GOBACK ~= 'Y' then   
                -- 站台定义不回库，继续从 picking_cfg 里进行判断
                if picking_cfg.empty_cntr_handling_mode == "unbind" then
                    picking_cfg.go_back_event = ''      -- 不回库
                elseif picking_cfg.empty_cntr_handling_mode == "prompt" then
                    picking_cfg.go_back_event = ''
                elseif picking_cfg.empty_cntr_handling_mode == "trigger_event" then 
                    picking_cfg.go_back_event = ''
                end
            end         
        end

        -- 如果需要自动回库
        if picking_cfg.go_back_event ~= ''then
            -- 增加一个后台进程对配盘进行回库处理（启动回库作业）
            local add_wfp = {
                wfp_type = 1,
                cls = "Distribution_CNTR",
                obj_id = dc.id,
                obj_name = "配盘'" .. parameter.dc_no .. "'-->回库处理",
                datajson = { get_putway_loc_first = picking_cfg.get_putway_loc_first,
                             cross_station_path_limit = picking_cfg.cross_station_path_limit or false },
                trigger_event = picking_cfg.go_back_event
            }
            nRet, strRetInfo = m3.AddSysWFP(strLuaDEID, add_wfp)
            if nRet ~= 0 then
                return nil, "AddSysWFP失败!" .. strRetInfo
            end
        end

        -- 如果需要出库后处理
        if picking_cfg.post_outbound_event then
            -- 增加一个后台进程对配盘进行处理，触发配盘明细中的 出库单是否可以完成
            local add_wfp = {
                wfp_type = 1,
                cls = "Distribution_CNTR",
                obj_id = dc.id,
                obj_name = "配盘'" .. parameter.dc_no .. "'-->出库后处理",
                trigger_event = picking_cfg.post_outbound_event
            }
            nRet, strRetInfo = m3.AddSysWFP(strLuaDEID, add_wfp)
            if nRet ~= 0 then
                return nil, "AddSysWFP失败!" .. strRetInfo
            end
        end
        local action_count = #action_set

        for n = 2, action_count do
            table.insert( action, action_set[n] )
        end
    end
    return action
end

-- 创建缺件清单
--[[
    shortage_list = { 
        ｛  bs_type --Outbound_Order/Outbound_Wave
            bs_no -- 出库单或出库波次号
            qty -- 缺件数量
            item_detail = {S_ITEM_CODE,...} },
        ...
    }
--]]
-- @function wms_out._Create_Shortage_Detail
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table shortage_list 缺件清单, 必须有值
-- @treturn table|nil action nil
-- @treturn string|nil 错误信息，成功时 nil
function wms_out._Create_Shortage_Detail( strLuaDEID, shortage_list )
    local nRet
    local base_attr_count = #ITEM_BASE_ATTRS
    local udf_count = #UDF_ATTRS

    for _, shortage in ipairs( shortage_list ) do
        local shortage_detail_data = m3.AllocObject2(strLuaDEID, "Shortage_Detail")

        for m = 1, base_attr_count do
            shortage_detail_data[ITEM_BASE_ATTRS[m]] = shortage.item_detail[ITEM_BASE_ATTRS[m]]
        end

        for m = 1, udf_count do
            shortage_detail_data[UDF_ATTRS[m]] = shortage.item_detail[UDF_ATTRS[m]]
        end
        
        shortage_detail_data.F_QTY = shortage.qty
        if shortage.bs_type == "Outbound_Order" then
            shortage_detail_data.S_OO_NO = shortage.bs_no
        else
            shortage_detail_data.S_WO_NO = shortage.bs_no
        end
        shortage_detail_data.N_ROW_NO = shortage.item_detail.N_ROW_NO

        nRet, shortage_detail_data = m3.CreateDataObj2(strLuaDEID, shortage_detail_data)
        if nRet ~= 0 then
            return nil, "创建【缺件明细】失败!" .. shortage_detail_data
        end  
    end
    return true
end

-- 检查出库单/出库波次手工配盘结果
-- @function wms_out._Check_INV_Alloc
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string bs_type 出库单或出库波次, 必须有值
-- @tparam string bs_no 出库单或出库波次编码, 必须有值
-- @treturn boolean 分配完成 true / 分配未完成 false（有缺件）
-- @treturn string|nil 错误信息，成功时 nil
function wms_out._Check_INV_Alloc( strLuaDEID, bs_type, bs_no )
    local nRet

    if bs_type == nil or bs_type == '' then
        return nil, "wms_out._Check_INV_Alloc 函数中 bs_type 参数不能为空"
    end
    
    if bs_no == nil or bs_no == '' then
        return nil, "wms_out._Check_INV_Alloc 函数中 bs_no 参数不能为空"
    end
    
    local strCondition, data_objs
    if bs_type == "Outbound_Order" then
        strCondition = "S_OO_NO = '"..bs_no.."' AND F_QTY > F_ACC_D_QTY"
        nRet, data_objs = m3.QueryDataObject(strLuaDEID, "Outbound_Detail", strCondition, "N_ROW_NO" )
        if nRet ~= 0 then 
            return 2, "QueryDataObject失败!"..data_objs 
        end        
         
    elseif bs_type == "Outbound_Wave" then
        strCondition = "S_WAVE_NO = '"..bs_no.."' AND F_QTY > F_ACC_D_QTY"
        nRet, data_objs = m3.QueryDataObject(strLuaDEID, "OW_Detail", strCondition, "N_ROW_NO" )
        if nRet ~= 0 then 
            return 2, "QueryDataObject失败!"..data_objs 
        end        
    else
        return nil, "wms_out._Check_INV_Alloc 函数中 bs_type 参数错误"
    end   
    
    if #data_objs > 0 then
        return false, "存在未分配完成的出库明细"
    end
    
    return true
end

return wms_out
