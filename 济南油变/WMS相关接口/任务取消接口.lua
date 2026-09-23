m3 = require("oi_base_mobox")
lua = require("oi_base_func")
json = require("json")
wms_eq = require("wms_equipment")
hc_plc = require("hcplc_base")

function CancleTask(strLuaDEID)
    local nRet, strRetInfo, cancle_op, strErr, op_info, taskisbegining, updateOp, updateTask

    -- 获取接口中的Data
    nRet, cancle_op = m3.GetSysDataJson(strLuaDEID)
    if (nRet ~= 0) then
        local result = {
            msg = "WCS获取WMS接口信息失败,原因:" .. cancle_op,
            code = -1,
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    end

    lua.DebugEx(strLuaDEID, "002作业取消接口接收到的数据", cancle_op)
    local wms_task = cancle_op.taskNo -- WMS任务号

    -- 根据WMS任务号查询作业信息
    local strCondition = "S_WMS_TASK = '" .. wms_task .. "'"
    nRet, op_info = m3.GetDataObjByCondition(strLuaDEID, "Operation", strCondition, "T_CREATE DESC")
    if (nRet ~= 0) then
        local result = {
            msg = "WCS获取WMS任务信息失败,原因:" .. op_info,
            code = -1,
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    end

    if (op_info.b_state == 2) then
        local result = {
            msg = "任务已完成，无法取消",
            code = -1,
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    end

    if (op_info.s_type == "入库") then
        local result = {
            msg = "任务取消失败，入库任务不允许取消",
            code = -1,
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    else
        -- 根据WMS任务号查询作业信息
        local strCondition = "S_WMS_TASK = '" .. wms_task .. "' AND N_SCHEDULE_TYPE = 5"
        nRet, task_info = m3.GetDataObjByCondition(strLuaDEID, "Task", strCondition, "T_CREATE DESC")
        if (nRet ~= 0) then
            local result = {
                msg = "WCS获取WMS任务信息失败,原因:" .. task_info,
                code = -1,
                data = {}
            }
            mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
            return
        end
        if task_info.b_state == 1 then
            local result = {
                msg = "任务取消失败,原因:wcs已推送任务至堆垛机，无法取消任务",
                code = -1,
                data = {}
            }
            mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
            return
        end

        if task_info.b_state == 3 then
            if op_info.b_state ~= 2 then
                local result = {
                    msg = "任务取消失败,原因:设备正在执行，无法取消任务",
                    code = -1,
                    data = {}
                }
                mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
                return
            end
        end
    end

    -- 更新作业状态为取消
    nRet, updateOp = mobox.updateDataAttrByCondition(strLuaDEID, "Operation", "S_CODE = '" .. op_info.code .. "'",
        "S_B_STATE = '取消',N_B_STATE = 7")
    if (nRet ~= 0) then
        lua.DebugEx(strLuaDEID, "002作业取消,取消作业:" .. op_info.code .. "失败,原因:", updateOp)
        local result = {
            msg = "任务取消失败,原因:WCS取消任务失败" .. updateOp,
            code = -1,
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    end

    -- 更新任务状态为取消
    nRet, updateTask = mobox.updateDataAttrByCondition(strLuaDEID, "Task", "S_OP_CODE = '" .. op_info.code .. "'",
        "S_B_STATE = '取消',N_B_STATE = 5")
    if (nRet ~= 0) then
        lua.DebugEx(strLuaDEID, "002作业取消,取消作业:" .. op_info.code .. "的任务失败,原因:", updateTask)
        local result = {
            msg = "任务取消失败,原因:WCS取消子任务失败" .. updateTask,
            code = -1,
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    end

    local result = {
        msg = "任务取消成功!",
        code = 0,
        data = {}
    }
    mobox.returnValue(strLuaDEID, 1, lua.table2str(result))

end
