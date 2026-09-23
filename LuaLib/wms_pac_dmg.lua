--[[
    版本：     Version 1.0
    创建日期： 2025-4-20
    修改日期:  2026-6-18
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    功能：
        在处理入库作业时，将入库单明细中的货品预先分配到具体容器料格的过程在WMS系统里叫 预分配容器
        一般用在料箱库，空料箱有多种规格，根据货品中的设置呼出适配的料格

        supplement_cntr_list 和 out_cntr_list 的数据结构是一样的，如下
         {
            cntr_code:"xxx"
            cell_type:"A/B/C/D/E"
            cntr_good_weight: 100                        -- 容器中货品重量
            full: false/true,
            empty_cell_num: 0,
            empty_cell_list:[{"cell_no"，item_code, item_state, storer, item_name}]           -- 呼出的补料料箱中的空料格 cell 属性同下面的 cell_list
            cell_list:{
                { cntr_code:"", cell_no:"", item_code:"xx", item_name:"", wms_bn:"SN01", weight, volume, qty:10 ,sum_volume:10, sum_weight:10}
            }
        }

    【容器预分配】                
        set_out_cntr_empty_cell              — 查询并设置呼出容器列表中的空料格信息（空的 Container_Cell）
        Get_ItemList_GroupBy_CntrType        — 获取入库单/入库波次中需要入库的物料信息，并根据容器类型进行分组
        put_cell_item_to_out_cntr_list       — 将分配好的料格货品 cell_item 加入呼出容器列表 out_cntr_list
        set_replenishment_cntr_emptycell     — 遍历补料呼出料箱，查询并设置空料格列表，判断是否可用于预分配
        sku_complies_with_mixing_rule        — 检查 SKU 货品是否符合料箱的混箱规则
        reset_empty_cell_info                — 清理容器列表中的空料格信息，移除已分配货品的料格
        pre_alloc_sku_to_out_cntr            — 计算在容器 out_cntr 里预分配 SKU 货品的数量
        get_replenishment_cntr_list          — 获取补料容器料格列表，查询仓库中已存有货品且未满的料格
        Pre_Alloc_Cntr_DMG                   — 料箱预分配主函数（DMG算法），根据SKU的S_CELL_TYPE确定料箱格和最大转载数量

    更改记录:
        2025-4-20  HAN  创建
        2026-6-18  HAN  为所有函数添加文档注释，整理导出函数清单

    AI CHECK:
        -- 20260618
--]]
wms_cntr = require ("wms_container")
wms_wh = require ("wms_wh")

local wms_pac = {_version = "0.1.1"}

local BOX_MAX_WEIGHT = 0
local CHECK_CAPACITY = false         -- 是否检查超重

-- 需要查询的物料货品属性，一般用在 明细表 中如入库单明细，出库单明细
local DETAIL_ATTRS = {
                    "S_STORER", "S_ITEM_CODE", "S_ITEM_NAME", "S_ITEM_STATE", "S_BATCH_NO","S_SERIAL_NO", "S_WMS_BN",
                    "D_PRD_DATE", "D_EXP_DATE", "S_OWNER", "S_SUPPLIER_NO", "N_ROW_NO","F_QTY",
                    "S_UDF01", "S_UDF02", "S_UDF03", "S_UDF04", "S_UDF05", "S_UDF06", "S_UDF07", "S_UDF08", "S_UDF09", "S_UDF10",
                    "S_UDF11", "S_UDF12", "S_UDF13", "S_UDF14", "S_UDF15", "S_UDF16", "S_UDF17", "S_UDF18", "S_UDF19", "S_UDF20"
                    }
local SKU_ATTRS = { 
                    "F_WEIGHT","F_VOLUME","S_CTD_CODE", "S_CELL_TYPE", "S_AVL_SPEC", "S_ABCTYPE", "N_LOADING_LIMIT", 
                    "F_LOAD_CAPACITY","S_COUNT_METHOD","S_SKU_GRID_PARM","F_SCU"
                  }

-- 查询并设置呼出容器列表中的空料格信息（空的 Container_Cell）
-- @function wms_pac.set_out_cntr_empty_cell
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table out_cntr_list 呼出容器列表，每个元素包含 cntr_code, cntr_good_weight, cell_type, empty_cell_list 等字段
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string/table errMsg 失败时返回错误信息
function wms_pac.set_out_cntr_empty_cell( strLuaDEID, out_cntr_list )
    local nRet, strCondition, strOrder
    local cntr_cell_objs, cell_attr

    for n = 1, #out_cntr_list do
        strCondition = "S_CNTR_CODE = '"..out_cntr_list[n].cntr_code.."' AND N_EMPTY_FULL = 0"
        strOrder = "S_CELL_NO"
        nRet, cntr_cell_objs = m3.QueryDataObject(strLuaDEID, "Container_Cell", strCondition, strOrder )
        if nRet ~= 0 then
            return 1, cntr_cell_objs
        end
        
        if cntr_cell_objs ~= '' then
            for m = 1, #cntr_cell_objs do
                cell_attr = m3.KeyValueAttrsToObjAttr(cntr_cell_objs[m].attrs)
                if cell_attr == nil then
                    return 1, "KeyValueAttrsToObjAttr 失败!"
                end
                local empty_cell = {
                    cntr_code = out_cntr_list[n].cntr_code,
                    cell_no = cell_attr.S_CELL_NO,
                    item_code = "",
                    item_name = "",
                    entry_batch_no = "",
                    qty = 0, sum_volume = 0, sum_weight = 0
                }
                table.insert( out_cntr_list[n].empty_cell_list, empty_cell )
            end
        end
    end 
    return 0 
end                  
--[[
    获取入库单，入库波次中需要入库的物料信息，并且根据容器类型进行区分
    输入参数:
        paramter -- 预分配料箱配置参数
                {
                    wh_code, area_code  仓库，库区编码
                    station 站台
                    bs_type 来源类型：入库单、入库波次
                    bs_no 来源单号  
                    ctd_code 容器类型编码(来源入库单，入库波次)
                } 
    返回:ctd_list = {
            {ctd_code="CTD-003"，item_list={..}},
            ...
    }
--]]
-- 获取入库单/入库波次中需要入库的物料信息，并根据容器类型进行分组
-- @function wms_pac.Get_ItemList_GroupBy_CntrType
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table paramter 预分配料箱配置参数
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table/string ctd_list 成功时返回按容器类型分组的货品列表，失败时返回错误信息
function wms_pac.Get_ItemList_GroupBy_CntrType( strLuaDEID, paramter )
    local nRet, strRetInfo, n, isOk
    -- 输入参数合法性检查
    isOk, strRetInfo = wms_base.PreAllocCntr_CFG_Check( paramter )
    if not isOk then
        return 1, strRetInfo
    end

    -- 获取入库货品明细 item_lis， 这个货品列表要根据容器类型进行区分，因此保存在 ctd_list
    -- { {ctd_code="", item_lits = {} },... }
    -- 确定要联表查询的表和条件
    local strTable, strCondition
    local condition = ""
    local cls_id = ''
    local paramter_ctd_code = paramter.ctd_code or ''

    if paramter.bs_type == "Inbound_Order" then
        strTable = "TN_Inbound_Detail a LEFT JOIN TN_SKU b ON ( a.S_ITEM_CODE = b.S_ITEM_CODE and a.S_STORER = b.S_STORER )" 
        strCondition = "a.S_IO_NO = '"..paramter.bs_no.."'"
        condition = "S_IO_NO = '"..paramter.bs_no.."'"
        cls_id = "Inbound_Detail"
    elseif paramter.bs_type == "Inbound_Wave" then
        strTable = "TN_IW_Detail a LEFT JOIN TN_SKU b ON ( a.S_ITEM_CODE = b.S_ITEM_CODE and a.S_STORER = b.S_STORER )" 
        strCondition = "a.S_WAVE_NO = '"..paramter.bs_no.."'"
        condition = "S_WAVE_NO = '"..paramter.bs_no.."'"
        cls_id = "IW_Detail"
    else
        return 1, "系统目前不支持对数据类 '"..paramter.bs_type.."'进行入库预分配计算!"
    end

    -- 检查一下入库单明细中是否都存在 N_ROW_NO 并且是唯一值，如果不是报错
    local group_attrs = {"N_ROW_NO"}
    local have_duplicate
    nRet, have_duplicate = lua.Have_Duplicates_Data( strLuaDEID, cls_id, group_attrs, condition )
    if nRet ~= 0 then
        return 1, have_duplicate
    end
    if have_duplicate then
        return 1, "编码 = '"..paramter.bs_no.."'的数据类'"..cls_id.."'中存在 N_ROW_NO 相同的记录,系统无法进行预分配计算!"
    end

    -- 要查询的属性
    local detail_attrs_count = #DETAIL_ATTRS
    local sku_attrs_count = #SKU_ATTRS
    local strAttrs = ""
    
    for n = 1, detail_attrs_count do
        strAttrs = strAttrs.."a."..DETAIL_ATTRS[n]..","
    end
    for n = 1, sku_attrs_count do
        strAttrs = strAttrs.."b."..SKU_ATTRS[n]..","
    end    
    strAttrs = lua.trim_laster_char( strAttrs )

   
    local strOrder = "a.N_ROW_NO"
    -- 注意最多只能 2000 条明细, 如果有超过 2000 的记录概要分页查询函数，一般的入库单不会有这么多记录
    nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 2000, strCondition, strOrder )
    if nRet ~= 0 then 
        return 2,"QueryDataObject失败!"..strRetInfo  
    end
    if strRetInfo == '' then 
        return 1, paramter.bs_type.."'"..paramter.bs_no.."'明细为空!"  
    end

    local ret_attr = json.decode(strRetInfo)
    local ctd_list = {}
    local find, success, ctd_code
 
    for n = 1, #ret_attr do
        local item = {}
        for m = 1, detail_attrs_count do
            item[DETAIL_ATTRS[m]] = ret_attr[n][m]
        end
        for m = 1, sku_attrs_count do
            item[SKU_ATTRS[m]] = ret_attr[n][m+detail_attrs_count]
        end
        item.qty = lua.Get_NumAttrValue( item.F_QTY )
        item.volume = lua.Get_NumAttrValue( item.F_VOLUME )
        item.weight = lua.Get_NumAttrValue( item.F_WEIGHT )
        item.row = lua.Get_NumAttrValue( item.N_ROW_NO )
        item.scu = lua.Get_NumAttrValue( item.F_SCU )
        item.alloc_qty = 0
        item.ok = false
        item.cntr_cell_list = {}            -- 预分配的料格列表
        item.sku_grid_parm = ''

        if not lua.StrIsEmpty( item.S_SKU_GRID_PARM ) then
            success, item.sku_grid_parm = pcall( json.decode, item.S_SKU_GRID_PARM )
            if success == false then
                return 1, "SKU 编码 = '"..item.S_ITEM_CODE.."' 的数据对象中 S_SKU_GRID_PARM 不符合json规范!" 
            end            
        end

        -- 获取SKU的容器定义类型 S_CTD_CODE
        if paramter_ctd_code ~= '' then
            ctd_code = paramter_ctd_code
        else
            ctd_code = item.S_CTD_CODE or ''
            if ctd_code == '' then
                return 1, "编码 = '"..item.S_ITEM_CODE.."' 的SKU没有定义容器类型!"        
            end
        end
        find = false
        if ctd_list ~= nil then
           for i = 1, #ctd_list do
              if ctd_list[i].ctd_code == ctd_code then
                  table.insert( ctd_list[i].item_list, item )
                  find = true
                  break
              end
          end
        end
        
        if not find then
            local ctd_item = {
                ctd_code = ctd_code,
                item_list = {item}
            }
            table.insert( ctd_list, ctd_item )
        end
    end
    return 0, ctd_list
end                      

-- 把匹配到的料格 cell_item 加入 呼出料箱容器清单 out_cntr_list
-- cntr_mixing_rule 为补料容器的混箱规则
--[[
        cell_item = {
            cntr_code = cntr_cell.cntr_code,
            cell_type = cntr_cell.cell_type,
            cell_no = cntr_cell.cell_no,
            item_code = item.S_ITEM_CODE,
            item_name = item.S_ITEM_NAME,
            row = item.row,
            wms_bn = "",
            qty = si_qty,
            sum_volume = si_qty*volume,
            sum_weight = si_qty*weight,
            weight = weight,
            volume = volume,
            sku = item
        }
--]]
-- 将分配好的料格货品 cell_item 加入呼出容器列表 out_cntr_list，如容器不存在则新建
-- @function wms_pac.put_cell_item_to_out_cntr_list
-- @tparam table out_cntr_list 呼出容器列表
-- @tparam number cntr_good_weight 容器已有货品重量
-- @tparam table cell_item 分配的料格货品信息，
-- @tparam table cntr_mixing_rule 容器混箱规则属性（可为 nil）
-- @treturn number nRet 0: 成功
function wms_pac.put_cell_item_to_out_cntr_list( out_cntr_list, cntr_good_weight, cell_item, cntr_mixing_rule )
    if cntr_mixing_rule == nil then
        cntr_mixing_rule = {}
    end
    for n = 1, #out_cntr_list do
        if out_cntr_list[n].cntr_code == cell_item.cntr_code then
            table.insert( out_cntr_list[n].cell_list, cell_item )
            -- 容器中商品的总重量需要加上岗加入到料格里的货品重量
            out_cntr_list[n].cntr_good_weight = out_cntr_list[n].cntr_good_weight + cell_item.sum_weight
            return 0
        end
    end

    local out_cntr = {}
    out_cntr = {
        cntr_code = cell_item.cntr_code,
        cell_type = cell_item.cell_type,
        full = false,
        cntr_mixing_rule = cntr_mixing_rule,        -- 和混箱策略相关的属性值
        empty_cell_list = {},
        cntr_good_weight = cntr_good_weight + cell_item.sum_weight,
        cell_list = {}
    }

    table.insert( out_cntr.cell_list, cell_item )
    table.insert( out_cntr_list, out_cntr )
    return 0
end

-- 遍历补料呼出料箱，查询并设置空料格列表（empty_cell_list），判断是否可以用补料箱进行预分配
-- @function wms_pac.set_replenishment_cntr_emptycell
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table supplement_cntr_list 补料呼出料箱列表
-- @treturn number nRet 0: 成功，1/2: 失败
-- @treturn boolean/string have_empty_cell 成功时返回是否有空料格，失败时返回错误信息
function wms_pac.set_replenishment_cntr_emptycell( strLuaDEID, supplement_cntr_list )
    local nRet, strCondition, strOrder
    local data_objects
    local cell
    local have_empty_cell = false

    strOrder = "S_CELL_NO"
    for n = 1, #supplement_cntr_list do
        -- 空料格
        strCondition = "S_CNTR_CODE = '"..supplement_cntr_list[n].cntr_code.."' AND N_EMPTY_FULL = 0"
        nRet, data_objects = m3.QueryDataObject(strLuaDEID, "Container_Cell", strCondition, strOrder )
        if nRet ~= 0 then
            return 2, "QueryDataObject失败!"..data_objects
        end
        if data_objects ~= '' then 
            for m = 1, #data_objects do
                cell = m3.KeyValueAttrsToObjAttr(data_objects[m].attrs)
                if cell == nil then
                    return 1, "KeyValueAttrsToObjAttr 失败"
                end
                local empty_cell = {
                    cntr_code = supplement_cntr_list[n].cntr_code,
                    cell_no = cell.S_CELL_NO,
                    item_code = "", item_state = "", storer = "", item_name = "", wms_bn = "",
                    qty = 0, sum_volume = 0, sum_weight = 0
                }
                table.insert( supplement_cntr_list[n].empty_cell_list, empty_cell )
                have_empty_cell = true
            end
        else
            -- 没有空料箱格
            supplement_cntr_list[n].full = true
        end
    end
    return 0, have_empty_cell
end

-- 检查 SKU 货品是否符合料箱的混箱规则（混箱属性值必须一致）
-- @function wms_pac.sku_complies_with_mixing_rule
-- @tparam table ctd 容器类型定义，包含 mixing_attrs 混箱属性列表
-- @tparam table sku 货品属性表
-- @tparam table cntr_mixing_rule 料箱当前的混箱属性值
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn boolean/string result 成功时返回 true(符合) 或 false(不符合)，失败时返回错误信息
function wms_pac.sku_complies_with_mixing_rule ( ctd, sku, cntr_mixing_rule )
    local sku_value, cntr_mixing_rule_value

    if lua.isTableEmpty( cntr_mixing_rule ) then
        return 1, "wms_pac.sku_complies_with_mixing_rule 函数中 cntr_mixing_rule 不合规!"
    end
    for _, attr in ipairs( ctd.mixing_attrs ) do
        sku_value = sku[attr]
        if sku_value == nil then
            return 1, "在判断是否符合混箱规则时，发现 SKU 缺少属性'"..attr.."'"
        end
        cntr_mixing_rule_value = cntr_mixing_rule[attr]
        if cntr_mixing_rule_value == nil then
            return 1, "在判断是否符合混箱规则时，发现 容器扩展属性中 缺少属性'"..attr.."'"
        end    
        if sku_value ~= cntr_mixing_rule_value then
            return 0, false
        end 
    end
    return 0, true
end

-- 清理容器列表中的空料格信息，移除已分配货品的料格（item_code 非空），更新 full 状态
-- @function wms_pac.reset_empty_cell_info
-- @tparam table cntr_list 容器列表
-- @treturn boolean have_empty_cell 是否还存在空料格
function wms_pac.reset_empty_cell_info( cntr_list )
    local empty_cell_list
    local have_empty_cell = false       -- 说明cntr_list是否有空料箱

    for n = 1, #cntr_list do
        empty_cell_list = {}
        for m = 1, #cntr_list[n].empty_cell_list do
            if cntr_list[n].empty_cell_list[m].item_code == '' then
                local empty_cell = {
                    cntr_code = cntr_list[n].empty_cell_list[m].cntr_code,
                    cell_no = cntr_list[n].empty_cell_list[m].cell_no,
                    item_code = "",
                    item_name = "",
                    wms_bn = "",
                    weight = 0, volume = 0,
                    qty = 0, sum_volume = 0, sum_weight = 0
                }                
                table.insert( empty_cell_list, empty_cell )
            end
        end
        cntr_list[n].empty_cell_list = empty_cell_list
        if 0 == #empty_cell_list then
            cntr_list[n].full = true
        else
            have_empty_cell = true
        end
    end
    return have_empty_cell
end

--[[
      计算在容器 out_cntr 里预分配 sku 的数量，注意这个时候的 out_cntr 已经是在呼出容器的队列，比如已经在补料呼出队列，呼出空料箱队列
      ctd -- 容器类型定义
      sku -- 入库商品
      out_cntr = {
            cntr_code:"xxx"
            cell_type:"A/B/C/D/E"
            cntr_good_weight: 100                        -- 容器中货品重量
            full: false/true,
            empty_cell_num: 0,
            empty_cell_list:{{"cell_no"，item_code, item_state, storer, item_name}} -- 空料格
            cell_list:{
                { cntr_code:"", cell_no:"", item_code:"xx", item_name:"", wms_bn:"SN01", weight, volume, qty:10 ,sum_volume:10, sum_weight:10}
            }      
      }
      bs_no -- 入库波次号/入库单号
--]]
-- 计算在容器 out_cntr 里预分配 SKU 货品的数量，将货品分配到容器的空料格中
-- @function wms_pac.pre_alloc_sku_to_out_cntr
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数，包含 ctd(容器类型定义), bs_no(来源单号) 等
-- @tparam table sku 需要分配的货品信息，包含 S_ITEM_CODE, S_CELL_TYPE, qty, alloc_qty, ok 等字段
-- @tparam table out_cntr 呼出容器对象
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string errMsg 失败时返回错误信息
function wms_pac.pre_alloc_sku_to_out_cntr( strLuaDEID, pac_cfg, sku, out_cntr )
    local nRet, Q, strRetInfo
    local match_ok = false
    -- 获取货品的计数方法
    local sku_count_method = lua.Get_StrAttrValue( sku.S_COUNT_METHOD )
    local qty  -- 需要分配料箱格的货品数量

    if sku_count_method == '' then
        return 1, "SKU '"..sku.S_ITEM_CODE.."' 没有定义计数方法 S_COUNT_METHOD"
    end
    --补料料箱不满，且料格规格和SKU设定的料格规格相等
    if not out_cntr.full and out_cntr.cell_type == sku.S_CELL_TYPE then
        if pac_cfg.ctd.have_mixing_rule then
            nRet, match_ok = wms_pac.sku_complies_with_mixing_rule ( pac_cfg.ctd, sku, out_cntr.cntr_mixing_rule )
            if nRet ~= 0 then
                return 1, "wms_pac.sku_complies_with_mixing_rule 时出错! "..match_ok
            end
        else
            match_ok = true                     
        end
    end
    Q = 0
    if match_ok then
        qty = sku.qty - sku.alloc_qty
        local cntr_cell
        -- SKU 找到适配的空料箱格
        for _, empty_cell in ipairs( out_cntr.empty_cell_list ) do
            if empty_cell.item_code == '' then
                cntr_cell = {
                    qty = 0,
                    good_volume = 0,
                    good_weight = 0,
                    cntr_code = empty_cell.cntr_code,
                    cell_no = empty_cell.cell_no,
                    cell_type = out_cntr.cell_type,
                }
                nRet, Q = wms_cntr.Get_CntrCell_Goods_Qty( pac_cfg.ctd, out_cntr.cntr_good_weight, cntr_cell, sku )
                if nRet ~= 0 then
                    return 1, Q
                end
                if Q > 0 then
                    if Q > qty then
                        Q = qty
                    end

                    sku.alloc_qty = sku.alloc_qty + Q
                    qty = qty - Q
                    if lua.equation( sku.alloc_qty, sku.qty ) then
                        sku.ok = true      -- 表示已经全部分配了料箱
                    end

                    -- 把分配掉的si_qty个货品加到补料呼出的容器里
                    local cell_item = {
                        cntr_code = out_cntr.cntr_code,
                        cell_type = out_cntr.cell_type,
                        cell_no = empty_cell.cell_no,
                        item_code = sku.S_ITEM_CODE,
                        item_name = sku.S_ITEM_NAME,
                        row = sku.row,
                        wms_bn = "",
                        qty = Q,
                        sum_volume = Q*sku.volume,
                        sum_weight = Q*sku.weight,
                        weight = sku.weight,
                        volume = sku.volume,
                        sku = sku
                    }
                    empty_cell.item_code = sku.S_ITEM_CODE                -- 说明该空料格已经有分配，需要后面的程序删除
                    table.insert( out_cntr.cell_list, cell_item )
                    out_cntr.cntr_good_weight = out_cntr.cntr_good_weight + cell_item.sum_weight
                    table.insert( sku.cntr_cell_list, cell_item )

                    nRet, strRetInfo = wms_cntr.CNTR_cell_alloc_set( strLuaDEID, cntr_cell.cntr_code, cntr_cell.cell_no, pac_cfg.bs_no )
                    if nRet ~= 0 then
                        return 1, strRetInfo
                    end
                    if sku.ok then
                        break
                    end
                end
            end
        end
    end

    return 0
end

-- SKU 排序函数：按 cell_type 升序，同 cell_type 按需要呼出料格数量 Q 降序
-- @function sku_sort
-- @tparam table sku_a SKU 货品 A
-- @tparam table sku_b SKU 货品 B
-- @treturn boolean true 表示 A 排在 B 前面
local function sku_sort( sku_a, sku_b )
    -- A 排 B 前面
    if sku_a.S_CELL_TYPE > sku_b.S_CELL_TYPE then
        return false
    elseif sku_a.S_CELL_TYPE == sku_b.S_CELL_TYPE then
        return sku_a.Q > sku_b.Q
    end
    return true
end

--[[ 
    合并可混箱的相同类型料格数量，
    same_mixing_rule_item_list --> {{ cell_type ,need_cell_num , mixing_rule={}  item_codes = {"X1","X2"} },...}
    out_cell_item --> { cell_type ,need_cell_num , mixing_rule={}, item_code } 
--]]
-- 合并可混箱的相同料格类型货品，将相同 cell_type 且相同混箱规则的货品归入同一组
-- @function add_in_same_mixing_rule_item_list
-- @tparam table ctd 容器类型定义，包含 mixing_attrs 混箱属性列表
-- @tparam table same_mixing_rule_item_list 相同混箱规则的料格分组列表
-- @tparam table out_cell_item 待加入的料格项 {cell_type, need_cell_num, mixing_rule, sku}
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string errMsg 失败时返回错误信息
local function add_in_same_mixing_rule_item_list( ctd, same_mixing_rule_item_list, out_cell_item )
    local find = false
    local nRet
    for _, cell_item in ipairs( same_mixing_rule_item_list ) do
        if cell_item.cell_type == out_cell_item.cell_type then
            if not lua.isTableEmpty( out_cell_item.mixing_rule ) then
                -- 判断是否相同混箱规则
                nRet, find = wms_pac.sku_complies_with_mixing_rule ( ctd, out_cell_item.mixing_rule, cell_item.mixing_rule )
                if nRet ~= 0 then
                    return 1, find
                end
                if find then
                    cell_item.need_cell_num = cell_item.need_cell_num + out_cell_item.need_cell_num
                    table.insert( cell_item.sku_list, out_cell_item.sku )
                    return 0
                end
            end
        end
    end

    if not find then
        local out_cntr = {
            cell_type = out_cell_item.cell_type,
            need_cell_num = out_cell_item.need_cell_num,
            mixing_rule = out_cell_item.mixing_rule,
            sku_list = {}
        }
        table.insert( out_cntr.sku_list, out_cell_item.sku )
        table.insert( same_mixing_rule_item_list, out_cntr )
    end
    return 0
end

--[[
    把货品分配到 呼出的料箱格列表 out_cntr_list
    cntr_list/准备呼出的料箱 = {{ cntr_code，cntr_good_weight，cntr_mixing_rule = {} cell_type，empty_cell_list = {},，full = false,cell_list = {},...}
                      cntr_mixing_rule -- 料箱混料规则
    item -- 入库单明细 item_list 中的一个元素
    out_cntr_list -- 分配好的料格加入这个列表
    注意：这里的 out_cntr_list 都是符合混箱规则的，空料格都可以分配
--]]
-- 将单个货品 item 分配到呼出的容器列表 cntr_list 中的空料格，完成分配后加入 out_cntr_list
-- @function alloc_cntr
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数
-- @tparam table cntr_list 待分配的容器列表
-- @tparam table item 入库货品信息
-- @tparam table out_cntr_list 输出：已分配的容器列表
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string errMsg 失败时返回错误信息
local function alloc_cntr( strLuaDEID, pac_cfg, cntr_list, item, out_cntr_list )
    local nRet, strRetInfo
    
    if pac_cfg == nil  then
        return 1,  "alloc_cntr 函数中输入参数 pac_cfg 不能为 nil"
    end    
    if item == nil  then
        return 1,  "alloc_cntr 函数中输入参数 item 不能为 nil"
    end
    if cntr_list == nil  then
        return 1,  "alloc_cntr 函数中输入参数 cntr_list 不能为 nil"
    end  
    -- 如果货品已经分配完成不需要执行该函数
    if item.ok then
        return 0
    end

    local cntr_cell = {}
    local si_qty, qty, cntr_good_weight
    for _, cntr in ipairs( cntr_list ) do
        -- 遍历呼出料箱中的空料格列表
        for _, empty_cell in ipairs( cntr.empty_cell_list ) do
            -- item_code 为空说明这个料格还没有被其它货品分配
            if empty_cell.item_code == '' then
                -- 料格初始化
                cntr_cell = {
                    cntr_code = cntr.cntr_code,
                    cell_no = empty_cell.cell_no,
                    cell_type = cntr.cell_type,
                    good_volume = 0,         -- 料格已经存放的货品体积累计值
                    good_weight = 0,
                    qty = 0, 
                    wms_bn = ""  
                }            
                cntr_good_weight = cntr.cntr_good_weight     

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
                    local cell_item = {
                        cntr_code = cntr_cell.cntr_code,
                        cell_type = cntr_cell.cell_type,
                        cell_no = cntr_cell.cell_no,
                        item_code = item.S_ITEM_CODE,
                        item_name = item.S_ITEM_NAME,
                        row = item.row,
                        wms_bn = "",
                        qty = si_qty,
                        sum_volume = si_qty*item.volume,
                        sum_weight = si_qty*item.weight,
                        weight = item.weight,
                        volume = item.volume,
                        sku = item
                    }
                    table.insert( item.cntr_cell_list, cell_item )
                    table.insert( cntr.cell_list, cell_item )
                    cntr.cntr_good_weight = cntr.cntr_good_weight + cell_item.sum_weight
                    empty_cell.item_code = cell_item.item_code

                    if lua.isTableEmpty( cntr.cntr_mixing_rule ) then
                        local cntr_mixing_rule = {}
                        for _, attr in ipairs( pac_cfg.ctd.mixing_attrs ) do
                            cntr_mixing_rule[attr] = lua.Get_StrAttrValue( item[attr])
                        end
                        cntr.cntr_mixing_rule = cntr_mixing_rule
                    end

                    -- 更新容器对象里 N_ALLOC_CELL_NUM 数量
                    nRet, strRetInfo = wms_cntr.CNTR_cell_alloc_set( strLuaDEID, cntr_cell.cntr_code, cntr_cell.cell_no, pac_cfg.bs_no )
                    if nRet ~= 0 then
                        return 1, strRetInfo
                    end
                    if item.ok then
                        goto reset_cntr_list
                    end

                end               
            end
        end
    end

    ::reset_cntr_list::
    -- 设置一下 cntr_list 中的空料格
    local find
    wms_pac.reset_empty_cell_info( cntr_list )
    for _, cntr in ipairs( cntr_list ) do
        if #cntr.cell_list > 0 then
            find = false
            for _, out_cntr in ipairs( out_cntr_list ) do
                if cntr.cntr_code == out_cntr.cntr_code then
                    find = true
                    break
                end
            end
            if not find then
                table.insert( out_cntr_list, cntr )
            end
        end
    end
    return 0
end

--[[
    把对应的货品分配到呼出的空料箱
    same_cell_sum/相同料格汇总信息 =  { cell_type ,need_cell_num , mixing_rule={}  sku_list = {item_code,item_state,storer} }
    cntr_list/呼出的料箱编码 ={{ cntr_code，cntr_good_weight，cell_type，empty_cell = {},，full = false,cell_list = {},...}
    item_list/入库单明细
    out_cntr_list
--]]
-- 将相同料格汇总中的货品分配到呼出的空料箱列表中
-- @function alloc_cntr_by_cell_same_sum
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数
-- @tparam table cell_same_sum 相同料格汇总信息
-- @tparam table cntr_list 呼出的空料箱列表
-- @tparam table item_list 入库货品明细列表
-- @tparam table out_cntr_list 输出：已分配的容器列表
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string errMsg 失败时返回错误信息
local function alloc_cntr_by_cell_same_sum( strLuaDEID, pac_cfg, cell_same_sum, cntr_list, item_list, out_cntr_list )
    local nRet, strRetInfo

    for _, sku in ipairs( cell_same_sum.sku_list ) do
        for _, item in ipairs( item_list ) do
            -- 定位到 入库单明细 这里的item
            if item.ok == false and item.S_ITEM_CODE == sku.item_code and item.S_ITEM_STATE == sku.item_state and item.S_STORER == sku.storer then
                nRet, strRetInfo = alloc_cntr( strLuaDEID, pac_cfg, cntr_list, item, out_cntr_list )
                if nRet ~= 0 then
                    return 1, strRetInfo
                end 
                break
            end
        end
    end
    return 0
end

-- 计算货品列表中每个 SKU 需要多少个空料格（Q 值）
-- @function set_sku_Q_value
-- @tparam table ctd 容器类型定义
-- @tparam table item_list 货品列表
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string errMsg 失败时返回错误信息
local function set_sku_Q_value( ctd, item_list )
    local nRet
    local cntr_cell = {
                        cntr_code = "",
                        cell_no = "",
                        wms_bn = "",
                        good_volume = 0,
                        cell_type = "",
                        good_weight = 0, 
                        qty = 0
                    }
    local cell_max_qty   -- 料格数量
    local x_qty, qty
    for _, sku in ipairs( item_list ) do
        if not sku.ok then
            -- 计算 SKU 需要多少个空料格
            -- 获取一个料格能分配多少给 SKU
            qty = sku.qty - sku.alloc_qty
            cntr_cell.cell_type = sku.S_CELL_TYPE
            nRet, cell_max_qty = wms_cntr.Get_CntrCell_Goods_Qty( ctd, 0, cntr_cell, sku )
            if nRet ~= 0 then
                return nRet, cell_max_qty
            end
            if cell_max_qty <= 0 then
                return 1, "SKU'"..sku.S_ITEM_CODE.."'在计算料格转载最大数量是失败,返回数量 <= 0"
            end
            Q = math.floor( qty/cell_max_qty)
            -- 余量
            x_qty = qty - Q*cell_max_qty
            if lua.equation( 0, x_qty ) == false then
                Q = Q + 1
            end
            sku.Q = Q
        else
            sku.Q = 0
        end
    end 
    return 0   
end

-- 把 item_list 中的货品根据混箱规则进行分组，相同 cell_type 和混箱规则的归为一组
-- @function get_same_mixing_rule_cntr_list
-- @tparam table ctd 容器类型定义，包含 mixing_attrs 混箱属性列表
-- @tparam table item_list 货品列表
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table/string same_mixing_rule_cntr_list 成功时返回分组后的列表，失败时返回错误信息
local function get_same_mixing_rule_cntr_list( ctd, item_list )
    local nRet, strRetInfo
    local same_mixing_rule_cntr_list = {}

    for _, sku in ipairs( item_list ) do
        -- 合并相同 cell_type 及 混箱规则的SKU这些货品可以一起呼叫料箱
        if not sku.ok then
            local out_cell_item = {
                cell_type = sku.S_CELL_TYPE,
                need_cell_num = sku.Q,
                mixing_rule = sku.mixing_rule,
                sku = { item_code = sku.S_ITEM_CODE, item_state = sku.S_ITEM_STATE, storer = sku.S_STORER }
            }
            nRet, strRetInfo = add_in_same_mixing_rule_item_list( ctd, same_mixing_rule_cntr_list, out_cell_item )
            if nRet ~= 0 then
                return 1, strRetInfo 
            end
        end
    end
    return 0, same_mixing_rule_cntr_list
end  

-- 根据巷道任务均衡从容器表中查询指定数量的空料箱
-- @function get_empty_cntr_list_by_aisile_lb
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数，包含 ctd, dbtype, aisle_lb 等
-- @tparam string cell_type 料格类型
-- @tparam string str_loc_where 货位查询条件
-- @tparam number num 需要的容器数量
-- @tparam table empty_cntr_list 输出：查询到的空料箱列表
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string errMsg 失败时返回错误信息
local function get_empty_cntr_list_by_aisile_lb( strLuaDEID, pac_cfg, cell_type, str_loc_where, num, empty_cntr_list )
    local strCondition
    local strTable = "TN_Container a INNER JOIN TN_Loc_Container b ON a.S_CODE = b.S_CNTR_CODE "..
                     "INNER JOIN TN_Location c ON b.S_LOC_CODE = c.S_CODE "
                    
    if pac_cfg.dbtype == DB_TYPE.SQLServer then    
        strCondition = "a.S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."' AND a.C_ENABLE = 'Y' AND a.S_SPEC = '"..cell_type.."' AND a.N_EMPTY_FULL = 0 AND a.N_LOCK_STATE = 0 AND a.N_ALLOC_CELL_NUM = 0 AND "..
                    "a.S_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where "..str_loc_where..")) "
    else
        strCondition = "a.S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."' AND a.C_ENABLE = 'Y' AND a.S_SPEC = '"..cell_type.."' AND a.N_EMPTY_FULL = 0 AND a.N_LOCK_STATE = 0 AND a.N_ALLOC_CELL_NUM = 0 AND "..
                    "a.S_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where "..str_loc_where..")) "
    end   
    -- 获取料箱编码，货位，巷道编码
    local strAttrs = "a.S_CODE, b.S_LOC_CODE, c.S_AISLE_CODE"
    local strOrder = 'a.S_CODE'

    local nRet, cntr_list = wms_base.Get_Matching_cntr_list( strLuaDEID, pac_cfg, strTable, strAttrs, 3, strCondition, strOrder)
    if nRet ~= 0 then
        return 1, "获取所有符合条件的料箱失败! "..cntr_list
    end

    -- 获取 num 个空托盘
    local n = 1
    for _, empty_cntr in ipairs( cntr_list ) do
        local out_cntr = {
            cntr_code = empty_cntr.cntr_code,
            cntr_good_weight = 0, 
            cell_type = cell_type,
            empty_cell_list = {},
            full = false,
            cell_list = {}
        }
        table.insert( empty_cntr_list, out_cntr )        
        n = n + 1
        if n > num then
            break
        end
    end   
    return 0
end

-- 从容器表查出指定数量的空料箱（所有料格都空），设置空料格信息并完成分配
-- @function query_empty_cntr_to_alloc
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数
-- @tparam table item_list 入库货品明细列表
-- @tparam table cell_same_sum 相同混箱规则的料格汇总 {cell_type, need_cell_num, mixing_rule, sku_list}
-- @tparam number num 需要的空料箱数量
-- @tparam string str_loc_where 货位查询条件
-- @tparam table out_cntr_list 输出：已分配的容器列表
-- @treturn number nRet 0: 成功，1/2: 失败
-- @treturn string errMsg 失败时返回错误信息
local function query_empty_cntr_to_alloc( strLuaDEID, pac_cfg, item_list, cell_same_sum, num, str_loc_where, out_cntr_list )
    local nRet, data_objs, strRetInfo, data_attrs
    local cntr_list = {}         

    -- 注： N_EMPTY_FULL = 0 表示空箱 N_LOCK_STATE = 0 表示料格没锁 N_ALLOC_CELL_NUM = 0 表示没预分配 
    -- **** N_ALLOC_CELL_NUM 这里需要再思考一下
    -- N_EMPTY_FULL < 2 说明料箱未满
    local strCondition
    if pac_cfg.aisle_lb == 1 then
        -- 需要做巷道均衡
        nRet, strRetInfo = get_empty_cntr_list_by_aisile_lb( strLuaDEID, pac_cfg, cell_same_sum.cell_type, str_loc_where, num, cntr_list  )
        if nRet ~= 0 then
            return 1, strRetInfo
        end
    else
        if pac_cfg.dbtype == DB_TYPE.SQLServer then    
            strCondition = "S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."' AND C_ENABLE = 'Y' AND S_SPEC = '"..cell_same_sum.cell_type.."' AND N_EMPTY_FULL = 0 AND N_LOCK_STATE = 0 AND N_ALLOC_CELL_NUM = 0 AND "..
                        "S_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where "..str_loc_where..")) "
        else
            strCondition = "S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."' AND C_ENABLE = 'Y' AND S_SPEC = '"..cell_same_sum.cell_type.."' AND N_EMPTY_FULL = 0 AND N_LOCK_STATE = 0 AND N_ALLOC_CELL_NUM = 0 AND "..
                        "S_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where "..str_loc_where..")) "
        end
        nRet, data_objs = m3.QueryDataObject3( strLuaDEID, "Container", strCondition, "",num)
        if nRet ~= 0 then 
            return 2, "查询容器失败! "..data_objs 
        end
        if data_objs ~= '' then
            for n = 1, #data_objs do
                data_attrs = m3.KeyValueAttrsToObjAttr(data_objs[n].attrs)
                if data_attrs == nil then      
                    return 1, "KeyValueAttrsToObjAttr 失败! "..data_objs[n].attrs 
                end
                local out_cntr = {
                    cntr_code = data_attrs.S_CODE,
                    cntr_good_weight = 0, 
                    cell_type = cell_same_sum.cell_type,
                    empty_cell_list = {},
                    full = false,
                    cell_list = {}
                }
                table.insert( cntr_list, out_cntr )
            end
        end
    end

    nRet, strRetInfo = wms_pac.set_out_cntr_empty_cell( strLuaDEID, cntr_list )
    if nRet ~= 0 then
        return 1, strRetInfo
    end
    -- 把对应的货品分配到呼出的空料箱,把料箱加入呼出列表 out_cntr_list
    nRet, strRetInfo = alloc_cntr_by_cell_same_sum( strLuaDEID, pac_cfg, cell_same_sum, cntr_list, item_list, out_cntr_list )
    if nRet ~= 0 then
        return 1, strRetInfo
    end 
    return 0           
end

-- 将查询结果数组转换为料格信息表 cntr_cell
-- @function get_cntr_cell_info
-- @tparam table call_out_cntr_cell 查询结果数组 [cntr_code, cell_no, wms_bn, good_volume, cell_type, cntr_good_weight, good_weight, ...]
-- @treturn table cntr_cell 料格信息表 {cntr_code, cell_no, wms_bn, good_volume, cell_type, cntr_good_weight, good_weight}
local function get_cntr_cell_info(call_out_cntr_cell)
    local cntr_cell = {}

    cntr_cell.cntr_code = call_out_cntr_cell[1]
    cntr_cell.cell_no = call_out_cntr_cell[2]
    cntr_cell.wms_bn = call_out_cntr_cell[3]
    cntr_cell.good_volume = lua.StrToNumber( call_out_cntr_cell[4] )         -- 料格已经存放的货品体积累计值
    cntr_cell.cell_type = call_out_cntr_cell[5]              -- 料格类型 A/B/C/D/E
    cntr_cell.cntr_good_weight = lua.StrToNumber( call_out_cntr_cell[6] )   -- 容器当前存储货品重量
    cntr_cell.good_weight = lua.StrToNumber( call_out_cntr_cell[7] )  -- 料格里的货品重量，这里的货品都是一样重量的

    return cntr_cell
end

-- 将呼出的容器 out_cntr 加入 out_cntr_list，如容器已存在则合并 cell_list
-- @function insert_out_cntr_list
-- @tparam table out_cntr_list 呼出容器列表
-- @tparam table out_cntr 待加入的容器
local function insert_out_cntr_list( out_cntr_list, out_cntr )
    -- 先判断一下呼出的料箱列表中这个料箱是否已经存在
    for _, cntr in ipairs(out_cntr_list) do
        if cntr.cntr_code == out_cntr.cntr_code then
            for _, cell in ipairs(out_cntr.cell_list) do
                table.insert(cntr.cell_list, cell)
            end
            return
        end
    end
    table.insert(out_cntr_list, out_cntr)    
end

-- 从容器表查询空料格（非全空容器），逐个尝试将货品分配到合适的料格中（支持巷道均衡）
-- @function query_empty_cell_to_alloc
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数
-- @tparam table item_list 入库货品明细列表
-- @tparam table in_op_cntr_list 有作业的料箱
-- @tparam string str_loc_where 货位查询条件
-- @tparam table out_cntr_list 输出：已分配的容器列表
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string errMsg 失败时返回错误信息
local function query_empty_cell_to_alloc( strLuaDEID, pac_cfg, item_list, str_loc_where, in_op_cntr_list, out_cntr_list )
    local strRetInfo
    local cntr_max_weight = pac_cfg.ctd.load_capacity   
    local strTable = "TN_Container_Cell a LEFT JOIN TN_Container b ON a.S_CNTR_CODE = b.S_CODE "       -- 联表

    -- 如果有混箱规则，需要把容器中规则定义的属性取值
    if pac_cfg.ctd.have_mixing_rule then
        strTable = strTable.." LEFT JOIN TN_Container_Ext c ON a.S_CNTR_CODE = c.S_CNTR_CODE"
    end
    local strAttrs = "a.S_CNTR_CODE, a.S_CELL_NO, a.S_WMS_BN, a.F_GOOD_VOLUME, b.S_SPEC, b.F_GOOD_WEIGHT, a.F_GOOD_WEIGHT" 

    -- 如果要考虑巷道均衡，必须要有料箱所在的巷道信息
    if pac_cfg.aisle_lb == 1 then
        strTable = strTable.." INNER JOIN TN_Loc_Container d ON a.S_CNTR_CODE = d.S_CNTR_CODE "..
                             " INNER JOIN TN_Location e ON d.S_LOC_CODE = e.S_CODE "
        strAttrs = strAttrs..", e.S_AISLE_CODE"
    end

    local strCondition

    -- 排序根据有货的料箱优先
    local strOrder = "b.N_EMPTY_CELL_NUM desc"
    local old_alloc_qty

    for _, item in ipairs( item_list ) do
        if not item.ok and item.Q > 0 then
            local mixing_condition = "" -- 混箱条件
            local cntr_mixing_rule = {}  
            
            if pac_cfg.ctd.have_mixing_rule then
                for _, attr in ipairs( pac_cfg.ctd.mixing_attrs ) do
                    mixing_condition = mixing_condition.." AND c."..attr.." = '"..item[attr].."'"
                end
                for _, attr in ipairs( pac_cfg.ctd.mixing_attrs ) do
                    cntr_mixing_rule[attr] = item[attr]
                end    
            end
       
            if pac_cfg.dbtype == DB_TYPE.SQLServer then    
                strCondition = "b.S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."' AND b.C_ENABLE = 'Y' AND b.S_SPEC = '"..item.S_CELL_TYPE.."' AND a.N_EMPTY_FULL = 0 AND b.N_LOCK_STATE = 0 AND "..
                               "b.S_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where "..str_loc_where..")) "
            else
                strCondition = "b.S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."' AND b.C_ENABLE = 'Y' AND b.S_SPEC = '"..item.S_CELL_TYPE.."' AND a.N_EMPTY_FULL = 0 AND b.N_LOCK_STATE = 0 AND "..
                               "b.S_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where "..str_loc_where..")) "
            end
            strCondition = strCondition..mixing_condition

            -- 如果要控制料箱总的载重
            if pac_cfg.ctd.check_capacity then
                strCondition = strCondition.." AND b.F_GOOD_WEIGHT < "..cntr_max_weight
            end

            -- 获取所有符合条件的料箱
            local nRet, empty_cntr_list = wms_base.Get_Matching_cntr_list( strLuaDEID, pac_cfg, strTable, strAttrs, 8, strCondition, strOrder)
            if nRet ~= 0 then
                return 1, "获取所有符合条件的料箱失败! "..empty_cntr_list
            end

            -- MDF BY HAN @20260730
            -- 如果要判断没作业的料箱优先
            if pac_cfg.no_operation_first then
                for _, out_cntr in ipairs( empty_cntr_list ) do 
                    if lua.IsInTable( out_cntr.cntr_code, in_op_cntr_list ) then
                        out_cntr.op = 1      -- 料箱有作业在做
                    else
                        out_cntr.op = 2      -- 料箱没作业在做
                    end
                end
                -- 排序，有作业的靠后
                table.sort( empty_cntr_list, function(a, b)
                                                return a.op > b.op  -- 没作业的料箱优先
                                        end
                        ) 
            end            

            for _, cntr in ipairs(empty_cntr_list) do
                local out_cntr_cell
                out_cntr_cell = get_cntr_cell_info(cntr.attrs)
                local out_cntr = {
                    cntr_code = cntr.cntr_code,
                    cntr_good_weight = out_cntr_cell.cntr_good_weight, 
                    cell_type = out_cntr_cell.cell_type,
                    empty_cell_list = {},
                    full = false,
                    cell_list = {},
                    cntr_mixing_rule = cntr_mixing_rule
                }                
                local cntr_list = {}
                table.insert( cntr_list, out_cntr )
                -- 设置 out_cntr中的empty_cell_list
                nRet, strRetInfo = wms_pac.set_out_cntr_empty_cell( strLuaDEID, cntr_list )
                if nRet ~= 0 then
                    return 1, strRetInfo
                end
                -- 把料格推荐给货品 item
                old_alloc_qty = item.alloc_qty
                nRet, strRetInfo = wms_pac.pre_alloc_sku_to_out_cntr( strLuaDEID, pac_cfg, item, cntr_list[1] )
                if nRet ~= 0 then
                    return 1, strRetInfo
                end
                -- 货品分配数量变化说明 cntr_list[1]的这个料箱已经被货品匹配到
                if old_alloc_qty ~= item.alloc_qty then
                    -- 巷道的任务数量加一
                    if pac_cfg.aisle_lb == 1 then
                        wms_base.Add_Aisle_Task_Num( pac_cfg.aisle_set, cntr.aisle_code )
                    end
                    wms_pac.reset_empty_cell_info( cntr_list )
                    insert_out_cntr_list( out_cntr_list, cntr_list[1] )
                end

                if item.ok then
                    break
                end
            end
        end
    end
    return 0           
end

-- 从容器表查询一个空料箱，尝试将单个货品 item 分配到该料箱的空料格中
-- @function query_one_empty_cntr_to_alloc
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数
-- @tparam table item 单个入库货品信息
-- @tparam string str_loc_where 货位查询条件
-- @tparam table in_op_cntr_list 有作业的料箱
-- @tparam table out_cntr_list 输出：已分配的容器列表
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string errMsg 失败时返回错误信息
local function query_one_empty_cntr_to_alloc( strLuaDEID, pac_cfg, item, str_loc_where, in_op_cntr_list, out_cntr_list )
    local strRetInfo
    local strTable = "TN_Container_Cell a LEFT JOIN TN_Container b ON a.S_CNTR_CODE = b.S_CODE "       -- 联表
    local strAttrs = "a.S_CNTR_CODE, a.S_CELL_NO, a.S_WMS_BN, a.F_GOOD_VOLUME, b.S_SPEC, b.F_GOOD_WEIGHT, a.F_GOOD_WEIGHT" 

    -- 如果要考虑巷道均衡，必须要有料箱所在的巷道信息
    if pac_cfg.aisle_lb == 1 then
        strTable = strTable.." INNER JOIN TN_Loc_Container d ON a.S_CNTR_CODE = d.S_CNTR_CODE "..
                             " INNER JOIN TN_Location e ON d.S_LOC_CODE = e.S_CODE "
        strAttrs = strAttrs..", e.S_AISLE_CODE"
    end
    
    local strCondition

    -- 排序根据有货的料箱优先
    local strOrder = "b.N_EMPTY_CELL_NUM desc"
    local old_alloc_qty
    local cntr_mixing_rule = {}  
    
    if pac_cfg.ctd.have_mixing_rule then
        for _, attr in ipairs( pac_cfg.ctd.mixing_attrs ) do
            cntr_mixing_rule[attr] = item[attr]
        end    
    end    

    if pac_cfg.dbtype == DB_TYPE.SQLServer then    
        strCondition = "b.S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."' AND b.C_ENABLE = 'Y' AND b.S_SPEC = '"..item.S_CELL_TYPE.."' AND a.N_EMPTY_FULL = 0 AND b.N_LOCK_STATE = 0 AND "..
                    "b.S_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where "..str_loc_where..")) "
    else
        strCondition = "b.S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."' AND b.C_ENABLE = 'Y' AND b.S_SPEC = '"..item.S_CELL_TYPE.."' AND a.N_EMPTY_FULL = 0 AND b.N_LOCK_STATE = 0 AND "..
                    "b.S_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where "..str_loc_where..")) "
    end
    -- 

    -- 获取所有符合条件的料箱
    local nRet, empty_cntr_list = wms_base.Get_Matching_cntr_list( strLuaDEID, pac_cfg, strTable, strAttrs, 8, strCondition, strOrder)
    if nRet ~= 0 then
        return 1, "获取所有符合条件的料箱失败! "..empty_cntr_list
    end

    -- MDF BY HAN @20260730
    -- 如果要判断没作业的料箱优先
    if pac_cfg.no_operation_first then
        for _, out_cntr in ipairs( empty_cntr_list ) do 
            if lua.IsInTable( out_cntr.cntr_code, in_op_cntr_list ) then
                out_cntr.op = 1      -- 料箱有作业在做
            else
                out_cntr.op = 2      -- 料箱没作业在做
            end
        end
        -- 排序，有作业的靠后
        table.sort( empty_cntr_list, function(a, b)
                                        return a.op > b.op  -- 没作业的料箱优先
                                end
                ) 
    end    

    local out_cntr_cell
    if #empty_cntr_list > 0 then
        -- 获取一个空料箱
        out_cntr_cell = get_cntr_cell_info(empty_cntr_list[1].attrs)    
        local out_cntr = {
            cntr_code = out_cntr_cell.cntr_code,
            cntr_good_weight = out_cntr_cell.cntr_good_weight, 
            cell_type = out_cntr_cell.cell_type,
            empty_cell_list = {},
            full = false,
            cell_list = {},
            cntr_mixing_rule = cntr_mixing_rule
        }   
        local cntr_list = {}
        table.insert( cntr_list, out_cntr )
        -- 设置 out_cntr中的empty_cell_list
        nRet, strRetInfo = wms_pac.set_out_cntr_empty_cell( strLuaDEID, cntr_list )
        if nRet ~= 0 then
            return 1, strRetInfo
        end
        -- 把料格推荐给货品 item
        old_alloc_qty = item.alloc_qty
        nRet, strRetInfo = wms_pac.pre_alloc_sku_to_out_cntr( strLuaDEID, pac_cfg, item, cntr_list[1] )
        if nRet ~= 0 then
            return 1, strRetInfo
        end
        -- 货品分配数量变化说明 cntr_list[1]的这个料箱已经被货品匹配到
        if old_alloc_qty ~= item.alloc_qty then
            -- 如果考虑了巷道均衡，需要增加巷道任务数量
            if pac_cfg.aisle_lb == 1 then
                wms_base.Add_Aisle_Task_Num( pac_cfg.aisle_set, empty_cntr_list[1].aisle_code )
            end        
            wms_pac.reset_empty_cell_info( cntr_list )
            insert_out_cntr_list( out_cntr_list, cntr_list[1] )
        end
    end
    return 0           
end

-- 获取空料箱格推荐给入库货品（DMG算法核心：先呼空箱→已呼容器→空料格→补呼空箱）
-- @function get_out_cntr_list_dmg
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 料箱预分配策略配置信息，包含 wh_code, area_code, ctd 等
-- @tparam table item_list 入库货品列表
-- @tparam table in_op_cntr_list 在作业中的容器
-- @tparam table out_cntr_list 输出：呼出的料箱列表
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn string errMsg 失败时返回错误信息
local function get_out_cntr_list_dmg( strLuaDEID, pac_cfg, item_list, in_op_cntr_list, out_cntr_list )
    local nRet, strRetInfo
    local str_loc_where = ''

    -- step1 输入参数判断
    if pac_cfg.wh_code == nil or pac_cfg.wh_code == '' then
        return 1, "输入参数错误， wh_code 必须有值"
    end
    str_loc_where = "C_ENABLE = 'Y' AND S_WH_CODE = '"..pac_cfg.wh_code.."'"
    if not lua.StrIsEmpty( pac_cfg.area_code ) then
        str_loc_where = str_loc_where.." AND S_AREA_CODE = '"..pac_cfg.area_code.."'"
    end
    local ctd_code = pac_cfg.ctd.ctd_code
    if ctd_code == nil or ctd_code == '' then
        return 1, "输入参数错误， pac_cfg 中 ctd.ctd_code 必须有值"
    end

    -- step2 数据准备
    -- 计算入库SKU需要多少料格
    nRet, strRetInfo = set_sku_Q_value( pac_cfg.ctd, item_list )
    if nRet ~= 0 then
        return 1, strRetInfo 
    end    
    -- SKU根据 cell_type + Q (需要呼出料格数量) 进行排序 Q 大的前面
    table.sort( item_list, sku_sort )

    -- 遍历需要入库的货品清单，把相同混箱条件的货品的呼出料箱数量合并。
    -- 确定是否整个料箱都是空的料箱先呼出
    -- 先呼出整个料箱都是空的料箱，目的是减少出入库料箱数量
    local same_mixing_rule_cntr_list
    nRet, same_mixing_rule_cntr_list = get_same_mixing_rule_cntr_list( pac_cfg.ctd, item_list )
    if nRet ~= 0 then
        return 1, same_mixing_rule_cntr_list
    end
    
    -- step3 
    -- 先把可以进相同混箱规则料箱的货品 SUM 在一起，呼出全空的料箱（每个料格都是空），尽量减少搬运次数
    local cell_def, num
   
    for _, cell_same_sum in ipairs( same_mixing_rule_cntr_list ) do
        nRet, cell_def = wms_cntr.Get_CTD_GridDef( pac_cfg.ctd, cell_same_sum.cell_type )
        if nRet ~= 0 then
            return 1, cell_def
        end
        -- 如果需要的料格数量小于 一个空料箱的料格 不执行下面的呼出
        if cell_same_sum.need_cell_num >= cell_def.box_num then
            -- 呼出整个料箱都是空的料箱
            num = math.floor( cell_same_sum.need_cell_num/cell_def.box_num )
            -- 从容器表找到合适的料箱（数量=num）分配给 item_list
            nRet, strRetInfo = query_empty_cntr_to_alloc( strLuaDEID, pac_cfg, item_list, cell_same_sum, num, str_loc_where, out_cntr_list )
            if nRet ~= 0 then
                return 1, strRetInfo
            end
        end
    end

    -- MDF BY HAN @20260730
    -- 如果要判断没作业的料箱优先
    if pac_cfg.no_operation_first then
        for _, out_cntr in ipairs( out_cntr_list ) do 
            if lua.IsInTable( out_cntr.cntr_code, in_op_cntr_list ) then
                out_cntr.op = 1      -- 料箱有作业在做
            else
                out_cntr.op = 2      -- 料箱没作业在做
            end
        end
        -- 排序，有作业的靠后
        table.sort( out_cntr_list, function(a, b)
                                        return a.op > b.op  -- 没作业的料箱优先
                                   end
                ) 
    end
    local pac_is_ok = wms_base.item_list_is_all_ok( item_list )    

    -- step 4 在已经呼出的料箱容器列表中查找有相同混箱规则的且未满有货的料格
    if not pac_is_ok then
        for _, item in ipairs( item_list ) do
            if not item.ok then
                -- 根据货品的适配料格类型呼出空料格
                for _, cntr in ipairs( out_cntr_list ) do
                    nRet, strRetInfo = wms_pac.pre_alloc_sku_to_out_cntr( strLuaDEID, pac_cfg, item, cntr )
                    if nRet ~= 0 then
                        return 1, strRetInfo
                    end
                    if item.ok then
                        break
                    end
                end                
            end
        end
    end

    pac_is_ok = wms_base.item_list_is_all_ok( item_list )
    -- step 5 查找空料格装载剩余没分配料格的货品
    if not pac_is_ok then   
        -- 进一步设置一下货品需要的料格数 Q
        nRet, strRetInfo = set_sku_Q_value( pac_cfg.ctd, item_list )
        if nRet ~= 0 then
            return 1, strRetInfo 
        end    
        -- SKU 根据 cell_type + Q (需要呼出料格数量) 进行排序 Q 大的前面
        table.sort( item_list, sku_sort ) 
        
        -- 如果料箱类型是允许补料，检查一下 out_cntr_list 是否可以进行补料
        -- 检查已经呼出的料箱列表，是否有空料格可以进行推荐
        pac_is_ok = wms_base.item_list_is_all_ok( item_list )
        -- 从新呼出空料箱格进行推荐
        if not pac_is_ok then
            nRet, strRetInfo = query_empty_cell_to_alloc( strLuaDEID, pac_cfg, item_list, str_loc_where, in_op_cntr_list, out_cntr_list )
            if nRet ~= 0 then
                return 1, strRetInfo
            end
        end

        pac_is_ok = wms_base.item_list_is_all_ok( item_list )
        if not pac_is_ok then
            -- 呼出空料箱进行推荐  
            local new_call_out_cntr_list = {}
            for _, item in ipairs( item_list ) do
                if not item.ok then
                    -- 首先从新呼出的料箱里进行匹配
                    for _, cntr in ipairs( new_call_out_cntr_list ) do
                        nRet, strRetInfo = wms_pac.pre_alloc_sku_to_out_cntr( strLuaDEID, pac_cfg, item, cntr )
                        if nRet ~= 0 then
                            return 1, strRetInfo
                        end
                        if item.ok then
                            break
                        end
                    end                     
                    if not item.ok then
                        nRet, strRetInfo = query_one_empty_cntr_to_alloc( strLuaDEID, pac_cfg, item, str_loc_where, in_op_cntr_list, new_call_out_cntr_list )
                        if nRet ~= 0 then
                            return 1, strRetInfo
                        end                        
                    end
                end
            end

            for _, cntr in ipairs( new_call_out_cntr_list ) do
                table.insert( out_cntr_list, cntr )
            end
        end        

    end

    -- 下面可以加一个优化，呼出有相同混箱规则的未满空料格的料箱，这部分代码没完善
    return 0    
end

-- 计算料箱的可补料数量，将货品分配到补料呼出的容器料格中
-- @function calculate_bin_replenishment_qty
-- @tparam table pac_cfg 预分配配置参数，包含 ctd, aisle_lb 等
-- @tparam table item 入库货品信息
-- @tparam table call_out_cntr_cell 呼出的可补料格查询结果数组
-- @tparam table supplement_cntr_list 补料呼出容器列表（累加输出）
-- @treturn number nRet 0: 成功，1/2: 失败
-- @treturn string errMsg 失败时返回错误信息
local function calculate_bin_replenishment_qty( strLuaDEID, pac_cfg, item, call_out_cntr_cell, supplement_cntr_list )
    local cntr_cell = {}
    local cntr_good_weight = 0
    local ext_attr_index = 8
    local nRet, strRetInfo

    if pac_cfg.aisle_lb == 1 then
        ext_attr_index = 9
    end

    cntr_cell.cntr_code = call_out_cntr_cell[1]
    cntr_cell.cell_no = call_out_cntr_cell[2]
    cntr_cell.wms_bn = call_out_cntr_cell[3]
    cntr_cell.good_volume = lua.StrToNumber( call_out_cntr_cell[4] )         -- 料格已经存放的货品体积累计值
    cntr_cell.cell_type = call_out_cntr_cell[5]              -- 料格类型 A/B/C/D/E
    cntr_good_weight = lua.StrToNumber( call_out_cntr_cell[6] )   -- 容器当前存储货品重量
    cntr_cell.good_weight = lua.StrToNumber( call_out_cntr_cell[7] )  -- 料格里的货品重量，这里的货品都是一样重量的
    cntr_cell.qty = lua.StrToNumber( call_out_cntr_cell[8] )  
    local aisle_code = ''
    if pac_cfg.aisle_lb == 1 then
        aisle_code = call_out_cntr_cell[9]
    end
    -- MDF BY HAN @20250807 cntr_cell.qty 要判断一下是否已经被本次的预分配占用了一定的数量，因此需要调整 cntr_cell.qty
    -- cntr_cell.qty 是数据库里查询出来的已经实打实存在的量，cell.qty 是本次PAC过程中产生的数量，已经分配掉
    for _, si_cntr in ipairs( supplement_cntr_list ) do
        if si_cntr.cntr_code == cntr_cell.cntr_code then
            for _, cell in ipairs( si_cntr.cell_list ) do
                if cell.cell_no == cntr_cell.cell_no then
                    cntr_cell.qty = cntr_cell.qty + cell.qty
                    if cntr_cell.qty > 0 then
                        cntr_good_weight = cntr_good_weight + cell.weight*cell.qty
                    end
                    break
                end
            end
            break
        end
    end

    -- 获取料箱混箱规则属性                
    local cntr_mixing_rule = {}
    for i, attr in ipairs( pac_cfg.ctd.mixing_attrs ) do
        cntr_mixing_rule[attr] = lua.Get_StrAttrValue( call_out_cntr_cell[ext_attr_index+i])
    end

    -- 计算一下料格能分配多少个货品 si_qty
    local si_qty
    nRet, si_qty = wms_cntr.Get_CntrCell_Goods_Qty( pac_cfg.ctd, cntr_good_weight, cntr_cell, item )
    if nRet ~= 0 then 
        return 1, si_qty 
    end
    -- 如果计算出来的可存储数量大于 item.qty
    local qty = item.qty - item.alloc_qty
    if si_qty > qty then
        si_qty = qty
    end
    local weight, volume
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
            wms_bn = "",
            qty = si_qty,
            sum_volume = si_qty*volume,
            sum_weight = si_qty*weight,
            weight = weight,
            volume = volume,
            sku = item,
            sku_list = {}
        }
        nRet, strRetInfo = wms_pac.put_cell_item_to_out_cntr_list( supplement_cntr_list, cntr_good_weight, cell_item, cntr_mixing_rule )
        if nRet ~= 0 then
            return 2, strRetInfo
        end
        -- MDF BY WZK @20260708 补料料格也需要设置预分配状态,与空料格分配保持一致
        nRet, strRetInfo = wms_cntr.CNTR_cell_alloc_set( strLuaDEID, cntr_cell.cntr_code, cntr_cell.cell_no, pac_cfg.bs_no )
        if nRet ~= 0 then
            return 1, strRetInfo
        end
        if pac_cfg.aisle_lb == 1 then
            wms_base.Add_Aisle_Task_Num( pac_cfg.aisle_set, aisle_code )
        end        
        table.insert( item.cntr_cell_list, cell_item )
    end  
    return 0  
end
-- 获取补料容器料格列表（step1.1）：查询仓库中已存有货品且未满的料格，支持补料呼出
-- @function wms_pac.get_replenishment_cntr_list
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 呼出预分配料箱的基本参数，包含 wh_code, area_code, ctd 等
-- @tparam table item_list 需要进行料箱预分配的货品清单
-- @treturn number nRet 0: 成功，1/2: 失败
-- @treturn table/string supplement_cntr_list 成功时返回补料容器列表，失败时返回错误信息
function wms_pac.get_replenishment_cntr_list( strLuaDEID, pac_cfg, item_list )
    local nRet, strRetInfo, strCondition, strOrder
    local str_loc_where = ''
    local supplement_cntr_list = {}

    -- 输入参数判断
    if pac_cfg.wh_code == nil or pac_cfg.wh_code == '' then
        return 1, "输入参数错误， wh_code必须有值"
    end
    str_loc_where = "C_ENABLE = 'Y' AND S_WH_CODE = '"..pac_cfg.wh_code.."'"
    if not lua.StrIsEmpty( pac_cfg.area_code ) then
        str_loc_where = str_loc_where.." AND S_AREA_CODE = '"..pac_cfg.area_code.."'"
    end

    local ctd_code = pac_cfg.ctd.ctd_code
    if ctd_code == nil or ctd_code == '' then
        return 1, "输入参数错误， pac_cfg 中 ctd.ctd_code 必须有值"
    end

    -- 组织匹配料格的查询条件
    local si_match_attrs = pac_cfg.ctd.si_match_attrs or {}
    if type(si_match_attrs) ~= "table" then
        return 1, "输入参数错误, pac_cfg.ctd.si_match_attrs 必须是 table 类型!"
    end
    -- 匹配属性要加上 S_ITEM_CODE, S_STRORER, S_ITEM_STATE
    if not lua.IsInTable( "S_STORER", si_match_attrs ) then
        table.insert( si_match_attrs, "S_STORER" )
    end
    if not lua.IsInTable( "S_ITEM_CODE", si_match_attrs ) then
        table.insert( si_match_attrs, "S_ITEM_CODE" )
    end
    if not lua.IsInTable( "S_ITEM_STATE", si_match_attrs ) then
        table.insert( si_match_attrs, "S_ITEM_STATE" )
    end

    local ret_attr

    -- 确定匹配料格时查询顺序
    strOrder = ''
    local si_match_order = lua.Get_StrAttrValue( pac_cfg.ctd.si_match_order )
    if si_match_order == "Last_Entry_Batch" then
        strOrder = "a.S_WMS_BN DESC" 
    elseif si_match_order == "QTY_Desc" then
        strOrder = "a.F_QTY DESC" 
    elseif si_match_order == "QTY_Asc" then
        strOrder = "a.F_QTY Asc"         
    end

    -- 查询匹配的数量
    local si_cntr_num = lua.Get_NumAttrValue( pac_cfg.ctd.si_cntr_num )
    if si_cntr_num == 0 then
        si_cntr_num = 1000
    end

    -- si_cntr_num 为 1 时，只查询最近的批次号的料格，2 时查询最近的2个批次号的料格，以此类推
    -- 是呼出补料料格数量
    if si_cntr_num == 1 then
        strOrder = "a.S_WMS_BN DESC" 
    end

    local strTable = "TN_Container_Cell a LEFT JOIN TN_Container b ON a.S_CNTR_CODE = b.S_CODE "       -- 联表
    -- 如果有混箱规则，需要把容器中规则定义的属性取值
    if pac_cfg.ctd.have_mixing_rule then
        strTable = strTable.." LEFT JOIN TN_Container_Ext c ON a.S_CNTR_CODE = c.S_CNTR_CODE"
    end
    local strAttrs = "a.S_CNTR_CODE, a.S_CELL_NO, a.S_WMS_BN, a.F_GOOD_VOLUME, b.S_SPEC, b.F_GOOD_WEIGHT, a.F_GOOD_WEIGHT, a.F_QTY"          -- 查询字段
    if pac_cfg.aisle_lb == 1 then
        strTable = strTable.." INNER JOIN TN_Loc_Container d ON a.S_CNTR_CODE = d.S_CNTR_CODE "..
                             " INNER JOIN TN_Location e ON d.S_LOC_CODE = e.S_CODE "
        strAttrs = strAttrs..", e.S_AISLE_CODE"
    end
    
    if pac_cfg.ctd.have_mixing_rule then
        for _, attr in ipairs( pac_cfg.ctd.mixing_attrs ) do
            strAttrs = strAttrs..",c."..attr
        end
    end

    local cntr_max_weight = pac_cfg.ctd.load_capacity   
    local match_condition, str_value
    local si_match_attrs_count = #si_match_attrs

    for _, item in ipairs( item_list ) do
        -- ??? 这里有问题的，这里的属性都当是字符串来进行判断
        match_condition = ""
        for i = 1, si_match_attrs_count do
            str_value = item[si_match_attrs[i]]
            if str_value == nil then
                return 1, "容器类型定义'"..pac_cfg.ctd.ctd_code.."' matching_attrs --> "..si_match_attrs[i].." 没有在 item_list 中定义!"
            end
            match_condition = match_condition.." AND a."..si_match_attrs[i].." = '"..str_value.."' "
        end

        -- 查询出仓库里同一货品最近批次号并且未满的料格, 查 Container_Cell 表
        -- 注： N_EMPTY_FULL = 1 表示料格有货未满格 N_LOCK_STATE = 0 表示料格没锁
        -- a.S_STATE <> 'Abnormal' 料格有异常
        if pac_cfg.dbtype == DB_TYPE.SQLServer then        
            strCondition = "b.S_CTD_CODE = '"..ctd_code.."' AND a.S_CNTR_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where "..str_loc_where..")) "..
                            " AND a.C_FORCED_FILL = 'N' AND a.N_EMPTY_FULL = 1 AND b.N_LOCK_STATE = 0 AND b.C_ENABLE = 'Y' AND b.N_EMPTY_FULL < 2  AND b.C_FORCED_FILL = 'N'"..
                            " AND a.S_STATE <> 'Abnormal'"..match_condition
        else
            strCondition = "b.S_CTD_CODE = '"..ctd_code.."' AND a.S_CNTR_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where "..str_loc_where..")) "..
                            " AND a.C_FORCED_FILL = 'N' AND a.N_EMPTY_FULL = 1 AND b.N_LOCK_STATE = 0 AND b.C_ENABLE = 'Y' AND b.N_EMPTY_FULL < 2  AND b.C_FORCED_FILL = 'N'"..
                            " AND a.S_STATE <> 'Abnormal'"..match_condition            
        end

        -- 如果要控制料箱总的载重
        if pac_cfg.ctd.check_capacity then
            strCondition = strCondition.." AND b.F_GOOD_WEIGHT < "..cntr_max_weight
        end
        -- 
        if si_cntr_num == 1 or pac_cfg.aisle_lb ~= 1 then
            -- 不考虑巷道均衡
            nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, si_cntr_num, strCondition, strOrder )
            if nRet ~= 0 then
                return 2, "查询【容器料格】信息失败! " .. strRetInfo
            end
            if strRetInfo ~= '' then
                ret_attr = json.decode(strRetInfo)
                -- si_cntr_num = 1 表示只是把最近的一个料箱呼出进行补料
                if si_cntr_num == 1 then
                    -- 这种情况第一次出现在巨星二期的料箱库项目中
                    nRet, strRetInfo = calculate_bin_replenishment_qty( strLuaDEID, pac_cfg, item, ret_attr[1], supplement_cntr_list )
                    if nRet ~= 0 then
                        return 1, strRetInfo
                    end
                else
                    -- 把所有可以进行补料的料箱呼出进行补料
                    for _, attr in ipairs( ret_attr ) do
                        nRet, strRetInfo = calculate_bin_replenishment_qty( strLuaDEID, pac_cfg, item, attr, supplement_cntr_list )
                        if nRet ~= 0 then
                            return 1, strRetInfo
                        end
                        if item.ok then
                            break
                        end
                    end
                end
            end
        else
            -- 考虑巷道均衡
            local cntr_list = {}
            nRet, cntr_list = wms_base.Get_Matching_cntr_list( strLuaDEID, pac_cfg, strTable, strAttrs, 9, strCondition, strOrder)
            if nRet ~= 0 then
                return 1, "获取所有符合条件的料箱失败! "..cntr_list
            end
            -- 获取空托盘
            for _, empty_cntr in ipairs( cntr_list ) do
                nRet, strRetInfo = calculate_bin_replenishment_qty( pac_cfg, item, empty_cntr.attrs, supplement_cntr_list )
                if nRet ~= 0 then
                    return 1, strRetInfo
                end
                if item.ok then
                    break
                end
            end
        end
    end
    return 0, supplement_cntr_list
end

-- 将呼出料箱中合并过的货品按合并前的原始货品进行批分（拆分合并的 SKU）
-- @function split_merge_item
-- @tparam table out_cntr_list 呼出的料箱列表
-- @tparam table item_list_bak 合并前的原始 item_list，以 row 为索引的数组
local function split_merge_item( out_cntr_list, item_list_bak )
    for _, out_cntr in ipairs( out_cntr_list ) do
        local split_cell_list = {}
        for _, cell in ipairs( out_cntr.cell_list ) do
            if cell.sku.is_qty_merge then
                -- 如果有货品是合并的，需要根据合并前的货品进行批分
                local alloc_qty = cell.qty
                local need_qty

                for _, row in ipairs( cell.sku.detail_row_list ) do
                    local item = lua.table_deepcopy( item_list_bak[row] )
                    need_qty = item.qty - item.alloc_qty
                    if need_qty > 0 then
                        if need_qty > alloc_qty then
                            need_qty = alloc_qty
                        end
                        item_list_bak[row].alloc_qty = item_list_bak[row].alloc_qty + need_qty
                        alloc_qty = alloc_qty - need_qty
                        
                        --local cell_item = lua.table_deepcopy( cell )
                        -- 用字段级拷贝替代 deepcopy，避免 cell.sku → item.cntr_cell_list 环引用导致栈溢出
                        -- cell_item.sku 会在下面立即覆盖，无需深拷贝
                        local cell_item = {
                            cntr_code = cell.cntr_code,
                            cell_type = cell.cell_type,
                            cell_no = cell.cell_no,
                            item_code = cell.item_code,
                            item_name = cell.item_name,
                            wms_bn = cell.wms_bn,
                            entry_batch_no = cell.entry_batch_no or "",
                            sum_volume = cell.sum_volume,
                            sum_weight = cell.sum_weight,
                            weight = cell.weight,
                            volume = cell.volume,
                        }      
                        
                        item.qty = need_qty
                        cell_item.sku = item
                        cell_item.row = row
                        cell_item.qty = need_qty
                        table.insert( split_cell_list, cell_item )
                        if alloc_qty == 0 then
                            break
                        end
                    end
                end
            end
        end

        -- 删除有合并货品的料格
        for i = #out_cntr.cell_list, 1, -1 do
            if out_cntr.cell_list[i].sku and out_cntr.cell_list[i].sku.is_qty_merge then
                table.remove( out_cntr.cell_list, i )
            end
        end     

        -- 把批分好的cell_item插入out_cntr.cell_list
        for _, cell in ipairs(split_cell_list) do
            table.insert( out_cntr.cell_list, cell )
        end
    end
end

--[[
    料箱料格类型根据 SKU 中的 S_CELL_TYPE 获取
    DMG 是指根据SKU中的S_CELL_TYPE确定料箱格和最大转载数量

    输入参数: pac_cfg = {
                wh_code, area_code  仓库，库区编码
                station 站台
                bs_type 来源类型：入库单、入库波次
                bs_no 来源单号   
                aisle_lb -- 巷道均衡，0 不考虑 1 -- 任务均衡 

                aisle -- 可用巷道 'A01',"A02",... 字符串
                cntr_out_op_def = "料箱出库",           --空料箱出库的作业定义
                cntr_back_op_def = "货品入库"           --料箱回库的主业定义       
                          
                -- 容器类型定义
                ctd = {
                    check_capacty = false/true, ---是否检测整箱载重), 
                    load_capacity = 50,         --料箱最大载重
                    si_enable = false/true,                         -- 是否启用补料
                    si_match_attrs = {"S_ITEM_CODE","XX",...}       -- 这些属性一致的可以进行补料
                    si_match_order = "Last_Entry_Batch/QTY_Desc/QTY_Asc"            -- 可以为空
                    si_cntr_num = 0/1                           -- 0 不限制所以可以补料的料箱优先补料， 1 -- 补一个料箱
                    grid_box_def = { { cell_type = "A",volume = 72000, box_num = 1,load_capacity=12},...}
                    have_mixing_rule = false/true  true 表示有混箱规则
                    mixing_attrs = {"A","B"} -- 这些属性一样的可以放一个料箱
                }
                
                -- MDF BY HAN @20260730
                replenish_priority -- bool true 优先补料，默认为true
                no_operation_first -- bool true 优先匹配没有作业的料箱, 默认为true                
            }
            item_list -- 需要预分配料箱的货品列表(注意这里入库的货品的容器类型都一样)
    返回参数:
            supplement_cntr_list, out_cntr_list 为返回值
--]]

-- 料箱预分配主函数（DMG算法）：根据SKU的S_CELL_TYPE确定料箱格和最大转载数量，完成货品到容器的预分配
-- @function wms_pac.Pre_Alloc_Cntr_DMG
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数 
-- @tparam table item_list 需要预分配料箱的货品列表（同一容器类型的货品）
-- @treturn number nRet 0: 成功，1/2: 失败
-- @treturn table/string supplement_cntr_list 成功时返回补料容器列表，失败时返回错误信息
-- @treturn table out_cntr_list 成功时返回呼出的空料箱容器列表
function wms_pac.Pre_Alloc_Cntr_DMG( strLuaDEID, pac_cfg, item_list )
    local nRet, strRetInfo
    local wh_code
    local ctd_code
    local sku_count = #item_list
    local supplement_cntr_list = {}
    local out_cntr_list = {}

    -- step0: 输入参数校验,及初始化
    if sku_count == 0 then
        return 0
    end
    if pac_cfg == nil or type( pac_cfg ) ~= "table" then
        return 2, "Pre_Alloc_Cntr_DMG 函数输入参数错误: pac_cfg 必须有值，必须是 table 类型"
    end
    wh_code = lua.Get_StrAttrValue( pac_cfg.wh_code )
    if wh_code == '' then
        return 2, "Pre_Alloc_Cntr_DMG 函数输入参数错误: pac_cfg 参数中的 wh_code 必须有值!"
    end
    ctd_code = lua.Get_StrAttrValue( pac_cfg.ctd.ctd_code )
    if ctd_code == "" then
        return 2, "Pre_Alloc_Cntr_DMG 算法只适合 Cell_Box 类型的容器进行分配， pac_cfg中的参数  ctd_code 错误!"
    end

    -- V3.0 MDF BY HAN @20260129 item_list 合并有相同补料匹配属性的 SKU
    local merge_item_list = {}
    local item_list_bak = {}
    if pac_cfg.ctd.si_enable and pac_cfg.ctd.si_cntr_num ~= 1 then
        -- 合并相同补料匹配属性的SKU
        nRet, merge_item_list = wms_base.get_merge_item_list( pac_cfg.ctd, item_list )
        if nRet == 0 then
            -- 说明有相同的SKU进行了合并
            for _, item in ipairs( item_list ) do
                -- 备份原始item_list
                item_list_bak[item.row] = item
            end
            item_list = merge_item_list
        end
    end    

    -- step1 计算补料呼出料箱
    -- 是否启用补料呼出
    local have_si_empty_cell = false        -- 补料呼出料箱中是否还有空料格
    local pac_is_ok = false                 -- 预分配操作已经完成

    -- 如果要做没作业的容器优先，需要先装载当前正在作业状态的料箱
    local in_op_cntr_list = {}  -- 在作业里的料箱
    if pac_cfg.no_operation_first then
        in_op_cntr_list, strRetInfo = wms_cntr._Get_Bin_Under_Operation( strLuaDEID, wh_code )
        if in_op_cntr_list == nil then
            return 1, "获取正在作业的料箱失败!"..strRetInfo
        end
    end
    
    -- 容器定义中允许补料箱
    -- 注意：补料箱时不考虑巷道均衡
    if pac_cfg.ctd.si_enable and pac_cfg.replenish_priority then
        -- step1.1 计算可以进行补料的料箱
        if pac_cfg.no_operation_first then
            -- 补料的料箱如果有作业，则不进行补料
            local si_cntr_list = {} 
            nRet, si_cntr_list = wms_pac.get_replenishment_cntr_list( strLuaDEID, pac_cfg, item_list )
            if nRet ~= 0 then 
                return 2, si_cntr_list  
            end         
            for _, si_cntr in ipairs( si_cntr_list ) do
                if not lua.IsInTable( si_cntr.cntr_code, in_op_cntr_list ) then
                    table.insert( supplement_cntr_list, si_cntr )
                end                
            end
        else
            nRet, supplement_cntr_list = wms_pac.get_replenishment_cntr_list( strLuaDEID, pac_cfg, item_list )
            if nRet ~= 0 then 
                return 2, supplement_cntr_list  
            end
        end
        -- step1.2 设置补料料箱中的空料格列表
        nRet, have_si_empty_cell = wms_pac.set_replenishment_cntr_emptycell( strLuaDEID, supplement_cntr_list )
        if nRet ~= 0 then
            return 2, have_si_empty_cell
        end
        -- step1.3 检查补料箱中是否和合适料格做预分配        
        if not wms_base.item_list_is_all_ok( item_list ) and have_si_empty_cell then
            for _, sku in ipairs( item_list ) do
                if sku.qty > sku.alloc_qty then
                    for _, si_cntr in ipairs( supplement_cntr_list ) do
                        nRet, strRetInfo = wms_pac.pre_alloc_sku_to_out_cntr( strLuaDEID, pac_cfg, sku, si_cntr )
                        if nRet ~= 0 then
                            return 1, strRetInfo
                        end
                        if sku.ok then
                            break
                        end
                    end
                end
            end
            -- 删除 empty_cell_list 中已经分配出去的料格，返回 supplement_cntr_list 是否还有空料格
            have_si_empty_cell = wms_pac.reset_empty_cell_info( supplement_cntr_list )
        end

        -- 判断是否已经完成预分配
        pac_is_ok = wms_base.item_list_is_all_ok( item_list )
    end
    
    -- step2 遍历item_list计算适配空料箱
    if not pac_is_ok then
        -- 继续呼出料箱
        nRet, strRetInfo = get_out_cntr_list_dmg( strLuaDEID, pac_cfg, item_list, in_op_cntr_list, out_cntr_list )
        if nRet ~= 0 then 
            return 2, strRetInfo  
        end
    end

    -- step3 检查是否所以货品都已经预分配了料箱，
    local msg_list = {}                         -- 保存无法分配料格的货品数量
    for _, sku in ipairs( item_list ) do
        if sku.ok == false then
            local qty = sku.qty-sku.alloc_qty
            local msg = "系统没有匹配到货品编码 = '"..sku.S_ITEM_CODE.."'的适配料箱进行预分配, 货品的适配料格类型 = '"..sku.S_CELL_TYPE.."', 数量 = "..qty
            table.insert( msg_list, msg )
        end
    end   
    if #msg_list > 0 then
        -- 这些货品没有合适的料箱
        return 1,  lua.table2str( msg_list )
    end    

    -- 如果入库货品清单有数量合并过，最后需要进行批分
    if not lua.isTableEmpty( item_list_bak ) then
        -- 说明Pre-Alloction前是合并过数量的货品清单，需要进行批分
        -- 把呼出料箱里的有合并的货品拆分
        split_merge_item( supplement_cntr_list, item_list_bak )
        split_merge_item( out_cntr_list, item_list_bak )
    end 
    return 0, supplement_cntr_list, out_cntr_list
end

return wms_pac