--[[
    版本：     Version 1.0
    创建日期： 2023-6-16
    修改日期： 2026-6-16
    创建人：   HAN

    功能：
        和盘点相关的一些标准函数

        -- Create_CountOrder_ByCountPlan        根据盘点计划创建【盘点单】，触发指定数量的【计划盘点容器】执行盘点脚本
        -- Filter_Out_Empty_Bins                过滤空料箱，将盘点计划中的空料箱容器设为取消，不参与盘点
        -- CountCntr_PostProcess                盘点容器盘点完成后处理，有差异则生成【Count_Diff】
        -- Get_CountPlan_QueryPanel_Condition   获取盘点计划查询面板条件，支持货品/货位/容器三种盘点类型
        -- Count_Diff_RepeatCount               盘点差异复盘，创建盘点单、出库作业并给容器加盘点锁
        -- CountDiff_Transfter                  盘点差异转移处理，逐条调整库存量
        -- CountOrder_Transfter                 盘点单差异转移处理，查询并转移所有未转移的盘点差异

    更改说明：
        V2.0 MDF BY FCL @20260106 增加空料箱不参与盘点过滤条件 wms_count.Get_CountPlan_QueryPanel_Condition

    AI CHECK
        -- 20260616 统一函数注释格式，整理外部函数列表至文件头部
--]]

wms_cntr = require ("wms_container")
wms_wh = require ("wms_wh")
wms_inv = require ("wms_inventory")

local wms_count = {_version = "0.1.1"}

-- 根据盘点计划创建【盘点单】数据对象 (不建议使用，使用 Create_CountOrder_ByCountPlan2 )
-- 触发指定数量的【计划盘点容器】执行"Create_IWP_CNTR_Detail"脚本
-- @function wms_count.Create_CountOrder_ByCountPlan
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table count_plan 盘点计划数据对象
-- @tparam number method 盘点方法，1=人工到货位盘点，2=自动设备搬运到站台，默认2
-- @tparam string station 站台编码，method=2时必填
-- @tparam number num 盘点容器数量，0或不输入表示所有容器，默认0
-- @tparam boolean reject_emptybox 是否排斥空料箱盘点，默认true
-- @tparam string strOrder 盘点容器排序字段，默认'T_CREATE DESC'
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string 失败时返回错误信息
function wms_count.Create_CountOrder_ByCountPlan( strLuaDEID, count_plan, method, station, num, reject_emptybox, strOrder )
    local nRet, strRetInfo, n

    if strOrder == nil then
        strOrder = 'T_CREATE DESC'
    end
    -- step1：输入参数合法性检查
    if count_plan == nil or count_plan == '' then 
        return 1, "count_plan 必须有值!" 
    end
    if method == nil or type(method) ~= "number" then method = 2 end
    if method == 2 then
        if station == nil or station == '' then 
            return 1, "station 必须有值!" 
        end
    end
    if num == nil then num = 0 end
    if reject_emptybox == nil then reject_emptybox = true end

    -- 获取常量 盘点差异需要审核 = Y
    local diff_need_review
    nRet, diff_need_review = wms_base.Get_sConst2( "盘点差异需要审核")
    if nRet ~= 0 then
        return 1, "系统无法获取常量'盘点差异需要审核'"
    end

    local diff_hand_method = 0
    -- 1 表示有差异需要审核后才能变
    if diff_need_review == "Y" then diff_hand_method = 1 end

    -- step2：创建盘点单
    local count_order = m3.AllocObject(strLuaDEID,"Count_Order")
    count_order.cp_no = count_plan.cp_no
    count_order.wh_code = count_plan.wh_code
    count_order.area_code = count_plan.area_code
    count_order.range_type = count_plan.range_type
    count_order.count_type = count_plan.count_type
    count_order.method = method                      -- 1 表示是人工盘点，这是新兴项目的要求
    count_order.num = num
    count_order.station = station

    count_order.diff_hand_method = diff_hand_method
    nRet, count_order = m3.CreateDataObj( strLuaDEID, count_order )   
    if nRet ~= 0 then 
        return 1, "创建【盘点单】失败!"..count_order 
    end 


    -- step3：查询盘点计划中没有盘点单的【库内作业容器】
    --        特别注意需要 多页查询
    local strCondition = "S_IWP_NO = '"..count_plan.cp_no.."' AND N_B_STATE = 0"    
    nRet, strRetInfo = mobox.queryDataObjAttr2( strLuaDEID, "IWP_Container", strCondition, strOrder, 100 )
    if nRet ~= 0 then 
        return 1, "queryDataObjAttr2: "..strRetInfo 
    end  
    if strRetInfo == '' then 
        return 1, "盘点计划'".. count_plan.cp_no.."'中没有待盘点的容器!" 
    end

    local success
    local queryInfo
    success, queryInfo = pcall( json.decode, strRetInfo )
    if success == false then 
        return 1, "queryDataObjAttr2 返回结果是非法的JSON格式!" 
    end

    local nPageCount = queryInfo.pageCount
    local nPage = 1
    local dataSet = queryInfo.dataSet       -- 查询出来的数据集
    local datajson = {
                        reject_emptybox = reject_emptybox,        -- 是否拒绝空料箱出库盘点
                        cp_no = count_plan.cp_no,                 -- 盘点计划号，这个在WFP的脚本里有用
                        count_order_no = count_order.count_no,    -- 盘点单号
                        count_method = method,                    -- 盘点方法
                        diff_hand_method = diff_hand_method,      -- 盘点有差异处理方法
                        station = station,                        -- 盘点站台
                        data_version = 0                          -- 数据版本号，默认0，用于数据一致性检查
                     }

    local count = 1
    while (nPage <= nPageCount) do

        for n = 1, #dataSet do
            -- step3.1: 后台触发【计划盘点容器】的 Create_IWP_CNTR_Detail
            -- 考虑到生成盘点货品明细的时间会较长用 WFP 来进行处理
            local add_wfp = {
                                wfp_type = 1,                 -- 触发数据对象事件（指定数据对象标识）
                                datajson = datajson,
                                cls = "IWP_Container",
                                obj_id = dataSet[n].id,
                                trigger_event = "Create_IWP_CNTR_Detail"
                            }
            nRet, strRetInfo = m3.AddSysWFP( strLuaDEID, add_wfp )
            if nRet ~= 0 then 
                return 1, strRetInfo  
            end  
            if num > 0 then
                -- 如果num=0 就触发所有容器
                if count == num then goto finish_step end 
            end    
            count = count + 1        
        end        

        nPage = nPage + 1
        if nPage <= nPageCount then
            -- 取下一页
            nRet, strRetInfo = mobox.queryDataObjAttr2( strLuaDEID, nPage)
            if nRet ~= 0 then
                return 1, "queryDataObjAttr2失败! nPage="..nPage.."  "..strRetInfo
            end 
            queryInfo = json.decode(strRetInfo) 
            dataSet = queryInfo.dataSet              
        end
    end

    -- step4：更新盘点单中盘点容器数量, 
    if count < num or num == 0 then 
        -- 更新盘点单盘点容器数量
        strCondition = "S_COUNT_NO = '"..count_order.count_no.."'"
        local strSetSQL = "N_COUNT_NUM = "..count
        nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Count_Order", strCondition, strSetSQL)
        if nRet ~= 0 then 
            return 1, "设置【盘点单】信息失败!"..strRetInfo 
        end        
    end

    ::finish_step::
    -- step5：更新盘点计划中的 进行盘点容器数量
    strCondition = "S_CP_NO = '"..count_plan.cp_no.."'"
    nRet, strRetInfo = mobox.incDataObjAccQty( strLuaDEID, "Count_Plan", strCondition, "N_PLAN_TOTAL", "N_ACC_COUNT", count )
    if nRet ~= 0 then 
        return 1, "incDataObjAccQty(Count_Plan)失败! "..strRetInfo 
    end      
    if strRetInfo ~= '' then
        return 1, "盘点计划号'"..count_order.count_no.."'的累计盘点容器数量异常，无法增加!"
    end 
    
    return 0
end

-- 根据盘点计划创建【盘点单】数据对象
-- 触发指定数量的【计划盘点容器】执行"Create_IWP_CNTR_Detail"脚本
-- @function wms_count.Create_CountOrder_ByCountPlan
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table count_plan 盘点计划数据对象
-- @tparam number method 盘点方法，1=人工到货位盘点，2=自动设备搬运到站台，默认2
-- @tparam string station 站台编码，method=2时必填
-- @tparam number num 盘点容器数量，0或不输入表示所有容器，默认0
-- @tparam boolean reject_emptybox 是否排斥空料箱盘点，默认true
-- @tparam string strOrder 盘点容器排序字段，默认'T_CREATE DESC'
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string 失败时返回错误信息
function wms_count.Create_CountOrder_ByCountPlan2( strLuaDEID, count_plan, method, station, num, reject_emptybox, strOrder )
    local nRet, strRetInfo, n

    if strOrder == nil then
        strOrder = 'T_CREATE DESC'
    end
    -- step1：输入参数合法性检查
    if count_plan == nil or count_plan == '' then 
        return 1, "count_plan 必须有值!" 
    end
    if method == nil or type(method) ~= "number" then method = 2 end
    if method == 2 then
        if station == nil or station == '' then 
            return 1, "station 必须有值!" 
        end
    end
    if num == nil then 
        num = 0 
    end
    if reject_emptybox == nil then reject_emptybox = true end

    -- 获取常量 盘点差异需要审核 = Y
    local diff_need_review
    nRet, diff_need_review = wms_base.Get_sConst2( "盘点差异需要审核")
    if nRet ~= 0 then
        return 1, "系统无法获取常量'盘点差异需要审核'"
    end

    local diff_hand_method = 0
    -- 1 表示有差异需要审核后才能变
    if diff_need_review == "Y" then diff_hand_method = 1 end

    -- step2：创建盘点单
    local count_order = m3.AllocObject(strLuaDEID,"Count_Order")
    count_order.cp_no = count_plan.cp_no
    count_order.wh_code = count_plan.wh_code
    count_order.area_code = count_plan.area_code
    count_order.range_type = count_plan.range_type
    count_order.count_type = count_plan.count_type
    count_order.method = method                      -- 1 表示是人工盘点，这是新兴项目的要求
    count_order.num = num
    count_order.station = station

    count_order.diff_hand_method = diff_hand_method
    nRet, count_order = m3.CreateDataObj( strLuaDEID, count_order )   
    if nRet ~= 0 then 
        return 1, "创建【盘点单】失败!"..count_order 
    end 


    -- step3：查询盘点计划中没有盘点单的【库内作业容器】
    --        特别注意需要 多页查询
    local strCondition = "S_IWP_NO = '"..count_plan.cp_no.."' AND N_B_STATE = 0"    
    nRet, strRetInfo = mobox.queryDataObjAttr2( strLuaDEID, "IWP_Container", strCondition, strOrder, 100, "N_DATA_VER" )
    if nRet ~= 0 then 
        return 1, "queryDataObjAttr2: "..strRetInfo 
    end  
    if strRetInfo == '' then 
        return 1, "盘点计划'".. count_plan.cp_no.."'中没有待盘点的容器!" 
    end

    local success
    local queryInfo
    success, queryInfo = pcall( json.decode, strRetInfo )
    if success == false then 
        return 1, "queryDataObjAttr2 返回结果是非法的JSON格式!" 
    end

    local nPageCount = queryInfo.pageCount
    local nPage = 1
    local dataSet = queryInfo.dataSet       -- 查询出来的数据集
    local datajson = {
                        reject_emptybox = reject_emptybox,        -- 是否拒绝空料箱出库盘点
                        cp_no = count_plan.cp_no,                 -- 盘点计划号，这个在WFP的脚本里有用
                        count_order_no = count_order.count_no,    -- 盘点单号
                        count_method = method,                    -- 盘点方法
                        diff_hand_method = diff_hand_method,      -- 盘点有差异处理方法
                        station = station,                        -- 盘点站台
                        data_version = 0                          -- 数据版本号，默认0，用于数据一致性检查
                     }

    local count = 1
    local strSetSQL, version
    while (nPage <= nPageCount) do

        for n = 1, #dataSet do
            version = lua.Get_NumAttrValue( dataSet[n].attrs[1].value )
            -- 预锁定
            strCondition = "S_ID = '"..lua.trim_guid_str(dataSet[n].id).."' AND N_DATA_VER = "..version
            strSetSQL = "N_DATA_VER = N_DATA_VER + 1, N_B_STATE = "..IWPC_STATE.PreLock
            nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "IWP_Container", strCondition, strSetSQL)
            if nRet ~= 0 then
                return 1, "设置【IWP_Container】信息失败!"..strRetInfo
            end
            -- 更新成功
            if tonumber( strRetInfo ) == 1 then
                datajson.data_version = version + 1
                -- step3.1: 后台触发【计划盘点容器】的 Create_IWP_CNTR_Detail
                -- 考虑到生成盘点货品明细的时间会较长用 WFP 来进行处理
                local add_wfp = {
                                    wfp_type = 1,                 -- 触发数据对象事件（指定数据对象标识）
                                    datajson = datajson,
                                    cls = "IWP_Container",
                                    obj_id = dataSet[n].id,
                                    trigger_event = "Create_IWP_CNTR_Detail"
                                }
                nRet, strRetInfo = m3.AddSysWFP( strLuaDEID, add_wfp )
                if nRet ~= 0 then 
                    return 1, strRetInfo  
                end  
                if num > 0 then
                    -- 如果num=0 就触发所有容器
                    if count == num then goto finish_step end 
                end    
                count = count + 1
            end
        end        

        nPage = nPage + 1
        if nPage <= nPageCount then
            -- 取下一页
            nRet, strRetInfo = mobox.queryDataObjAttr2( strLuaDEID, nPage)
            if nRet ~= 0 then
                return 1, "queryDataObjAttr2失败! nPage="..nPage.."  "..strRetInfo
            end 
            queryInfo = json.decode(strRetInfo) 
            dataSet = queryInfo.dataSet              
        end
    end

    -- step4：更新盘点单中盘点容器数量, 
    if count < num or num == 0 then 
        -- 更新盘点单盘点容器数量
        strCondition = "S_COUNT_NO = '"..count_order.count_no.."'"
        local strSetSQL = "N_COUNT_NUM = "..count
        nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Count_Order", strCondition, strSetSQL)
        if nRet ~= 0 then 
            return 1, "设置【盘点单】信息失败!"..strRetInfo 
        end        
    end

    ::finish_step::
    -- step5：更新盘点计划中的 进行盘点容器数量
    strCondition = "S_CP_NO = '"..count_plan.cp_no.."'"
    nRet, strRetInfo = mobox.incDataObjAccQty( strLuaDEID, "Count_Plan", strCondition, "N_PLAN_TOTAL", "N_ACC_COUNT", count )
    if nRet ~= 0 then 
        return 1, "incDataObjAccQty(Count_Plan)失败! "..strRetInfo 
    end      
    if strRetInfo ~= '' then
        return 1, "盘点计划号'"..count_order.count_no.."'的累计盘点容器数量异常，无法增加!"
    end 
    
    return 0
end

-- 过滤掉空料箱，将盘点计划中的空料箱容器状态设为取消，不参与盘点
-- @function wms_count.Filter_Out_Empty_Bins
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string count_plan_no 盘点计划号
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string 失败时返回错误信息
function wms_count.Filter_Out_Empty_Bins(strLuaDEID, count_plan_no )
    local nRet, strRetInfo

    -- 要联表查询的表
    local strTable = "TN_IWP_Container a LEFT JOIN TN_Container b ON a.S_CNTR_CODE = b.S_CODE" 
    -- 要查询的属性
    local strAttrs = "a.S_IWPC_NO" 
    
    -- 从盘点容器表中查找还没盘点，并且容器是空箱
    local strCondition = "a.S_IWP_NO = '"..count_plan_no.."' AND a.N_B_STATE = 0 AND b.N_EMPTY_FULL = 0"    
    local strOrder = "a.S_ID"
    nRet, strRetInfo = mobox.queryMultiTable2(strLuaDEID, strAttrs, strTable, 100, strCondition, strOrder )
    if nRet ~= 0 then 
        return 1, "queryMultiTable2: "..strRetInfo 
    end  
    if strRetInfo == '' then return 0 end

    local success
    local queryInfo
    success, queryInfo = pcall( json.decode, strRetInfo )
    if success == false then 
        return 1, "queryMultiTable2 返回结果是非法的JSON格式!" 
    end

    local nPageCount = queryInfo.page_count
    local nPage = 1
    local data_list = queryInfo.data_list       -- 查询出来的数据集
    local strUpdateSql, iwpc_no

    while (nPage <= nPageCount) do
        for n = 1, #data_list do
            -- 设置盘点容器的状态=[8]取消
            iwpc_no = lua.Get_StrAttrValue( data_list[n][1] )       -- 计划盘点容器流水号
            strUpdateSql = "N_B_STATE = 8, S_NOTE = '空料箱'"
            strCondition = "S_IWPC_NO = '"..iwpc_no.."'"
            nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "IWP_Container", strCondition, strUpdateSql )
            if nRet ~= 0 then  return 1, "更新【计划盘点容器】信息失败!"..strRetInfo end
        end        

        nPage = nPage + 1
        if nPage <= nPageCount then
            -- 取下一页
            nRet, strRetInfo = mobox.queryMultiTable2( strLuaDEID, nPage)
            if nRet ~= 0 then
                return 1, "queryMultiTable2 失败! nPage="..nPage.."  "..strRetInfo
            end 
            queryInfo = json.decode(strRetInfo) 
            data_list = queryInfo.data_list              
        end
    end  
    return 0  
end

-- 盘点容器盘点完成后的处理逻辑
-- 根据盘点容器流水号查询【IWP_CNTR_Detail】，有差异则生成【Count_Diff】
-- 支持首次盘点和复盘两种场景，有差异时会设置盘点单的C_HAVE_DIFF字段
-- @function wms_count.CountCntr_PostProcess
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table cp_cntr 计划盘点容器数据对象
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string 失败时返回错误信息
function wms_count.CountCntr_PostProcess( strLuaDEID, cp_cntr )
    local nRet, strRetInfo
    local strCondition

    -- 获取盘点计划编码
    local cp_no = lua.Get_StrAttrValue( cp_cntr.iwp_no )

    -- 判断盘点单的盘点类型是否是货物盘点，如果是，需要更新货品盘点的结果 【CP_Good_List】
    local count_no = lua.Get_StrAttrValue( cp_cntr.count_no )
    if count_no == '' then
        return 1, "CountCntr_PostProcess 函数输入参数有问题，盘点容器里没有盘点单号!"      
    end

    local is_good_count = false         -- 是货品盘点
    local count_order
    nRet, count_order = m3.GetDataObjectByKey( strLuaDEID, "Count_Order", "S_COUNT_NO", count_no )
    if nRet ~= 0 then return 1, "GetDataObjectByKey失败"..count_order end  

    if cp_no ~= '' and count_order.range_type == IWP_RANGE_TYPE.Goods then
        is_good_count = true
    end

    local data_objs
    strCondition = "S_IWPC_NO = '"..cp_cntr.iwpc_no.."'"
    nRet, data_objs = m3.QueryDataObject(strLuaDEID, "IWP_CNTR_Detail", strCondition )
    if nRet ~= 0 then 
        return 1, "QueryDataObject失败!"..data_objs 
    end
    if data_objs == '' then return 0  end
    
    local act_qty, qty, last_act_qty, q
    local have_diff = false
    local obj_attrs
    local count_diff
    local strUpdateSql
    local add_diff, count_diff_id, count_diff_data

    -- 遍历【IWP_CNTR_Detail】
    for n = 1, #data_objs do
        obj_attrs = m3.KeyValueAttrsToObjAttr(data_objs[n].attrs)
        if obj_attrs == nil then
            return 1, "KeyValueAttrsToObjAttr失败!"
        end
        qty = lua.StrToNumber( obj_attrs.F_QTY )
        act_qty = lua.StrToNumber( obj_attrs.F_ACT_QTY )        -- 本次盘点数量

        -- 如果是复盘的下面这个属性有值
        count_diff_id = lua.Get_StrAttrValue( obj_attrs.G_COUNT_DIFF_ID )
        add_diff = false
        -- 判断是否是复盘
        if count_diff_id == '' then
            -- 不是复盘，是第一次盘点
            --[[
            if is_good_count then
                strCondition = "S_ITEM_CODE = '"..obj_attrs.S_ITEM_CODE.."' AND S_CP_NO = '"..cp_no.."'"
                strUpdateSql = "F_ACT_QTY = F_ACT_QTY + "..act_qty
                nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "CP_Good_List", strCondition, strUpdateSql)
                if nRet ~= 0 then return 1, "更新【计划盘点货品】 实际数量失败!"..strRetInfo end                
            end
            ]]

            if qty ~= act_qty then
                add_diff = true
            end
        else
            -- 复盘处理差异，首先获取原先最早盘点容器流水号中的差异，判断是否存在差异
            strCondition = "S_ID = '"..count_diff_id.."'"
            nRet, count_diff = m3.GetDataObjByCondition( strLuaDEID, "Count_Diff", strCondition )  
            if nRet ~= 0 then  return 1, "获取【盘点差异表】信息失败!"..count_diff end 

            -- 如果是货品盘点，要调整货品盘点里的实际数量
            --[[
            if is_good_count then
                -- 上一次的盘点数量
                last_act_qty = lua.Get_NumAttrValue( count_diff.act_qty )
                if act_qty ~= last_act_qty then
                    strCondition = "S_ITEM_CODE = '"..obj_attrs.S_ITEM_CODE.."' AND S_CP_NO = '"..cp_no.."'"
                    if last_act_qty > act_qty then
                        q = last_act_qty - act_qty
                        strUpdateSql = "F_ACT_QTY = F_ACT_QTY  - "..q
                    else
                        q = act_qty - last_act_qty
                        strUpdateSql = "F_ACT_QTY = F_ACT_QTY  + "..q                        
                    end
                    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "CP_Good_List", strCondition, strUpdateSql)
                    if nRet ~= 0 then return 1, "更新【计划盘点货品】 实际数量失败!"..strRetInfo end                       
                end
            end
            ]]

            -- 判断盘点次数, 如果已经是二盘
            strUpdateSql = "N_B_STATE = 1, F_ACT_QTY = "..act_qty
            if count_diff.count_time == 2 then
                -- 不允许再复盘
                strUpdateSql = strUpdateSql..", N_COUNT_TIME = 3, C_RECOUNT = 'N'"
            else
                strUpdateSql = strUpdateSql..", N_COUNT_TIME = 2 "
            end
            nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Count_Diff", strCondition, strUpdateSql )
            if nRet ~= 0 then  return 1, "更新【Count_Diff】信息失败!"..strRetInfo end 
            have_diff = true
        end

        if add_diff then
            count_diff_data = m3.AllocObject2(strLuaDEID,"Count_Diff")

            for m = 1, #COUNT_CNTR_DETAIL_ATTRS do
                count_diff_data[COUNT_CNTR_DETAIL_ATTRS[m]] = obj_attrs[COUNT_CNTR_DETAIL_ATTRS[m]]
            end
            for m = 1, #UDF_ATTRS do
                count_diff_data[UDF_ATTRS[m]] = obj_attrs[UDF_ATTRS[m]]
            end
            
            count_diff_data.S_IWPC_NO = cp_cntr.iwpc_no            
            count_diff_data.S_CP_NO = cp_no
            count_diff_data.S_COUNT_NO = cp_cntr.count_no
            count_diff_data.G_INV_DETAIL_ID = obj_attrs.G_INV_DETAIL_ID          -- 可能为空如果是多条相同货品合并盘点的情况
            count_diff_data.F_ACT_QTY = act_qty

            nRet, count_diff_data = m3.CreateDataObj2( strLuaDEID, count_diff_data )
            if nRet ~= 0 then 
                return 1, 'mobox 创建【盘点差异表】对象失败!'..count_diff_data
            end 
            have_diff = true               
        end
    end

    -- 盘点单｛累计盘点数量｝+1
    strCondition = "S_COUNT_NO = '"..cp_cntr.count_no.."'"
    nRet, strRetInfo = mobox.incDataObjAccQty ( strLuaDEID, "Count_Order", strCondition, "N_COUNT_NUM", "N_ACC_FINISH", 1 )
    if nRet ~= 0 or strRetInfo ~= '' then 
        return 1, '在增加【盘点单】中的累计盘点数量时失败!'..strRetInfo 
    end     

    -- 更新计划盘点容器中的 C_HAVE_DIFF = 'Y' 表示这个容器盘点有差异
    if have_diff then
        strCondition = "S_ID = '"..cp_cntr.id.."'"
        local strSetAttr = "C_HAVE_DIFF = 'Y'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "IWP_Container", strCondition, strSetAttr )
        if nRet ~= 0 then  
            return 1, "更新【IWP_Container】信息失败!"..strRetInfo 
        end 
        
        --V3.0 盘点单也设置 C_HAVE_DIFF = Y
        strCondition = "S_COUNT_NO = '"..cp_cntr.count_no.."'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Count_Order", strCondition, strSetAttr )
        if nRet ~= 0 then  
            return 1, "更新【Count_Order】信息失败!"..strRetInfo 
        end         
    end

    -- 增加一个后台进程对盘点单进行处理，检查盘点单是否可以完成
    local add_wfp = {
        wfp_type = 1,
        cls = "Count_Order",
        obj_id = count_order.id,
        obj_name = "盘点单'"..count_order.count_no.."'-->检查是否可以完成",
        trigger_event = "ResetCountOrderState"
    }
    nRet, strRetInfo = m3.AddSysWFP( strLuaDEID, add_wfp )
    if nRet ~= 0 then 
        return 1, "AddSysWFP失败!"..strRetInfo  
    end 

    return 0
end

-- 获取盘点计划的查询面板中的查询条件
-- 支持按货品范围、货位范围、容器范围三种盘点类型生成不同的查询条件
-- @function wms_count.Get_CountPlan_QueryPanel_Condition
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam boolean isSetQueryCondition true时容器查询条件返回base64编码
-- @treturn number nRet 0=成功，1=条件不满足，2=错误
-- @treturn number ret_condition_type 0=纯SQL字符串，1=base64编码
-- @treturn string strCondition 查询条件字符串
function wms_count.Get_CountPlan_QueryPanel_Condition( strLuaDEID, isSetQueryCondition )
    local nRet
    local attrs = {}
    local ret_condition_type = 0        -- 非base64

    local lua_info
    nRet, lua_info = lua.GetLuaDEInfo( strLuaDEID )
    if nRet ~= 0 then
        return 1, "GetLuaDEInfo 失败!"..lua_info
    end

    -- step1  获取当前查询输入面板中的 仓库编码/库区/物料编码/物料名称
    nRet, attrs = m3.GetSysInputParameter( strLuaDEID ) 
    if nRet ~= 0 then return 2, 0, "获取当前查询面板里的输入属性时失败! "..attrs end 

    local obj_attrs = m3.KeyValueAttrsToObjAttr(attrs)
    if obj_attrs == nil then 
        return 2, 0, "询面板里的输入属性为空" 
    end
    -- "N_TYPE","S_WH_CODE","Area","ItemCode", "ItemName"
    local range_type = tonumber(obj_attrs.N_RANGE_TYPE)     -- 盘点类型
    local wh_code = obj_attrs.S_WH_CODE                     -- 仓库编码
    local area_code = obj_attrs.S_AREA_CODE                 -- 库区编码
    if area_code == nil then area_code = '' end

    local strCondition =  ''
    local strOrder = ''
    if wh_code == '' then  return 1, 0, "必须选择一个仓库"  end

    if range_type == IWP_RANGE_TYPE.Goods then
        local item_code = obj_attrs.ItemCode                    -- 物料编码
        local item_name = obj_attrs.ItemName                    -- 物料名称
        local item_condition = ''

        if item_code ~= '' and item_code ~= nil then
            item_condition = " AND S_ITEM_CODE like '%%"..item_code.."%%'"
        end
        if item_name ~= '' and item_name ~= nil then
            item_condition = item_condition.." AND S_ITEM_NAME like '%%"..item_name.."%%' "
        end
        strOrder = 'S_ITEM_CODE'
        -- 如果是货物盘点
        if area_code == '' then
            -- 没有输入库区就直接查仓库量表
            strCondition = "F_QTY > 0 AND S_WH_CODE = '"..wh_code.."' "..item_condition
        else
            -- 有库区查库区量表
            strCondition = "F_QTY > 0 AND S_WH_CODE = '"..wh_code.."' AND S_AREA_CODE = '"..area_code.."' "..item_condition
        end
    else
        strCondition = "S_WH_CODE = '"..wh_code.."'"
        if area_code ~= '' then
            strCondition = strCondition .. " AND S_AREA_CODE = '"..area_code.."' "
        end
        -- V2.0
        if range_type == IWP_RANGE_TYPE.Location then
            -- 如果是货位盘点
            local aisle = lua.StrToNumber(obj_attrs.Roadway)           -- 巷道
            local row = lua.StrToNumber(obj_attrs.Row)                   -- 排
            local col = lua.StrToNumber(obj_attrs.Col)                   -- 列
            local layer = lua.StrToNumber(obj_attrs.layer)               -- 层               
            if aisle ~= 0 then
                strCondition = strCondition .. " AND N_AISLE = "..aisle
            end               
            if row ~= 0 then
                strCondition = strCondition .. " AND N_ROW = "..row
            end 
            if col ~= 0 then
                strCondition = strCondition .. " AND N_COL = "..col
            end 
            if layer ~= 0 then
                strCondition = strCondition .. " AND N_LAYER = "..layer
            end            
            strCondition = strCondition.." AND N_CURRENT_NUM > 0"
            --V2.0 增加空料箱不参与盘点过滤条件
            strCondition=strCondition.." AND S_CODE IN (SELECT S_LOC_CODE FROM TN_INV_Detail WHERE F_QTY>0)"
        elseif  range_type == IWP_RANGE_TYPE.Container then
            -- 容器盘点
            local cntr_code = lua.Get_StrAttrValue(obj_attrs.cntr_code)           -- 料箱号
            local str_wharea_condition = strCondition

            -- 这里的查询条件带 In 不能用简单模式
            if isSetQueryCondition then
                local condition

                if lua_info.dbtype == DB_TYPE.SQLServer then
                    condition = "(select S_CNTR_CODE from TN_Loc_Container A with (NOLOCK) where EXISTS (SELECT 1 FROM TN_INV_Detail WHERE S_LOC_CODE=A.S_LOC_CODE AND F_QTY>0) AND S_LOC_CODE in (select S_CODE from TN_Location with (NOLOCK) where "..str_wharea_condition.."))"
                else
                    condition = "(select S_CNTR_CODE from TN_Loc_Container A where EXISTS (SELECT 1 FROM TN_INV_Detail WHERE S_LOC_CODE=A.S_LOC_CODE AND F_QTY>0) AND S_LOC_CODE in (select S_CODE from TN_Location where "..str_wharea_condition.."))"
                end
                local sql_condition = {
                    {
                        {
                            field = "C_ENABLE",     -- 容器是启用状态
                            value = "Y",
                            op = "="
                        }
                    },
                    {
                        {
                            field = "N_LOCK_STATE",  -- 容器没被锁
                            value = "0",
                            op = "="
                        }
                    },
                    {
                        {
                            field = "S_CODE",
                            value = condition,
                            op = "in"
                        }
                    }                        
                }
                -- 如果有输入容器料箱编码直接查料箱编码
                if cntr_code ~= '' then
                    local sql_item = {
                        {
                            field = "S_CODE",     
                            value = cntr_code,
                            op = "="
                        }
                    }
                    table.insert( sql_condition, sql_item )
                end
                nRet, strCondition = mobox.strToBase64( lua.table2str(sql_condition) )
                if nRet ~= 0 then return 2, 0, "strToBase64 失败: "..strCondition end 
                ret_condition_type = 1
            else
                strCondition = "C_ENABLE = 'Y' AND N_LOCK_STATE = 0 "
                if cntr_code ~= '' then
                    strCondition = strCondition.." AND S_CODE = '"..cntr_code.."'"
                end
                if lua_info.dbtype == DB_TYPE.SQLServer then
                    strCondition = strCondition.." AND S_CODE in (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE in (select S_CODE from TN_Location with (NOLOCK) where "..str_wharea_condition.."))"
                else
                    strCondition = strCondition.." AND S_CODE in (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE in (select S_CODE from TN_Location where "..str_wharea_condition.."))"
                end
                --V2.0 增加空料箱不参与盘点过滤条件
                 strCondition=strCondition.." AND EXISTS (SELECT 1 FROM TN_INV_Detail WHERE S_LOC_CODE=TN_Location.S_CODE AND F_QTY>0)"
            end
        else
            return 1, 0, "抽盘范围类型不合法!"
        end
    end  
    return 0, ret_condition_type, strCondition
end

-- 盘点差异进行复盘
-- 检查盘点差异是否可以复盘，可复盘则创建盘点单、创建出库作业、并给容器加盘点锁
-- @function wms_count.Count_Diff_RepeatCount
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string station 复盘站台编码
-- @tparam table count_diff_ids 需要复盘的盘点差异对象标识数组
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string 失败时返回错误信息
function wms_count.Count_Diff_RepeatCount( strLuaDEID, station, count_diff_ids )
    local nRet, strRetInfo
    local count_diff_data    
    local count_cntr_list = {}   -- 需要盘点的容器
    local find, id, n, m

    if lua.StrIsEmpty(station) then  return 1, "站台必须有值!" end

    -- 注意: 选中的盘点差异必须是一个盘点单里的差异
    local count_no = ''    
    for n = 1, #count_diff_ids do
        -- 获取盘点差异对象属性
        id = lua.trim_guid_str( count_diff_ids[n] )
        nRet, count_diff_data = m3.GetDataObject2( strLuaDEID, "Count_Diff", id )
        if nRet ~= 0 then 
            return 2, '获取【盘点差异】对象失败!'..count_diff_data 
        end  

        -- 盘点是否允许复盘(recount == 'Y') , 状态b_state不能是在盘点中...
        -- diff_trans == 'N'  盘点差异没转移
        -- b_state == 1 表示是1盘
        local b_state = lua.Get_NumAttrValue( count_diff_data.N_B_STATE )
        if count_diff_data.C_RECOUNT == 'Y' and b_state == 1 and count_diff_data.C_DIFF_TRANS == 'N' then
            find = false
            -- 判断盘点差异的盘点单是否一样
            if count_no == '' then
                count_no = count_diff_data.S_COUNT_NO
            else
                if count_no ~= count_diff_data.S_COUNT_NO then
                    lua.Stop( strLuaDEID, "复盘的盘点差异中其盘点单号必须相同!")
                    return                       
                end
            end            
            local count_item = count_diff_data


            for m = 1, #count_cntr_list do
                if count_cntr_list[m].cntr_code == count_diff_data.S_CNTR_CODE then
                    table.insert( count_cntr_list[m].count_item_list, count_item )
                    find = true
                    break
                end
            end
            if find == false then
                local count_cntr = {
                    cntr_code = count_diff_data.S_CNTR_CODE,
                    count_item_list = {}
                }
                table.insert( count_cntr.count_item_list, count_item )
                table.insert( count_cntr_list, count_cntr )
            end
        end
    end

    local strCondition
    local nCount = #count_cntr_list
    if nCount == 0 or count_no == '' then 
        mobox.setInfo( strLuaDEID, "复盘数量为0, 请检查一下需要复盘的容器是否可以进行复盘!")
        return 0 
    end

    -- 获取要复盘的差异所属的盘点单，盘点计划
    local first_count_order
    nRet, first_count_order = m3.GetDataObjectByKey(strLuaDEID, "Count_Order", "S_COUNT_NO", count_no )
    if nRet ~= 0 then     
        mobox.setInfo( strLuaDEID, "盘点单'"..count_no.."'不存在!" )
        return  0
    end

    -- 创建盘点单
    local count_order = m3.AllocObject(strLuaDEID,"Count_Order")
    count_order.method = first_count_order.method
    count_order.num = nCount
    count_order.station = station
    count_order.count_type = first_count_order.count_type
    count_order.cp_no = first_count_order.cp_no
    count_order.recheck = 'Y'
    count_order.first_count_no = count_no
    count_order.diff_hand_method = 1        -- 1 不自动差异转移
    nRet, count_order = m3.CreateDataObj( strLuaDEID, count_order )    
    if nRet ~= 0 then
         return 2, "创建【盘点单】失败!"..count_order 
    end  
    
    -- 创建【计划盘点容器】
    local count_cg_detail, count_item
    local cp_count_container_list = {}
    local loc, loc_code

    for n = 1, nCount do
        --  获取容器所在货位
        nRet, loc_code = wms_cntr.Get_Container_Loc( strLuaDEID, count_cntr_list[n].cntr_code )
        if nRet ~= 0 or loc_code == '' then
            return 1, loc_code
        end    
        if loc_code == '' then
            return 1, "容器'"..count_cntr_list[n].cntr_code.."'不在货位上"              
        end
        nRet, loc = wms_wh.GetLocInfo( loc_code )
        if nRet ~= 0 then return 1, '获取货位信息失败! '..loc_code end   
    

        local cp_count_container = m3.AllocObject(strLuaDEID,"IWP_Container")
        cp_count_container.method = 2
        cp_count_container.station = station
        cp_count_container.loc_code = loc_code
        cp_count_container.wh_code = loc.wh_code
        cp_count_container.area_code = loc.area_code
        cp_count_container.iwp_no = first_count_order.cp_no
        cp_count_container.count_no = count_order.count_no
        cp_count_container.cntr_code = count_cntr_list[n].cntr_code
        nRet, cp_count_container = m3.CreateDataObj( strLuaDEID, cp_count_container )
        if nRet ~= 0 then 
            return 2, cp_count_container 
        end  
        table.insert( cp_count_container_list, cp_count_container )

        -- 创建【盘点容器货品明细】 IWP_CNTR_Detail
        local iwp_cntr_detail_data
        for m = 1, #count_cntr_list[n].count_item_list do
            iwp_cntr_detail_data = m3.AllocObject2(strLuaDEID,"IWP_CNTR_Detail")
            count_item = count_cntr_list[n].count_item_list[m]

            for i = 1, #COUNT_CNTR_DETAIL_ATTRS do
                iwp_cntr_detail_data[COUNT_CNTR_DETAIL_ATTRS[i]] = count_item[COUNT_CNTR_DETAIL_ATTRS[i]]
            end
            for i = 1, #UDF_ATTRS do
                iwp_cntr_detail_data[UDF_ATTRS[i]] = count_item[UDF_ATTRS[i]]
            end
            iwp_cntr_detail_data.G_INV_DETAIL_ID = count_item.G_INV_DETAIL_ID
            iwp_cntr_detail_data.S_COUNT_NO = count_order.count_no
            iwp_cntr_detail_data.S_IWPC_NO = cp_count_container.iwpc_no
            iwp_cntr_detail_data.S_STATION_NO = station
            -- 复盘时要用到，和根据这个ID 更新新的盘点结果
            iwp_cntr_detail_data.G_COUNT_DIFF_ID = count_item.id
            
            nRet, iwp_cntr_detail_data = m3.CreateDataObj2( strLuaDEID, iwp_cntr_detail_data )   
            if nRet ~= 0 then 
                return 2, "创建【IWP_CNTR_Detail】失败!"..iwp_cntr_detail_data 
            end 
            
            -- 设置【盘点差异】表记录的状态=2/复盘
            local strUpdateSql = "N_B_STATE = 2"
            strCondition = "S_ID = '"..count_item.id.."'"
            nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Count_Diff", strCondition, strUpdateSql )
            if nRet ~= 0 then  
                return 2, "更新【盘点差异表】信息失败!"..strRetInfo
            end                 
        end
    end
   
    -- 盘点容器生成作业
    local add_wfp
    for n = 1, #cp_count_container_list do
        -- 增加一个后台进程进行入库单完工回报
        add_wfp = {
            wfp_type = 1,                  -- 触发数据对象事件（指定数据对象标识）
            cls = "IWP_Container",
            obj_id = cp_count_container_list[n].id,
            obj_name = "Container No '"..cp_count_container_list[n].cntr_code.."'-->Create stocktaking outbound operation",
            trigger_event = "CreateStocktakingOutOperation"
        }

        nRet, strRetInfo = m3.AddSysWFP( strLuaDEID, add_wfp )
        if nRet ~= 0 then 
            return 2, "AddSysWFP失败!"..strRetInfo  
        end         
        -- step6: 给容器加盘点锁 4 -- 盘点锁
        nRet, strRetInfo = wms.wms_LockCntr( strLuaDEID, cp_count_container_list[n].cntr_code, 4, count_order.count_no )
        if nRet ~= 0 then
            return 2, "给容器'"..cp_count_container_list[n].cntr_code.."'加盘点锁失败!" 
        end  
    end

    return 0      
end

-- 盘点差异转移处理
-- 适用不需要和上游进行回报操作，可以对单条盘点差异进行转移（改库存量）的业务场景
-- @function wms_count.CountDiff_Transfter
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table count_diff_objs 盘点差异数据对象
-- @treturn number nRet 0: 成功，非零失败
-- @treturn number/string 失败返回错误信息
function wms_count.CountDiff_Transfter ( strLuaDEID, count_diff_objs ) 
    local   nRet, strRetInfo

    if count_diff_objs == nil or type( count_diff_objs ) ~= "table" then
        return 1, "wms_count.CountDiff_Transfter 函数的输入参数 count_diff_objs 不合法,必须有值,必须是table类型!"
    end
    local nCount = #count_diff_objs
    if nCount == 0 then  return 0 end

    local count_diff
    local cntr_code_set = {}

    local qty
    local inventory_loss
    local strSetSQL, cntr_code, inv_detail_id, diff_trans
    local wh_code = ''
    local strCondition = ''

    for n = 1, nCount do
        nRet, count_diff = m3.ObjAttrStrToLuaObj( "Count_Diff", lua.table2str(count_diff_objs[n].attrs) )
        if nRet ~= 0 then 
            return 2, "m3.ObjAttrStrToLuaObj(Count_Diff) 失败! "..count_diff 
        end

        diff_trans = lua.Get_StrAttrValue( count_diff.diff_trans )
        if diff_trans == '' then
            return 1, "盘点差异显示表格中必须带'是否差异移库'列"
        end

        if diff_trans == 'N' then
            cntr_code = count_diff.cntr_code
            if cntr_code == nil or cntr_code == '' then
                return 1, "盘点差异显示表格中必须带'容器号'列"
            end

            wh_code = lua.Get_StrAttrValue( count_diff.wh_code )
            if wh_code == '' then
                return 1, "盘点差异显示表格中必须带'仓库'列"
            end        
            -- 生成量表变化数据 
            inventory_loss = nil
            if count_diff.qty > count_diff.act_qty then
                -- 盘亏
                inventory_loss = true
                qty = count_diff.qty - count_diff.act_qty
            elseif  count_diff.qty < count_diff.act_qty  then
                -- 盘盈
                inventory_loss =  false
                qty = count_diff.act_qty - count_diff.qty
            end

            inv_detail_id = count_diff.inv_detail_id
            -- inventory_loss == nil 说明数量一样
            if inventory_loss ~= nil then
                if inv_detail_id == nil or inv_detail_id == '' then
                    -- V2.0
                    -- 需要把差异数据批分到 INV_Detail 中有相同货品的Item中
                    strCondition = "S_CNTR_CODE = '"..count_diff.cntr_code.."' AND S_ITEM_CODE = '"..count_diff.item_code.."'"
                    if inventory_loss then
                        -- 盘亏
                        --strOrder = "F_QTY"
                        strOrder = "T_CREATE"   -- 考虑把先创建的 INV_Detial 扣减
                        nRet, strRetInfo = wms_inv.Reduce_INV_Detail_Qty( strLuaDEID, count_diff.cntr_code, strCondition, strOrder, qty )
                    else
                        -- 盘盈 的情况把 qty 加到其中一条 INV_Detail 即可
                        strOrder = "T_CREATE"
                        nRet, strRetInfo = wms_inv.Add_INV_Detail_Qty( strLuaDEID, count_diff.cntr_code, strCondition, strOrder, qty )                    
                    end
                    if nRet ~= 0 then return 2, "调整【INV_Detail】 数量失败!"..strRetInfo end  
                else    
                    local inv_detail_data 
                    nRet, inv_detail_data = m3.GetDataObject2( strLuaDEID, "INV_Detail", inv_detail_id ) 
                    if nRet ~= 0 then 
                        return 2, inv_detail_data
                    end 
                    if inventory_loss then
                        nRet, strRetInfo = wms_inv.INV_Detail_Reduce_Qty_By_ADJ( strLuaDEID, inv_detail_data, qty, "Count_Order", count_diff.count_no )
                    else
                        nRet, strRetInfo = wms_inv.INV_Detail_Add_Qty_By_ADJ( strLuaDEID, inv_detail_data, qty, "Count_Order", count_diff.count_no )
                    end
                    if nRet ~= 0 then 
                        return 2, "调整【INV_Detail】 数量失败!"..strRetInfo 
                    end  
                end 
            end
            -- Count_Diff 更新数据差异转移状态
            strSetSQL = "C_DIFF_TRANS = 'Y'"
            strCondition = "S_ID = '"..lua.trim_guid_str( count_diff_objs[n].id ).."'"
            nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Count_Diff", strCondition, strSetSQL)
            if nRet ~= 0 then 
                return 2, "设置【盘点差异表】差异转移失败!"..strRetInfo 
            end   

            if lua.IsInTable(cntr_code, cntr_code_set) == false then
                table.insert( cntr_code_set, cntr_code )
            end
        end
    end

    -- 对容器进行 差异转移后处理 程序，（设置容器为可用）
    local container
    for n = 1, #cntr_code_set do
        nRet, container = wms_cntr.GetInfo( strLuaDEID, cntr_code_set[n] )
        if nRet ~= 0 then 
            return 1, container
        end
        local add_wfp = {
            wfp_type = 1,
            cls = "Container",
            obj_id = container.id,
            obj_name = "容器'"..cntr_code_set[n].."'-->盘点差异转移后重置",
            trigger_event = "CountDiffPostProcess"
        }
        nRet, strRetInfo = m3.AddSysWFP( strLuaDEID, add_wfp )
        if nRet ~= 0 then 
            return 2, "AddSysWFP失败!"..strRetInfo  
        end  
    end
    return 0
end

-- 盘点单差异转移处理
-- 查询盘点单下所有未转移的盘点差异，逐条执行差异转移
-- @function wms_count.CountOrder_Transfter
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table count_order 盘点单数据对象
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string 失败时返回错误信息
function wms_count.CountOrder_Transfter ( strLuaDEID, count_order )
    local nRet, strRetInfo

    if count_order == nil or type( count_order ) ~= "table" then
        return 1, "CountOrder_Transfter 输入参数 count_order 不合法!"
    end

    local count_diff_objects
    local strCondition = "S_COUNT_NO = '"..count_order.count_no.."' AND C_DIFF_TRANS = 'N'"
    nRet, count_diff_objects = m3.QueryDataObject(strLuaDEID, "Count_Diff", strCondition )
    if nRet ~= 0 then 
        return 2, "QueryDataObject失败!"..count_diff_objects 
    end

    if count_diff_objects == '' then 
        return 1, "盘点单'"..count_order.count_no.."'没可以转移的盘点差异!"
    end    
    nRet, strRetInfo = wms_count.CountDiff_Transfter ( strLuaDEID, count_diff_objects ) 
    if nRet ~= 0 then 
        return nRet, strRetInfo 
    end

    strCondition = "S_COUNT_NO = '"..count_order.count_no.."'"
    local strSetAttr = "C_DIFF_TRANS = 'Y'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Count_Order", strCondition, strSetAttr )
    if nRet ~= 0 then 
        return 2, "更新【盘点单】信息失败!"..strRetInfo 
    end  

    return 0
end

return wms_count