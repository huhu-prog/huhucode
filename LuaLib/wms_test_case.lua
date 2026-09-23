--[[
    版本：     Version 3.0
    创建日期： 2026-9-10
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    名称:   wms_tc
    功能：  WMS 中和测试用例相关的函数，用于实施辅助

    【测试用例导入】
        CreateDataSync  — 创建数据同步记录（WMS_Data_Sync）

    更改记录:
        2025-4-10  HAN  创建
        2026-6-19        整理函数注释，添加 @tparam/@treturn 注解

    AI CHECK:
        -- 20260619
--]]

m3 = require ("oi_base_mobox")
wms_cntr = require("wms_container")
wms_import = require("wms_import")

wms_inv  = require ("wms_inventory")

local wms_tc = {_version = "0.1.1"}
local test_case_attr_pos = {
    tc_code = {4,6},
    tc_name = {4,15},
    factory = {6,6},
    wh_code = {8,6},
    storer = {10,6},
    desc = {12,6},
}

local function get_excel_value(rows, pos)
    local row = rows[pos[1]]
    if row then
        return row[pos[2]]
    end
    return nil
end

-- 从测试用例的 Home 页签获取测试用例的基本属性
-- @function wms_tc.Get_TestCaseData
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table rows 测试用例的 Tool 页签数据队列
-- @treturn number nRet 0: 成功，1: 创建失败，2: 参数错误
-- @treturn table/string test_case 成功返回 WMS_TC_Step 对象，失败返回错误信息
function wms_tc.Get_TestCaseData( strLuaDEID, rows )
    local tc_code = get_excel_value(rows, test_case_attr_pos.tc_code)
    local tc_name = get_excel_value(rows, test_case_attr_pos.tc_name)    
    local factory = get_excel_value(rows, test_case_attr_pos.factory)
    local wh_code = get_excel_value(rows, test_case_attr_pos.wh_code)
    local storer = get_excel_value(rows, test_case_attr_pos.storer)
    local desc = get_excel_value(rows, test_case_attr_pos.desc)

    if tc_code == nil or tc_code == '' then
        return 1, "测试用例编码不能为空!"
    end
    if factory == nil or factory == '' then
        return 1, "工厂编码不能为空!"
    end
    local test_case = m3.AllocObject2( strLuaDEID, "WMS_Test_Case" )

    test_case.S_TC_CODE = tc_code
    test_case.S_TC_NAME = tc_name
    test_case.S_FACTORY = factory
    test_case.S_WH_CODE = wh_code
    test_case.S_STORER = storer
    test_case.S_DESC = desc

    return 0, test_case
end

-- 从测试用例的 Step 页签获取测试工具数据队列列表
-- @function wms_tc.Get_TC_StepDataList
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table rows 测试用例的 Tool 页签数据队列
-- @treturn number nRet 0: 成功，1: 创建失败，2: 参数错误
-- @treturn table/string tc_step_data 成功返回 WMS_TC_Step 对象，失败返回错误信息
function wms_tc.Get_TC_StepDataList( strLuaDEID, rows )
    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "WMS_TC_Step" )
    if nRet ~= 0 then
        return 1, "获取WMS_TC_Step对象属性失败! 原因:"..cls_attrs
    end

    local tc_step_list = {}
    
    for n = 2, #rows do
        local tc_step_data = m3.AllocObject2( strLuaDEID, "WMS_TC_Step" )
        for key, value in pairs(rows[n]) do
            key = lua.trim(key)
            if lua.IsInTable( key, cls_attrs ) then
                tc_step_data[key] = value
            end
        end
        tc_step_data.N_ORDER = n-1
        if tc_step_data.S_NAME == nil or tc_step_data.S_NAME == '' then
            return 1, "测试步骤名称不能为空!"
        end
        table.insert( tc_step_list, tc_step_data )
    end

    return 0, tc_step_list
end

-- 从测试用例的 Tool 页签获取测试工具数据队列列表
-- @function wms_tc.Get_TC_ToolsDataList
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table rows 测试用例的 Tool 页签数据队列
-- @treturn number nRet 0: 成功，1: 创建失败，2: 参数错误
-- @treturn table/string tc_tools_list 成功返回 WMS_TC_Tools 对象，失败返回错误信息
function wms_tc.Get_TC_ToolsDataList( strLuaDEID, rows )
    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "WMS_TC_Tools" )
    if nRet ~= 0 then
        return 1, "获取 WMS_TC_Tools 对象属性失败! 原因:"..cls_attrs
    end

    local tc_tools_list = {}
    for n = 2, #rows do
        local tc_tools_data = m3.AllocObject2( strLuaDEID, "WMS_TC_Tools" )
        for key, value in pairs(rows[n]) do
            key = lua.trim(key)
            if lua.IsInTable( key, cls_attrs ) then
                tc_tools_data[key] = value
            end
        end
        tc_tools_data.N_ORDER = n-1
        if tc_tools_data.S_NAME == nil or tc_tools_data.S_NAME == '' then
            return 1, "测试工具名称不能为空!"
        end
        table.insert( tc_tools_list, tc_tools_data )
    end

    return 0, tc_tools_list
end

local function reload_resident_in_memory( strLuaDEID, cls_id, strCondition )
    local nRet, data_objs = m3.QueryDataObject( strLuaDEID, cls_id, strCondition )
    if nRet ~= 0 then 
        return 1, "获取'"..cls_id.."'信息失败! " .. data_objs
    end
    
    local id_str = ''
    local max_count = 10
    local n = 1
    local err
    local data_obj_list = {}

    if data_objs == '' then
        return 0, data_obj_list 
    end
    for _, obj in ipairs( data_objs ) do
        local data_obj = m3.KeyValueAttrsToObjAttr( obj.attrs )
        if data_obj == nil then
            return 1, "获取'"..cls_id.."'信息失败! " 
        end
        table.insert( data_obj_list, data_obj )
        id_str = id_str..obj.id..";"
        if n == max_count then
            nRet, err = mobox.reloadMemoryDataObjInfo( strLuaDEID, cls_id, id_str )
            if nRet ~= 0 then 
                return 1, "重新装载'"..cls_id.."'信息失败! " .. err
            end
            n = 1
            id_str = ''
        else
            n = n + 1
        end
    end
    if id_str ~= '' then
        nRet, err = mobox.reloadMemoryDataObjInfo( strLuaDEID, cls_id, id_str )
        if nRet ~= 0 then 
            return 1, "重新装载'"..cls_id.."'信息失败! " .. err
        end
    end
    return 0, data_obj_list
end
-- 把工厂标识 = factory_no的所有WMS基础数据对象数据属性重新装载内存

-- @function wms_tc.Reload_Resident_In_Memory
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string factory_no 工厂编码
-- @treturn number nRet 0: 成功，1: 创建失败，2: 参数错误
-- @treturn table/string tc_tools_list 成功返回 WMS_TC_Tools 对象，失败返回错误信息
function wms_tc.Reload_Resident_In_Memory( strLuaDEID, factory_no )

    if factory_no == nil or factory_no == '' then
        return 1, "工厂编码不能为空!"
    end

    local strCondition = "S_FACTORY = '"..factory_no.."'"
    -- 重新装载容器定义
    local nRet, ctd_list = reload_resident_in_memory( strLuaDEID, "Container_Type_Def", strCondition )
    if nRet ~= 0 then
        return 1, "重新装载 Container_Type_Def 信息失败! " .. ctd_list
    end
    -- 重新装载Warehouse信息
    local nRet, wh_data_list = reload_resident_in_memory( strLuaDEID, "Warehouse", strCondition )
    if nRet ~= 0 then
        return 1, "重新装载Warehouse信息失败! " .. wh_data_list
    end

    -- 重新装载Area/Aisle/Rack信息
    local area_data_list, aisle_data_list, rack_data_list
    for _, wh_data in ipairs(wh_data_list) do
        strCondition = "S_WH_CODE = '"..wh_data.S_CODE.."'"
        nRet, area_data_list = reload_resident_in_memory( strLuaDEID, "Area", strCondition )
        if nRet ~= 0 then
            return 1, "重新装载Area信息失败! " .. area_data_list
        end  
        
        nRet, aisle_data_list = reload_resident_in_memory( strLuaDEID, "Aisle", strCondition )
        if nRet ~= 0 then
            return 1, "重新装载 Aisle 信息失败! " .. aisle_data_list
        end   
        
        nRet, rack_data_list = reload_resident_in_memory( strLuaDEID, "Rack", strCondition )
        if nRet ~= 0 then
            return 1, "重新装载 Rack 信息失败! " .. rack_data_list
        end          
    end

    mobox.reloadMemoryDataObjInfo( strLuaDEID, "Location" )

    return 0
end

local function clear_factory_related_data( strLuaDEID, factory_no )
    local strCondition = "S_FACTORY = '"..factory_no.."'"
    local err, condition

    -- 清除业务数据
    -- 删除组盘
    local nRet, data_list = wms_base.Clear_Data( strLuaDEID, "Inbound_Palletization", strCondition )
    if nRet ~= 0 then
        return 1, "移除 Inbound_Palletization 信息失败! " .. data_list
    end
    for _, data in ipairs(data_list) do
        condition = "S_IBP_NO = '"..data.S_IBP_NO.."'"
        nRet, err = mobox.dbdeleteData(strLuaDEID, "INB_Pallet_Detail", condition )    
        if nRet ~= 0 then 
            return 1, "删除'INB_Pallet_Detail'数据失败! " .. err
        end
    end
    
    -- 删除入库单
    nRet, data_list = wms_base.Clear_Data( strLuaDEID, "Inbound_Order", strCondition )
    if nRet ~= 0 then
        return 1, "移除 Inbound_Order 信息失败! " .. data_list
    end
    for _, data in ipairs(data_list) do
        condition = "S_IO_NO = '"..data.S_NO.."'"
        nRet, err = mobox.dbdeleteData(strLuaDEID, "Inbound_Detail", condition )    
        if nRet ~= 0 then 
            return 1, "删除'Inbound_Detail'数据失败! " .. err
        end
    end   
    -- 删除入库波次
    nRet, data_list = wms_base.Clear_Data( strLuaDEID, "Inbound_Wave", strCondition )
    if nRet ~= 0 then
        return 1, "移除 Inbound_Wave 信息失败! " .. data_list
    end
    for _, data in ipairs(data_list) do
        condition = "S_WAVE_NO = '"..data.S_WAVE_NO.."'"
        nRet, err = mobox.dbdeleteData(strLuaDEID, "IW_Compose", condition )    
        if nRet ~= 0 then 
            return 1, "删除'IW_Compose'数据失败! " .. err
        end
        nRet, err = mobox.dbdeleteData(strLuaDEID, "IW_Detail", condition )    
        if nRet ~= 0 then 
            return 1, "删除'IW_Detail'数据失败! " .. err
        end        
    end 
    
        
    -- 删除出库单
    nRet, data_list = wms_base.Clear_Data( strLuaDEID, "Outbound_Order", strCondition )
    if nRet ~= 0 then
        return 1, "移除 Outbound_Order 信息失败! " .. data_list
    end
    for _, data in ipairs(data_list) do
        condition = "S_OO_NO = '"..data.S_NO.."'"
        nRet, err = mobox.dbdeleteData(strLuaDEID, "Outbound_Detail", condition )    
        if nRet ~= 0 then 
            return 1, "删除'Outbound_Detail'数据失败! " .. err
        end
    end  

    -- 删除出库波次
    nRet, data_list = wms_base.Clear_Data( strLuaDEID, "Outbound_Wave", strCondition )
    if nRet ~= 0 then
        return 1, "移除 Outbound_Wave 信息失败! " .. data_list
    end
    for _, data in ipairs(data_list) do
        condition = "S_WAVE_NO = '"..data.S_WAVE_NO.."'"
        nRet, err = mobox.dbdeleteData(strLuaDEID, "OW_Compose", condition )    
        if nRet ~= 0 then 
            return 1, "删除'OW_Compose'数据失败! " .. err
        end
        nRet, err = mobox.dbdeleteData(strLuaDEID, "OW_Detail", condition )    
        if nRet ~= 0 then 
            return 1, "删除'OW_Detail'数据失败! " .. err
        end        
    end 
    
    -- 删除作业
    nRet, data_list = wms_base.Clear_Data( strLuaDEID, "Operation", strCondition )
    if nRet ~= 0 then
        return 1, "移除 Operation 信息失败! " .. data_list
    end
    for _, data in ipairs(data_list) do
        condition = "S_OP_CODE = '"..data.S_CODE.."'"
        nRet, err = mobox.deleteDataObject(strLuaDEID, "Task", condition )    
        if nRet ~= 0 then 
            return 1, "删除'Task'数据失败! " .. err
        end
    end

    -- 删除配盘 Pre_Alloc_Container
    nRet, data_list = wms_base.Clear_Data( strLuaDEID, "Pre_Alloc_Container", strCondition )
    if nRet ~= 0 then
        return 1, "移除 Pre_Alloc_Container 信息失败! " .. data_list
    end
    for _, data in ipairs(data_list) do
        condition = "S_PAC_NO = '"..data.S_PAC_NO.."'"
        nRet, err = mobox.dbdeleteData(strLuaDEID, "Pre_Alloc_CNTR_Detail", condition )    
        if nRet ~= 0 then 
            return 1, "删除'Pre_Alloc_CNTR_Detail'数据失败! " .. err
        end
    end  
    
    -- 删除配盘 Distribution_CNTR
    nRet, data_list = wms_base.Clear_Data( strLuaDEID, "Distribution_CNTR", strCondition )
    if nRet ~= 0 then
        return 1, "移除 Distribution_CNTR 信息失败! " .. data_list
    end
    for _, data in ipairs(data_list) do
        condition = "S_DC_NO = '"..data.S_DC_NO.."'"
        nRet, err = mobox.dbdeleteData(strLuaDEID, "Distribution_CNTR_Detail", condition )    
        if nRet ~= 0 then 
            return 1, "删除'Distribution_CNTR_Detail'数据失败! " .. err
        end
    end  

    -- 删除库存量
    local strCondition = "S_WH_CODE IN ( select S_CODE from TN_Warehouse where S_FACTORY = '"..factory_no.."')"
    nRet, err = mobox.deleteDataObject(strLuaDEID, "INV_Detail", strCondition)    
    if nRet ~= 0 then 
        return 1, "删除'INV_Detail'数据失败! " .. err
    end
    
    return 0
end

-- 把工厂标识 = factory_no的所有WMS相关的业务数据清除
-- @function wms_tc.Clear_WMS_BusinessData
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string factory_no 工厂编码
-- @treturn number nRet 0: 成功，1: 创建失败，2: 参数错误
-- @treturn string err 失败返回错误信息
function wms_tc.Clear_WMS_BusinessData( strLuaDEID, factory_no )

    if factory_no == nil or factory_no == '' then
        return 1, "工厂编码不能为空!"
    end

    local nRet, err = clear_factory_related_data( strLuaDEID, factory_no )
    if nRet ~= 0 then
        return 1, "清除工厂相关数据失败! " .. err
    end

    -- 删除 Loc_Container 
    strCondition = "S_LOC_CODE IN ( select S_CODE from TN_Location where S_WH_CODE IN ( select S_CODE from TN_Warehouse where S_FACTORY = '"..factory_no.."'))"
    nRet, err = mobox.dbdeleteData(strLuaDEID, "Loc_Container", strCondition )    
    if nRet ~= 0 then 
        return 1, "删除'Loc_Container'数据失败! " .. err
    end
    -- 删除库位锁 Lock
    strCondition = "N_OBJ_TYPE = 1 AND S_OBJ_CODE IN ( select S_CODE from TN_Location where S_WH_CODE IN ( select S_CODE from TN_Warehouse where S_FACTORY = '"..factory_no.."'))"
    nRet, err = mobox.dbdeleteData(strLuaDEID, "Lock", strCondition )    
    if nRet ~= 0 then 
        return 1, "删除'Lock'数据失败! " .. err
    end
    -- 设置Location属性
    strCondition = "S_CODE IN ( select S_CODE from TN_Location where S_WH_CODE IN ( select S_CODE from TN_Warehouse where S_FACTORY = '"..factory_no.."'))"
    local strUpdateSql = "N_CURRENT_NUM = 0, C_ENABLE = 'Y', N_LOCK_STATE = 0, S_LOCK_STATE = '', N_LOCK_VER = 1, S_LOCK_OP = ''"
    nRet, err = mobox.updateDataAttrByCondition( strLuaDEID, "Location", strCondition, strUpdateSql )
    if nRet ~= 0 then  
        return  1, "更新【Location】信息失败!"..err
    end 

    --容器相关
    --删除 Container_Ext
    strCondition = "S_CNTR_CODE IN ( select S_CODE from TN_Container where S_FACTORY = '"..factory_no.."')"
    nRet, err = mobox.dbdeleteData(strLuaDEID, "Container_Ext", strCondition )    
    if nRet ~= 0 then 
        return 1, "删除'Container_Ext'数据失败! " .. err
    end    

    --设置 Container 属性
    strCondition = "S_CODE IN ( select S_CODE from TN_Container where S_FACTORY = '"..factory_no.."')"
    local strUpdateSql = "C_ENABLE = 'Y', N_B_STATE = 0, N_LOCK_STATE = 0, N_EMPTY_CELL_NUM = N_MAX_CELL_NUM, "..
                         "N_LOCK_VER = 1, S_POSITION = '', F_CNTR_UTIL = 0, N_ALLOC_CELL_NUM = 0, N_NEST_FILL_STATUS = 0,"..
                         "N_EMPTY_FULL = 0, F_GOOD_VOLUME = 0, N_DETAIL_COUNT = 0, F_GOOD_WEIGHT = 0, C_FORCED_FILL = 'N'"
    nRet, err = mobox.updateDataAttrByCondition( strLuaDEID, "Container", strCondition, strUpdateSql )
    if nRet ~= 0 then  
        return  1, "更新【Container】信息失败!"..err
    end 

    --设置 Container_Cell 属性
    strCondition = "S_CNTR_CODE IN ( select S_CODE from TN_Container where S_FACTORY = '"..factory_no.."')"
    local strUpdateSql = "N_EMPTY_FULL = 0, F_GOOD_VOLUME = 0, F_GOOD_WEIGHT = 0, C_FORCED_FILL = 'N', F_CELL_UTIL = 0, "
    for _, attr in pairs(CNTR_EXT_BASE_ATTRS) do
        strUpdateSql = strUpdateSql .. attr .. " = '', "
    end
    for _, attr in pairs(UDF_ATTRS) do
        strUpdateSql = strUpdateSql .. attr .. " = '', "
    end    
    strUpdateSql = strUpdateSql .. "S_ALLOC_OP_CODE = '', F_QTY = 0, F_LIMIT = 0,  F_REM_CAP = 0"
    nRet, err = mobox.updateDataAttrByCondition( strLuaDEID, "Container_Cell", strCondition, strUpdateSql )
    if nRet ~= 0 then  
        return  1, "更新【Container_Cell】信息失败!"..err
    end 

    -- 删除容器锁 Container_Lock
    strCondition = "S_CNTR_CODE IN ( select S_CODE from TN_Container where S_FACTORY = '"..factory_no.."')"
    nRet, err = mobox.dbdeleteData(strLuaDEID, "Container_Lock", strCondition )    
    if nRet ~= 0 then 
        return 1, "删除'Container_Lock'数据失败! " .. err
    end
    
    return 0
end

-- 把工厂标识 = factory_no的所有WMS基础数据对象数据属性从驻留内存中取消
-- @function wms_tc.Clear_WMS_BaseData
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string factory_no 工厂编码
-- @treturn number nRet 0: 成功，1: 创建失败，2: 参数错误
-- @treturn table/string tc_tools_list 成功返回 WMS_TC_Tools 对象，失败返回错误信息
function wms_tc.Clear_WMS_BaseData( strLuaDEID, factory_no )

    if factory_no == nil or factory_no == '' then
        return 1, "工厂编码不能为空!"
    end

    local nRet, err = clear_factory_related_data( strLuaDEID, factory_no )
    if nRet ~= 0 then
        return 1, "清除工厂相关数据失败! " .. err
    end    
    local strCondition = "S_FACTORY = '"..factory_no.."'"
  
    -- 删除Warehouse信息
    local nRet, wh_data_list = wms_base.Clear_Data( strLuaDEID, "Warehouse", strCondition )
    if nRet ~= 0 then
        return 1, "移除 Warehouse 信息失败! " .. wh_data_list
    end
    -- 移除Area/Aisle/Rack信息
    local area_data_list, aisle_data_list, rack_data_list
    for _, wh_data in ipairs(wh_data_list) do
        strCondition = "S_WH_CODE = '"..wh_data.S_CODE.."'"
        nRet, area_data_list = wms_base.Clear_Data( strLuaDEID, "Area", strCondition )
        if nRet ~= 0 then
            return 1, "移除 Area 信息失败! " .. area_data_list
        end  
        
        nRet, aisle_data_list = wms_base.Clear_Data( strLuaDEID, "Aisle", strCondition )
        if nRet ~= 0 then
            return 1, "移除 Aisle 信息失败! " .. aisle_data_list
        end   
        
        nRet, rack_data_list = wms_base.Clear_Data( strLuaDEID, "Rack", strCondition )
        if nRet ~= 0 then
            return 1, "移除 Rack 信息失败! " .. rack_data_list
        end

        -- 删除库位
        nRet, err = mobox.deleteDataObject(strLuaDEID, "Location", strCondition)    
        if nRet ~= 0 then 
            return 1, "删除 Location 数据失败! " .. err
        end        
    end

    -- 查询库存量有问题
    --[[
    strCondition = "S_WH_CODE IN ( select S_CODE from TN_Warehouse where S_FACTORY = '"..factory_no.."')"
    nRet, data_objs = m3.QueryDataObject(strLuaDEID, "INV_Detail", strCondition )
    nRet, data_objs = m3.QueryDataObject(strLuaDEID, "INV_Detail", "S_CNTR_CODE = '#TP-1'" )
    --]]

    strCondition = "S_FACTORY = '"..factory_no.."'"
    -- 删除机台
    nRet, err = mobox.deleteDataObject(strLuaDEID, "Machine_Station", strCondition )    
    if nRet ~= 0 then 
        return 1, "删除'Machine_Station'数据失败! " .. err
    end  
    
    -- 删除容器定义
    local nRet, ctd_list = wms_base.Clear_Data( strLuaDEID, "Container_Type_Def", strCondition )
    if nRet ~= 0 then
        return 1, "移除 Container_Type_Def 信息失败! " .. ctd_list
    end
    for _, ctd_data in ipairs(ctd_list) do
        -- 容器删除
        strCondition = "S_CTD_CODE = '"..ctd_data.S_CTD_CODE.."'"
        nRet, err = mobox.deleteDataObject(strLuaDEID, "Container", strCondition)    
        if nRet ~= 0 then 
            return 1, "删除 Container 数据失败! " .. err
        end

        -- 容器嵌套规则删除
        strCondition = "S_P_CTD_CODE = '"..ctd_data.S_CTD_CODE.."'"
        nRet, err = mobox.dbdeleteData(strLuaDEID, "Container_Nest_Rule", strCondition)    
        if nRet ~= 0 then 
            return 1, "删除'Container_Nest_Rule'数据失败! " .. err
        end        
    end
    -- 删除工厂
    strCondition = "S_CODE = '"..factory_no.."'"
    nRet, err = mobox.dbdeleteData(strLuaDEID, "Factory", strCondition)    
    if nRet ~= 0 then 
        return 1, "删除'Factory'数据失败! " .. err
    end  

    mobox.removeCacheGroup( "Container_Type_Def" )
    return 0
end


return wms_tc
