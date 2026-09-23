--[[ 
 编码: 
 名称: CreatAgvTask 
 作者: xsy
 入口函数：CreatAgvTask 
 功能说明: 
 变更历史: 
 --]] m3 = require("oi_base_mobox")
lua = require("oi_base_func")
json = require("json")
hc_plc = require("hcplc_base")
wms_wh = require("wms_wh")
wms_base = require("wms_base")
wms_cntr = require("wms_container")
wms_out = require("wms_outbound")
wms_station = require("wms_station")

-- "http://10.124.5.141:5103/api/pei/callext/XDXC/CreatTask?UsingCustomFmt=1"

function CreatTask(strLuaDEID)
    local nRet, strRetInfo, operation_info, input_datajson, end_loc
    -- 获取接口中的Data
    nRet, input_datajson = m3.GetSysDataJson(strLuaDEID)
    if (nRet ~= 0) then
        lua.Stop(strLuaDEID, "PLCStateChange无法获取数据包!" .. input_datajson)
        return 1
    end
    lua.DebugEx(strLuaDEID, "收到wms调用001任务下发接口信息", input_datajson)

    local wms_task = input_datajson.taskNo -- WMS任务号
    local op_type = input_datajson.taskType -- 作业类型 “入库” 出库 移库
    local priority = tonumber(input_datajson.priority) -- 作业优先级
    local start_loc = input_datajson.from -- 起点
    local wms_end_loc = input_datajson.to -- 终点
    local cntr_code = input_datajson.cntrNo -- 托盘号
    local cntr_type = input_datajson.cntrType -- 托盘类型
    local req_time = input_datajson.reqTime -- WMS请求时间
    local req_id = input_datajson.reqId -- WMS请求id
    local groupNo = input_datajson.groupNo -- 任务组号  可空 拣选对应的任务：填写订单号
    local pre_wmstask = input_datajson.preTaskNo -- 前置WMS任务号 可空，有前置任务号的需先执行前置任务

    -- 参数校验
    if wms_task == "" or wms_task == nil then
        local result = {
            code = -1,
            msg = "wcs创建任务失败! 原因:缺少taskNo",
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    end
    if op_type == "" or op_type == nil then
        local result = {
            code = -1,
            msg = "wcs创建任务失败! 原因:缺少taskType",
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    end
    if priority == "" or priority == nil then
        local result = {
            code = -1,
            msg = "wcs创建任务失败! 原因:缺少priority",
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    end
    if start_loc == "" or start_loc == nil then
        local result = {
            code = -1,
            msg = "wcs创建任务失败! 原因:缺少from",
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    end
    if end_loc == "" or end_loc == nil then
        local result = {
            code = -1,
            msg = "wcs创建任务失败! 原因:缺少to",
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    end
    if cntr_code == "" or cntr_code == nil then
        local result = {
            code = -1,
            msg = "wcs创建任务失败! 原因:缺少cntrNo",
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    end

    local n_op_type
    if op_type == "2" then -- 2 入库
        n_op_type = 1
    elseif op_type == "1" or op_type == "4" then -- 1 空托垛出库、4 出库
        n_op_type = 2
        local lastChar = string.sub(start_loc, -1)
        if lastChar == "2" then
            priority = 10
        end
    elseif op_type == "3" then -- 移库
        n_op_type = 3
        local lastChar = string.sub(start_loc, -1)
        if lastChar == "2" then
            priority = 10
        end
    end

    local op_def_name
    if end_loc == "013" or end_loc == "014" or end_loc == "015" or end_loc == "016" then
        op_def_name = "库前出库"
    elseif end_loc == "065" or end_loc == "064" then
        op_def_name = "库中出库"
    elseif end_loc == "038" or end_loc == "039" or end_loc == "040" or end_loc == "043" then
        op_def_name = "库后出库"
    else
        op_def_name = "库内移库"
    end

    local startloc_info, endloc_info
    -- 查询起点货位信息
    nRet, startloc_info = hc_plc.GetLocInfo(strLuaDEID, start_loc)
    if nRet ~= 0 then
        lua.DebugEx(strLuaDEID, "001查询起点货位信息失败,原因:", startloc_info)
        local result = {
            code = -1,
            msg = "wcs创建任务失败! 查询起点货位信息失败,请联系wcs处理。原因:" .. startloc_info,
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    end

    lua.DebugEx(strLuaDEID, "起点货位信息", startloc_info)

    -- 查询终点货位信息
    nRet, endloc_info = hc_plc.GetLocInfo(strLuaDEID, end_loc)
    if nRet ~= 0 then
        lua.DebugEx(strLuaDEID, "001查询终点货位信息失败,原因:", endloc_info)
        local result = {
            code = -1,
            msg = "wcs创建任务失败! 查询终点货位信息失败,请联系wcs处理。原因:" .. endloc_info,
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    end

    -- 创建作业
    local operation = m3.AllocObject(strLuaDEID, 'Operation')
    operation.op_def_code = "OP004" -- 根据不同作业类型区分
    operation.op_type = n_op_type -- 1 入库 2 出库 3 移库
    operation.op_def_name = op_def_name -- 根据WMS下发的不同作业类型区分
    operation.b_state = 0 -- 状态 已推送
    operation.cntr_code = cntr_code
    -- 起点信息 查询起点货位获取
    operation.start_wh_code = startloc_info.wh_code -- 仓库
    operation.start_area_code = startloc_info.area_code -- 库区  SXCK  TPK  DSLXK
    operation.start_loc_code = start_loc -- 货位
    -- 终点信息 查询终点货位获取
    operation.end_wh_code = endloc_info.wh_code -- 终点仓库
    operation.end_area_code = endloc_info.area_code -- 终点库区
    operation.end_loc_code = end_loc -- 终点货位
    operation.factory = "YB"
    operation.wms_loc = wms_end_loc

    operation.wms_task = wms_task
    -- 判断作业执行顺序用
    -- operation.group = groupNo -- 作业组号
    operation.priority = priority -- 优先级
    operation.pre_wmstask = pre_wmstask

    if n_op_type == 2 or n_op_type == 3 then
        operation.start_aisle = startloc_info.aisle -- 先写成2
    end

    lua.DebugEx(strLuaDEID, "作业创建前", operation)
    nRet, strRetInfo = m3.CreateDataObj(strLuaDEID, operation)
    if (nRet ~= 0) then
        lua.DebugEx(strLuaDEID, "作业创建失败，原因:", strRetInfo)
        local result = {
            code = -1,
            msg = "wcs创建任务失败! 请联系wcs处理。原因:" .. strRetInfo,
            data = {}
        }
        mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
        return
    end

    lua.DebugEx(strLuaDEID, "作业" .. operation.code .. "已成功创建,WMS任务号:", input_datajson.taskNo)
    local result = {
        code = 0,
        msg = "success",
        data = {}
    }
    mobox.returnValue(strLuaDEID, 1, lua.table2str(result))
end
