--[[
    版本：      Version 2.2
    创建日期：  2023-6-16
    创建人：    HAN
    修改日期：  2026-06-17


    WMS-Basis-Model-Version: V15.5
        
    功能：
        wms_operation Lua程序包整合了一些【作业】对象相关的操作

        -- GetInfo                          根据作业编号获取作业属性
        -- SetEndLoc                        更新【作业】对象的终点货位和库区、仓库等信息
        -- SetStartLoc                      更新【作业】对象的起点货位和库区、仓库等信息
        -- Update                           更新【作业】的起点和终点货位和库区、仓库等信息
        -- SetFinish                        设置【作业】对象的状态=完成
        -- SetCancel                        设置【作业】状态=取消
        -- Reset                            设置【作业】对象的状态=执行，错误码清空
        -- SetTaskState                     设置作业中的任务状态（0未下发/1已推送/2已执行/3已执行完成）
        -- Create                           点到点创建作业
        -- CanCancel                        判断作业是否可以取消
        -- Create_Distribution_OutOperation 创建配盘出库作业
        -- Create_Inbound_Operation         创建入库作业（站台→立库）
        -- Create_IWP_OutOperation          创建库内业务（指定出库/理货/盘点）出库作业

    更改说明：
        V2.2 (2026-06-17):
        - 补充缺失的 Create_Distribution_OutOperation、Create_Inbound_Operation、Create_IWP_OutOperation 函数描述
        - 所有函数添加标准 @function/@tparam/@treturn 注解
        - 修复 loc_code 变量引用错误（应使用 from_loc_code）
        - 移除未使用的 strRetInfo 局部变量

    AI CHECK： 
        -- 2026-06-17 16:14  
        -- 2026-8-5 修改 Create_Inbound_Operation
--]]

wms_base = require ("wms_base")
wms_station = require( "wms_station" )
wms_putaway = require( "wms_putaway" )
wms_cntr = require( "wms_container" )

local wms_op = {_version = "0.1.1"}

--/////////////////////////////////////////////////////////作业相关////////////////////////////////////////////////////////////
--[[
    @function wms_op.GetInfo
    根据作业编号获取作业属性
    @tparam string strLuaDEID Lua数据引擎ID
    @tparam string op_code 作业编码
    @treturn number nRet 返回码: 0成功获取信息, 1不存在, 2错误
    @treturn table|string object 作业对象或错误信息
--]]
function wms_op.GetInfo( strLuaDEID, op_code )
    if op_code == nil or op_code == '' then
        return 2, "调用 wms_op.GetInfo 函数时参数不正确，作业编码不能为空!"
    end

    local nRet, strRetInfo, id, attrs
    local strCondition = "S_CODE = '"..op_code.."'"
    nRet, id, attrs = mobox.getDataObjAttrByKeyAttr( strLuaDEID, "Operation", strCondition )
    if nRet == 1 then
        return 1, "作业编码='"..op_code.."'的作业不存在!"
    end
    if nRet ~= 0 then
        return 2, "getDataObjAttrByKeyAttr 发生错误!"..id
    end

    nRet, strRetInfo = mobox.objAttrsToLuaJson( "Operation", attrs )
    if nRet ~= 0 then
        return 2, "objAttrsToLuaJson Operation 失败!"..strRetInfo
    end

    local object, success
    success, object = pcall( json.decode, strRetInfo )
    if success == false then
        return 1, "objAttrsToLuaJson('Operation') 返回的的JSON格式不合法!"
    end
    object.id = id
    return 0, object
end

--[[
    @function wms_op.SetEndLoc
    更新【作业】的终点货位和库区、仓库等信息

    @tparam string strLuaDEID Lua数据引擎ID
    @tparam string strOpCode 作业编码
    @tparam string strLocCode 货位编码
    @tparam string strAreaCode 库区编码
    @tparam string strWHCode 仓库编码
    @tparam string|nil strCntrCode 容器编码(可不输入)
    @treturn number nRet 返回码: 0成功, 非0失败
    @treturn string strRetInfo 错误信息
--]]
function wms_op.SetEndLoc( strLuaDEID,  strOpCode, strLocCode, strAreaCode, strWHCode, strCntrCode )
    local nRet, strRetInfo

    -- 输入参数检查
    if strOpCode == nil or strOpCode == '' then
        return 1, "调用 wms_op.SetEndLoc 函数时参数不正确, 作业编码不能为空!"
    end
    if strWHCode == nil or strWHCode == '' then
        return 1, "调用 wms_op.SetEndLoc 函数时参数不正确, 仓库编码不能为空!"
    end
    if strAreaCode == nil or strAreaCode == '' then
        return 1, "调用 wms_op.SetEndLoc 函数时参数不正确, 库区编码不能为空!"
    end
    if strLocCode == nil or strLocCode == '' then
        return 1, "调用 wms_op.SetEndLoc 函数时参数不正确, 货位编码不能为空!"
    end

    local strCondition
    strCondition = "S_CODE = '"..strOpCode.."'"
    strSetAttr = "S_END_WH='"..strWHCode.."', S_END_AREA='"..strAreaCode.."', S_END_LOC='"..strLocCode.."'"
    if strCntrCode ~= nil then
        strSetAttr = strSetAttr..", S_CNTR_CODE='"..strCntrCode.."'"
    end    
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Operation", strCondition, strSetAttr )
    if nRet ~= 0 then
       return nRet, strRetInfo
    end  

    return 0,""
end


--[[
    @function wms_op.SetStartLoc
    更新【作业】的起点货位和库区、仓库等信息

    @tparam string strLuaDEID Lua数据引擎ID
    @tparam string strOpCode 作业编码
    @tparam string strLocCode 货位编码
    @tparam string strAreaCode 库区编码
    @tparam string strWHCode 仓库编码
    @tparam string|nil strCntrCode 容器编码(可不输入)
    @treturn number nRet 返回码: 0成功, 非0失败
    @treturn string strRetInfo 错误信息
--]]
function wms_op.SetStartLoc( strLuaDEID,  strOpCode, strLocCode, strAreaCode, strWHCode, strCntrCode )
    local nRet, strRetInfo

    -- 输入参数检查
    if strOpCode == nil or strOpCode == '' then
        return 1, "调用 wms_op.SetStartLoc 函数时参数不正确, 作业ID不能为空!"
    end

    local strCondition
    strCondition = "S_CODE = '"..strOpCode.."'"
    strSetAttr = "S_START_WH='"..strWHCode.."', S_START_AREA='"..strAreaCode.."', S_START_LOC='"..strLocCode.."'"
    if strCntrCode ~= nil then
        strSetAttr = strSetAttr..", S_CNTR_CODE='"..strCntrCode.."'"
    end
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Operation", strCondition, strSetAttr )
    if nRet ~= 0 then
       return nRet, strRetInfo
    end  

    return 0,""
end

--[[
    @function wms_op.Update
    更新【作业】的起点和终点货位和库区、仓库等信息

    @tparam string strLuaDEID Lua数据引擎ID
    @tparam table operation 作业数据对象(lua变量对象)
    @treturn number nRet 返回码: 0成功, 非0失败
    @treturn string strRetInfo 错误信息
--]]
function wms_op.Update( strLuaDEID, operation )
    local nRet, strRetInfo

    -- 输入参数检查
    if operation == nil then
        return 1, "调用 wms_op.Update 函数时参数不正确, operation 必须有值!"
    end

    local strCondition, strSetAttr
    strCondition = "S_CODE = '"..operation.code.."'"
    strSetAttr = "S_START_WH='"..operation.start_wh_code.."', S_START_AREA='"..operation.start_area_code.."', S_START_LOC='"..operation.start_loc_code.."',"
    strSetAttr = strSetAttr.."S_CNTR_CODE='"..operation.cntr_code.."',S_END_WH='"..operation.end_wh_code.."', S_END_AREA='"..operation.end_area_code.."', S_END_LOC='"..operation.end_loc_code.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Operation", strCondition, strSetAttr )
    if nRet ~= 0 then
       return nRet, strRetInfo
    end  
    return 0,""
end

--[[
    @function wms_op.SetFinish
    设置【作业】状态=完成

    @tparam string strLuaDEID Lua数据引擎ID
    @tparam string|table operation 作业编码 或 作业数据对象(table)
    @treturn number nRet 返回码: 0成功, 非0失败
    @treturn string strRetInfo 错误信息
--]]
function wms_op.SetFinish( strLuaDEID, operation )
    local nRet, strRetInfo
    local strOpCode = ''
    local strCNTRCode = ''
    local start_time = ''
    local carry_cb_no = ''
    local carry_cb_cls = ''

    if type(operation) == "string" then
        strOpCode = operation
    else
        strOpCode = operation.code
        strCNTRCode = operation.cntr_code
        -- 作业携带容器业务类型
        carry_cb_cls = operation.carry_cb_cls
        carry_cb_no = operation.carry_cb_no

        if operation.run_time ~= nil then
            -- 说明作业有新增的 F_RUN_TIME 属性
            start_time = operation.start_time
        end
    end

    -- 输入参数检查
    if strOpCode == nil or strOpCode == '' then
        return 1, "调用 wms_op.SetFinish 函数时参数不正确, 作业编码不能为空!"
    end
    --local b_state = wms_base.Get_nConst(strLuaDEID,"作业状态-完成")
    local b_state = 2
    local strCondition, strSetAttr
    local str_b_state = wms_base.GetDictItemName( strLuaDEID, "WMS_OperationState", b_state ) 

    local curTime = os.date("%Y-%m-%d %H:%M:%S")
    strCondition = "S_CODE = '"..strOpCode.."'"
    strSetAttr = "N_B_STATE="..b_state..", S_B_STATE='"..str_b_state.."', T_END_TIME='"..curTime.."'"

    if start_time ~= '' then
        local st = lua.toTimestamp( start_time )
        local run_time = os.difftime( os.time(), st )
        strSetAttr = strSetAttr..", F_RUN_TIME = "..run_time
    end

    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Operation", strCondition, strSetAttr )
    if nRet ~= 0 then
       return nRet, strRetInfo
    end  

    -- 解锁由该作业造成的货位锁，逻辑库区锁都解除
    nRet, strRetInfo = wms.wms_UnlockByOperation( strLuaDEID, strOpCode )
    if nRet ~= 0 then
        return 1, "wms_UnlockByOperation 失败! "..strRetInfo
    end

    -- 容器解锁
    if strCNTRCode ~= '' then
        -- 容器解锁
        nRet, strRetInfo = wms.wms_UnlockCntr( strLuaDEID, strCNTRCode )
        if nRet ~= 0 then
            return 1, "wms_UnlockCntr 失败!"..strRetInfo
        end
    end

    if carry_cb_cls == "Pre_Alloc_Container" then
        -- 如果作业携带的容器是【预分配容器】，需要把预分配容器的状态也设置为｛完成｝
        if carry_cb_no ~= '' then
            -- 配盘容器的状态 = 0，1
            strCondition = "S_PAC_NO = '"..carry_cb_no.."' AND (N_B_STATE <= 1 )"
            strSetAttr = "N_B_STATE = 5"   -- 完成
            nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Pre_Alloc_Container", strCondition, strSetAttr )
            if nRet ~= 0 then
                return nRet, strRetInfo
            end  
        end  
    elseif carry_cb_cls == "Distribution_CNTR" then         
        -- 如果作业携带的容器是【预分配容器】，需要把预分配容器的状态也设置为完成
        if carry_cb_no ~= '' then
            -- 配盘容器的状态 = 0，1，2 7
            strCondition = "S_DC_NO = '"..carry_cb_no.."' AND (N_B_STATE <= 2 OR N_B_STATE = 7)"
            strSetAttr = "N_B_STATE = 6"
            nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Distribution_CNTR", strCondition, strSetAttr )
            if nRet ~= 0 then
                return nRet, strRetInfo
            end  
        end
    end
    return 0,""
end

-- 设置【作业】状态=取消
--[[
    @function wms_op.SetCancel
    设置【作业】状态=取消

    @tparam string strLuaDEID Lua数据引擎ID
    @tparam string|table operation 作业编码 或 作业数据对象(table)
    @treturn number nRet 返回码: 0成功, 非0失败
    @treturn string strRetInfo 错误信息
--]]
function wms_op.SetCancel( strLuaDEID, operation )
    local nRet, strRetInfo
    local strOpCode = ''
    local strCNTRCode = ''

    if type(operation) == "string" then
        strOpCode = operation
    else
        strOpCode = operation.code
        strCNTRCode = operation.cntr_code
    end

    -- 输入参数检查
    if strOpCode == nil or strOpCode == '' then
        return 1, "调用 wms_op.SetFinish 函数时参数不正确, 作业编码不能为空!"
    end
    local b_state = OPERATION_STATE.Cancel  -- 取消
    local strCondition
    local str_b_state = wms_base.GetDictItemName( strLuaDEID, "WMS_OperationState", b_state ) 

    local curTime = os.date("%Y-%m-%d %H:%M:%S")
    strCondition = "S_CODE = '"..strOpCode.."'"
    local strSetAttr = "N_B_STATE="..b_state..", S_B_STATE='"..str_b_state.."', T_END_TIME='"..curTime.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Operation", strCondition, strSetAttr )
    if nRet ~= 0 then
        return nRet, strRetInfo
    end  

    -- 解锁由该作业造成的货位锁，逻辑库区锁都解除
    nRet, strRetInfo = wms.wms_UnlockByOperation( strLuaDEID, strOpCode )
    if nRet ~= 0 then
        return 1, "wms_UnlockByOperation 失败! "..strRetInfo
    end

    -- 容器解锁
    if strCNTRCode ~= '' then
        -- 容器解锁
        nRet, strRetInfo = wms.wms_UnlockCntr( strLuaDEID, strCNTRCode )
        if nRet ~= 0 then
            return 1, "wms_UnlockCntr 失败!"..strRetInfo
        end
    end

    return 0,""
end

--[[
    @function wms_op.Reset
    设置【作业】状态=执行，错误码清空

    @tparam string strLuaDEID Lua数据引擎ID
    @tparam table obj 作业对象(Operation类型table)
    @treturn number nRet 返回码: 0成功, 非0失败
    @treturn string strRetInfo 错误信息
--]]
function wms_op.Reset( strLuaDEID, obj )
    local nRet, strRetInfo

    assert( type(obj) == "table", "wms_op.Reset 的输入参数 obj 必须是一个 table 类型" )  
    assert( obj.cls == "Operation", "wms_op.Reset 的输入参数 obj 必须是'Operation'类型的数据对象" )

    local b_state = obj.laste_b_state
    local strCondition
    local str_b_state = wms_base.GetDictItemName( strLuaDEID, "WMS_OperationState", b_state ) 

    strCondition = "S_CODE = '"..obj.code.."' AND N_B_STATE >= 3"
    local strSetAttr = "N_FAIL_COUNT = 0, N_B_STATE="..b_state..", S_B_STATE='"..str_b_state.."', S_ERR=''"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Operation", strCondition, strSetAttr )
    if nRet ~= 0 then
       return nRet, strRetInfo
    end  

    return 0,""
end

--[[
    设置作业中的任务状态
        0 表示任务没下发
        1 表示有任务已经推送给设备
        2 任务已经执行
        3 已经执行完成

    @function wms_op.SetTaskState
    @tparam string strLuaDEID Lua数据引擎ID
    @tparam string op_code 作业编码
    @tparam number task_state 任务状态值
    @treturn number nRet 返回码: 0成功, 非0失败
--]]
function wms_op.SetTaskState( strLuaDEID, op_code, task_state )
    local nRet, strRetInfo

    if op_code == nil or op_code == '' then
        return 1, "函数 wms_op.SetTaskState 中的 op_code 必须有值!"
    end
    if task_state == nil then
        return 1, "函数 wms_op.SetTaskState 中的 task_state 必须有值!"
    end

    -- 设置任务已经推送
    local strCondition, strSetAttr
    if task_state == OP_TASK_STATE.Pushed then
        strCondition = "S_CODE = '"..op_code.."' AND N_TASK_STATE = 0"
        strSetAttr = "N_TASK_STATE = 1"
    -- 2 任务已经执行
    elseif task_state == OP_TASK_STATE.Run then
        strCondition = "S_CODE = '"..op_code.."' AND N_TASK_STATE = 1"
        strSetAttr = "N_TASK_STATE = 2"        
    else
        return 0
    end
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Operation", strCondition, strSetAttr )
    if nRet ~= 0 then
        return nRet, strRetInfo
    end
    
    return 0
end

--[[
    @function wms_op.Create
    点到点创建作业

    @tparam string strLuaDEID Lua数据引擎ID
    @tparam string cntr_code 容器号
    @tparam string from_loc_code 起点货位编码
    @tparam string to_loc_code 终点货位编码
    @tparam number op_type 作业类型
    @tparam string op_def_name 作业定义名称
    @tparam table|nil ext_info 扩展信息 { lock_cntr, source_sys, bs_type, bs_no }
    @treturn number nRet 返回码: 0成功, 1参数非法, 2创建失败
    @treturn table|string operation 作业对象或错误信息
]]
function wms_op.Create( strLuaDEID, cntr_code, from_loc_code, to_loc_code, op_type, op_def_name, ext_info )
    local nRet

    -- 输入参数验证
    if lua.StrIsEmpty( to_loc_code ) then
        return 1, "wms_op.Create 函数参数 to_loc_code 非法!"
    end
    if lua.StrIsEmpty( cntr_code ) then
        return 1, "wms_op.Create 函数参数 cntr_code 非法!"
    end
    if lua.StrIsEmpty( from_loc_code ) then
        return 1, "wms_op.Create 函数参数 from_loc_code 非法!"
    end
    if lua.StrIsEmpty( op_def_name ) then
        return 1, "wms_op.Create 函数参数 op_def_name 非法!"
    end
    if op_type == nil then
        return 1, "wms_op.Create 函数参数 op_type 非法!"
    end

    local source_sys = ""
    local lock_cntr = 'Y'
    local bs_type = ''
    local bs_no = ''

    if ext_info ~= nil then 
        source_sys = lua.Get_StrAttrValue( ext_info.source_sys )
        bs_type = lua.Get_StrAttrValue( ext_info.bs_type )
        bs_no = lua.Get_StrAttrValue( ext_info.bs_no )
        lock_cntr = lua.Get_StrAttrValue( ext_info.lock_cntr )
    end
    if lock_cntr == '' then
        lock_cntr = 'Y'
    end

    local to_loc
    nRet, to_loc = wms_wh.GetLocInfo( to_loc_code )
    if nRet ~= 0 then
        return 1, '获取货位信息失败! '..to_loc
    end  

    local from_loc
    nRet, from_loc = wms_wh.GetLocInfo( from_loc_code )
    if nRet ~= 0 then
        return 1, '获取货位信息失败! '..from_loc
    end  

    local operation = m3.AllocObject(strLuaDEID,"Operation")
    operation.source_sys = source_sys
    operation.start_wh_code = from_loc.wh_code
    operation.start_area_code = from_loc.area_code
    operation.start_loc_code = from_loc_code

    operation.end_wh_code = to_loc.wh_code
    operation.end_area_code = to_loc.area_code
    operation.end_loc_code = to_loc_code

    operation.op_type = op_type
    operation.op_def_name = op_def_name
    operation.cntr_code = cntr_code
    operation.lock_cntr = lock_cntr
    operation.bs_type = bs_type
    operation.bs_no = bs_no
    
    nRet, operation = m3.CreateDataObj( strLuaDEID, operation )
    if nRet ~= 0 then
        return 2, '创建【作业】失败!'..operation
    end
   
    return 0, operation
end

--[[
    @function wms_op.CanCancel
    判断作业是否可以取消, 顺带返回作业对象

    @tparam string strLuaDEID Lua数据引擎ID
    @tparam string op_code 作业编码
    @treturn number nRet 返回码: 0函数执行正确, 非0错误
    @treturn bool can_cancel 是否可取消
    @treturn table|nil operation 作业对象(不存在时为nil)
--]]
function wms_op.CanCancel( strLuaDEID, op_code )
    local nRet
    local operation

    nRet, operation = wms_op.GetInfo( strLuaDEID, op_code )
    if nRet == 1 then 
        -- 作业已经被删除，不存在
        operation = nil
        return 0, true,  operation
    end
    if nRet > 1 then
        return nRet, operation
    end 

    -- 作业已经完成不能取消
    if operation.b_state == 2 then
        return 0, false, operation
    end

    -- 作业在执行中
    if operation.b_state == 1 then
        if operation.task_state == 2 then
            return 0, false, operation
        end
    end
    return 0, true, operation
end     

--[[
    @function wms_op.Create_Distribution_OutOperation
    创建一个配盘出库作业

    @tparam string strLuaDEID Lua数据引擎ID
    @tparam table dist_cntr_data 配盘数据对象 { S_DC_NO, S_CNTR_CODE, ... }
    @tparam number|nil priority 优先级(默认1)
    @treturn number nRet 返回码: 0成功, 非0失败
    @treturn string nil|msg 错误信息
--]]
function wms_op.Create_Distribution_OutOperation ( strLuaDEID, dist_cntr_data, priority ) 
    local nRet, strRetInfo
    local msg
    local dc_no = dist_cntr_data.S_DC_NO 
    local b_state = lua.Get_NumAttrValue( dist_cntr_data.N_B_STATE )
    local to_station = lua.Get_StrAttrValue( dist_cntr_data.S_STATION_NO )
    local cntr_code = dist_cntr_data.S_CNTR_CODE   
    local from_loc_code = lua.Get_StrAttrValue( dist_cntr_data.S_LOC_CODE )
    local to_area_code = lua.Get_StrAttrValue( dist_cntr_data.S_EXIT_AREA_CODE )
    local to_loc_code = lua.Get_StrAttrValue( dist_cntr_data.S_EXIT_LOC_CODE )       -- 出库货位
    local bs_no = lua.Get_StrAttrValue( dist_cntr_data.S_BS_NO )                     -- 业务来源
    local bs_type = lua.Get_StrAttrValue( dist_cntr_data.S_BS_TYPE )                 -- 业务来源类型
    local source_sys = lua.Get_StrAttrValue( dist_cntr_data.S_SOURCE_SYS )

    if priority == nil then
        priority = 1
    end
    
    if to_station == '' then
        return 1, "wms_op.Create_Distribution_OutOperation 函数中 dist_cntr_data 中必须有 S_STATION_NO!"
    end
    local op_def_name = lua.Get_StrAttrValue( dist_cntr_data.S_OUT_OP_NAME )
    if op_def_name == '' then
        return 1, "wms_op.Create_Distribution_OutOperation 函数中 dist_cntr_data 中必须有 S_OUT_OP_NAME!"
    end

    -- 【配盘】数据对象属性判断，不合法的终止程序执行
    -- b_state 不是配货完成状态
    if b_state ~= DIST_CNTR_STATE.PrePickingOK then
        msg = "配盘号'"..dc_no.."'的状态不是配货完成状态，不能启动配盘出库作业!"
        lua.Warning( strLuaDEID, debug.getinfo(1), msg )
        return 1, msg
    end

    if from_loc_code == '' then
        nRet, from_loc_code = wms_cntr.Get_Container_Loc( strLuaDEID, cntr_code )
        if nRet ~= 0 or from_loc_code == '' then
            return 1, "配盘号'"..dc_no.."'中的容器'"..cntr_code.."'没有绑定货位!"
        end
    end
    
    local from_loc
    nRet, from_loc = wms_wh.GetLocInfo( from_loc_code )
    if nRet ~= 0 then 
        return 1, '获取货位信息失败! '..from_loc_code
    end      

    -- 获取站点货位，站点货位定义在常量中
    local to_wh_code = ''

    if to_loc_code == '' then 
        local area
        if to_area_code ~= '' then
            nRet, area = wms_wh.GetAreaInfo( to_area_code )
            if nRet ~= 0 then 
                return 1, "获取库区'"..to_area_code.."'信息失败! "..area
            end              
            to_wh_code = area.wh_code
        end
    else
        local to_loc
        nRet, to_loc = wms_wh.GetLocInfo( to_loc_code )
        if nRet ~= 0 then 
            return 1, '获取货位信息失败! '..to_loc
        end  
        to_wh_code = to_loc.wh_code
        to_area_code = to_loc.area_code
    end

    -- 创建【货品出库】作业. 【配盘】状态改为2（出库中）
    local operation = m3.AllocObject(strLuaDEID,"Operation")
    operation.b_state = OPERATION_STATE.BeforeStartup    -- 待启动前，这些作业有待后台脚本来设置为状态 0 
    operation.start_wh_code = from_loc.wh_code
    operation.start_area_code = from_loc.area_code
    operation.start_loc_code = from_loc_code
    operation.station = to_station
    operation.priority = priority

    operation.end_wh_code = to_wh_code
    operation.end_area_code = to_area_code
    operation.end_loc_code = to_loc_code

    operation.op_type = OPERATION_TYPE.Outbound
    operation.op_def_name = op_def_name
    operation.cntr_code = cntr_code
    
    -- 说明作业携带的容器的业务类型
    operation.carry_cb_cls = "Distribution_CNTR"
    operation.carry_cb_no = dc_no

    operation.source_sys = source_sys
    operation.bs_type = bs_type
    operation.bs_no = bs_no

    nRet, operation = m3.CreateDataObj( strLuaDEID, operation )
    if nRet ~= 0 then 
        return 1, '创建【作业】失败!'..operation 
    end  

    -- 更新【配盘】对象属性
    -- DIST_CNTR_STATE.Out 表示配盘容器已经安排作业进行搬运
    local strUpdateSql = "S_LOC_CODE = '"..from_loc_code.."', N_B_STATE = "..DIST_CNTR_STATE.Out..", S_OUT_OP_NO = '"..operation.code.."'"
    strCondition = "S_DC_NO = '"..dc_no.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Distribution_CNTR", strCondition, strUpdateSql )
    if nRet ~= 0 then  
        return 1, "更新【配盘】信息失败!"..strRetInfo  
    end   
    
    return 0
end

--[[
    创建入库作业
    根据站台位置创建一个入库到立库的入库作业，适合站台-->立库,
    物流规划: 通过AGV或输送线把料箱从站台搬运到立库巷道堆垛机入库接驳位，然后堆垛机从接驳位取货搬运到立库

    @function wms_op.Create_Inbound_Operation
    @tparam string strLuaDEID Lua数据引擎ID
    @tparam string station 站台位置
    @tparam table container 容器对象
    @tparam string loc_code 容器绑定货位编码
    @tparam table parameter 输入参数 {
        carry_cb_cls, carry_cb_no,   -- 作业携带容器业务类型/编号
        bs_type, bs_no,              -- 业务类型/编号
        factory,                     -- 工厂标识
        wh_code, area_code,          -- 去向仓库/库区编码
        op_def_name,                 -- 入库作业类型定义
        get_putway_loc_first         -- 是否需要先计算货位
        need_sync_cntr_loc           -- 是否需要同步获取计算库位， false 就是异步
                                        如果是同步获取库位，作业状态为 待启动
        priority                     -- 作业优先级
    }
    @treturn number nRet 返回码: 0成功, 非0失败
    @treturn table|string operation 作业对象或错误信息
--]]
function wms_op.Create_Inbound_Operation( strLuaDEID, station, container, loc_code, parameter )
    local nRet, strRetInfo, can_usedin_op
    local cntr_code = container.code or ''
    if loc_code == '' or loc_code == nil then
        return 1, "wms_op.Create_Inbound_Operation 函数中容器绑定货位 loc_code 必须有值!"
    end 

    local loc
    nRet, loc = wms_wh.GetLocInfo( loc_code )
    if nRet ~= 0 then
        return 1, '获取货位信息失败! '..loc
    end  

    if parameter == nil then
        return 1, "wms_op.Create_Inbound_Operation 函数中容器绑定货位 parameter 必须有值!"
    end
    local get_putway_loc_first = parameter.get_putway_loc_first or true
    local need_sync_cntr_loc = parameter.need_sync_cntr_loc or false
    local priority = parameter.priority or 1

    --V2.0 创建作业前对容器进行判断，如容器已经存在 active 作业，不能创建
    nRet, can_usedin_op = wms_cntr.CanUsedInOperation( strLuaDEID, cntr_code )
    if nRet ~= 0 then
        return 2, can_usedin_op
    end
    if can_usedin_op == false then
        return 1, "料箱'"..cntr_code.."'存在未完成的作业，不能继续创建作业!"
    end
    
    -- 获取入库作业类型，通过作业类型里定义的上架策略来计算 入库货位
    local op_def
    local op_def_name = parameter.op_def_name or ''
    if op_def_name == '' then
        return 1, "在创建入库作业时失败，没定义入库作业类型!"
    end
    local factory = parameter.factory or ''
    if factory == '' then
        return 1, "在创建入库作业时失败, 在parameter参数中没定义工厂标识!"
    end

    nRet, op_def = wms_base.GetOpDefInfo( factory, op_def_name )
    if nRet ~= 0 then
        return 1, "系统无法获取名为'"..op_def_name.."'的作业类型! "..op_def
    end

    local operation = m3.AllocObject(strLuaDEID,"Operation")
    operation.factory = factory
    operation.b_state = OPERATION_STATE.BeforeStartup    -- 待启动前，这些作业有待后台脚本来设置为状态 0 
    operation.source_sys = op_def.source_sys
    operation.start_wh_code = loc.wh_code
    operation.start_area_code = loc.area_code
    operation.start_loc_code = loc_code
    operation.priority = priority
    operation.station = station
    operation.op_type = OPERATION_TYPE.Inbound
    operation.op_def_name = op_def_name
    operation.cntr_code = cntr_code
    
    if parameter ~= nil and parameter ~= '' then
        operation.carry_cb_cls = lua.Get_StrAttrValue( parameter.carry_cb_cls )
        operation.carry_cb_no = lua.Get_StrAttrValue( parameter.carry_cb_no )
        operation.bs_type = lua.Get_StrAttrValue( parameter.bs_type )
        operation.bs_no = lua.Get_StrAttrValue( parameter.bs_no )
    end

    nRet, operation = m3.CreateDataObj( strLuaDEID, operation )
    if nRet ~= 0 then 
        return 2, '创建【作业】失败!'..operation 
    end 

    if get_putway_loc_first then
        -- 需要根据上架策略计算货位，后台线程队列去计算货位
        -- 根据作业定义里的上架策略进行货位计算
        parameter.station = station
        parameter.cntr_code = cntr_code
        parameter.operation_code = operation.code
        local proc_id  -- 后台处理线程句柄
        -- 后台线程通过队列的方法进行上架货位计算，计算后的结果放在 Operation_To
        -- 注意： GetInboundAreaLoc 是编码 = WMS-70-05 的标准脚本

        if need_sync_cntr_loc then
            -- 采用同步获取库位信息，可以吧作业直接设置为待启动状态，速度会快一些
            -- 6秒超时，轮休间隔 100 毫秒
            nRet, strRetInfo = wms_base.WaitForPostEventProcess( "Putaway_Strategy","GetInboundAreaLoc", lua.table2str( parameter ), 6, 100 )            
            if nRet ~= 0 then 
                return 2, strRetInfo
            end
            local success, result = pcall( json.decode, strRetInfo )
            if not success then
                return 1, "GetInboundAreaLoc 返回的的计算库位结果的JSON格式不合法!"
            end

            -- 更新【作业】对象的终点货位和库区、仓库等信息
            local to_loc_code = result.loc_code or ''
            local to_loc
            nRet, to_loc = wms_wh.GetLocInfo( to_loc_code )
            if nRet ~= 0 then
                return 1, '获取货位信息失败! '..to_loc
            end        
            local strUpdateSql, strCondition
            local to_wh_code = to_loc.wh_code or ''
            local to_area_code = to_loc.area_code or ''
            strUpdateSql = "S_END_WH = '"..to_wh_code.."', S_END_AREA = ''"..to_area_code.."', S_END_LOC = '"..to_loc_code.."', N_B_STATE = "..OPERATION_STATE.WaitStartup
            strCondition = "S_CODE = '"..operation.code.."'"
            nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Operation", strCondition, strUpdateSql )
            if nRet ~= 0  then  
                return 1, "更新【Operation】状态信息失败!"..strRetInfo
            end    
            strCondition = "S_OP_CODE = '"..operation.code.."'"
            nRet, strRetInfo = mobox.dbdeleteData( strLuaDEID, "Operation_To", strCondition )
            if nRet ~= 0 then 
                return 1, "删除【Operation_To】失败!  "..strRetInfo
            end 
            
        else
            nRet, proc_id = mobox.addBackendScriptProc( "Putaway_Strategy","GetInboundAreaLoc", lua.table2str( parameter ) )
            if nRet ~= 0 then 
                return 2, proc_id
            end
        end
    end
    return 0, operation
end

--[[
    @function wms_op.Create_IWP_OutOperation
    创建一个库内业务（指定出库, 理货, 盘点）的出库作业

    @tparam string strLuaDEID Lua数据引擎ID
    @tparam table iwp_cntr_date 库内作业关联容器 { S_IWPC_NO, S_CNTR_CODE, ... }
    @tparam bool|nil lock_cntr 是否锁容器(true则锁, 默认true)
    @treturn number nRet 返回码: 0成功, 非0失败
    @treturn string nil|msg 错误信息
--]]
function wms_op.Create_IWP_OutOperation ( strLuaDEID, iwp_cntr_date, lock_cntr  ) 
    local nRet, strRetInfo
    local msg

    if lock_cntr == nil then
        lock_cntr = true
    end

    local iwpc_no = iwp_cntr_date.S_IWPC_NO 
    local b_state = lua.Get_NumAttrValue( iwp_cntr_date.N_B_STATE )
    local to_station = lua.Get_StrAttrValue( iwp_cntr_date.S_STATION_NO )
    local cntr_code = iwp_cntr_date.S_CNTR_CODE or ''  
    local from_loc_code = lua.Get_StrAttrValue( iwp_cntr_date.S_LOC_CODE )
    local to_area_code = lua.Get_StrAttrValue( iwp_cntr_date.S_EXIT_AREA_CODE )
    local to_loc_code = lua.Get_StrAttrValue( iwp_cntr_date.S_EXIT_LOC_CODE )       -- 出库货位

    local bs_no = iwp_cntr_date.S_IWP_NO or ''

    if to_station == '' then
        return 1, "wms_op.Create_IWP_OutOperation 函数中 iwp_cntr_date 中必须有 S_STATION_NO!"
    end
    if cntr_code == '' then
        return 1, "wms_op.Create_IWP_OutOperation 函数中 iwp_cntr_date 中必须有 S_CNTR_CODE!"
    end

    local op_def_name = lua.Get_StrAttrValue( iwp_cntr_date.S_OUT_OP_NAME )
    if op_def_name == '' then
        return 1, "wms_op.Create_IWP_OutOperation 函数中 iwp_cntr_date 中必须有 S_OUT_OP_NAME!"
    end

    -- 【配盘】数据对象属性判断，不合法的终止程序执行
    -- b_state 的状态已经有启动作业
    if b_state ~= IWPC_STATE.Wait and b_state ~= IWPC_STATE.Lock then
        msg = "库内作业容器流水号'"..iwpc_no.."'的状态不能启动出库作业!"
        lua.Warning( strLuaDEID, debug.getinfo(1), msg )
        return 1, msg
    end

    if from_loc_code == '' then
        nRet, from_loc_code = wms_cntr.Get_Container_Loc( strLuaDEID, cntr_code )
        if nRet ~= 0 or from_loc_code == '' then
            return 1, "库内作业容器流水号'"..iwpc_no.."'中的容器'"..cntr_code.."'没有绑定货位!"
        end
    end
    
    local from_loc
    nRet, from_loc = wms_wh.GetLocInfo( from_loc_code )
    if nRet ~= 0 then 
        return 1, '获取货位信息失败! '..from_loc_code
    end      

    -- 获取站点货位，站点货位定义在常量中
    local to_wh_code = ''

    if to_loc_code == '' then 
        local area
        if to_area_code ~= '' then
            nRet, area = wms_wh.GetAreaInfo( to_area_code )
            if nRet ~= 0 then 
                return 1, "获取库区'"..to_area_code.."'信息失败! "..area
            end              
            to_wh_code = area.wh_code
        end
    else
        local to_loc
        nRet, to_loc = wms_wh.GetLocInfo( to_loc_code )
        if nRet ~= 0 then 
            return 1, '获取货位信息失败! '..to_loc
        end  
        to_wh_code = to_loc.wh_code
        to_area_code = to_loc.area_code
    end

    -- 创建出库作业. 【库内作业容器】状态改为2（出库中）
    local operation = m3.AllocObject(strLuaDEID,"Operation")
    operation.b_state = OPERATION_STATE.BeforeStartup    -- 待启动前，这些作业有待后台脚本来设置为状态 0 
    operation.start_wh_code = from_loc.wh_code
    operation.start_area_code = from_loc.area_code
    operation.start_loc_code = from_loc_code
    operation.station = to_station

    operation.end_wh_code = to_wh_code
    operation.end_area_code = to_area_code
    operation.end_loc_code = to_loc_code

    operation.op_type = OPERATION_TYPE.Outbound
    operation.op_def_name = op_def_name
    operation.cntr_code = cntr_code

    operation.bs_type = "IW_Process"
    operation.bs_no = bs_no
    
    -- 说明作业携带的容器的业务类型
    operation.carry_cb_cls = "IWP_Container"
    operation.carry_cb_no = iwpc_no

    if lock_cntr then 
        operation.lock_cntr = 'Y'
    else
        operation.lock_cntr = 'N'
    end

    nRet, operation = m3.CreateDataObj( strLuaDEID, operation )
    if nRet ~= 0 then 
        return 1, '创建【作业】失败!'..operation 
    end  

    -- 更新【配盘】对象属性
    -- IWPC_STATE.Out 表示配盘容器已经安排作业进行搬运
    local strUpdateSql = "S_LOC_CODE = '"..from_loc_code.."', N_B_STATE = "..IWPC_STATE.Out..", S_OUT_OP_NO = '"..operation.code.."'"
    strCondition = "S_IWPC_NO = '"..iwpc_no.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "IWP_Container", strCondition, strUpdateSql )
    if nRet ~= 0 then  
        return 1, "更新【IWP_Container盘】信息失败!"..strRetInfo  
    end   
    
    return 0
end

-- 插入作业日志
-- @function wms_op.InsertLog
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string op_code 作业编码，必须有值
-- @tparam number log_type 日志类型, 必须有值
-- @tparam string log_msg 日志内容，必须有值
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
function wms_op.InsertLog( strLuaDEID, op_code, log_type, log_msg )
    if op_code == nil or op_code == '' then
        return 1, "wms_op.InsertLog 函数中 op_code 必须有值!"
    end
    local strCondition = "S_OP_CODE = '"..op_code.."'"
    local nRet, last_log_data = m3.GetDataObjByCondition2( strLuaDEID, "Operation_Log", strCondition, "T_CREATE Desc" )

    local insert_log = false
    if nRet == 1 then
        -- 没有日志
        insert_log = true
    elseif nRet == 0 then
        -- 有日志
        if last_log_data.N_LOG_TYPE ~= log_type or
           last_log_data.S_LOG_MSG ~= log_msg then
            insert_log = true
        end
    end
    if insert_log then
        local log_data = m3.AllocObject2(strLuaDEID, "Operation_Log")

        log_data.S_OP_CODE = op_code
        log_data.N_LOG_TYPE = log_type
        log_data.S_LOG_MSG = log_msg
        nRet, log_data = m3.CreateDataObj2(strLuaDEID, log_data)
        if nRet ~= 0 then
            return 1, "创建作业日志失败! 原因:" .. log_data
        end
        return 0, "new_log"
    end
    return 0, ""
end

return wms_op