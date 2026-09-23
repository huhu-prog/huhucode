--[[
    编码: WMS-80-22
    名称: 双深料箱库入库作业启动
    作者：XSY
    日期：2025-09-02
        
    入口函数： OperationStart
                  
    功能说明:

    变更记录:
--]] wms_base = require("wms_base")
json = require("json")
mobox = require("OILua_JavelinExt")
m3 = require("oi_base_mobox")
hc_plc = require("hcplc_base")
wms = require("OILua_WMS")

-- 料箱出库作业启动
function OperationStart(strLuaDEID)

    local nRet, isExist_priwait, operation_info, wms_task, strRetInfo

    nRet, operation_info = m3.GetSysCurEditDataObj(strLuaDEID, "Operation")
    if (nRet ~= 0) then
        lua.Stop(strLuaDEID, "双深料箱库入库作业启动-》获取待启动作业失败! " .. operation_info)
        return
    end
    lua.DebugEx(strLuaDEID, "开始启动作业", operation_info)

    -- 是否存在优先级更高的作业
    local sqlCondition = "N_B_STATE = 0 AND N_START_AISLE = " .. operation_info.start_aisle .. " AND N_PRIORITY > " ..
                             operation_info.priority
    nRet, isExist_priwait = mobox.existThisData(strLuaDEID, "Operation", sqlCondition)
    if (nRet ~= 0) then
        lua.Stop(strLuaDEID,
            "作业启动查询是否存在高优先级作业未启动失败!原因:" .. isExist_priwait)
        return
    end

    if isExist_priwait == 'yes' then
        lua.DebugEx(strLuaDEID, "当前作业" .. operation_info.code .. "存在更高优先级待启动,暂停启动",
            operation_info)
        return
    end

    -- 前置WMS任务号不为空时，检查WMS前置任务是否启动
    if operation_info.pre_wmstask ~= "" then
        -- 获取WMS前置任务信息
        nRet, wms_task = m3.GetDataObjByCondition(strLuaDEID, "Operation",
            "S_WMS_TASK = '" .. operation_info.pre_wmstask .. "'", "T_CREATE DESC")
        if (nRet == 2) then
            lua.Stop(strLuaDEID,
                "作业" .. operation_info.code .. "启动获取前置任务信息失败,原因: " .. wms_task)
            return
        end

        -- 如果前置任务未开始执行 使用wfp事件 直接启动前置任务
        if wms_task.b_state == 0 then
            local parameter = {
                op_code = wms_task.code
            }
            -- 增加后台脚本处理
            nRet, strRetInfo = mobox.addBackendScriptProc("Operation", "前置任务优先启动",
                lua.table2str(parameter))
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "作业启动,添加wfp启动前置任务失败" .. strRetInfo)
                return
            end
            return
        end

        if wms_task.b_state == 1 then
            lua.DebugEx(strLuaDEID,
                "当前作业" .. operation_info.code .. "前置任务执行中未完成,暂停启动", operation_info)
            return
        end
    end
    local start_loc_info, strCondition, task_type, ddj_end_loc
    -- -- 查询起点货位巷道
    strCondition = "S_CODE = '" .. operation_info.start_loc_code .. "'"
    nRet, start_loc_info = m3.GetDataObjByCondition(strLuaDEID, "Location", strCondition, "T_CREATE DESC")
    if (nRet ~= 0) then
        lua.Stop(strLuaDEID, "查询起点货位信息失败" .. start_loc_info)
        return
    end

    if start_loc_info.aisle == 1 then
        task_type = 202 -- 1号堆垛机出库搬运
    else
        task_type = 205 -- 2号堆垛机出库搬运
    end

    -- 库前
    if operation_info.end_loc_code == "1002" or operation_info.end_loc_code == "1003" then
        ddj_end_loc = "1004"
    elseif operation_info.end_loc_code == "1009" then
        ddj_end_loc = "1010"
        -- 库后
    elseif operation_info.end_loc_code == "1016" or operation_info.end_loc_code == "1019" or operation_info.end_loc_code ==
        "1022" or operation_info.end_loc_code == "1015" then
        if operation_info.start_aisle == 1 then
            ddj_end_loc = "1011"
        end
        if operation_info.start_aisle == 2 then
            ddj_end_loc = "1017"
        end
    end

    if operation_info.end_loc_code == "1015" then

        if start_loc_info.aisle == 1 then
            ddj_end_loc = "1011"
            task_type = 202 -- 1号堆垛机出库搬运
        elseif operation_info.aisle == 2 then
            ddj_end_loc = "1017"
            task_type = 205 -- 2号堆垛机出库搬运
        end
    end

    -- 创建堆垛机任务
    local task = m3.AllocObject(strLuaDEID, "Task")
    task.op_code = operation_info.code -- 作业编码
    task.op_name = operation_info.op_def_name -- 作业名称
    task.factory = operation_info.factory -- 工厂
    task.cntr_code = operation_info.cntr_code

    -- 起点
    task.start_wh_code = operation_info.start_wh_code
    task.start_area_code = operation_info.start_area_code
    task.start_loc_code = operation_info.start_loc_code

    -- 终点
    task.end_wh_code = operation_info.end_wh_code
    task.end_area_code = operation_info.end_area_code
    task.end_loc_code = ddj_end_loc

    task.wms_loc = operation_info.wms_loc
    -- task.start_aisle = operation_info.start_aisle

    task.type = task_type -- 任务类型 
    task.schedule_type = wms_base.Get_nConst(strLuaDEID, "调度类型-堆垛机") -- 设置调度类型 -- 调度类型 堆垛机
    task.priority = operation_info.priority -- 优先级
    task.wms_task = operation_info.wms_task -- WMS任务号
    task.pre_wmstask = operation_info.pre_wmstask -- 前置任务号

    -- 创建任务
    nRet, task = m3.CreateDataObj(strLuaDEID, task)
    if (nRet ~= 0) then
        lua.Stop(strLuaDEID, "创建堆垛机任务失败" .. task)
        return
    end
end
