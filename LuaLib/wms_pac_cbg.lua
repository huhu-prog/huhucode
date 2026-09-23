--[[
    编码: 
    名称: 预分配料箱算法
    作者：HAN  
    创建日期：2024-8-5
    修改日期：2026-6-18
    来源：巨星料箱库
    
    算法标识 CBG -- Compatible Bin Grid 专指WMS中与物料存储适配的料格系统
            料格可以装载货品数量通过体积和料格体积或，重量和料箱的最大载重进行计算得到
            算法特点：
            -- 尽量有大一些的料格装更多的货品，减少入库任务条数（提高入库操作效率）
    功能:
         空料箱呼出算法，货物可以适配多种类型料箱，根据入库的总体积进行计算

  
    【预分配料箱】
        Release_Pre_Alloc_Cntr    — 释放预分配的料格
        Pre_Alloc_Cntr_CBG        — CBG模式的料箱格预分配主函数
        Pre_Alloc_Cntr            — 预分配料箱（外部调用）

     -------------------------------------------------------------------------------------------------------------------------
    几个主要参数的定义
    1)  item_list -- 入库货品清单
            { 
                item_code -- SKU编码 
                volume -- 单个体积  
                weight -- 单个重量 
                item_name,
                cell_type:"A/B/C/D/E"   -- 货品最小适配料格类型
                qty -- 计划入库数量
                alloc_qty -- 已经安排料箱的货品数量
                cntr_cell_list -- 已经配货的料格 { cntr_code:"", cell_no:"", item_code:"xx", item_name:"", entry_batch_no:"SN01", 
                                                  weight, volume, qty:10 ,sum_volume:10, sum_weight:10}
                empty_cell_type -- Q 数量的空料格类型 辅助用，表示本次整体呼出的空料箱类型
                Q -- 需要呼出空料格数量
            }
    2)  supplement_cntr_list  -- 补料呼出的料箱
            {
                cntr_code:"xxx"
                cell_type:"A/B/C/D/E"
                cntr_good_weight: 100                        -- 容器中货品重量
                full: false/true,
                empty_cell_num: 0,
                empty_cell_list:[{"cell_no"，item_code, item_name}]           -- 呼出的补料料箱中的空料格 cell 属性同下面的 cell_list
                cell_list:{
                    { cntr_code:"", cell_no:"", item_code:"xx", item_name:"", entry_batch_no:"SN01", weight, volume, qty:10 ,sum_volume:10, sum_weight:10}
                }
            }
    3）  out_cntr_list  -- 呼出的空料箱( 和 supplement_cntr_list 是一样的)
            {
                cntr_code = "XXX",
                cell_type = "A/B/C/D/E",                
                cntr_good_weight = 0,
                full = false,
                empty_cell_num = 0,
                empty_cell_list:[{"cell_no"，item_code, item_name}] 
                cell_list:{     -- 分配货品的料格
                    { cntr_code:"", cell_no:"", item_code:"xx", item_name:"", entry_batch_no:"SN01", weight, volume, qty:10 ,sum_volume:10, sum_weight:10}
                }
            }   
    
    更改记录:
        V2.0 HAN 20241030 取消给容器加锁
        V3.0 HAN 20241104 升格处理改进
        V4.0 HAN 20241108 补料呼出料箱和空料箱进行检查，相同料箱号的合并
        V2.0 HAN 20241220 对升格进行提前处理，加了一个专门的升格链表
        V3.0 HAN 20260131 在预分配料箱前先把相同的货品进行合并数量，预分配好后再进行拆分

    AI CHECK:
        -- 20260618
]]

local wms_cntr = require( "wms_container" )
-- wms_pac_dmg 是制定料箱类型的精准预分配方法，属于 pre-alloction container 的一种，先require
local wms_pac = require( "wms_pac_dmg" )
local wms_pac_ffd = require ("wms_pac_ffd")

-- 释放预分配的料格
-- @function Release_Pre_Alloc_Cntr
-- @tparam string strLuaDEID Lua引擎ID
-- @tparam string bs_type 来源类型：入库单、入库波次
-- @tparam string bs_no 来源单号
-- @treturn int nRet 0成功，1失败
-- @treturn string|nil 错误信息，成功时nil
function wms_pac.Release_Pre_Alloc_Cntr( strLuaDEID, bs_type, bs_no )
    local nRet, strRetInfo
    local data_objs
    if lua.StrIsEmpty( bs_type ) then
        return 1, "Release_Pre_Alloc_Cntr 函数中 bs_type 必须有值"
    end
    if lua.StrIsEmpty( bs_no ) then
        return 1, "Release_Pre_Alloc_Cntr 函数中 bs_no 必须有值"
    end    
    -- 释放预分配的料格数量
    local strCondition = "S_BS_TYPE = '"..bs_type.."' AND S_BS_NO = '"..bs_no.."'"
    nRet, data_objs = m3.QueryDataObject(strLuaDEID, "Pre_Alloc_CNTR_Detail", strCondition, "S_CNTR_CODE" )
    if nRet ~= 0 then 
        return 1, "QueryDataObject失败!"..data_objs
    end
    if data_objs ~= ''  then 
        local pac_detail
        local cntr_list = {}
        local find
        for n = 1, #data_objs do
            pac_detail = m3.KeyValueAttrsToObjAttr(data_objs[n].attrs)
            if pac_detail == nil then
                return 1, "KeyValueAttrsToObjAttr 失败!"..data_objs[n].attrs
            end
            find = false
            local cell = { cell_no = pac_detail.S_CELL_NO }            
            for m = 1, #cntr_list do
                if cntr_list[m].cntr_code == pac_detail.S_CNTR_CODE  then
                    find = true
                    table.insert( cntr_list[m].cell_list, cell )
                    break
                end
            end
            if find == false  then
                local cntr = {
                    cntr_code = pac_detail.S_CNTR_CODE,
                    cell_list = {}
                }
                table.insert( cntr.cell_list, cell )
                table.insert( cntr_list, cntr )
            end
        end
        local cell_num
        for m = 1, #cntr_list do
            strCondition = "S_CODE = '"..cntr_list[m].cntr_code.."'"
            cell_num = #cntr_list[m].cell_list
            nRet, strRetInfo = mobox.decDataObjAccQty( strLuaDEID, "Container", strCondition, "N_ALLOC_CELL_NUM", cell_num )
            if nRet ~= 0 then 
                return 1, "decDataObjAccQty(Container)失败! "..strRetInfo
            end            
        end
        --[[
        -- 把料格状态=3（预约）的设置为 0
        local strUpdateSql = "N_EMPTY_FULL = 0, S_ALLOC_OP_CODE = ''"
        strCondition = "N_EMPTY_FULL = 3 AND S_ALLOC_OP_CODE = '"..bs_no.."'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Container_Cell", strCondition, strUpdateSql )
        if nRet ~= 0  then  
            lua.Stop( strLuaDEID, "更新【Container_Cell】状态信息失败!"..strRetInfo ) 
            return
        end  
        --]]
        local inv_exist, cell_empty_full, strUpdateSql
        for _, cntr in ipairs( cntr_list ) do
            for _, cell in ipairs( cntr.cell_list ) do
                strCondition = "S_CNTR_CODE = '"..cntr.cntr_code.."' AND S_CELL_NO = '"..cell.cell_no.."'"
                nRet, inv_exist = m3.ExistThisDataByCondition( strLuaDEID, "INV_Detail", strCondition )
                if nRet ~= 0 then
                    return 1, "检查码盘容器是否有库存时,出现错误!"..inv_exist 
                end
                cell_empty_full = 0
                if inv_exist then
                    cell_empty_full = 1
                end

                strUpdateSql = "N_EMPTY_FULL = "..cell_empty_full..", S_ALLOC_OP_CODE = ''"
                strCondition = "S_CNTR_CODE = '"..cntr.cntr_code.."' AND S_CELL_NO = '"..cell.cell_no.."'"
                nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Container_Cell", strCondition, strUpdateSql )
                if nRet ~= 0  then  
                    return 1, "更新【Container_Cell】状态信息失败!"..strRetInfo
                end                 
            end
        end
    end    
    return 0
end

-- item list 排序函数 把体积大的排前面
-- @function item_sort_volume
-- @tparam table item_a 货品A
-- @tparam table item_b 货品B
-- @treturn bool 体积大的返回true
local function item_sort_volume( item_a, item_b )
    return item_a.volume > item_b.volume
end

-- 根据货品体积计算需要多少个料格
-- @function calculate_box_count_by_volume
-- @tparam int box_volume 料格体积
-- @tparam int item_volume 货品单个体积
-- @tparam int qty 货品数量
-- @treturn int 料格数量
-- @treturn int 可装货品数量
local function calculate_box_count_by_volume(box_volume, item_volume, qty )
    
    if 0 == item_volume or 0 == box_volume then
        return 0,0
    end
    local items_per_box = math.floor( box_volume / item_volume )
    -- 单品就超体积，这种情况一般是数据错误
    if items_per_box == 0 then
        return 0,0
    end
    local num_boxes = math.floor( qty / items_per_box)
    return num_boxes, num_boxes*items_per_box
end

-- 根据货品重量计算需要多少个料格
-- @function calculate_box_count_by_weight
-- @tparam table pac_cfg 预分配配置参数
-- @tparam int cell_type_index 料格类型索引
-- @tparam int item_weight 货品单个重量
-- @tparam int qty 货品数量
-- @treturn int 料格数量
-- @treturn int 可装货品数量
local function calculate_box_count_by_weight( pac_cfg, cell_type_index, item_weight, qty )
    if 0 == item_weight then
        return 0,0
    end
    local items_per_box = math.floor( pac_cfg.ctd.load_capacity / item_weight )
    -- 单品就超重，这种情况一般是数据错误
    if items_per_box == 0 then
        return 0,0
    end
    local num_boxes = math.floor( qty / items_per_box)
    return num_boxes*pac_cfg.ctd.grid_box_def[cell_type_index].box_num, items_per_box*num_boxes
end

-- 计算出item中每种料格类型需要的空料格数量
-- @function generate_item_needemptycell_qty
-- @tparam table ctd 容器类型定义
-- @tparam table item_list 入库货品清单
-- @tparam table grid_def 料格定义 {cell_type, box_num, volume}
-- @treturn int nRet 0成功，1失败
-- @treturn int|string sum_Q 呼出料格总数，失败时为错误信息
local function generate_item_needemptycell_qty( ctd, item_list, grid_def )
    local nRet
    local qty, total_volume, volumeX, pk_qty, qX
    local cell_volume = grid_def.volume or 0
    local box_num = grid_def.box_num or 0
    if box_num <= 0 then
        return 1,"料箱类型定义中料格定义不合规! box_num 必须大于0"
    end        

    local cell_type = grid_def.cell_type
    local sum_Q = 0
    local loading_limit, next_grid_def
    if cell_volume == nil or cell_volume <= 0  then
        return 1,"料箱类型定义中料格定义不合规! 料格体积必须大于0"
    end
    
    for n = 1, #item_list do
        -- MDY BY HAN 20241211 如果当前进行匹配的料格类型 大于 货品的最小适配料格（A,B,C,D,E），不做判断
        if cell_type > item_list[n].S_CELL_TYPE then
            goto continue
        end
        item_list[n].empty_cell_type = cell_type        -- 当前呼出的料箱规格
        item_list[n].Q = 0                              -- cell_type 类型的料格数量
        if item_list[n].qty > item_list[n].alloc_qty  then
            qty = item_list[n].qty - item_list[n].alloc_qty
            if lua.equation( qty, 0 ) then
                goto continue
            end
          
            -- 根据容器定义中的计数方法进行判断 Mixed 为混合模式，会从根据情况从体积计算变成重量计算
            if ctd.count_method == "Mixed" or ctd.count_method == "Volume" then
                 -- *** 注意这里还留下一个问题，就是重量是否会超，可能要对 calculate_box_count_by_volume 优化一下
                total_volume = qty*item_list[n].volume
                pk_qty = 0
                if total_volume > cell_volume  then
                    item_list[n].Q, pk_qty = calculate_box_count_by_volume( cell_volume, item_list[n].volume, qty )
                    volumeX = (item_list[n].volume)*(qty-pk_qty)
                else
                    volumeX = total_volume
                end
                -- 如果整除后还有余数, 判断这些体积是否增加一个料格
                if volumeX > 0  then
                    -- 如果料格在料箱中最小的料格说明不能再降格了
                    if item_list[n].S_CELL_TYPE == cell_type or grid_def.is_smallest  then
                        item_list[n].Q = item_list[n].Q + 1
                    else
                        -- 2024-9-28 改进
                        -- 如果剩余体积 > 降格后料格体积 Q需要加1
                        nRet, next_grid_def = wms_cntr.Get_CTD_Next_GridDef( ctd, cell_type )
                        if nRet ~= 0 or next_grid_def == nil then
                            return 1, "wms_cntr.Get_CTD_Next_GridDef 失败!"..next_grid_def
                        end
                        if volumeX > next_grid_def.volume  then
                            item_list[n].Q = item_list[n].Q + 1
                        end
                    end
                end
            elseif ctd.count_method == "Limit" then
                -- 获取 SKU 在 grid_def.cell_type 的料格中的装载数量
                nRet, loading_limit = wms_base.GetSKU_LoadingLimit( item_list[n], ctd.ctd_code, grid_def.cell_type )
                if nRet ~= 0  then
                    return 1, loading_limit
                end
                -- qX 为余数
                if qty >= loading_limit then
                    item_list[n].Q = math.floor(qty/loading_limit) 
                    qX = qty - item_list[n].Q*loading_limit
                else
                    qX = qty
                end
                if qX > 0 then
                    -- 如果料格在料箱中最小的料格说明不能再降格了
                    if item_list[n].S_CELL_TYPE == cell_type or grid_def.is_smallest  then
                        item_list[n].Q = item_list[n].Q + 1
                    else
                        -- 如果剩余体积 > 降格后料格数量
                        nRet, next_grid_def = wms_cntr.Get_CTD_Next_GridDef( ctd, cell_type )
                        if nRet ~= 0 or next_grid_def == nil then
                            return 1, "wms_cntr.Get_CTD_Next_GridDef 失败!"..next_grid_def
                        end
                        nRet, loading_limit = wms_base.GetSKU_LoadingLimit( item_list[n], ctd.ctd_code, next_grid_def.cell_type )
                        if nRet ~= 0  then
                            return 1, loading_limit
                        end
                        if qX > loading_limit  then
                            item_list[n].Q = item_list[n].Q + 1
                        end
                    end
                end                    
            else
                return 1, "料箱计数方法 = '"..ctd.count_method.."'的算法还没实现!"
            end
            -- 计算呼出料格总数
            sum_Q = sum_Q + item_list[n].Q
        end
        ::continue::
    end
    return 0, sum_Q
end

-- 检查 item_list 中的item是否有SKU的最低适配货隔（cell_type） 并且料格还可以继续存储货品
-- @function have_this_cell_type
-- @tparam table item_list 入库货品清单
-- @tparam string cell_type 料格类型
-- @treturn bool 有需求返回true
-- @treturn int 货品在item_list中的下标，无则为0
local function have_this_cell_type( item_list, cell_type )

    for n = 1, #item_list do
        if item_list[n].ok == false and item_list[n].S_CELL_TYPE == cell_type  then
            if item_list[n].qty > item_list[n].alloc_qty  then
                if lua.equation( item_list[n].qty, item_list[n].alloc_qty ) == false  then
                    return true, n
                end
            end
        end
    end
    return false, 0
end

-- 把空料格数量小的排前面
-- @function empty_cntr_sort
-- @tparam table item_a 料箱A
-- @tparam table item_b 料箱B
-- @treturn bool 空料格少的返回true
local function empty_cntr_sort( item_a, item_b )
    return item_a.empty_cell_num < item_b.empty_cell_num
end

-- 检查料箱是否已在呼出列表中
-- @function cntr_in_this_list
-- @tparam string cntr_code 料箱编码
-- @tparam table out_cntr_result 已呼出的料箱列表
-- @treturn bool 已在列表中返回true
local function cntr_in_this_list( cntr_code, out_cntr_result )
    if nil == out_cntr_result then
        return false
    end

    for  n = 1, #out_cntr_result do
        if out_cntr_result[n].cntr_code == cntr_code then
            return true
        end
    end
    return false
end

--[[ ***
    呼出 cell_need_num 个 cell_type 类型的空料格，需要多少个料箱
    从数据库查询获取 料箱类型 = cell_type 有空料格的料箱列表，并且根据空料格数量的大小进行排序，空料格数量大的在最前面
    输入参数:  
        pac_cfg -- 预分配配置参数
        cell_type 呼出料箱类型
        cell_need_num 需要呼出多少个料格
        out_cntr_list 呼出料箱列表, 是本函数计算后的主要成果
        query_cntr_list -- 除 out_cntr_list 外可用的料箱，用于 out_cntr_list 在分配货物是因为重量的原因不能使用需要分配新的料箱
        out_cntr_result -- 已经呼出的料箱
    返回3个参数，格式（nRet,x_sum_Q, strErrInfo ）
    nRet 0 正常 1 -- 无法匹配需求 2 -- 程序错误
    x_sum_Q 呼出的料格缺少的cell_type类型的料格数量
-- @function generate_out_cntr_list
-- @tparam string strLuaDEID Lua引擎ID
-- @tparam table pac_cfg 预分配配置参数
-- @tparam string cell_type 呼出料箱类型
-- @tparam int cell_need_num 需要呼出多少个料格
-- @tparam table out_cntr_list 呼出料箱列表（本函数计算后的主要成果）
-- @tparam table query_cntr_list 除out_cntr_list外可用的料箱
-- @tparam table out_cntr_result 已经呼出的料箱
-- @treturn int nRet 0正常 1无法匹配需求 2程序错误
-- @treturn int|string x_sum_Q 缺少的料格数量 / 错误信息
]]
local function generate_out_cntr_list( strLuaDEID, pac_cfg, cell_type, cell_need_num, out_cntr_list, query_cntr_list, out_cntr_result )
    local nRet, strCondition, strOrder
    
    local str_loc_where = "C_ENABLE = 'Y' AND S_WH_CODE = '"..pac_cfg.wh_code.."'"
    if pac_cfg.area_code ~= nil and pac_cfg.area_code ~= '' then
        str_loc_where = str_loc_where.." AND S_AREA_CODE = '"..pac_cfg.area_code.."'"
    end
    if pac_cfg.aisle ~= nil and pac_cfg.aisle ~= '' then
        str_loc_where = str_loc_where.." AND S_AISLE_CODE IN ("..pac_cfg.aisle..")"
    end
    local cntr_max_weight = pac_cfg.ctd.load_capacity   
    local strTable = "TN_Container a INNER JOIN TN_Loc_Container b ON a.S_CODE = b.S_CNTR_CODE "..
                     "INNER JOIN TN_Location c ON b.S_LOC_CODE = c.S_CODE "    
    local cntr_condition = " a.S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."'"
    -- N_EMPTY_FULL < 2 料箱未满
    if pac_cfg.dbtype == DB_TYPE.SQLServer then
        strCondition = "a.N_EMPTY_CELL_NUM > a.N_ALLOC_CELL_NUM AND a.S_SPEC = '"..cell_type.."' AND a.N_LOCK_STATE = 0 AND a.C_ENABLE = 'Y' AND "..cntr_condition.." AND a.N_EMPTY_FULL < 2 AND a.N_EMPTY_CELL_NUM > 0 "..
                       " AND a.S_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where "..str_loc_where..")) "
    else
        strCondition = "a.N_EMPTY_CELL_NUM > a.N_ALLOC_CELL_NUM AND a.S_SPEC = '"..cell_type.."' AND a.N_LOCK_STATE = 0 AND a.C_ENABLE = 'Y' AND "..cntr_condition.." AND a.N_EMPTY_FULL < 2 AND a.N_EMPTY_CELL_NUM > 0 "..
                       " AND a.S_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where "..str_loc_where..")) "
    end
    if pac_cfg.ctd.check_capacity then    
        if cntr_max_weight <= 0 then
            return 1, "容器类型定义'"..pac_cfg.ctd.ctd_code.."'中缺少容器载重参数!"
        end           
        strCondition = strCondition.." AND a.F_GOOD_WEIGHT < "..cntr_max_weight
    end
    strOrder = "(a.N_EMPTY_CELL_NUM - a.N_ALLOC_CELL_NUM) desc"
    local strAttrs = "a.S_CODE, c.S_AISLE_CODE, a.N_EMPTY_CELL_NUM, a.N_ALLOC_CELL_NUM, a.F_GOOD_WEIGHT"
    
    local cntr_list = {}
    nRet, cntr_list = wms_base.Get_Matching_cntr_list( strLuaDEID, pac_cfg, strTable, strAttrs, 2, strCondition, strOrder)
    if nRet ~= 0 then
        return 1, "获取所有符合条件的料箱失败! "..cntr_list
    end
    if #cntr_list == 0 then 
        return 0, cell_need_num, "没找到匹配的料箱" 
    end
    local empty_cell_num, qty
    local empty_cntr_list = {}
    local query_cntr_count = 0          -- 这样的箱子不需要太多不超过100
    local aisle_code = ''
    query_cntr_list = {}                -- 查询出来的符合条件的料箱
    for _, cntr in ipairs(cntr_list) do
        local cntr_attr = {
            S_CODE = cntr.attrs[1],
            N_EMPTY_CELL_NUM = cntr.attrs[3],
            N_ALLOC_CELL_NUM = cntr.attrs[4],
            F_GOOD_WEIGHT = cntr.attrs[5]
        }
        aisle_code = cntr.attrs[2]
        -- 防止找到的料箱已经在呼出的料箱列表中
        if cntr_in_this_list( cntr_attr.S_CODE, out_cntr_result )  then 
            goto continue 
        end
        if cell_need_num > 0  then
            -- 呼出料箱空料格数量
            empty_cell_num = lua.StrToNumber( cntr_attr.N_EMPTY_CELL_NUM ) - lua.StrToNumber( cntr_attr.N_ALLOC_CELL_NUM )
            if cell_need_num > empty_cell_num  then
                qty = empty_cell_num
            else
                -- 特别关注: 需要找到最适配的料箱 cell_need_num = empty_cell_num 是最优的
                if cell_need_num == empty_cell_num  then
                    qty = cell_need_num
                else
                    -- 把当前这个料箱加到附加链表, 没找到最优数量的料格后会从这个 empty_cntr_list 里获取
                    local empty_cntr = {
                        cntr_code = cntr_attr.S_CODE,
                        cntr_good_weight = lua.StrToNumber( cntr_attr.F_GOOD_WEIGHT ), 
                        empty_cell_num = empty_cell_num,
                        aisle_code = aisle_code
                    }
                    table.insert( empty_cntr_list, empty_cntr )
                    goto continue
                end
            end
            --  分配成功, 把这个料箱加入呼出料箱列表
            local out_cntr = {
                cntr_code = cntr_attr.S_CODE,
                cntr_good_weight = lua.StrToNumber( cntr_attr.F_GOOD_WEIGHT ),
                cell_type = cell_type,
                empty_cell_list = {},
                full = false,
                cell_list = {}
            }
            table.insert( out_cntr_list, out_cntr )
            if pac_cfg.aisle_lb == 1 then
                wms_base.Add_Aisle_Task_Num( pac_cfg.aisle_set, aisle_code )
            end
            cell_need_num = cell_need_num - qty
        else
            -- query_cntr_list 是候补
            local out_cntr = {
                cntr_code = cntr_attr.S_CODE,
                cntr_good_weight = lua.StrToNumber( cntr_attr.F_GOOD_WEIGHT ),
                cell_type = cell_type,
                empty_cell_list = {},
                full = false,
                aisle_code = aisle_code,
                cell_list = {}
            }
            table.insert( query_cntr_list, out_cntr )
            query_cntr_count = query_cntr_count + 1
            if query_cntr_count > 100 then
                break
            end
        end
        ::continue::
    end
    
    -- 如果还有 cell_need_num 没分配， 从上面为了适配料格数量跳过的哪些料格
    if cell_need_num > 0 and #empty_cntr_list > 0  then
        table.sort( empty_cntr_list, empty_cntr_sort )
        -- 取第一个空料箱（这个是空料箱数最接近cell_need_num）
        local out_cntr = {
            cntr_code = empty_cntr_list[1].cntr_code,
            cntr_good_weight = empty_cntr_list[1].cntr_good_weight,
            cell_type = cell_type,
            empty_cell_list = {},
            full = false,
            cell_list = {}
        }
        table.insert( out_cntr_list, out_cntr )
        if pac_cfg.aisle_lb == 1 then
            wms_base.Add_Aisle_Task_Num( pac_cfg.aisle_set, empty_cntr_list[1].aisle_code )
        end
        for n = 2, #empty_cntr_list do
            if query_cntr_count > 100 then
                break
            end
            local out_cntr = {
                cntr_code = empty_cntr_list[n].cntr_code,
                cntr_good_weight = empty_cntr_list[n].cntr_good_weight,
                cell_type = cell_type,
                empty_cell_list = {},
                full = false,
                aisle_code = empty_cntr_list[n].aisle_code,
                cell_list = {}
            }
            table.insert( query_cntr_list, out_cntr )  
            query_cntr_count = query_cntr_count + 1       
        end
        cell_need_num = 0         
    end
    return 0, cell_need_num
end

-- 默认的入库批次编码生成函数   
local function generate_batch_no( item_code )
    local nRet, strRetInfo

    if item_code == '' or item_code == nil then 
        return 1, "generate_batch_no 输入参数必须有值" 
    end
    local strCode = ''
    local strHeader = item_code..'_'..os.date("%y%m%d")..'-'
    nRet, strCode = mobox.getSerialNumber( "Inbound_Batch", strHeader, 3 )  
    if nRet ~= 0 then 
        return 2,  '申请入库批次号失败!'..strCode 
    end
    local seg = lua.split( strCode, "_" )
    return 0, seg[2]
end

-- 通过调用外部函数生成入库序列号
-- @function get_wms_sn
-- @tparam table pac_cfg 预分配配置参数
-- @tparam string item SKU对象
-- @treturn int nRet 0成功，非0失败
-- @treturn string|nil 错误信息，成功时入库序列号
local function get_wms_sn( pac_cfg, item )
    if pac_cfg.get_wms_sn_func == nil or lua.IsTableEmpty(pac_cfg.get_wms_sn_func) then
        local nRet, wms_sn = generate_batch_no( item.S_ITEM_CODE )
        return nRet, wms_sn
    else
        -- 有特殊生成入库序列号的函数
        local module = pac_cfg.get_wms_sn_func.module_name or ''
        local function_name = pac_cfg.get_wms_sn_func.function_name or ''
        local nRet, wms_sn = lua.callFunctionByName( module, function_name, item )
        if nRet ~= 0 then
            return 1, wms_sn
        end
        return 0, wms_sn
    end
end



-- 在呼出的空料箱里分配货物, 遍历 item_list 把item_list的货品批分到 呼出的空料箱中，空料箱资源是 out_cntr_list
-- @function distribute_to_outcntrlist
-- @tparam string strLuaDEID Lua引擎ID
-- @tparam table pac_cfg 预分配配置参数
-- @tparam table item_list 入库货品清单
-- @tparam table out_cntr_list 呼出料箱列表
-- @tparam string cell_type 料格类型
-- @treturn int nRet 0成功，非0失败
-- @treturn string|nil 错误信息，成功时nil
local function distribute_to_outcntrlist( strLuaDEID, pac_cfg, item_list, out_cntr_list, cell_type )
    local nRet, strRetInfo, nCount, strSN, qty, si_qty
    local empty_cell_count
    nCount = #item_list
    if nCount == 0 then
        return 0
    end
    -- m 是呼出的料箱列表下标
    for m = 1, #out_cntr_list do
        empty_cell_count = lua.GetTableCount( out_cntr_list[m].empty_cell_list )
        if empty_cell_count > 0  then
            -- 遍历item_list n 是货品列表下标
            for n = 1, nCount do
                -- > 0 说明有cell_type类型的料箱格需求
                if item_list[n].ok == false and item_list[n].Q > 0 and item_list[n].empty_cell_type == cell_type  then
                    -- 遍历呼出的空料箱里的空料格
                    for i = 1, empty_cell_count do
                        if out_cntr_list[m].empty_cell_list[i].item_code == ''  then
                            -- 取一个空料格存储计算能存储多少个货品
                            local cntr_cell = {}
                            cntr_cell.cntr_code = out_cntr_list[m].cntr_code
                            cntr_cell.cell_no = out_cntr_list[m].empty_cell_list[i].cell_no
                            cntr_cell.good_volume = 0                      -- 是空料格
                            cntr_cell.cell_type = cell_type
                            nRet, si_qty = wms_cntr.Get_CntrCell_Goods_Qty( pac_cfg.ctd, out_cntr_list[m].cntr_good_weight, cntr_cell, item_list[n] )
                            if nRet ~= 0  then 
                                return 1, si_qty 
                            end 
                            qty = item_list[n].qty - item_list[n].alloc_qty
                            if si_qty > qty then
                                si_qty = qty
                            end
                            -- 呼出料箱里加一个料格存储 item
                            if si_qty > 0  then
                                --  生成批次号
                                nRet, strSN = get_wms_sn( item_list[n].S_ITEM_CODE )
                                if nRet ~= 0 then
                                    return 1, strSN
                                end
                                item_list[n].alloc_qty = item_list[n].alloc_qty + si_qty
                                if lua.equation( item_list[n].alloc_qty, item_list[n].qty )  then
                                    item_list[n].ok = true
                                end
                
                                -- 把分配掉的si_qty个货品加到呼出的空料格里
                                local cell_item = {
                                    cntr_code = cntr_cell.cntr_code,
                                    cell_type = cntr_cell.cell_type,
                                    cell_no = cntr_cell.cell_no,
                                    item_code = item_list[n].S_ITEM_CODE,
                                    item_name = item_list[n].S_ITEM_NAME,
                                    row = item_list[n].row,
                                    entry_batch_no = strSN,
                                    qty = si_qty,
                                    sum_volume = si_qty*item_list[n].volume,
                                    sum_weight = si_qty*item_list[n].weight,
                                    weight = item_list[n].weight,
                                    volume = item_list[n].volume,
                                    sku = item_list[n]  
                                }
                                table.insert( out_cntr_list[m].cell_list, cell_item )
                                
                                -- 20241104 容器料格分配数量+1，料格设置为预分配
                                nRet, strRetInfo = wms_cntr.CNTR_cell_alloc_set( strLuaDEID, cntr_cell.cntr_code, cntr_cell.cell_no, pac_cfg.bs_no )
                                if nRet ~= 0 then
                                    return 1, strRetInfo
                                end
                                -- 容器中商品的总重量需要加上刚加入到料格里的货品重量
                                out_cntr_list[m].cntr_good_weight = out_cntr_list[m].cntr_good_weight + cell_item.sum_weight
                                table.insert( item_list[n].cntr_cell_list, cell_item ) 
                                -- empty_cell_list 里item_code 设置为有值，表示这个空料格已经有货
                                out_cntr_list[m].empty_cell_list[i].item_code = item_list[n].S_ITEM_CODE
                                out_cntr_list[m].empty_cell_list[i].item_name = item_list[n].S_ITEM_NAME
                                item_list[n].Q = item_list[n].Q - 1
                            end
                        end
                        if item_list[n].Q <= 0  then
                            break
                        end
                    end                    
                end
            end
        end
    end
    return 0
end

-- 删除呼出容器中的empty_cell 列表中 名为 cell_no 的料格
-- @function remove_empty_cell
-- @tparam table cntr 料箱对象
-- @tparam string cell_no 料格编号
local function remove_empty_cell( cntr, cell_no )
    
    for n = 1, #cntr.empty_cell_list do
        if cntr.empty_cell_list[n].cell_no == cell_no  then
            table.remove( cntr.empty_cell_list, n )
            return 
        end
    end
end

-- 把料箱中已经分配了SKU的空料格删除
-- @function remove_empty_cell_have_item_code
-- @tparam table cntr 料箱对象
local function remove_empty_cell_have_item_code( cntr )
    -- 清除料箱里的空容器列表
    local m = 1
    while cntr.empty_cell_list[m] do
        if cntr.empty_cell_list[m].item_code ~= ''  then
            table.remove( cntr.empty_cell_list, m )
        else
            m = m + 1
        end
    end  
end    
-- 把一个指定的货品批分到呼出容器列表中
-- @function distribute_item_to_out_cntr_list
-- @tparam string strLuaDEID Lua引擎ID
-- @tparam table pac_cfg 预分配配置参数
-- @tparam table item 单个货品
-- @tparam table out_cntr_list 呼出料箱列表
-- @treturn int nRet 0成功，非0失败
-- @treturn string|nil 错误信息，成功时nil
local function distribute_item_to_out_cntr_list( strLuaDEID, pac_cfg, item, out_cntr_list )
    local nRet, strRetInfo, qty, si_qty
    local strSN
    if item.ok then
        return
    end
    for m = 1, #out_cntr_list do
        -- 遍历呼出的空料箱里的空料格
        for i = 1, #out_cntr_list[m].empty_cell_list do
            if out_cntr_list[m].empty_cell_list[i].item_code == ''  then
                -- 取一个空料格存储计算能存储多少个货品
                local cntr_cell = {}
                cntr_cell.cntr_code = out_cntr_list[m].cntr_code
                cntr_cell.cell_no = out_cntr_list[m].empty_cell_list[i].cell_no
                cntr_cell.good_volume = 0                      -- 是空料格
                cntr_cell.cell_type =  out_cntr_list[m].cell_type
                nRet, si_qty = wms_cntr.Get_CntrCell_Goods_Qty( pac_cfg.ctd, out_cntr_list[m].cntr_good_weight, cntr_cell, item )
                if nRet ~= 0  then 
                    return 1, si_qty
                 end 
                qty = item.qty - item.alloc_qty
                if si_qty > qty  then 
                    si_qty = qty 
                end  
                -- 呼出料箱里加一个料格存储 item
                if si_qty > 0  then
                    --  生成批次号
                    nRet, strSN = get_wms_sn( pac_cfg, item )
                    if nRet ~= 0 then
                        return 1, strSN
                    end
                    item.alloc_qty = item.alloc_qty + si_qty
                    if lua.equation( item.alloc_qty, item.qty ) then
                        item.ok = true
                    end
    
                    -- 把分配掉的si_qty个货品加到呼出的空料格里
                    local cell_item = {
                        cntr_code = cntr_cell.cntr_code,
                        cell_type = cntr_cell.cell_type,
                        cell_no = cntr_cell.cell_no,
                        item_code = item.S_ITEM_CODE,
                        item_name = item.S_ITEM_NAME,
                        row = item.row,
                        entry_batch_no = strSN,
                        qty = si_qty,
                        sum_volume = si_qty*item.volume,
                        sum_weight = si_qty*item.weight,
                        weight = item.weight,
                        volume = item.volume,
                        sku = item                                  
                    }
                    table.insert( out_cntr_list[m].cell_list, cell_item )
                    
                    -- 容器料格分配数量+1，料格设置为预分配
                    nRet, strRetInfo = wms_cntr.CNTR_cell_alloc_set( strLuaDEID, cntr_cell.cntr_code, cntr_cell.cell_no, pac_cfg.bs_no )
                    if nRet ~= 0 then
                        return 1, strRetInfo
                    end
                    -- 容器中商品的总重量需要加上刚加入到料格里的货品重量
                    out_cntr_list[m].cntr_good_weight = out_cntr_list[m].cntr_good_weight + cell_item.sum_weight
                    table.insert( item.cntr_cell_list, cell_item ) 
                    -- empty_cell_list 里item_code 设置为有值，表示这个空料格已经有货
                    out_cntr_list[m].empty_cell_list[i].item_code = item.S_ITEM_CODE
                    out_cntr_list[m].empty_cell_list[i].item_name = item.S_ITEM_NAME
                end
            end
            if item.ok then
                break
            end
        end
        remove_empty_cell_have_item_code( out_cntr_list[m] )
        if item.ok then
            break
        end
    end
  
    return 0
end

-- 从已经呼出的料箱列表中分配一个空的料格分配存储货品(item),返回分配后还需要多少料格数量
-- @function alloc_cell_in_out_cntr_list
-- @tparam string strLuaDEID Lua引擎ID
-- @tparam table pac_cfg 预分配配置参数
-- @tparam string cell_type 料格类型
-- @tparam table item 单个货品
-- @tparam int need_q 需要的料格数量
-- @treturn int nRet 0成功，非0失败
-- @treturn string|nil 错误信息，成功时nil

-- out_cntr_list 已经呼出的料箱列表，cell_type 匹配的料格类型， item 分配的货品， need_q 需要的料格数量
local function alloc_cell_in_out_cntr_list( strLuaDEID, pac_cfg, out_cntr_list, cell_type, item, need_q )
    local empty_cell_count, nRet, si_qty
    local alloc_item = false
    local cntr_cell = {}
    local strRetInfo, strSN
    -- 获取料箱混箱规则属性                
    local cntr_mixing_rule = {}
    --[[
    *****
    @20260610 取消这里要获取料箱的混箱属性的值，下面这段代码是有问题的，先取消，这样这里的混箱处理是有问题
    有时间再查一下，这里要获取每个料箱的混箱属性，建议加在 out_cntr_list 中
    for i, attr in ipairs( pac_cfg.ctd.mixing_attrs ) do
        cntr_mixing_rule[attr] = lua.Get_StrAttrValue( call_out_cntr_cell[ext_attr_index+i])
    end
    --]]
    local cntr_good_weight, qty
    for n = 1, #out_cntr_list do
        empty_cell_count = lua.GetTableCount( out_cntr_list[n].empty_cell_list )
        cntr_good_weight = out_cntr_list[n].cntr_good_weight
        alloc_item = false
        if out_cntr_list[n].full == false and out_cntr_list[n].cell_type == cell_type and empty_cell_count > 0  then
            for i = 1, empty_cell_count do
                if out_cntr_list[n].empty_cell_list[i].item_code == ''  then
                    -- 取一个空料格存储计算能存储多少个货品
                    cntr_cell.cntr_code = out_cntr_list[n].cntr_code
                    cntr_cell.cell_no = out_cntr_list[n].empty_cell_list[i].cell_no
                    cntr_cell.good_volume = 0                      -- 是空料格
                    cntr_cell.cell_type = cell_type
                    nRet, si_qty = wms_cntr.Get_CntrCell_Goods_Qty( pac_cfg.ctd, out_cntr_list[n].cntr_good_weight, cntr_cell, item )
                    if nRet ~= 0  then 
                        return 1, si_qty 
                    end 
                    
                    -- 需要分配料格的货品数量 qty，如果计算出来的数量大于需求数量，就用需求数量
                    qty = item.qty - item.alloc_qty
                    if si_qty > qty then
                        si_qty = qty
                    end
                    -- 呼出料箱里加一个料格存储 item
                    if si_qty > 0  then
                        --  生成批次号
                        nRet, strSN = get_wms_sn( pac_cfg, item )
                        if nRet ~= 0 then
                            return 1, strSN
                        end
                        item.alloc_qty = item.alloc_qty + si_qty
                        if lua.equation( item.alloc_qty, item.qty ) then
                            item.ok = true
                        end
        
                        -- 把分配掉的si_qty个货品加到补料呼出的容器里
                        local cell_item = {
                            cntr_code = cntr_cell.cntr_code,
                            cell_type = cntr_cell.cell_type,
                            cell_no = cntr_cell.cell_no,
                            item_code = item.S_ITEM_CODE,
                            item_name = item.S_ITEM_NAME,
                            row = item.row,
                            entry_batch_no = strSN,
                            qty = si_qty,
                            sum_volume = si_qty*item.volume,
                            sum_weight = si_qty*item.weight,
                            weight = item.weight,
                            volume = item.volume,    
                            sku = item,
                            sku_list = {}
                        }
                        --put_cell_item_to_out_cntr_list( out_cntr_list, cell_item )
                        nRet, strRetInfo = wms_pac.put_cell_item_to_out_cntr_list( out_cntr_list, cntr_good_weight, cell_item, cntr_mixing_rule )
                        if nRet ~= 0 then
                            return 2, strRetInfo
                        end                        
                        table.insert( item.cntr_cell_list, cell_item ) 
                        -- 容器料格分配数量+1，料格设置为预分配
                        nRet, strRetInfo = wms_cntr.CNTR_cell_alloc_set( strLuaDEID, cntr_cell.cntr_code, cntr_cell.cell_no, pac_cfg.bs_no )
                        if nRet ~= 0 then
                            return 1, strRetInfo
                        end
                        -- empty_cell_list 里item_code 设置为有值，表示这个空料格已经有货
                        out_cntr_list[n].empty_cell_list[i].item_code = item.S_ITEM_CODE
                        out_cntr_list[n].empty_cell_list[i].item_name = item.S_ITEM_NAME
                        need_q = need_q - 1
                        alloc_item = true
                        if need_q == 0 then
                            break
                        end
                    end
                end
            end  
        end
        -- 删除那些已经分配货品的空料格empty_cell
        if alloc_item  then
            remove_empty_cell_have_item_code( out_cntr_list[n] )
        end
        if need_q == 0 then
            break
        end
    end
    return 0, need_q                 
end

-- 清除呼出料箱列表中没有cell_list的节点
-- @function remove_no_cell_list_out_cntr_list
-- @tparam table out_cntr_list 呼出料箱列表
local function remove_no_cell_list_out_cntr_list( out_cntr_list )
    local n = 1
    while out_cntr_list[n] do
        if #out_cntr_list[n].cell_list == 0  then
            table.remove( out_cntr_list, n )
        else
            n = n + 1
        end
    end
end

--[[ 
    step2 遍历SKU清单进行料箱预分配
    输入参数:
    pac_cfg -- 预分配算法基本参数配置
    item_list -- 需要做预分配的货品明细
    supplement_cntr_list 补料呼出的料箱列表
    out_cntr_result -- 呼出的料箱列表
    注意：料格类型A体积最大，依次类推
--]]

-- 获取呼出料箱列表
-- @function get_out_cntr_list_cbg
-- @tparam string strLuaDEID Lua引擎ID
-- @tparam table pac_cfg 预分配算法基本参数配置
-- @tparam table item_list 需要做预分配的货品明细
-- @tparam table supplement_cntr_list 补料呼出的料箱列表
-- @tparam table out_cntr_result 呼出的料箱列表
-- @treturn int nRet 0成功，非0失败
-- @treturn table|string supplement_cntr_list或错误信息
-- @treturn table|nil out_cntr_result或nil
local function get_out_cntr_list_cbg( strLuaDEID, pac_cfg, item_list, supplement_cntr_list, out_cntr_result )
    local nRet, strRetInfo
    if pac_cfg.ctd.count_method == "Volume" then
        -- 排序把体积大的放前面
        table.sort( item_list, item_sort_volume )
    end
     
    -- 从A类型料箱开始一直到E类型料箱呼出空料箱（大宗货品用A料框来满足入库需求）
    local sum_Q, x_sum_Q
    local out_cntr_list = {}
    local cell_type
    local b_have_this_cell_type = false
    local item_index, n
    local upgrad_item_list = {}     -- 需要进行升格的物料
    local query_cntr_list
    -- 从A类型料格开始遍历容器定义的料格类型
    for cell_type_index, grid_def in ipairs( pac_cfg.ctd.grid_box_def ) do
        cell_type = grid_def.cell_type
        -- step1 获取某类型空料箱格数量
        nRet, sum_Q = generate_item_needemptycell_qty( pac_cfg.ctd, item_list, grid_def )
        if nRet ~= 0  then
            return nRet, sum_Q
        end
        if sum_Q > 0  then
            --呼出空料箱格 生成 out_cntr_list
            out_cntr_list = {}
            query_cntr_list = {}
            -- 呼出数量最匹配的空料箱, 返回 out_cntr_list [{"cnter":"","good_weight":10, cell_type:"B"}]
            -- x_sum_Q 是不足的 cell_type 料格数量，需要进行降格
            nRet, x_sum_Q, strRetInfo = generate_out_cntr_list( strLuaDEID, pac_cfg, cell_type, sum_Q, out_cntr_list, 
                                                                query_cntr_list, out_cntr_result )
            if nRet ~= 0 then
                return 2, "generate_out_cntr_list 发生错误! "..strRetInfo
            end 
            -- 存在呼出的料箱列表，把货品批分到呼出的料箱格
            if lua.IsTableEmpty( out_cntr_list ) == false  then
                -- 设置 out_cntr_list 中 empty_cell_list 
                nRet, strRetInfo = wms_pac.set_out_cntr_empty_cell( strLuaDEID, out_cntr_list )
                if nRet ~= 0 then
                    return 2, strRetInfo
                end                
                -- 把 item_list 中的货品批分到 呼出的 out_cntr_list 中的容器中
                nRet, strRetInfo = distribute_to_outcntrlist( strLuaDEID, pac_cfg, item_list, out_cntr_list, cell_type )
                if nRet ~= 0  then
                    return 2, "step4.3 发生错误! "..strRetInfo
                end
                wms_pac.reset_empty_cell_info( out_cntr_list )
                lua.table_merge( out_cntr_result, out_cntr_list )
            end  
            if x_sum_Q > 0  then
                -- 如果未分配料箱的货品中还存在 cell_type 的料格
                b_have_this_cell_type, item_index = have_this_cell_type( item_list, cell_type )
                if b_have_this_cell_type  then
                    -- 如果不是A类型的料格需要考虑升格
                    if cell_type == 'A' then
                        local x_qty = item_list[item_index].qty - item_list[item_index].alloc_qty
                        return 1, "在分配货品编码 = '"..item_list[item_index].S_ITEM_CODE.."'时, 料箱类型 = "..cell_type.."的料箱不足! 货品数量 = "..x_qty
                    end
                end  
                -- MDF 20241220
                -- 说明没呼出足够的适配料箱
                if cell_type_index == 1  then   -- A 料格
                    -- 降格处理 A --> B 
                    lua.Warning( strLuaDEID, debug.getinfo(1), pac_cfg.bs_type.."-->'"..pac_cfg.bs_no.."'有"..x_sum_Q.."个A料箱降格!" )
                else
                    -- 升格处理 B --> A
                    lua.Warning( strLuaDEID, debug.getinfo(1), pac_cfg.bs_type.."-->'"..pac_cfg.bs_no.."'有"..x_sum_Q.."个"..cell_type.."料箱升格!" )
                    -- 把item_list中 item.Q > 0 的加入升格通道
                    n = 1
                    while item_list[n] do
                        if item_list[n].Q > 0  then
                            item_list[n].upgrad_cell_index = cell_type_index
                            table.insert( upgrad_item_list, item_list[n] )
                            table.remove( item_list, n )
                        else
                            n = n + 1
                        end
                    end
                end
            end
            -- MDF 20241220
            -- 判断 item_list 中的数量是否已经全部分配到容器，如果全部分配了料箱 break    
            if wms_base.item_list_is_all_ok( item_list ) or #item_list == 0  then 
                break 
            end        
        end
    end
    -- MDF 20241220 ***
    -- step5 如果有升料格需求的货品进行升格处理
    -- 如果有升料格的货品进入升格
    local qty, total_volume, Q, cell_volume, pk_qty, xQty, loading_limit, cell_type_index
    for n = 1, #upgrad_item_list do
        if upgrad_item_list[n].ok == false  then
            cell_type_index = upgrad_item_list[n].upgrad_cell_index
            -- 升格循环
            while ( cell_type_index > 1 ) do 
                cell_type_index = cell_type_index - 1               -- 升一个料格
                cell_type = pac_cfg.ctd.grid_box_def[cell_type_index].cell_type
                qty = upgrad_item_list[n].qty - upgrad_item_list[n].alloc_qty
                if pac_cfg.ctd.count_method == "Mixed" or pac_cfg.ctd.count_method == "Volume" then
                    total_volume = qty*upgrad_item_list[n].volume
                    cell_volume = pac_cfg.ctd.grid_box_def[cell_type_index].volume
                    if total_volume > cell_volume  then
                        --Q = math.floor( total_volume/cell_volume )
                        Q, pk_qty = calculate_box_count_by_volume( cell_volume, upgrad_item_list[n].volume, qty )
                    else
                        Q = 1
                    end 
                elseif pac_cfg.ctd.count_method == "Limit" then
                    -- 获取 SKU 在 grid_def.cell_type 的料格中的装载数量
                    nRet, loading_limit = wms_base.GetSKU_LoadingLimit( upgrad_item_list[n], pac_cfg.ctd.ctd_code, cell_type )
                    if nRet ~= 0  then
                        return 1, loading_limit
                    end
                    if qty >= loading_limit then
                        Q = math.floor(qty/loading_limit) 
                    else
                        Q = 1
                    end
                else
                    return 1, "料箱计数方法 = '"..pac_cfg.ctd.count_method.."'的算法还没实现!"
                end
                -- 从补料呼出的容器里找
                nRet, Q = alloc_cell_in_out_cntr_list( strLuaDEID, pac_cfg, supplement_cntr_list, cell_type, upgrad_item_list[n], Q )
                if nRet ~= 0 then
                    return 1, Q
                end
                if Q == 0 then
                    break
                end
                -- 从呼出容器里找
                nRet, Q = alloc_cell_in_out_cntr_list( strLuaDEID, pac_cfg, out_cntr_result, cell_type, upgrad_item_list[n], Q )
                if nRet ~= 0 then
                    return 1, Q
                end
                if Q == 0 then
                    break
                end
                -- 从新呼出一个料箱容器     
                out_cntr_list = {}
                query_cntr_list = {}
                nRet, Q, strRetInfo = generate_out_cntr_list( strLuaDEID, pac_cfg, cell_type, Q, out_cntr_list, query_cntr_list, out_cntr_result )
                if nRet ~= 0  then
                    return 2, "step5.1 发生错误! "..strRetInfo
                end   
                if lua.IsTableEmpty( out_cntr_list ) == false  then
                    -- 设置 out_cntr_list 中 empty_cell_list 
                    nRet, strRetInfo = wms_pac.set_out_cntr_empty_cell( strLuaDEID, out_cntr_list )
                    if nRet ~= 0 then
                        return 2, strRetInfo 
                    end
                    -- 把 upgrad_item_list 中的货品批分到 呼出的 out_cntr_list 中的容器中
                    nRet, strRetInfo = distribute_item_to_out_cntr_list( strLuaDEID, pac_cfg, upgrad_item_list[n], out_cntr_list )
                    if nRet ~= 0  then
                        return 2, "step5.2 发生错误! "..strRetInfo
                    end
                    wms_pac.reset_empty_cell_info( out_cntr_list )
                    lua.table_merge( out_cntr_result, out_cntr_list )
                end  
                if Q == 0 then
                    break
                end
            end          
        end
    end
    -- MDF 20241220 ***
    -- step6 检查升格后货品是否有没有匹配到料箱的，如果有需要降格
    local xVolume
    for n = 1, #upgrad_item_list do
        if upgrad_item_list[n].ok == false  then
            -- 开始降格
            cell_type_index = upgrad_item_list[n].upgrad_cell_index
            while ( cell_type_index < 5 ) do 
                cell_type_index = cell_type_index + 1               -- 降一个料格
                cell_type = pac_cfg.ctd.grid_box_def[cell_type_index].cell_type
                
                if upgrad_item_list[n].S_CELL_TYPE < cell_type then
                    break
                end
                qty = upgrad_item_list[n].qty - upgrad_item_list[n].alloc_qty
                if pac_cfg.ctd.count_method == "Mixed" or pac_cfg.ctd.count_method == "Volume" then
                    total_volume = qty*upgrad_item_list[n].volume
                    cell_volume = pac_cfg.ctd.grid_box_def[cell_type_index].volume
                    if total_volume > cell_volume  then
                        --Q = math.floor( total_volume/cell_volume )
                        Q, pk_qty = calculate_box_count_by_volume( cell_volume, upgrad_item_list[n].volume, qty )
                        xVolume = upgrad_item_list[n].volume*(qty-pk_qty)
                        if xVolume > 0 then
                            Q = Q + 1
                        end
                    else
                        Q = 1
                    end 
                elseif pac_cfg.ctd.count_method == "Limit" then
                    -- 获取 SKU 在 grid_def.cell_type 的料格中的装载数量
                    nRet, loading_limit = wms_base.GetSKU_LoadingLimit( upgrad_item_list[n], pac_cfg.ctd.ctd_code, cell_type )
                    if nRet ~= 0  then
                        return 1, loading_limit
                    end
                    if qty >= loading_limit then
                        Q = math.floor(qty/loading_limit) 
                        xQty = qty - Q*loading_limit
                        if xQty > 0 then
                            Q = Q + 1
                        end
                    else
                        Q = 1
                    end                    
                else
                    return 1, "料箱计数方法 = '"..pac_cfg.ctd.count_method.."'的算法还没实现!"
                end                
                -- 从补料呼出的容器里找
                nRet, Q = alloc_cell_in_out_cntr_list( strLuaDEID, pac_cfg, supplement_cntr_list, cell_type, upgrad_item_list[n], Q )
                if nRet ~= 0 then
                    return 2, Q
                end
                if Q == 0 then
                    break
                end
                -- 从呼出容器里找
                nRet, Q = alloc_cell_in_out_cntr_list( strLuaDEID, pac_cfg, out_cntr_result, cell_type, upgrad_item_list[n], Q )
                if nRet ~= 0 then
                    return 2, Q
                end
                if Q == 0 then
                    break
                end
                -- 从新呼出一个料箱容器     
                out_cntr_list = {}
                nRet, Q, strRetInfo = generate_out_cntr_list( strLuaDEID, pac_cfg, cell_type, Q, out_cntr_list, query_cntr_list, out_cntr_result )
                if nRet ~= 0  then
                    return 2, "step6.1 发生错误! "..strRetInfo
                end   
                if lua.IsTableEmpty( out_cntr_list ) == false  then
                    -- 设置 out_cntr_list 中 empty_cell_list 
                    nRet, strRetInfo = wms_pac.set_out_cntr_empty_cell( strLuaDEID, out_cntr_list )
                    if nRet ~= 0 then
                        return 2, strRetInfo
                    end
                    -- 把 upgrad_item_list 中的货品批分到 呼出的 out_cntr_list 中的容器中
                    nRet, strRetInfo = distribute_item_to_out_cntr_list( strLuaDEID, pac_cfg, upgrad_item_list[n], out_cntr_list )
                    if nRet ~= 0  then
                        return 2, "step6.2 发生错误! "..strRetInfo
                    end
                    wms_pac.reset_empty_cell_info( out_cntr_list )
                    lua.table_merge( out_cntr_result, out_cntr_list )
                end  
                if Q == 0 then
                    break
                end
            end          
        end
    end
    -- step7 判断货品是否已经全部分配料箱完成，没完成报错
    -- 把 item_list 和 upgrad_item_list 合并
    lua.table_merge( item_list, upgrad_item_list )
    -- 重置 supplement_cntr_list 和 out_cntr_list 中的empty_cell 等属性, 
    wms_pac.reset_empty_cell_info( supplement_cntr_list )
    wms_pac.reset_empty_cell_info( out_cntr_result )
    -- step8 遍历item_list 对没找到呼出料箱的货品进行单个呼出
    --       有可能因为重量超的原因上面分配的料格没办法装下货品
    local Q1, Q2
    for n = 1, #item_list do
        if item_list[n].ok == false then
            cell_type_index = string.byte( item_list[n].S_CELL_TYPE ) - string.byte( "A" ) + 1
            while ( cell_type_index >= 1 ) do 
                cell_type = pac_cfg.ctd.grid_box_def[cell_type_index].cell_type
                qty = item_list[n].qty - item_list[n].alloc_qty
                -- 根据体积算的料格数量
                if pac_cfg.ctd.count_method == "Mixed" or pac_cfg.ctd.count_method == "Volume" then
                    total_volume = qty*item_list[n].volume
                    cell_volume = pac_cfg.ctd.grid_box_def[cell_type_index].volume
                    if total_volume > cell_volume  then
                        --Q = math.floor( total_volume/cell_volume )
                        Q1, pk_qty = calculate_box_count_by_volume( cell_volume, item_list[n].volume, qty )
                        xVolume = item_list[n].volume*(qty-pk_qty)
                        if xVolume > 0 then
                            Q1 = Q1 + 1
                        end
                    else
                        Q1 = 1
                    end 
                    -- 根据重量算的料格数量
                    Q2, pk_qty = calculate_box_count_by_weight( pac_cfg, cell_type_index, item_list[n].weight, qty )
                    xVolume = item_list[n].volume*(qty-pk_qty)
                    if xVolume > 0 then
                        Q2 = Q2 + 1
                    end
                    
                    if Q2 > Q1  then 
                        Q = Q2
                    else
                        Q = Q1
                    end                    
                elseif pac_cfg.ctd.count_method == "Limit" then
                    -- 获取 SKU 在 grid_def.cell_type 的料格中的装载数量
                    nRet, loading_limit = wms_base.GetSKU_LoadingLimit( item_list[n], pac_cfg.ctd.ctd_code, cell_type )
                    if nRet ~= 0  then
                        return 1, loading_limit
                    end
                    if qty >= loading_limit then
                        Q = math.floor(qty/loading_limit) 
                        xQty = qty - Q*loading_limit
                        if xQty > 0 then
                            Q = Q + 1
                        end
                    else
                        Q = 1
                    end                       
                else
                    return 1, "料箱计数方法 = '"..pac_cfg.ctd.count_method.."'的算法还没实现!"
                end
                -- 从呼出容器里找
                nRet, Q = alloc_cell_in_out_cntr_list( strLuaDEID, pac_cfg, out_cntr_result, cell_type, item_list[n], Q )
                if nRet ~= 0 then
                    return 2, Q
                end
                if Q == 0 then
                    break
                end
                -- 从新呼出一个料箱容器     
                out_cntr_list = {}
                nRet, Q, strRetInfo = generate_out_cntr_list( strLuaDEID, pac_cfg, cell_type, Q, out_cntr_list, query_cntr_list, out_cntr_result )
                if nRet ~= 0  then
                    return 2, "step8.1 发生错误! "..strRetInfo
                end   
                if lua.IsTableEmpty( out_cntr_list ) == false  then
                    -- 设置 out_cntr_list 中 empty_cell_list 
                    nRet, strRetInfo = wms_pac.set_out_cntr_empty_cell( strLuaDEID, out_cntr_list )
                    if nRet ~= 0 then
                        return 2, strRetInfo
                    end
                    -- 把 upgrad_item_list 中的货品批分到 呼出的 out_cntr_list 中的容器中
                    nRet, strRetInfo = distribute_item_to_out_cntr_list( strLuaDEID, pac_cfg, item_list[n], out_cntr_list )
                    if nRet ~= 0  then
                        return 2, "step8.2 发生错误! "..strRetInfo
                    end
                    -- 清除呼出料箱列表中没有cell_list的节点
                    remove_no_cell_list_out_cntr_list( out_cntr_list )
                    if #out_cntr_list > 0  then
                        wms_pac.reset_empty_cell_info( out_cntr_list )
                        lua.table_merge( out_cntr_result, out_cntr_list )
                    end
                end                  
                if item_list[n].ok then
                    break
                end
                cell_type_index = cell_type_index - 1
            end
        end
    end
    return 0
end
--[[
    item_list -- 需要预分配料箱的货品
    pac_cfg   -- 预分配料箱配置参数
                {
                    wh_code, area_code  仓库，库区编码
                    factory
                    station 站台
                    aisle -- 可用巷道
                    aisle_lb -- 巷道均衡，0 不考虑 1 -- 任务均衡 
                    
                    bs_type 来源类型：入库单、入库波次
                    bs_no 来源单号   
                    cntr_out_op_def = "料箱出库",           --空料箱出库的作业定义
                    cntr_back_op_def = "货品入库"           --料箱回库的主业定义  
                    ctd = {}

                    -- MDF BY HAN @20260730
                    cntr_alloc_rule = 0 -- 容器呼出策略:  0 -- 出库容器数量少优先， 1 -- 容器利用率优先(补料呼出的料箱优先) 默认为 0
                    no_operation_first -- bool true 优先匹配没有作业的料箱, 默认为true                    
                }
    返回参数:
        nRet 返回值：0 成功 1 -- 料箱不足 2 -- 程序错误
    返回: pac_list 呼出的料箱列表 pac_detail_list 站台入库任务列表
--]]

-- CBG模式的料箱格预分配主函数
-- @function Pre_Alloc_Cntr_CBG
-- @tparam string strLuaDEID Lua引擎ID
-- @tparam table pac_cfg 预分配料箱配置参数 {wh_code,area_code,factory,station,aisle,aisle_lb,bs_type,bs_no,cntr_out_op_def,cntr_back_op_def,ctd}
-- @tparam table item_list 需要预分配料箱的货品清单
-- @treturn int nRet 0成功 1料箱不足 2程序错误
-- @treturn table|string pac_list或错误信息
-- @treturn table|nil pac_detail_list或nil
function wms_pac.Pre_Alloc_Cntr_CBG( strLuaDEID, pac_cfg, item_list )
    local nRet, strRetInfo
    local wh_code
    local ctd_code
    local sku_count = #item_list
    local supplement_cntr_list = {}
    local out_cntr_result = {}
    local alloc_event
    
    -- step1: 输入参数校验,及初始化
    if sku_count == 0  then
        return 0
    end
    if pac_cfg == nil or type( pac_cfg ) ~= "table"  then
        return 2, "Pre_Alloc_Cntr_CBG 函数输入参数错误: pac_cfg 必须有值，必须是 table 类型"
    end
    wh_code = lua.Get_StrAttrValue( pac_cfg.wh_code )
    if wh_code == ''  then
        return 2, "Pre_Alloc_Cntr_CBG 函数输入参数错误: pac_cfg 参数中的 wh_code 必须有值!"
    end
    ctd_code = lua.Get_StrAttrValue( pac_cfg.ctd.ctd_code )
    if ctd_code == ""  then
        return 2, "Pre_Alloc_Cntr_CBG 算法只适合 Cell_Box 类型的容器进行分配， pac_cfg中的参数  ctd_code 错误!"
    end
    -- local cntr_max_weight = pac_cfg.ctd.load_capacity   
    -- 如果 ctd 容器类型定义中定义过 混箱规则，这些规则一般会用到空料箱呼出规则中
    -- 比如在国科项目中，不同产品线的物料是不能放在一个料箱的，而产品线也确定了料箱存放区域，空料箱要优先从这些区域呼出
    local storage_area_set = {}
  
    if pac_cfg.empty_cntr_out_rule ~= nil and type( pac_cfg.empty_cntr_out_rule ) == "table"  then
        -- 根据 呼出空料箱策略，组织空料箱呼出库区
        local strategy = pac_cfg.empty_cntr_out_rule
        local strategy_code = strategy.no
        if strategy.alloc_method == 'script' then
            -- 根据脚本获取空料箱库区
            local str_alloc_event = strategy.alloc_event or ''
            if str_alloc_event == '' then
                return 1, "空料箱呼出策略编码 = '"..strategy_code.."' 的策略定义不合规，脚本类型的规则没定义脚本！"
            end
            alloc_event = json.decode( str_alloc_event )
            local event_name = alloc_event.name or ''
            if event_name == '' then
                return 1, "空料箱呼出策略编码 = '"..strategy_code.."' 的策略定义不合规，脚本类型的规则没定义脚本！"
            end        
            -- 执行脚本
            local ret_value
            local parameter = pac_cfg.mixing_attr_value
            nRet, ret_value = m3.RunScript( strLuaDEID, "EmptyCntrOut_Strategy", event_name, "", "", parameter )
            --[[
                ret_result = {..,result = {  err_code = 0, msg = "", area_set = {{wh_code="xx",area_code="xx"},..}} }
            --]]
            if nRet ~= 0 then
                return 1, ret_value
            end
            local result = ret_value.result
            if result == nil then
                return 1, "空料箱呼出策略'"..strategy_code.."'的脚本中返回值的格式不正确!"
            end
            if result.err_code == 0 then
                storage_area_set = result.area_set or ''
                if storage_area_set == '' then
                    return 1, "空料箱呼出策略'"..strategy_code.."'的脚本中返回值的格式不正确(少 area_set )!"
                end
            else
                return 1, "空料箱呼出策略'"..strategy_code.."'在计算是呼出空料箱库区是出现错误!"..result.msg 
            end
        elseif strategy.alloc_method == 'rule' then
            nRet, storage_area_set = wms_base.Get_Storage_Area_By_Strategy( pac_cfg.empty_cntr_out_rule, pac_cfg.mixing_attr_value )
            if nRet ~= 0 then
                return 1, storage_area_set
            end
        end
        if #storage_area_set == 0 then
            return 1, "空料箱呼出策略'"..strategy_code.."'无法确定空料箱从哪个库区呼出!" 
        end
        -- 对入库单中的库区和 空料箱呼出的库区 进行Check
        for _, storage_area in ipairs( storage_area_set ) do
            if storage_area.wh_code ~= pac_cfg.wh_code then
                return 1, "空料箱呼出策略 '"..pac_cfg.empty_cntr_out_rule.no.."' 中定义的仓库编码和入库单中的仓库不一致!"
            end
            if lua.StrIsEmpty( storage_area.area_code ) then
                return 1, "空料箱呼出策略 '"..pac_cfg.empty_cntr_out_rule.no.."' 中定义的策略必须指定到库区编码!"
            end                
        end
    end
    -- V3.0 MDF BY HAN @20260129 item_list 合并有相同补料匹配属性的 SKU
    local merge_item_list = {}
   
    if pac_cfg.ctd.si_enable and pac_cfg.ctd.si_cntr_num ~= 1 then
        -- 合并相同补料匹配属性的SKU
        nRet, merge_item_list = wms_base.get_merge_item_list( pac_cfg.ctd, item_list )
        if nRet == 0 then
            -- 说明有相同的SKU进行了合并
            -- item_list_bak = item_list  如果入库货品清单有数量合并过，最后需要进行批分（以后考虑）
            item_list = merge_item_list
        end
    end   
    
    -- step2 计算补料呼出料箱
    local have_si_empty_cell = false
    local pac_is_ok = false
    if pac_cfg.ctd.si_enable  then
        -- 需要补料
        -- step2.1
        nRet, supplement_cntr_list = wms_pac.get_replenishment_cntr_list( strLuaDEID, pac_cfg, item_list )
        if nRet ~= 0 then 
            return 2, supplement_cntr_list  
        end
        -- step2.2 补料呼出料箱中是否有存在空料格, 有空料格设置 empty_cell_list 属性
        nRet, have_si_empty_cell = wms_pac.set_replenishment_cntr_emptycell( strLuaDEID, supplement_cntr_list )
        if nRet ~= 0 then
            return 2,have_si_empty_cell
        end
        -- step1.3 检查补料箱中是否和合适料格做预分配        
        if not wms_base.item_list_is_all_ok( item_list ) and have_si_empty_cell then
            for _, sku in ipairs( item_list ) do
                if sku.qty > sku.alloc_qty  then
                    for _, si_cntr in ipairs( supplement_cntr_list ) do
                        nRet, strRetInfo = wms_pac.pre_alloc_sku_to_out_cntr( strLuaDEID, pac_cfg, sku, si_cntr )
                        if nRet ~= 0  then
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
    if not pac_is_ok then
        -- 继续呼出料箱
        if lua.IsTableEmpty( storage_area_set ) then
            nRet, strRetInfo = get_out_cntr_list_cbg( strLuaDEID, pac_cfg, item_list, supplement_cntr_list, out_cntr_result )
            if nRet ~= 0  then 
                return 2, strRetInfo  
            end
        else
            -- 如果有呼出空料箱策略
            for _, storage_area in ipairs( storage_area_set ) do
                pac_cfg.area_code = storage_area.area_code
                nRet, strRetInfo = get_out_cntr_list_cbg( strLuaDEID, pac_cfg, item_list, supplement_cntr_list, out_cntr_result )
                if nRet ~= 0  then 
                    return 2, strRetInfo  
                end    
                pac_is_ok = wms_base.item_list_is_all_ok( item_list )     
                if pac_is_ok then
                    break
                end           
            end
        end
    end
 
    local msg_list = {}                         -- 保存无法分配料格的货品数量
    for n = 1, #item_list do
        if item_list[n].ok == false then
            local qty = item_list[n].qty-item_list[n].alloc_qty
            local msg = "系统没有匹配到货品编码 = '"..item_list[n].S_ITEM_CODE.."'的适配料箱进行预分配, 货品的适配料格类型 = '"..item_list[n].S_CELL_TYPE.."', 数量 = "..qty
            table.insert( msg_list, msg )
        end
    end   
    if #msg_list > 0  then
        -- 这些货品没有合适的料箱
        return 1,  lua.table2str( msg_list )
    end
    -- 如果入库货品清单有数量合并过，最后需要进行批分
    --[[
    ****
        下面的代码有时间再考虑细化
        if item_list_bak ~= nil then
            -- 说明Pre-Alloction前是合并过数量的货品清单，需要进行批分
        end 
    --]]
    return 0, supplement_cntr_list, out_cntr_result
end

-- 
-- replenish = Y  表示是补料呼出料箱  station -- 站台
-- 创建预分配料箱和明细，生成 【Pre_Alloc_Container】【Pre_Alloc_CNTR_Detail】
-- @function generate_pac_detail
-- @tparam string strLuaDEID Lua引擎ID
-- @tparam table pac_cfg 预分配算法基本参数配置
-- @tparam string cntr_code 料箱编码
-- @tparam string replenish 是否是补料呼出料箱 Y/N
-- @tparam table cell_list 需要做预分配的料格列表
-- @tparam table pac_list 预分配料箱列表
-- @tparam table pac_detail_list 预分配料箱明细列表
-- @treturn int nRet 0成功，非0失败
-- @treturn string 错误信息
local function generate_pac_detail( strLuaDEID, pac_cfg, cntr_code, replenish, cell_list, pac_list, pac_detail_list )
    local nRet

    local pac = m3.AllocObject2( strLuaDEID, "Pre_Alloc_Container" )
    pac.S_CNTR_CODE = cntr_code
    pac.C_REPLENISH = replenish
    pac.S_BS_TYPE = pac_cfg.bs_type
    pac.S_BS_NO = pac_cfg.bs_no
    pac.S_STATION_NO = pac_cfg.station
    pac.S_OUT_OP_NAME = pac_cfg.cntr_out_op_def
    pac.S_BACK_OP_NAME = pac_cfg.cntr_back_op_def
    pac.S_FACTORY = pac_cfg.factory
    
    nRet, pac = m3.CreateDataObj2(strLuaDEID, pac)
    if nRet ~= 0 then
        return 1, "创建【预分配容器】失败!"..pac
    end
    table.insert( pac_list, pac )
    local pac_detail
    
    for n = 1, #cell_list do 
        pac_detail = m3.AllocObject2( strLuaDEID, "Pre_Alloc_CNTR_Detail" )
        pac_detail.S_PAC_NO = pac.S_PAC_NO
        pac_detail.S_CNTR_CODE = cntr_code
        pac_detail.S_CELL_NO = cell_list[n].cell_no        
        pac_detail.S_STATION_NO = pac_cfg.station
        pac_detail.S_STORER = cell_list[n].sku.S_STORER
        pac_detail.S_ITEM_CODE = cell_list[n].item_code
        pac_detail.S_ITEM_STATE = cell_list[n].sku.S_ITEM_STATE
        pac_detail.S_ITEM_NAME = cell_list[n].item_name
        pac_detail.S_OWNER = cell_list[n].sku.S_OWNER
        pac_detail.S_SUPPLIER_NO = cell_list[n].sku.S_SUPPLIER_NO
        pac_detail.S_BATCH_NO = cell_list[n].sku.S_BATCH_NO
        pac_detail.S_SERIAL_NO = cell_list[n].sku.S_SERIAL_NO
        pac_detail.D_PRD_DATE = cell_list[n].sku.D_PRD_DATE
        pac_detail.D_EXP_DATE = cell_list[n].sku.D_EXP_DATE
        pac_detail.F_WEIGHT = cell_list[n].weight
        pac_detail.F_VOLUME = cell_list[n].volume
        pac_detail.S_WMS_BN = cell_list[n].wms_bn
        pac_detail.F_QTY = cell_list[n].qty
        pac_detail.S_BS_TYPE = pac_cfg.bs_type
        pac_detail.S_BS_NO = pac_cfg.bs_no
        pac_detail.N_BS_ROW_NO = cell_list[n].row
        -- 把SKU中的明细扩展属性带入
        for _, udf_attr in ipairs(UDF_ATTRS) do
            pac_detail[udf_attr] = cell_list[n].sku[udf_attr]
        end
        nRet, pac_detail = m3.CreateDataObj2(strLuaDEID, pac_detail)
        if nRet ~= 0 then
            return 1, "创建【预分配容器明细】失败!"..pac_detail
        end
        
        table.insert( pac_detail_list, pac_detail )
    end
    return 0
end

-- 从数据对象(字段)中获取 attrs_array 中的属性值
-- @function get_data_object_attr_value
-- @tparam table object_data 数据对象
-- @tparam table attrs_array 属性数组，如 {"S_BATCH_NO","S_STATE"}
-- @treturn string mixing_key 拼接后的key字符串
-- @treturn table attr_value 属性值表
local function get_data_object_attr_value( object_data, attrs_array )
    local attr_value = {}
    local key_value = ''
    local value
    for _, attr in ipairs( attrs_array ) do
        value = object_data[attr] or ''
        key_value = key_value..attr.."='"..value.."';"
        attr_value[attr] = value
    end
    return lua.trim_laster_char( key_value ), attr_value
end
--[[
    把 item_list 根据容器类型定义 ctd 中的混箱规则，把相同混箱规则的 item 分组，生成 split_item_list
    ctd.mixing_attrs_def = {
            {attr = "S_BATCH_NO", type = "string"},
            ..
    }
    ctd.mixing_attrs = {"S_BATCH_NO",...}
    split_item_list = {
        mixing_attr_value = {S_BATCH_NO="xxx",S_X="xxx"},
        mixing_key = "S_BATCH_NO='xx';S_STATE='xx'"
        item_list = {
                        {S_ITEM_CODE = "X1",...},
                    }
    }
--]]
-- 把 item_list 根据容器类型定义 ctd 中的混箱规则，把相同混箱规则的 item 分组，生成 split_item_list
-- @function split_item_list_by_mixing_rule
-- @tparam table ctd 容器类型定义
-- @tparam table item_list 入库货品清单
-- @tparam table split_item_list 分组后的货品清单（输出参数）
-- @treturn int nRet 0成功
-- @treturn string 错误信息
local function split_item_list_by_mixing_rule( ctd, item_list, split_item_list )
    local mixing_attr_value = {}
    local find, mixing_key
    if lua.isTableEmpty( ctd.mixing_attrs ) then
        return 1, "容器类型定义'"..ctd.ctd_code.."'中的混箱规则不能为空!"
    end
    for _, item in ipairs( item_list ) do
        mixing_key, mixing_attr_value = get_data_object_attr_value( item, ctd.mixing_attrs )
        find = false
        for _, split_item in ipairs( split_item_list ) do
            if split_item.mixing_key == mixing_key then
                find = true
                table.insert( split_item.item_list, item )
                break
            end
        end
        if not find then
            local split_item = {
                mixing_attr_value = mixing_attr_value,
                mixing_key = mixing_key,
                item_list = {}
            }
            table.insert( split_item.item_list, item )
            table.insert( split_item_list, split_item )
        end
    end
    return 0
end

-- 检查货品列表中货品（SKU）中的SCU值是否符合要求
-- @function check_sku_scu_value
-- @tparam int max_scu_value 料箱最大SCU值, 必须有值
-- @tparam table sku_list sku清单, 必须有值
-- @treturn bool|check_ok nil
-- @treturn string|nil 错误信息，成功时nil
local function check_sku_scu_value( max_scu_value, sku_list )
    if max_scu_value <= 0 then
        return false, "料箱定义中SCU值必须有值!"
    end
    for _, sku in ipairs( sku_list ) do
        if sku.scu == 0 then
            return false, "编码为'"..sku.S_ITEM_CODE.."'的SKU没定义SCU值!"
        end
        if sku.scu > max_scu_value then
            return false, "编码为'"..sku.S_ITEM_CODE.."'的SKU的SCU值大于容器类型的SCU上限"..max_scu_value
        end
    end
    return true
end
--[[
        预分配料箱，物料预先指定存储料格及料格中最大存储数量，或重量
        如果货品
        Designated Material Grid -- 简称 DMG 意思是每个货品都指定了一种料格进行存储
        特点:
            一种货品保存在一种类型的料格
            料格中货品最大存储数量计算方法有两种， 1 -- 系统设置最大储藏数量 2 -- 系统设置重量后根据料格载重进行计算
            在匹配料箱时，一个料箱只能用相同的数量计算方法
    来源项目: 艾默生料箱库
    输入参数:
        pac_cfg -- 预分配料箱配置参数
                {
                    handling_model -- 搬运模式 AGV;PickingAGV;AS/RS
                    aisle_lb -- 巷道均衡，0 不考虑 1 -- 任务均衡 
                    factory 工厂标识                    
                    wh_code, area_code  仓库，库区编码
                    station 站台
                    bs_type 来源类型：入库单、入库波次
                    bs_no   来源单号
                    aisle   可用巷道  'A01','A02',...  字符串
                    -- 入库单序列号生成方法 20260615
                    get_wms_sn_func = { module_name = "prj_base", function_name = "" }

                    cntr_out_op_def = "料箱出库",           --空料箱出库的作业定义
                    cntr_back_op_def = "货品入库"           --料箱回库的主业定义 
                    --- 如果入库的时候指定了容器类型，在下面这个参数设置容器类型编码
                    ctd_code = "T002" 入库容器类型编码 （如果没值从 SKU的属性获取，如果有值用这里的值）

                    -- MDF BY HAN @20260730
                    replenish_priority -- bool true 优先补料，默认为true
                    no_operation_first -- bool true 优先匹配没有作业的料箱, 默认为true
                }        
   
        ---- 下面两个参数是系统运算后的结果返回 ----
        pac_list -- Pre_Alloc_Container 对象列表
        pac_detail_list Pre_Alloc_CNTR_Detail 列表
--]]

-- 预分配料箱（外部调用）
-- @function Pre_Alloc_Cntr
-- @tparam string strLuaDEID Lua引擎ID
-- @tparam table pac_cfg 预分配料箱配置参数 {handling_model,aisle_lb,factory,wh_code,area_code,station,bs_type,bs_no,aisle,cntr_out_op_def,cntr_back_op_def,ctd_code,cntr_alloc_rule}
-- @tparam table pac_list Pre_Alloc_Container对象列表（输出参数）
-- @tparam table pac_detail_list Pre_Alloc_CNTR_Detail列表（输出参数）
-- @treturn int nRet 0成功，非0失败
-- @treturn string|nil 错误信息，成功时nil

function wms_pac.Pre_Alloc_Cntr( strLuaDEID, pac_cfg, pac_list, pac_detail_list )
    local nRet, strRetInfo
    -- 输入参数检查
    if pac_cfg.wh_code == nil or pac_cfg.wh_code == ''  then
        return 1, "输入参数 pac_cfg 错误， wh_code必须有值"
    end
    -- 如果没定义巷道均衡，默认不考虑
    if pac_cfg.aisle_lb == nil then
        pac_cfg.aisle_lb = 0
    end
    
    -- MDF BY HAN @20260730
    if pac_cfg.replenish_priority == nil then
        pac_cfg.replenish_priority = true   -- 补料优先
    else
        if type(pac_cfg.replenish_priority) ~= "boolean" then
            return 1, "输入参数 pac_cfg 错误， replenish_priority 必须是 boolean 类型!"
        end
    end
    if pac_cfg.no_operation_first == nil then
        pac_cfg.no_operation_first = true   -- 没作业的料箱优先
    else
        if type(pac_cfg.no_operation_first) ~= "boolean" then
            return 1, "输入参数 pac_cfg 错误， no_operation_first 必须是 boolean 类型!"
        end
    end
    
    -- 如果要考虑巷道均衡，必须要有可用巷道参数（因为有些巷道会因为设备检修等原因不可用，这些必须通过WCS系统获取）
    if pac_cfg.aisle == nil or type(pac_cfg.aisle) ~= "string" then
        return 1, "输入参数 pac_cfg 错误， aisle 必须有值,且必须是 string 类型!"
    end
    -- 生成可用巷道数据集
    local aisle_set = {}
    if pac_cfg.aisle ~= '' then
        -- %w+ 直接提取连续的字母/数字，自动跳过所有引号和逗号
        for item in pac_cfg.aisle:gmatch("%w+") do
            local aisle = {
                aisle_code = item,
                task_num = 0,           -- 巷道任务数量
                cntr_list = {}          -- 检索出来的本巷道可用出库的料箱编码
            }
            aisle_set[#aisle_set + 1] = aisle
        end
        -- 如果需要做巷道均衡
        if pac_cfg.aisle_lb == 1 then
            nRet, strRetInfo = wms_wh.GetAisleTaskNum( strLuaDEID, pac_cfg.wh_code, aisle_set )
            if nRet ~= 0 then
                return 1, "获取巷道任务数量失败! "..strRetInfo
            end
        end
    end
    -- 巷道任务数组赋值 aisle_set = { {aisle_code,task_num},...}
    pac_cfg.aisle_set = aisle_set
    -- step1: 根据入库单，入库波次获取入库的货品信息，根据容器类型进行分组
    --        一种容器类型一个分组
    local ctd_list = {}
    nRet, ctd_list = wms_pac.Get_ItemList_GroupBy_CntrType( strLuaDEID, pac_cfg )
    if nRet ~= 0  then
        return 1, ctd_list
    end
    -- 从 pac_cfg.cntr_back_op_def （入库/回库作业）中获取空料箱呼出策略
    local op_def
    nRet, op_def = wms_base.GetOpDefInfo( pac_cfg.factory, pac_cfg.cntr_back_op_def )
    if nRet ~= 0 then
        return 1, "系统无法获取名为'"..pac_cfg.cntr_back_op_def.."'的作业类型! "..op_def
    end
    -- 如果有输入‘空料箱呼出策略’ 需要从系统获取该策略
    if not lua.StrIsEmpty( op_def.ec_callout_rule ) then
        local strategy = {}
        nRet, strategy = wms_base.GetStrategyInfo( "EmptyCntrOut_Strategy", op_def.ec_callout_rule )
        if nRet ~= 0 then
            return 1, "在获取'空料箱呼出策略'时失败! "..strategy
        end
        pac_cfg.empty_cntr_out_rule = strategy
    end
    -- 根据容器类型进行料箱预分配
    local count_method
    local supplement_cntr_list = {}
    local out_cntr_list = {}
    local ffd_model = false
    for n = 1, #ctd_list do
        ffd_model = false
        -- 通过容器类型定义设置 料箱呼出规则
        nRet, pac_cfg.ctd = wms_cntr.GetCTDInfo( ctd_list[n].ctd_code )
        if nRet ~= 0  then
            return 1, "容器类型定义'"..ctd_list[n].ctd_code.."'转换数据格式! --> "..pac_cfg.ctd
        end        
        count_method = pac_cfg.ctd.count_method
        -- 对入库货品进行参数判断，是否有少必要参数
        for _, item in ipairs( ctd_list[n].item_list ) do
            if pac_cfg.ctd.type == "Cell_Box" then
                if lua.StrIsEmpty( item.S_CELL_TYPE )  then
                    return 1, "编码'"..item.S_ITEM_CODE.."'的 SKU 没有定义料格类型/S_CELL_TYPE"
                end
            end
            -- 注意：改变从SKU获取计数方法，这个有局限，一个货品可能有多个计数方法, 改成直接从容器定义里取值
            -- count_method = lua.Get_StrAttrValue( item.S_COUNT_METHOD )
            if count_method == "Volume"  then
                if item.volume <= 0  then
                    return 1, "编码'"..item.S_ITEM_CODE.."'的 SKU 定义的料格计数方法是根据体积计算，没有设置SKU的体积!"
                end
            elseif count_method == "Weight"  then
                if item.weight <= 0  then
                    return 1, "编码'"..item.S_ITEM_CODE.."'的 SKU 定义的料格计数方法是根据重量计算，没有设置SKU的重量!"
                end    
            elseif count_method == "SCU" then
                if item.scu <= 0 then
                    return 1, "编码'"..item.S_ITEM_CODE.."'的 SKU没有设置 F_SCU !"
                end
            end
            item.mixing_rule = {}
            if pac_cfg.ctd.have_mixing_rule  then
                -- 获取 SKU 的混箱属性
                for _, attr in ipairs( pac_cfg.ctd.mixing_attrs ) do
                    item.mixing_rule[attr] = lua.Get_StrAttrValue( item[attr])
                end
            end        
        end
        -- 对pac_cfg中的入库作业定义进行处理，获取入库作业的上架策略，通过这个策略去查找空料箱
        -- ecda_rule 空料箱格呼出规则
        if pac_cfg.ctd.ecda_rule == "Flex match"  then
            -- 灵活匹配可以匹配多种类型料格
            -- 需要进一步对入库货品进行分类（根据混箱规则，比如相同产品线）
            if pac_cfg.ctd.have_mixing_rule then
                -- 根据混箱规则对入库货品明细进行分割，相同混箱规则的放一起，加入 split_item_list
                -- split_item_list = {{"mixing_value":{S_UDF01="PRD-01"}, item_list:{}},...}
                local split_item_list = {}
                nRet, strRetInfo = split_item_list_by_mixing_rule( pac_cfg.ctd, ctd_list[n].item_list, split_item_list )
                if nRet ~= 0 then
                    return 1, strRetInfo
                end
                -- 分别对有相同混箱规则的货品进行 容器预分配
                for _, split_item in ipairs( split_item_list ) do
                    local s_cntr_list = {}
                    local o_cntr_list = {}
                    -- 下面属性说明了料箱的混箱规则和值
                    pac_cfg.mixing_attr_value = split_item.mixing_attr_value
                    if pac_cfg.ctd.type == "Cell_Box" then
                        nRet, s_cntr_list, o_cntr_list = wms_pac.Pre_Alloc_Cntr_CBG( strLuaDEID, pac_cfg, split_item.item_list )
                        if nRet ~= 0  then
                            return nRet, o_cntr_list
                        end
                        lua.table_merge( supplement_cntr_list, s_cntr_list )
                    elseif pac_cfg.ctd.type == "Pallet" or pac_cfg.ctd.type == "Normal" then
                        -- 在进行FFD算法前,先判断一下，SKU的scu值是否超出容器定义的最大值，或SKU没定义
                        local max_scu_value = pac_cfg.ctd.max_scu_value or 0
                        if max_scu_value <= 0 then
                            return 2, "容器定义编码为'"..pac_cfg.ctd.code.."'没有定义SCU值!"
                        end
                        local check_ok, err = check_sku_scu_value( max_scu_value, split_item.item_list )
                        if not check_ok then
                            return 2, err
                        end
                        nRet, o_cntr_list = wms_pac_ffd.Pre_Alloc_Cntr_FFD( strLuaDEID, pac_cfg, split_item.item_list )
                        if nRet ~= 0  then
                            return nRet, o_cntr_list
                        end
                    else
                        return 1, "容器类型 = '"..pac_cfg.ctd.type.."'不支持预分配容器料箱入库算法!"
                    end
                    lua.table_merge( out_cntr_list, o_cntr_list )
                end
            else
                if pac_cfg.ctd.type == "Cell_Box" then
                    nRet, supplement_cntr_list, out_cntr_list = wms_pac.Pre_Alloc_Cntr_CBG( strLuaDEID, pac_cfg, ctd_list[n].item_list )
                    if nRet ~= 0  then
                        return nRet, supplement_cntr_list
                    end 
                elseif pac_cfg.ctd.type == "Pallet" or pac_cfg.ctd.type == "Normal" then
                    nRet, out_cntr_list = wms_pac_ffd.Pre_Alloc_Cntr_FFD( strLuaDEID, pac_cfg, ctd_list[n].item_list )
                    if nRet ~= 0  then
                        return nRet, out_cntr_list
                    end
                    ffd_model = true
                else
                    return 1, "容器类型 = '"..pac_cfg.ctd.type.."'不支持预分配容器料箱入库算法!"
                end                    
            end
        elseif pac_cfg.ctd.ecda_rule == "SDM Grid"  then
            -- SKU指定了特定的料格类型
            nRet, supplement_cntr_list, out_cntr_list = wms_pac.Pre_Alloc_Cntr_DMG( strLuaDEID, pac_cfg, ctd_list[n].item_list )
            if nRet ~= 0  then
                return nRet, supplement_cntr_list
            end
        else
            return 1, "系统不支持名为'"..pac_cfg.ctd.ecda_rule.."'的料箱呼出规则!"
        end
        -- step9 创建 预分配容器 
        -- 20241108 HAN 补料呼出的料箱和空料箱呼出的如果料箱号是一样的需要合并一下，合并在补料箱列表
        -- 如果呼出的有补料和空料箱的时候要检查
        if ffd_model == true then
            for _, bin in ipairs( out_cntr_list ) do
                nRet, strRetInfo = wms_pac_ffd.Generate_Pac_Detail( strLuaDEID, pac_cfg, bin, pac_list, pac_detail_list )
                if nRet ~= 0  then
                    return 2, "呼出空料箱 Generate_Pac_Detail 发生错误! "..strRetInfo
                end                 
            end
        else
            for n = 1, #supplement_cntr_list do
                for m = 1, #out_cntr_list do
                    if supplement_cntr_list[n].cntr_code == out_cntr_list[m].cntr_code then
                        for i = 1, #out_cntr_list[m].cell_list do
                            table.insert( supplement_cntr_list[n].cell_list, out_cntr_list[m].cell_list[i])
                            remove_empty_cell( supplement_cntr_list[n], out_cntr_list[m].cell_list[i].cell_no )
                        end
                        out_cntr_list[m].cell_list = {}
                    end
                end
            end
            -- 生成 【Pre_Alloc_Container】【Pre_Alloc_CNTR_Detail】
            local cell_list
            for n = 1, #supplement_cntr_list do
                cell_list = supplement_cntr_list[n].cell_list
                if #cell_list > 0  then
                    nRet, strRetInfo = generate_pac_detail( strLuaDEID, pac_cfg, supplement_cntr_list[n].cntr_code, 'Y', 
                                                            cell_list, pac_list, pac_detail_list )
                    if nRet ~= 0  then
                        return 2, "补料 generate_pac_detail 发生错误! "..strRetInfo
                    end            
                end
            end
            for n = 1, #out_cntr_list do
                cell_list = out_cntr_list[n].cell_list
                if #cell_list > 0  then
                    nRet, strRetInfo = generate_pac_detail( strLuaDEID, pac_cfg, out_cntr_list[n].cntr_code, 'N', 
                                                            cell_list, pac_list, pac_detail_list )
                    if nRet ~= 0  then
                        return 2, "呼出空料箱 generate_pac_detail 发生错误! "..strRetInfo
                    end            
                end
            end
        end
    end
    -- 设置入库单业务状态为 PreAlloc_OK/预分配完成（ps:入库需要的料箱已经确定）
    local strUpdateSql
    local strCondition    
    if pac_cfg.bs_type == "Inbound_Order"  then
        strUpdateSql = "N_B_STATE = "..INBOUND_STATE.PreAlloc_OK
        strCondition = "S_NO = '"..pac_cfg.bs_no.."'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Inbound_Order", strCondition, strUpdateSql )
        if nRet ~= 0  then  
            return 2, "更新【入库单】信息失败!"..strRetInfo 
        end  
    elseif pac_cfg.bs_type == "Inbound_Wave" then
        strUpdateSql = "N_B_STATE = "..IN_WAVE_STATE.PreAlloc_OK
        strCondition = "S_WAVE_NO = '"..pac_cfg.bs_no.."'"
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Inbound_Wave", strCondition, strUpdateSql )
        if nRet ~= 0  then  
            return 2, "更新【入库波次】信息失败!"..strRetInfo  
        end          
    end         
    return 0
end

return wms_pac
