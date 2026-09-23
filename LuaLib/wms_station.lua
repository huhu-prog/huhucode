--[[
    版本：     Version 3.0
    创建日期： 2025-3-26
    修改日期:  2026-6-19
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    名称:   wms_station
    说明:   机台、站台相关的一些标准函数

    【站台信息获取】
        GetInfo                        — 获取站台信息
        Get_Station_ExtData            — 获取站台扩展属性
        Get_Station_Loc                — 获取站台所在货位
        Get_Station_TransferZone       — 获取站台的接驳区、位
        Get_Connectable_Stations       — 获取可以连通的站台

    【站台作业查询】
        _Get_Station_CurRun_Operation  — 获取站台正在作业的Operation列表
        _Get_Station_CurRun_Order      — 获取站台正在作业的订单列表

    更改记录:
        2025-3-26  HAN  创建
        2026-6-19        整理函数注释，添加 @tparam/@treturn 注解

    AI CHECK:
        -- 20260619
--]]

wms_base = require ("wms_base")

local wms_station = {_version = "0.2.1"}

-- 获取站台信息
-- @function wms_station.GetInfo
-- @tparam string station_code 站台编码
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table/string station_data 成功返回站台属性table，失败返回错误信息
function wms_station.GetInfo( station_code )

    if station_code == nil or station_code == '' then
        return 1, "wms_station.GetInfo 函数 station_code 不能为nil或空!"
    end
    local nRet, station_data = m3.GetDataFromCache( "Machine_Station", station_code )
    if nRet ~= 0  then 
        return nRet, station_data 
    end
    return 0, station_data    
end

-- 获取 '机台-XX' 常量并且解析成站台扩展属性 table
-- 作废（不建议使用)
-- @function wms_station.Get_Station_ExtData
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string station_code 站台编码
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table/string staion_attr 成功返回站台扩展属性table，失败返回错误信息
function wms_station.Get_Station_ExtData( strLuaDEID, station_code )
    if station_code == nil or station_code == '' then
        return 1, "wms_station.Get_Station_ExtData 函数中 station_code 不能为空!"
    end

    local nRet, station_info
    nRet, station_info = wms_base.Get_sConst2( "机台-"..station_code)
    if nRet ~= 0 then
        return 1, "系统无法获取常量'机台-"..station_code.."'"
    end

    if station_info == '' then
        return 1, "机台-"..station_code.." 常量中没有定义信息, 或没定义这个机台常量!" 
    end
    local staion_attr = json.decode( station_info )   

    return 0, staion_attr
end

-- 获取 '机台-XX' 所在货位编码
-- 作废（不建议使用)
-- @function wms_station.Get_Station_Loc
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string station_code 站台编码
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string/table loc_code 成功返回货位编码，失败返回错误信息
function wms_station.Get_Station_Loc( strLuaDEID, station_code )
    local nRet, station_data
    nRet, station_data = wms_station.Get_Station_ExtData( strLuaDEID, station_code )
    if nRet ~= 0 then
        return 1, station_data
    end
    return 0, station_data.loc_code
end

-- 根据作业定义和站台编码获取站台的接驳区、位
-- 支持 WS(TP)、WS(TP/SW)、WS(TPS)、WS(TPS/SW) 四种站台类型
-- @function wms_station.Get_Station_TransferZone
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string station_no 站台号
-- @tparam table op_def 作业定义（可以为空）
-- @treturn number nRet 0: 成功，1/2: 失败
-- @treturn string wh_code 仓库编码
-- @treturn string area_code 库区编码
-- @treturn string loc_code 货位编码
function wms_station.Get_Station_TransferZone( strLuaDEID, station_no, op_def )
    local nRet

    if lua.StrIsEmpty( station_no ) then
        return 1, "wms_station.Get_Station_TransferZone 函数中 station_no 必须有值!"
    end

    -- 获取站点信息
    local station_data
    nRet, station_data = m3.GetDataFromCache( "Machine_Station", station_no )
    if nRet ~= 0 then
        return 2, station_data
    end

    local target_area_is_loc = true
    if not lua.isTableEmpty( op_def ) then
        if op_def.hand_proc == "[Picking-AS/RS]->[Station]" then
            -- Pickingc 车不需要对最终位置加锁
            target_area_is_loc = false
        end
    end
    
    local to_loc_code = station_data.S_LOC_CODE or ''
    local to_wh_code = ''
    local to_area_code = ''

    if station_data.S_TYPE == 'WS(TP)' or station_data.S_TYPE == 'WS(TP/SW)' then
        local area
        to_area_code = station_data.S_TP_AREA or ''
        if to_area_code == '' then
            return 1, "站台'"..station_no.."'没有定义接驳区!"
        end
        nRet, area = wms_wh.GetAreaInfo( to_area_code )
        if nRet ~= 0 then 
            return 1, '获取库区信息失败! '..area
        end 
        to_wh_code = area.wh_code
        to_loc_code = ''                -- 需要后面程序来确定

        if target_area_is_loc then
            local loc
            nRet, loc = wms_alg.Get_One_Available_Location_InArea( strLuaDEID, to_area_code )
            if nRet ~= 0 then
                return 2, "在获取库区'"..to_area_code.."'的空货位时失败! "..loc
            end
            if loc == '' then
                return 1,"站台的接驳区'"..to_area_code.."'已满! "
            end
            to_loc_code = loc.code
        end   
    elseif station_data.S_TYPE == 'WS(TPS)' or station_data.S_TYPE == 'WS(TPS/SW)' then
        --  TPS 有多个接驳区
        to_area_code = ''
        to_wh_code = ''
        to_loc_code = ''                -- 需要后面程序来确定
    else        
        if target_area_is_loc then
            local to_loc
            nRet, to_loc = wms_wh.GetLocInfo( to_loc_code )
            if nRet ~= 0 then 
                return 1, '获取货位信息失败! '..to_loc
            end 
            to_wh_code = to_loc.wh_code
            to_area_code = to_loc.area_code
        else
            return 1, "站台'"..station_no.."'的类型有冲突!"
        end
    end   
    return 0, to_wh_code, to_area_code, to_loc_code
end

-- 获取站台正在作业的Operation列表
-- @function wms_station._Get_Station_CurRun_Operation
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string station_no 站台号, 必须有值
-- @treturn table|nil op_set nil
-- @treturn string|nil 错误信息，成功时 nil
function wms_station._Get_Station_CurRun_Operation( strLuaDEID, station_no )
    if station_no == nil or station_no == '' then
        return nil, "wms_station._Get_Station_CurRun_Operation 函数中 station_no 必须有值!"
    end
    local strCondition = "N_B_STATE = "..OPERATION_STATE.Run.." AND S_STATION_NO = '"..station_no.."'"
    local nRet, op_objs = m3.QueryDataObject(strLuaDEID, "Operation", strCondition )
    if nRet ~= 0 then 
        return nil,"QueryDataObject失败!"..op_objs
    end
    local op_set = {}    
    if op_objs ~= '' then 
        for _, obj in ipairs(op_objs) do
            local obj_attrs = m3.KeyValueAttrsToObjAttr(obj.attrs)
            if obj_attrs == nil then
                return nil, "KeyValueAttrsToObjAttr失败!"
            end
            obj_attrs.id = obj.id
            table.insert(op_set, obj_attrs)
        end
    end
    return op_set
end

-- 获取站台正在作业的订单列表，返回 S_BS_NO、S_BS_TYPE
-- @function wms_station._Get_Station_CurRun_Order
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string station_no 站台号, 必须有值
-- @treturn table|nil 订单列表 nil
-- @treturn string|nil 错误信息，成功时 nil
function wms_station._Get_Station_CurRun_Order( strLuaDEID, station_no )
    if station_no == nil or station_no == '' then
        return nil, "wms_station._Get_Station_CurRun_Operation 函数中 station_no 必须有值!"
    end
    local strCondition = "N_B_STATE = "..OPERATION_STATE.Run.." AND S_STATION_NO = '"..station_no.."'"
    local nRet, strRetInfo = mobox.groupDataObjAttrs( strLuaDEID, "Operation", strCondition, "", "S_BS_TYPE", "S_BS_NO" )
    if nRet ~= 0 then 
        return nil,"groupDataObjAttrs失败!"..strRetInfo
    end
    local op_set = {}    
    if strRetInfo ~= '' then 
        local order_info = json.decode( strRetInfo ) 
    
        for _, order in ipairs(order_info) do
            local bs_order = {
                S_BS_TYPE = order[1].value,
                S_BS_NO = order[2].value
            }
            table.insert(op_set, bs_order)
        end
    end
    return op_set
end

-- 获取 '站台'station_code 可以连通的站台
-- @function wms_station.Get_Station_ExtData
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string station_code 站台编码
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table/string staion_attr 成功返回站台可以连通的站台{"s1","s2",...}，失败返回错误信息
function wms_station.Get_Connectable_Stations( strLuaDEID, station_code )
    if station_code == nil or station_code == '' then
        return 1, "wms_station.Get_Connectable_Stations 函数中 station_code 不能为空!"
    end

    local strCondition = "C_ENABLE = 'Y' AND S_S_NODE_TYPE = 'Machine_Station' AND S_E_NODE_TYPE = 'Machine_Station' AND S_S_NODE_NO = '"..station_code.."'"
    local nRet, path_objs = m3.QueryDataObject(strLuaDEID, "Path_Edge", strCondition )
    if nRet ~= 0 then 
        return 2,"QueryDataObject失败!"..path_objs
    end
    local connect_station_set = {}    
    if path_objs ~= '' then 
        for _, obj in ipairs(path_objs) do
            local obj_attrs = m3.KeyValueAttrsToObjAttr(obj.attrs)
            if obj_attrs == nil then
                return 2, "KeyValueAttrsToObjAttr 失败!"
            end
            obj_attrs.id = obj.id
            table.insert(connect_station_set, obj_attrs.S_E_NODE_NO)
        end
    end

    return 0, connect_station_set
end

-- 根据站台分配策略分配出库站台
-- @function wms_station.Get_Station_ExtData
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table strategy 站台分配策略
-- @tparam string op_type 作业类型，用来匹配站台的作业模式
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string staion_no 成功返回站台号，如果找不到返回空，失败返回错误信息
-- @treturn string msg 如果站台分配失败，这个参数返回失败原因
--[[
    strategy = {
        model = "BY_SEQUENCE/EVEN_DISTRIBUTION/PRIO_FEWER_TASKS"
        station = {"S01","S03",...}
    }
    BY_SEQUENCE -- 根据站台顺序先安排满前面的站台
    PRIO_FEWER_TASKS -- 优先选择任务较少的站台
--]]
function wms_station.Assignment_ByStrategy( strLuaDEID, strategy, op_type )
    if strategy == nil or type(strategy) ~= 'table' then
        return 1, "wms_station.Assignment_ByStrategy 函数中 strategy 必须有值,必须是table类型!"
    end
      if strategy.station == nil or type(strategy.station) ~= 'table' then
        return 1, "wms_station.Assignment_ByStrategy 函数中 strategy.station 必须有值,必须是table类型!"
    end
    local station_list = {}
    local nRet, station_data

    if #strategy.station == 0 then
        return 0, "", "系统建议的可用站台数量为零"
    end
    for _, station_code in ipairs(strategy.station) do
        local check_ok = true
        nRet, station_data = wms_station.GetInfo( station_code )
        if nRet ~= 0 then
            return 1, "系统中没有定义编码'"..station_code.."'的站台!"
        end
        -- 站台禁用
        if station_data.C_ENABLE ~= 'Y' then
            check_ok = false
        else
            -- 判断站台的作业模式
            if station_data.N_OP_MODEL == STATION_OP_MODEL.Single then
                -- 如果是单一模式要判断当前的作业模式是否适合当前站台
                if op_type == OPERATION_TYPE.Outbound then
                    if station_data.N_CUR_OP_TYPE ~= STATION_OP_TYPE.Picking then
                        check_ok = false
                    end
                elseif op_type == OPERATION_TYPE.Inbound then
                    if station_data.N_CUR_OP_TYPE ~= STATION_OP_TYPE.Putaway then
                        check_ok = false
                    end
                end
            end
        end
        if check_ok then
            -- 获取当前站台正在作业的，已经待启动的作业数量
            local count
            -- 作业状态 = 待启动，执行，错误，暂停，启动失败，等待 都算是站台任务
            local strCondition = "N_B_STATE IN(0,1,3,4,5,6) AND S_STATION_NO = '"..station_code.."'"
            nRet, count = m3.GetDataObjCount( strLuaDEID, "Operation", strCondition )
            if nRet ~= 0 then 
                return 1, "m3.GetDataObjCount 失败!"..count
            end
            local station = {
                station_no = station_code,
                op_count = count,
                max_op = station_data.N_MAX_OP_NUM
            }
            table.insert(station_list, station)
        end
    end

    if #station_list == 0 then
        return 0, "", "建议分配可能被禁用或和当前的作业模式不匹配"        -- 无法分配站台
    end

    -- 根据站台分配策略分配适合的站台
    if strategy.model == "PRIO_FEWER_TASKS" then
        -- 优先选择任务较少的站台
        table.sort( station_list, function(a, b) return a.op_count < b.op_count end )
    end

    for _, station in ipairs(station_list) do
        if station.op_count < station.max_op then
            return 0, station.station_no, ""
        end
    end

    return 0, "", "站台忙，每个站台的任务都已经到极限"               
end

return wms_station