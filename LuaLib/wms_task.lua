--[[
    版本：     Version 3.0
    创建日期： 2023-6-16
    修改日期:  2026-6-19
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    名称:   wms_task
    功能：   Task Lua程序包整合了一些【任务】对象相关的操作

    【任务状态】
        GetPushedCount         — 获取调度系统已经推送的任务数量
        SetState               — 设置任务状态
        SetRunState            — 设置任务状态为"执行"
        SetErrState            — 设置任务错误状态

    【任务信息】
        GetInfo                — 根据任务号获取任务属性
        Update                 — 更新任务数据对象
        Action_Exist           — 判断任务下是否存在某个动作码

    【任务操作】
        LockLocation           — 给任务的两个货位加锁
        GetEndLocInAreaCount   — 获取物理库区任务数量
        After_TaskFinish       — 任务完成后的标准处理流程

    更改记录:
        2023-6-16  HAN  创建
        2026-6-19       整理函数注释，添加 @tparam/@treturn 注解

    AI CHECK:
        -- 20260619
--]]

wms_base = require ("wms_base")
wms_wh   = require ("wms_wh")

local wms_task = {_version = "0.2.1"}

-- 获取调度系统已推送的任务数量
-- @function wms_task.GetPushedCount
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strSecheduleType 调度类型（常量名或数值）
-- @treturn number nRet 0: 成功，非0: 失败
-- @treturn number nCount 任务数量
function wms_task.GetPushedCount( strLuaDEID, strSecheduleType )
    local nRet, strRetInfo
    local strCondition

    local nSecheduleType
    if type(strSecheduleType) == "string"  then
        nSecheduleType = wms_base.Get_nConst( strLuaDEID, strSecheduleType )
    else
        nSecheduleType = strSecheduleType
    end
    -- 获取某种调度类型的任务数量
    -- 1 已推送 2 -- 执行
    strCondition = "N_SCHEDULE_TYPE = "..nSecheduleType.." AND ( N_B_STATE = 1 OR N_B_STATE = 2 )"
    nRet, strRetInfo = mobox.getDataObjCount( strLuaDEID, "Task", strCondition )
    if nRet ~= 0  then
        return nRet, strRetInfo
    end
    return 0, tonumber( strRetInfo )
end

-- 设置任务错误状态
-- @function wms_task.SetErrState
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table task 任务对象（含 id, cls）
-- @tparam number nErrCode 错误码
-- @tparam string strErr 错误信息
-- @treturn number nRet 0: 成功，非0: 失败
-- @treturn string result 错误信息
function wms_task.SetErrState( strLuaDEID, task, nErrCode, strErr )
    if task.id == nil or task.id == ''  then
        return 1, "调用 wms_task.SetErrState 函数时参数不正确, 任务ID不能为空!"
    end

    -- 根据字典获取 N_B_STATE 的显示名称
    local str_b_state = wms_base.GetDictItemName( strLuaDEID, "WMS_TaskState", 4 )           -- 4 表示错误状态
    local condition = "S_ID = '"..task.id.."'"
    local strSetAttr = "N_B_STATE = 4, S_B_STATE = '"..str_b_state.."', S_ERR='"..strErr.."', N_ERR = "..nErrCode
    local nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, task.cls, condition, strSetAttr )
    if nRet ~= 0  then
       return nRet, "更新任务对象失败!"..strRetInfo
    end
    return 0, "ok"
end

-- 设置任务状态为"执行"
-- @function wms_task.SetRunState
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table task 任务对象（含 code, cls）
-- @tparam string executor_id 执行者ID（可选）
-- @tparam string executor_name 执行者名称（可选）
-- @treturn number nRet 0: 成功，非0: 失败
function wms_task.SetRunState( strLuaDEID, task, executor_id, executor_name )

    local nBState = TASK_STATE.Run
    -- 根据字典获取 N_B_STATE 的显示名称
    local str_b_state = wms_base.GetDictItemName( strLuaDEID, "WMS_TaskState", nBState ) 
    local condition = "S_CODE = '"..task.code.."'"
    local strSetAttr

    strSetAttr = "N_B_STATE = "..nBState..", S_B_STATE = '"..str_b_state.."', T_START_TIME = '"..os.date("%Y-%m-%d %H:%M:%S").."'"
    if executor_id ~= nil and executor_id ~= '' and executor_name ~= nil and executor_name ~= '' then
        strSetAttr = strSetAttr..",S_EXECUTOR_ID = '"..executor_id.."', S_EXECUTOR_NAME = '"..executor_name.."'"
    end
    local nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, task.cls, condition, strSetAttr )
    if nRet ~= 0 then
        return 1, "设置任务状态失败!"..strRetInfo
    end
    return 0
end

-- 设置任务状态（代替原 SetStateByCode）
-- @function wms_task.SetState
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string task_code 任务编码
-- @tparam number b_state 任务状态值
-- @tparam string strErr 错误信息（可选）
-- @treturn number nRet 0: 成功，非0: 失败
-- @treturn string result "ok"或错误信息
function wms_task.SetState( strLuaDEID, task_code, b_state, strErr )
    local nRet, strRetInfo

    if task_code == nil or task_code == ''  then
        return 1, "调用 wms_task.SetState 函数时参数不正确, 任务编码不能为空!"
    end  
    if b_state == nil then
        return 1, "调用 wms_task.SetState 函数时参数不正确, 状态不能为空!"
    end   
    if strErr == nil then strErr = '' end
    -- 根据字典获取 N_B_STATE 的显示名称
    local str_b_state = wms_base.GetDictItemName( strLuaDEID, "WMS_TaskState", b_state ) 
    local condition = "S_CODE = '"..task_code.."'"
    local strSetAttr = "N_B_STATE = "..b_state..", S_B_STATE = '"..str_b_state.."', S_ERR = '"..strErr.."'"

    -- 设置任务为执行状态
    if b_state == TASK_STATE.Run  then
        local curTime = os.date("%Y-%m-%d %H:%M:%S")
        strSetAttr = strSetAttr..", T_START_TIME = '"..curTime.."'"
    end

    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Task", condition, strSetAttr )
    if nRet ~= 0  then
       return nRet, "设置任务状态失败!"..strRetInfo
    end
    return 0, "ok"
end

-- 根据任务号获取任务属性，不存在则返回非0
-- @function wms_task.GetInfo
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string task_code 任务编码
-- @treturn number nRet 0: 成功，1: 不存在，2: 错误
-- @treturn table/string object 任务对象或错误信息
function wms_task.GetInfo( strLuaDEID, task_code )
    if task_code == nil or task_code == ''  then
        return 2, "调用 WMS_Task_GetBaseInfo 函数时参数不正确，任务编码不能为空!"
    end
    local nRet, strRetInfo, id
    local strCondition = "S_CODE = '"..task_code.."'"
    nRet, id, strRetInfo = mobox.getDataObjAttrByKeyAttr( strLuaDEID, "Task", strCondition )
    if nRet == 1  then
        return 1, "任务编码='"..task_code.."'的任务不存在!"
    end
    if nRet ~= 0   then
        return 2, "getDataObjAttrByKeyAttr 发生错误!"..id
    end

    nRet, strRetInfo = mobox.objAttrsToLuaJson( "Task", strRetInfo )
    if nRet ~= 0   then
        return 2, "objAttrsToLuaJson Task 失败!"..strRetInfo
    end

    local object, success
    success, object = pcall( json.decode, strRetInfo )
    if success == false  then
        return 2, "objAttrsToLuaJson('Task') 返回的的JSON格式不合法!"
    end
    object.id = id
    return 0, object
end

-- 更新任务数据对象，需要有任务ID
-- @function wms_task.Update
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table task 任务对象（含 id, cls）
-- @treturn number nRet 0: 成功，非0: 失败
-- @treturn string result "ok"或错误信息
function wms_task.Update( strLuaDEID, task )
    if task.id == nil or task.id == ''  then
        return 1, "调用 wms_task.Update 函数时参数不正确, 任务ID不能为空!"
    end
    local nRet, strAttrs
    nRet, strAttrs = mobox.luaJsonToObjAttrs(task.cls, lua.table2str(task))
    if nRet ~= 0 then
        return nRet, strAttrs
    end

    local strUpdate = '[{"id":"'..task.id..'","attrs":'..strAttrs..'}]'
    local strRetInfo

    nRet, strRetInfo = mobox.updateDataObj( strLuaDEID, task.cls, strUpdate, 1 )
    if nRet ~= 0  then
        return nRet, strRetInfo
    end
    return 0, "ok"
end

-- 判断任务下是否存在某个动作码
-- @function wms_task.Action_Exist
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string task_code 任务编码
-- @tparam string action_code 动作码
-- @treturn number nRet 0: 成功，非0: 失败
-- @treturn string result "yes"/"no"或错误信息
function wms_task.Action_Exist( strLuaDEID, task_code, action_code )
    local nRet, strRetInfo

    if task_code == '' or  task_code == nil then 
        return 1, "wms_task.Action_Exist 任务编码不能为空！"
    end
	local strCondition = "S_TASK_CODE ='"..task_code.."' AND N_ACTION_CODE = "..action_code
	nRet, strRetInfo = mobox.existThisData( strLuaDEID, "Task_Action", strCondition )
    if nRet ~= 0  then
        return 1, "在【任务动作】是否存在时失败! "..strRetInfo
    end
    if strRetInfo == 'no' then
        return 0, "no"
    end
    return 0, "yes"
end

-- 通过任务对象给任务的两个货位加锁
-- @function wms_task.LockLocation
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table task 任务对象（含 start_loc_code, end_loc_code, code, op_code, op_name）
-- @tparam string/number startLockType 开始货位锁类型（常量名或数值）
-- @tparam string/number endLockType 结束货位锁类型（常量名或数值）
-- @treturn number nRet 0: 成功，1: 失败
function wms_task.LockLocation( strLuaDEID, task, startLockType, endLockType )
    local nRet, strRetInfo

    if task == nil or type(task) ~= "table"  then 
        return 1, "wms_task.LockLocation  函数中 task不能为空而且必须是table类型!"
    end
    if startLockType == nil or startLockType == ""  then 
        return 1, "wms_task.LockLocation  函数中 startLockType 不能为空而且必须有值!"
    end
    if endLockType == nil or endLockType == ""  then 
        return 1, "wms_task.LockLocation  函数中 endLockType 不能为空而且必须有值!"
    end

    local nStartLockType, nEndLockType
    if type(startLockType) == "string" then
        nStartLockType = wms_base.Get_nConst( strLuaDEID, startLockType )
    else
        nStartLockType = startLockType
    end
    if type(endLockType) == "string" then
        nEndLockType = wms_base.Get_nConst( strLuaDEID, endLockType )
    else
        nEndLockType = endLockType
    end

    nRet, strRetInfo = wms.wms_LockLocation(strLuaDEID, task.start_loc_code, nStartLockType, task.code, task.op_code, task.op_name )
    if nRet ~= 0 then
        return 1, "wms_LockLocation 失败! 开始货位='"..task.start_loc_code.."'  "..strRetInfo
    end
    nRet, strRetInfo = wms.wms_LockLocation(strLuaDEID, task.end_loc_code, nEndLockType, task.code, task.op_code, task.op_name )
    if nRet ~= 0 then
        return 1, "wms_LockLocation 失败! 终止货位='"..task.end_loc_code.."'  "..strRetInfo
    end

    return 0
end

-- 获取物理库区中任务数量
-- @function wms_task.GetEndLocInAreaCount
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 物理库区编码
-- @tparam string str_task_type 任务类型（可选，常量名或数值）
-- @treturn number nRet 0: 成功，非0: 失败
-- @treturn number nCount 任务数量
function wms_task.GetEndLocInAreaCount( strLuaDEID, area_code, str_task_type )
    local nRet, strRetInfo
    local strCondition

    if area_code == nil or area_code == ''  then 
        return 1, "WMS_Task_GetAreaCount 函数area_code 不能为空!"
    end
    
    -- 获取物理库区某种任务类型数量
    -- N_B_STATE 0等待/1已推送/2执行中/3完成/4错误
    strCondition = "S_END_AREA = '"..area_code.."' AND  N_B_STATE <= 2 "
    if str_task_type ~= nil and str_task_type ~= '' then
        local nType
        if type(str_task_type) == "string" then
            nType = wms_base.Get_nConst( strLuaDEID, str_task_type )
        else
            nType = str_task_type
        end
        strCondition = strCondition.." AND N_TYPE = "..nType
    end

    nRet, strRetInfo = mobox.getDataObjCount( strLuaDEID, "Task", strCondition )
    if nRet ~= 0  then
        return nRet, strRetInfo
    end
    return 0, lua.StrToNumber( strRetInfo )
end

-- 任务完成后的标准处理流程，适用于大部分任务
-- 流程：获取当前Task → 解绑起点货位 → 绑定终点货位 → 解锁任务锁
-- @function wms_task.After_TaskFinish
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number nRet 0: 成功，非0: 失败
function wms_task.After_TaskFinish(strLuaDEID) 
    local nRet, strRetInfo

    -- 获取当前触发脚本的任务信息(Task)
    local task
    nRet, task = m3.GetSysCurEditDataObj( strLuaDEID, "Task" )
    if nRet ~= 0 then
        return 1, task
    end

    -- 解绑起点货位
    nRet, strRetInfo = wms_wh.Loc_Container_Unbinding( strLuaDEID, task.start_loc_code, task.cntr_code, "绑定解绑方法-系统",  
                                                    task.op_code.." "..task.op_name )
    if nRet ~= 0 then
        return 1, '货位容器解绑失败!'..strRetInfo
    end

    -- 绑定终点货位  
    nRet, strRetInfo = wms_wh.Loc_Container_Binding( strLuaDEID, task.end_loc_code, task.cntr_code, "绑定解绑方法-系统",  
                                                  task.op_code.." "..task.op_name )
    if nRet ~= 0 then
        return 1, '货位容器绑定失败!'..strRetInfo
    end

    -- 解锁由该任务造成的货位锁，逻辑库区锁都解除
    nRet, strRetInfo = wms.wms_UnlockByTask( strLuaDEID, task.code )
    if nRet ~= 0 then
        return 1, "wms_UnlockByTask 失败! "..strRetInfo
    end

    return 0
end

return wms_task
