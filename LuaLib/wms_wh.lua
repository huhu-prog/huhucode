--[[
    版本：     Version 3.0
    创建日期： 2025-1-29
    修改日期:  2026-6-19
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    名称:   wms_wh
    功能：   整合了【仓库】【库区】【货位】【巷道】这些仓库基础构成对象相关的操作


    【仓库】
        GetWarehouse              — 通过工厂标识获取仓库列表
        GetMyFactoryWarehouse     — 获取当前操作人员对应的工厂仓库

    【库区】
        GetArea                   — 通过仓库获取下面的库区
        Area_GetInfo              — 通过货区编码获取货区信息
        GetAreaInfo               — 从内存获取库区信息
        GetAreaInfo2              — 批量获取库区信息
        GetAreaInfo3              — 从内存获取库区信息

    【货位查询】
        GetLocInfo                — 从内存获取货位信息
        GetLocInfo2               — 从内存获取货位信息（返回table属性为字段名）
        Location_GetInfo          — 通过货位编码获取货位信息
        Location_Reset            — 重新设置货位信息
        GetFewestTaskLoc_InArea   — 获取库区里Task最少的货位（已作废）
        GetFewestTaskLoc_InArea2  — 获取库区里Task最少的货位（已取消）
        Get_MinimumTaskLoc_InArea — 获取库区里Task最少的货位
        GetAreaMostEmptyLoc       — 获取库区中最空的货位
        GetLocCodeByCNTR          — 通过容器编号找出货位
        GetLocByCNTR              — 根据容器编码获取货位对象
        GetLocCodeByRCL           — 根据行列层获取货位
        GetEmptyLocInAisle        — 获取巷道中的空货位
        GetEmptyLocNum            — 获取空货位数量
        GetLocAisle               — 获取货位所属巷道
        Get_Area_OneFuncLoc       — 获取库区的一个功能货位
        Loc_CheckUsability        — 检查货位是否可用

    【货位绑定】
        Loc_Container_Binding     — 货位和容器绑定
        Loc_Container_Unbinding   — 货位和容器解绑
        Get_CNTR_ByLocCode        — 根据货位获取绑定的容器列表

    【逻辑库区/巷道】
        GetZoneListByGroup        — 根据分组获取库区里的逻辑库区
        GetAreaZoneList           — 获取库区里的逻辑库区
        GetAisleList              — 获取库区里的巷道列表
        GetAisleZoneCodeSet       — 获取巷道中的逻辑库区编码集合
        CheckAisle                — 检查巷道是否存在
        GetAisleInfo              — 从内存获取巷道数据
        GetAisleTaskNum           — 获取巷道正在执行的任务数量
        Get_Zone_OneFuncArea      — 获取逻辑库区的一个功能库区

    更改记录:
        2025-1-29  HAN  创建
        2026-6-19        整理函数清单，添加 @tparam/@treturn 注解

    AI CHECK:
        -- 20260619
--]]

wms_base = require ("wms_base")
wms_cntr = require ("wms_container")

local wms_wh = {_version = "0.2.1"}

-- 通过工厂标识获取仓库列表
-- @function wms_wh.GetWarehouse
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string factory 工厂标识
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table choic_items 仓库编码数组
function wms_wh.GetWarehouse( strLuaDEID, factory )
    local nRet, strRetInfo
    local strCondition
    local strOrder = 'S_CODE'
    local choic_items = {}

    if factory == nil or factory == '' then 
        return 1, "工厂标识不能为空!" 
    end

    strCondition = "S_FACTORY = '"..factory.."'"
    nRet, strRetInfo = mobox.queryDataObjAttr(strLuaDEID, "Warehouse", strCondition, strOrder,"S_CODE" )
    if nRet ~= 0 then 
        return 1, "获取【仓库】信息失败! " .. strRetInfo 
    end
    if strRetInfo ~= ''  then
        local warehouse = {}
        local nCount
        local success
        local attrs
        success, warehouse = pcall( json.decode, strRetInfo)
        if success == false  then 
            return 1, "获取【仓库】信息失败! 非法的JSON格式!"..warehouse 
        end

        nCount = #warehouse
        for n = 1, nCount do
            attrs = warehouse[n].attrs
            table.insert( choic_items, attrs[1].value )
        end
    end
    return 0, choic_items
end

-- 获取当前登录者所在工厂的仓库列表
-- @function wms_wh.GetMyFactoryWarehouse
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number nRet 0: 成功，1/2: 失败
-- @treturn table choic_items 仓库编码数组
function wms_wh.GetMyFactoryWarehouse( strLuaDEID )
    local nRet, strRetInfo

    local strUserLogin, strUserName
    nRet, strUserLogin, strUserName = mobox.getCurUserInfo( strLuaDEID )
    if nRet ~= 0  then
        return 2, "获取当前操作人员信息失败! "..strUserLogin
    end
    -- 获取当前操作人员的单位编码，作为工厂标识
    nRet, strRetInfo = mobox.getUserSectionUnit( strUserLogin )
    if nRet ~= 0  then
        return 2, "获取当前操作人员所属单位失败! "..strRetInfo
    end
    local factory
    if strRetInfo ~= ''  then
        local orgInfo = json.decode( strRetInfo ) 
        factory = orgInfo.company_code
    else
        nRet, factory = wms_base.Get_sConst2( "WMS_Default_Factory" )
        if nRet ~= 0  then
            return 1, "系统无法获取常量'WMS_Default_Factory'"
        end          
    end

    local choic_items = {}

    if factory ~= ''  then
        local strCondition
        local strOrder = 'S_CODE'
        strCondition = "S_FACTORY = '"..factory.."'"
        nRet, strRetInfo = mobox.queryDataObjAttr(strLuaDEID, "Warehouse", strCondition, strOrder,"S_CODE" )
        if nRet ~= 0 then
            return 1, "获取【仓库】信息失败! " .. strRetInfo
        end
        if strRetInfo ~= ''  then
            local warehouse = {}
            local nCount
            local success
            local attrs
            success, warehouse = pcall( json.decode, strRetInfo)
            if success == false  then
                return 2, "获取【仓库】信息失败! 非法的JSON格式!"..warehouse
            end

            nCount = #warehouse
            -- 组织下拉列表选项
            for n = 1, nCount do
                attrs = warehouse[n].attrs
                table.insert( choic_items, attrs[1].value )
            end
        end
    end  
    return 0, choic_items  
end

-- 通过仓库获取下面的库区，可输入库区类型
-- @function wms_wh.GetArea
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string wh_code 仓库编码
-- @tparam string/number area_type 库区类型（类型名称或数值）
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table choic_items 库区编码数组
function wms_wh.GetArea( strLuaDEID, wh_code, area_type )
    local nRet, strRetInfo
    local strCondition
    local strOrder = 'S_CODE'
    local choic_items = {}

    if wh_code == nil or wh_code == '' then
        return 1, "仓库编码不能为空!"
    end
    if area_type == nil or  area_type == ''  then 
        strCondition = "S_WH_CODE = '"..wh_code.."'" 
    elseif type(area_type) == "number"  then
        strCondition = "S_WH_CODE = '"..wh_code.."' AND N_TYPE = "..area_type
    else
        strCondition = "S_WH_CODE = '"..wh_code.."' AND N_TYPE = "..wms_base.Get_nConst( strLuaDEID, area_type )
    end

    nRet, strRetInfo = mobox.queryDataObjAttr(strLuaDEID, "Area", strCondition, strOrder,"S_CODE" )
    if nRet ~= 0 then
        return 1,  "获取【库区】信息失败! " .. strRetInfo
    end
    if strRetInfo ~= ''  then
        local area = {}
        local nCount
        local success
        local attrs
        success, area = pcall( json.decode, strRetInfo)
        if success == false  then
            return 1, "获取【库区】信息失败! 非法的JSON格式!"..area
        end

        nCount = #area
        for n = 1, nCount do
            attrs = area[n].attrs
            table.insert( choic_items, attrs[1].value )
        end
        return 0, choic_items
    end
    return 0, ""
end


-- 任务数量排序比较函数（table.sort 使用），数量少的优先
-- @function sort_count
-- @tparam table a {count: n}
-- @tparam table b {count: n}
-- @treturn boolean a.count < b.count
local function sort_count( a, b )
    return a.count < b.count
end
-- 作废不建议使用
-- 获取库区里Task数量最少的货位（已作废，不建议使用）
-- @function wms_wh.GetFewestTaskLoc_InArea
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @tparam string loc_attr 统计任务数量的货位属性
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string loc_code 货位编码
function wms_wh.GetFewestTaskLoc_InArea( strLuaDEID, area_code, loc_attr )
    local nRet, strRetInfo
    if area_code == nil or  area_code == ''  then 
        return 1, "wms_wh.GetFewestTaskLoc_InArea 函数中 area_code 不能为空或nil! "
    end
    if loc_attr == nil or  loc_attr == ''  then 
        return 1,  "wms_wh.GetFewestTaskLoc_InArea 函数中 loc_attr 不能为空或nil! "
    end

    -- 首先获取目前area_code库区中在 loc_attr 没有任务的货位
    local strCond
    strCond = "S_CODE IN ( Select S_CODE From TN_Location Where S_AREA_CODE = '"..area_code.."' ) AND "
    strCond = strCond.."S_CODE NOT IN ( Select ISNULL("..loc_attr..",'') From TN_Task Where N_B_STATE >= 0 AND N_B_STATE <= 2 )"
    nRet, strRetInfo = mobox.queryOneDataObjAttr(strLuaDEID, "Location", strCond, "S_CODE", "S_CODE" )
    if nRet ~= 0  then
        return 1, "获取【货位】信息失败! " .. strRetInfo
    end
    if strRetInfo ~= ''  then
        local ret_info = json.decode(strRetInfo)
        return 0, ret_info.attrs[1].value
    end

    -- 货位都有任务，找出任务数量最少的货位
    strCond = " N_B_STATE >= 0 AND N_B_STATE <= 2 AND "..loc_attr.." IN ( Select S_CODE From TN_Location Where S_AREA_CODE = '"..area_code.."' )"
    nRet, strRetInfo = mobox.getDataObjGroupCount( strLuaDEID, "Task", loc_attr, strCond )
    if nRet ~= 0  then
        return 1, "getDataObjGroupCount失败! " .. strRetInfo
    end
    if strRetInfo == ''  then
        return ""
    end
    -- 解析返回的字符串 [ { "value": "", "count": X }, ... ]
    local loc_count_array = json.decode(strRetInfo)
    -- 排序最少的放前面
    if loc_count_array == nil or #loc_count_array == 0 then
        return 0, ""
    end
    table.sort( loc_count_array, sort_count )
    return 0, loc_count_array[1].value    
end

-- 获取在库区里Task数量最少的货位
-- @function wms_wh.Get_MinimumTaskLoc_InArea
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @tparam string loc_attr 统计任务数量的货位属性
-- @treturn number nRet 0: 成功，2: 失败
-- @treturn string loc_code 货位编码
function wms_wh.Get_MinimumTaskLoc_InArea( strLuaDEID, area_code, loc_attr )
    local nRet, strRetInfo
    if area_code == nil or  area_code == ''  then 
        return 1, "wms_wh.Get_MinimumTaskLoc_InArea 函数中 area_code 不能为空或nil! "
    end
    if loc_attr == nil or  loc_attr == ''  then 
        return 2, "wms_wh.Get_MinimumTaskLoc_InArea 函数中 loc_attr 不能为空或nil! "
    end

    -- 首先获取目前area_code库区中在 loc_attr 没有任务的货位 -- 下面这个SQL 有待讨论
    local strCond
    strCond = "S_CODE IN ( Select S_CODE From TN_Location Where S_AREA_CODE = '"..area_code.."' ) AND "
    strCond = strCond.."S_CODE NOT IN ( Select ISNULL("..loc_attr..",'') From TN_Task Where N_B_STATE >= 0 AND N_B_STATE <= 2 )"
    nRet, strRetInfo = mobox.queryOneDataObjAttr(strLuaDEID, "Location", strCond, "S_CODE", "S_CODE" )
    if nRet ~= 0  then
        return 2, "获取【货位】信息失败! " .. strRetInfo 
    end
    if strRetInfo ~= ''  then
        local ret_info = json.decode(strRetInfo)
        return 0, ret_info.attrs[1].value
    end

    -- 货位都有任务，找出任务数量最少的货位
    strCond = " N_B_STATE >= 0 AND N_B_STATE <= 2 AND "..loc_attr.." IN ( Select S_CODE From TN_Location Where S_AREA_CODE = '"..area_code.."' )"
    nRet, strRetInfo = mobox.getDataObjGroupCount( strLuaDEID, "Task", loc_attr, strCond )
    if nRet ~= 0  then
        return 2, "getDataObjGroupCount失败! " .. strRetInfo
    end
    if strRetInfo == ''  then
        return ""
    end
    -- 解析返回的字符串 [ { "value": "", "count": X }, ... ]
    local loc_count_array = json.decode(strRetInfo)
    -- 排序最少的放前面
    if loc_count_array == nil or #loc_count_array == 0 then
        return 0, ""
    end
    table.sort( loc_count_array, sort_count )
    return 0, loc_count_array[1].value    
end

-- 获取库区里Task数量最少的货位（调用Get_MinimumTaskLoc_InArea，已取消）
-- @function wms_wh.GetFewestTaskLoc_InArea2
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @tparam string loc_attr 货位属性
-- @treturn number nRet 0: 成功
-- @treturn string loc_code 货位编码
function wms_wh.GetFewestTaskLoc_InArea2( strLuaDEID, area_code, loc_attr )
    local nRet, strRetInfo
    nRet, strRetInfo = wms_wh.Get_MinimumTaskLoc_InArea( strLuaDEID, area_code, loc_attr )
    return nRet, strRetInfo
end

-- 获取库区/逻辑库区中最空的货位
-- @function wms_wh.GetAreaMostEmptyLoc
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cls_id 对象类型 (Area/Zone)
-- @tparam string area_code 库区编码
-- @treturn number nRet 0: 成功，1/2: 失败
-- @treturn table loc_info 货位信息对象
function wms_wh.GetAreaMostEmptyLoc( strLuaDEID, cls_id, area_code )
    local nRet, strRetInfo

    nRet, strRetInfo = wms.wms_GetAreaMostEmptyLoc ( strLuaDEID, cls_id, area_code )
    if nRet ~= 0  then
        return 2, "获取分拣区'"..area_code.."'的最大可入库容量货位失败!"..strRetInfo
    end

    -- 如果没用空闲返回 1
    if strRetInfo == '' then
        return 1, ""
    end

    local loc_info, success
    success, loc_info = pcall( json.decode, strRetInfo )
    if success == false  then
        return 2, "wms_GetAreaMostEmptyLoc 返回的的JSON格式不合法!" 
    end
    return  0, loc_info    
end

-- 通过货位编码获取货位信息
-- @function wms_wh.Location_GetInfo
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string loc_code 货位编码
-- @treturn number nRet 0: 成功，2: 失败
-- @treturn table object 货位数据对象（含id）
function wms_wh.Location_GetInfo( strLuaDEID, loc_code )
    if loc_code == nil or loc_code == ''  then
        return 1, "wms_wh.Location_GetInfo 货位号不能为空!"
    end

    local nRet, strRetInfo, id
    local strCondition = "S_CODE = '"..loc_code.."'"
    nRet, id, strRetInfo = mobox.getDataObjAttrByKeyAttr( strLuaDEID, "Location", strCondition )

    if nRet ~= 0  then
        -- 如果发生错误，返回2个参数
        return 2, "getDataObjAttrByKeyAttr 失败! loc_code = '"..loc_code.."'  "..id
    end

    nRet, strRetInfo = mobox.objAttrsToLuaJson( "Location", strRetInfo )
    if nRet ~= 0   then
        return 2, "objAttrsToLuaJson Location 失败!"..strRetInfo
    end

    local object, success
    success, object = pcall( json.decode, strRetInfo )
    if success == false  then
        return 2, "objAttrsToLuaJson('Location') 返回的的JSON格式不合法!"
    end
    object.id = id
    return 0, object
end

-- 直接从内存获取货位信息, 返回的是 lua 属性
-- @function wms_wh.GetLocInfo
-- @tparam string loc_code 货位编码
-- @treturn number nRet 0: 成功，1/2: 失败
-- @treturn table object 货位信息对象
function wms_wh.GetLocInfo( loc_code )
    local nRet, strRetInfo
    
    if loc_code == nil or loc_code == ''  then
        return 1, "wms_wh.GetLocInfo 函数 loc_code 不能为nil或空!"
    end
    nRet, strRetInfo = wms.wms_GetLocInfo( loc_code )
    if nRet ~= 0  then
        return nRet, strRetInfo
    end

    local object, success
    success, object = pcall( json.decode, strRetInfo )
    if success == false  then
        return 2, "wms_GetLocInfo 返回的的JSON格式不合法!"
    end
    return 0, object    
end

-- 直接从内存获取货位信息, 返回的是数据表字段属性
-- @function wms_wh.GetLocInfo2
-- @tparam string loc_code 货位编码
-- @treturn number nRet 0: 成功，1/2: 失败
-- @treturn table object 货位信息对象
function wms_wh.GetLocInfo2( loc_code )
    local nRet, strRetInfo
    
    if loc_code == nil or loc_code == ''  then
        return 1, "wms_wh.GetLocInfo 函数 loc_code 不能为nil或空!"
    end
    local nRet, loc_data = m3.GetDataFromCache( "Location", loc_code )
    if nRet ~= 0  then
        return nRet, loc_data
    end
    return 0, loc_data
end

-- 重新设置货位信息（容器数量，锁状态）
-- @function wms_wh.Location_Reset
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string loc_code 货位编码
-- @treturn number nRet 0: 成功，2: 失败
function wms_wh.Location_Reset( strLuaDEID, loc_code )
    local nRet, strRetInfo

    if loc_code == nil or loc_code == '' then
        return 2, "Location_Reset 的输入参数  loc_code 必须有值!"
    end
    local loc_obj
    nRet, loc_obj = wms_wh.Location_GetInfo( strLuaDEID, loc_code )
    if nRet ~= 0 then
        return 2, "Location_GetInfo 失败!"..loc_obj
    end

    -- 获取货位绑定的容器数量
    local strCondition = "S_LOC_CODE = '"..loc_code.."'"
    nRet, strRetInfo = mobox.getDataObjCount( strLuaDEID, "Loc_Container", strCondition )
    if nRet ~= 0 then 
        return nRet, strRetInfo 
    end 
    local cntr_num = lua.StrToNumber( strRetInfo ) 

    -- 如果货位有锁，进一步检查锁定的作业是否正常
    local lock_state = loc_obj.lock_state
    local lock_op = loc_obj.lock_op or ''

    if loc_obj.lock_state ~= 0 then
        local data_objs

        strCondition = "N_OBJ_TYPE = 1 AND S_OBJ_CODE = '"..loc_code.."'"
        nRet, data_objs = m3.QueryDataObject(strLuaDEID, "Lock", strCondition )
        if nRet ~= 0 then 
            return 2, "QueryDataObject失败!"..data_objs
        end
        if data_objs == ''  then 
            lock_state = 0
            lock_op = ''
        else
            local lock = m3.KeyValueAttrsToObjAttr(data_objs[1].attrs)
            if lock == nil then
                return 1, "KeyValueAttrsToObjAttr 失败!"
            end
            local op_code = lock.op_code or ''
            
            if op_code ~= '' then
                strCondition = "S_CODE = '"..op_code.."'"
                nRet, data_objs = m3.QueryDataObject(strLuaDEID, "Operation", strCondition )
                if nRet ~= 0 then 
                    return 2, "QueryDataObject失败!"..data_objs
                end   
                if data_objs == '' then
                    -- 作业已经不存在
                    lock_state = 0
                    lock_op = ''                    
                else
                    local op = m3.KeyValueAttrsToObjAttr(data_objs[1].attrs)
                    if op == nil then
                        return 1, "KeyValueAttrsToObjAttr 失败!"
                    end
                    if op.b_state == OPERATION_STATE.Finish or
                       op.b_state == OPERATION_STATE.Cancel then
                        lock_state = 0
                        lock_op = ''                          
                    end
                end
            end
        end
    end

    local strUpdateSql = "N_CURRENT_NUM = "..cntr_num..", N_LOCK_STATE = "..lock_state..", S_LOCK_OP = '"..lock_op.."'"
    strCondition = "S_CODE = '"..loc_code.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Location", strCondition, strUpdateSql )
    if nRet ~= 0 then 
        return 2, "更新【Location】信息失败!"..strRetInfo
    end            
    return 0    
end

-- 从内存获取库区信息（不建议使用，建议用 GetAreaInfo3）
-- @function wms_wh.GetAreaInfo
-- @tparam string area_code 库区编码
-- @treturn number nRet 0: 成功，1/2: 失败
-- @treturn table object 库区信息对象
function wms_wh.GetAreaInfo( area_code )
    local nRet, strRetInfo
    if area_code == nil or area_code == ''  then
        return 1, "wms_wh.GetAreaInfo 函数 area_code 不能为nil或空!"
    end
    nRet, strRetInfo = wms.wms_GetAreaInfo( area_code )
    if nRet ~= 0  then
        return nRet, strRetInfo
    end

    local object, success
    success, object = pcall( json.decode, strRetInfo )
    if success == false  then
        return 2, "wms_GetAreaInfo 返回的的JSON格式不合法!"
    end
    return 0, object    
end

-- 从内存获取库区信息（数据类驻留内存方法）
-- @function wms_wh.GetAreaInfo3
-- @tparam string area_code 库区编码
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table area_data 库区数据对象
function wms_wh.GetAreaInfo3( area_code )

    if area_code == nil or area_code == ''  then
        return 1, "wms_wh.GetAreaInfo 函数 area_code 不能为nil或空!"
    end
    local nRet, area_data = m3.GetDataFromCache( "Area", area_code )
    if nRet ~= 0  then
        return nRet, area_data
    end
    return 0, area_data    
end

-- 批量获取多个库区信息
-- @function wms_wh.GetAreaInfo2
-- @tparam table area_code_array 库区编码数组
-- @treturn number nRet 0: 成功，1/2: 失败
-- @treturn table area_info 库区信息数组
function wms_wh.GetAreaInfo2( area_code_array )
    local nRet, strRetInfo

    if area_code_array == nil or type(area_code_array) ~= 'table'  then
        return 1, "wms_wh.GetAreaInfo2 函数 area_code_array 不能为 nil 必须是一个字符串数组! 123"
    end
    nRet, strRetInfo = wms.wms_GetAreaInfo2( lua.table2str(area_code_array) )
    if nRet ~= 0  then
        return nRet, "wms_GetAreaInfo2 失败!"..strRetInfo
    end

    local area_info, success
    success, area_info = pcall( json.decode, strRetInfo )
    if success == false  then
        return 2, "wms_GetAreaInfo 返回的的JSON格式不合法!"
    end
    return 0, area_info    
end


-- 通过容器编号找出货位（不建议使用）
-- @function wms_wh.GetLocCodeByCNTR
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strCntrCode 容器编码
-- @treturn string loc_code 货位编码，失败返回空串
function wms_wh.GetLocCodeByCNTR( strLuaDEID, strCntrCode )
    if strCntrCode == nil or  strCntrCode == '' then
        return ""
    end
    local strCondition = "S_CNTR_CODE = '"..strCntrCode.."'"
    local strOrder = "" 
    local nRet, strRetInfo

    nRet, strRetInfo = mobox.queryOneDataObjAttr(strLuaDEID, "Loc_Container", strCondition, strOrder, "S_LOC_CODE" )
    if nRet ~= 0 or strRetInfo == ""  then
        return ""
    end

    local ret_info = json.decode(strRetInfo)
    return ret_info.attrs[1].value
end

-- 获取货位绑定的容器列表
-- @function wms_wh.Get_CNTR_ByLocCode
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strLocCode 货位编码
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table cntr_list 容器编码数组 {"X1","X2"}
function wms_wh.Get_CNTR_ByLocCode( strLuaDEID, strLocCode )
    local nRet, strRetInfo

    if strLocCode == nil or  strLocCode == '' then
        return 1, "wms_wh.Get_CNTR_ByLocCode 中的 strLocCode 不能为空或nil"
    end
    local strCondition = "S_LOC_CODE = '"..strLocCode.."'"
    local strOrder = "N_BIND_ORDER" 
    local cntr_list = {}

    nRet, strRetInfo = mobox.queryDataObjAttr(strLuaDEID, "Loc_Container", strCondition, strOrder )
    if nRet ~= 0 then
        return 1, "获取【货位容器绑定】信息失败! " .. strRetInfo
    end
    if strRetInfo == "" then
         return 0, cntr_list
    end

    local retObjs = json.decode( strRetInfo )
    local nCount = #retObjs
    local loc_container

    for n = 1, nCount do
        nRet, loc_container = m3.ObjAttrStrToLuaObj( "Loc_Container", lua.table2str(retObjs[n].attrs) )
        if nRet ~= 0  then
            return 1, "m3.ObjAttrStrToLuaObj 失败! "..loc_container
        end
 
        table.insert( cntr_list, loc_container.cntr_code )     
    end 
    return 0, cntr_list
end

-- 通过行列层获取货位编码
-- @function wms_wh.GetLocCodeByRCL
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @tparam number row 行
-- @tparam number col 列
-- @tparam number layer 层
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string loc_code 货位编码
function wms_wh.GetLocCodeByRCL( strLuaDEID, area_code, row, col, layer )
    if area_code == nil or  area_code == '' then
        return 1, "wms_wh.GetLocCodeByRCL 中参数 area_code 不能为空或nil"
    end
    local strCondition = "S_AREA_CODE = '"..area_code.."' AND N_ROW = "..row.." AND N_COL = "..col.." AND N_LAYER = "..layer
    local strOrder = "" 
    local nRet, strRetInfo

    nRet, strRetInfo = mobox.queryOneDataObjAttr(strLuaDEID, "Location", strCondition, strOrder, "S_CODE" )
    if nRet ~= 0 then
        return 1, "获取【Location】信息失败! " .. strRetInfo
    end
    if strRetInfo == "" then
        return 0, ""
    end
    local ret_info = json.decode(strRetInfo)
    return 0, ret_info.attrs[1].value
end

-- 根据容器编码获取货位对象（不建议使用）
-- @function wms_wh.GetLocByCNTR
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strCntrCode 容器编码
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table loc 货位对象
function wms_wh.GetLocByCNTR( strLuaDEID, strCntrCode )
    local nRet, strRetInfo

    local loc_code = wms_wh.GetLocCodeByCNTR( strLuaDEID, strCntrCode )
    if loc_code == "" then
        return ""
    end

    local loc
    nRet, loc = wms_wh.GetLocInfo( loc_code )
    if nRet ~= 0  then
        return ""
    end
    
    return loc
end

-- 货位和容器进行绑定
-- @function wms_wh.Loc_Container_Binding
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strLocCode 货位编码
-- @tparam string strCntrCode 容器编码
-- @tparam string/number strBind_method 绑定方法（常量名或数值）
-- @tparam string strSource 来源
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string result Loc_Container的ID
function wms_wh.Loc_Container_Binding( strLuaDEID, strLocCode, strCntrCode, strBind_method, strSource )
    local nRet
    local location = {}
    local bind_method
    if type(strBind_method) == "string" then
        bind_method = wms_base.Get_nConst(strLuaDEID, strBind_method )
    else
        bind_method = strBind_method
    end

    -- 对货位进行判断是否可以进行绑定
    nRet, location = wms_wh.Location_GetInfo( strLuaDEID, strLocCode )
    if nRet ~= 0  then
         return 1, 'wms_wh.Location_GetInfo 失败!'..location
    end
    if location.enable == 'N'  then
        return 1, "货位'"..strLocCode.."'未启用!"
    end
    if location.cur_num >= location.capacity  then
        return 1, "货位'"..strLocCode.."'的容量已满!["..location.cur_num..","..location.capacity.."]"
    end
    -- 如果 容器 已经和别的货位进行了绑定，就不能和这个货位进行绑定
    local loc_code
    nRet, loc_code = wms_cntr.Get_Container_Loc( strLuaDEID, strCntrCode )
    if nRet ~= 0 or loc_code ~= '' then 
        return 1, "容器'"..strCntrCode.."'已经和货位'"..loc_code.."'绑定!" 
    end
    
    local loc_cntr = m3.AllocObject(strLuaDEID,"Loc_Container")
    loc_cntr.loc_code = strLocCode
    loc_cntr.cntr_code = strCntrCode
    loc_cntr.bind_order = location.cur_num + 1
    loc_cntr.bind_method = bind_method
    loc_cntr.src = strSource
    -- 注意创建数据类【Loc_Container】会触发创建后事件，这里会调用  wms_ContainerLocAction
    nRet, loc_cntr = m3.CreateDataObj( strLuaDEID, loc_cntr )

    if nRet ~= 0  then
        return nRet, "CreateDataObj失败! "..loc_cntr
    end
    return 0, loc_cntr.id
end

-- 货位和容器解绑
-- @function wms_wh.Loc_Container_Unbinding
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strLocCode 货位编码
-- @tparam string strCntrCode 容器编码
-- @tparam string/number strUnbinding_method 解绑方法（常量名或数值）
-- @tparam string strSource 来源
-- @treturn number nRet 0: 成功，非0: 失败
-- @treturn string result "ok"或错误信息
function wms_wh.Loc_Container_Unbinding( strLuaDEID, strLocCode, strCntrCode, strUnbinding_method, strSource )
    local nRet, strRetInfo, strErr

    local unbinding_method
    if type(strUnbinding_method) == "string" then    
        unbinding_method = wms_base.Get_nConst(strLuaDEID, strUnbinding_method )
    else
        unbinding_method = strUnbinding_method
    end

    -- 把解绑方式，解绑来源加到全局变量中，在 Loc_Container 删除后事件上会用到
    local strGlobalAttr = '[{"attr":"N_BINDING_METHOD","value":"'..unbinding_method..'"},{"attr":"S_ACTION_SRC","value":"'..strSource..'"}]'
    mobox.setGlobalAttr( strLuaDEID, strGlobalAttr )

    local strCondition = "S_LOC_CODE = '"..strLocCode.."' AND S_CNTR_CODE = '"..strCntrCode.."'"
    -- 删除数据对象【Loc_Container】会触发该数据类的删除后事件，事件会调用函数 wms_ContainerLocAction
    nRet, strRetInfo = mobox.deleteDataObject( strLuaDEID, "Loc_Container", strCondition )
    if nRet ~= 0 then
        strErr = "删除【货位容器绑定】失败!  "..strRetInfo
        return nRet, strErr
    end
    return 0,"ok" 
end

-- 检查货位是否可用
-- @function wms_wh.Loc_CheckUsability
-- @tparam table location 货位对象 {code, enable, lock_state, cur_num, capacity}
-- @treturn number nRet 0: 可用，1: 不可用
-- @treturn string strRetInfo 不可用的原因
function wms_wh.Loc_CheckUsability( location )
    if location.enable == 'N'  then
        return 1, "货位'"..location.code.."'未启用!"
    end
    if location.lock_state ~= 0  then
        return 1, "货位'"..location.code.."'已经被其它业务锁定!"
    end
    if location.cur_num >= location.capacity  then
        return 1, "货位空间不足'"..location.code.."'已绑定其它容器!" 
    end
    return 0, ""
end


-- 通过货区编码获取货区信息
-- @function wms_wh.Area_GetInfo
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @treturn number nRet 0: 成功，1: 不存在，2: 错误
-- @treturn table object 货区数据对象（含id）
function wms_wh.Area_GetInfo( strLuaDEID, area_code )
    if area_code == nil or area_code == ''  then
        return 1, "调用 WMS_Area_GetBaseInfo 函数时参数不正确，库区编码不能为空!"
    end

    local nRet, strRetInfo, id
    local strCondition = "S_CODE = '"..area_code.."'"
    nRet, id, strRetInfo = mobox.getDataObjAttrByKeyAttr( strLuaDEID, "Area", strCondition )
    if nRet == 1  then
        return 1, "库区编码='"..area_code.."'的库区不存在!"
    end
    if nRet ~= 0   then
        return 2, "getDataObjAttrByKeyAttr 发生错误!"..id
    end

    nRet, strRetInfo = mobox.objAttrsToLuaJson( "Area", strRetInfo )
    if nRet ~= 0   then
        return 2, "objAttrsToLuaJson Area 失败!"..strRetInfo
    end

    local object, success
    success, object = pcall( json.decode, strRetInfo )
    if success == false  then
        return 1, "objAttrsToLuaJson('Area') 返回的的JSON格式不合法!"..strRetInfo
    end
    object.id = id
    return 0, object
end

-- 获取库区里的逻辑库区列表
-- @function wms_wh.GetZoneListByGroup
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @tparam string group 分組名
-- @tparam boolean bNoLock 是否排除禁用锁（可选）
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string items 逻辑库区编码JSON数组 ["z1","z2"]
function wms_wh.GetZoneListByGroup( strLuaDEID, area_code, group, bNoLock )
    local nRet, strRetInfo, strCondition
    local strOrder = "S_CODE"

    if bNoLock == nil  then
        bNoLock = false
    else
        bNoLock = true
    end

    if area_code == nil or area_code == ''  then
        return 1, "调用 wms_wh.GetZoneListByGroup 函数时参数不正确，库区编码不能为空!"
    end
    if group == nil or group == ''  then
        return 1, "调用 wms_wh.GetZoneListByGroup 函数时参数不正确，分组不能为空!"
    end

    strCondition = "S_AREA_CODE = '"..area_code.."' AND S_GROUP = '"..group.."'"
    if bNoLock  then
        -- 并且 没有在逻辑库区加禁用锁 
        strCondition = strCondition.." AND S_CODE NOT IN ( select S_OBJ_CODE from TN_Lock where N_OBJ_TYPE = 2 and N_TYPE = 3 )"
    end
    nRet, strRetInfo = mobox.queryDataObjAttr(strLuaDEID, "Zone", strCondition, strOrder, "S_CODE" )
    if nRet ~= 0 then
        return 1, "获取【逻辑库区】信息失败! " .. strRetInfo
    end
    if strRetInfo ~= ''  then
        local zone = {}
        local nCount
        local success
        local attrs
        local items = '['

        success, zone = pcall( json.decode, strRetInfo)
        if success == false  then
            return 1, "获取【仓库】信息失败! 非法的JSON格式!"..zone
        end
        nCount = #zone
        if nCount == 0  then
            return 0,""
        end
        for n = 1, nCount do
            attrs = zone[n].attrs
            items = items..'"'..attrs[1].value..'",'
        end
        items = lua.trim_laster_char( items )..']'
        return 0, items
    end
    return 0, ""
end


-- 根据库区编码获取库区中的逻辑库区
-- @function wms_wh.GetAreaZoneList
-- @tparam string area_code 库区编码
-- @tparam string strZoneGroup 逻辑库区分类（可选）
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table zone 逻辑库区编码数组
function wms_wh.GetAreaZoneList( area_code, strZoneGroup )
    local nRet, strRetInfo

    if strZoneGroup == nil or strZoneGroup == ''  then
        nRet, strRetInfo = wms.wms_GetAreaZoneList(area_code)
    else
        nRet, strRetInfo = wms.wms_GetAreaZoneList(area_code, strZoneGroup)
    end
    if nRet ~= 0 then
        return 1, "wms_GetAreaZoneList 失败!"..strRetInfo
    end
    -- 返回字符串 [{ "id": "", "code": "", "name": "", "group": "" }]
    if strRetInfo == '' then
        return 0, ""
    end
    -- 获取系统计算出来的 货位 及 接驳货位
    local success, ret_zone
    success, ret_zone = pcall( json.decode, strRetInfo )
    if success == false  then
        return 1, "wms_GetAreaZoneList 返回值为非法的JSON格式!"..ret_zone
    end

    local zone = {}
    for n = 1, #ret_zone do
        zone[n] = ret_zone[n].code
    end

    return 0, zone
end

-- 获取库区的一个功能区位
-- @function wms_wh.Get_Area_OneFuncLoc
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strAreaCode 库区编码
-- @tparam string strFuncType 功能位置类型
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table loc 功能货位对象
function wms_wh.Get_Area_OneFuncLoc( strLuaDEID, strAreaCode, strFuncType )

    local func_area_set = wms_base.Get_Area_FuncArea(strLuaDEID, strAreaCode, strFuncType )
    if #func_area_set > 1 then
        return 1, '不能超过一个!'
    end
    local func_area = func_area_set[1]
    if func_area.class ~= "Location" then
         return 1, '功能位置类型必须是货位'
    end

    local nRet, from_loc = wms_wh.GetLocInfo(func_area.code)
    if nRet ~= 0 then
        return 1, "WMS_GetLocInfo失败! " .. from_loc
    end
    return 0, from_loc
end

-- 获取逻辑库区的一个功能区域
-- @function wms_wh.Get_Zone_OneFuncArea
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strZoneCode 逻辑库区编码
-- @tparam string strFuncType 功能区域类型
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string area_code 物理库区编码
function wms_wh.Get_Zone_OneFuncArea( strLuaDEID, strZoneCode, strFuncType )
    if strZoneCode == nil or strZoneCode == ''  then
        return 1, "调用 wms_wh.Get_Zone_OneFuncArea 函数时参数不正确，库区编码不能为空!"
    end

    local func_area_set = wms_base.Get_Zone_FuncArea(strLuaDEID, strZoneCode, strFuncType )
    if #func_area_set > 1 then
        return 1, strFuncType..'不能超过一个!'
    end
    local func_area = func_area_set[1]
    if func_area.class ~= "Area" then
         return 1, strFuncType..'的类型必须是物理库区'
    end
    return 0, func_area.code
end

-- 获取库区里的巷道对象列表
-- @function wms_wh.GetAisleList
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @tparam boolean bNoLock 是否排除锁定巷道（可选）
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table return_data 巷道对象数组
function wms_wh.GetAisleList( strLuaDEID, area_code, bNoLock )
    local nRet, strRetInfo, strCondition
    local strOrder = "N_AISLE"

    if bNoLock == nil  then
        bNoLock = false
    else
        bNoLock = true
    end

    if area_code == nil or area_code == ''  then
        return 1, "调用 wms_wh.GetAisleList 函数时参数不正确，库区编码不能为空!"
    end

    strCondition = "S_AREA_CODE = '"..area_code.."'"
    if bNoLock  then
        strCondition = strCondition.." AND N_LOCK_STATE = 0"
    end
    nRet, strRetInfo = mobox.queryDataObjAttr(strLuaDEID, "Aisle", strCondition, strOrder )
    if nRet ~= 0 then
        return 1, "获取【巷道】信息失败! " .. strRetInfo
    end
    
    local return_data = {}
    if strRetInfo ~= ''  then
        local retObjs = json.decode( strRetInfo )

        for n = 1,  #retObjs do
            local aisle = {}
            nRet, aisle = m3.ObjAttrStrToLuaObj( "Aisle", lua.table2str(retObjs[n].attrs) )
            if nRet ~= 0  then
                return 1, "m3.ObjAttrStrToLuaObj(Aisle) 失败! "..aisle
            end
            aisle.id = lua.trim_guid_str( retObjs[n].id )
            aisle.cls = "Aisle"
            if nRet ~= 0  then
                return 1, "m3.ObjAttrStrToLuaObj(INV_Detail) 失败! "
            end
            return_data[n] = aisle
        end
    end
    return 0, return_data
end

-- 获取货位所在的巷道逻辑库区编码
-- @function wms_wh.GetLocAisle
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @tparam string loc_code 货位编码
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string zon_code 逻辑库区编码
function wms_wh.GetLocAisle( strLuaDEID, area_code, loc_code )
    local nRet, loc_info, strRetInfo

    -- 从内存获取货位的基础信息
    nRet, loc_info = wms_wh.GetLocInfo( loc_code )
    if nRet ~= 0  then
        return 1, "wms_wh.GetLocAisle 里获取货位信息失败"..loc_info
    end

    local strAisleName = "巷道"..loc_info.aisle

    -- 获取巷道名称 = strAisleName 的逻辑库区
    local strCondition = "S_AREA_CODE = '"..area_code.."' AND S_NAME = '"..strAisleName.."'"
    nRet, strRetInfo = mobox.queryDataObjAttr(strLuaDEID, "Zone", strCondition, strOrder, "S_CODE" )
    if nRet ~= 0  then
        return 1, "wms_wh.GetLocAisle 获取【逻辑库区】信息失败! " .. strRetInfo
    end
    if strRetInfo ~= ''  then
        local zone = {}
        local nCount
        local success
        local attrs

        success, zone = pcall( json.decode, strRetInfo)
        if success == false  then
            return 1, "wms_wh.GetLocAisle 获取【仓库】信息失败! 非法的JSON格式!"..zone
        end
        nCount = #zone
        if nCount == 0  then
            return ""
        end
        if nCount > 1  then
            return 1, "wms_wh.GetLocAisle: 货位'"..loc_code.."'不能在多个名为'"..strAisleName.."'的逻辑库区"
        end

        attrs = zone[1].attrs
        return attrs[1].value
    end

    return 0, ""    
end

-- 检查巷道对象属性是否完整
-- @function wms_wh.CheckAisle
-- @tparam table aisle_list 巷道对象列表
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string strInfo 检测结果
function wms_wh.CheckAisle( aisle_list )
    for n = 1, #aisle_list do
        if aisle_list[n].cls == nil or aisle_list[n].cls ~= "Aisle" then
            return 1, "wms_wh.CheckAisle 输入参数非法!"
        end
        if aisle_list[n].zone_code == nil or aisle_list[n].zone_code == "" then
            return 1, "【Aisle】对象中逻辑库区没关联!"
        end
        if aisle_list[n].left_deep == nil or aisle_list[n].left_deep == 0  then
            return 1, "【Aisle】对象中'左深'必须有值!"
        end
        if aisle_list[n].right_deep == nil or aisle_list[n].right_deep == 0  then
            return 1, "【Aisle】对象中'右深'必须有值!"
        end  
        if aisle_list[n].left_row_group == nil or aisle_list[n].left_row_group == 0  then
            return 1, "【Aisle】对象中'左排组号'必须有值!"
        end
        if aisle_list[n].right_row_group == nil or aisle_list[n].right_row_group == 0  then
            return 1, "【Aisle】对象中'右排组号'必须有值!"
        end  
        if aisle_list[n].aisle == nil or aisle_list[n].aisle == 0  then
            return 1, "【Aisle】对象中'巷道号'必须有值!"
        end                                 
    end
    return 0, ""
end

-- 获取巷道对象中的逻辑库区编码集合
-- @function wms_wh.GetAisleZoneCodeSet
-- @tparam table aisle_list 巷道对象列表
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table zone_code 逻辑库区编码数组
function wms_wh.GetAisleZoneCodeSet( aisle_list )
    local zone_code = {}

    for n = 1, #aisle_list do
        if aisle_list[n].cls == nil or aisle_list[n].cls ~= "Aisle" then
            return 1, "wms_wh.GetAisleZoneCodeSet 输入参数非法!"
        end
        if aisle_list[n].zone_code == nil or aisle_list[n].zone_code == "" then
            return 1, "【Aisle】对象中逻辑库区没关联!"
        end
        zone_code[n] = aisle_list[n].zone_code           
    end
    return 0, zone_code
end

-- 空货位排序比较函数：优先级小的优先，同优先级按列/层排序
-- @function empty_loc_sort
-- @tparam table a {priority, col, layer}
-- @tparam table b {priority, col, layer}
-- @treturn boolean a优先返回true，否则false
local function empty_loc_sort( a, b )
    if a.priority < b.priority  then
        return true
    elseif a.priority == b.priority  then
        if a.col < b.col  then
            return true
        elseif a.col == b.col  then
            return a.layer < b.layer
        else
            return false
        end
    else
        return false
    end
end

-- 从货位分组表查询空货位并加入结果集
-- @function get_empty_loc_by_loc_group
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strCondition 查询条件
-- @tparam table empty_loc_set 空货位结果集（引用参数）
-- @tparam table index 索引计数器（引用参数）
-- @tparam number priority 优先级
-- @treturn number nRet 0: 成功
-- @treturn string strRetInfo 失败时为错误信息
local function get_empty_loc_by_loc_group(  strLuaDEID, strCondition, empty_loc_set, index, priority )
    local nRet, strRetInfo
    local strOrder = "N_COL, N_LAYER"   -- 最近巷道口 

    -- 最多获取 10 条
    nRet, strRetInfo = mobox.queryDataObjAttr3( strLuaDEID, "Location_Group", strCondition, 10, strOrder )
    if nRet ~= 0  then
        return 1, "获取货位组信息错误! "..strRetInfo 
    end

    if strRetInfo ~= '' then
        local loc_group
        local retObjs = json.decode( strRetInfo )

        for n = 1, #retObjs do
            nRet, loc_group = m3.ObjAttrStrToLuaObj( "Location_Group", lua.table2str(retObjs[n].attrs) )
            if nRet ~= 0  then
                return 1, "m3.ObjAttrStrToLuaObj(Location_Group) 失败! "..loc_group
            end
            -- 获取同一个穴的2个货位，判断外深位是否为空
            strCondition = "N_CURRENT_NUM = 0 AND N_POS = 2 AND N_LOCK_STATE = 0 AND S_AREA_CODE = '"..area_code.."' AND N_ROW_GROUP = "..loc_group.row_group
            strCondition = strCondition.." N_COL = "..loc_group.col.." AND N_LAYER = "..loc_group.layer
            nRet, strRetInfo  = mobox.queryOneDataObjAttr( strLuaDEID, "Location", strCondition, strOrder,"S_CODE","N_ROW","N_COL","N_LAYER" )
            if nRet ~= 0  then
                return 1, "获取货位信息错误! "..strRetInfo 
            end
            if strRetInfo ~= ''  then
                local retInfo = json.decode( strRetInfo )
                local retAttrs = retInfo.attrs
                local empty_loc = {}

                empty_loc.priority = priority              -- 分配优先级最高
                empty_loc.loc_code = retAttrs[1].value  
                empty_loc.row = lua.StrToNumber( retAttrs[2].value )   
                empty_loc.col = lua.StrToNumber( retAttrs[3].value )   
                empty_loc.layer = lua.StrToNumber( retAttrs[4].value ) 
                
                empty_loc_set[index.value] = empty_loc
                index.value = index.value+1
            end
            if index.value == index.max  then
                break
            end
        end   
    end  
    return 0,""
end  

-- 从货位表查询空货位并加入结果集（index 必须是 table 作为引用参数）
-- @function get_empty_loc
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strCondition 查询条件
-- @tparam table empty_loc_set 空货位结果集（引用参数）
-- @tparam table index 索引计数器（引用参数）
-- @tparam number priority 优先级
-- @treturn number nRet 0: 成功
-- @treturn string strRetInfo 失败时为错误信息
local function get_empty_loc(  strLuaDEID, strCondition, empty_loc_set, index, priority )
    local nRet, strRetInfo
    local strOrder = "N_COL, N_LAYER"   -- 最近巷道口 

    -- 最多获取 10 条
    nRet, strRetInfo = mobox.queryDataObjAttr3( strLuaDEID, "Location", strCondition, 10, strOrder )
    if nRet ~= 0  then
        return 1, "获取货位信息错误! "..strRetInfo.." SQL条件: "..strCondition
    end

    if strRetInfo ~= '' then
        local loc
        local retObjs = json.decode( strRetInfo )

        for n = 1, #retObjs do
            nRet, loc = m3.ObjAttrStrToLuaObj( "Location", lua.table2str(retObjs[n].attrs) )
            if nRet ~= 0  then
                return 1, "m3.ObjAttrStrToLuaObj(Location) 失败! "..loc
            end
  
            local empty_loc = {}
            empty_loc.priority = priority              -- 分配优先级最高
            empty_loc.loc_code = loc.code 
            empty_loc.row = loc.row   
            empty_loc.col = loc.col   
            empty_loc.layer = loc.layer
            empty_loc_set[index.value] = empty_loc
            index.value = index.value+1
            if index.value == index.max  then
                break
            end
        end   
    end  
    return 0,""
end  

-- 获取巷道中的空货位（深位>2无效）
-- @function wms_wh.GetEmptyLocInAisle
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @tparam table aisle_obj 巷道数据对象
-- @tparam string ext_condition 扩展条件（可选）
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table empty_loc_set 空货位列表
function wms_wh.GetEmptyLocInAisle( strLuaDEID, area_code, aisle_obj, ext_condition )
    local nRet, strRetInfo
    local strCondition = ''
    local empty_loc_set = {}            -- 空货位集
    local index = {}
    index.value = 1
    index.max = 11                      -- 空货位集最多10个

    if aisle_obj == nil  then
        return 1, "无效参数!"
    end
    if ext_condition == nil  then
        ext_condition = ''
    end

    -- 如果需要匹配现有存储货物条件
    if ext_condition ~= ''  then
        -- 巷道左边排是双深位
        if aisle_obj.left_deep == 2  then
            -- 多深位货位
            -- 获取已经有满足匹配条件的货物在 深位 货位
            strCondition = "N_CURRENT_NUM = 1 AND S_AREA_CODE = '"..area_code.."' AND N_ROW_GROUP = "..aisle_obj.left_row_group
            strCondition = strCondition .. " AND ("..ext_condition..")"
            nRet, strRetInfo = get_empty_loc_by_loc_group(  strLuaDEID, strCondition, empty_loc_set, index, 1 )
            if nRet ~= 0  then
                return 1, strRetInfo
            end
        end 
        if index.value >= index.max  then
            goto go_back
        end

        -- 巷道右边排也是双深位
        if aisle_obj.right_deep == 2  then
            -- 多深位货位
            -- 获取已经有满足匹配条件的货物在 深位 货位
            strCondition = "N_CURRENT_NUM = 1 AND S_AREA_CODE = '"..area_code.."' AND N_ROW_GROUP = "..aisle_obj.right_row_group
            strCondition = strCondition .. " AND ("..ext_condition..")"
            nRet, strRetInfo = get_empty_loc_by_loc_group(  strLuaDEID, strCondition, empty_loc_set, index, 1 )
            if nRet ~= 0  then
                return 1, strRetInfo
            end
        end 
        if index.value >= index.max  then
            goto go_back
        end
    end
    
    -- 获取最里面的空货位
    -- 左边是双深位
    if aisle_obj.left_deep == 2  then
        -- 获取左边最里面的空货位
        strCondition = "N_CURRENT_NUM = 0 AND S_AREA_CODE = '"..area_code.."' AND N_ROW_GROUP = "..aisle_obj.left_row_group
        strCondition = strCondition.." AND N_LOCK_STATE = 0 AND C_ENABLE = 'Y' AND N_POS = 2"  
        nRet, strRetInfo = get_empty_loc(  strLuaDEID, strCondition, empty_loc_set, index, 2 )
        if nRet ~= 0  then
            return 1, strRetInfo
        end
        if index.value >= index.max  then
            goto go_back
        end
    end
    -- 右边是双深位
    if aisle_obj.right_deep == 2  then
        -- 获取右边最里面的空货位
        strCondition = "N_CURRENT_NUM = 0 AND S_AREA_CODE = '"..area_code.."' AND N_ROW_GROUP = "..aisle_obj.right_row_group
        strCondition = strCondition.." AND N_LOCK_STATE = 0 AND C_ENABLE = 'Y' AND N_POS = 2"
   
        nRet, strRetInfo = get_empty_loc(  strLuaDEID, strCondition, empty_loc_set, index, 2 )
        if nRet ~= 0  then
            return 1, strRetInfo
        end
        if index.value >= index.max  then
            goto go_back
        end
    end 

    -- 获取左边最外面的空货位
    strCondition = "N_CURRENT_NUM = 0 AND S_AREA_CODE = '"..area_code.."' AND N_ROW_GROUP = "..aisle_obj.left_row_group
    strCondition = strCondition.." AND N_LOCK_STATE = 0 AND C_ENABLE = 'Y' AND N_POS = 1" 
    nRet, strRetInfo = get_empty_loc(  strLuaDEID, strCondition, empty_loc_set, index, 3 )
    if nRet ~= 0  then
        return 1, strRetInfo
    end
    if index.value >= index.max  then
        goto go_back
    end

    -- 获取右边最外面的空货位
    strCondition = "N_CURRENT_NUM = 0 AND S_AREA_CODE = '"..area_code.."' AND N_ROW_GROUP = "..aisle_obj.right_row_group
    strCondition = strCondition.." AND N_LOCK_STATE = 0 AND C_ENABLE = 'Y' AND N_POS = 1"        
    nRet, strRetInfo = get_empty_loc(  strLuaDEID, strCondition, empty_loc_set, index, 3 )
    if nRet ~= 0  then
        return 1, strRetInfo
    end
    
    ::go_back::
    --  排序
    table.sort( empty_loc_set, empty_loc_sort )
    return 0, empty_loc_set
end

-- 获取库区的空货位数量
-- @function wms_wh.GetEmptyLocNum
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @treturn number nRet 0: 成功，非0: 失败
-- @treturn number empty_loc_num 空货位数量
function wms_wh.GetEmptyLocNum( strLuaDEID, area_code )
    local nRet, strRetInfo, strCondition

    strCondition = "N_LOCK_STATE = 0 AND N_CAPACITY > N_CURRENT_NUM AND C_ENABLE = 'Y' AND S_AREA_CODE = '"..area_code.."'"
    nRet, strRetInfo = mobox.getDataObjCount( strLuaDEID, "Location", strCondition )
    if nRet ~= 0  then 
        return nRet, strRetInfo 
    end 
    local empty_loc_num = lua.StrToNumber( strRetInfo ) 
    return 0, empty_loc_num
end

-- 从内存获取巷道数据对象信息
-- @function wms_wh.GetAisleInfo
-- @tparam string aisle_code 巷道编码，必须有值
-- @treturn number nRet 0 成功，其他失败（错误编码），失败时，strRetInfo 有值
-- @treturn string/table strRetInfo 失败时返回错误信息，成功返回 aisle_data_objs
function wms_wh.GetAisleInfo( aisle_code )
    if lua.StrIsEmpty( aisle_code ) then
        return 1, "aisle_code 是无效参数, 必须有值!"
    end    
    local nRet, aisle_data_obj = m3.GetDataFromCache( "Aisle", aisle_code )
    if nRet ~= 0 then 
        return nRet, aisle_data_obj
    end
    return 0, aisle_data_obj     
end

-- 获取仓库中巷道中正在执行的任务数量，用于巷道均衡计算，函数会检查巷道
-- @function wms_wh.GetAisleTaskNum
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string wh_code 仓库编码，必须有值
-- @tparam table aisle_set 巷道数据对象集，必须有值
-- @treturn number nRet 0 成功，其他失败（错误编码），失败时，strRetInfo 有值
-- @treturn string strRetInfo 失败时返回错误信息
--[[
    aisle_set = {
                    { aisle_code = "A01", task_num = 0, cntr_list = {}},...
                }
    该函数赋值 task_num
--]]
function wms_wh.GetAisleTaskNum( strLuaDEID, wh_code, aisle_set )
    local nRet, strRetInfo, strCondition

    if aisle_set == nil  then
        return 1, "aisle_set 是无效参数, 必须有值!"
    end
    if lua.StrIsEmpty( wh_code ) then
        return 1, "wh_code 是无效参数, 必须有值!"
    end
    -- 判断一下 aisle_set 中的巷道是否存在，如果存在，则获取任务数，否则返回错误
    local aisle_data_obj
    for _, aisle_obj in ipairs(aisle_set) do
        local aisle_code = aisle_obj.aisle_code

        nRet, aisle_data_obj = wms_wh.GetAisleInfo( aisle_code )
        if nRet ~= 0 then 
            return nRet, aisle_data_obj
        end
        if aisle_data_obj.S_WH_CODE ~= wh_code then
            return 1, "巷道 "..aisle_code.." 不属于仓库 "..wh_code
        end
        
        -- 获取巷道任务数
        strCondition = string.format("N_B_STATE < 3 AND ( S_START_AISLE_CODE = '%s' OR S_END_AISLE_CODE = '%s')",
                                     aisle_code, aisle_code )
        nRet, strRetInfo = mobox.getDataObjCount(strLuaDEID, "Task", strCondition)
        if nRet == 0 then
            aisle_obj.task_num = lua.StrToNumber(strRetInfo)
        end
    end
    return 0
end

return wms_wh
