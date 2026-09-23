wms_base = require("wms_base")
json = require("json")
mobox = require("OILua_JavelinExt")
m3 = require("oi_base_mobox")
hc_plc = require("hcplc_base")
wms = require("OILua_WMS")

-- 料箱出库作业启动
function OperationStart(strLuaDEID)

    local nRet, isExist_priwait, operation_info, wms_task, strRetInfo, end_loc_info, ssx_end_loc, task_type

    nRet, operation_info = m3.GetSysCurEditDataObj(strLuaDEID, "Operation")
    if (nRet ~= 0) then
        lua.Stop(strLuaDEID, "库后入库作业启动-》获取待启动作业失败! " .. operation_info)
        return
    end
    lua.DebugEx(strLuaDEID, "开始启动作业", operation_info)

    -- 查询作业终点信息
    -- local strCondition = "S_CODE = '" .. operation_info.end_loc_code .. "'"
    -- nRet, end_loc_info = m3.GetDataObjByCondition(strLuaDEID, "Location", strCondition, "T_CREATE DESC")
    -- if (nRet ~= 0) then
    --     lua.Stop(strLuaDEID, "库后入库作业启动-》获取终点货位信息失败! " .. end_loc_info)
    --     return
    -- end

    -- if end_loc_info.aisle == 1 then
    --     task_type = 201
    -- elseif end_loc_info.aisle == 2 then
    --     task_type = 204
    -- end
    -- 根据起点区分单深/双深料箱库入库

    if operation_info.start_loc_code == 1006 or operation_info.start_loc_code == 108 then -- 单深
        task_type = 210
    elseif operation_info.start_loc_code == 102 or operation_info.start_loc_code == 104 then -- 单深
        task_type = 213
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
    task.end_loc_code = operation_info.end_loc_code

    task.type = task_type
    task.schedule_type = 5
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
