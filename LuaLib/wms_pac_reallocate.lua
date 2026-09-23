--[[
    名称: 空料箱呼出算法-重新呼出空料箱格
    作者：HAN  
    日期：2024-8-5
    修改: 2026-6-18 整理文件头注释

    级别：标准
    
    功能:
         在料箱入库作业中，会出现料格放不下计划入库货品的情况，需要从立库中再呼出料格储藏货品
         在入库的操作界面中一般有 【强制完成】功能按钮，点击后入库任务完成
         并且根据入库货品的情况重新分配料格继续入库

    算法基本构想:
        1# 首先判断当前正在站台入库的料箱是否有合适的料格，如果有优先考虑
        2# 从本次入库单呼出的空料格料箱中匹配合适料格
        3# 从立库从新匹配料箱进行出库（+）

 
    【预分配/空料箱呼出】
        Reallocate_EmptyBox — 在入库任务时，操作人员按【强制置满】后处理程序，把没入库的货品在本次入库波次的呼出料箱中安排料格，无法安排则重新呼出空料格

    更改记录:
        2024-8-5   HAN  创建
        2026-6-18              整理文件头注释

    AI CHECK:
        -- 20260618
--]]

wms_base  = require( "wms_base" )

local wms_pac = require( "wms_pac_dmg" )

-- 相同料格的货品数量直接累相加
-- @function add_cell_to_cntr_list
-- @tparam table cntr_list 容器列表
-- @tparam table cell_item 料格信息 
local function add_cell_to_cntr_list( cntr_list, cell_item )
    local find

    for n = 1, #cntr_list do
        if cell_item.cntr_code == cntr_list[n].cntr_code then
            -- 判断是否有相同货品的cell
            find = false
            for m = 1, #cntr_list[n].cell_list do
                if cntr_list[n].cell_list[m].cell_no == cell_item.cell_no then
                    find = true
                    cntr_list[n].cell_list[m].qty = cntr_list[n].cell_list[m].qty + cell_item.qty
                    cntr_list[n].cell_list[m].state = cell_item.state
                    break
                end
            end
            if find == false then
                table.insert( cntr_list[n].cell_list, cell_item )
            end
            return
        end
    end
end

-- 重置容器列表中的空料格列表、重量、货品体积等信息
-- @function reset_cntr_list
-- @tparam table cntr_list 容器列表
local function reset_cntr_list( cntr_list )
    local find
    local cell_no

    for n = 1, #cntr_list do
        -- 判断是否存在空料格
        if cntr_list[n].max_cell_num > #cntr_list[n].cell_list then
            for m = 1, cntr_list[n].max_cell_num do
                cell_no = cntr_list[n].cell_type.."-"..m        -- 料格编码
                find = false
                for i = 1, #cntr_list[n].cell_list do
                    if cntr_list[n].cell_list[i].cell_no == cell_no then
                        find = true
                        break
                    end
                end
                if find == false then
                    local cell_item = {
                        cntr_code =  cntr_list[n].cntr_code,
                        cell_no = cell_no,
                        item_code = "",
                        item_name = "",
                        qty = 0,
                        weight = 0,
                        volume = 0,
                        state = 0,
                        good_volume = 0,                    
                    }
                    table.insert( cntr_list[n].empty_cell_list, cell_item )
                end
            end
        end

        -- 重置重量
        cntr_list[n].weight = 0
        for m = 1, #cntr_list[n].cell_list do
            cntr_list[n].weight = cntr_list[n].weight + (cntr_list[n].cell_list[m].weight*cntr_list[n].cell_list[m].qty) 
        end

        -- 重置料格货品体积
        for m = 1, #cntr_list[n].cell_list do
            cntr_list[n].cell_list[m].good_volume = cntr_list[n].cell_list[m].qty*cntr_list[n].cell_list[m].volume
        end
        cntr_list[n].empty_cell_num = #cntr_list[n].empty_cell_list
    end
end

-- 从容器列表中查找指定容器编码和料格编码的料格
-- @function get_cell_item
-- @tparam table cntr_list 容器列表
-- @tparam string cntr_code 容器编码
-- @tparam string cell_no 料格编码
-- @treturn table cntr 容器对象，未找到返回空字符串
-- @treturn table cell_item 料格对象，未找到返回空字符串
local function get_cell_item( cntr_list, cntr_code, cell_no )

    for n = 1, #cntr_list do
        if cntr_list[n].cntr_code == cntr_code then
            for m = 1, #cntr_list[n].cell_list do
                if cntr_list[n].cell_list[m].cell_no == cell_no then
                    return cntr_list[n], cntr_list[n].cell_list[m]
                end
            end
        end
    end 
    return "",""   
end


--[[
    cntr = {
                pac_no, cntr_code, cell_type, max_cell_num, max_weight,
                cntr_good_weight,weight,
                cell_list = {},
                empty_cell_list = {},
                empty_cell_num
            }
    cell = {
        cntr_code , cell_no, item_code, item_name, item_state, storer,      
        sku = {},          
        qty, weight , volume state, good_volume
    }
--]]
-- 计算料格里能放多少个货品
-- @function calculate_cell_qty
-- @tparam table ctd 容器类型定义
-- @tparam table cntr 容器对象
-- @tparam table cell 料格对象
-- @tparam table item 货品信息
-- @treturn number nRet 0: 成功，非零失败
-- @treturn number Q 料格可装载的货品数量
local function calculate_cell_qty( ctd, cntr, cell, item )
    local Q
    local cntr_cell = {
        cntr_code = cntr.cntr_code,
        cell_no = cell.cell_no,
        qty = cell.qty,
        cell_type = cntr.cell_type,
        good_volume = cell.qty*cell.volume,
        good_weight = cell.qty*cell.weight
    }
    local cntr_good_weight = cntr.cntr_good_weight or 0

    nRet, Q = wms_cntr.Get_CntrCell_Goods_Qty( ctd, cntr_good_weight, cntr_cell, item )
    if nRet ~= 0 then 
        return 1, Q 
    end
    return 0, Q
end

-- 从呼出的料箱里找出适配的空料格，将分配结果加入 new_pac_detail_list
-- @function cell_type_match
-- @tparam table ctd 容器类型定义
-- @tparam string cell_type 料格类型
-- @tparam table cntr_list 容器列表
-- @tparam table item 货品信息（含 alloc_qty, qty 等）
-- @tparam table new_pac_detail_list 新预分配明细列表（出参，会追加分配结果）
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string 错误信息
local function cell_type_match( ctd, cell_type, cntr_list, item, new_pac_detail_list )
    local nRet, Q
    local si_qty = item.qty - item.alloc_qty

    if si_qty == 0 then 
        return 0, "" 
    end

    for n = 1, #cntr_list do
        if cntr_list[n].cell_type == cell_type and cntr_list[n].empty_cell_num > 0 then
            for m = 1, #cntr_list[n].empty_cell_list do
                nRet, Q = calculate_cell_qty( ctd, cntr_list[n], cntr_list[n].empty_cell_list[m], item )
                if nRet ~= 0 then 
                    return 1, Q 
                end
                if Q > 0 then
                    if si_qty > Q then
                        si_qty = Q
                    end                    
                    local pac_detial = {
                        cntr_code = cntr_list[n].cntr_code,
                        cell_no = cntr_list[n].empty_cell_list[m].cell_no,
                        qty = si_qty
                    }
                    table.insert( new_pac_detail_list, pac_detial )
                    item.alloc_qty = item.alloc_qty + si_qty
                end   
                if item.alloc_qty == item.qty then 
                    return 0, "" 
                end             
            end
            if item.alloc_qty == item.qty then break end
        end
    end
    return 0, ""
end

-- 查询并可分配的空料格，将分配结果更新到货品和出库容器列表中
-- @function query_and_alloc_empty_cell
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数 { ctd, dbtype, bs_type, bs_no }
-- @tparam string strTable 联表查询的表信息
-- @tparam string strCondition 查询条件
-- @tparam string cell_type 料格类型
-- @tparam table item 货品信息
-- @tparam table out_cntr_list 出库容器列表（出参）
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string 错误信息
local function query_and_alloc_empty_cell( strLuaDEID, pac_cfg, strTable, strCondition, cell_type, item, out_cntr_list )
    local nRet, strRetInfo
    local strAttrs = "a.S_CNTR_CODE, a.S_CELL_NO, b.F_GOOD_WEIGHT"          -- 查询字段
    local cntr_good_weight, weight, si_qty, volume

    nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 1000, strCondition )
    if nRet ~= 0 then 
        return 2, "查询【容器料格】信息失败! " .. strRetInfo  
    end
    if strRetInfo == '' then
        return 0
    end
    local cntr_cell_attr_set = json.decode(strRetInfo)  
    
    for _, cntr_cell_attr in ipairs( cntr_cell_attr_set ) do
        -- cntr_cell 用于计算数量用
        local cntr_cell = {
            cntr_code = cntr_cell_attr[1],
            cell_no = cntr_cell_attr[2],
            cell_type = cell_type,
            good_volume = 0, good_weight = 0, qty = 0
        }
        cntr_good_weight = lua.Get_NumAttrValue( cntr_cell_attr[3] )

        -- 计算一下料格能分配多少个货品 si_qty
        nRet, si_qty = wms_cntr.Get_CntrCell_Goods_Qty( pac_cfg.ctd, cntr_good_weight, cntr_cell, item )
        if nRet ~= 0 then 
            return 1, si_qty 
        end
        -- 如果计算出来的可存储数量大于 item.qty
        qty = item.qty - item.alloc_qty
        if si_qty > qty then
            si_qty = qty
        end
        -- si_qty 补料数量
        if si_qty > 0 then
            item.alloc_qty = item.alloc_qty + si_qty
            if lua.equation( item.alloc_qty, item.qty) then
                item.ok = true      -- 表示已经全部分配了料箱
            end

            -- 把分配掉的si_qty个货品加到补料呼出的容器里
            weight = lua.Get_NumAttrValue( item.F_WEIGHT )
            volume = lua.Get_NumAttrValue( item.F_VOLUME )

            local cell_item = {
                cntr_code = cntr_cell.cntr_code,
                cell_type = cntr_cell.cell_type,
                cell_no = cntr_cell.cell_no,
                item_code = item.S_ITEM_CODE,
                item_name = item.S_ITEM_NAME,
                row = item.row,
                qty = si_qty,
                sum_volume = si_qty*volume,
                sum_weight = si_qty*weight,
                weight = weight,
                volume = volume,
                sku = item,
                sku_list = {}
            }
            nRet, strRetInfo = wms_pac.put_cell_item_to_out_cntr_list( out_cntr_list, cntr_good_weight, cell_item, item.mixing_rule )
            if nRet ~= 0 then
                return 1, strRetInfo
            end            
            nRet, strRetInfo = wms_cntr.CNTR_cell_alloc_set( strLuaDEID, cntr_cell.cntr_code, cntr_cell.cell_no, pac_cfg.bs_no )
            if nRet ~= 0 then
                return 1, strRetInfo
            end
        end
        if item.ok then
            return 0
        end        
    end
    return 0
end

-- 查询出可以装载 item 的空料格（这些料箱已经有装载货品的），保存到 out_cntr_list
-- @function get_empty_cell
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数 { ctd, dbtype, bs_type, bs_no }
-- @tparam string cell_type 料格类型
-- @tparam string str_loc_where 货位查询条件
-- @tparam table item 货品信息
-- @tparam table out_cntr_list 出库容器列表（出参）
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string 错误信息
local function get_empty_cell( strLuaDEID, pac_cfg, cell_type, str_loc_where, item, out_cntr_list )
    local nRet, strRetInfo
    local mixing_condition = ''

    if lua.StrIsEmpty( cell_type ) then
        return 1, "输入参数中 cell_type 不能为空!"
    end
   
    local strTable = "TN_Container_Cell a LEFT JOIN TN_Container b ON a.S_CNTR_CODE = b.S_CODE "       -- 联表    
    -- 如果有混箱规则，需要把容器中规则定义的属性取值
    if pac_cfg.ctd.have_mixing_rule then
        strTable = strTable.." LEFT JOIN TN_Container_Ext c ON a.S_CNTR_CODE = c.S_CNTR_CODE"
        -- 获取 SKU 的混箱属性
        for _, attr in ipairs( pac_cfg.ctd.mixing_attrs ) do
            mixing_condition = mixing_condition.." AND c."..attr.." = '"..lua.Get_StrAttrValue( item[attr] ).."' "
        end
    end     

    local strCondition
    if pac_cfg.dbtype == DB_TYPE.SQLServer then
        strCondition = " b.S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."' AND b.S_SPEC = '"..cell_type.."' "..
                         " AND a.S_CNTR_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where "..str_loc_where..")) "..
                         " AND a.N_EMPTY_FULL = 0 AND b.N_LOCK_STATE = 0 AND b.C_ENABLE = 'Y' AND b.N_EMPTY_FULL < 2  AND b.C_FORCED_FILL = 'N'"..
                         " AND a.S_STATE <> 'Abnormal'"..mixing_condition
    else
        strCondition = " b.S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."' AND b.S_SPEC = '"..cell_type.."' "..
                         " AND a.S_CNTR_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where "..str_loc_where..")) "..
                         " AND a.N_EMPTY_FULL = 0 AND b.N_LOCK_STATE = 0 AND b.C_ENABLE = 'Y' AND b.N_EMPTY_FULL < 2  AND b.C_FORCED_FILL = 'N'"..
                         " AND a.S_STATE <> 'Abnormal'"..mixing_condition
    end        
    -- 如果要控制料箱总的载重
    if pac_cfg.ctd.check_capacity then
        strCondition = strCondition.." AND b.F_GOOD_WEIGHT < "..pac_cfg.ctd.load_capacity
    end
    nRet, strRetInfo = query_and_alloc_empty_cell( strLuaDEID, pac_cfg, strTable, strCondition, cell_type, item, out_cntr_list )
    if nRet ~= 0 then
        return nRet, strRetInfo
    end
    return 0
end

-- 查询可以装载 item 货品的全空料箱，保存到 out_cntr_list
-- @function get_empty_cntr
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数 { ctd, dbtype, bs_type, bs_no }
-- @tparam string cell_type 料格类型
-- @tparam string str_loc_where 货位查询条件
-- @tparam table item 货品信息
-- @tparam table out_cntr_list 出库容器列表（出参）
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string 错误信息
local function get_empty_cntr( strLuaDEID, pac_cfg, cell_type, str_loc_where, item, out_cntr_list )
    local nRet, strRetInfo

    if lua.StrIsEmpty( cell_type ) then
        return 1, "输入参数中 cell_type 不能为空!"
    end
    local strTable = "TN_Container_Cell a LEFT JOIN TN_Container b ON a.S_CNTR_CODE = b.S_CODE "       -- 联表
    local strCondition
    if pac_cfg.dbtype == DB_TYPE.SQLServer then
        strCondition = " b.S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."' AND b.S_SPEC = '"..cell_type.."' "..
                         " AND a.S_CNTR_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where "..str_loc_where..")) "..
                         " AND a.N_EMPTY_FULL = 0 AND b.N_LOCK_STATE = 0 AND b.C_ENABLE = 'Y' AND b.N_EMPTY_FULL = 0 AND b.C_FORCED_FILL = 'N'"..
                         " AND a.S_STATE <> 'Abnormal'"
    else
        strCondition = " b.S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."' AND b.S_SPEC = '"..cell_type.."' "..
                         " AND a.S_CNTR_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where "..str_loc_where..")) "..
                         " AND a.N_EMPTY_FULL = 0 AND b.N_LOCK_STATE = 0 AND b.C_ENABLE = 'Y' AND b.N_EMPTY_FULL = 0  AND b.C_FORCED_FILL = 'N'"..
                         " AND a.S_STATE <> 'Abnormal'"
    end        

    nRet, strRetInfo = query_and_alloc_empty_cell( strLuaDEID, pac_cfg, strTable, strCondition, cell_type, item, out_cntr_list )
    if nRet ~= 0 then
        return nRet, strRetInfo
    end
    return 0
end

-- 呼出一个货品入库所需的料箱，入库数量一般较小，因此处理比 JX_EmptyBoxCellOutPlan 简单
-- @function emptyboxcell_out_byonegoods
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数 { ctd, dbtype, bs_type, bs_no, station, wh_code, area_code, factory, cntr_out_op_def, cntr_back_op_def }
-- @tparam table item 货品信息 { cell_type, qty, weight, volume, alloc_qty, ok 等 }
-- @treturn number nRet 0: 成功，1: 没有找到空料格，2: 错误
-- @treturn string 错误信息
local function emptyboxcell_out_byonegoods( strLuaDEID, pac_cfg, item )
    local nRet, strRetInfo

    if pac_cfg == nil or type(pac_cfg) ~= "table" then
        return 2, "emptyboxcell_out_byonegoods 输入参数非法 pac_cfg 必须有值!, 必须是 table 类型"
    end 
    local bs_type = lua.Get_StrAttrValue( pac_cfg.bs_type )
    local bs_no = lua.Get_StrAttrValue( pac_cfg.bs_no )
    local station = lua.Get_StrAttrValue( pac_cfg.station )
    local wh_code = lua.Get_StrAttrValue( pac_cfg.wh_code )
    local area_code = lua.Get_StrAttrValue( pac_cfg.area_code )
    local cell_type = lua.Get_StrAttrValue( item.cell_type )
    local factory = pac_cfg.factory or ''

    if bs_type == '' or bs_no == '' then
        return 2, "emptyboxcell_out_byonegoods 输入参数 pac_cfg 非法 pac_cfg.bs_type, pac_cfg.bs_no 必须有值,必须是字符串" 
    end
    if station == '' then
        return 2, "emptyboxcell_out_byonegoods 输入参数 pac_cfg 非法 pac_cfg.station 必须有值,必须是字符串" 
    end 
    if cell_type == '' then
        return 2, "emptyboxcell_out_byonegoods 输入参数 item 非法item.cell_type 必须有值,必须是字符串" 
    end  
    if wh_code == '' then
        return 2, "emptyboxcell_out_byonegoods 输入参数 pac_cfg 非法 pac_cfg.wh_code 必须有值,必须是字符串" 
    end   
    if factory == '' then
        return 2, "emptyboxcell_out_byonegoods 输入参数 pac_cfg 非法 pac_cfg.factory 必须有值,必须是字符串" 
    end   

    -- step1 数据准备，根据货品的体积确定呼出那种类型的料格料箱
    local out_cntr_list = {}
    local str_loc_where = "C_ENABLE = 'Y' AND S_WH_CODE = '"..wh_code.."'"
    if area_code ~= '' then
        str_loc_where = str_loc_where.." AND S_AREA_CODE = '"..area_code.."'"
    end    
    local cell_type_count
    if pac_cfg.ctd.ecda_rule == "Flex match" then  
        local goods_volume = item.qty * item.volume
        local goods_weight = item.qty * item.weight
        local match_cell_type = ''          -- 需要呼出的料格类型

        for _, box_def_item in ipairs( pac_cfg.ctd.grid_box_def) do
            if goods_volume <= box_def_item.volume then
                match_cell_type = box_def_item.cell_type
                break
            end
        end
        if match_cell_type == '' then
            return 2, "追加空料箱呼出的货品总体积过大(>72000), emptyboxcell_out_byonegoods 函数不适合，请检讨业务流程!"
        end
        if item.cell_type < match_cell_type then
            match_cell_type = item.cell_type
        end

        cell_type_count = ( string.byte(match_cell_type) - string.byte('A') + 1 )    -- 料格类型匹配次数
          -- 先从最适配的料格找空料格，没有升格
        for n = 1, cell_type_count do    
            nRet, strRetInfo = get_empty_cell( strLuaDEID, pac_cfg, match_cell_type, str_loc_where, item, out_cntr_list )
            if nRet ~= 0 then
                return 2, "呼出空料箱算法出错!"..strRetInfo
            end
            if item.ok then 
                break 
            end
            -- 升格
            match_cell_type = lua.DecrementChar(match_cell_type)
        end
        if not item.ok then
            for n = 1, cell_type_count do    
                nRet, strRetInfo = get_empty_cntr( strLuaDEID, pac_cfg, match_cell_type, str_loc_where, item, out_cntr_list )
                if nRet ~= 0 then
                    return 2, "呼出空料箱算法出错!"..strRetInfo
                end
                if item.ok then 
                    break 
                end
                -- 升格
                match_cell_type = lua.DecrementChar(match_cell_type)
            end
        end
        
    elseif pac_cfg.ctd.ecda_rule == "SDM Grid" then 
        -- 料格类型恒定，不会产生升格
        nRet, strRetInfo = get_empty_cell( strLuaDEID, pac_cfg, item.cell_type, str_loc_where, item, out_cntr_list )
        if nRet ~= 0 then
            return 2, "呼出空料箱算法出错!"..strRetInfo
        end 
        -- 如果还是没有完全转载，呼出全空料箱
        if not item.ok then   
            nRet, strRetInfo = get_empty_cntr( strLuaDEID, pac_cfg, item.cell_type, str_loc_where, item, out_cntr_list )
            if nRet ~= 0 then
                return 2, "呼出空料箱算法出错!"..strRetInfo
            end            
        end    
    end

    if lua.isTableEmpty( out_cntr_list ) then
        return 1, "没有找到空料箱2"
    end    
    
    local item_base_attr_count = #ITEM_BASE_ATTRS
    local udf_attr_count = #UDF_ATTRS

    for _, out_cntr in ipairs( out_cntr_list ) do
        -- step3 创建预分配容器及组盘容器明细
        local pac = m3.AllocObject( strLuaDEID, "Pre_Alloc_Container" )
        pac.cntr_code = out_cntr.cntr_code
        pac.bs_type = bs_type
        pac.bs_no = bs_no
        pac.station = station
        pac.factory = factory
        pac.out_op_name = pac_cfg.cntr_out_op_def
        pac.back_op_name = pac_cfg.cntr_back_op_def
        
        nRet, pac = m3.CreateDataObj(strLuaDEID, pac)
        if nRet ~= 0 then
            return 2, "创建【组盘容器】失败!"..pac 
        end   

        for _, cell in ipairs( out_cntr.cell_list ) do
            nRet, strRetInfo = wms_cntr.CNTR_cell_alloc_set( strLuaDEID, out_cntr.cntr_code, cell.cell_no, bs_no ) 
            if nRet ~= 0 then
                return 2, "wms_cntr.CNTR_cell_alloc_set 失败!"..strRetInfo
            end

            local pac_detail_data = m3.AllocObject2( strLuaDEID, "Pre_Alloc_CNTR_Detail" )
            if pac_detail_data == nil then
                return 2, "创建【预分配容器明细】失败!"
            end
            for m = 1, item_base_attr_count do
                pac_detail_data[ITEM_BASE_ATTRS[m]] = item[ITEM_BASE_ATTRS[m]]
            end
            for m = 1, udf_attr_count do
                pac_detail_data[UDF_ATTRS[m]] = item[UDF_ATTRS[m]]
            end

            pac_detail_data.S_PAC_NO = pac.pac_no
            pac_detail_data.S_CNTR_CODE = out_cntr.cntr_code
            pac_detail_data.S_STATION_NO = station
            pac_detail_data.S_CELL_NO = cell.cell_no
            pac_detail_data.F_QTY = cell.qty
            pac_detail_data.S_BS_TYPE = bs_type
            pac_detail_data.S_BS_NO = bs_no
            pac_detail_data.N_BS_ROW_NO = item.N_BS_ROW_NO

            nRet, pac_detail_data = m3.CreateDataObj2(strLuaDEID, pac_detail_data)
            if nRet ~= 0 then 
                return 2, "创建【预分配容器明细】失败!"..pac_detail_data 
            end   
        end

        -- step4 创建作业  
        local add_wfp = {
            wfp_type = 1,
            cls = "Pre_Alloc_Container",
            obj_id = pac.id,
            obj_name = "预分配料箱流水号'"..pac.pac_no.."'-->创建作业",
            trigger_event = "后台创建空料箱出库作业"
        }
        nRet, strRetInfo = m3.AddSysWFP( strLuaDEID, add_wfp )
        if nRet ~= 0 then 
            lua.Error( strLuaDEID, debug.getinfo(1), "AddSysWFP失败!"..strRetInfo )  
        end   
    end
    return 0
end

--[[
    Reallocate_EmptyBox -- 在入库任务时，操作人员按【强制置满】后处理程序，需要把没入库的货品在本次入库波次的呼出料箱中安排料格
                              如果无法安排从新呼出一个空料格
    输入参数: pac_cfg = {
            {
                wh_code, area_code  仓库，库区编码
                factory
                station 站台
                aisle -- 可用巷道
                bs_type 来源类型：入库单、入库波次
                bs_no 来源单号   
                cntr_out_op_def = "料箱出库",           --空料箱出库的作业定义
                cntr_back_op_def = "货品入库"           --料箱回库的主业定义  
            }                

            item 需要入库的货品
            {
                item_code = "04005740",
                item_state = "AVL",
                storer = "",
                item_name = "【SD-34538】世达_3/4寸系列六角风动套筒50MM/[1支]",
                weight = 1.1,
                volume = 722,
                cell_type = "E",
                qty = 10,           -- 需要料格的货品数量
                alloc_qty = 0
                S_STORE, S_ITEM_CODE, ...
            }
            cur_cntr_code -- 当前正在作业的容器（需要特别对待）
    算法逻辑:
    -- 1 找出该入库波次所有未完成入库的 组盘容器，检查一下是否有相同货品的料格，有是否可以放下，能放多少个
    -- 2 找后续的未执行的 预分配容器 是否有空料格
    -- 3 前面几步都没有满足的料格，分配一个新的空料箱
]]

-- 在入库任务时，操作人员按【强制置满】后处理程序，把没入库的货品在本次入库波次的呼出料箱中安排料格，无法安排则重新呼出空料格
-- @function wms_pac.Reallocate_EmptyBox
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数
-- @tparam table item 需要入库的货品 
-- @tparam string cur_cntr_code 当前正在作业的容器编码
-- @treturn number nRet 0: 成功，非零失败
-- @treturn boolean/string 成功返回 refrush_cur_page（是否需要刷新当前页面），失败返回错误信息
function wms_pac.Reallocate_EmptyBox( strLuaDEID, pac_cfg, item, cur_cntr_code )
    local nRet, strRetInfo
    local strCondition
    local data_objs
    local refrush_cur_page = false      -- 如果有新增的任务在当前在作业的容器需要刷新当前的页面

    if pac_cfg == nil or type(pac_cfg) ~= "table" then
        return 1, "wms_pac.Reallocate_EmptyBox 输入参数非法 pac_cfg 必须有值!, 必须是 table 类型"
    end 
    local bs_type = pac_cfg.bs_type
    local bs_no = pac_cfg.bs_no
    local station = pac_cfg.station

    local lua_info
    nRet, lua_info = lua.GetLuaDEInfo( strLuaDEID )
    if nRet ~= 0 then
        return 2, "GetLuaDEInfo 失败!"..lua_info
    end
    pac_cfg.dbtype = lua_info.dbtype

    if lua.StrIsEmpty( bs_type ) or lua.StrIsEmpty( bs_no ) then
        return 1, "wms_pac.Reallocate_EmptyBox 输入参数 pac_cfg 非法 bs_type, bs_no 必须有值,必须是字符串" 
    end
    if lua.StrIsEmpty( cur_cntr_code ) then
        return 1, "wms_pac.Reallocate_EmptyBox 输入参数非法 cur_cntr_code 必须有值,必须是字符串" 
    end
    if lua.StrIsEmpty( station ) then
        return 1, "wms_pac.Reallocate_EmptyBox 输入参数 pac_cfg 非法 station 必须有值,必须是字符串" 
    end   
    
    local item_base_attr_count = #ITEM_BASE_ATTRS
    local udf_attr_count = #UDF_ATTRS    

    -- 获取容器类型定义
    local container
    nRet, container = wms_cntr.GetInfo( strLuaDEID, cur_cntr_code )
    if nRet ~= 0 then 
        return 2, "获取【容器】信息失败! " .. container 
    end 

    local ctd       -- 容器类型定义
    nRet, ctd = wms_cntr.GetCTDInfo( container.ctd_code )
    if nRet ~= 0 then
        return 2, ctd
    end 
    pac_cfg.ctd = ctd

    -- 获取补料料格匹配数据
    local si_match_attrs = ctd.si_match_attrs or {}
    -- 匹配属性要加上 S_ITEM_CODE, S_STRORER, S_ITEM_STATE
    table.insert( si_match_attrs, "S_STORER" )
    table.insert( si_match_attrs, "S_ITEM_CODE" )
    table.insert( si_match_attrs, "S_ITEM_STATE" )    

    -- step1 算法依赖的基础数据cntr_list 本入库波次呼出的未完成入库的料箱列表
    --       查询出入库波次中未完成的 预分配容器 并且获取这些容器的CG_Detail （+预分配容器明细），需要判断料箱的重量
    --       判断是否可以继续入货品
    local strTable = "TN_Pre_Alloc_Container a LEFT JOIN TN_Container b ON a.S_CNTR_CODE = b.S_CODE" 
    -- 要查询的属性
    local strAttrs = "b.S_CODE, b.F_MAX_WEIGHT, b.N_MAX_CELL_NUM, b.S_SPEC, a.S_PAC_NO, b.F_GOOD_WEIGHT" 
    -- 2 Arrive_Station/到入库口 
    strCondition = "a.S_BS_TYPE = '"..bs_type.."' AND a.S_BS_NO = '"..bs_no.."' AND a.N_B_STATE <= 2 "
    nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 1000, strCondition )
    if nRet ~= 0 then 
        return 2, "QueryDataObject失败!"..strRetInfo 
    end

    local inv_detail, cntr_code, max_weight, cell_type, max_cell_num
    local cntr_code_set = {}
    local cntr_list = {}
    local pac_detail    
    local strUpdateSql
    local same_item_list = {}        -- 相同货品的料格
    local same_item_count
    local cntr, Q
    local new_pac_detail_list = {}         -- 新增加的呼出入库任务
    local cell_type_count, cntr_good_weight
    local call_empty_box = false           -- 是否需要重新呼出空料箱（替代goto标签）

    if strRetInfo ~= '' then 
        local ret_attr = json.decode(strRetInfo)

        for n = 1, #ret_attr do
            cntr_code = ret_attr[n][1]
            max_weight = lua.Get_NumAttrValue( ret_attr[n][2] )
            max_cell_num = lua.Get_NumAttrValue( ret_attr[n][3] )
            cell_type = lua.Get_StrAttrValue( ret_attr[n][4] )
            cntr_good_weight = lua.Get_NumAttrValue( ret_attr[n][6] )

            table.insert( cntr_code_set, cntr_code )  
            local cntr_item = {
                pac_no = lua.Get_StrAttrValue( ret_attr[n][5] ),
                cntr_code = cntr_code,
                cell_type = cell_type,
                max_cell_num = max_cell_num,
                max_weight = max_weight,
                cntr_good_weight = cntr_good_weight,
                weight = 0,
                cell_list = {},
                empty_cell_list = {},
                empty_cell_num = 0
            }
            table.insert( cntr_list, cntr_item )  
        end
    else
        -- 重新呼叫空料箱
        -- goto call_empty_box_out
        call_empty_box = true
    end
    
    if not call_empty_box then
        -- 查询未完成的组盘容器中的货品明细 INV_Detail 加入cntr_list, 主要是用来计算重量
        strCondition = "S_CNTR_CODE IN ("..lua.strArray2string( cntr_code_set )..")"
        nRet, data_objs = m3.QueryDataObject(strLuaDEID, "INV_Detail", strCondition, "S_CNTR_CODE" )
        if nRet ~= 0 then 
            return 2, "QueryDataObject失败!"..data_objs 
        end    
        if data_objs ~= '' then 
            for n = 1, #data_objs do
                inv_detail = m3.KeyValueAttrsToObjAttr(data_objs[n].attrs )
                if inv_detail == nil then
                    return 2, "KeyValueAttrsToObjAttr失败!" 
                end
                local cell_item = {
                    cntr_code =  inv_detail.S_CNTR_CODE,
                    cell_no = inv_detail.S_CELL_NO,
                    item_code = inv_detail.S_ITEM_CODE,
                    item_name = inv_detail.S_ITEM_NAME,
                    item_state = inv_detail.S_ITEM_STATE,
                    storer = inv_detail.S_STORER,
                    sku = inv_detail,
                    pac_detail_id = '',
                    qty = lua.Get_NumAttrValue( inv_detail.F_QTY ),
                    weight = lua.Get_NumAttrValue( inv_detail.F_WEIGHT ),
                    volume = lua.Get_NumAttrValue( inv_detail.F_VOLUME ),
                    good_volume = 0,
                    state = 0
                }
                add_cell_to_cntr_list( cntr_list, cell_item )
            end        
        end

        -- 把预分配容器明细也加入 cntr_list 这样方便算重量
        strCondition = "S_BS_TYPE = '"..bs_type.."' AND S_BS_NO = '"..bs_no.."' AND S_CNTR_CODE IN ("..lua.strArray2string( cntr_code_set )..")"
        nRet, data_objs = m3.QueryDataObject(strLuaDEID, "Pre_Alloc_CNTR_Detail", strCondition )
        if nRet ~= 0 then 
            return 2, "QueryDataObject失败!"..data_objs 
        end
        if data_objs ~= '' then 
            for n = 1, #data_objs do
                pac_detail = m3.KeyValueAttrsToObjAttr(data_objs[n].attrs)
                if pac_detail == nil then
                    return 2, "KeyValueAttrsToObjAttr失败!" 
                end
                pac_detail.id = data_objs[n].id
                
                local cell_item = {
                    cntr_code =  pac_detail.S_CNTR_CODE,
                    cell_no = pac_detail.S_CELL_NO,
                    item_code = pac_detail.S_ITEM_CODE,
                    item_name = pac_detail.S_ITEM_NAME,
                    item_state = pac_detail.S_ITEM_STATE,
                    storer = pac_detail.S_STORER,      
                    sku = pac_detail,    
                    pac_detail_id = pac_detail.id,
                    qty = lua.Get_NumAttrValue( pac_detail.F_QTY ),
                    weight = lua.Get_NumAttrValue( pac_detail.F_WEIGHT ),
                    volume = lua.Get_NumAttrValue( pac_detail.F_VOLUME ),
                    state = lua.Get_NumAttrValue( pac_detail.N_B_STATE ),
                    good_volume = 0
                }
                add_cell_to_cntr_list( cntr_list, cell_item )   
                -- 把预分配容器明细中未执行（cell_item.state < 2）且货品和当前要补料的货品相同的加入 same_item_list
                if cell_item.state < 2 and wms_base.SKU_Match( si_match_attrs, item, pac_detail ) then
                    -- MDF BY HAN @20260714
                    -- 判断一下料格的状态，强制置满是否为N ，如果是N可以用这个料格补料
                    local nRet, cntr_cell = wms_cntr.Get_Container_Cell_Data( strLuaDEID, cell_item.cntr_code, cell_item.cell_no )
                    if nRet ~= 0 then
                        return 2, "wms_cntr.Get_Container_Cell_Data 失败!" .. cntr_cell
                    end
                    if cntr_cell.C_FORCED_FILL == 'N' then
                        table.insert( same_item_list, cell_item )
                    end
                end   
            end
        end

        -- 生成cntr_list 中的 empty_cell_list (这些地方是可以放货品的), 重置容器重量
        reset_cntr_list( cntr_list )
    
        -- step2 找出  cntr_list 中是否有可装载本次多余货品数量的料格，并计算出能放下多少个
        local cell_item
        same_item_count = #same_item_list
        if same_item_count > 0 then 
            -- step2.1 先从当前正在作业的料箱中找是否存在相同货品的料格，如果有是最优解
            for n = 1, same_item_count do   
                if item.alloc_qty == item.qty then break end
                if same_item_list[n].cntr_code == cur_cntr_code then
                    -- 当前作业的料箱有料格可以装载
                    cntr, cell_item = get_cell_item( cntr_list, cur_cntr_code, same_item_list[n].cell_no )
                    if cntr ~= '' then
                        -- 计算 cee_iten 可以分配的数量 Q
                        nRet, Q = calculate_cell_qty( ctd, cntr, cell_item, item )
                        if nRet ~= 0 then 
                            return 1, Q 
                        end
                        if Q > 0 then
                            local si_qty = item.qty - item.alloc_qty
                            if si_qty > Q then
                                si_qty = Q
                            end
                            local pac_detial = {
                                cntr_code = cell_item.cntr_code,
                                cell_no = cell_item.cell_no,
                                qty = si_qty,

                                bs_type = same_item_list[n].sku.S_BS_TYPE,
                                bs_no = same_item_list[n].sku.S_BS_NO,
                                bs_row_no = same_item_list[n].sku.S_BS_ROW_NO,

                            }
                            table.insert( new_pac_detail_list, pac_detial )
                            item.alloc_qty = item.alloc_qty + si_qty
                        end
                    end
                end
            end

            -- step2.2 从后续的入库任务里找有相同货品的料格
            for n = 1, same_item_count do   
                if item.alloc_qty == item.qty then break end
                if same_item_list[n].cntr_code ~= cur_cntr_code then
                    cntr, cell_item = get_cell_item( cntr_list, same_item_list[n].cntr_code, same_item_list[n].cell_no )
                    if cntr ~= '' then
                        -- 计算 cee_iten 可以分配的数量 Q
                        nRet, Q = calculate_cell_qty( ctd, cntr, cell_item, item )
                        if nRet ~= 0 then 
                            return 1, Q 
                        end
                        if Q > 0 then
                            local si_qty = item.qty - item.alloc_qty
                            if si_qty > Q then
                                si_qty = Q
                            end
                            local pac_detial = {
                                cntr_code = cell_item.cntr_code,
                                cell_no = cell_item.cell_no,
                                qty = si_qty,
                                bs_type = same_item_list[n].sku.S_BS_TYPE,
                                bs_no = same_item_list[n].sku.S_BS_NO,
                                bs_row_no = same_item_list[n].sku.S_BS_ROW_NO,                                
                            }
                            table.insert( new_pac_detail_list, pac_detial )
                            item.alloc_qty = item.alloc_qty + si_qty
                        end
                    end
                end
            end
        end

        -- ecda_rule 空料箱格呼出规则
        if ctd.ecda_rule == "Flex match" then 
            -- Flex match 是不固定某种类型的料格
            -- 查看呼出的料箱里是否有空料格可以放下货品, 首先要考虑选 cell_type 一样的，找不到再升级
            cell_type_count = ( string.byte(item.cell_type) - string.byte('A') + 1 )    -- 料格类型匹配次数
            cell_type = item.cell_type

            -- 先从最适配的料格找空料格，没有升格
            for n = 1, cell_type_count do
                cell_type_match( ctd, cell_type, cntr_list, item, new_pac_detail_list )
                if item.alloc_qty == item.qty then 
                    break
                end
                cell_type = lua.DecrementChar(cell_type)
            end
        elseif ctd.ecda_rule == "SDM Grid" then
            -- 指定料格类型
            cell_type_match( ctd, cell_type, cntr_list, item, new_pac_detail_list )
        end

        -- 在现有的呼出料箱里查找是否有空料格可以装载强制完成多出的货品
        for i = 1, #new_pac_detail_list do
            -- 先判断一下是不是在原来呼出的任务里加数量?
            for n = 1, #cntr_list do
                if cntr_list[n].cntr_code == new_pac_detail_list[i].cntr_code then
                    -- 新增 Pre_Alloc_CNTR_Detail
                    local pac_detail = m3.AllocObject2( strLuaDEID, "Pre_Alloc_CNTR_Detail" )
                    if pac_detail == nil then 
                        return 1, "分配【预分配容器明细】失败!" 
                    end
                    for m = 1, item_base_attr_count do
                        pac_detail[ITEM_BASE_ATTRS[m]] = item[ITEM_BASE_ATTRS[m]]
                    end
                    for m = 1, udf_attr_count do
                        pac_detail[UDF_ATTRS[m]] = item[UDF_ATTRS[m]]
                    end

                    pac_detail.S_PAC_NO = cntr_list[n].pac_no
                    pac_detail.S_CNTR_CODE = cntr_list[n].cntr_code
                    pac_detail.S_STATION_NO = station
                    pac_detail.S_CELL_NO = new_pac_detail_list[i].cell_no
                    pac_detail.F_QTY = new_pac_detail_list[i].qty
                    pac_detail.S_BS_TYPE = bs_type
                    pac_detail.S_BS_NO = bs_no
                    pac_detail.N_BS_ROW_NO = item.N_BS_ROW_NO
                    -- 注意状态，如果是当前容器 状态设置为 1 表示执行
                    if pac_detail.S_CNTR_CODE == cur_cntr_code then
                        pac_detail.N_B_STATE = 1
                        refrush_cur_page = true
                    end

                    nRet, pac_detail = m3.CreateDataObj2( strLuaDEID, pac_detail )
                    if nRet ~= 0 then 
                        return 1, "创建【预分配容器明细】失败!"..pac_detail 
                    end  
                    -- 料格的状态设置为 预分配
                    wms_cntr.CNTR_cell_alloc_set( strLuaDEID, cntr_list[n].cntr_code, new_pac_detail_list[i].cell_no, bs_no )
                end
            end
        end
        if item.alloc_qty == item.qty then 
            return 0, refrush_cur_page 
        end
    end

    --  step3 重新呼出空料箱
    item.qty = item.qty - item.alloc_qty
    item.alloc_qty = 0
    item.ok = false
    nRet, strRetInfo = emptyboxcell_out_byonegoods( strLuaDEID, pac_cfg, item )
    if nRet ~= 0 then
        return nRet, strRetInfo
    end
    return 0, refrush_cur_page
end

return wms_pac