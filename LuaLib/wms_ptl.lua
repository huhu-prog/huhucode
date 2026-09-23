--[[
    版本：     Version 3.0
    创建日期： 2025-3-29
    修改日期： 2026-6-18
    作者：     HAN

    WMS-Basis-Model-Version: V16.6

    名称:   wms_ptl
    应用:   涉及电子标签的一些应用
            《OpenInfo Pick To Light WebAPI》

    【亮灯/灭灯】
        Lighting              — 亮灯
        TurnOff               — 灭灯
        TurnOffByStation      — 根据站台灭灯（取货区的库位）

    【按钮/状态】
        GetPTLState           — 得到指定货位的灯的状态
        PushButtonLight       — 模拟按灯动作
        SimulateConfirm       — 模拟拍灯
        SetConfirmProcStatus  — 设置确定按钮按下已处理状态

    【站台】
        SetStationPTLStatus   — 设置站台电子标签状态（取货区+放货区灭灯并设置确认状态）


    更改记录:
        2025-3-29  HAN  创建
        2026-6-18        整理函数注释，完善 @tparam/@treturn 注解

    AI CHECK:
        -- 20260618
--]]

wms_base = require("wms_base")

local wms_ptl = { _version = "0.2.1" }

-- 亮灯颜色
PTL_COLOR = lua.MakeConstantTable({
    Red = 1,    -- 红色
    Green = 2,  -- 绿色
    Orange = 3, -- 橙色
    Blue = 4,   -- 蓝色
    Pink = 5,   -- 粉红色
    Cyan = 6    -- 青色
})


--[[
    亮灯
    输入参数:
        loc_code    -- 亮灯的库位
        digit_str   -- 料格编码加数量的一串字符串
        color       -- 颜色 (1 - 红色，2 - 绿色，3 - 橙色， 4 - 蓝色，5 - 粉红色，6 - 青色)
        parameter   --  {
                            show_mode -- 显示模式: 1 - 静态显示（默认），2~7 - 闪烁，值越大，闪烁越快
                            press_off -- 是否可确定拍灭：1 - 可拍灭（默认），2 - 不可拍灭
                            notify_user -- 按灯后需要通知的用户
                            addin_name -- 消息通知时的扩展插件名称
                            ext_data -- 扩展附加数据，用于通知时返回给接收方
                        }
    返回参数:

--]]
-- 亮灯
-- @function wms_ptl.Lighting
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string loc_code 亮灯的库位
-- @tparam string digit_str 料格编码加数量的一串字符串
-- @tparam number color 颜色（1-红色，2-绿色，3-橙色，4-蓝色，5-粉红色，6-青色）
-- @tparam table parameter 扩展参数表
-- @treturn number nRet 0: 成功，1: 参数错误，2: 系统错误
-- @treturn string strRetInfo 错误信息（仅当 nRet ~= 0 时有意义）
function wms_ptl.Lighting(strLuaDEID, loc_code, digit_str, color, parameter)
    local nRet, strRetInfo

    if lua.StrIsEmpty(loc_code) then
        return 1, "wms_ptl.Lighting 函数的输入参数 loc_code 不能为空!"
    end
    if lua.StrIsEmpty(digit_str) then
        return 1, "wms_ptl.Lighting 函数的输入参数 digit_str 不能为空!"
    end

    if color == nil or type(color) ~= "number" then
        return 1, "wms_ptl.Lighting 函数的输入参数 color 必须是一个数值!"
    end
    if parameter == nil or type(parameter) ~= "table" then
        return 1, "wms_ptl.Lighting 函数的输入参数 parameter 必须是一个 table !"
    end

    local ptl_url
    nRet, ptl_url = wms_base.Get_sConst2("PTL_Service")
    if nRet ~= 0 then
        return 1, "系统无法获取常量'PTL_Service'"
    end

    local strurl = ptl_url .. '/api/ptl/Lighting'
    local body = {
        loc_code = loc_code,
        digit = digit_str,
        color = color,
        show_mode = parameter.show_mode or 1,
        press_off = parameter.press_off or 1,
        notify_user = parameter.notify_user or '',
        addin_name = parameter.addin_name or '',
        ext_data = parameter.ext_data or '',
    }

    nRet, strRetInfo = mobox.sendHttpRequest(strurl, "", lua.table2str(body))
    if nRet ~= 0 or strRetInfo == '' then
        return 2, "调用 PTL api/ptl/Lighting 接口失败! " .. strRetInfo
    end

    local ret_info = json.decode(strRetInfo)
    return ret_info.err_code, ret_info.err_msg
end

-- 灭灯
-- @function wms_ptl.TurnOff
-- @tparam string loc_code 灭灯的库位
-- @treturn number nRet 0: 成功，1: 参数错误，2: 系统错误
-- @treturn string strRetInfo 返回信息
function wms_ptl.TurnOff(loc_code)
    local nRet, strRetInfo

    if lua.StrIsEmpty(loc_code) then
        return 1, "wms_ptl.TurnOff 函数的输入参数 loc_code 不能为空!"
    end

    local ptl_url
    nRet, ptl_url = wms_base.Get_sConst2("PTL_Service")
    if nRet ~= 0 then
        return 1, "系统无法获取常量'PTL_Service'"
    end

    local strurl = ptl_url .. '/api/ptl/TurnOff'
    local body = {
        loc_code = loc_code
    }

    nRet, strRetInfo = mobox.sendHttpRequest(strurl, "", lua.table2str(body))
    if nRet ~= 0 or strRetInfo == '' then
        return 2, "调用 PTL api/ptl/TurnOff 接口失败! " .. strRetInfo
    end

    local ret_info = json.decode(strRetInfo)
    return 0, ret_info.msg
end

-- 检查指定库位是否有库存
-- @function check_exists_stock
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string loc_code 库位编码
-- @treturn boolean 是否存在库存（true: 有库存，false: 无库存）
local function check_exists_stock(strLuaDEID, loc_code)
    local nRet, strRetInfo
    local strTableName = "TN_INV_Detail"
    local strCondition = string.format("S_LOC_CODE='%s' AND F_QTY>0", loc_code)
    nRet, strRetInfo = mobox.getDBRecordCount(strLuaDEID, strTableName, strCondition)
    if nRet ~= 0 then
        lua.Stop(strLuaDEID, "查询TN_INV_Detail失败!" .. strRetInfo)
        return false
    end
    local count = lua.StrToNumber(strRetInfo)
    if count > 0 then
        return true
    end
    return false
end

-- 根据站台灭灯（取货区的库位）
-- @function wms_ptl.TurnOffByStation
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string station 站台编码
-- @tparam boolean valid_stock 是否仅灭有库存的灯
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string strRetInfo 错误信息
function wms_ptl.TurnOffByStation(strLuaDEID, station, valid_stock)
    local nRet, strRetInfo
    local station_objs
    local strCondition = string.format("S_CODE='%s'", station)
    nRet, station_objs = m3.QueryDataObject(strLuaDEID, "Machine_Station", strCondition, "S_CODE")
    if nRet ~= 0 then
        return 1, '查询【Machine_Station】失败!' .. station_objs
    end

    local data_attrs
    for _, obj in ipairs(station_objs) do
        data_attrs = m3.KeyValueAttrsToObjAttr(obj.attrs)
        if data_attrs == nil then
            return 1, 'KeyValueAttrsToObjAttr失败!'
        end
        local tp_area = data_attrs.S_TP_AREA or ''
        local tp_loc_list
        strCondition = string.format( "S_AREA_CODE = '%s' ", tp_area)
        nRet, tp_loc_list = m3.QueryDataObject(strLuaDEID, "Location", strCondition, "S_CODE")
        if nRet ~= 0 then
            return 1, '查询【Location】失败!' .. tp_loc_list
        end
        for _, loc in ipairs(tp_loc_list) do
            local loc_obj = m3.KeyValueAttrsToObjAttr(loc.attrs)
            if loc_obj == nil then
                return 1, 'KeyValueAttrsToObjAttr失败!'
            end
            if valid_stock == true then
                local exists_stock = check_exists_stock(strLuaDEID, loc_obj.S_CODE)
                if exists_stock == true then
                    nRet, strRetInfo = wms_ptl.TurnOff(loc_obj.S_CODE)
                    if nRet ~= 0 then
                        return 1, strRetInfo or ''
                    end
                end
            else
                nRet, strRetInfo = wms_ptl.TurnOff(loc_obj.S_CODE)
                if nRet ~= 0 then
                    return 1, strRetInfo or ''
                end
            end
        end
        --[[local sw_area=data_attrs.S_SW_AREA
        local sw_loc_list
         strCondition=string.format("S_AREA_CODE='%s'",sw_area)
        nRet,sw_loc_list=m3.QueryDataObject(strLuaDEID,"Location",strCondition,"S_CODE")
        if nRet ~= 0 then
            return 1,'查询【Location】失败!'..sw_loc_list
        end
        for _, loc in ipairs(sw_loc_list) do
            local loc_obj=m3.KeyValueAttrsToObjAttr(loc.attrs)
            nRet,strRetInfo=wms_ptl.TurnOff(loc_obj.S_CODE)
            if nRet~=0 then
                return 1, strRetInfo or ''
            end
        end]]
    end
    return 0, ''
end

-- 得到指定货位的灯的状态
-- @function wms_ptl.GetPTLState
-- @tparam string loc_code 灯的库位
-- @treturn number nRet 0: 成功，1: 参数错误，2: 系统错误
-- @treturn table result 灯状态 {loc_code, is_pressed}
function wms_ptl.GetPTLState(loc_code)
    local nRet, strRetInfo

    if lua.StrIsEmpty(loc_code) then
        return 1, "wms_ptl.GetPTLState 函数的输入参数 loc_code 不能为空!"
    end

    local ptl_url
    nRet, ptl_url = wms_base.Get_sConst2("PTL_Service")
    if nRet ~= 0 then
        return 1, "系统无法获取常量'PTL_Service'"
    end

    local strurl = ptl_url .. '/api/ptl/GetConfirmStatus'
    local body = {
        loc_code = loc_code
    }

    nRet, strRetInfo = mobox.sendHttpRequest(strurl, "", lua.table2str(body))
    if nRet ~= 0 or strRetInfo == '' then
        return 2, "调用 PTL api/ptl/GetConfirmStatus 接口失败! " .. strRetInfo
    end

    local ret_info = json.decode(strRetInfo)
    return 0, ret_info.result
end

-- 模拟按灯动作
-- @function wms_ptl.PushButtonLight
-- @tparam string loc_code 灯的库位
-- @treturn number nRet 0: 成功，1: 参数错误，2: 系统错误
-- @treturn string strRetInfo 错误信息
function wms_ptl.PushButtonLight(loc_code)
    local nRet, strRetInfo

    if lua.StrIsEmpty(loc_code) then
        return 1, "wms_ptl.PushButtonLight 函数的输入参数 loc_code 不能为空!"
    end

    local ptl_url
    nRet, ptl_url = wms_base.Get_sConst2("PTL_Service")
    if nRet ~= 0 then
        return 1, "系统无法获取常量'PTL_Service'"
    end

    local strurl = ptl_url .. '/api/ptl/SimulateConfirm'
    local body = {
        loc_code = loc_code
    }
    nRet, strRetInfo = mobox.sendHttpRequest(strurl, "", lua.table2str(body))
    if nRet ~= 0 or strRetInfo == '' then
        return 2, "调用 PTL api/ptl/SimulateConfirm 接口失败! " .. strRetInfo
    end

    local ret_info = json.decode(strRetInfo)
    return ret_info.err_code, ret_info.err_msg
end

-- 模拟拍灯
-- @function wms_ptl.SimulateConfirm
-- @tparam string loc_code 灭灯的库位
-- @treturn number nRet 0: 成功，1: 参数错误，2: 系统错误
-- @treturn string strRetInfo 返回信息
function wms_ptl.SimulateConfirm(loc_code)
    local nRet, strRetInfo

    if lua.StrIsEmpty(loc_code) then
        return 1, "wms_ptl.SimulateConfirm 函数的输入参数 loc_code 不能为空!"
    end

    local ptl_url
    nRet, ptl_url = wms_base.Get_sConst2("PTL_Service")
    if nRet ~= 0 then
        return 1, "系统无法获取常量'PTL_Service'"
    end

    local strurl = ptl_url .. '/api/ptl/SimulateConfirm'
    local body = {
        loc_code = loc_code
    }

    nRet, strRetInfo = mobox.sendHttpRequest(strurl, "", lua.table2str(body))
    if nRet ~= 0 or strRetInfo == '' then
        return 2, "调用 PTL api/ptl/SimulateConfirm 接口失败! " .. strRetInfo
    end

    local ret_info = json.decode(strRetInfo)
    return 0, ret_info.msg
end

-- 设置确定按钮按下已处理状态
-- @function wms_ptl.SetConfirmProcStatus
-- @tparam string loc_code 灭灯的库位
-- @treturn number nRet 0: 成功，1: 参数错误，2: 系统错误
-- @treturn string strRetInfo 返回信息
function wms_ptl.SetConfirmProcStatus(loc_code)
    local nRet, strRetInfo
    if lua.StrIsEmpty(loc_code) then
        return 1, "wms_ptl.SetConfirmProcStatus 函数的输入参数 loc_code 不能为空!"
    end

    local ptl_url
    nRet, ptl_url = wms_base.Get_sConst2("PTL_Service")
    if nRet ~= 0 then
        return 1, "系统无法获取常量'PTL_Service'"
    end

    local strurl = ptl_url .. '/api/ptl/SetConfirmProcStatus'
    local body = {
        loc_code = loc_code
    }

    nRet, strRetInfo = mobox.sendHttpRequest(strurl, "", lua.table2str(body))
    if nRet ~= 0 then
        return 2, "调用 PTL api/ptl/SetConfirmProcStatus 接口失败! " .. strRetInfo
    end

    return 0, strRetInfo
end

-- 设置站台电子标签状态（取货区+放货区灭灯并设置确认状态）
-- @function wms_ptl.SetStationPTLStatus
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string station 站台编码
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string strRetInfo 错误信息
function wms_ptl.SetStationPTLStatus(strLuaDEID, station)
    local nRet, strRetInfo
    local station_objs
    local strCondition = string.format("S_CODE='%s'", station)

    nRet, station_objs = m3.QueryDataObject(strLuaDEID, "Machine_Station", strCondition, "S_CODE")
    if nRet ~= 0 then
        return 1, '查询【Machine_Station】失败!' .. station_objs
    end

    local data_attrs
    for _, obj in ipairs(station_objs) do
        data_attrs = m3.KeyValueAttrsToObjAttr(obj.attrs)
        if data_attrs == nil then
            return 1, 'KeyValueAttrsToObjAttr 失败!'
        end
        local tp_area = data_attrs.S_TP_AREA or ''
        local tp_loc_list
        strCondition = string.format("S_AREA_CODE='%s'", tp_area)
        nRet, tp_loc_list = m3.QueryDataObject(strLuaDEID, "Location", strCondition, "S_CODE")
        if nRet ~= 0 then
            return 1, '查询【Location】失败!' .. tp_loc_list
        end
        for _, loc in ipairs(tp_loc_list) do
            local loc_obj = m3.KeyValueAttrsToObjAttr(loc.attrs)
            if loc_obj == nil then
                return 1, 'KeyValueAttrsToObjAttr 失败!'
            end
            nRet, strRetInfo = wms_ptl.TurnOff(loc_obj.S_CODE)
            if nRet ~= 0 then
                return 1, strRetInfo or ''
            end
            nRet, strRetInfo = wms_ptl.SetConfirmProcStatus(loc_obj.S_CODE)
            if nRet ~= 0 then
                return 1, strRetInfo or ''
            end
        end
        local sw_area = data_attrs.S_SW_AREA or ''
        local sw_loc_list
        strCondition = string.format("S_AREA_CODE='%s'", sw_area)
        nRet, sw_loc_list = m3.QueryDataObject(strLuaDEID, "Location", strCondition, "S_CODE")
        if nRet ~= 0 then
            return 1, '查询【Location】失败!' .. sw_loc_list
        end
        for _, loc in ipairs(sw_loc_list) do
            local loc_obj = m3.KeyValueAttrsToObjAttr(loc.attrs)
            if loc_obj == nil then
                return 1, 'KeyValueAttrsToObjAttr 失败!'
            end
            nRet, strRetInfo = wms_ptl.TurnOff(loc_obj.S_CODE)
            if nRet ~= 0 then
                return 1, strRetInfo or ''
            end
             nRet, strRetInfo = wms_ptl.SetConfirmProcStatus(loc_obj.S_CODE)
            if nRet ~= 0 then
                return 1, strRetInfo or ''
            end
        end
    end
    return 0, ''
end

return wms_ptl
