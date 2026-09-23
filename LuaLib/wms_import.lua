--[[
    版本：     Version 1.0
    创建日期： 2026-8-10
    创建人：   HAN

    WMS-Basis-Model-Version: V20.1

    功能：
        WMS 中一些业务数据的导入处理函数，可以用于测试、实施过程中的业务数据导入

    ——————————————————————————————————
    导入函数列表（共 6 个）:
    ——————————————————————————————————

    【单据导入】
        Inbound_Order         — 导入入库单（含明细、SKU），同一入库单号的多行明细自动合并到一张入库单
        Outbound_Order        — 导入出库单（含明细），同一出库单号的多行明细自动合并到一张出库单
        Inbound_Palletization — 导入组盘单（含明细、SKU），同一组盘单号的多行明细自动合并到一张组盘单

    【主数据导入】
        Container             — 导入容器，支持单条与批量创建（CreateQty+CodeHead，容器编码由序列号自动生成）
        Area                  — 导入库区数据对象，行中含 CreateLocation(JSON) 时按 type 创建立体库/平面库/地堆库位
        Data                  — 通用导入任意数据类对象，按数据类属性过滤，缺省工厂/仓库/货主时兜底
        Import_Data           -- 导入数据的管理程序
        INV_Detail            -- 导入库存明细
    ——————————————————————————————————
--]]

require ("wms_const")
wms_wh = require("wms_wh")

local wms_import = {_version = "0.3.0"}

-- 创建立体库（高架库）库位
-- @function create_high_bay_wh_loc
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table area_data 库区数据对象（须含 S_CODE、S_WH_CODE、N_TYPE、N_LOC_TYPE）
-- @tparam table parameter 库位生成参数，见下方说明
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
--[[ 
    parameter 输入参数说明:
    {
        asile = { -- 巷道列表，必须有值
            { asile_code = "A01", left_row = 2, right_row = 2, col = 20, layer = 10,
              loc_capacity = 1,length = 1.2, width = 1.0, height = 1.5, max_weight = 1000 },
            ...
        }
    }
    "loc_capacity" -- 库位容量，默认 1
    说明：
      每个巷道按左右两侧分别生成库位，同时创建 Aisle 巷道对象；
      库位编码规则：S_CODE = 库区编码-排-列-层
]]
local function create_high_bay_wh_loc( strLuaDEID, area_data, parameter )
    local nRet
    if parameter == nil then
        return 1, "CreateLocation 字段解析失败! 原因: 参数为空!"
    end
    if parameter.asile == nil then
        return 1, "创建立库库位必须有 asile 信息!"
    end
    local row_no = 1
    local asile_no = 1
    local deep = 0    
    local area_code = area_data.S_CODE or ''
    local wh_code = area_data.S_WH_CODE or ''
    local purpose = area_data.N_TYPE or 1
    local loc_type = area_data.N_LOC_TYPE or 1

    if area_code == '' then
        return 1, "创建立库库位必须有 area_code 信息!"
    end
    if wh_code == '' then
        return 1, "创建立库库位必须有 wh_code 信息!"
    end

    for _, asile in ipairs(parameter.asile) do
        local asile_code = asile.asile_code
        if asile_code == nil or asile_code == '' then
            return 1, "创建立库库位必须有 asile_code 信息!"
        end
        local left_row  = asile.left_row or 0
        if left_row <= 0 then
            return 1, "创建立库库位必须有 left_row 信息!"
        end
        local right_row = asile.right_row or 0
        if right_row <= 0 then
            return 1, "创建立库库位必须有 right_row 信息!"
        end
        local max_col = asile.col or 0
        if max_col <= 0 then
            return 1, "创建立库库位必须有 col 信息!"
        end
        local max_layer = asile.layer or 0
        if max_layer <= 0 then
            return 1, "创建立库库位必须有 layer 信息!"
        end
        local length = asile.length or 0
        local width = asile.width or 0
        local height = asile.height or 0
        local max_weight = asile.max_weight or 0
        local loc_capacity = asile.loc_capacity or 1
        local str_left_rows, str_right_rows = '', ''

        -- 创建巷道
        local asile_data = m3.AllocObject2( strLuaDEID, "Aisle" )
        
        asile_data.N_AISLE = asile_no
        asile_data.S_AISLE_CODE = asile_code
        asile_data.S_AREA_CODE = area_code
        asile_data.S_WH_CODE = wh_code

        asile_data.N_LEFT_DEEP = left_row
        asile_data.N_RIGHT_DEEP = right_row
        asile_data.N_MAX_COL = max_col
        asile_data.N_MAX_LAYER = max_layer

        for n = 1, left_row do
            str_left_rows = str_left_rows .. row_no .. ','
            deep = left_row - n + 1

            for col = 1, max_col do
                for layer = 1, max_layer do
                    local loc_data = m3.AllocObject2( strLuaDEID, "Location" )
                    loc_data.S_CODE = area_code.."-"..row_no.."-"..col.."-"..layer
                    loc_data.S_WH_CODE = wh_code
                    loc_data.S_AREA_CODE = area_code
                    loc_data.N_AISLE = asile_no
                    loc_data.S_AISLE_CODE = asile_code
                    loc_data.N_ROW = row_no
                    loc_data.N_COL = col
                    loc_data.N_LAYER = layer
                    loc_data.N_DEEP = deep
                    loc_data.N_MAX_WEIGHT = max_weight
                    loc_data.N_LENGTH = length
                    loc_data.N_WIDTH = width
                    loc_data.N_HEIGHT = height
                    loc_data.N_PURPOSE = purpose
                    loc_data.N_TYPE = loc_type
                    loc_data.N_CAPACITY = loc_capacity
                    nRet, loc_data = m3.CreateDataObj2( strLuaDEID, loc_data )
                    if nRet ~= 0 then 
                        return 1, "创建 Location 失败!"..loc_data
                    end                    
                end
            end

            row_no = row_no + 1
        end

        for n = 1, right_row do
            str_right_rows = str_right_rows .. row_no .. ','
            deep = n

            for col = 1, max_col do
                for layer = 1, max_layer do
                    local loc_data = m3.AllocObject2( strLuaDEID, "Location" )
                    loc_data.S_CODE = area_code.."-"..row_no.."-"..col.."-"..layer
                    loc_data.S_WH_CODE = wh_code
                    loc_data.S_AREA_CODE = area_code
                    loc_data.N_AISLE = asile_no
                    loc_data.S_AISLE_CODE = asile_code
                    loc_data.N_ROW = row_no
                    loc_data.N_COL = col
                    loc_data.N_LAYER = layer
                    loc_data.N_DEEP = deep
                    loc_data.N_MAX_WEIGHT = max_weight
                    loc_data.N_LENGTH = length
                    loc_data.N_WIDTH = width
                    loc_data.N_HEIGHT = height
                    loc_data.N_PURPOSE = purpose
                    loc_data.N_TYPE = loc_type
                    loc_data.N_CAPACITY = loc_capacity                    
                    nRet, loc_data = m3.CreateDataObj2( strLuaDEID, loc_data )
                    if nRet ~= 0 then 
                        return 1, "创建 Location 失败!"..loc_data
                    end                    
                end
            end
            row_no = row_no + 1
        end

        asile_data.S_LEFT_ROWS = str_left_rows
        asile_data.S_RIGHT_ROWS = str_right_rows
        nRet, asile_data = m3.CreateDataObj2( strLuaDEID, asile_data )
        if nRet ~= 0 then 
            return 1, "创建 Aisle 失败!"..asile_data
        end
    end

    return 0
end

-- 创建平面库、地堆库库位
-- @function create_low_bay_wh_loc
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table area_data 库区数据对象（须含 S_CODE、S_WH_CODE、N_TYPE、N_LOC_TYPE）
-- @tparam table parameter 库位生成参数，见下方说明
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
--[[ 
    parameter 输入参数说明:
    {
        row = 10,         -- 排数，必须有值
        col = 20,         -- 列数，必须有值
        length = 1.2,     -- 长
        width = 1.0,      -- 宽
        height = 1.5,     -- 高
        loc_capacity = 1, -- 库位容量，默认 1
        max_weight = 1000 -- 最大承重
    }
    说明：
      库位编码规则：S_CODE = 库区编码-排-列，层数和深度固定为 1
]]
local function create_low_bay_wh_loc( strLuaDEID, area_data, parameter )
    local nRet
    if parameter == nil then
        return 1, "CreateLocation 字段解析失败! 原因: 参数为空!"
    end

    local area_code = area_data.S_CODE or ''
    local wh_code = area_data.S_WH_CODE or ''
    local purpose = area_data.N_TYPE
    local loc_type = area_data.N_LOC_TYPE or 1

    if area_code == '' then
        return 1, "创建平面库库位必须有 area_code 信息!"
    end
    if wh_code == '' then
        return 1, "创建平面库库位必须有 wh_code 信息!"
    end

    local max_row = parameter.row or 0
    if max_row <= 0 then
        return 1, "创建平面库库位必须有 row 信息!"
    end
    local max_col = parameter.col or 0
    if max_col <= 0 then
        return 1, "创建平面库库位必须有 col 信息!"
    end

    local length = parameter.length or 0
    local width = parameter.width or 0
    local height = parameter.height or 0
    local loc_capacity = parameter.loc_capacity or 1
    local max_weight = parameter.max_weight or 0

    for row = 1, max_row do
        for col = 1, max_col do
            local loc_data = m3.AllocObject2( strLuaDEID, "Location" )

            loc_data.S_CODE = area_code.."-"..row.."-"..col
            loc_data.S_WH_CODE = wh_code
            loc_data.S_AREA_CODE = area_code
            loc_data.N_ROW = row
            loc_data.N_COL = col
            loc_data.N_LAYER = 1
            loc_data.N_DEEP = 1
            loc_data.N_MAX_WEIGHT = max_weight
            loc_data.N_LENGTH = length
            loc_data.N_WIDTH = width
            loc_data.N_HEIGHT = height
            loc_data.N_PURPOSE = purpose
            loc_data.N_TYPE = loc_type
            loc_data.N_CAPACITY = loc_capacity  
            nRet, loc_data = m3.CreateDataObj2( strLuaDEID, loc_data )
            if nRet ~= 0 then 
                return 1, "创建 Location 失败!"..loc_data
            end                    
        end
    end
    return 0
end


-- 导入一行库存量明细
-- 如果 SKU 不存在会创建SKU, 会和容器会和库位进行绑定
-- @function import_inv_detail
-- @tparam table parameter 输入参数 
-- @tparam table row 导入的入库单明细行数据 { S_IO_NO = "", N_ROW_NO = "1", ... }
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
--[[ 
    parameter 输入参数说明:
    { 
        factory_no, -- 必须有值不能为空
        wh_code, 
        storer_no, -- 必须有值不能为空
        cntr_list = {{cntr_code = "", loc_code = ""},...} -- 库位和容器关系
        inv_detail_attrs = {}, -- 库存量数据类中的属性
        sku_attrs = {} -- sku 数据类中的属性
        create_sku_if_not_exist = true -- 如果 sku 不存在是否创建
    }    
]]
local function import_inv_detail( strLuaDEID, parameter, row )
    local inv_detail_data = m3.AllocObject2( strLuaDEID, "INV_Detail" )
    local sku_data = m3.AllocObject2( strLuaDEID, "SKU" )

    local find, strCondition
    local nRet, sku_exist
    local create_sku_if_not_exist = parameter.create_sku_if_not_exist
    if create_sku_if_not_exist == nil then
        create_sku_if_not_exist = true
    end
    for key, value in pairs(row) do
        key = lua.trim(key)
        value = lua.trim(value)
        if lua.IsInTable( key, parameter.inv_detail_attrs ) then
            inv_detail_data[key] = value
        end
        if lua.IsInTable( key, parameter.sku_attrs ) then
            sku_data[key] = value
        end
    end

    if inv_detail_data.S_LOC_CODE == '' then
        return 1, "库存量明细中库位编码不能为空!"
    end
    if inv_detail_data.S_CNTR_CODE == '' then
        return 1, "库存量明细中容器编码不能为空!"
    end
    if inv_detail_data.S_ITEM_CODE == '' then
        return 1, "库存量明细中SKU编码不能为空!"
    end    
    
    -- 是否已经中新建的入库单对象列表中
    find = false
    for _, data in pairs(parameter.cntr_list) do
        if data.cntr_code == inv_detail_data.S_CNTR_CODE then
            if data.loc_code ~= inv_detail_data.S_LOC_CODE then
                return 1, "库存量明细中容器编码和库位编码不一致!"
            end
            find = true
            break
        end
    end

    -- 判断库位是否存在
    local loc
    nRet, loc = wms_wh.GetLocInfo( inv_detail_data.S_LOC_CODE )
    if nRet ~= 0 then
        return 1, "库位'"..inv_detail_data.S_LOC_CODE.."'不存在!"
    end    
    if not find then
        -- 判断库位是否已经绑定容器
        local cntr_list
        nRet, cntr_list = wms_wh.Get_CNTR_ByLocCode( strLuaDEID, inv_detail_data.S_LOC_CODE )
        if nRet ~= 0 then
            return 1, "库位'"..inv_detail_data.S_LOC_CODE.."' Get_CNTR_ByLocCode 时失败!"
        end
        if #cntr_list >= loc.capacity then
            return 1, "库位'"..inv_detail_data.S_LOC_CODE.."'容器已满!"
        end

        -- 判断容器是否已经存在?
        local cntr_id
        nRet, cntr_id = m3.GetDataObjectID( strLuaDEID, "Container", "S_CODE", inv_detail_data.S_CNTR_CODE )
        if nRet ~= 0 or  cntr_id == '' then
            return 1, "容器'"..inv_detail_data.S_CNTR_CODE.."'不存在!"
        end
       
        local new_cntr_loc = { cntr_code = inv_detail_data.S_CNTR_CODE, loc_code = inv_detail_data.S_LOC_CODE, id = cntr_id }
        table.insert( parameter.cntr_list, new_cntr_loc )

        -- 创建容器库位绑定
        local loc_cntr = m3.AllocObject(strLuaDEID,"Loc_Container")
        loc_cntr.loc_code = inv_detail_data.S_LOC_CODE
        loc_cntr.cntr_code = inv_detail_data.S_CNTR_CODE
        loc_cntr.bind_order = loc.cur_num + 1
        loc_cntr.bind_method = METHOD_TYPE.System
        loc_cntr.src = "Testing Import"
        -- 注意创建数据类【Loc_Container】会触发创建后事件，这里会调用  wms_ContainerLocAction
        nRet, loc_cntr = m3.CreateDataObj( strLuaDEID, loc_cntr )
        if nRet ~= 0  then
            return nRet, "创建 Loc_Container 失败! "..loc_cntr
        end        
    end
    -- 创建入库单明细
    if inv_detail_data.S_STORER == '' then
        inv_detail_data.S_STORER = parameter.storer_no
    end
    inv_detail_data.S_WH_CODE = loc.wh_code
    inv_detail_data.S_AREA_CODE = loc.area_code

    nRet, inv_detail_data = m3.CreateDataObj2( strLuaDEID, inv_detail_data )
    if nRet ~= 0 then 
        return 1, "创建 INV_Detail 失败!"..inv_detail_data
    end     
    -- 判断SKU是否已经存在，不存在创建
    if sku_data.S_STORER == '' then
        sku_data.S_STORER = parameter.storer_no
    end
    if sku_data.S_FACTORY == '' then
        sku_data.S_FACTORY = parameter.factory_no
    end
    if sku_data.S_ITEM_CODE == '' then
        return 1, "SKU 编码不能为空!"
    end
    strCondition = "S_ITEM_CODE = '"..sku_data.S_ITEM_CODE.."' AND S_STORER = '"..sku_data.S_STORER.."'"
    nRet, sku_exist = m3.ExistThisDataByCondition( strLuaDEID, "SKU", strCondition )
    if nRet ~= 0 then
        return 1, "检查SKU是否存在时,出现错误!"..sku_exist 
    end

    if not sku_exist then
        if create_sku_if_not_exist then
            nRet, sku_data = m3.CreateDataObj2( strLuaDEID, sku_data )
            if nRet ~= 0 then 
                return 1, "创建 SKU 失败!"..sku_data
            end
        else
            return 1, "SKU编码'"..sku_data.S_ITEM_CODE.."' 货主'"..sku_data.S_STORER.."' 不存在, 请先创建!"
        end
    end        

    return 0, "导入库存量成功!"
end

-- 导入一行配盘数据对象
-- 容器会和库位进行绑定
-- @function import_distribution_cntr
-- @tparam table parameter 输入参数 
-- @tparam table row 导入的入库单明细行数据 { S_DC_NO = "", ... }
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
--[[ 
    parameter 输入参数说明:
    { 
        factory_no, -- 必须有值不能为空
        wh_code, 
        storer_no, -- 必须有值不能为空
        distribution_cntr_attrs = {}, -- 库存量数据类中的属性
    }    
]]
local function import_distribution_cntr( strLuaDEID, parameter, row )
    local distribution_cntr_data = m3.AllocObject2( strLuaDEID, "Distribution_CNTR" )
    local nRet

    for key, value in pairs(row) do
        key = lua.trim(key)
        value = lua.trim(value)
        if lua.IsInTable( key, parameter.distribution_cntr_attrs ) then
            distribution_cntr_data[key] = value
        end
    end

    if distribution_cntr_data.S_FACTORY == '' then
        distribution_cntr_data.S_FACTORY = parameter.factory_no
    end    
    if distribution_cntr_data.S_LOC_CODE == '' then
        return 1, "配盘数据导入时库位编码不能为空!"
    end
    if distribution_cntr_data.S_CNTR_CODE == '' then
        return 1, "配盘数据导入时容器编码不能为空!"
    end
    
    -- 判断库位是否存在
    local loc
    nRet, loc = wms_wh.GetLocInfo( distribution_cntr_data.S_LOC_CODE )
    if nRet ~= 0 then
        return 1, "库位'"..distribution_cntr_data.S_LOC_CODE.."'不存在!"
    end    

    -- 判断容器是否存在
    local exist, err = wms_cntr.Exist( strLuaDEID, distribution_cntr_data.S_CNTR_CODE )
    if not exist then
        return 1, "容器'"..distribution_cntr_data.S_CNTR_CODE.."'不存在!"..err
    end
    -- 判断容器是否已经绑定库位
    local loc_code
    nRet, loc_code = wms_cntr.Get_Container_Loc( strLuaDEID, distribution_cntr_data.S_CNTR_CODE )
    if nRet ~= 0 then
        return 1, "wms_cntr.Get_Container_Loc 失败!"..loc_code
    end
    if loc_code ~= '' then
        return 1, "容器'"..distribution_cntr_data.S_CNTR_CODE.."'已经绑定库位!"
    end

    -- 创建容器库位绑定
    local loc_cntr = m3.AllocObject(strLuaDEID,"Loc_Container")
    loc_cntr.loc_code = distribution_cntr_data.S_LOC_CODE
    loc_cntr.cntr_code = distribution_cntr_data.S_CNTR_CODE
    loc_cntr.bind_order = loc.cur_num + 1
    loc_cntr.bind_method = METHOD_TYPE.System
    loc_cntr.src = "Testing Import"
    -- 注意创建数据类【Loc_Container】会触发创建后事件，这里会调用  wms_ContainerLocAction
    nRet, loc_cntr = m3.CreateDataObj( strLuaDEID, loc_cntr )
    if nRet ~= 0  then
        return nRet, "创建 Loc_Container 失败! "..loc_cntr
    end        

    nRet, distribution_cntr_data = m3.CreateDataObj2( strLuaDEID, distribution_cntr_data )
    if nRet ~= 0 then 
        return 1, "创建 Distribution_CNTR 失败!"..distribution_cntr_data
    end     

    return 0, "导入配盘成功!"
end

-- 导入一行入库单明细
-- 如果入库单不存在会创建入库单，SKU 不存在会创建SKU
-- @function import_inbound_order
-- @tparam table parameter 输入参数 
-- @tparam table row 导入的入库单明细行数据 { S_IO_NO = "", N_ROW_NO = "1", ... }
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
--[[ 
    parameter 输入参数说明:
    { 
        factory_no, -- 必须有值不能为空
        wh_code, 
        storer_no, -- 必须有值不能为空
        new_inbound_order_list = {{id="", inbound_order_no = ""},...} -- 本次导入创建入库单对象列表
        inbound_order_attrs = {}, -- 入库单数据类中的属性
        inbound_order_detail_attrs = {}, -- 入库单明细数据类中的属性
        sku_attrs = {} -- sku 数据类中的属性
    }    
]]
local function import_inbound_order( strLuaDEID, parameter, row )
    local inbound_order_data = m3.AllocObject2( strLuaDEID, "Inbound_Order" )
    local inbound_order_detail_data = m3.AllocObject2( strLuaDEID, "Inbound_Detail" )
    local sku_data = m3.AllocObject2( strLuaDEID, "SKU" )

    local find, strCondition
    local nRet, sku_exist
    for key, value in pairs(row) do
        key = lua.trim(key)
        value = lua.trim(value)
        if lua.IsInTable( key, parameter.inbound_order_attrs ) then
            inbound_order_data[key] = value
        end
        if lua.IsInTable( key, parameter.inbound_order_detail_attrs ) then
            inbound_order_detail_data[key] = value
        end
        if lua.IsInTable( key, parameter.sku_attrs ) then
            sku_data[key] = value
        end
    end

    if inbound_order_detail_data.S_IO_NO == '' then
        return 1, "入库单明细中入库单号不能为空!"
    end
    inbound_order_data.S_NO = inbound_order_detail_data.S_IO_NO

    -- 是否已经中新建的入库单对象列表中
    find = false
    for _, data in pairs(parameter.new_inbound_order_list) do
        if data.inbound_order_no == inbound_order_data.S_NO then
            find = true
            break
        end
    end
    if not find then
        -- 创建入库单
        if inbound_order_data.S_FACTORY == '' then
            inbound_order_data.S_FACTORY = parameter.factory_no
        end
        if inbound_order_data.S_WH_CODE == '' then
            inbound_order_data.S_WH_CODE = parameter.wh_code
        end
        nRet, inbound_order_data = m3.CreateDataObj2( strLuaDEID, inbound_order_data )
        if nRet ~= 0 then 
            return 1, "创建 Inbound_Order 失败!"..inbound_order_data
        end    
        local new_order = { id = inbound_order_data.id, inbound_order_no = inbound_order_data.S_NO }
        table.insert( parameter.new_inbound_order_list, new_order )
    end
    -- 创建入库单明细
    if inbound_order_detail_data.S_STORER == '' then
        inbound_order_detail_data.S_STORER = parameter.storer_no
    end
    if inbound_order_detail_data.S_ITEM_CODE == '' then
        return 1, "入库单明细中 SKU 编码不能为空!"
    end    
    nRet, inbound_order_detail_data = m3.CreateDataObj2( strLuaDEID, inbound_order_detail_data )
    if nRet ~= 0 then 
        return 1, "创建 Inbound_Detail 失败!"..inbound_order_detail_data
    end     
    -- 判断SKU是否已经存在，不存在创建
    if sku_data.S_STORER == '' then
        sku_data.S_STORER = parameter.storer_no
    end
    if sku_data.S_FACTORY == '' then
        sku_data.S_FACTORY = parameter.factory_no
    end
    if sku_data.S_ITEM_CODE == '' then
        return 1, "SKU 编码不能为空!"
    end
    strCondition = "S_ITEM_CODE = '"..sku_data.S_ITEM_CODE.."' AND S_STORER = '"..sku_data.S_STORER.."'"
    nRet, sku_exist = m3.ExistThisDataByCondition( strLuaDEID, "SKU", strCondition )
    if nRet ~= 0 then
        return 1, "检查SKU是否存在时,出现错误!"..sku_exist 
    end

    if not sku_exist then
        nRet, sku_data = m3.CreateDataObj2( strLuaDEID, sku_data )
        if nRet ~= 0 then 
            return 1, "创建 SKU 失败!"..sku_data
        end  
    end        

    return 0, "导入入库单成功!"
end

-- 导入一条出库单明细
-- @function import_outbound_order
-- @tparam table parameter 输入参数 
-- @tparam table row 导入的入出单明细行数据 { S_OO_NO = "", N_ROW_NO = "1", ... }
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
--[[ 
    parameter 输入参数说明:
    { 
        factory_no, -- 必须有值不能为空
        wh_code, 
        storer_no, -- 必须有值不能为空
        new_outbound_order_list = {{id="", outbound_order_no = ""},...} -- 本次导入创建出库单对象列表
        outbound_order_attrs = {}, -- 出库单数据类中的属性
        outbound_order_detail_attrs = {}, -- 出库单明细数据类中的属性
    }    
]]
local function import_outbound_order( strLuaDEID, parameter, row )
    local outbound_order_data = m3.AllocObject2( strLuaDEID, "Outbound_Order" )
    local outbound_order_detail_data = m3.AllocObject2( strLuaDEID, "Outbound_Detail" )
    local find, nRet
    for key, value in pairs(row) do
        key = lua.trim(key)
        value = lua.trim(value)
        if lua.IsInTable( key, parameter.outbound_order_attrs ) then
            outbound_order_data[key] = value
        end
        if lua.IsInTable( key, parameter.outbound_order_detail_attrs ) then
            outbound_order_detail_data[key] = value
        end
    end

    if outbound_order_detail_data.S_OO_NO == '' then
        return 1, "出库单明细中出库单号不能为空!"
    end
    outbound_order_data.S_NO = outbound_order_detail_data.S_OO_NO

    -- 是否已经中新建的出库单对象列表中
    find = false
    for _, data in pairs(parameter.new_outbound_order_list) do
        if data.outbound_order_no == outbound_order_data.S_NO then
            find = true
            break
        end
    end
    if not find then
        -- 创建出库单
        if outbound_order_data.S_FACTORY == '' then
            outbound_order_data.S_FACTORY = parameter.factory_no
        end
        if outbound_order_data.S_WH_CODE == '' then
            outbound_order_data.S_WH_CODE = parameter.wh_code
        end
        nRet, outbound_order_data = m3.CreateDataObj2( strLuaDEID, outbound_order_data )
        if nRet ~= 0 then 
            return 1, "创建 Outbound_Order 失败!"..outbound_order_data
        end    
        local new_order = { id = outbound_order_data.id, outbound_order_no = outbound_order_data.S_NO }
        table.insert( parameter.new_outbound_order_list, new_order )
    end
    -- 创建出库单明细
    if outbound_order_detail_data.S_STORER == '' then
        outbound_order_detail_data.S_STORER = parameter.storer_no
    end
    if outbound_order_detail_data.S_ITEM_CODE == '' then
        return 1, "出库单明细中 SKU 编码不能为空!"
    end    
    nRet, outbound_order_detail_data = m3.CreateDataObj2( strLuaDEID, outbound_order_detail_data )
    if nRet ~= 0 then 
        return 1, "创建 Outbound_Detail 失败!"..outbound_order_detail_data
    end     

    return 0, "导入出库单成功!"
end

-- 导入组盘
-- SKU 不存在会创建SKU
-- @function import_inbound_palletization
-- @tparam table parameter 输入参数 
-- @tparam table row 导入的组盘明细 { S_IBP_NO = "", N_ROW_NO = "1", ... }
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
--[[ 
    parameter 输入参数说明:
    { 
        factory_no, -- 必须有值不能为空
        wh_code, 
        storer_no, -- 必须有值不能为空
        new_ibp_list = {{id="", ibp_no = ""},...} -- 本次导入创建组盘单对象列表
        ibp_attrs = {}, -- 组盘数据类中的属性
        ibp_detail_attrs = {}, -- 组盘明细数据类中的属性
        sku_attrs = {} -- sku 数据类中的属性
    }    
]]
local function import_inbound_palletization( strLuaDEID, parameter, row )
    local ibp_data = m3.AllocObject2( strLuaDEID, "Inbound_Palletization" )
    local ibp_detail_data = m3.AllocObject2( strLuaDEID, "INB_Pallet_Detail" )
    local sku_data = m3.AllocObject2( strLuaDEID, "SKU" )

    local find, strCondition
    local nRet, sku_exist
    for key, value in pairs(row) do
        key = lua.trim(key)
        value = lua.trim(value)
        if lua.IsInTable( key, parameter.ibp_attrs ) then
            ibp_data[key] = value
        end
        if lua.IsInTable( key, parameter.ibp_detail_attrs ) then
            ibp_detail_data[key] = value
        end
        if lua.IsInTable( key, parameter.sku_attrs ) then
            sku_data[key] = value
        end
    end

    if ibp_detail_data.S_IBP_NO == '' then
        return 1, "组盘明细中组盘单号不能为空!"
    end

    -- 是否已经中新建的组盘对象列表中
    find = false
    for _, data in pairs(parameter.new_ibp_list) do
        if data.ibp_no == ibp_data.S_IBP_NO then
            find = true
            break
        end
    end
    if not find then
        -- 创建组盘单
        if ibp_data.S_FACTORY == '' then
            ibp_data.S_FACTORY = parameter.factory_no
        end
        if ibp_data.S_WH_CODE == '' then
            ibp_data.S_WH_CODE = parameter.wh_code
        end
        nRet, ibp_data = m3.CreateDataObj2( strLuaDEID, ibp_data )
        if nRet ~= 0 then 
            return 1, "创建 Inbound_Palletization 失败!"..ibp_data
        end    
        local new_order = { id = ibp_data.id, ibp_no = ibp_data.S_IBP_NO }
        table.insert( parameter.new_ibp_list, new_order )
    end
    -- 创建组盘明细
    if ibp_detail_data.S_STORER == '' then
        ibp_detail_data.S_STORER = parameter.storer_no
    end
    if ibp_detail_data.S_ITEM_CODE == '' then
        return 1, "组盘明细中 SKU 编码不能为空!"
    end    
    nRet, ibp_detail_data = m3.CreateDataObj2( strLuaDEID, ibp_detail_data )
    if nRet ~= 0 then 
        return 1, "创建 INB_Pallet_Detail 失败!"..ibp_detail_data
    end     
    -- 判断SKU是否已经存在，不存在创建
    if sku_data.S_STORER == '' then
        sku_data.S_STORER = parameter.storer_no
    end
    if sku_data.S_FACTORY == '' then
        sku_data.S_FACTORY = parameter.factory_no
    end
    if sku_data.S_ITEM_CODE == '' then
        return 1, "SKU 编码不能为空!"
    end
    strCondition = "S_ITEM_CODE = '"..sku_data.S_ITEM_CODE.."' AND S_STORER = '"..sku_data.S_STORER.."'"
    nRet, sku_exist = m3.ExistThisDataByCondition( strLuaDEID, "SKU", strCondition )
    if nRet ~= 0 then
        return 1, "检查SKU是否存在时,出现错误!"..sku_exist 
    end

    if not sku_exist then
        nRet, sku_data = m3.CreateDataObj2( strLuaDEID, sku_data )
        if nRet ~= 0 then 
            return 1, "创建 SKU 失败!"..sku_data
        end  
    end        

    return 0, "导入组盘成功!"
end

-- 导入库存量表
-- @function wms_import.INV_Detail
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string factory_no 工厂编码，必须有值
-- @tparam string wh_code 仓库编码
-- @tparam string storer_no 货主编码，必须有值
-- @tparam table rows 导入的数据行数组，每行是 { 字段名 = 值, ... }
-- @tparam number start_row 起始行号（默认 1），用于跳过表头
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
function wms_import.INV_Detail( strLuaDEID, factory_no, wh_code, storer_no, rows, start_row )
    local err
    if factory_no == nil or factory_no == '' then
        return 1, "工厂编码不能为空!"
    end
    if storer_no == nil or storer_no == '' then
        return 1, "货主不能为空!"
    end
    if start_row == nil then
        start_row = 1
    end
    local parameter = {
        factory_no = factory_no,
        wh_code = wh_code,
        storer_no = storer_no,
        inv_detail_attrs = {},
        sku_attrs = {},
        cntr_list = {}
    }

    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "INV_Detail" )
    if nRet ~= 0 then
        return 1, "获取 INV_Detail 对象属性失败! 原因:"..cls_attrs
    end
    parameter.inv_detail_attrs = cls_attrs

    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "SKU" )
    if nRet ~= 0 then
        return 1, "获取 SKU 对象属性失败! 原因:"..cls_attrs
    end
    parameter.sku_attrs = cls_attrs

    for n = start_row, #rows do
        nRet, err = import_inv_detail( strLuaDEID, parameter, rows[n] )
        if nRet ~= 0 then
            return 1, "导入INV_detail失败!"..err
        end
    end
    return 0
end

-- 导入配盘数据对象，并且和库位绑定
-- @function wms_import.Distribution_CNTR
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string factory_no 工厂编码，必须有值
-- @tparam string wh_code 仓库编码
-- @tparam string storer_no 货主编码，必须有值
-- @tparam table rows 导入的数据行数组，每行是 { 字段名 = 值, ... }
-- @tparam number start_row 起始行号（默认 1），用于跳过表头
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
function wms_import.Distribution_CNTR( strLuaDEID, factory_no, wh_code, storer_no, rows, start_row )
    local err
    if factory_no == nil or factory_no == '' then
        return 1, "工厂编码不能为空!"
    end
    if storer_no == nil or storer_no == '' then
        return 1, "货主不能为空!"
    end
    if start_row == nil then
        start_row = 1
    end
    local parameter = {
        factory_no = factory_no,
        wh_code = wh_code,
        storer_no = storer_no,
        distribution_cntr_attrs = {},
    }

    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "Distribution_CNTR" )
    if nRet ~= 0 then
        return 1, "获取 Distribution_CNTR 对象属性失败! 原因:"..cls_attrs
    end
    parameter.distribution_cntr_attrs = cls_attrs
    for n = start_row, #rows do
        nRet, err = import_distribution_cntr( strLuaDEID, parameter, rows[n] )
        if nRet ~= 0 then
            return 1, "导入INV_detail失败!"..err
        end
    end
    return 0
end

-- 导入入库单（含明细、SKU）
-- 调用方按行遍历数据，同一入库单号的多行明细自动合并到一张入库单
-- @function wms_import.Inbound_Order
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string factory_no 工厂编码，必须有值
-- @tparam string wh_code 仓库编码
-- @tparam string storer_no 货主编码，必须有值
-- @tparam table rows 导入的数据行数组，每行是 { 字段名 = 值, ... }
-- @tparam number start_row 起始行号（默认 1），用于跳过表头
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
function wms_import.Inbound_Order( strLuaDEID, factory_no, wh_code, storer_no, rows, start_row )
    local err
    if factory_no == nil or factory_no == '' then
        return 1, "工厂编码不能为空!"
    end
    if storer_no == nil or storer_no == '' then
        return 1, "货主不能为空!"
    end
    if start_row == nil then
        start_row = 1
    end
    local parameter = {
        factory_no = factory_no,
        wh_code = wh_code,
        storer_no = storer_no,
        new_inbound_order_list = {},
        inbound_order_attrs = {},
        inbound_order_detail_attrs = {},
        sku_attrs = {}
    }

    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "Inbound_Order" )
    if nRet ~= 0 then
        return 1, "获取 Inbound_Order 对象属性失败! 原因:"..cls_attrs
    end
    parameter.inbound_order_attrs = cls_attrs

    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "Inbound_Detail" )
    if nRet ~= 0 then
        return 1, "获取 Inbound_Detail 对象属性失败! 原因:"..cls_attrs
    end
    parameter.inbound_order_detail_attrs = cls_attrs

    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "SKU" )
    if nRet ~= 0 then
        return 1, "获取 SKU 对象属性失败! 原因:"..cls_attrs
    end
    parameter.sku_attrs = cls_attrs
    
    for n = start_row, #rows do
        nRet, err = import_inbound_order( strLuaDEID, parameter, rows[n] )
        if nRet ~= 0 then
            return 1, "导入入库单失败!"..err
        end
    end
    return 0
end

-- 导入出库单（含明细）
-- 调用方按行遍历数据，同一出库单号的多行明细自动合并到一张出库单
-- @function wms_import.Outbound_Order
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string factory_no 工厂编码，必须有值
-- @tparam string wh_code 仓库编码
-- @tparam string storer_no 货主编码，必须有值
-- @tparam table rows 导入的数据行数组，每行是 { 字段名 = 值, ... }
-- @tparam number start_row 起始行号（默认 1），用于跳过表头
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
function wms_import.Outbound_Order( strLuaDEID, factory_no, wh_code, storer_no, rows, start_row )
    local err
    if factory_no == nil or factory_no == '' then
        return 1, "工厂编码不能为空!"
    end
    if storer_no == nil or storer_no == '' then
        return 1, "货主不能为空!"
    end
    if start_row == nil then
        start_row = 1
    end
    local parameter = {
        factory_no = factory_no,
        wh_code = wh_code,
        storer_no = storer_no,
        new_outbound_order_list = {},
        outbound_order_attrs = {},
        outbound_order_detail_attrs = {},
    }

    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "Outbound_Order" )
    if nRet ~= 0 then
        return 1, "获取 Outbound_Order 对象属性失败! 原因:"..cls_attrs
    end
    parameter.outbound_order_attrs = cls_attrs

    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "Outbound_Detail" )
    if nRet ~= 0 then
        return 1, "获取 Outbound_Detail 对象属性失败! 原因:"..cls_attrs
    end
    parameter.outbound_order_detail_attrs = cls_attrs

    for n = start_row, #rows do
        nRet, err = import_outbound_order( strLuaDEID, parameter, rows[n] )
        if nRet ~= 0 then
            return 1, "导入出库单失败!"..err
        end
    end
    return 0
end

-- 导入组盘单（含明细、SKU）
-- 调用方按行遍历数据，同一组盘单号的多行明细自动合并到一张组盘单
-- @function wms_import.Inbound_Palletization
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string factory_no 工厂编码，必须有值
-- @tparam string wh_code 仓库编码
-- @tparam string storer_no 货主编码，必须有值
-- @tparam table rows 导入的数据行数组，每行是 { 字段名 = 值, ... }
-- @tparam number start_row 起始行号（默认 1），用于跳过表头
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
function wms_import.Inbound_Palletization( strLuaDEID, factory_no, wh_code, storer_no, rows, start_row )
    local err
    if factory_no == nil or factory_no == '' then
        return 1, "工厂编码不能为空!"
    end
    if storer_no == nil or storer_no == '' then
        return 1, "货主不能为空!"
    end
    if start_row == nil then
        start_row = 1
    end
    local parameter = {
        factory_no = factory_no,
        wh_code = wh_code,
        storer_no = storer_no,
        new_ibp_list = {},
        ibp_attrs = {},
        ibp_detail_attrs = {},
        sku_attrs = {}
    }

    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "Inbound_Palletization" )
    if nRet ~= 0 then
        return 1, "获取 Inbound_Palletization 对象属性失败! 原因:"..cls_attrs
    end
    parameter.ibp_attrs = cls_attrs

    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "INB_Pallet_Detail" )
    if nRet ~= 0 then
        return 1, "获取 INB_Pallet_Detail 对象属性失败! 原因:"..cls_attrs
    end
    parameter.ibp_detail_attrs = cls_attrs

    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "SKU" )
    if nRet ~= 0 then
        return 1, "获取 SKU 对象属性失败! 原因:"..cls_attrs
    end
    parameter.sku_attrs = cls_attrs
    
    for n = start_row, #rows do
        nRet, err = import_inbound_palletization( strLuaDEID, parameter, rows[n] )
        if nRet ~= 0 then
            return 1, "导入组盘单失败!"..err
        end
    end
    return 0
end

-- 导入容器数据对象
-- 支持单条创建与批量创建：行中包含 CreateQty（数量）和 CodeHead（编码前缀）列时按批次创建，
-- 容器编码由序列号自动生成；批量创建前会清空该编码分组的序列号种子
-- @function wms_import.Container
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string factory_no 工厂编码，必须有值
-- @tparam table rows 导入的数据行数组，每行是 { 字段名 = 值, ..., CreateQty = 数量, CodeHead = 编码前缀 }
-- @tparam number start_row 起始行号（默认 1），用于跳过表头
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
function wms_import.Container( strLuaDEID, factory_no, rows, start_row )
    local err
    if factory_no == nil or factory_no == '' then
        return 1, "工厂编码不能为空!"
    end
    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "Container" )
    if nRet ~= 0 then
        return 1, "获取 Container 对象属性失败! 原因:"..cls_attrs
    end
    if start_row == nil then
        start_row = 1
    end
    local batch_create, head_code, qty, ctd
    local container, strCode
    local group = "TCC-"..factory_no

    -- 清空用于测试用例的容器编码顺序种子值
    nRet, err = mobox.removeSerialNumber( group )
    if nRet ~= 0 then
        return 1, "删除序列号失败! 原因:"..err
    end

    for n = start_row, #rows do
        local cntr_data = m3.AllocObject2( strLuaDEID, "Container" )
        qty = 0
        head_code = ''
        batch_create = false

        for key, value in pairs(rows[n]) do
            key = lua.trim(key)
            value = lua.trim(value)
            if lua.IsInTable( key, cls_attrs ) then
                cntr_data[key] = value
            elseif key == "CreateQty" then
                batch_create = true
                qty = tonumber(value)
                if qty == nil  or qty <= 0 then 
                    return 1,"Data#Container 页中第"..n.."行 CreateQty 列的值必须有值且大于 0 "
                end
            elseif key == "CodeHead" then
                head_code = value
                if head_code == '' then 
                    return 1,"Data#Container 页中第"..n.."行 CodeHead 列的值必须有值 "
                end                
            end
        end
        cntr_data.S_FACTORY = factory_no
        if cntr_data.S_CTD_CODE == '' then
            return 1,"Data#Container 页中第"..n.."行 S_CTD_CODE 列的值必须有值 "
        end

        nRet, ctd = wms_cntr.GetCTDInfo( cntr_data.S_CTD_CODE, strLuaDEID )
        if nRet ~= 0 then
            return 1,"Data#Container 页中第"..n.."行容器类型定义'"..cntr_data.S_CTD_CODE.."'定义获取失败!"..ctd
        end            
        if not batch_create then
            nRet, cntr_data = m3.CreateDataObj2( strLuaDEID, cntr_data )
            if nRet ~= 0 then 
                return 1, "创建 Container 失败!"..cntr_data
            end
        else
            -- 批量创建容器
            for m = 1, qty do
                container = m3.AllocObject2( strLuaDEID, "Container" )
                -- 将模板行(cntr_data)的字段复制到新容器对象，避免所有容器共享同一对象
                if cntr_data ~= nil then
                    for ck, cv in pairs(cntr_data) do
                        container[ck] = cv
                    end
                end
                container.S_TYPE = ctd.data.S_TYPE
                -- 申请容器编码
                nRet, strCode = mobox.getSerialNumber( group, head_code, 1)
                if nRet ~= 0 then 
                    return 1, "申请容器编码失败!"
                end
                container.S_CTD_CODE = ctd.data.S_CTD_CODE
                container.S_CODE = strCode
                container.S_FACTORY = factory_no
                nRet, container = m3.CreateDataObj2(strLuaDEID, container)
                if nRet ~= 0 then 
                    return 1, "创建 Container 失败!"..container
                end           
            end            
        end
    end
    return 0    
end

-- 导入库区数据对象，并按需生成库位
-- 行中包含 CreateLocation 列（JSON 格式）时，按 type 字段创建立体库（立库）或平面库/地堆库位
-- @function wms_import.Area
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string factory_no 工厂编码，必须有值
-- @tparam string wh_code 仓库编码
-- @tparam table rows 导入的数据行数组，每行是 { 字段名 = 值, ..., CreateLocation = "{json}" }
-- @tparam number start_row 起始行号（默认 1），用于跳过表头
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
function wms_import.Area( strLuaDEID, factory_no, wh_code, rows, start_row )
    local err
    if factory_no == nil or factory_no == '' then
        return 1, "工厂编码不能为空!"
    end
    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, "Area" )
    if nRet ~= 0 then
        return 1, "获取 Area 对象属性失败! 原因:"..cls_attrs
    end
    if start_row == nil then
        start_row = 1
    end
    local create_loc_parameter = {}
    local success

    for n = start_row, #rows do
        local area_data = m3.AllocObject2( strLuaDEID, "Area" )
        create_loc_parameter = nil
        for key, value in pairs(rows[n]) do
            key = lua.trim(key)
            value = lua.trim(value)
            if lua.IsInTable( key, cls_attrs ) then
                area_data[key] = value
            elseif key == "CreateLocation" then
                if value ~= '' then
                    success, create_loc_parameter = pcall( json.decode, value )
                    if not success then 
                        return 1,"Data#Area 页中第"..n.."行 CreateLocation 字段解析失败! 原因:"..create_loc_parameter
                    end
                end
            end
        end
        area_data.S_FACTORY = factory_no
        if area_data.S_WH_CODE == '' then
            area_data.S_WH_CODE = wh_code
        end
        if area_data.S_TYPE == '' then
            area_data.S_TYPE = "存储区"
        end
        local area_type = AREA_TYPE_NAME[area_data.S_TYPE]
        if area_type == nil then
            return 1, "Area 类型不支持! --> "..area_data.S_TYPE
        end
        area_data.N_TYPE = area_type
        nRet, area_data = m3.CreateDataObj2( strLuaDEID, area_data )
        if nRet ~= 0 then 
            return 1, "创建 Area失败!"..area_data
        end

        -- 是否有要继续创建库位
        if create_loc_parameter ~= nil then
            if create_loc_parameter.type == "立体库" or create_loc_parameter.type == "立库"  then
                nRet, err = create_high_bay_wh_loc( strLuaDEID, area_data, create_loc_parameter )
                if nRet ~= 0 then
                    return 1, "创建库位失败! 原因:"..err
                end
            elseif create_loc_parameter.type == "平面库" or create_loc_parameter.type == "地堆" then
                nRet, err = create_low_bay_wh_loc( strLuaDEID, area_data, create_loc_parameter )
                if nRet ~= 0 then
                    return 1, "创建库位失败! 原因:"..err
                end
            else
                return 1, "CreateLocation 的 type 字段不支持! --> "..tostring(create_loc_parameter.type)
            end
        end
    end
    return 0
end

-- 导入任意数据类对象（通用导入）
-- 按数据类的属性列表过滤行数据，字段缺失时用传入的 factory_no/wh_code/storer_no 兜底
-- @function wms_import.Data
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cls_id 数据类标识（如 "Batch"、"Container"）
-- @tparam string factory_no 工厂编码
-- @tparam string wh_code 仓库编码
-- @tparam string storer_no 货主编码
-- @tparam table rows 导入的数据行数组，每行是 { 字段名 = 值, ... }
-- @tparam number start_row 起始行号（默认 1），用于跳过表头
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string err 失败返回错误信息
function wms_import.Data( strLuaDEID, cls_id, factory_no, wh_code, storer_no, rows, start_row )

    local nRet, cls_attrs = m3.Get_Cls_Attrs( strLuaDEID, cls_id )
    if nRet ~= 0 then
        return 1, "获取"..cls_id.."对象属性失败! 原因:"..cls_attrs
    end
    if start_row == nil then
        start_row = 1
    end
    for n = start_row, #rows do
        local data = m3.AllocObject2( strLuaDEID, cls_id )
        for key, value in pairs(rows[n]) do
            key = lua.trim(key)
            value = lua.trim(value)
            if lua.IsInTable( key, cls_attrs ) then
                data[key] = value
            end
        end
        if data.S_FACTORY ~= nil and data.S_FACTORY == '' then
            data.S_FACTORY = factory_no
        end
        if data.S_WH_CODE ~= nil and data.S_WH_CODE == '' then
            data.S_WH_CODE = wh_code
        end        
        if data.S_STORER ~= nil and data.S_STORER == '' then
            data.S_STORER = storer_no
        end    
        nRet, data = m3.CreateDataObj2( strLuaDEID, data )
        if nRet ~= 0 then 
            return 1, "创建 '"..cls_id.."' 失败!"..data
        end
    end  
    return 0
end

-- 从测试用例的Data#xxx页签获取测试用例中和WMS相关的基础数据,包括下面这些数据类
-- @function wms_import.Import_Data
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string factory_no 工厂编码
-- @tparam string wh_code 仓库编码
-- @tparam string storer_no 货主编码
-- @tparam string cls_id 导入的数据类标识
-- @tparam table rows 测试用例的 Tool 页签数据队列
-- @treturn number nRet 0: 成功，1: 创建失败，2: 参数错误
-- @treturn table/string tc_tools_list 成功返回 WMS_TC_Tools 对象，失败返回错误信息
function wms_import.Import_Data( strLuaDEID, factory_no, wh_code, storer_no, cls_id, rows, start_row )
    local nRet, err

    if start_row == nil then
        start_row = 1
    end
    if factory_no == nil or factory_no == '' then
        return 1, "工厂编码不能为空!"
    end

    if cls_id == nil or cls_id == '' then
        return 1, "cls_id不能为空!"
    end

    if cls_id == "Area" then
        -- 库区有特别处理比如创建库位
        nRet, err = wms_import.Area( strLuaDEID, factory_no, wh_code, rows, start_row )
        if nRet ~= 0 then
            return 1, "导入库区数据失败! 原因:"..err
        end
    elseif cls_id == "Container" then
        -- 容器有特别处理比如列里带 CreateQty 时需要批量创建容器
        nRet, err = wms_import.Container( strLuaDEID, factory_no, rows, start_row )
        if nRet ~= 0 then
            return 1, "导入容器数据失败! 原因:"..err
        end   
    elseif cls_id == "INV_Detail" then
        -- 导入组盘单
        nRet, err = wms_import.INV_Detail( strLuaDEID, factory_no, wh_code, storer_no, rows, start_row )
        if nRet ~= 0 then
            return 1, "导入库存量数据失败! 原因:"..err
        end 
    elseif cls_id == "Distribution_CNTR" then
        -- 导入组盘单
        nRet, err = wms_import.Distribution_CNTR( strLuaDEID, factory_no, wh_code, storer_no, rows, start_row )
        if nRet ~= 0 then
            return 1, "导入 Distribution_CNTR 数据失败! 原因:"..err
        end         
    elseif cls_id == "Warehouse" then
        if wh_code ~= '' then
            local strCondition = "S_CODE = '"..wh_code.."'"    
            nRet, err = mobox.dbdeleteData(strLuaDEID, "Warehouse", strCondition)
            if nRet ~= 0 then 
                return 1, "删除【Warehouse】失败!"..err
            end
        end
        nRet, err = wms_import.Data( strLuaDEID, cls_id, factory_no, wh_code, storer_no, rows, start_row )
        if nRet ~= 0 then
            return 1, "导入"..cls_id.."数据失败! 原因:"..err
        end        
    else
        nRet, err = wms_import.Data( strLuaDEID, cls_id, factory_no, wh_code, storer_no, rows, start_row )
        if nRet ~= 0 then
            return 1, "导入"..cls_id.."数据失败! 原因:"..err
        end
    end

    return 0
end

-- 从测试用例的MSData#xxx页签获取测试用例中和WMS相关的主从表模式的业务数据对象
-- @function wms_import.Import_MSData
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string factory_no 工厂编码
-- @tparam string wh_code 仓库编码
-- @tparam string storer_no 货主编码
-- @tparam string cls_id 导入的数据类标识
-- @tparam table rows 测试用例的 Tool 页签数据队列
-- @treturn number nRet 0: 成功，1: 创建失败，2: 参数错误
-- @treturn table/string tc_tools_list 成功返回 WMS_TC_Tools 对象，失败返回错误信息
function wms_import.Import_MSData( strLuaDEID, factory_no, wh_code, storer_no, cls_id, rows, start_row )
    local nRet, err

    if start_row == nil then
        start_row = 1
    end
    if factory_no == nil or factory_no == '' then
        return 1, "工厂编码不能为空!"
    end

    if cls_id == nil or cls_id == '' then
        return 1, "cls_id不能为空!"
    end

    if cls_id == "Inbound_Order" then
        -- 导入入库单
        nRet, err = wms_import.Inbound_Order( strLuaDEID, factory_no, wh_code, storer_no, rows, start_row )
        if nRet ~= 0 then
            return 1, "导入入库单数据失败! 原因:"..err
        end   
    elseif cls_id == "Outbound_Order" then
        -- 导入出库单
        nRet, err = wms_import.Outbound_Order( strLuaDEID, factory_no, wh_code, storer_no, rows, start_row )
        if nRet ~= 0 then
            return 1, "导入出库单数据失败! 原因:"..err
        end     
    elseif cls_id == "Inbound_Palletization" then
        -- 导入组盘单
        nRet, err = wms_import.Inbound_Palletization( strLuaDEID, factory_no, wh_code, storer_no, rows, start_row )
        if nRet ~= 0 then
            return 1, "导入组盘单数据失败! 原因:"..err
        end
    else
        return 1, "数据类'"..cls_id.."'，没有主从导入模式!"
    end

    return 0
end

-- 用于导入公司标准数据导入模板输入的excel数据
-- @function wms_import.Import
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number nRet 0: 成功，1: 创建失败，2: 参数错误
-- @treturn string err 失败返回错误信息
function wms_import.Import(strLuaDEID)
    local nRet, err
    local strClsID, strObjID
    nRet, strClsID, strObjID = mobox.getCurEditDataObjID( strLuaDEID )
    if nRet ~= 0 or strClsID == '' then
        return 2, "getCurEditDataObjID失败!  "..strClsID
    end
    -- 获取导入的数据, 返回 [{"attr":"xx","value":""},...]
    local row_data = {}
    nRet, row_data = m3.GetSysDataJson(strLuaDEID)
    if nRet ~= 0 then 
        return 1, "无法获取导入数据!"
    end

    local factory_no
    nRet, factory_no = wms_base.Get_sConst2( "WMS_Default_Factory" )
    if nRet ~= 0 then
        return 1, "系统无法获取常量'WMS_Default_Factory'"
    end      
    local wh_code   -- 默认入库仓库
    nRet, wh_code = wms_base.Get_sConst2( "WMS_Default_Warehouse" )
    if nRet ~= 0 then
        return 1, "系统无法获取常量'WMS_Default_Warehouse'"
    end
    
    local storer_no   -- 默认货主
    nRet, storer_no = wms_base.Get_sConst2( "WMS_Default_Storer" )
    if nRet ~= 0 then
        return 1, "系统无法获取常量'WMS_Default_Storer'"
    end

    local excel_rows = {}
    for _, row_attrs in ipairs( row_data ) do
        local row = {}
        for _, attr in ipairs( row_attrs ) do
            row[attr.attr] = attr.value
        end
        table.insert( excel_rows, row )
    end
    nRet, err = wms_import.Import_Data( strLuaDEID, factory_no, wh_code, storer_no, strClsID, excel_rows )
    if nRet ~= 0 then
        return 1, "导入失败! " .. err
    end
    return 0
end

function wms_import.Clear_Business_Data( strLuaDEID, factory_no, cls_id )
    local nRet
    if factory_no == nil or factory_no == '' then
        return 1, "wms_import.Clear_Business_Data 函数的参数 factory_no 必须有值"
    end
    local exist, factory, data_list, condition
    local strCondition = "S_FACTORY = '"..factory_no.."'"

    nRet, exist = m3.ExistThisDataObject( strLuaDEID, "Factory", "S_CODE", factory_no )
    if exist then    
        nRet, factory = m3.GetDataObjectByKey2( strLuaDEID, "Factory", "S_CODE", factory_no )
        if nRet ~= 0 then 
            return 1, "获取 Factory 属性失败! "..factory
        end
        if factory.C_TESTING == 'Y' then
            local err

            if cls_id == nil or cls_id == '' then
                return 1, "wms_import.Clear_Business_Data 函数的参数 cls_id 必须有值"
            end

            if cls_id == "Operation" then
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

                    nRet, err = mobox.dbdeleteData(strLuaDEID, "Operation_Log", condition )    
                    if nRet ~= 0 then 
                        return 1, "删除'Operation_Log'数据失败! " .. err
                    end                    
                end
            elseif cls_id == "Distribution_CNTR" then
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
            elseif cls_id == "Inbound_Order" then
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
            elseif cls_id == "Outbound_Order" then
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
            elseif cls_id == "INV_Detail" then
                -- 删除库存量
                strCondition = "S_WH_CODE IN ( select S_CODE from TN_Warehouse where S_FACTORY = '"..factory_no.."')"
                nRet, err = mobox.deleteDataObject(strLuaDEID, "INV_Detail", strCondition)    
                if nRet ~= 0 then 
                    return 1, "删除'INV_Detail'数据失败! " .. err
                end  
            elseif cls_id == "Loc_Container" then
                -- 删除 Loc_Container 
                strCondition = "S_LOC_CODE IN ( select S_CODE from TN_Location where S_WH_CODE IN ( select S_CODE from TN_Warehouse where S_FACTORY = '"..factory_no.."'))"
                nRet, err = mobox.dbdeleteData(strLuaDEID, "Loc_Container", strCondition )    
                if nRet ~= 0 then 
                    return 1, "删除'Loc_Container'数据失败! " .. err
                end
            elseif cls_id == "Lock" then
                -- 删除库位锁 Lock
                strCondition = "N_OBJ_TYPE = 1 AND S_OBJ_CODE IN ( select S_CODE from TN_Location where S_WH_CODE IN ( select S_CODE from TN_Warehouse where S_FACTORY = '"..factory_no.."'))"
                nRet, err = mobox.dbdeleteData(strLuaDEID, "Lock", strCondition )    
                if nRet ~= 0 then 
                    return 1, "删除'Lock'数据失败! " .. err
                end                
            else
                return 1, "Clear_Business_Data 函数目前还不支持数据类'"..cls_id.."'的清除操作!"
            end
        end
    end
    return 0
end

return wms_import