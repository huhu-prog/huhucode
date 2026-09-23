--[[
    版本：     Version 2.0
    创建日期： 2025-1-27
    修改日期:  2026-6-16
    创建人：   HAN

    功能：
        和容器数据类(Container)相关的函数集合

        -- [容器基础操作]
        CreateVirtual                创建一个虚拟容器
        SetWeight                    设置容器的重量
        GetInfo                      获取容器信息(不推荐，推荐GetInfo2)
        GetInfo2                     获取容器信息(返回数据表字段属性的table)
        GetInfo_Location             获取容器及绑定的库位信息，如果没绑定货位容器对象为{}
        Exist                        判断某个编号的容器是否存在
        InOperation                  判断某个编号的容器是否被作业使用
        CanUsedInOperation           检查容器是否可以用于作业中（如果容器在一个未完成的作业中则不可用）

        -- [容器扩展属性]
        Add_CNTR_ExtInfo             创建容器的扩展属性（从 data_object 获取混箱属性加到 Container_Ext）
        Get_Container_ExtInfo        获取容器及容器扩展属性，返回数据字段属性对象

        -- [容器与货位]
        Loc_Container_Exist          判断某个货位是否有绑定过容器
        Get_Loc_Container            获取货位中的容器编码列表
        Get_Container_Loc            获取容器所在货位
        Unbinding                    容器和货位解绑，并且释放库存量

        -- [容器锁定]
        SetLock                      容器加锁
        Lock                         给容器加锁（调用 wms_LockCntr 然后更新 Container 表）

        -- [容器料格/容量计算]
        Calculate_Cell_Capacity      计算料箱料格最多能装几个SKU，这里不考虑超重的情况
        Get_CntrCell_Goods_Qty       计算料格能装多少个SKU货品，根据SKU的S_COUNT_METHOD计算
        Get_CellNum_ToLoad_SKU       计算需要多少个料格来装下指定数量的SKU，从SKU最适配料格起逐步计算
        CNTR_cell_alloc_set          预分配一个容器料格（容器 N_ALLOC_CELL_NUM + 1，料格 N_EMPTY_FULL = 3）
        Get_Empty_CellList           获取容器中的空料格列表
        Set_CntrCell_Data_List       设置料格 cell_no 里的属性（基于INV_Detail的汇总数据填充到对应的料格中）

        -- [容器类型定义]
        GetCTDInfo                   获取容器类型定义数据对象（含混箱规则、补料规则、料格定义等扩展属性）
        Get_CTD_GridDef              根据 cell_type 获取料格定义
        Get_CTD_Next_GridDef         根据 cell_type 获取下一个等级的料格定义
        Get_Cell_Volume_Weight       获取指定料格类型的体积和重量限制

        -- [容器重置]
        Reset                        重置容器的料格属性和容器本身属性（基于INV_Detail重新计算）

        -- [内部/辅助]
        _Get_Bin_Under_Operation     获取正在作业的料箱编码列表

        ----------------------------------------------------------------------
        Get_Container_Cell_Data      获取容器中的料格数据对象信息
        Create_Mobile_Rack           根据移动料架中的定义，创建容器料格
        Create_Cell_Box              创建容器类型为Cell_Box的料格对象
        
        -- [容器嵌套操作]
        CanNestChildContainer          判断容器是否可以嵌套子容器

    更改说明：
    
    AI CHECK:
        -- 20260616
--]]
wms_inv  = require ("wms_inventory")

-- Container 的基本属性
CNTR_BASE_ATTRS= {
    "S_CODE",
    "S_CTD_CODE",
    "S_TYPE",
    "S_SPEC",
    "F_WEIGHT",
    "F_GOOD_WEIGHT",
    "F_MAX_WEIGHT",
    "F_LENGTH",
    "F_WIDTH",
    "F_HEIGHT",
    "C_IS_VIRTUAL",
    "C_ENABLE",
    "N_DETAIL_COUNT",
    "N_B_STATE",
    "S_LOCK_OP_CODE",
    "S_LOCK_STATE",
    "N_LOCK_STATE",
    "F_MAX_VOLUME",
    "F_GOOD_VOLUME",
    "N_EMPTY_FULL",
    "N_MAX_CELL_NUM",
    "N_EMPTY_CELL_NUM",
    "N_ALLOC_CELL_NUM",
    "C_FORCED_FILL",
    "S_POSITION",
    "S_SOURCE",
    "F_CNTR_UTIL"
}

local wms_cntr = {_version = "0.1.1"}

-- 创建一个虚拟容器
-- @function wms_cntr.CreateVirtual
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table container 容器对象（含基础属性）, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn table|string container 成功时返回容器对象，失败时返回错误信息
function wms_cntr.CreateVirtual( strLuaDEID, container )
    local nRet, strRetInfo, strErr
    strErr = ''

    -- 生成容器编码
    local strHeader = 'VC'..os.date("%y%m")..'-'
    nRet,strRetInfo = mobox.getSerialNumber( "virtual_container", strHeader, 5 )  
    if ( nRet ~= 0 ) then
        strErr = '申请虚拟容器编码失败!'..strRetInfo
        return nRet, strErr
    end
    container.code = strRetInfo

    -- 获取创建容器时需要的属性
    nRet, container = m3.CreateDataObj( strLuaDEID, container )
    if ( nRet ~= 0 ) then
        return nRet, "CreateDataObj失败! "..container
    end

    return nRet, container
end

-- 创建容器的扩展属性
-- @function wms_cntr.Add_CNTR_ExtInfo
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @tparam table mixing_attrs 混箱属性字段列表
-- @tparam table data_object 数据对象（含混箱属性值）,从 data_object 中获取混箱属性加到 Container_Ext
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string errMsg 失败时返回错误信息
function wms_cntr.Add_CNTR_ExtInfo( strLuaDEID, cntr_code, mixing_attrs, data_object )
    local nRet
    local cntr_ext_data = m3.AllocObject2( strLuaDEID, "Container_Ext" )
    
    cntr_ext_data.S_CNTR_CODE  = cntr_code 
    for _, mixing_attr in ipairs(mixing_attrs) do
        cntr_ext_data[mixing_attr] = data_object[mixing_attr]
    end
    nRet, cntr_ext_data = m3.CreateDataObj2( strLuaDEID, cntr_ext_data, 1 ) -- 1 表示已经存在就覆盖
    if ( nRet ~= 0 ) then 
        return 2, "创建[Container_Ext]失败!"..cntr_ext_data
    end 
    return 0
end

-- 设置容器的重量
-- @function wms_cntr.SetWeight
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @tparam number fWeight 容器重量, 必须有值且不能为负数
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string errMsg 失败时返回错误信息，成功时返回"ok"
function wms_cntr.SetWeight( strLuaDEID, cntr_code, fWeight )
    local nRet, strRetInfo, strErr

    if ( cntr_code == nil or  cntr_code == '' ) then 
        return 1, "cntr_code 必须有值" 
    end
    if ( fWeight == nil or fWeight < 0) then 
        return 1, "重量必须有值，不能为负数!"
    end

    local strSetAttr = "F_GOOD_WEIGHT = "..fWeight
    local strCondition = "S_CODE = '"..cntr_code .. "'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Container", strCondition, strSetAttr )
    if ( nRet ~= 0 ) then 
        return nRet, strRetInfo 
    end    
    return 0, "ok"
end

-- 获取容器信息(不推荐),新开发用 wms_cntr.GetInfo2
-- @function wms_cntr.GetInfo
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @treturn number nRet 0表示成功，1表示不存在，2表示失败
-- @treturn table|string cntr 成功时返回容器对象，不存在时返回空字符串，失败时返回错误信息
function wms_cntr.GetInfo( strLuaDEID, cntr_code )
    if ( cntr_code == nil or cntr_code == '' ) then
        return 2, "wms_cntr.GetInfo 容器编号不能为空!"
    end

    local nRet, strRetInfo, id
    local strCondition = "S_CODE = '"..cntr_code.."'"
    nRet, id, strRetInfo = mobox.getDataObjAttrByKeyAttr( strLuaDEID, "Container", strCondition )

    -- 返回1表示不存在
    if ( nRet == 1 ) then 
        return 1, "容器'"..cntr_code.."'不存在!" 
    end

    if ( nRet ~= 0 ) then
        return 2, "getDataObjAttrByKeyAttr 失败!"..id
    end

    local strJson
    nRet, strJson = mobox.objAttrsToLuaJson( "Container", strRetInfo )
    if ( nRet ~= 0  ) then
        return 2, "objAttrsToLuaJson Container 失败!"..strRetInfo
    end

    local object, success
    success, object = pcall( json.decode, strJson )
    if ( success == false ) then
        return 2,"objAttrsToLuaJson('Container') 返回的的JSON格式不合法!" 
    end
    object.id = id
    return 0, object
end

-- 获取容器信息(返回数据表字段属性的table)
-- @function wms_cntr.GetInfo2
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @treturn number nRet 0表示成功，1表示不存在，2表示失败
-- @treturn table|string cntr 成功时返回容器对象，不存在时返回空字符串，失败时返回错误信息
function wms_cntr.GetInfo2( strLuaDEID, cntr_code )
    if cntr_code == nil or cntr_code == '' then
        return 2, "wms_cntr.GetInfo2 容器编号不能为空!"
    end

    local nRet, strRetInfo, id
    local strCondition = "S_CODE = '"..cntr_code.."'"
    nRet, id, strRetInfo = mobox.getDataObjAttrByKeyAttr( strLuaDEID, "Container", strCondition )
    -- 返回1表示不存在
    if nRet == 1 then 
        return 1, "容器'"..cntr_code.."'不存在!" 
    end

    if nRet ~= 0 then
        return 2, "getDataObjAttrByKeyAttr 失败!"..id
    end

    local strJson
    nRet, strJson = mobox.objAttrToObjJson( "Container", strRetInfo )
    if nRet ~= 0 then
        return 2, "objAttrToObjJson 失败!"..strRetInfo
    end

    local object, success
    success, object = pcall( json.decode, strJson )
    if success == false then
        return 2,"objAttrToObjJson('Container') 返回的的JSON格式不合法!" 
    end
    object.id = id
    object.cls = "Container"
    return 0, object
end

-- 获取容器及绑定的库位信息，如果没绑定货位容器对象为{}
-- @function wms_cntr.GetInfo_Location
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn table cntr 成功时返回容器对象（含字段属性），如 { code = "", ... }
-- @treturn string loc_code 容器绑定的货位编码，如 "1-2-3"
function wms_cntr.GetInfo_Location( strLuaDEID, cntr_code )
    local nRet, strRetInfo

    if ( cntr_code == nil or cntr_code == '' ) then
        return 2, "WMS_Container_GetBaseInfo 容器编号不能为空!"
    end
    local strTable = "TN_Container a INNER JOIN TN_Loc_Container b ON a.S_CODE = b.S_CNTR_CODE" 
    -- 要查询的属性
    local strAttrs = "b.S_LOC_CODE" 
    for _, attr in ipairs( CNTR_BASE_ATTRS ) do
        strAttrs = strAttrs..", a."..attr
    end
    -- 从指定的巷道获取巷道内 巨星空料箱，根据位置进行排序
    local strCondition =  "a.S_CODE = '"..cntr_code.."'"
    local strOrder = ""
    nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 1, strCondition, strOrder )

    if strRetInfo == "" then 
        return 1, "容器'"..cntr_code.."'没绑定库位!"
    end
    if nRet ~= 0  then
        return 2, "GetCntrLocation 失败!"..strRetInfo
    end

    local cntr_data = {}
--  local ret_attr = json.decode(strRetInfo)
    local ret_attr, success
    success, ret_attr = pcall( json.decode, strRetInfo )
    if not success then
        return 2,"解析 queryMultiTable 返回的的JSON格式不合法!" 
    end

    local loc_code = ret_attr[1][1]
    for n = 1, #CNTR_BASE_ATTRS do
        cntr_data[CNTR_BASE_ATTRS[n]] = ret_attr[1][n+1]
    end
    nRet, strRetInfo = mobox.objJsonToLuaJson( "Container", lua.table2str(cntr_data) )
    if nRet ~= 0 then
        return 2, "objJsonToLuaJson  (Container) 失败!"..strRetInfo
    end
--  local cntr = json.decode( strRetInfo )
    local cntr, success
    success, cntr = pcall( json.decode, strRetInfo )
    if not success then
        return 2,"解析 objJsonToLuaJson 返回的的JSON格式不合法!" 
    end
    
    if cntr.position ~= loc_code then
        local msg = "容器'"..cntr_code.."'里的 position = '"..cntr.position.."', 实际绑定的货位是'"..loc_code.."'"
        lua.WriteLog( strLuaDEID, "警告", "GetInfo_Location", 0, "容器位置差异报警", msg )
        cntr.position = loc_code
    end
    return 0, cntr, loc_code
end

-- 判断某个编号的容器是否被作业使用
-- @function wms_cntr.InOperation
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string ret "yes"表示容器在作业中，"no"表示没有
function wms_cntr.InOperation( strLuaDEID, cntr_code )
    local strCondition
    local nRet, strRetInfo

    strCondition = "( N_B_STATE = 0 OR N_B_STATE = 1)  AND S_CNTR_CODE = '"..cntr_code.."'"
    nRet, strRetInfo = mobox.getDataObjCount( strLuaDEID, "Operation", strCondition )
    if ( nRet ~= 0 ) then return nRet, strRetInfo end 
    local nCount = lua.StrToNumber( strRetInfo )   
    if ( nCount == 0 ) then return 0, "no" end
    return 0, "yes"
end

-- 判断某个编号的容器是否存在
-- @function wms_cntr.Exist
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @treturn boolean exist true表示存在，false表示不存在
-- @treturn string|nil errMsg 失败时返回错误信息，成功时为nil
function wms_cntr.Exist( strLuaDEID, cntr_code )
    local nRet, strRetInfo
    if ( cntr_code == nil or  cntr_code == '' ) then 
        return false, "wms_cntr.Exist 函数中容器编码不能为空!"
    end
    local strCondition = "S_CODE = '"..cntr_code.."'"
    nRet, strRetInfo = mobox.existThisData( strLuaDEID, "Container", strCondition )
    if ( nRet ~= 0 ) then  
        return false, strRetInfo 
    end
    if ( strRetInfo == 'no' ) then 
        return false, "容器不存在"
    end
    return true
end

-- 判断某个货位是否有绑定过容器
-- @function wms_cntr.Loc_Container_Exist
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string loc_code 货位编码, 必须有值
-- @treturn boolean exist true表示存在，false表示不存在
function wms_cntr.Loc_Container_Exist( strLuaDEID, loc_code )
    local nRet, strRetInfo
    if ( loc_code == nil or loc_code == '' ) then 
        return false
    end
    local strCondition = "S_LOC_CODE = '"..loc_code.."'"
    nRet, strRetInfo = mobox.existThisData( strLuaDEID, "Loc_Container", strCondition )
    if ( nRet ~= 0 ) then return false end
    if ( strRetInfo == 'no' ) then return false end
    return true
end

-- 获取货位中的容器编码列表
-- @function wms_cntr.Get_Loc_Container
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string loc_code 货位编码, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn table|string cntr_set 成功时返回容器编码table如["C1","C2"]，无容器返回空字符串
function wms_cntr.Get_Loc_Container( strLuaDEID, loc_code )
    local nRet, strRetInfo

    if ( loc_code == nil or  loc_code == '' ) then 
        return 1, "wms_cntr.Get_Loc_Container 函数中loc_code不能为空!"
    end
    local strCondition = "S_LOC_CODE = '"..loc_code.."'"
    local strOrder = "N_BIND_ORDER"
    nRet, strRetInfo = mobox.queryDataObjAttr( strLuaDEID, "Loc_Container", strCondition, strOrder, "S_CNTR_CODE" )
    if ( nRet ~= 0 ) then return 1, "获取【Loc_Container】失败! "..strRetInfo end
    if ( strRetInfo == '' ) then return 0, "" end

    local retObjs = json.decode( strRetInfo )
    local attrs
    local cntr_set = {}

    for n = 1, #retObjs  do
        attrs = retObjs[n].attrs
        cntr_set[n] = attrs[1].value
    end

    return 0, cntr_set
end

-- 获取容器所在货位
-- @function wms_cntr.Get_Container_Loc
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string str_loc_code 成功时返回货位编码，未绑定货位返回空字符串
function wms_cntr.Get_Container_Loc( strLuaDEID, cntr_code )
    local nRet, strRetInfo

    if ( cntr_code == nil or  cntr_code == '' ) then 
        return 1, "wms_cntr.Get_Container_Loc 函数中 cntr_code 不能为空!"
    end
    local strCondition = "S_CNTR_CODE = '"..cntr_code.."'"
    local strOrder = "N_BIND_ORDER"
    nRet, strRetInfo = mobox.queryDataObjAttr( strLuaDEID, "Loc_Container", strCondition, strOrder, "S_LOC_CODE" )
    if ( nRet ~= 0 ) then 
        return 1, "获取【Loc_Container】失败! "..strRetInfo 
    end
    if ( strRetInfo == '' ) then 
        return 0, "" 
    end

    local retObjs = json.decode( strRetInfo )
    if ( #retObjs > 1 ) then
        return 1, "容器'"..cntr_code.."'在多个货位，数据错误请及时处理!"
    end

    local attrs
    attrs = retObjs[1].attrs
    return 0, attrs[1].value
end

-- 容器加锁
-- @function wms_cntr.SetLock
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string|table cntr 容器对象或容器编码，必须是Container类型
-- @tparam string str_lock_state 锁状态名称（如常量名）或锁状态数值
-- @tparam string lock_op_no 加锁的业务编码
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string errMsg 失败时返回错误信息
function wms_cntr.SetLock( strLuaDEID, cntr, str_lock_state, lock_op_no )
    local nRet, strRetInfo

    if ( str_lock_state == nil or str_lock_state == '') then
        return 1, "wms_cntr.SetLock 函数中 str_lock_state 不能为空!"
    end
    -- 如果 cntr 是一个字符串那就是容器编码
    if ( type(cntr) == "string" ) then
        nRet, cntr = wms_cntr.GetInfo( strLuaDEID, cntr )
        if ( nRet ~= 0 ) then return 1, "获取【容器】失败! " .. cntr end        
    else
        if ( cntr == nil or  cntr.cls ~= "Container" ) then 
            return 1, "wms_cntr.SetLock 函数中 cntr 不能为空,并且必须是容器对象"
        end
    end
    if ( lock_op_no == nil ) then lock_op_no = '' end

    local lock_state
    if ( type(str_lock_state) == "string") then
        lock_state = wms_base.Get_nConst( strLuaDEID, str_lock_state )
    else
        lock_state = str_lock_state
    end
    local lock_state_name = wms_base.GetDictItemName( strLuaDEID, "WMS_LocationLockState", lock_state )

    if ( lock_state ~= 0 ) then
        -- 如果已经有锁是不能继续加其它锁的
        if (cntr.lock_state ~= 0) then
            return 1, "容器'"..cntr.code.."'已经被业务'"..cntr.lock_op_code.."'锁定，不能继续加锁!"
        end
    end

    -- 更新容器表Lock相关属性
    local strCondition = "S_CODE = '"..cntr.code.."'"
    local strSetAttr = "N_LOCK_STATE = "..lock_state..", S_LOCK_STATE = '"..lock_state_name.."', S_LOCK_OP_CODE ='"..lock_op_no.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Container", strCondition, strSetAttr )
    if ( nRet ~= 0 ) then  
        return 2, "更新【容器】锁状态失败!"..strRetInfo
    end   
    return 0, ""  
end

-- 计算料箱料格最多能装几个SKU，这里不考虑超重的情况
-- @function wms_cntr.Calculate_Cell_Capacity
-- @tparam table ctd 容器类型定义对象, 必须有值
-- @tparam string cell_type 料格类型, 必须有值
-- @tparam table sku SKU货品对象（含S_COUNT_METHOD等属性）, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn number capacity 成功时返回料格可装载的货品数量
function wms_cntr.Calculate_Cell_Capacity( ctd, cell_type, sku )
    local sku_count_method = sku.S_COUNT_METHOD or ''
    local cell_max_weight = 0
    local capacity = 0
    local nRet, weight, volume
    -- ecda_rule 料箱定义里定义的 空料箱呼出规则
    -- sku_count_method 货品在一个料格里能存储多少个的计算方法

    -- 获取料格计数的一些基本属性
    if sku_count_method == "Limit" then
        -- 如果料格是通过数量限制是否满格
        local sku_grid_parm, success
        if ctd.ecda_rule == "Flex match" then
            sku_grid_parm = sku.sku_grid_parm
            if sku_grid_parm == nil then
                if not lua.StrIsEmpty( sku.S_SKU_GRID_PARM ) then
                    success, sku_grid_parm = pcall( json.decode, sku.S_SKU_GRID_PARM )
                    if ( success == false ) then
                        return 1, "SKU 编码 = '"..sku.S_ITEM_CODE.."' 的数据对象中 S_SKU_GRID_PARM 不符合json规范!" 
                    end  
                else
                    return 1, "SKU 编码 = '"..sku.S_ITEM_CODE.."' 的数据对象中 S_SKU_GRID_PARM 不合规!"
                end
            end  
            local item_key = sku.S_ITEM_CODE..'/'..sku.S_STORER
            nRet, capacity = wms_base.Get_LoadingLimit( item_key, sku_grid_parm, ctd.ctd_code, cell_type )
            if nRet ~= 0 then
                return 1, capacity
            end
            if capacity <= 0 then
                return 1, "SKU 编码 = '"..sku.S_ITEM_CODE.."' 的数据对象中 S_SKU_GRID_PARM 不合规!"
            end  
            
        elseif ctd.ecda_rule == "SDM Grid" then
            if not lua.StrIsEmpty( sku.N_LOADING_LIMIT ) then
                capacity = lua.Get_NumAttrValue( sku.N_LOADING_LIMIT )
                if capacity <= 0 then
                    return 1, "SKU 编码 = '"..sku.S_ITEM_CODE.."' 的数据对象中 N_LOADING_LIMIT 不合规!"
                end
            else
                return 1, "SKU 编码 = '"..sku.S_ITEM_CODE.."' 的数据对象中 N_LOADING_LIMIT 不合规!"
            end
        else
            return 1, "容器类定义编码 = '"..ctd.ctd_code.."' 的空料箱呼出策略不符合规范!" 
        end
    elseif sku_count_method == "Weight" then
        -- 需要获取料格最大载重
        local grid_def
        nRet, grid_def = wms_cntr.Get_CTD_GridDef( ctd, cell_type )
        if nRet ~= 0 or grid_def.box_num <= 0 then
            return 1, "容器类型'"..ctd.ctd_code.."'中没有定义 cell_type = '"..cell_type.."'的定义"
        end
        cell_max_weight = ctd.load_capacity/grid_def.box_num
        if cell_max_weight <= 0 then
            return 1, "容器类型'"..ctd.ctd_code.."'中没容器载重定义不合规!"
        end

        weight = lua.Get_NumAttrValue( sku.F_WEIGHT )
        if weight <= 0 then
            return 1, "SKU 编码 = '"..sku.S_ITEM_CODE.."' 的数据对象中 F_WEIGHT 不合规!"
        end   
        capacity = cell_max_weight/weight

    elseif sku_count_method == "Volume" or sku_count_method == "Mixed" then
        volume = lua.Get_NumAttrValue( sku.F_VOLUME )
        if volume <= 0 then
            return 1, "SKU 编码 = '"..sku.S_ITEM_CODE.."' 的数据对象中 F_VOLUME 不合规!"
        end   
        local grid_def
        nRet, grid_def = wms_cntr.Get_CTD_GridDef( ctd, cell_type )
        if nRet ~= 0 or grid_def.box_num <= 0 then
            return 1, "容器类型'"..ctd.ctd_code.."'中没有定义 cell_type = '"..cell_type.."'的定义"
        end        
        capacity = grid_def.volume/volume
    elseif sku_count_method == "None" then
        return 0, 0  -- 表示不考虑数量, 这样的结果就是料箱补料是不考虑数量的，因此不建议用补料
    else
        return 1, "SKU 编码 = '"..sku.S_ITEM_CODE.."' 的数据对象中 S_COUNT_METHOD 为空或不合规!" 
    end
    return 0, capacity
end

-- 设置料格 cell_no里的属性（基于INV_Detail的汇总数据填充到对应的料格中）
-- @function wms_cntr.Set_CntrCell_Data_List
-- @tparam table ctd 容器类型定义对象
-- @tparam table cell_list 当前容器中 Container_Cell 列表
-- @tparam string cell_no 需要设置的料格编码
-- @tparam table cntr_cell 料格属性（含F_QTY, F_GOOD_VOLUME等汇总值）
-- @tparam table inv_detail_data INV_Detail中该料格的完整属性，用于提取match_attr
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string errMsg 失败时返回错误信息
function wms_cntr.Set_CntrCell_Data_List( ctd, cell_list, cell_no, cntr_cell, inv_detail_data )
    local nRet
    local volume = 0
    local limit = 0
    local weight = 0
    local sku_count_method = inv_detail_data.S_COUNT_METHOD or ''

    local cell_max_weight = lua.Get_NumAttrValue( ctd.load_capacity )
    if sku_count_method == "Weight" and cell_max_weight <= 0 then
        return 1, "容器类型'"..ctd.ctd_code.."'中没容器载重定义不合规!"
    end   

    -- 获取料格的一些基本属性
    volume = lua.Get_NumAttrValue( inv_detail_data.F_VOLUME )
    weight = lua.Get_NumAttrValue( inv_detail_data.F_WEIGHT )
    nRet, limit = wms_cntr.Calculate_Cell_Capacity( ctd, cntr_cell.S_CELL_TYPE, inv_detail_data )
    if nRet ~= 0 then
        return 1, "计算料格容量失败"..limit
    end
    -- 如果料格这里的最大SKU存储数量=0 表示不考虑数量
    if limit == 0 then
        return 0
    end

    local CNTR_CELL_ATTRS_COUNT = #CNTR_CELL_BASE_ATTRS2
    local UDF_ATTRS_COUNT = #UDF_ATTRS
    
    for n = 1, #cell_list do
        if ( cell_list[n].S_CELL_NO == cell_no ) then
            cell_list[n].F_LIMIT = limit
            cell_list[n].F_GOOD_VOLUME = cntr_cell.F_GOOD_VOLUME
            cell_list[n].F_GOOD_WEIGHT = cntr_cell.F_GOOD_WEIGHT
            cell_list[n].F_QTY = cntr_cell.F_QTY
            cell_list[n].F_REM_CAP = limit - cntr_cell.F_QTY
            cell_list[n].inv_detail_data=inv_detail_data

            for m = 1, CNTR_CELL_ATTRS_COUNT do
                cell_list[n][CNTR_CELL_BASE_ATTRS2[m]] = cntr_cell[CNTR_CELL_BASE_ATTRS2[m]]
            end
            for m = 1, UDF_ATTRS_COUNT do
                cell_list[n][UDF_ATTRS[m]] = cntr_cell[UDF_ATTRS[m]]
            end
            
            cell_list[n].S_CELL_TYPE = cntr_cell.S_CELL_TYPE
            cell_list[n].S_ITEM_CELL_TYPE = cntr_cell.S_ITEM_CELL_TYPE

            -- 如果料格被强制设置为满
            if ( cell_list[n].C_FORCED_FILL == 'Y' ) then
                cell_list[n].N_EMPTY_FULL = 2
                cell_list[n].F_CELL_UTIL = 100         -- 利用率
            else
                if sku_count_method == "Volume" or sku_count_method == "Mixed" then
                    if ( (cntr_cell.F_GOOD_VOLUME + volume) > cell_list[n].F_VOLUME ) then 
                        cell_list[n].N_EMPTY_FULL = 2
                        cell_list[n].F_CELL_UTIL = 100         -- 利用率
                    else
                        cell_list[n].N_EMPTY_FULL = 1
                        if cell_list[n].F_VOLUME > 0 then
                            cell_list[n].F_CELL_UTIL = 100*( cntr_cell.F_GOOD_VOLUME/cell_list[n].F_VOLUME )
                        end
                    end
                elseif sku_count_method == "Limit" then
                    if cntr_cell.F_QTY >= limit then
                        cell_list[n].N_EMPTY_FULL = 2
                        cell_list[n].F_CELL_UTIL = 100         -- 利用率
                    else
                        cell_list[n].N_EMPTY_FULL = 1
                        cell_list[n].F_CELL_UTIL = 100*( cntr_cell.F_QTY/limit )
                    end    
                elseif sku_count_method == "Weight" then   
                    if ( (cntr_cell.F_GOOD_WEIGHT + weight) > cell_max_weight ) then 
                        cell_list[n].N_EMPTY_FULL = 2
                        cell_list[n].F_CELL_UTIL = 100         -- 利用率
                    else
                        cell_list[n].N_EMPTY_FULL = 1
                        cell_list[n].F_CELL_UTIL = 100*( cntr_cell.F_GOOD_WEIGHT/cell_max_weight )
                    end                                                         
                end
            end
            return 0
        end
    end
    return 1, "在 Set_CntrCell_Data_List 时失败，无法匹配到料格列表! SKU -->"..inv_detail_data.S_ITEM_CODE
end

-- 更新容器料格的属性（空满状态、重量、体积、利用率等），并计算容器平均利用率
-- @function update_container_cell
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table ctd 容器类型定义对象, 必须有值
-- @tparam table cell_list 料格列表, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn number|string cntr_util 成功时返回容器平均利用率，失败时返回错误信息
local function update_container_cell( strLuaDEID, ctd, cell_list )
    local n, nRet, strRetInfo
    local strCondition, strSetAttr
    local si_match_attrs_count = #ctd.si_match_attrs
    local match_attr_update = ''
    local inv_detail_data = {}
    local cntr_cell_data
    local cntr_util = 0
    local cell_count = #cell_list

    for n = 1, cell_count do
        if ( cell_list[n].F_QTY == 0 ) then
            -- 空料格，属性全部设置为初始值
            cntr_cell_data = m3.AllocObject2( strLuaDEID, "Container_Cell" )
            cntr_cell_data.S_CNTR_CODE = cell_list[n].S_CNTR_CODE
            cntr_cell_data.S_CELL_NO = cell_list[n].S_CELL_NO
            cntr_cell_data.S_CELL_TYPE = cell_list[n].S_CELL_TYPE
            nRet, strSetAttr = mobox.objJsonToObjAttr( "Container_Cell", lua.table2str(cntr_cell_data))
            if ( nRet ~= 0 ) then 
                return nRet, strSetAttr 
            end
            nRet, strRetInfo = mobox.setDataObjAttr( strLuaDEID, "Container_Cell", cell_list[n].id, strSetAttr )
            if ( nRet ~= 0  ) then
                return 2, "setDataObjAttr 发生错误!"..strRetInfo
            end            
        else
            match_attr_update = ''
            inv_detail_data = cell_list[n].inv_detail_data
            -- 如果料格匹配还有附加的属性
            if ( si_match_attrs_count > 0 ) then
                for m = 1, si_match_attrs_count do
                    if ( lua.isTableEmpty(inv_detail_data) ) then
                        match_attr_update = match_attr_update..","..ctd.si_match_attrs[m].." = ''"
                    else
                        match_attr_update = match_attr_update..","..ctd.si_match_attrs[m].." = '"..inv_detail_data[ctd.si_match_attrs[m]].."'"
                    end
                end
            end
            cntr_util = cntr_util + cell_list[n].F_CELL_UTIL
            local rem_cap = cell_list[n].F_LIMIT - cell_list[n].F_QTY
            strCondition = " S_CELL_NO = '"..cell_list[n].S_CELL_NO.."' AND S_CNTR_CODE = '"..cell_list[n].S_CNTR_CODE.."'"
            strSetAttr = "F_GOOD_WEIGHT = "..cell_list[n].F_GOOD_WEIGHT..", F_GOOD_VOLUME = "..cell_list[n].F_GOOD_VOLUME..", N_EMPTY_FULL = "..cell_list[n].N_EMPTY_FULL..
                        ", S_ITEM_CODE = '"..cell_list[n].S_ITEM_CODE.."', S_ITEM_NAME = '"..cell_list[n].S_ITEM_NAME.."', F_QTY = "..cell_list[n].F_QTY..
                        ", S_WMS_BN = '"..cell_list[n].S_WMS_BN.."', S_ALLOC_OP_CODE = '', S_CELL_TYPE = '"..cell_list[n].S_CELL_TYPE.."'"..
                        ", S_ITEM_CELL_TYPE = '"..cell_list[n].S_ITEM_CELL_TYPE.."'"..
                        ", S_ITEM_STATE = '"..cell_list[n].S_ITEM_STATE.."', S_STORER = '"..cell_list[n].S_STORER.."'"..match_attr_update..
                        ", F_CELL_UTIL = "..cell_list[n].F_CELL_UTIL..", F_REM_CAP = "..rem_cap..", F_LIMIT = "..cell_list[n].F_LIMIT
                        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Container_Cell", strCondition, strSetAttr )
            if ( nRet ~= 0 ) then  
                return 2, "更新【容器料格】信息失败!"..strRetInfo 
            end 
        end
    end
    if cell_count > 0 then
        cntr_util = cntr_util/cell_count
    end
    return 0, cntr_util
end

-- 获取料箱中空料格的数量（N_EMPTY_FULL == 0）
-- @function get_empty_cell_num
-- @tparam table cell_list 料格列表, 必须有值
-- @treturn number num 空料格数量
local function get_empty_cell_num( cell_list )
    local n, num

    num = 0
    for n = 1, #cell_list do
        if ( cell_list[n].N_EMPTY_FULL == 0 ) then
            num = num + 1
        end
    end
    return num
end

-- 根据料格的空满状态判断容器是否可以设置为满状态（所有料格都满或强制满）
-- @function cntr_is_full
-- @tparam table cell_list 料格列表, 必须有值
-- @treturn boolean 所有料格都已满则返回true，否则返回false
local function cntr_is_full( cell_list )
    local n, nCount, full_cell_count

    nCount = #cell_list
    full_cell_count = 0
    for n = 1, nCount do
        if ( cell_list[n].C_FORCED_FILL == 'Y' or cell_list[n].N_EMPTY_FULL == 2 ) then
            full_cell_count = full_cell_count + 1
        end
    end
    if ( full_cell_count == nCount ) then 
        return true 
    end
    return false
end

-- 根据INV_Detail中的信息重新计算容器和料格的各项属性（料箱库必须使用）
-- 包括料格和料箱的空满状态、最大装载数量、还可装载数量、货品数量、总体积、总重量等
-- @function cntr_reset_by_inv_detail
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table ctd 容器类型定义对象, 必须有值
-- @tparam table cntr 容器对象, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string errMsg 失败时返回错误信息
local function cntr_reset_by_inv_detail( strLuaDEID, ctd, cntr )
    local strCondition
    local data_objs
    local nRet, strRetInfo    

    strCondition = "S_CNTR_CODE = '"..cntr.code.."'"
    local strOrder = "" 
    local cntr_loc_pos = ""
    local cell_type = cntr.spec
    local count_method = ctd.count_method or ''
    -- 获取容器的装载限制
    local cntr_max_volume = ctd.data.F_MAX_VOLUME or 0
    local cntr_max_weight = ctd.data.F_LOAD_CAPACITY or 0
    local cntr_max_scu = ctd.data.F_MAX_SCU or 0

    --[[ 暂时取消 20260903
    if count_method == '' then
        return 2, "容器类型'" .. ctd.ctd_code.."'没有定义计数方式!"
    end
    ]]
    -- 获取料箱位置 cntr_loc_pos
    nRet, strRetInfo = mobox.queryOneDataObjAttr(strLuaDEID, "Loc_Container", strCondition, strOrder, "S_LOC_CODE" )
    if nRet ~= 0 then
        return 2, "获取【货位容器绑定】信息失败! " .. strRetInfo 
    end
    if ( strRetInfo ~= "") then 
        local ret_info = json.decode(strRetInfo)
        cntr_loc_pos = ret_info.attrs[1].value
    end

    -- type = Cell_Box 是带料格的容器
    if ( cntr.type == "Cell_Box" ) then
        strCondition = "S_CNTR_CODE = '"..cntr.code.."'"        
        nRet, data_objs = m3.QueryDataObject(strLuaDEID, "Container_Cell", strCondition, "S_CELL_NO" )
        if nRet ~= 0 then 
            return 2, "QueryDataObject失败!"..data_objs 
        end
        if ( data_objs == '' ) then return 0  end
        
        local nCellCount

        nCellCount = #data_objs
        if ( 0 == nCellCount ) then return 0 end

        local cell_list = {}
        local obj_attrs

        for n = 1, nCellCount do
            obj_attrs = m3.KeyValueAttrsToObjAttr(data_objs[n].attrs)
            if obj_attrs == nil then
                return 1, "属性转化错误!"
            end
            local cell = {
                id = data_objs[n].id,

                S_CNTR_CODE = obj_attrs.S_CNTR_CODE,
                S_CELL_NO = obj_attrs.S_CELL_NO,
                S_CELL_TYPE = obj_attrs.S_CELL_TYPE,
                F_QTY = 0,
                F_LIMIT = 0,      -- 容量
                F_REM_CAP = 0,
                F_VOLUME = lua.StrToNumber( obj_attrs.F_VOLUME ),   -- 料格体积
                C_FORCED_FILL = obj_attrs.C_FORCED_FILL,
                F_GOOD_VOLUME = 0,
                F_GOOD_WEIGHT = 0,
                N_EMPTY_FULL = 0,               
                inv_detail_data = {}
            }
            table.insert( cell_list, cell )
        end

        -- 获取 INV_Detial + SKU 中的属性
        local strTable = "TN_INV_Detail a LEFT JOIN TN_SKU b ON ( a.S_ITEM_CODE = b.S_ITEM_CODE and a.S_STORER = b.S_STORER )" 
        -- 要查询的属性
        local strAttrs = ""
        local attr_set = {}
        local ITEM_BASE_ATTR_COUNT = #ITEM_BASE_ATTRS2
        local CNTR_CELL_COUNT = #CNTR_CELL_BASE_ATTRS

        local attrs = {}
        for m = 1, CNTR_CELL_COUNT do
            table.insert( attrs, "a."..CNTR_CELL_BASE_ATTRS[m] )
            --strAttrs = strAttrs.."a."..CNTR_CELL_BASE_ATTRS[m]..","
            table.insert( attr_set, CNTR_CELL_BASE_ATTRS[m] )
        end
        local UDF_ATTRS_COUNT = #UDF_ATTRS
        for m = 1, UDF_ATTRS_COUNT do
            table.insert( attrs, "a."..UDF_ATTRS[m] )
            --strAttrs = strAttrs.."a."..UDF_ATTRS[m]..","
            table.insert( attr_set, UDF_ATTRS[m] )
        end
        strAttrs = table.concat( attrs, ",")
        strAttrs = strAttrs..",b.F_VOLUME, b.F_WEIGHT, b.S_CELL_TYPE, b.S_SKU_GRID_PARM, b.S_COUNT_METHOD, b.N_LOADING_LIMIT"
        table.insert( attr_set, "F_VOLUME" )
        table.insert( attr_set, "F_WEIGHT" )
        table.insert( attr_set, "S_CELL_TYPE" )
        table.insert( attr_set, "S_SKU_GRID_PARM" )
        table.insert( attr_set, "S_COUNT_METHOD" )  
        table.insert( attr_set, "N_LOADING_LIMIT" )

        -- 入库批次也要进行排序
        strOrder = "a.S_CELL_NO, a.S_WMS_BN"
        strCondition = "a.S_CNTR_CODE = '"..cntr.code.."'"
        nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 2000, strCondition, strOrder )
        if ( nRet ~= 0 ) then return 2, "queryMultiTable 失败!"..strRetInfo end
        local nCount
        local ret_data = {}
        if ( strRetInfo ~= '' ) then     
            ret_data = json.decode(strRetInfo)
            nCount  = #ret_data
        else
            nCount = 0
        end

        local cell_no
        local current_cell_no = ''
        local sum_volume, sum_weight, sum_qty
        local volume, weight, qty
        local cg_detail_count = nCount
        local good_weight, good_volume, good_num

        -- 计算料箱料格的体积、重量，已经料箱格的空满状态
        -- 料格里的货品重量、体积
        sum_volume = 0
        sum_weight = 0
        sum_qty = 0
        -- 整个料箱里的货品重量、体积
        good_weight = 0
        good_volume = 0
        good_num = 0

        local cntr_cell = {}
        local inv_detail_data = {}
        local data_obj
        local mixing_rule_value = {}        -- 混箱属性值 {S_BATCH_NO = 'x'}

        if ( nCount > 0 ) then
            for n = 1, nCount do
                nRet, data_obj = lua.GetDataAttrObj_By_StrArray( attr_set, ret_data[n] )
                if ( nRet ~= 0 ) then
                    return 1, data_obj
                end
                cell_no = lua.Get_StrAttrValue( data_obj.S_CELL_NO )  
                if ( current_cell_no == '' ) then
                    current_cell_no = cell_no
                end
                if ( current_cell_no ~= cell_no ) then
                    cntr_cell.F_QTY = sum_qty
                    cntr_cell.F_GOOD_VOLUME = sum_volume
                    cntr_cell.F_GOOD_WEIGHT = sum_weight
                    nRet, strRetInfo = wms_cntr.Set_CntrCell_Data_List( ctd, cell_list, current_cell_no, cntr_cell, inv_detail_data )
                    if nRet ~= 0 then
                        return 1, strRetInfo
                    end

                    sum_volume = 0
                    sum_weight = 0 
                    sum_qty = 0
                    current_cell_no = cell_no           
                end

                if ctd.have_mixing_rule then
                    -- 获取混箱属性
                    for _, mixing_attr in ipairs(ctd.mixing_attrs) do
                        mixing_rule_value[mixing_attr] = data_obj[mixing_attr]
                    end
                end
                cntr_cell.S_CELL_TYPE = cell_type
                cntr_cell.S_ITEM_CELL_TYPE = lua.Get_StrAttrValue( data_obj.S_CELL_TYPE )  
                for m = 1, ITEM_BASE_ATTR_COUNT do
                    cntr_cell[ITEM_BASE_ATTRS2[m]] = data_obj[ITEM_BASE_ATTRS2[m]]
                end
              
                inv_detail_data = data_obj

                qty = lua.Get_NumAttrValue( data_obj.F_QTY )    
                volume = lua.Get_NumAttrValue( data_obj.F_VOLUME )   
                weight = lua.Get_NumAttrValue( data_obj.F_WEIGHT)   
                cntr_cell.S_ITEM_CELL_TYPE = lua.Get_StrAttrValue( data_obj.S_CELL_TYPE )  

                volume = volume*qty
                weight = weight*qty

                good_weight = good_weight + weight
                good_volume = good_volume + volume
                good_num = good_num + qty

                sum_volume = sum_volume + volume
                sum_weight = sum_weight + weight
                sum_qty = sum_qty + qty
            end
            cntr_cell.F_QTY = sum_qty
            cntr_cell.F_GOOD_VOLUME = sum_volume
            cntr_cell.F_GOOD_WEIGHT = sum_weight
            
            nRet, strRetInfo = wms_cntr.Set_CntrCell_Data_List( ctd, cell_list, current_cell_no, cntr_cell, inv_detail_data )
            
            if nRet ~= 0 then
                return 1, strRetInfo
            end

            -- 设置 容器扩展属性
            if ctd.have_mixing_rule then
                nRet, strRetInfo = wms_cntr.Add_CNTR_ExtInfo( strLuaDEID, cntr.code, ctd.mixing_attrs, mixing_rule_value )
                if nRet ~= 0 then
                    return 1, strRetInfo
                end                
            end
        else
            -- 空料箱，混箱属性也需要清空
            if ctd.have_mixing_rule then
                strCondition = "S_CNTR_CODE = '" .. cntr.code .."'"
                nRet, strRetInfo = mobox.dbdeleteData(strLuaDEID, "Container_Ext", strCondition)
                if (nRet ~= 0) then 
                    return 1, "删除【Container_Ext】失败!"..strRetInfo
                end                   
            end
        end

        -- 更新【容器料格】属性
        local cntr_util = 0     -- 容器利用率
        nRet, cntr_util = update_container_cell( strLuaDEID, ctd, cell_list )
        if ( nRet ~= 0 ) then 
            return 2, cntr_util 
        end
        
        -- 更新【容器】本身属性
        local empty_cell_num  = get_empty_cell_num( cell_list )
        local strSetAttr
        local empty_full = 0
        
        -- V2.0 MDF BY WHB 对容器空满状态判断的改进
        if ( cntr.forced_fill == 'Y' ) then
            empty_full = 2
        else
            if ( empty_cell_num == cntr.max_cell_num ) then
                empty_full = 0
            else
                empty_full = 1
                if ( 0 == empty_cell_num ) then
                    -- 判断一下容器里的料格是否都是已经满，那么料箱也要设置为满
                    if ( cntr_is_full( cell_list ) ) then
                        empty_full = 2
                    end
                end
            end
        end
        if ( cntr.max_weight > 0 ) then
            if ( ( good_weight + cntr.weight ) >= cntr.max_weight ) then
                empty_full = 2
            end
        end

        strCondition = "S_CODE = '"..cntr.code.."'"
        strSetAttr = "N_ALLOC_CELL_NUM = 0, N_EMPTY_CELL_NUM = "..empty_cell_num..", N_EMPTY_FULL = "..empty_full..", N_DETAIL_COUNT = "..cg_detail_count..
                     ", F_GOOD_WEIGHT = "..good_weight..", F_GOOD_VOLUME = "..good_volume..", N_GOOD_NUM = "..good_num..", S_POSITION = '"..cntr_loc_pos.."'"..
                     ", F_CNTR_UTIL = "..cntr_util
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Container", strCondition, strSetAttr )
        if ( nRet ~= 0 ) then  return 2, "更新【容器料格】信息失败!"..strRetInfo end 
    else
        -- 重置一下 容器中的 N_DETAIL_COUNT 即可
        strCondition = "S_CNTR_CODE = '"..cntr.code.."'"
        nRet, strRetInfo = mobox.getDataObjCount( strLuaDEID, "INV_Detail", strCondition )
        if ( nRet ~= 0 ) then 
            return 2, strRetInfo 
        end 
        local nCount = lua.StrToNumber( strRetInfo )

        -- 如果料箱计数类型为 SCU 需要统计一下，货品的 SCU 累计值
        local set_attr = ''
        local sum_value = nil  -- 初始化为 nil
        nRet, strRetInfo = mobox.getDataObjAttrSum( strLuaDEID, "INV_Detail", strCondition, "F_SUM_SCU", "F_SUM_VOLUME", "F_SUM_WEIGHT", "F_QTY")
        if nRet ~= 0 then
            return 2, strRetInfo
        end
        local scu, volume, weight, good_num = 0, 0, 0, 0
        if strRetInfo ~= '' then
            sum_value = json.decode( strRetInfo )
            if sum_value then
                scu = lua.Get_NumAttrValue( sum_value[1] )
                volume = lua.Get_NumAttrValue( sum_value[2] )
                weight = lua.Get_NumAttrValue( sum_value[3] )
                good_num = lua.Get_NumAttrValue( sum_value[4] )
                set_attr = ", F_SCU_VALUE = "..scu..", F_GOOD_VOLUME = "..volume..", F_GOOD_WEIGHT = "..weight..", N_GOOD_NUM = "..good_num
            end
        end
        local empty_full = 1
        if nCount == 0 then
            empty_full = 0
        else
            if sum_value ~= nil then
                if count_method == 'SCU' then
                    local max_scu = lua.Get_NumAttrValue(ctd.max_scu_value)
                    if max_scu > 0 and scu >= max_scu then
                        empty_full = 2
                    end
                else
                    if cntr_max_volume > 0 and volume >= cntr_max_volume then
                        empty_full = 2
                    elseif cntr_max_weight > 0 and weight >= cntr_max_weight then
                        empty_full = 2
                    end
                end
            end
        end
        set_attr = set_attr..", N_EMPTY_FULL = "..empty_full
        strCondition = "S_CODE = '"..cntr.code.."'"       
        local strSetAttr = "N_DETAIL_COUNT = "..nCount..", S_POSITION = '"..cntr_loc_pos.."'"..set_attr
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Container", strCondition, strSetAttr )
        if ( nRet ~= 0 ) then
            return 2, "更新【容器料格】信息失败!"..strRetInfo
        end
        if nCount == 0 then
            -- 空料箱，混箱属性也需要清空
            if ctd.have_mixing_rule then
                strCondition = "S_CNTR_CODE = '" .. cntr.code .."'"
                nRet, strRetInfo = mobox.dbdeleteData(strLuaDEID, "Container_Ext", strCondition)
                if (nRet ~= 0) then 
                    return 1, "删除【Container_Ext】失败!"..strRetInfo
                end                   
            end            
        else
            strCondition = "S_CNTR_CODE = '"..cntr.code.."'"
            nRet, data_obj = m3.GetDataObjByCondition2( strLuaDEID, "INV_Detail", strCondition, "T_CREATE" )
            if ( nRet == 0  ) then
                nRet, strRetInfo = wms_cntr.Add_CNTR_ExtInfo( strLuaDEID, cntr.code, ctd.mixing_attrs, data_obj )
                if nRet ~= 0 then
                    return 1, strRetInfo
                end                                 
            end
        end

    end
    return 0
end

-- 重置容器的料格属性和容器本身属性（基于INV_Detail重新计算）
-- @function wms_cntr.Reset
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table cntr 容器对象, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string errMsg 失败时返回错误信息
function wms_cntr.Reset( strLuaDEID, cntr )
    local nRet, strRetInfo

    if cntr == nil or type(cntr) ~= 'table' then
        return 1, "Rest函数中cntr必须有值,必须是table类型!"
    end
    local ctd       -- 容器类型定义
    nRet, ctd = wms_cntr.GetCTDInfo( cntr.ctd_code, strLuaDEID )
    if ( nRet ~= 0 ) then
        return 2, ctd
    end    

    -- 重置容器属性
    nRet, strRetInfo = cntr_reset_by_inv_detail( strLuaDEID, ctd, cntr )
    if ( nRet ~= 0 ) then
        return 2, strRetInfo
    end          
    return 0 
end

-- 给容器加锁（调用 wms_LockCntr 然后更新 Container 表）
-- @function wms_cntr.Lock
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @tparam number lock_state 锁状态数值
-- @tparam string op_code 加锁的业务编码
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string errMsg 失败时返回错误信息
function wms_cntr.Lock( strLuaDEID, cntr_code, lock_state, op_code )
    local nRet, strRetInfo

    nRet, strRetInfo = wms.wms_LockCntr( strLuaDEID, cntr_code, 2, op_code )
    if ( nRet ~= 0 ) then
        return 1, "给容器'"..cntr_code.."'加出库锁失败!"  
    end 

    local strCondition = "S_CODE = '"..cntr_code.."'"
    local strSetAttr = "N_LOCK_STATE = "..lock_state..", S_LOCK_OP_CODE = '"..op_code.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Container", strCondition, strSetAttr )
    if (nRet ~= 0) then 
        return 2, "设置【Container】状态失败!"..strRetInfo 
    end

    return 0
end

-- 预分配一个容器料格（容器 N_ALLOC_CELL_NUM + 1，料格 N_EMPTY_FULL = 3）
-- @function wms_cntr.CNTR_cell_alloc_set
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @tparam string cell_no 料格编码, 必须有值
-- @tparam string bs_no 产生预分配料格的业务编码
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string errMsg 失败时返回错误信息
function wms_cntr.CNTR_cell_alloc_set( strLuaDEID, cntr_code, cell_no, bs_no )
    local nRet, strRetInfo
    local strCondition = "S_CODE = '"..cntr_code.."'"
    local strUpdateSql = "N_ALLOC_CELL_NUM = N_ALLOC_CELL_NUM + 1"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Container", strCondition, strUpdateSql )
    if ( nRet ~= 0 ) then  return 1, strRetInfo end

    strCondition = "S_CELL_NO = '"..cell_no.."' AND S_CNTR_CODE = '"..cntr_code.."'"
    strUpdateSql = "N_EMPTY_FULL = 3, S_ALLOC_OP_CODE = '"..bs_no.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Container_Cell", strCondition, strUpdateSql )
    if ( nRet ~= 0 ) then 
        return 1, strRetInfo
    end
    return 0
end

-- 检查容器是否可以用于作业中（如果容器在一个未完成的作业中则不可用）
-- @function wms_cntr.CanUsedInOperation
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn boolean can_usedinop true表示可用于作业，false表示不可用
function wms_cntr.CanUsedInOperation( strLuaDEID, cntr_code )
    local nRet, strRetInfo

    if cntr_code == '' or cntr_code == nil then
        return 1, "CanUsedInOperation 函数中参数 cntr_code 必须有值!"
    end

    -- 作业状态不等于完成, 已经启动过被挂起说明作业的启动条件已经具备
    local strCondition = "N_B_STATE <> "..OPERATION_STATE.Finish.." AND N_B_STATE < "..OPERATION_STATE.Cancel.." AND S_CNTR_CODE = '"..cntr_code.."'"
    nRet, strRetInfo = mobox.existThisData( strLuaDEID, "Operation", strCondition )
    if nRet ~= 0 then 
        return 2, strRetInfo
    end
    if strRetInfo == "yes" then
        -- 检测容器已经存在没完成的作业 
        return 0, false 
    end
    return 0, true
end

-- 检查混箱/匹配等属性是否正确，并返回这些属性的类型值
-- @function check_attrs
-- @tparam string str_attrs 属性字符串（如 "S_BATCH_NO;S_UDF01"）, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn table attrs 属性列表 {"S_BATCH_NO", "S_UDF01", ...}
-- @treturn table attrs_def_list 属性类型定义列表 { { attr = "S_ITEM_CODE", type = "string" }, ... }
local function check_attrs( str_attrs )
    local nRet, strRetInfo
    local attr_type
    local attrs_def_list = {}
    local attrs = {}
    local attr_type_def = {}
    
    if str_attrs == nil or str_attrs == '' then
        return 0, {}, {}
    end
    local seg = lua.split( str_attrs, ";" )    
    for i = 1, #seg do
        table.insert( attrs, seg[i] )
    end
    -- 获取匹配属性的类型（数据类为 INV_Detail）

    nRet, strRetInfo = mobox.getClassAttrType( "INV_Detail", lua.table2str( attrs ) )   
    if nRet ~= 0 then
        return 1, strRetInfo
    end     
    attr_type_def = json.decode( strRetInfo )
 
    -- 默认属性的类型全部是字符串，用下面的暂时替换一下，以后再细化
    for _, attr in ipairs( attrs ) do
        attr_type_def[attr] = "char"
    end
    
    local val
    for _, attr in ipairs( attrs ) do
        attr_type = attr_type_def[attr] or ''
        val = ''
        if attr_type == '' then
            return 1, "属性'"..attr.."'不是 INV_Detail 中定义的属性!"
        elseif attr_type == 'int' or attr_type == 'float' or attr_type == 'bigint' or attr_type == 'dict-int' or attr_type == 'computed' then
            val = 'number'
        else
            val = 'string'
        end
        local new_attr_type = {
            attr = attr, type = val
        } 
        table.insert( attrs_def_list, new_attr_type ) 
    end
    return 0, attrs, attrs_def_list
end

-- 料格定义按 box_num 升序排序的比较函数
-- @function grid_box_num_sort
-- @tparam table a 料格定义对象
-- @tparam table b 料格定义对象
-- @treturn boolean a.box_num < b.box_num 时返回true
local function grid_box_num_sort( a, b )
    return a.box_num < b.box_num
end

-- 获取容器类型定义数据对象（含混箱规则、补料规则、料格定义等扩展属性）
-- @function wms_cntr.GetCTDInfo
-- @tparam string ctd_code 容器类型定义编码, 必须有值
-- @tparam string strLuaDEID Lua数据交换区句柄, 如果项目中的容器是嵌套类型的必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn table ctd 成功时返回容器类型定义对象，含以下扩展属性:
--   code              - 容器定义编码
--   type              - 容器类型（如 Cell_Box）
--   mixing_attrs_def  - 混箱属性的字段定义（string/number）
--   mixing_attrs      - 混箱属性字段列表
--   have_mixing_rule  - 是否有混箱规则（boolean）
--   si_enable         - 是否允许补料（boolean）
--   si_match_attrs_def - 补料属性的字段定义（string/number）
--   si_match_attrs    - 补料属性字段列表
--   check_capacity    - 是否超重检查（boolean）
--   qty_merge         - 料格货品数量是否可合并（boolean）
--   merge_attrs_def   - 合并数量属性字段定义（string/number）
--   merge_attrs       - 合并数量属性字段列表
--   grid_box_def      - 料箱中料格定义
--   mobile_rack_def   - 移动托盘中料格定义 {layer = 5, cell_per_layer = 2 }
--   nest_check_func   - 嵌套检查函数 {module_name = '',function_name = '' }
--   
function wms_cntr.GetCTDInfo( ctd_code, strLuaDEID )
    local nRet, strRetInfo, ctd_data

    if ( ctd_code == nil or ctd_code == '' ) then
        return 1, "GetCTDInfo 函数中 ctd_code 不能为空!"
    end
    if strLuaDEID == nil then
        strLuaDEID = ''
    end

    -- 先从缓存中获取，是否有存在
    local ctd, success    
    nRet, ctd_data = mobox.getCacheValue( ctd_code, "Container_Type_Def" )
    if nRet == 0  then
        if ctd_data ~= '' then
            success, ctd = pcall( json.decode, ctd_data )
            if success then
                return 0, ctd
            end        
        end
    end

    -- 没有从缓存中获取到，从数据库中获取
    nRet, ctd_data = m3.GetDataFromCache( "Container_Type_Def", ctd_code )
    if nRet ~= 0 then
        return 2, ctd_data
    end

    nRet, strRetInfo = mobox.objJsonToLuaJson( "Container_Type_Def", lua.table2str(ctd_data) )
    if ( nRet ~= 0 ) then
        return 1, strRetInfo
    end

    success, ctd = pcall( json.decode, strRetInfo )
    if ( success == false ) then
        return 1,"objJsonToLuaJson('Container') 返回的的JSON格式不合法! --> "..strRetInfo 
    end
    
    -- 混箱规则，如果 mixing_attrs_def 有值满足这些要求的SKU才能放一个料箱
    local str_val = ctd_data.S_MIXING_RULE or ''
    ctd.code = ctd_data.S_CTD_CODE
    ctd.data = ctd_data
    ctd.mixing_attrs_def = {}
    ctd.mixing_attrs = {}
    ctd.have_mixing_rule = false
    if ( str_val ~= '' ) then
        nRet, ctd.mixing_attrs, ctd.mixing_attrs_def = check_attrs( str_val ) 
        if nRet ~= 0 then
            return 1, ctd.mixing_attrs
        end 
        if #ctd.mixing_attrs_def > 0 then
            ctd.have_mixing_rule = true    
        end        
    end

    -- 料格里符合下面条件的SKU可以加入这个料格
    ctd.si_enable = ctd.si_enable == 'Y' and true or false
    ctd.si_match_attrs_def = {}
    ctd.si_match_attrs = {}
    str_val = ctd_data.S_SI_MATCH_ATTRS or ''
    if ( str_val ~= '' ) then
        nRet, ctd.si_match_attrs, ctd.si_match_attrs_def = check_attrs( str_val ) 
        if nRet ~= 0 then
            return 1, ctd.si_match_attrs
        end         
    end

    -- 料格里符合下面条件的SKU数量可以相加
    ctd.qty_merge = ctd.qty_merge == 'Y' and true or false  
    ctd.merge_attrs_def = {}
    ctd.merge_attrs = {}
    str_val = ctd_data.S_MERGE_ATTRS or ''
    if ( str_val ~= '' ) then
        nRet, ctd.merge_attrs, ctd.merge_attrs_def = check_attrs( str_val ) 
        if nRet ~= 0 then
            return 1, ctd.merge_attrs
        end          
    end    

    ctd.check_capacity = ctd.check_capacity == 'Y' and true or false 
    str_val = ctd_data.S_GRID_BOX_DEF or ''
    if ( str_val ~= '' ) then
        local success
        success, ctd.grid_box_def = pcall( json.decode, str_val )
        if ( success == false ) then
            return 1, "容器类型定义'"..ctd.ctd_code.."'中的料格定义不合规!"
        end
        -- 检查输入的 box_num 不能为 <=0
        for _, box_def in ipairs( ctd.grid_box_def ) do
            if box_def.box_num <= 0 then
                return 1, "容器类型定义'"..ctd.ctd_code.."'中的料格定义不合规! box_num 必须大于0"
            end
            box_def.is_smallest = false  -- 是这种类型料箱中最小的料格
        end    
        -- grid_box_def 根据料格数量进行排序
        table.sort( ctd.grid_box_def, grid_box_num_sort )
        ctd.grid_box_def[#ctd.grid_box_def].is_smallest = true
    else
        ctd.grid_box_def = {}
    end

    -- MDF BY HAN @20260723
    str_val = ctd_data.S_MOBILE_RACK_DEF or ''
    ctd.mobile_rack_def = {}
    if str_val ~= '' then
        local success
        success, ctd.mobile_rack_def = pcall( json.decode, str_val )
        if not success then
            return 1, "容器类型定义'"..ctd.ctd_code.."'中的 S_MOBILE_RACK_DEF 定义不合规!"
        end
        -- 检查移动料格定义中的属性
        local layer = ctd.mobile_rack_def.layer or 0
        local cell_per_layer = ctd.mobile_rack_def.cell_per_layer or 0
        if layer <= 0 or cell_per_layer <= 0 then
            return 1, "容器类型定义'"..ctd.ctd_code.."'中的 S_MOBILE_RACK_DEF 定义不合规! layer 和 cell_per_layer 必须大于0"
        end
        ctd.mobile_rack_def.cell_num = layer * cell_per_layer
    end   
    -- 如果带嵌套好检查一下嵌套检查函数
    str_val = ctd_data.C_IS_NESTABLE or ''
    ctd.nest_check_func = {}
    ctd.nest_rule = {}
    if str_val == 'Y' then
        str_val = ctd_data.NEST_CHECK_FUNC or ''
        if str_val ~= '' then
            local success
            success, ctd.nest_check_func = pcall( json.decode, str_val )
            if not success then
                return 1, "容器类型定义'"..ctd.ctd_code.."'中的 NEST_CHECK_FUNC 定义不合规!"
            end
            local module_name = ctd.nest_check_func.module_name or ''
            local func_name = ctd.nest_check_func.function_name or ''
            if module_name == '' or func_name == '' then
                return 1, "容器类型定义'"..ctd.ctd_code.."'中的 NEST_CHECK_FUNC 定义不合规! module_name 和 function_name 不能为空"
            end            
        end
        -- 装载 Container_Nest_Rule
        if strLuaDEID == '' then
            return 1, "容器类型定义'"..ctd.ctd_code.."'是嵌套容器 strLuaDEID 不能为空"
        end
        local nest_rule_data
        local strCondition = "S_P_CTD_CODE = '"..ctd_code.."'"
        nRet, nest_rule_data = m3.QueryDataObject(strLuaDEID, "Container_Nest_Rule", strCondition )
        if nRet ~= 0 then 
            return 2, "QueryDataObject失败!" .. nest_rule_data 
        end
        if nest_rule_data ~= '' then 
            local nest_rule
            for n = 1, #nest_rule_data do
                nest_rule = m3.KeyValueAttrsToObjAttr(nest_rule_data[n].attrs)
                if nest_rule == nil then
                    return 1, "容器类型定义'"..ctd.ctd_code.."'中的 Container_Nest_Rule 定义不合规!"    
                end
                local neset_rule = {
                    ctd_code = nest_rule.S_S_CTD_CODE,
                    max_qty = tonumber(nest_rule.N_MAX_QTY) or 0
                }
                table.insert( ctd.nest_rule, neset_rule )
            end
        end
    end

    -- 把容器类型定义作为缓存进行永久保存
    nRet, strRetInfo = mobox.setCacheValue( ctd_code, lua.table2str(ctd), "Container_Type_Def", 1 )
    if nRet ~= 0 then
        return 1, strRetInfo
    end
    
    return 0, ctd
end

-- 根据 cell_type 获取料格定义
-- @function wms_cntr.Get_CTD_GridDef
-- @tparam table ctd 容器类型定义对象, 必须有值
-- @tparam string cell_type 料格类型（如 A/B/C）, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn table box_def_item 料格定义对象 { cell_type = "A", volume = 72000, box_num = 1, long = x, middle = y, short = z }
function wms_cntr.Get_CTD_GridDef( ctd, cell_type )
    if ctd == nil or cell_type == nil then
        return 1, "wms_cntr.Get_CTD_GridDef 函数输入参数不能为 nil"
    end
    for _, box_def_item in ipairs( ctd.grid_box_def) do
        if box_def_item.cell_type == cell_type then
            return 0, box_def_item
        end
    end
    return 1, "在容器类型定义中无法获取料格类型 = '"..cell_type.."' 的料格定义"
end

-- 根据 cell_type 获取下一个等级的料格定义
-- @function wms_cntr.Get_CTD_Next_GridDef
-- @tparam table ctd 容器类型定义对象, 必须有值
-- @tparam string cell_type 料格类型（如 A/B/C）, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn table|nil box_def_item 下一个料格定义，已是最后一级则返回nil
function wms_cntr.Get_CTD_Next_GridDef( ctd, cell_type )
    if ctd == nil or cell_type == nil then
        return 1, "wms_cntr.Get_CTD_Next_GridDef 函数输入参数不能为 nil"
    end
    for n, box_def_item in ipairs( ctd.grid_box_def) do
        if box_def_item.cell_type == cell_type then
            if n == #ctd.grid_box_def then
                return 0, nil
            end
            return 0, ctd.grid_box_def[n+1]
        end
    end
    return 1, "在容器类型定义中无法获取料格类型 = '"..cell_type.."' 的料格定义"
end

-- 获取指定料格类型的体积和重量限制
-- @function wms_cntr.Get_Cell_Volume_Weight
-- @tparam table ctd 容器类型定义对象, 必须有值
-- @tparam string cell_type 料格类型, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn number cell_max_volume 料格最大体积
-- @treturn number cell_max_weight 料格最大载重
function wms_cntr.Get_Cell_Volume_Weight( ctd, cell_type )
    local n
    local cell_max_volume = 0
    local cell_max_weight = 0
    local cntr_max_weight = lua.Get_NumAttrValue( ctd.load_capacity )

    -- 获取料格的体积
    for n = 1, #ctd.grid_box_def do
        if ( ctd.grid_box_def[n].cell_type == cell_type ) then
            cell_max_volume = lua.Get_NumAttrValue( ctd.grid_box_def[n].volume )
            cell_max_weight  = lua.Get_NumAttrValue( ctd.grid_box_def[n].weight )
            if cell_max_weight <= 0 then
                -- 如果没定义料格载重就用容器总载重除料格数量
                if ctd.grid_box_def[n].box_num > 0 then
                    cell_max_weight = cntr_max_weight/ctd.grid_box_def[n].box_num
                end
            end
            return 0, cell_max_volume, cell_max_weight
        end
    end  
    return 1, "系统无法找到料格的体积、重量限制!"   
end

-- 计算料格能装多少个SKU货品（用于补料场景）
-- 根据SKU的 S_COUNT_METHOD 计算: Weight-按重量, Volume-按体积, Limit-按数量限制, Mixed-取重量和体积的最小值
-- @function wms_cntr.Get_CntrCell_Goods_Qty
-- @tparam table ctd 容器类型定义对象, 必须有值
-- @tparam number cntr_good_weight 当前容器货品总重量
-- @tparam table container_cell 容器料格对象 { qty, cntr_code, cell_no, cell_type, good_volume, good_weight }
-- @tparam table sku SKU货品对象, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn number qty 料格可装载的货品数量
function wms_cntr.Get_CntrCell_Goods_Qty( ctd, cntr_good_weight, container_cell, sku )
    local sku_volume, sku_weight, sku_count_method
    local sku_loading_limit      -- SKU 在料格里最多可装载数量
    local cntr_max_weight

    -- 输入参数判断    
    sku_volume = lua.Get_NumAttrValue( sku.F_VOLUME )
    sku_weight = lua.Get_NumAttrValue( sku.F_WEIGHT )
    sku_count_method = lua.Get_StrAttrValue( sku.S_COUNT_METHOD )
    cntr_max_weight = lua.Get_NumAttrValue( ctd.load_capacity )
    sku_loading_limit = lua.Get_NumAttrValue( sku.N_LOADING_LIMIT )

    if ( sku_count_method == '' or sku_count_method == "None" ) then
        return 1, "SKU 编码'"..sku.S_ITEM_CODE.."'的 S_COUNT_METHOD 必须有值且不能为 None!"
    end

    if (container_cell.cell_type == '' or container_cell.cell_type == nil ) then
        return 1, "calculate_quantity 参数中cell_type必须有值!"
    end
    
    local nRet
    local cell_max_volume = 0
    local cell_max_weight = 0
    local cell_goods_qty = lua.Get_NumAttrValue( container_cell.qty )     -- 料格中已经存在的货品数量
    
    for n = 1, #ctd.grid_box_def do
        if ( ctd.grid_box_def[n].cell_type == container_cell.cell_type ) then
            cell_max_volume = lua.Get_NumAttrValue( ctd.grid_box_def[n].volume )
            cell_max_weight  = lua.Get_NumAttrValue( ctd.grid_box_def[n].weight )
            if cell_max_weight <= 0 then
                -- 如果没定义料格载重就用容器总载重除料格数量
                if ctd.grid_box_def[n].box_num > 0 then
                    cell_max_weight = cntr_max_weight/ctd.grid_box_def[n].box_num
                end
            end
            break
        end
    end    

    if ( ctd.check_capacity or sku_count_method == "Weight" or sku_count_method == "Mixed" ) then  
        -- SKU 必须有重量属性
        if (sku_weight <= 0) then
            return 1, "Calculate_Quantity 参数中 SKU 中 F_WEIGHT 必须有值并且是数值类型大于0!"
        end 
        if ( cell_max_weight <= 0 ) then 
          return 1, "料格类型'"..container_cell.cell_type.."'没有定义料格承重!" 
        end
    end
    if ( sku_count_method == "Volume" or sku_count_method == "Mixed" ) then
        -- SKU 必须有体积属性
        if (sku_volume <= 0) then
            return 1, "Calculate_Quantity 参数中 SKU 中 F_VOLUME 必须有值并且是数值类型大于0!"
        end 
        if ( cell_max_volume <= 0 ) then 
            return 1, "料格类型'"..container_cell.cell_type.."'没有定义体积!" 
        end
    end
    if ( sku_count_method == "Limit" ) then
        -- SKU 必须有 N_LOADING_LIMIT/容器装载上限 属性
        if ctd.ecda_rule == "Flex match" then
            if not lua.isTableEmpty( sku.sku_grid_parm ) then
              nRet, sku_loading_limit = wms_base.GetSKU_LoadingLimit( sku, ctd.ctd_code, container_cell.cell_type )
              if nRet ~= 0  then
                  return 1, sku_loading_limit
              end   
            else
                return 1, "SKU 没有定义料格转载货品数量设置!"
            end
        elseif ctd.ecda_rule == "SDM Grid" then
            if (sku_loading_limit <= 0) then
                return 1, "Calculate_Quantity 参数中 SKU 中 N_LOADING_LIMIT 必须有值并且是数值类型大于0!"
            end
        else
            return 1, "容器类型'"..ctd.ctd_code.."'的空料箱呼出规则不符合规范!"
        end
    end    
    
    if ( cell_goods_qty < 0 ) then return 1, "容器'"..container_cell.cntr_code.."' 料格  '"..container_cell.cell_no.."' 的货品数量为负数!" end

    -- V2.0 加 WMS_Volumetric_Ratio/容积率 MDF BY HAN 20250315   
    local v_ratio
    nRet, v_ratio = wms_base.Get_nConst2( "WMS_Volumetric_Ratio" )   
    if nRet ~= 0 then
        v_ratio = 1
    else
        if ( v_ratio == 0 or v_ratio > 1 ) then v_ratio = 1 end
    end
    cell_max_volume = cell_max_volume * v_ratio

    local Qv, Qw, Ql
    if ( sku_count_method == "Mixed" ) then
        -- 根据料箱格剩余体积计算可存储货品数量Qv
        Qv = math.floor(( cell_max_volume - container_cell.good_volume )/sku_volume)  
        if ( Qv < 0 ) then
            return  1, "calculate_quantity 通过体积计算数量失败! cell_max_volume = "..cell_max_volume.." container_cell_good_volume = "..container_cell.good_volume..
                       " 料箱号 = '"..container_cell.cntr_code.."' 料格号 = "..container_cell.cell_no
        end  

        -- 根据料箱剩余重量计算可存储货品数量Qw
        if ( ctd.check_capacity ) then
            Qw = math.floor(( cntr_max_weight - cntr_good_weight )/sku_weight)
            if ( Qw < 0 ) then
                return 1, "calculate_quantity 通过重量计算数量失败! cntr_max_weight = "..cntr_max_weight.." cntr_good_weight = "..cntr_good_weight..
                            " 料箱号 = '"..container_cell.cntr_code.."' 料格号 = "..container_cell.cell_no
            end
        else
            return 0, Qv
        end       
        if ( Qw > Qv ) then return 0, Qv end
        return 0, Qw
    elseif ( sku_count_method == "Weight" ) then
        Qw = math.floor(( cell_max_weight - container_cell.good_weight )/sku_weight)
        if ( Qw < 0 ) then
            return 1, "calculate_quantity 通过重量计算数量失败! cntr_max_weight = "..cntr_max_weight.." cntr_good_weight = "..cntr_good_weight..
                      " 料箱号 = '"..container_cell.cntr_code.."' 料格号 = "..container_cell.cell_no
        end 
        return 0, Qw       
    elseif ( sku_count_method == "Volume" ) then
        Qv = math.floor(( cell_max_volume - container_cell.good_volume )/sku_volume)  
        if ( Qv < 0 ) then
            return 1, "calculate_quantity 通过体积计算数量失败! cell_max_volume = "..cell_max_volume.." container_cell_good_volume = "..container_cell.good_volume..
                      " 料箱号 = '"..container_cell.cntr_code.."' 料格号 = "..container_cell.cell_no
        end 
        return 0, Qv        
    elseif ( sku_count_method == "Limit" ) then
       Ql = sku_loading_limit - cell_goods_qty
       return 0, Ql
    end
    return 1, "计数方法'"..sku_count_method.."'目前没支持"
end


-- 获取容器及容器扩展属性，返回数据字段属性对象
-- @function wms_cntr.Get_Container_ExtInfo
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn table cntr_ext 成功时返回容器+扩展属性对象，不存在时返回空表{}
function wms_cntr.Get_Container_ExtInfo( strLuaDEID, cntr_code )
    local nRet, strRetInfo

    local strTable = "TN_Container a LEFT JOIN TN_Container_Ext b ON a.S_CODE = b.S_CNTR_CODE" 
    local strCondition =  "a.S_CODE = '"..cntr_code.."'"

    -- 组织查询属性
    local attr_set = {}
    local strAttrs = ''
    local UDF_ATTRS_COUNT = #UDF_ATTRS
    local CNTR_BASE_ATTRS_COUNT = #CNTR_BASE_ATTRS
    local CNTR_EXT_BASE_ATTRS_COUNT = #CNTR_EXT_BASE_ATTRS

    for m = 1, CNTR_BASE_ATTRS_COUNT do
        strAttrs = strAttrs.."a."..CNTR_BASE_ATTRS[m]..","
        table.insert( attr_set, CNTR_BASE_ATTRS[m] )
    end
    for m = 1, CNTR_EXT_BASE_ATTRS_COUNT do
        strAttrs = strAttrs.."b."..CNTR_EXT_BASE_ATTRS[m]..","
        table.insert( attr_set, CNTR_EXT_BASE_ATTRS[m] )
    end
    for m = 1, UDF_ATTRS_COUNT do
        strAttrs = strAttrs.."b."..UDF_ATTRS[m]..","
        table.insert( attr_set, UDF_ATTRS[m] )
    end

    nRet, strRetInfo = mobox.queryMultiTable( strLuaDEID, lua.trim_laster_char( strAttrs ), strTable, 1, strCondition, "" )
    if (nRet ~= 0) then 
        return 2,"queryMultiTable 失败!"..strRetInfo
    end
    if ( strRetInfo == '' ) then 
        return 0, {}  
    end
    local ret_attr = json.decode(strRetInfo)
    local cntr_ext = {}
    local n = 1

    -- 获取联表查询属性
    for m = 1, CNTR_BASE_ATTRS_COUNT do
        cntr_ext[CNTR_BASE_ATTRS[m]] = ret_attr[1][n]
        n = n + 1
    end
    for m = 1, CNTR_EXT_BASE_ATTRS_COUNT do
        cntr_ext[CNTR_EXT_BASE_ATTRS[m]] = ret_attr[1][n]
        n = n + 1
    end
    for m = 1, UDF_ATTRS_COUNT do
        cntr_ext[UDF_ATTRS[m]] = ret_attr[1][n]
        n = n + 1
    end  
    cntr_ext.S_CNTR_CODE = cntr_ext.S_CODE
    return 0, cntr_ext
end


-- 容器和货位解绑，并且释放库存量
-- @function wms_cntr.Unbinding
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @tparam string action_src 解绑动作来源（可选）
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string errMsg 失败时返回错误信息
function wms_cntr.Unbinding( strLuaDEID, cntr_code, action_src )
    local nRet, strRetInfo

    if ( cntr_code == nil or cntr_code == '' ) then
        return 1, "wms_cntr.Unbinding 输入参数 cntr_code 必须有值!"
    end
    if ( action_src == nil ) then action_src = '' end

    -- 获取容器是否有绑定货位
    local loc_code
    nRet, loc_code = wms_cntr.Get_Container_Loc( strLuaDEID, cntr_code )
    if nRet ~= 0 then
        return 2, "获取容器位置失败!"..loc_code
    end
    if ( loc_code  == '' ) then return 0 end

    -- 把解绑方式，解绑来源加到全局变量中，在 Loc_Container 删除后事件上会用到
    local global_attrs = {
        { attr = "N_BINDING_METHOD",value = BINDING_METHOD.Manual },
        { attr = "S_ACTION_SRC", value = action_src }
    }
    mobox.setGlobalAttr( strLuaDEID, lua.table2str(global_attrs) )

    local strCondition = "S_LOC_CODE = '"..loc_code.."' AND S_CNTR_CODE = '"..cntr_code.."'"
    -- 删除数据对象【Loc_Container】会触发该数据类的删除后事件，事件会调用函数 wms_ContainerLocAction
    nRet, strRetInfo = mobox.deleteDataObject( strLuaDEID, "Loc_Container", strCondition )
    if ( nRet ~= 0) then
        return nRet, "删除【货位容器绑定】失败!  "..strRetInfo
    end
    nRet, strRetInfo = wms_inv.After_CntrLoc_UnBinding( strLuaDEID, cntr_code, action_src )
    if ( nRet ~= 0) then
        if nRet == 1 then 
            return 1, strRetInfo
        end
        return nRet, "wms_inv.After_CntrLoc_UnBinding 失败!  "..strRetInfo
    end    
    return 0 
end

-- 计算需要多少个料格来装下 qty 个 SKU，从 SKU 最适配料格起逐步计算
-- @function wms_cntr.Get_CellNum_ToLoad_SKU
-- @tparam table ctd 容器类型定义对象, 必须有值
-- @tparam table sku SKU货品对象, 必须有值
-- @tparam number qty 需要装入料箱的数量, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn table cell_num_list 料格数量列表 { {cell_type = 'C', num = 1, priority = 67}, ... }, priority越大优先级越高
function wms_cntr.Get_CellNum_ToLoad_SKU( ctd, sku, qty )
    local sku_volume, sku_weight, sku_count_method

    -- 输入参数判断    
    local cell_type = lua.Get_StrAttrValue( sku.S_CELL_TYPE )       -- 最低适配料格
    if cell_type == '' then
        return 1, "SKU 编码'"..sku.S_ITEM_CODE.."'的 S_CELL_TYPE 必须有值!"
    end
    if qty <= 0 or qty == nil then
        return 1, "Get_CellNum_ToLoad_SKU 函数中的 qty 必须有值!"
    end

    sku_volume = lua.Get_NumAttrValue( sku.F_VOLUME )*qty
    sku_weight = lua.Get_NumAttrValue( sku.F_WEIGHT )*qty
    sku_count_method = lua.Get_StrAttrValue( sku.S_COUNT_METHOD )
 
    if ( sku_count_method == '' or sku_count_method == "None" ) then
        return 1, "SKU 编码'"..sku.S_ITEM_CODE.."'的 S_COUNT_METHOD 必须有值且不能等于 None!"
    end

    local n, nRet, loading_limit, cell_max_volume
    local cell_max_weight = 0

    -- 从最小适配料格开始计算，计算出从小到大的料格需要多少个
    local Q, qX, vX, wX
    local cell_num_list = {}
    while true do
        -- 计算当前 cell_type 的料格数
        Q = 0
        if ( sku_count_method == "Limit" ) then
            nRet, loading_limit = wms_base.GetSKU_LoadingLimit( sku, ctd.ctd_code, cell_type )
            if nRet ~= 0 or loading_limit <= 0 then
                return 1, loading_limit
            end
            Q  = math.floor(qty/loading_limit) 
            qX = qty - Q*loading_limit
            if not lua.equation( qX, 0 ) then 
                Q = Q + 1
            end

        elseif ( sku_count_method == "Volume" or sku_count_method == "Mixed" ) then
            nRet, cell_max_volume, cell_max_weight = wms_cntr.Get_Cell_Volume_Weight( ctd, cell_type )
            if nRet ~= 0 or cell_max_volume <= 0 then
                return 1, cell_max_volume
            end
            Q  = math.floor(sku_volume/cell_max_volume) 
            vX = sku_volume - Q*cell_max_volume
            if not lua.equation( vX, 0 ) then 
                Q = Q + 1
            end
        elseif ( sku_count_method == "Weight"  ) then 
            nRet, cell_max_volume, cell_max_weight = wms_cntr.Get_Cell_Volume_Weight( ctd, cell_type )
            if nRet ~= 0 or cell_max_weight <= 0 then
                return 1, cell_max_weight
            end  
            Q  = math.floor(sku_weight/cell_max_weight) 
            wX = sku_weight - Q*cell_max_weight
            if not lua.equation( wX, 0 ) then 
                Q = Q + 1
            end                      
        end
        if Q > 0 then
            local cell_num = {
                cell_type = cell_type, num = Q, priority = string.byte( cell_type )
            }
            table.insert( cell_num_list, cell_num )
        end

        if cell_type == 'A' then
            break
        end
        if Q == 1 then
            -- 如果当前料箱一个料格就能装置SKU中qty个货品，那么比当前料格体积大的料格肯定1个就够
            -- 不需要进一步计算，后面的料格的可装载货品的数量肯定大于当前的 cell_type 因此Q = 1
            while true do
                cell_type = lua.DecrementChar( cell_type )
                local cell_num = {
                    cell_type = cell_type, num = Q, priority = string.byte( cell_type )
                }
                table.insert( cell_num_list, cell_num )  
                if cell_type == 'A' then
                    break
                end
            end 
            return 0, cell_num_list         
        end
        cell_type = lua.DecrementChar( cell_type )
    end

    return 0, cell_num_list
end

-- 获取容器中的空料格列表
-- @function wms_cntr.Get_Empty_CellList
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn table empty_cell_list 空料格列表 { {cntr_code = "X", cell_no = "A1"}, ... }
function wms_cntr.Get_Empty_CellList( strLuaDEID, cntr_code )
    local nRet
    local strCondition = "S_CNTR_CODE = '"..cntr_code.."' AND N_EMPTY_FULL = 0"
    local strOrder = "S_CELL_NO"
    local cntr_cell_objs

    nRet, cntr_cell_objs = m3.QueryDataObject(strLuaDEID, "Container_Cell", strCondition, strOrder )
    if nRet ~= 0 then 
        return 2, cntr_cell_objs 
    end 
    local empty_cell_list = {}
    local cell_attr
    if ( cntr_cell_objs ~= '') then
        for m = 1, #cntr_cell_objs do
            cell_attr = m3.KeyValueAttrsToObjAttr(cntr_cell_objs[m].attrs)
            local empty_cell = {
                cntr_code = cntr_code,
                cell_no = cell_attr.S_CELL_NO,
            }
            table.insert( empty_cell_list, empty_cell )
        end
    end
    return 0, empty_cell_list
end

-- 获取正在作业的料箱编码列表
-- @function wms_cntr._Get_Bin_Under_Operation
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string wh_code 仓库编码, 必须有值
-- @tparam int op_type 作业类型, 可以为空
-- @tparam string op_def_name 作业定义名称, 可以为
-- @treturn table|nil 料箱编码列表，失败时 nil, ["LX1","LX2",..]
-- @treturn string|nil 错误信息，成功时 nil
function wms_cntr._Get_Bin_Under_Operation( strLuaDEID, wh_code, op_type, op_def_name )
    
    if wh_code == nil or wh_code == '' then
        return nil, "wms_cntr._Get_Bin_Under_Operation 输入参数 wh_code 必须有值!"
    end
    if op_type == nil then op_type = 0 end
    if op_def_name == nil then op_def_name = '' end

    --  作业已经完成或取消的不考虑
    local strCondition
    if type( wh_code ) == "table" then
        local str_wh_codes = table.concat( wh_code, "','" )
        strCondition = "(S_START_WH in ("..str_wh_codes..") or S_END_WH in ("..str_wh_codes..") AND N_B_STATE <> "..OPERATION_STATE.Finish..
                       " AND N_B_STATE <> "..OPERATION_STATE.Cancel
    else 
        strCondition = "(S_START_WH = '"..wh_code.."' or S_END_WH ='"..wh_code.."') AND N_B_STATE <> "..OPERATION_STATE.Finish..
                       " AND N_B_STATE <> "..OPERATION_STATE.Cancel
    end
    
    if op_type ~= 0 then
        strCondition = strCondition.." AND N_TYPE = "..op_type
    end
    if op_def_name ~= '' then
        strCondition = strCondition.." AND S_OP_DEF_NAME = '"..op_def_name.."'"
    end
    
    local bin_list = {}
    local nRet, strRetInfo

    nRet, strRetInfo = mobox.queryDataObjAttr2( strLuaDEID, "Operation", strCondition, "S_CODE", 200 )
    if nRet ~= 0  then 
        return nil, "queryDataObjAttr2: "..strRetInfo
    end  
    if strRetInfo == '' then 
        return bin_list 
    end

    local success
    local queryInfo
    success, queryInfo = pcall( json.decode, strRetInfo )
    if not success then 
        return nil, "queryDataObjAttr2 返回结果是非法的JSON格式!"
    end

    local nPageCount = queryInfo.pageCount
    local nPage = 1
    local dataSet = queryInfo.dataSet       -- 查询出来的数据集
    local op_data
    while (nPage <= nPageCount) do
        for n = 1, #dataSet do
            op_data = m3.KeyValueAttrsToObjAttr(dataSet[n].attrs)
            if op_data == nil then
                return nil, "KeyValueAttrsToObjAttr转换失败!"
            end
            table.insert( bin_list, op_data.S_CNTR_CODE )
        end        

        nPage = nPage + 1
        if ( nPage <= nPageCount ) then
            -- 取下一页
            nRet, strRetInfo = mobox.queryDataObjAttr2( strLuaDEID, nPage)
            if nRet ~= 0 then
                return nil, "queryDataObjAttr2失败! nPage="..nPage.."  "..strRetInfo
            end 
            queryInfo = json.decode(strRetInfo) 
            dataSet = queryInfo.dataSet              
        end
    end    
    return bin_list
end

--*****

-- 获取容器中的料格数据对象信息
-- @function wms_cntr.Get_Container_Cell_Data
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @tparam string cell_no 料格编码, 必须有值
-- @treturn number nRet 0表示成功，1表示不存在，2表示失败
-- @treturn table|string cntr_cell 成功时返回容器料格对象，不存在时返回空字符串，失败时返回错误信息
function wms_cntr.Get_Container_Cell_Data( strLuaDEID, cntr_code, cell_no )
    if ( cntr_code == nil or cntr_code == '' ) then
        return 2, "wms_cntr.Get_Container_Cell_Data 容器编号不能为空!"
    end
    if ( cell_no == nil or cell_no == '' ) then
        return 2, "wms_cntr.Get_Container_Cell_Data 料格编号不能为空!"
    end

    local nRet, strRetInfo, id
    local strCondition = "S_CNTR_CODE = '"..cntr_code.."' AND S_CELL_NO = '"..cell_no.."'"
    nRet, id, strRetInfo = mobox.getDataObjAttrByKeyAttr( strLuaDEID, "Container_Cell", strCondition )
    -- 返回1表示不存在
    if nRet == 1  then 
        return 1, "容器'"..cntr_code.."'中的料格'"..cell_no.."'不存在!" 
    end
    if nRet ~= 0 then
        return 2, "getDataObjAttrByKeyAttr 失败!"..id
    end

    local strJson
    nRet, strJson = mobox.objAttrToObjJson( "Container_Cell", strRetInfo )
    if nRet ~= 0 then
        return 2, "objAttrToObjJson 失败!"..strRetInfo
    end

    local object, success
    success, object = pcall( json.decode, strJson )
    if success == false then
        return 2,"objAttrToObjJson('Container') 返回的的JSON格式不合法!" 
    end
    object.id = id
    return 0, object
end

-- 创建容器类型为Cell_Box的料格对象
-- @function wms_cntr.Create_Cell_Box
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string ctd_code 容器类型定义编码, 必须有值
-- @tparam string cntr_code 容器编码, 必须有值
-- @tparam string cntr_spec 料格类型, 必须有值
-- @treturn number nRet 0表示成功，1表示不存在，2表示失败
-- @treturn string errMsg 成功时返回nil，失败返回错误信息
function wms_cntr.Create_Cell_Box( strLuaDEID, ctd_code, cntr_code, cntr_spec )
    local cntr_cell, nRet, cell_symbol
    local num = 0   -- 根据不同类型的料箱类型生成料格对象
    local ctd       -- 容器类型定义
    local cell_def = {}

    nRet, ctd = wms_cntr.GetCTDInfo( ctd_code, strLuaDEID )
    if nRet ~= 0 then
        return 1, '获取容器类型定义失败!'..ctd
    end  

    if lua.IsTableEmpty( ctd.grid_box_def ) then
        if cntr_spec == 'A' then
            num = 1
        elseif cntr_spec == 'B' then
            num = 2
        elseif cntr_spec == 'C' then
            num = 3
        elseif cntr_spec == 'D' then
            num = 4
        elseif cntr_spec == 'E' then
            num = 6
        elseif cntr_spec == 'F' then
            num = 8 
        elseif cntr_spec == 'G' then
            num = 10       
        else
            return  1, "料格类型'"..cntr_spec.."'不合法!" 
        end
    else
        nRet, cell_def = wms_cntr.Get_CTD_GridDef( ctd, cntr_spec )
        if nRet ~= 0 or lua.IsTableEmpty(cell_def) then
            return 1, "容器类型定义中没有定义规格 = "..cntr_spec.." 的料格定义!"
        end   
        num = cell_def.box_num or 0
        if num == 0 then
            return  1,"容器类型定义中规格 = "..cntr_spec.." 的料格定义无效缺少 box_num!"
        end
    end
        
    for n = 1, num do
        cell_symbol= lua.strFill( tostring(n), 2, "0" )
        cntr_cell = m3.AllocObject(strLuaDEID,"Container_Cell")
        cntr_cell.cntr_code = cntr_code
        cntr_cell.cell_no = cntr_spec.."-"..cell_symbol 
        cntr_cell.cell_code = cntr_code.."-"..cell_symbol 

        -- 如果没有定义 Grid Def 参数就用巨星项目默认的料格尺寸
        if lua.IsTableEmpty( cell_def ) then
            if cntr_spec == 'A' then
                cntr_cell.long = 60
                cntr_cell.middle = 40
                cntr_cell.short = 30
            elseif cntr_spec == 'B' then
                cntr_cell.long = 40
                cntr_cell.middle = 30
                cntr_cell.short = 30            
            elseif cntr_spec == 'C' then
                cntr_cell.long = 40
                cntr_cell.middle = 30
                cntr_cell.short = 20            
            elseif cntr_spec == 'D' then
                cntr_cell.long = 30
                cntr_cell.middle = 30
                cntr_cell.short = 20            
            elseif cntr_spec == 'E' then 
                cntr_cell.long = 30
                cntr_cell.middle = 20
                cntr_cell.short = 20
            elseif cntr_spec == 'F' then 
                cntr_cell.long = 20
                cntr_cell.middle = 20
                cntr_cell.short = 20    
            elseif cntr_spec == 'G' then 
                cntr_cell.long = 20
                cntr_cell.middle = 20
                cntr_cell.short = 10
            end  
            cntr_cell.volume = cntr_cell.long*cntr_cell.middle*cntr_cell.short            
        else
            cntr_cell.long = cell_def.long or 0
            cntr_cell.middle = cell_def.middle or 0
            cntr_cell.short = cell_def.short or 0
            cntr_cell.volume = cell_def.volume or 0
        end

        cntr_cell.cell_type = cntr_spec
        nRet, cntr_cell = m3.CreateDataObj(strLuaDEID, cntr_cell)
        if nRet ~= 0 then 
            return 1, "创建【容器箱格】失败!"..cntr_cell
        end                                 
    end
    return 0
end

-- 根据移动料架中的定义，创建容器料格
-- @function wms_cntr.Create_Mobile_Rack
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string ctd_code 容器类型定义编码,必须有值
-- @tparam string cntr_code 容器编码，必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string|nil err_msg 失败时返回错误信息，成功时返回nil
function wms_cntr.Create_Mobile_Rack( strLuaDEID, ctd_code, cntr_code )
    local cntr_cell, nRet
    local ctd                           -- 容器类型定义

    nRet, ctd = wms_cntr.GetCTDInfo( ctd_code, strLuaDEID )
    if nRet ~= 0 then
        return 1, '获取容器类型定义失败!'..ctd
    end   
    if lua.IsTableEmpty( ctd.mobile_rack_def ) then
        return  1, "容器类型定义'"..ctd_code.."'没有定义移动料架定义!"
    end

    local layer = ctd.mobile_rack_def.layer or 0
    local cell_per_layer = ctd.mobile_rack_def.cell_per_layer or 0
    local layer_symbol, col_symnbol    
        
    for n = 1, layer do
        layer_symbol= lua.strFill( tostring(n), 2, "0" )
        for m = 1, cell_per_layer do
            col_symnbol= lua.strFill( tostring(m), 2, "0" )
            cntr_cell = m3.AllocObject2(strLuaDEID,"Container_Cell")
            cntr_cell.S_CNTR_CODE = cntr_code
            cntr_cell.S_CELL_NO = layer_symbol.."-"..col_symnbol 
            cntr_cell.S_CELL_CODE = cntr_code.."-"..layer_symbol.."-"..col_symnbol 
            nRet, cntr_cell = m3.CreateDataObj2( strLuaDEID, cntr_cell )
            if nRet ~= 0 then 
                return 1, "在Create_Mobile_Rack函数中创建【容器箱格】失败!"..cntr_cell
            end     
        end
    end
    return 0    
end

local function can_nest_child_container( strLuaDEID, p_cntr_data, s_cntr_data ) 
    local nRet, ctd

    -- 获取父容器类型定义
    nRet, ctd = wms_cntr.GetCTDInfo( p_cntr_data.S_CTD_CODE, strLuaDEID )
    if nRet ~= 0 then
        return 1, '获取容器类型定义失败!'..ctd
    end   
    -- 判断父容器是否支持嵌套
    local can_nest = ctd.data.C_IS_NESTABLE or 'N'
    if can_nest ~= 'Y' then
        return 0, false
    end

    -- 判断子容器是否可以加入父容器
    -- 获取父容器能最多加几个子容器 max_s_cntr_qty
    local max_s_cntr_qty = 0
    if not lua.IsTableEmpty( ctd.nest_rule  ) then
        local find = false   
        
        for _, rule in pairs( ctd.nest_rule ) do
            if rule.ctd_code == s_cntr_data.S_CTD_CODE then
                find = true
                max_s_cntr_qty = rule.max_qty
                break
            end
        end
        if not find then
            return 0, false
        end
    end
    -- 如果有外部检查是否可以嵌套的函数，执行外部函数
    local can_nest_cntr_qty = 0
    if not lua.IsTableEmpty( ctd.nest_check_func ) then
        local parameter = {
            p_cntr_data = p_cntr_data,
            s_cntr_data = s_cntr_data,
            max_s_cntr_qty = max_s_cntr_qty,
        }
        nRet, can_nest, can_nest_cntr_qty = lua.callFunctionByName( ctd.nest_check_func.module_name, ctd.nest_check_func.function_name, parameter )
        if nRet ~= 0 then
            return 1, can_nest, can_nest_cntr_qty
        end
        return 0, can_nest
    end

    -- 如果有最大嵌套数量限制，则判断是否超过限制
    if max_s_cntr_qty > 0 then
        local strCondition = "S_P_CNTR_CODE = '"..p_cntr_data.S_CODE.."'"        
        local data_objs
        nRet, data_objs = m3.QueryDataObject(strLuaDEID, "Container_Cell_Tote_Link", strCondition, "S_P_CELL_NO" )
        if nRet ~= 0 then 
            return 2, "QueryDataObject失败!"..data_objs 
        end
        local sub_cntr_count = 0        
        if not lua.IsTableEmpty( data_objs ) then
            -- 绑定的容器定义是否一样
            local link_tote = m3.KeyValueAttrsToObjAttr(data_objs[1].attrs)
            if link_tote == nil then
                return 1, "KeyValueAttrsToObjAttr失败!"
            end
            -- 目前是不支持嵌套不同容器类型的容器
            if link_tote.S_S_CTD_CODE ~= s_cntr_data.S_CTD_CODE then
                return 0, false
            end
            sub_cntr_count = #data_objs
        end
        if sub_cntr_count >= max_s_cntr_qty then
            return 0, false
        end
        can_nest_cntr_qty = max_s_cntr_qty - sub_cntr_count
        return 0, true, can_nest_cntr_qty
    end

    return 0, true, can_nest_cntr_qty   
end

-- 判断容器是否可以嵌套子容器
-- @function wms_cntr.CanNestChildContainer
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string p_cntr_code 父容器编码，必须有值
-- @tparam string s_cntr_code 子容器编码，必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn boolean|nil can_nest 是否可以嵌套子容器，成功时返回true，失败时返回err_msg
function wms_cntr.CanNestChildContainer( strLuaDEID, p_cntr_code, s_cntr_code )
    local nRet
    local p_cntr_data, s_cntr_data

    -- 获取容器数据对象信息
    nRet, p_cntr_data = wms_cntr.GetInfo2( strLuaDEID, p_cntr_code )
    if nRet ~= 0 then
        return 1, "获取父容器信息失败!"..p_cntr_data
    end
    nRet, s_cntr_data = wms_cntr.GetInfo2( strLuaDEID, s_cntr_code )
    if nRet ~= 0 then
        return 1, "获取子容器信息失败!"..s_cntr_data
    end
    local can_nest
    nRet, can_nest = can_nest_child_container( strLuaDEID, p_cntr_data, s_cntr_data )
    if nRet ~= 0 then
        return 1, "判断容器是否可以嵌套子容器失败!"..can_nest
    end
    return 0, can_nest
end

-- 根据容器号获取系统最新创建的组盘对象
-- @function get_current_inbp
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cntr_code 容器编码
-- @treturn number nRet 0: 成功, 1: 参数错误, 2: 查询出错
-- @treturn table|nil inb_pallet 组盘对象，nil表示不存在
local function get_current_inbp( strLuaDEID, cntr_code )
    local nRet
    local inb_pallet
    if cntr_code == nil or cntr_code == '' then 
        return 1, "Get_Current_INBP 函数中输入参数 cntr_code 必须有值!"
    end
    local strCondition = "S_CNTR_CODE = '"..cntr_code.."'"
    local strOrder = "T_CREATE Desc"

    nRet, inb_pallet = m3.GetDataObjByCondition( strLuaDEID, "Inbound_Palletization", strCondition, strOrder )
    if nRet > 1 then
        return 2, "查询【Inbound_Palletization】出错!"..inb_pallet
    end
    if nRet == 1 then
        -- 组盘对象不存在
        inb_pallet = nil
    else
        -- 如果该容器的【组盘】对象已经存在，如果状态是完成或取消
        if inb_pallet.b_state >= PALLET_STATE.Finish then
            inb_pallet = nil
        end
    end
    return 0, inb_pallet
end
                  
-- 把子容器加入父容器
-- @function wms_cntr.AttachChildToParent
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table parameter 参数表，必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string|nil err_msg 失败时返回err_msg
--[[ 
    parameter = { 
            p_cntr_code,    -- 父容器编码，必须有值
            p_cntr_cell_no, -- 父容器格编码，可以为空
            s_cntr_code,    -- 子容器编码，必须有值
    }
--]]

function wms_cntr.AttachChildToParent( strLuaDEID, parameter )
    local nRet, strRetInfo
    local p_cntr_data, s_cntr_data

    if lua.IsTableEmpty( parameter ) then
        return 1, "wms_cntr.AddChildToParent 函数中 parameter 必须有值!"
    end
    local p_cntr_code = parameter.p_cntr_code or ''
    local p_cntr_cell_no = parameter.p_cntr_cell_no or ''
    local s_cntr_code = parameter.s_cntr_code or ''

    if p_cntr_code == '' then
        return 1, "wms_cntr.AddChildToParent 函数中 parameter.p_cntr_code 必须有值!"
    end
    if s_cntr_code == '' then
        return 1, "wms_cntr.AddChildToParent 函数中 parameter.s_cntr_code 必须有值!"
    end

    -- 获取容器数据对象信息
    nRet, p_cntr_data = wms_cntr.GetInfo2( strLuaDEID, p_cntr_code )
    if nRet ~= 0 then
        return 1, "获取父容器信息失败!"..p_cntr_data
    end
    nRet, s_cntr_data = wms_cntr.GetInfo2( strLuaDEID, s_cntr_code )
    if nRet ~= 0 then
        return 1, "获取子容器信息失败!"..s_cntr_data
    end
    -- 子容器已经绑定父容器，则不允许再绑定
    if s_cntr_data.S_P_CNTR_CODE ~= '' then
        return 1, "子容器已经绑定父容器，不允许再绑定!"
    end
    -- 子容器是否可以加入当前的父容器
    local can_nest, can_nest_cntr_qty
    nRet, can_nest, can_nest_cntr_qty = can_nest_child_container( strLuaDEID, p_cntr_data, s_cntr_data )
    if nRet ~= 0 then
        return 1, "判断容器是否可以嵌套子容器失败!"..can_nest
    end  
    if not can_nest then
        return 1, "容器不支持嵌套子容器!"
    end 

    -- 设置子容器的父容器信息
    local strUpdateSql = "S_P_CNTR_CODE = '"..p_cntr_code.."'"
    local strCondition = "S_CODE = '" .. s_cntr_code .. "'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Container", strCondition, strUpdateSql)
    if nRet ~= 0 then
        return 2, "更新【Container】信息失败!" .. strRetInfo
    end
    -- 设置父容器信息
    local nest_fill_status = 1 -- 嵌套填充状态 1 有子容器
    if can_nest_cntr_qty == 1 then
        nest_fill_status = 2 -- 嵌套填充状态 2 子容器已满
    end
    strUpdateSql = "N_NEST_FILL_STATUS = "..nest_fill_status
    strCondition = "S_CODE = '" .. p_cntr_code .. "'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Container", strCondition, strUpdateSql)
    if nRet ~= 0 then
        return 2, "更新【Container】信息失败!" .. strRetInfo
    end   

    -- 设置 Container_Cell_Tote_Link 信息
    local tote_link = m3.AllocObject2(strLuaDEID, "Container_Cell_Tote_Link")
    tote_link.S_P_CNTR_CODE = p_cntr_code
    tote_link.S_P_CELL_NO = p_cntr_cell_no    
    tote_link.S_S_CNTR_CODE = s_cntr_code
    tote_link.S_S_CTD_CODE = s_cntr_data.S_CTD_CODE
    nRet, tote_link = m3.CreateDataObj2(strLuaDEID, tote_link)
    if nRet ~= 0 then
        return 1, "创建【Container_Cell_Tote_Link】失败!" .. tote_link
    end   
    
    -- 库存量相关信息变化
    -- 获取容器的库位信息
    local from_loc_code, to_loc_code
    nRet, from_loc_code = wms_cntr.Get_Container_Loc( strLuaDEID, s_cntr_code )
    if nRet ~= 0 then
        return 1, "获取容器的库位信息失败!" .. from_loc_code   
    end
    nRet, to_loc_code = wms_cntr.Get_Container_Loc( strLuaDEID, p_cntr_code )
    if nRet ~= 0 then
        return 1, "获取容器的库位信息失败!" .. to_loc_code   
    end    
    if from_loc_code == '' then 
        -- 子容器没有库位信息，说明容器处于组盘状态，或纯空料箱
        local inb_pallet
        nRet, inb_pallet = get_current_inbp( strLuaDEID, s_cntr_code )
        if inb_pallet ~= nil then
            -- 子容器在组盘中
            if to_loc_code == '' then
                -- 父容器也没有库位
                return 0
            else
                -- 父容器有库位，需要把子容器中的组盘明细信息变成库存量
                -- 只有码盘完成的料箱材料进行库存量转移
                if inb_pallet.b_state == PALLET_STATE.PalletOK then
                    nRet, strRetInfo = wms_inv.After_CntrLoc_Binding( strLuaDEID, inb_pallet, to_loc_code )
                    if nRet ~= 0 then
                        return 1, "wms_inv.After_CntrLoc_Binding 失败!" .. strRetInfo
                    end
                    -- 设置【码盘】状态为 待入库
                    local strUpdateSql = "N_B_STATE = "..PALLET_STATE.Inbound_Pending
                    local strCondition = "S_IBP_NO = '"..inb_pallet.ibp_no.."'"
                    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Inbound_Palletization", strCondition, strUpdateSql )
                    if nRet ~= 0 then
                        return 1, 'updateDataAttrByCondition 失败!'..strRetInfo
                    end   
                end
                return 0
            end
        end
    else
        -- 子容器有库位信息，说明容器有库存需要考虑库存迁移
        if to_loc_code == '' then
            return 1, "父容器没有库位信息，不支持库存迁移!"
        end
        local ext_parameter = { p_cntr_code = p_cntr_code }
        nRet, strRetInfo = wms_inv.Move(strLuaDEID, s_cntr_code, from_loc_code, to_loc_code, ext_parameter )
        if nRet ~= 0 then
            return 1, "wms_inv.Move 失败!" .. strRetInfo
        end
    end
    return 0
end

-- 解除子容器和父容器的嵌套关系
-- @function wms_cntr.DetachChildFromParent
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table parameter 参数表，必须有值
-- @treturn number nRet 0表示成功，非0表示失败
-- @treturn string|nil err_msg 失败时返回err_msg
--[[ 
    parameter = { 
            s_cntr_code,    -- 子容器编码，必须有值
            to_loc_code     -- 子容器移除后要放置的库位编码，必须有值
    }
--]]
function wms_cntr.DetachChildFromParent( strLuaDEID, parameter )
    local nRet, strRetInfo
    local s_cntr_data

    if lua.IsTableEmpty( parameter ) then
        return 1, "wms_cntr.AddChildToParent 函数中 parameter 必须有值!"
    end
    local p_cntr_code = ''
    local to_loc_code = parameter.to_loc_code or ''
    local s_cntr_code = parameter.s_cntr_code or ''

    if s_cntr_code == '' then
        return 1, "wms_cntr.DetachChildFromParent 函数中 parameter.s_cntr_code 必须有值!"
    end

    if to_loc_code == '' then
        return 1, "wms_cntr.DetachChildFromParent 函数中 parameter.to_loc_code 必须有值!"
    end

    -- 获取子容器数据对象信息
     nRet, s_cntr_data = wms_cntr.GetInfo2( strLuaDEID, s_cntr_code )
    if nRet ~= 0 then
        return 1, "获取子容器信息失败!"..s_cntr_data
    end
    p_cntr_code = s_cntr_data.S_P_CNTR_CODE
    if p_cntr_code == '' then
        return 1, "解除嵌套关系的子容器没有父容器!"
    end    

    -- 设置子容器的父容器信息
    local strUpdateSql = "S_P_CNTR_CODE = ''"
    local strCondition = "S_CODE = '" .. s_cntr_code .. "'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Container", strCondition, strUpdateSql)
    if nRet ~= 0 then
        return 2, "更新【Container】信息失败!" .. strRetInfo
    end

    -- 解除嵌套关系
    strCondition = "S_P_CNTR_CODE = '" .. p_cntr_code .. "' AND S_S_CNTR_CODE = '" .. s_cntr_code .. "'"
    nRet, strRetInfo = mobox.dbdeleteData(strLuaDEID, "Container_Cell_Tote_Link", strCondition)
    if nRet ~= 0 then 
        return 1, "删除【Container_Cell_Tote_Link】失败!"..strRetInfo
    end

    -- 设置父容器的 N_NEST_FILL_STATUS 状态
    local count
    strCondition = "S_P_CNTR_CODE = '" .. p_cntr_code .. "'"
    nRet, count = m3.GetDataObjCount( strLuaDEID, "Container_Cell_Tote_Link", strCondition )
    if nRet ~= 0 then 
        return 1, "m3.GetDataObjCount 失败!"..count
    end
    local nest_fill_status = 1 -- 嵌套填充状态 1 有子容器
    local empty_full = 1
    if count == 0 then
        nest_fill_status = 0 
    end
    strCondition = "S_P_CNTR_CODE = '" .. p_cntr_code .. "'"
    nRet, count = m3.GetDataObjCount( strLuaDEID, "INV_Detail", strCondition )
    if nRet ~= 0 then 
        return 1, "m3.GetDataObjCount 失败!"..count
    end
    if count == 0 then
        empty_full = 0 
    end 
    strUpdateSql = "N_NEST_FILL_STATUS = "..nest_fill_status..", N_EMPTY_FULL = "..empty_full
    strCondition = "S_CODE = '" .. p_cntr_code .. "'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition(strLuaDEID, "Container", strCondition, strUpdateSql)
    if nRet ~= 0 then
        return 2, "更新【Container】信息失败!" .. strRetInfo
    end 
    
    -- 获取子容器所在父容器的库位信息
    -- 获取容器的库位信息
    local from_loc_code
    nRet, from_loc_code = wms_cntr.Get_Container_Loc( strLuaDEID, p_cntr_code )
    if nRet ~= 0 then
        return 1, "获取容器的库位信息失败!" .. from_loc_code   
    end
    
    -- 库存量数据转移
    if from_loc_code ~= '' then
        local  ext_parameter = { p_cntr_code = '' }
        nRet, strRetInfo = wms_inv.Move( strLuaDEID, s_cntr_code, from_loc_code, to_loc_code, ext_parameter )
        if nRet ~= 0 then
            return 1, "wms_inv.Move 失败!" .. strRetInfo
        end 
    end
    return 0
end

return wms_cntr