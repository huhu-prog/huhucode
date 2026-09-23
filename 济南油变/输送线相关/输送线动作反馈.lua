m3 = require("oi_base_mobox")
lua = require("oi_base_func")
json = require("json")
mobox = require("OILua_JavelinExt")
wms_base = require("wms_base")
wms_cntr = require("wms_container")
hc_plc = require("hcplc_base")
xcwms_base = require("xcwms_base")
function YBPLCStatusChange(strLuaDEID)
    local nRet, strRetInfo, ret_info
    local input_datajson
    local device_code, unit_code, value, task_info, condition_flag, isexit, inter_code
    nRet, input_datajson = m3.GetSysDataJson(strLuaDEID)
    if (nRet ~= 0) then
        lua.Stop(strLuaDEID, "PLCStateChange无法获取数据包!" .. input_datajson)
        return 1
    end
    device_code = lua.Get_StrAttrValue(input_datajson.device_code)
    unit_code = lua.Get_StrAttrValue(input_datajson.unit_code)
    inter_code = lua.Get_StrAttrValue(input_datajson.inter_code)
    value = input_datajson.value[1]
    if (value == 2) then
        if unit_code == "1022" or unit_code == "1019" then
            local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH", unit_code .. "-SENT_WRITE",
                {1})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                return
            end
        end
        if unit_code == "1005" or unit_code == "1007" then
            if unit_code == "1005" then
                target = "1006"
            else
                target = "1008"
            end
            local nRet, returnvalue =
                hc_plc.WriteS7PLCCommsData(strLuaDEID, "XDXC_SSX", unit_code .. "-SENT_WRITE", {1})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                return
            end
            local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XDXC_SSX", target .. "-TARGET_ADD_WRITE",
                {0})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "写输送线终点失败! " .. returnvalue)
                return
            end
        end
    end

    if (value == 0) then
        if (unit_code == "1002" or unit_code == "1005" or unit_code == "1007") then
            local nRet, sent_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XDXC_SSX", {unit_code .. "-SENT_WRITE"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. sent_value)
                return
            end
            local sent_w = sent_value[1].value[1]
            if sent_w == 1 then
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XDXC_SSX", unit_code .. "-SENT_WRITE",
                    {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "SENT复位成功", os.date("%Y-%m-%d %H:%M:%S"))
            end
        end

        if (unit_code == "1006" or unit_code == "1008") then -- 库前入库口
            local nRet, sent_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XDXC_SSX", {unit_code .. "-SENT_WRITE"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. sent_value)
                return
            end
            local sent_w = sent_value[1].value[1]
            if sent_w == 1 then
                lua.DebugEx(strLuaDEID, "读到" .. unit_code .. "需复位信号，开始复位", 1)
                -- local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XDXC_SSX",
                --     unit_code .. "-TARGET_ADD_WRITE", {0})
                -- if (nRet ~= 0) then
                --     lua.Stop(strLuaDEID, "写输送线终点失败! " .. returnvalue)
                --     return
                -- end
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XDXC_SSX", unit_code .. "-SENT_WRITE",
                    {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                    return
                end
                -- lua.DebugEx(strLuaDEID, unit_code .. "目的地已复位", 0)
                lua.DebugEx(strLuaDEID, unit_code .. "sent_w已复位", 0)
            end
        end

        if (unit_code == "1004" or unit_code == "1010") then -- 库前堆垛机出库放货口
            local nRet, sent_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XDXC_SSX", {unit_code .. "-SENT_WRITE"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. sent_value)
                return
            end
            local sent_w = sent_value[1].value[1]
            if sent_w == 1 then
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XDXC_SSX", unit_code .. "-SENT_WRITE",
                    {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "SENT复位成功", os.date("%Y-%m-%d %H:%M:%S"))
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XDXC_SSX",
                    unit_code .. "-CNTR_CODE_WRITE", "0")
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写托盘号失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "托盘号复位成功", os.date("%Y-%m-%d %H:%M:%S"))
                if unit_code == "1004" then
                    local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XDXC_SSX",
                        unit_code .. "-TARGET_ADD_WRITE", {0})
                    if (nRet ~= 0) then
                        lua.Stop(strLuaDEID, "写输送线终点失败! " .. returnvalue)
                        return
                    end
                    lua.DebugEx(strLuaDEID, "" .. unit_code .. "目标机台号复位成功",
                        os.date("%Y-%m-%d %H:%M:%S"))
                end
            end
        end

        if (unit_code == "1003" or unit_code == "1009") then -- 库前出库agv取货口
            local nRet, sent_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XDXC_SSX", {unit_code .. "-SENT_WRITE"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. sent_value)
                return
            end
            local sent_w = sent_value[1].value[1]
            if sent_w == 1 then
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XDXC_SSX", unit_code .. "-SENT_WRITE",
                    {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "SENT复位成功", os.date("%Y-%m-%d %H:%M:%S"))
            end
        end

        if (unit_code == "1011" or unit_code == "1017") then -- 库后堆垛机放货口
            local nRet, sent_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH", {unit_code .. "-SENT_WRITE"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. sent_value)
                return
            end
            local sent_w = sent_value[1].value[1]
            if sent_w == 1 then
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-CNTR_CODE_WRITE", "0")
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写托盘号失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "托盘码复位成功", os.date("%Y-%m-%d %H:%M:%S"))
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-SENT_WRITE", {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "SENT复位成功", os.date("%Y-%m-%d %H:%M:%S"))
            end
        end

        if (unit_code == "1012" or unit_code == "1018") then -- 库后RGV出库口
            local nRet, sent_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH", {unit_code .. "-SENT_WRITE"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. sent_value)
                return
            end
            local sent_w = sent_value[1].value[1]
            if sent_w == 1 then
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-TARGET_ADD_WRITE", {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写输送线终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "目标机台号复位成功", os.date("%Y-%m-%d %H:%M:%S"))
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-SENT_WRITE", {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "SENT复位成功", os.date("%Y-%m-%d %H:%M:%S"))
            end
        end

        if (unit_code == "1016" or unit_code == "1019" or unit_code == "1022") then -- 库后线体出库agv接驳口
            local nRet, sent_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH", {unit_code .. "-SENT_WRITE"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. sent_value)
                return
            end
            local sent_w = sent_value[1].value[1]
            if unit_code == "1016" then
                local nRet, return_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    {unit_code .. "-CNTR_RETURN_WRITE"})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. sent_value)
                    return
                end
                local return_w = return_value[1].value[1]
                if return_w == 1 then
                    local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                        unit_code .. "-CNTR_RETURN_WRITE", {0})
                    if (nRet ~= 0) then
                        lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                        return
                    end
                    lua.DebugEx(strLuaDEID, "" .. unit_code .. "CNTR_RETURN_WRITE复位成功",
                        os.date("%Y-%m-%d %H:%M:%S"))
                end
            end
            if sent_w == 1 then
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-SENT_WRITE", {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "SENT复位成功", os.date("%Y-%m-%d %H:%M:%S"))
            end
        end

        if (unit_code == "1022") then -- 库后线体出库agv接驳口
            local nRet, sent_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH", {unit_code .. "-SENT_WRITE"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. sent_value)
                return
            end
            local sent_w = sent_value[1].value[1]
            local nRet, apply_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                {unit_code .. "-APPLY_CNTR_WRITE"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. sent_value)
                return
            end
            local apply_w = apply_value[1].value[1]
            if sent_w == 1 then
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-SENT_WRITE", {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "SENT复位成功", os.date("%Y-%m-%d %H:%M:%S"))
            end
            if apply_w == 1 then
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-APPLY_CNTR_WRITE", {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "APPLY_CNTR复位成功", os.date("%Y-%m-%d %H:%M:%S"))
            end
        end

        if (unit_code == "1025" or unit_code == "1026") then -- 库后线体回库口
            local nRet, sent_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH", {unit_code .. "-SENT_WRITE"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. sent_value)
                return
            end
            local sent_w = sent_value[1].value[1]
            if sent_w == 1 then
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-TARGET_ADD_WRITE", {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写输送线终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "目标机台号复位成功", os.date("%Y-%m-%d %H:%M:%S"))
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-SENT_WRITE", {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "SENT复位成功", os.date("%Y-%m-%d %H:%M:%S"))
            end
        end

        if (unit_code == "1013" or unit_code == "1020") then -- 库后堆垛机入库口
            local nRet, sent_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH", {unit_code .. "-SENT_WRITE"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. sent_value)
                return
            end
            local sent_w = sent_value[1].value[1]
            if sent_w == 1 then
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-SENT_WRITE", {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "SENT复位成功", os.date("%Y-%m-%d %H:%M:%S"))
            end
        end

        if (unit_code == "1015") then -- 库后堆垛机入库口
            local nRet, sent_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH", {unit_code .. "-SENT_WRITE"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. sent_value)
                return
            end
            local sent_w = sent_value[1].value[1]
            if sent_w == 1 then
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-SENT_WRITE", {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "SENT复位成功", os.date("%Y-%m-%d %H:%M:%S"))
            end
        end
    end

    if value == 1 then
        local newtime
        local sqlCondition = "S_EQ_CODE = '" .. unit_code .. "'"
        -- 查询当前分支点最新的创建时间
        nRet, newtime = m3.GetDataObjByCondition(strLuaDEID, "MQ_EQAction", sqlCondition, "T_CREATE DESC")
        if (nRet == 2) then
            lua.Stop(strLuaDEID, "获取动作队列失败! " .. newtime)
            return
        elseif (nRet == 0) then
            local new_time = newtime.current_time
            local currenttimestamp = os.time()
            local diff = currenttimestamp - new_time

            if (diff < 3) then
                lua.DebugEx(strLuaDEID, "时间小于3秒,已退出", diff)
                return
            end
        end

        -- 库前入库口
        if (unit_code == "1006" or unit_code == "108" or unit_code == "102" or unit_code == "104") then
            local target
            if (unit_code == "106") then
                target = 105
            elseif (unit_code == "108") then
                target = 107
            elseif (unit_code == "102") then
                target = 101
            elseif (unit_code == "104") then
                target = 103
            end

            local nRet, cntr_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XDXC_SSX", {unit_code .. "-CNTR_CODE_READ"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. cntr_info)
                return
            end
            local cntr_code = cntr_info[1].value
            lua.DebugEx(strLuaDEID, unit_code .. "读到的托盘码", cntr_code)
            -- 读取重量信息
            local nRet, weight_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XDXC_SSX", {unit_code .. "-WEIGHT_READ"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. nRet)
                return
            end
            local weight = weight_info[1].value
            lua.DebugEx(strLuaDEID, unit_code .. "读到的重量", weight)

            -- 读取托盘高度
            local nRet, height_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XDXC_SSX", {unit_code .. "-HEIGHT_READ"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. nRet)
                return
            end
            local height = height_info[1].value[1]
            lua.DebugEx(strLuaDEID, unit_code .. "读到的托盘高度", height)

            local cntrop_info
            local strCondition = "S_CNTR_CODE = '" .. cntr_code .. "'  AND S_START_LOC = '" .. unit_code ..
                                     "' AND N_B_STATE IN (0,1) "
            lua.DebugEx(strLuaDEID, unit_code .. "strCondition", strCondition)
            nRet, cntrop_info = m3.GetDataObjByCondition(strLuaDEID, "Operation", strCondition, "T_CREATE DESC")
            if (nRet == 2) then
                lua.Stop(strLuaDEID,
                    "GetDataObjByCondition获取托盘" .. cntr_code .. "作业信息失败" .. cntrop_info)
                return
            end
            if nRet == 1 then -- nRet = 1:当前无作业
                local wms_loc
                if unit_code == "106" then
                    wms_loc = "Z01XRK01"
                elseif unit_code == "108" then
                    wms_loc = "Z01XRK02"
                elseif unit_code == "102" then
                    wms_loc = "Z01XRK03"
                elseif unit_code == "104" then
                    wms_loc = "Z01XRK04"
                end
                local rkcanshu = {
                    reqId = "req" .. os.date("%Y%m%d%H%M%S"),
                    reqTime = os.date("%Y-%m-%d %H:%M:%S"),
                    loc = wms_loc,
                    cntrNo = cntr_code,
                    signalType = 3,
                    deviceNo = unit_code,
                    cntrType = 1,
                    qty = "8",
                    wareHouseCode = 'XCH01HYZHZ01',
                    extData = {{
                        ShapeCheckResult = 1,
                        Height = height,
                        Weight = tonumber(weight)
                    }}
                }
                local strHeader = ""
                local strBody = lua.table2str(rkcanshu)
                -- local strurl = "http://10.124.5.142:8080/xicai-boot/xicai/stacker/notifyDeviceSignal"
                local strurl = "http://192.168.1.106:5103/api/pei/callext/TEST/TEST?UsingCustomFmt=1"
                lua.DebugEx(strLuaDEID, "005接口申请入库作业 调用wms前参数", strBody)
                nRet, strRetInfo = mobox.sendHttpRequest(strurl, strHeader, strBody)
                lua.Debug(strLuaDEID, debug.getinfo(1), "005接口调用后返回原始信息:", strRetInfo)
                if (nRet ~= 0) then
                    lua.Error(strLuaDEID, debug.getinfo(1), "005接口调用失败! 原因:" .. strRetInfo)
                else
                    local retAttrs = json.decode(strRetInfo)
                    lua.Debug(strLuaDEID, debug.getinfo(1), "005接口调用后返回解析后信息:", retAttrs)
                    if (retAttrs["code"] == 0) then
                        local operation = m3.AllocObject(strLuaDEID, 'Operation')
                        operation.op_def_code = "OP074"
                        operation.op_type = 1 -- 1 入库 2 出库 3 移库
                        operation.op_def_name = "库前入库"
                        operation.b_state = 0
                        operation.cntr_code = retAttrs.data[1].cntrNo
                        operation.start_wh_code = "XDCK"
                        operation.start_area_code = "XDKQ"
                        operation.start_loc_code = unit_code
                        operation.end_wh_code = "XDCK"
                        operation.end_area_code = "XDKQ"
                        operation.end_loc_code = retAttrs.data[1].to
                        operation.factory = "YRGC"
                        operation.wms_task = retAttrs.data[1].taskNo -- 上游wms任务号
                        operation.wms_loc = wms_loc
                        operation.priority = retAttrs.data[1].priority -- 优先级
                        operation.pre_wmstask = retAttrs.data[1].proTaskNo -- 前置任务号
                        lua.DebugEx(strLuaDEID, "作业创建前", operation)
                        nRet, strRetInfo = m3.CreateDataObj(strLuaDEID, operation)
                        if (nRet ~= 0) then
                            lua.Stop(strLuaDEID, "创建入库作业失败" .. strRetInfo)
                            return
                        end
                    else
                        -- 回复sent1,写目的地 当前位置
                        local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XDXC_SSX",
                            unit_code .. "-TARGET_ADD_WRITE", {tonumber(target)})
                        if (nRet ~= 0) then
                            lua.Stop(strLuaDEID, "写输送线终点失败! " .. returnvalue)
                            return
                        end
                        lua.DebugEx(strLuaDEID, unit_code .. "申请wms任务异常 给输送线写终点回上料口",
                            cntr_code)
                        local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XDXC_SSX",
                            unit_code .. "-SENT_WRITE", {1})
                        if (nRet ~= 0) then
                            lua.Stop(strLuaDEID, "写SENT = 1失败! " .. returnvalue)
                            return
                        end
                    end
                end
            elseif (nRet == 0) then
                lua.DebugEx(strLuaDEID, "已有作业，创建动作队列", os.date("%Y-%m-%d %H:%M:%S"))
                -- 如果是出库作业
                if cntrop_info.op_def_name == "库前出库" then
                        -- 查询 当前起点的输送线任务
                    local strCondition = "S_START_LOC = '" .. unit_code .. "' AND N_B_STATE IN (0,1)"
                    lua.DebugEx(strLuaDEID, "strCondition", strCondition)
                    nRet, query_task = m3.GetDataObjByCondition(strLuaDEID, "Task", strCondition, "T_CREATE DESC")
                    if (nRet == 2) then
                        lua.Stop(strLuaDEID, "查询任务信息失败! " .. query_task)
                        return
                    end
                    lua.DebugEx(strLuaDEID, "query_task", query_task)
                    if (nRet == 1) then
                        lua.Stop(strLuaDEID, "无以当前线体起点的线体任务! " .. query_task)
                        return
                    end
                    local task_no = query_task.code
                    local strCondition = "S_EQ_CODE = '" .. unit_code .. "' AND S_TASK_CODE = '" .. task_no .. "'"
                    nRet, isexit = mobox.existThisData(strLuaDEID, "MQ_EQAction", strCondition)
                    if (nRet ~= 0) then
                        lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                        return
                    end
                    if (isexit == 'yes') then
                        return
                    end
                    xcwms_base.CreatMqEqaction(strLuaDEID, query_task.op_code, unit_code, 7, "库前堆垛机出库放货口",
                        query_task.cntr_code, 4, task_no, 0)
                else
                    local strCondition = "S_EQ_CODE = '" .. unit_code .. "' AND S_OP_CODE = '" .. cntrop_info.code .. "'" -- AND N_B_STATE != 1
                    nRet, isexit = mobox.existThisData(strLuaDEID, "MQ_EQAction", strCondition)
                    if (nRet ~= 0) then
                        lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                        return
                    end
                    if (isexit == 'yes') then
                        return
                    end
                    xcwms_base.CreatMqEqaction(strLuaDEID, cntrop_info.code, unit_code, 1, "库前入库口", cntr_code, 4,
                        "", 0)
                end
            end
        end

        -- 1010、1004库前出库口
        if (unit_code == "1010" or unit_code == "1004") then
            lua.DebugEx(strLuaDEID, unit_code, unit_code)
            local query_task
            -- 查询 当前起点的输送线任务
            local strCondition = "S_START_LOC = '" .. unit_code .. "' AND N_B_STATE IN (0,1)"
            lua.DebugEx(strLuaDEID, "strCondition", strCondition)
            nRet, query_task = m3.GetDataObjByCondition(strLuaDEID, "Task", strCondition, "T_CREATE DESC")
            if (nRet == 2) then
                lua.Stop(strLuaDEID, "查询任务信息失败! " .. query_task)
                return
            end
            lua.DebugEx(strLuaDEID, "query_task", query_task)
            if (nRet == 1) then
                lua.Stop(strLuaDEID, "无以当前线体起点的线体任务! " .. query_task)
                return
            end
            local task_no = query_task.code
            local strCondition = "S_EQ_CODE = '" .. unit_code .. "' AND S_TASK_CODE = '" .. task_no .. "'"
            nRet, isexit = mobox.existThisData(strLuaDEID, "MQ_EQAction", strCondition)
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                return
            end
            if (isexit == 'yes') then
                return
            end
            xcwms_base.CreatMqEqaction(strLuaDEID, query_task.op_code, unit_code, 7, "库前堆垛机出库放货口",
                query_task.cntr_code, 4, task_no, 0)
        end

        -- 1002 库前拆码盘机
        if (unit_code == "1002") then
            -- 托盘垛出库至码盘机
            if inter_code == "SENT_READ" then
                lua.DebugEx(strLuaDEID, unit_code .. "开始读托盘码", os.date("%Y-%m-%d %H:%M:%S"))
                -- 读取线体托盘号
                local nRet, cntr_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XDXC_SSX",
                    {unit_code .. "-CNTR_CODE_READ"})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. cntr_info)
                    return
                end
                local cntr_code = cntr_info[1].value
                lua.DebugEx(strLuaDEID, unit_code .. "读到的托盘码", cntr_code)
                local query_task
                -- 查询 当前终点的输送线任务
                local strCondition = "S_END_LOC = '" .. unit_code .. "' AND S_CNTR_CODE = '" .. cntr_code ..
                                         "' AND N_B_STATE = 1 AND N_SCHEDULE_TYPE = 4"

                lua.DebugEx(strLuaDEID, unit_code .. "strCondition", strCondition)
                nRet, query_task = m3.GetDataObjByCondition(strLuaDEID, "Task", strCondition, "T_CREATE DESC")
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "无以当前线体为终点的线体任务! " .. query_task)
                    return
                end
                local task_no = query_task.code
                local strCondition = "S_EQ_CODE = '" .. unit_code .. "' AND S_TASK_CODE = '" .. task_no .. "'"
                nRet, isexit = mobox.existThisData(strLuaDEID, "MQ_EQAction", strCondition)
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                    return
                end
                if (isexit == 'yes') then
                    return
                end
                xcwms_base.CreatMqEqaction(strLuaDEID, query_task.op_code, unit_code, 7, "库前码盘成功",
                    query_task.cntr_code, 4, task_no, 0)
            end
            -- 库前叫呼叫空托
            if (inter_code == "STATUS_READ") then
                local query_op, task_no
                lua.DebugEx(strLuaDEID, "读到1002的拆叠盘机状态为空框：", 1)
                -- 查询当前有无以1002为终点的 状态为=0 /=1 的空托垛出库作业
                local strCondition = "S_END_LOC = '" .. unit_code .. "' AND N_B_STATE IN (0,1)"
                nRet, query_op = m3.GetDataObjByCondition(strLuaDEID, "Operation", strCondition, "T_CREATE DESC")
                if (nRet == 2) then
                    lua.Stop(strLuaDEID, "查询作业信息失败! " .. query_op)
                    return
                end
                -- 无作业，向wms申请
                if (nRet == 1) then
                    nRet, task_no = xcwms_base.applyforEmptycntr(strLuaDEID, "Z01XDP01", "1002")
                    if nRet ~= 0 then
                        lua.Stop(strLuaDEID, "调用wms接口申请空托垛出库作业失败! " .. task_no)
                        return
                    end

                    lua.DebugEx(strLuaDEID, "调用wms下发的空托垛op_info", task_no)
                end
            end
        end

        -- 1003、1009 库前出库agv取货口
        if (unit_code == "1003" or unit_code == "1009") then
            local query_task
            local nRet, cntr_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XDXC_SSX", {unit_code .. "-CNTR_CODE_READ"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. nRet)
                return
            end
            local cntr_code = cntr_info[1].value
            lua.DebugEx(strLuaDEID, unit_code .. "读到的托盘码", cntr_code)
            -- 查询当前托盘的输送线任务
            local strCondition = "S_CNTR_CODE = '" .. cntr_code .. "' AND N_B_STATE IN (0,1) AND N_SCHEDULE_TYPE = 4"
            nRet, query_task = m3.GetDataObjByCondition(strLuaDEID, "Task", strCondition, "T_CREATE DESC")
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "查询任务信息失败! " .. query_task)
                return
            end
            local task_no = query_task.code
            local strCondition = "S_EQ_CODE = '" .. unit_code .. "' AND S_TASK_CODE = '" .. task_no .. "'"
            nRet, isexit = mobox.existThisData(strLuaDEID, "MQ_EQAction", strCondition)
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                return
            end
            if (isexit == 'yes') then
                return
            end
            xcwms_base.CreatMqEqaction(strLuaDEID, query_task.op_code, unit_code, 7, "库前出库AGV取货口",
                cntr_code, 4, task_no, 0)
        end

        -- 1011、1017 库后堆垛机出库放货口
        if (unit_code == "1011" or unit_code == "1017") then
            local query_task
            -- 查询 当前起点的输送线任务
            local strCondition = "S_START_LOC = '" .. unit_code .. "' AND N_B_STATE = 1"
            nRet, query_task = m3.GetDataObjByCondition(strLuaDEID, "Task", strCondition, "T_CREATE DESC")
            if (nRet == 2) then
                lua.Stop(strLuaDEID, "查询任务信息失败! " .. query_task)
                return
            end
            local task_no = query_task.code
            local strCondition = "S_EQ_CODE = '" .. unit_code .. "' AND S_TASK_CODE = '" .. task_no .. "'"
            nRet, isexit = mobox.existThisData(strLuaDEID, "MQ_EQAction", strCondition)
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                return
            end
            if (isexit == 'yes') then
                lua.DebugEx(strLuaDEID, "isexit", isexit)
                return 0
            end
            xcwms_base.CreatMqEqaction(strLuaDEID, query_task.op_code, unit_code, 7, "出库接驳口",
                query_task.cntr_code, 4, task_no, 0)
        end

        -- 1012、1018 库后RGV出库接驳口
        if (unit_code == "1012" or unit_code == "1018") then
            local query_task
            local nRet, cntr_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH", {unit_code .. "-CNTR_CODE_READ"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. nRet)
                return
            end
            local cntr_code = cntr_info[1].value
            lua.DebugEx(strLuaDEID, unit_code .. "读到的托盘码", cntr_code)

            -- 查询当前托盘的输送线任务
            local strCondition = "S_CNTR_CODE = '" .. cntr_code .. "' AND N_B_STATE IN (1,2,3) AND N_SCHEDULE_TYPE = 4"
            nRet, query_task = m3.GetDataObjByCondition(strLuaDEID, "Task", strCondition, "T_CREATE DESC")
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "查询任务信息失败! " .. query_task)
                return
            end
            local task_no = query_task.code
            local strCondition = "S_EQ_CODE = '" .. unit_code .. "' AND S_TASK_CODE = '" .. task_no .. "'"
            nRet, isexit = mobox.existThisData(strLuaDEID, "MQ_EQAction", strCondition)
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                return
            end
            if (isexit == 'yes') then
                return
            end
            xcwms_base.CreatMqEqaction(strLuaDEID, query_task.op_code, unit_code, 7, "库后出库RGV取货口",
                cntr_code, 4, task_no, 0)
        end

        -- 1019、1022、1016 库后线体出库agv接驳口
        if (unit_code == "1019" or unit_code == "1022" or unit_code == "1016") then
            if inter_code == "SENT_READ" then -- 出库到位上报
                local query_task
                local nRet, cntr_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    {unit_code .. "-CNTR_CODE_READ"})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. nRet)
                    return
                end
                local cntr_code = cntr_info[1].value
                lua.DebugEx(strLuaDEID, unit_code .. "读到的托盘码", cntr_code)
                -- 查询当前托盘的RGV任务
                local strCondition = "S_CNTR_CODE = '" .. cntr_code .. "' AND N_B_STATE = 1 AND N_SCHEDULE_TYPE = 9"
                nRet, query_task = m3.GetDataObjByCondition(strLuaDEID, "Task", strCondition, "T_CREATE DESC")
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "查询任务信息失败! " .. query_task)
                    return
                end
                local task_no = query_task.code
                local strCondition = "S_EQ_CODE = '" .. unit_code .. "' AND S_TASK_CODE = '" .. task_no .. "'"
                nRet, isexit = mobox.existThisData(strLuaDEID, "MQ_EQAction", strCondition)
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                    return
                end
                if (isexit == 'yes') then
                    return
                end
                xcwms_base.CreatMqEqaction(strLuaDEID, query_task.op_code, unit_code, 7, "库后出库AGV取货口",
                    cntr_code, 9, task_no, 0)
            end

            -- 叫空托申请
            if inter_code == "APPLY_CNTR_READ" then
                local strCondition = "S_END_LOC = '1015' AND N_B_STATE IN (0,1)"
                nRet, isexit = mobox.existThisData(strLuaDEID, "Operation", strCondition)
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                    return
                end
                lua.DebugEx(strLuaDEID, "触发叫空托垛信号,开始处理", 1)
                if (isexit == 'yes') then
                    -- sent置1
                    local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                        "1022-APPLY_CNTR_WRITE", {1})
                    if (nRet ~= 0) then
                        lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                        return
                    end
                    lua.DebugEx(strLuaDEID,
                        "触发叫空托垛信号,当前有出空托垛任务,疑似误触已复位", returnvalue)
                    return
                end
                if (isexit == 'no') then
                    local op_info -- wms申请空托垛出库
                    lua.DebugEx(strLuaDEID, "向wms申请出空垛", 1)
                    nRet, op_info = xcwms_base.applyforEmptycntr(strLuaDEID, "Z01DDP01", "1015")
                    lua.DebugEx(strLuaDEID, "调用wms下发的空托垛op_info", op_info)
                    -- 动作队列仅做记录
                    xcwms_base.CreatMqEqaction(strLuaDEID, op_info.code, unit_code, 8,
                        "库后拆叠盘机呼叫空托垛", op_info.cntr_code, 4, "", 1)
                    -- sent置1
                    local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                        "1022-APPLY_CNTR_WRITE", {1})
                    if (nRet ~= 0) then
                        lua.Stop(strLuaDEID, "写SENT终点失败! " .. returnvalue)
                        return
                    end
                    lua.DebugEx(strLuaDEID, "触发叫空托垛信号,已下发任务,已回复", returnvalue)
                    return
                end
            end
            -- 空托回库
            if inter_code == "CNTR_RETURN_READ" then
                local op_info
                -- 读取线体托盘号
                local nRet, cntr_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    {unit_code .. "-CNTR_CODE_READ"})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. cntr_info)
                    return
                end
                local cntr_code = cntr_info[1].value
                lua.DebugEx(strLuaDEID, unit_code .. "读到的托盘码", cntr_code)
                local strCondition = "S_START_LOC = '" .. unit_code .. "' AND S_CNTR_CODE = '" .. cntr_code ..
                                         "' AND N_B_STATE IN (0,1) "
                nRet, isexit = mobox.existThisData(strLuaDEID, "Task", strCondition)
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                    return
                end
                if (isexit == 'yes') then
                    return
                end
                -- 读当前拆叠盘机是否满料
                local nRet, cdp_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH", {"1015-STATUS_READ"})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. cntr_info)
                    return
                end
                local cdp_status = cdp_value[1].value[1]
                lua.DebugEx(strLuaDEID, unit_code .. "空托入拆叠盘,读到的拆叠盘当前状态", cdp_status)
                -- 如果满料
                if cdp_status ~= 3 then
                    if cdp_status == 2 then
                        -- 读取当前拆叠盘机托盘号
                        local nRet, cntr_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                            {"1015-CNTR_CODE_READ"})
                        if (nRet ~= 0) then
                            lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. cntr_info)
                            return
                        end
                        local cdp_cntr_code = cntr_info[1].value
                        lua.DebugEx(strLuaDEID, unit_code .. "读到的托盘码", cdp_cntr_code)
                        -- 调用wms接口 下发满托垛入库
                        nRet, op_info = xcwms_base.FullCntrInbound(strLuaDEID, "Z01DDP01", cdp_cntr_code, "1015")
                        if nRet ~= 0 then
                            lua.Stop(strLuaDEID, "调用WMS接口创建满托垛入库作业失败" .. op_info)
                            return
                        end
                        -- 创建RGV任务
                        nRet, task_info = xcwms_base.EmptyCntrBackCdpj2(strLuaDEID, unit_code, cntr_code)
                        if (nRet ~= 0) then
                            lua.Stop(strLuaDEID, "创建任务失败" .. task_info)
                            return
                        end
                    else
                        lua.DebugEx(strLuaDEID, unit_code .. "空托入拆叠盘 未满", cntr_code)
                        nRet, task_info = xcwms_base.EmptyCntrBackCdpjwm(strLuaDEID, unit_code, cntr_code)
                        if (nRet ~= 0) then
                            lua.Stop(strLuaDEID, "创建任务失败" .. task_info)
                            return
                        end
                    end
                    xcwms_base.CreatMqEqaction(strLuaDEID, "", unit_code, 9, "库后空托入拆叠盘", cntr_code, 9,
                        task_info.code, 1)
                end
            end
        end

        -- 1025、1026 库后线体回库口
        if (unit_code == "1025" or unit_code == "1026") then
            local target, unbind_info
            if (unit_code == "1025") then
                target = 1019
            elseif (unit_code == "1026") then
                target = 1022
            end
            -- 读取线体托盘号
            local nRet, cntr_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH", {unit_code .. "-CNTR_CODE_READ"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. cntr_info)
                return
            end
            local cntr_code = cntr_info[1].value
            lua.DebugEx(strLuaDEID, unit_code .. "读到的托盘码", cntr_code)
            -- 判断托盘是塑料托还是 仓储笼
            local res = tonumber(string.sub(cntr_code, 9, 9))
            lua.DebugEx(strLuaDEID, unit_code .. "res", res)
            if res ~= 3 and res ~= 4 then
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-TARGET_ADD_WRITE", {tonumber(target)})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写输送线终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, unit_code .. "申请wms任务异常 给输送线写终点回上料口",
                    cntr_code .. target)
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-SENT_WRITE", {1})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写SENT = 1失败! " .. returnvalue)
                    return
                end
            end
            -- 读是否有货
            local nRet, have_good_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                {unit_code .. "-HAV_GOD_READ"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. cntr_info)
                return
            end
            local have_god = tonumber(have_good_info[1].value[1])
            lua.DebugEx(strLuaDEID, unit_code .. "读到的是否有货", have_god)

            -- 铁笼/托盘有料 正常入库逻辑
            if res == 4 or (res == 3 and have_god == 1) then
                lua.DebugEx(strLuaDEID, unit_code .. "jinru", 1)
                local nRet, weight_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    {unit_code .. "-WEIGHT_READ"})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. nRet)
                    return
                end
                local weight = weight_info[1].value
                lua.DebugEx(strLuaDEID, unit_code .. "读到的重量", weight)
                local nRet, height_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    {unit_code .. "-HEIGHT_READ"})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. nRet)
                    return
                end
                local height = height_info[1].value[1]
                lua.DebugEx(strLuaDEID, unit_code .. "读到的高度", height)
                -- 检查此托盘码有无执行中的作业（区分人工叉车、agv搬运）
                local cntrop_info
                local strCondition = "S_CNTR_CODE = '" .. cntr_code .. "' AND N_B_STATE IN (0,1) " -- 
                nRet, cntrop_info = m3.GetDataObjByCondition(strLuaDEID, "Operation", strCondition, "T_CREATE DESC")
                if (nRet == 2) then
                    lua.Stop(strLuaDEID,
                        "GetDataObjByCondition获取托盘" .. cntr_code .. "作业信息失败" .. cntrop_info)
                    return
                end
                -- nRet = 1:当前无作业
                if nRet == 1 then
                    local wms_loc
                    if unit_code == "1025" then
                        wms_loc = "Z01DJX01"
                    elseif unit_code == "1026" then
                        wms_loc = "Z01DJX02"
                    end
                    -- 调用wms接口 005设备信号反馈 等待下发任务
                    local rkcanshu = {
                        reqId = "req" .. os.date("%Y%m%d%H%M%S"),
                        reqTime = os.date("%Y-%m-%d %H:%M:%S"),
                        loc = wms_loc,
                        cntrNo = cntr_code,
                        signalType = 3,
                        deviceNo = unit_code,
                        cntrType = 1,
                        qty = 8,
                        wareHouseCode = 'XCH01HYZHZ01',
                        extData = {{
                            ShapeCheckResult = 1,
                            Height = height,
                            Weight = tonumber(weight)
                        }}
                    }
                    -- 开始调用
                    local strHeader = ""
                    local strBody = lua.table2str(rkcanshu)
                    local strurl = "http://10.124.5.142:8080/xicai-boot/xicai/stacker/notifyDeviceSignal"
                    lua.DebugEx(strLuaDEID, "005接口调用前参数", strBody)
                    nRet, strRetInfo = mobox.sendHttpRequest(strurl, strHeader, strBody)
                    lua.Debug(strLuaDEID, debug.getinfo(1), "005接口调用后返回信息:", strRetInfo)
                    if (nRet ~= 0) then
                        lua.Error(strLuaDEID, debug.getinfo(1), "接口调用失败! 原因:" .. strRetInfo)
                    else
                        local retAttrs = json.decode(strRetInfo)
                        lua.Debug(strLuaDEID, debug.getinfo(1), "retAttrs:", retAttrs)
                        if (retAttrs["code"] == 0) then
                            -- 创建作业
                            local operation = m3.AllocObject(strLuaDEID, 'Operation')
                            operation.op_def_code = "OP074"
                            operation.op_type = 1 -- 1 入库 2 出库 3 移库
                            operation.op_def_name = "库后入库"
                            operation.b_state = 0
                            operation.cntr_code = retAttrs.data[1].cntrNo
                            operation.start_wh_code = "XD"
                            operation.start_area_code = "XDKQ"
                            operation.start_loc_code = unit_code
                            operation.end_wh_code = "XD"
                            operation.end_area_code = "XDKQ"
                            operation.end_loc_code = retAttrs.data[1].to -- 终点货位
                            operation.factory = "XD"
                            operation.wms_task = retAttrs.data[1].taskNo -- 上游wms任务号
                            operation.wms_loc = wms_loc
                            operation.priority = retAttrs.data[1].priority -- 优先级
                            operation.pre_wmstask = retAttrs.data[1].proTaskNo -- 前置任务号
                            lua.DebugEx(strLuaDEID, "作业创建前", operation)
                            nRet, strRetInfo = m3.CreateDataObj(strLuaDEID, operation)
                            if (nRet ~= 0) then
                                lua.Stop(strLuaDEID, "创建入库作业失败" .. strRetInfo)
                                return
                            end
                        else
                            local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                                unit_code .. "-TARGET_ADD_WRITE", {tonumber(target)})
                            if (nRet ~= 0) then
                                lua.Stop(strLuaDEID, "写输送线终点失败! " .. returnvalue)
                                return
                            end
                            lua.DebugEx(strLuaDEID,
                                unit_code .. "申请wms任务异常 给输送线写终点回上料口",
                                cntr_code .. target)
                            local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                                unit_code .. "-SENT_WRITE", {1})
                            if (nRet ~= 0) then
                                lua.Stop(strLuaDEID, "写SENT = 1失败! " .. returnvalue)
                                return
                            end
                            -- return
                        end
                    end
                elseif (nRet == 0) then
                    lua.DebugEx(strLuaDEID, "已有作业，创建动作队列", 1)
                    local strCondition = "S_EQ_CODE = '" .. unit_code .. "' AND S_OP_CODE = '" .. cntrop_info.code ..
                                             "'" -- AND N_B_STATE != 1
                    nRet, isexit = mobox.existThisData(strLuaDEID, "MQ_EQAction", strCondition)
                    if (nRet ~= 0) then
                        lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                        return
                    end
                    if (isexit == 'yes') then
                        return
                    end
                    xcwms_base.CreatMqEqaction(strLuaDEID, cntrop_info.code, unit_code, 7, "库后入库口", cntr_code,
                        4, "", 0)
                end
            end

            if res == 3 and have_god == 2 then
                -- 检测到是空托
                lua.DebugEx(strLuaDEID, "检测到是空托，开始送至1015叠盘", 1)
                local op_info
                -- 查当前托盘是否存在状态 ！= 1
                local strCondition = "S_START_LOC = '" .. unit_code .. "' AND S_CNTR_CODE = '" .. cntr_code ..
                                         "' AND N_B_STATE IN (0,1) "
                nRet, isexit = mobox.existThisData(strLuaDEID, "Task", strCondition)
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                    return
                end
                if (isexit == 'yes') then
                    return
                end
                -- 读当前拆叠盘机是否满料
                local nRet, cdp_value = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH", {"1015-STATUS_READ"})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. cntr_info)
                    return
                end
                local cdp_status = cdp_value[1].value[1]
                lua.DebugEx(strLuaDEID, unit_code .. "空托入拆叠盘,读到的拆叠盘当前状态", cdp_status)
                -- 如果满料 2
                if cdp_status ~= 3 then
                    if cdp_status == 2 then
                        -- 读取当前拆叠盘机托盘号
                        local nRet, cntr_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                            {"1015-CNTR_CODE_READ"})
                        if (nRet ~= 0) then
                            lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. cntr_info)
                            return
                        end
                        local cdp_cntr_code = cntr_info[1].value
                        lua.DebugEx(strLuaDEID, unit_code .. "读到的托盘码", cdp_cntr_code)
                        local strCondition = "S_START_LOC = '1015' AND N_B_STATE IN (0,1) "
                        nRet, isexit = mobox.existThisData(strLuaDEID, "Task", strCondition)
                        if (nRet ~= 0) then
                            lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                            return
                        end
                        if (isexit == 'yes') then
                            return
                        end
                        -- 调用wms接口 下发满托垛入库
                        nRet, op_info = xcwms_base.FullCntrInbound(strLuaDEID, "Z01DDP01", cdp_cntr_code, "1015")
                        if nRet ~= 0 then
                            lua.Stop(strLuaDEID, "调用WMS接口创建满托垛入库作业失败" .. op_info)
                            return
                        end
                        nRet, task_info = xcwms_base.EmptyCntrBackCdpj2(strLuaDEID, unit_code, cntr_code)
                    else
                        nRet, task_info = xcwms_base.EmptyCntrBackCdpjwm(strLuaDEID, unit_code, cntr_code)
                    end
                    xcwms_base.CreatMqEqaction(strLuaDEID, "", unit_code, 1, "库后空托叠盘", cntr_code, 9, "", 1)
                end
            end
        end

        -- 1013、1020 库后堆垛机入库口
        if (unit_code == "1013" or unit_code == "1020") then
            local query_task
            -- 读托盘码
            local nRet, cntr_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH", {unit_code .. "-CNTR_CODE_READ"})
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. nRet)
                return
            end
            local cntr_code = cntr_info[1].value
            lua.DebugEx(strLuaDEID, unit_code .. "读到的托盘码", cntr_code)

            -- 查询当前托盘的RGV任务
            local strCondition = "S_CNTR_CODE = '" .. cntr_code .. "' AND N_B_STATE = 1 AND N_SCHEDULE_TYPE = 9"
            nRet, query_task = m3.GetDataObjByCondition(strLuaDEID, "Task", strCondition, "T_CREATE DESC")
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "查询任务信息失败! " .. query_task)
                return
            end

            local strCondition = "S_EQ_CODE = '" .. unit_code .. "' AND S_TASK_CODE = '" .. query_task.code .. "'" -- AND N_B_STATE != 1
            nRet, isexit = mobox.existThisData(strLuaDEID, "MQ_EQAction", strCondition)
            if (nRet ~= 0) then
                lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                return
            end
            if (isexit == 'yes') then
                return
            end
            xcwms_base.CreatMqEqaction(strLuaDEID, query_task.op_code, unit_code, 1, "库后堆垛机入库口",
                cntr_code, 9, query_task.code, 0)
        end

        -- 库后拆叠盘机
        if (unit_code == "1015") then
            if inter_code == "SENT_READ" then
                local query_task
                local nRet, cntr_info = hc_plc.ReadS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    {unit_code .. "-CNTR_CODE_READ"})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法ReadS7PLCCommsData出错" .. nRet)
                    return
                end
                local cntr_code = cntr_info[1].value
                lua.DebugEx(strLuaDEID, unit_code .. "读到的托盘码", cntr_code)

                -- 查询当前托盘的RGV任务
                local strCondition = "S_CNTR_CODE = '" .. cntr_code .. "' AND N_B_STATE = 1 AND N_SCHEDULE_TYPE = 9"
                nRet, query_task = m3.GetDataObjByCondition(strLuaDEID, "Task", strCondition, "T_CREATE DESC")
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "查询任务信息失败! " .. query_task)
                    return
                end

                lua.DebugEx(strLuaDEID, unit_code .. "RGV查询任务信息", query_task)

                local task_no = query_task.code
                local strCondition = "S_EQ_CODE = '" .. unit_code .. "' AND S_TASK_CODE = '" .. task_no .. "'"
                nRet, isexit = mobox.existThisData(strLuaDEID, "MQ_EQAction", strCondition)
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "调用方法existThisData出错" .. isexit)
                    return
                end
                if (isexit == 'yes') then
                    return
                end
                xcwms_base.CreatMqEqaction(strLuaDEID, query_task.op_code, unit_code, 7, "空托到达拆叠盘机",
                    cntr_code, 9, task_no, 0)
            end

            if inter_code == "XIAFA_READ" then
                lua.DebugEx(strLuaDEID, unit_code .. "XIAFA_READ", 1)
                -- 写目的地至当前线体
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-TARGET_ADD_WRITE", {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写输送线终点失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "写输送线终点成功", 1)
                local nRet, returnvalue = hc_plc.WriteS7PLCCommsData(strLuaDEID, "XD_SSX_KH",
                    unit_code .. "-XIAFA_WRITE", {0})
                if (nRet ~= 0) then
                    lua.Stop(strLuaDEID, "写XIAFA_WRITE失败! " .. returnvalue)
                    return
                end
                lua.DebugEx(strLuaDEID, "" .. unit_code .. "回复线体XIAFA_WRITE = 0成功", 1)
            end
        end
    end
end
