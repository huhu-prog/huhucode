--[[
    版本：     Version 3.0
    创建日期： 2025-12-15
    修改日期:  2026-6-18
    创建人：   HAN

    WMS-Basis-Model-Version: V18.2

    功能：
        在处理入库作业时，将入库单明细中的货品预先分配到具体容器/料格的过程在WMS系统里叫预分配容器
        本算法适合容器类型为 pallet 托盘/normal常规 两种类型的容器，不适合料格类型容器
        本算法属于经典的 "装箱问题" 。由于要寻找精确的最优解（最小容器数）是NP-Hard问题，采用高效的"首次适应递减算法"
        First Fit Decreasing -- 简称 FFD

        核心思想是：
            先处理体积计量值大的货品，按顺序尝试放入第一个能容纳它的容器
            如果有混箱规则需要对入库货品做预处理，把有相同混箱规则的货品组成一个新的货品队列进行容器计算

    【预分配容器】
        Pre_Alloc_Cntr_FFD  — 预分配容器（FFD算法入口），将入库SKU分配到托盘/容器中
        Generate_Pac_Detail — 生成【预分配容器】和【预分配容器明细】数据对象并保存到数据库


    更改记录:
    2025-12-15  HAN  创建
    2026-6-18   HAN  添加函数文档注释，统一if语句格式

    AI CHECK:
        -- 20260618
--]]
wms_base = require ("wms_base")

local wms_pac_ffd = {_version = "0.1.1"}

-- SKU 按特殊计量值(SCU)降序排序的比较函数
-- @tparam table sku1 货品1
-- @tparam table sku2 货品2
-- @treturn boolean sku1.scu > sku2.scu
local function sku_scu_sort( sku1, sku2 )
    return sku1.scu > sku2.scu
end

-- SKU 按体积(Volume)降序排序的比较函数
-- @tparam table sku1 货品1
-- @tparam table sku2 货品2
-- @treturn boolean sku1.volume > sku2.volume
local function sku_volume_sort( sku1, sku2 )
    return sku1.volume > sku2.volume
end

-- SKU 按重量(Weight)降序排序的比较函数
-- @tparam table sku1 货品1
-- @tparam table sku2 货品2
-- @treturn boolean sku1.weight > sku2.weight
local function sku_weight_sort( sku1, sku2 )
    return sku1.weight > sku2.weight
end

-- 将 SKU 添加到容器的 SKU 列表中，如已存在则数量+1，否则深拷贝后新增
-- @tparam table bin_sku_list 容器的 SKU 列表（会被修改）
-- @tparam table sku 要添加的 SKU 对象（需包含 row 字段）
local function add_sku_to_bin_sku_list( bin_sku_list, sku )
    for _, item in ipairs( bin_sku_list ) do
        if item.row == sku.row then
            item.qty = item.qty + 1
            return
        end
    end
    -- 新加一个sku到 bin_sku_list
    local new_sku = lua.table_deepcopy(sku)
    new_sku.qty = 1
    table.insert( bin_sku_list, new_sku )
end

-- 将容器中已计划的 SKU 数量累加到主 SKU 列表的 alloc_qty 中，并标记分配完成状态
-- @tparam table sku_list 主货品列表（alloc_qty/ok 字段会被修改）
-- @tparam table plan_cntr_sku_list 容器中已计划的 SKU 列表
local function add_alloc_qty( sku_list, plan_cntr_sku_list )
    for _, cntr_sku in ipairs( plan_cntr_sku_list ) do
        for _, sku in ipairs( sku_list ) do
            if cntr_sku.row == sku.row then
                sku.alloc_qty = sku.alloc_qty + cntr_sku.qty
                if sku.alloc_qty == sku.qty then
                    sku.ok = true
                end
                break
            end
        end
    end
end

-- 将单个 SKU 分配到未满的容器中（含巷道任务均衡处理）
-- @tparam table pac_cfg 预分配配置参数
-- @tparam table cntr_data_objs 数据库中查询到的未满容器数据对象列表
-- @tparam table sku 需要分配的 SKU 对象（alloc_qty/ok 字段会被修改）
-- @tparam table notfull_cntr_out_list 已分配的输出容器列表（会被追加修改）
local function alloc_sku_to_notfull_cntr( pac_cfg, cntr_data_objs, sku, notfull_cntr_out_list )
    local cntr_code, cntr_scu_value, rem_scu_value, aisle_code
    local qty, find
    local cntr_max_scu_value = pac_cfg.ctd.max_scu_value
    
    -- 如果要考虑巷道均衡，需要根据巷道的任务数量进行排序
    local cntr_list= {}
    local task_num
    local aisle_set = lua.table_deepcopy( pac_cfg.aisle_set )

    for _, obj in ipairs(cntr_data_objs) do
        aisle_code = lua.Get_StrAttrValue(obj[3])    
        task_num = 0
        if pac_cfg.aisle_lb == 1 then
            -- 获取巷道任务数量，并且给当前巷道的任务数量+1
            task_num = wms_base.Add_Aisle_Task_Num( aisle_set, aisle_code )
        end
        local cntr = {
            cntr_code = lua.Get_StrAttrValue(obj[1]),
            cntr_scu_value = lua.Get_NumAttrValue(obj[2]),
            aisle_code = aisle_code,
            task_num = task_num,
        }
        table.insert(cntr_list, cntr)            
    end
    if pac_cfg.aisle_lb == 1 then
        -- 对巷道任务数量进行排序
        table.sort(cntr_list, function(a, b) return a.task_num < b.task_num end)
    end

    -- 遍历查询出来的未满托盘
    local cntr_is_full
    for _, cntr in ipairs(cntr_list) do
        cntr_code = cntr.cntr_code
        cntr_scu_value = cntr.cntr_scu_value
        aisle_code = cntr.aisle_code
        rem_scu_value = cntr_max_scu_value - cntr_scu_value -- 还可以继续装载的货品特别计数值

        -- 判断编号为 cntr_code 的容器是否已经分配完成
        cntr_is_full = false
        for _, notfull_cntr in ipairs( notfull_cntr_out_list ) do
            if cntr_code == notfull_cntr.cntr_code then
                if notfull_cntr.rem_scu_value <= 0 then
                    cntr_is_full = true
                    break
                end
            end
        end

        -- 如果容器还有空间，继续分配
        if not cntr_is_full then
            qty = sku.qty - sku.alloc_qty
            for n = 1, qty do
                -- 先从呼出的存储未满的托盘中查找是否可以存储当前的 SKU
                find = false
                for _, notfull_cntr in ipairs( notfull_cntr_out_list ) do
                    if notfull_cntr.rem_scu_value >= sku.scu then
                        find = true 
                        sku.alloc_qty = sku.alloc_qty + 1
                        notfull_cntr.rem_scu_value = notfull_cntr.rem_scu_value - sku.scu
                        add_sku_to_bin_sku_list( notfull_cntr.sku_list, sku )
                        break
                    end
                end

                -- 如果上面这段代码没找到合适的托盘，继续判断货品是否能存储到查询出的未满托盘
                if find == false then
                    if  rem_scu_value >= sku.scu then
                        -- 可以装载得下
                        rem_scu_value = rem_scu_value - sku.scu
                        sku.alloc_qty = sku.alloc_qty + 1

                        -- 新分配一个容器
                        local bin = {
                            cntr_code = cntr_code,
                            rem_scu_value = rem_scu_value,
                            sku_list = {}
                        }
                        -- 巷道任务数量加一
                        wms_base.Add_Aisle_Task_Num( pac_cfg.aisle_set, aisle_code )

                        -- 深拷贝 SKU 对象，避免引用问题
                        local new_sku = lua.table_deepcopy(sku)
                        new_sku.qty = 1
                        table.insert( bin.sku_list, new_sku )
                        table.insert( notfull_cntr_out_list, bin )
                    else
                        break
                    end
                end

                if sku.qty == sku.alloc_qty then
                    sku.ok = true
                    break
                end      
                if rem_scu_value < sku.scu then
                    break
                end
            end
        end
    end
end

-- 从仓库获取有货但未满的托盘或容器，尝试将未分配SKU分配到未满容器中
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数
-- @tparam table sku_list 货品列表（alloc_qty/ok 字段会被修改）
-- @tparam table out_cntr_list 输出容器列表（会被追加分配结果）
-- @treturn number nRet 0: 成功, 1: 参数错误, 2: 数据库查询失败
-- @treturn string strRetInfo 错误信息（成功时为空字符串）
local function get_notfull_cntr_list( strLuaDEID, pac_cfg, sku_list, out_cntr_list )
    local nRet, strRetInfo

    local str_loc_where = "C_ENABLE = 'Y' AND S_WH_CODE = '"..pac_cfg.wh_code.."'"
    if not lua.StrIsEmpty( pac_cfg.area_code ) then
        str_loc_where = str_loc_where.." AND S_AREA_CODE = '"..pac_cfg.area_code.."'"
    end

    local ctd_code = pac_cfg.ctd.ctd_code
    if ctd_code == nil or ctd_code == '' then
        return 1, "输入参数错误， pac_cfg 中 ctd.ctd_code 必须有值"
    end

    local strTable = "TN_Container a INNER JOIN TN_Loc_Container b ON a.S_CODE = b.S_CNTR_CODE "..
                     "INNER JOIN TN_Location d ON b.S_LOC_CODE = d.S_CODE "

    -- 如果有混箱规则，需要把容器中规则定义的属性取值
    if pac_cfg.ctd.have_mixing_rule then
        strTable = strTable.." LEFT JOIN TN_Container_Ext c ON a.S_CODE = c.S_CNTR_CODE"
    end

    local strAttrs = "a.S_CODE, a.F_SCU_VALUE, d.S_AISLE_CODE"          -- 查询字段
    if pac_cfg.ctd.have_mixing_rule then
        for _, attr in ipairs( pac_cfg.ctd.mixing_attrs ) do
            strAttrs = strAttrs..",c."..attr
        end
    end

    --local cntr_max_weight = pac_cfg.ctd.load_capacity 
    local cntr_max_scu_value = pac_cfg.ctd.max_scu_value
    local cntr_mixing_condition = ''        -- 混箱条件

    if pac_cfg.ctd.have_mixing_rule then
        for _, attr in ipairs( pac_cfg.ctd.mixing_attrs ) do
            cntr_mixing_condition = cntr_mixing_condition..",c."..attr.." = '"..pac_cfg.mixing_attr_value[attr].."'"
        end
    end
    local strCondition = "a.N_EMPTY_FULL = 1 AND a.C_ENABLE = 'Y' AND a.N_LOCK_STATE = 0"
    if cntr_mixing_condition ~= '' then
        strCondition = strCondition.." AND "..cntr_mixing_condition
    end
    local strOrder = "a.F_SCU_VALUE DESC"   -- 已占位多的托盘优先（剩余空间少的优先，优先补满）


    local data_objs
    local notfull_cntr_out_list = {}
    for _, sku in ipairs( sku_list ) do
        if sku.ok == false then
            local query_condition = strCondition.." AND ("..cntr_max_scu_value.." - a.F_SCU_VALUE ) >= "..sku.scu
            nRet, strRetInfo = mobox.queryMultiTable(strLuaDEID, strAttrs, strTable, 1800, query_condition, strOrder)
            if nRet ~= 0 then
                return 2, "查询【容器料格】信息失败! " .. strRetInfo
            end
            if strRetInfo ~= '' then
                data_objs = json.decode(strRetInfo)
                alloc_sku_to_notfull_cntr( pac_cfg, data_objs, sku, notfull_cntr_out_list )
            end 
        end
    end
    lua.table_merge( out_cntr_list, notfull_cntr_out_list )
    
    return 0 
 
end

-- 从仓库获取空的托盘或容器，将 plan_out_cntr_list 中计划的货品分配进去
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数
-- @tparam table sku_list 货品列表（alloc_qty/ok 字段会被修改）
-- @tparam table plan_out_cntr_list FFD算法计算出的计划空容器列表（cntr_code 会被分配实际容器编码）
-- @tparam table out_cntr_list 输出容器列表（会被追加分配结果）
-- @treturn number nRet 0: 成功, 1: 参数错误或数据库查询失败
-- @treturn string strRetInfo 错误信息（成功时为空字符串）
local function get_out_empty_cntr( strLuaDEID, pac_cfg, sku_list, plan_out_cntr_list, out_cntr_list )
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

    -- 注： N_EMPTY_FULL = 0 表示空箱 N_LOCK_STATE = 0 表示料格没锁
    local strCondition
    local strTable = "TN_Container a INNER JOIN TN_Loc_Container b ON a.S_CODE = b.S_CNTR_CODE "..
                     "INNER JOIN TN_Location c ON b.S_LOC_CODE = c.S_CODE "

    if pac_cfg.dbtype == DB_TYPE.SQLServer then    
        strCondition = "a.S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."' AND a.C_ENABLE = 'Y' AND a.N_EMPTY_FULL = 0 AND a.N_LOCK_STATE = 0 AND "..
                       "a.S_CODE IN (select S_CNTR_CODE from TN_Loc_Container with (NOLOCK) where S_LOC_CODE IN (select S_CODE from TN_Location with (NOLOCK) where "..str_loc_where..")) "
    else
        strCondition = "a.S_CTD_CODE = '"..pac_cfg.ctd.ctd_code.."' AND a.C_ENABLE = 'Y' AND a.N_EMPTY_FULL = 0 AND a.N_LOCK_STATE = 0 AND "..
                       "a.S_CODE IN (select S_CNTR_CODE from TN_Loc_Container where S_LOC_CODE IN (select S_CODE from TN_Location where "..str_loc_where..")) "
    end
    -- 获取料箱编码，货位，巷道编码
    local strAttrs = "a.S_CODE, b.S_LOC_CODE, c.S_AISLE_CODE"
    local strOrder = 'a.S_CODE'
    local nRet, cntr_list = wms_base.Get_Matching_cntr_list( strLuaDEID, pac_cfg, strTable, strAttrs, 3, strCondition, strOrder)
    if nRet ~= 0 then
        return 1, "获取所有符合条件的料箱失败! "..cntr_list
    end
 
    local find, cntr_code

    -- 获取空托盘
    for _, empty_cntr in ipairs( cntr_list ) do
        cntr_code = empty_cntr.cntr_code
        find = false
        -- 空托盘/容器分配 SKU
        for _, cntr in ipairs( plan_out_cntr_list ) do
            if cntr.cntr_code == '' then
                cntr.cntr_code = cntr_code
                find = true
                -- 巷道的任务数量加一
                wms_base.Add_Aisle_Task_Num( pac_cfg.aisle_set, empty_cntr.aisle_code )

                add_alloc_qty( sku_list, cntr.sku_list )
                table.insert( out_cntr_list, cntr )
                break
            end
        end
        if find == false then
            -- plan_out_cntr_list 已经全部分配的容器
            break
        end
    end
    return 0    
end

--[[ 
    First Fit Decreasing 核心算法，根据货品计算出需要呼出的空托盘列表
    输入参数:
        sku_list  货品列表
        cntr_max_scu_value 容器类型定义中定义的最大特殊计数值
    输出:
        plan_out_cntr_list FFD算法计算出的需要的空托盘列表
        {
            cntr_code = ''
            rem_cap = X -- 剩余存储容量
            sku_list = {
                            {sku},
                            ...
                    }
        }
--]]
-- First Fit Decreasing 核心算法，根据货品计算出需要呼出的空容器计划列表
-- @tparam table sku_list 货品列表（已按计量值降序排列）
-- @tparam number cntr_max_scu_value 容器类型最大特殊计数值
-- @tparam table plan_out_cntr_list 输出的计划空容器列表（会被追加）

local function get_plan_out_cntr_list( sku_list, cntr_max_scu_value, plan_out_cntr_list )  
    local qty      
    local find

    -- First Fit Decreasing
    for _, sku in ipairs( sku_list ) do
        qty = sku.qty - sku.alloc_qty
        for n = 1, qty do
            find = false
            -- 从已经分配的容器里查找是否有合适的容器
            for _, bin in ipairs( plan_out_cntr_list ) do
                if bin.rem_cap >= sku.scu then
                    find = true
                    bin.rem_cap = bin.rem_cap - sku.scu
                    add_sku_to_bin_sku_list( bin.sku_list, sku )
                    break
                end
            end
            if find == false then
                -- 新分配一个容器
                local bin = {
                    cntr_code = '',
                    rem_cap = cntr_max_scu_value - sku.scu,
                    sku_list = {}
                }
                if bin.rem_cap == 0 then
                    bin.full = true
                end
                -- 深度拷贝 SKU 对象，避免引用问题
                local new_sku = lua.table_deepcopy( sku )
                new_sku.qty = 1
                table.insert( bin.sku_list, new_sku )
                table.insert( plan_out_cntr_list, bin )
            end
        end
    end
    
end
--[[
    料箱料格类型根据 SKU 中的 S_CELL_TYPE 获取
    输入参数: pac_cfg = {
                wh_code, area_code  仓库，库区编码
                aisle_lb -- 巷道均衡，0 不考虑 1 -- 任务均衡
                aisle_set = { { aisle_code, task_num, cntr_list = {}},...}

                station 站台
                bs_type 来源类型：入库单、入库波次
                bs_no 来源单号   
                aisle -- 可用巷道 'A01',"A02",... 字符串
                cntr_alloc_rule -- 容器呼出策略:  0 -- 出库容器数量少优先， 1 -- 容器利用率优先

                cntr_out_op_def = "料箱出库",           --空料箱出库的作业定义
                cntr_back_op_def = "货品入库"           --料箱回库的主业定义       
                          
                -- 容器类型定义
                ctd = {
                    check_capacity = false/true, ---是否检测整箱载重, 
                    load_capacity = 50,         -- 托盘最大载重
                    have_mixing_rule = false/true  true 表示有混箱规则
                    mixing_attrs = {"A","B"} -- 这些属性一样的可以放一个料箱
                }
            }
            sku_list -- 需要预分配料箱的货品列表(注意这里入库的货品的容器类型都一样,并且混箱规则也是一样的)
            {
                -- 用于算法的一些属性
                row -- 出库单明细/出库波次明细行号（唯一值）
                qty  -- 入库数量
                alloc_qty -- 已经分配有入库容器的SKU数量
                volume -- sku 体积
                weight -- sku 重量
                scu -- sku 特定计量值（和volume等有一样的作用）
                ok -- 是否已经分配完成
                cntr_cell_list -- 预分配容器料格列表
                sku_grid_parm -- sku在不同料格的存储数量定义

                --- 下面就是 SKU 的数据表字段
                S_ITEM_CODE，S_STORER, ...
            }
    返回参数:
            supplement_cntr_list, out_cntr_list 为返回值
--]]

-- 预分配容器（FFD算法入口），将入库SKU分配到托盘/容器中
-- @function wms_pac_ffd.Pre_Alloc_Cntr_FFD
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数
-- @tparam table sku_list 需要预分配容器的货品列表
-- @treturn number nRet 0: 成功, 1: 部分货品未分配, 2: 输入参数错误
-- @treturn table/string 成功时返回 out_cntr_list, 失败时返回错误信息字符串
function wms_pac_ffd.Pre_Alloc_Cntr_FFD( strLuaDEID, pac_cfg, sku_list )
    local nRet, strRetInfo
    local wh_code
    local sku_count = #sku_list
    local out_cntr_list = {}

    -- step1: 输入参数校验,及初始化
    if sku_count == 0 then
        return 0
    end

    if pac_cfg == nil or type( pac_cfg ) ~= "table" then
        return 2, "Pre_Alloc_Cntr_FFD 函数输入参数错误: pac_cfg 必须有值，必须是 table 类型"
    end

    wh_code = lua.Get_StrAttrValue( pac_cfg.wh_code )
    if wh_code == '' then
        return 2, "Pre_Alloc_Cntr_FFD 函数输入参数错误: pac_cfg 参数中的 wh_code 必须有值!"
    end

    local cntr_type = lua.Get_StrAttrValue( pac_cfg.ctd.type )
    if cntr_type ~= "Pallet" and cntr_type ~= "Normal" then
        return 2, "Pre_Alloc_Cntr_FFD 算法只适合 Pallet/Normaly 类型的容器进行预分配!"
    end      
    local ctd_code = pac_cfg.ctd.ctd_code
    if ctd_code == nil or ctd_code == '' then
        return 2, "Pre_Alloc_Cntr_FFD 输入参数错误， pac_cfg 中 ctd.ctd_code 必须有值"
    end
    -- step2: 根据容器的计数方式对 SKU 进行排序，计量值大的排前面
    if pac_cfg.ctd.count_method == "SCU" then
        table.sort( sku_list, sku_scu_sort )
    elseif pac_cfg.ctd.count_method == "Volume" then
        table.sort( sku_list, sku_volume_sort )        
    elseif pac_cfg.ctd.count_method == "Weight" then
        table.sort( sku_list, sku_weight_sort ) 
    else
        return 2, "FFD目前只支持 SCU/Volume/Weight这三种计数方式"
    end

    -- step3: 根据容器呼出的策略呼出容器进行入库
    local cntr_max_scu_value = pac_cfg.ctd.max_scu_value or 0
    if cntr_max_scu_value == 0 then
        return 2, "容器类型定义中没有定义最大特殊计数值!"
    end
    local plan_out_cntr_list = {}   --  计划中需要呼出的空容器列表
                                    --  { rem_scu_value, sku_list = {}, cntr_code}
    local pac_is_ok
    if pac_cfg.cntr_alloc_rule == nil or pac_cfg.cntr_alloc_rule == 0 then
        -- 呼出容器数量最少优先
        -- 算法的核心是先呼出空的托盘或容器
        get_plan_out_cntr_list( sku_list, cntr_max_scu_value, plan_out_cntr_list )  
        -- 从数据库查找出空托盘分配给 plan_out_cntr_list
        nRet, strRetInfo = get_out_empty_cntr( strLuaDEID, pac_cfg, sku_list, plan_out_cntr_list, out_cntr_list )
        if nRet ~= 0 then
            return 1, strRetInfo
        end
        pac_is_ok = wms_base.item_list_is_all_ok( sku_list )
        if pac_is_ok == false then
            -- 检查是否还有未分配托盘的货品，这些需要呼出未满的托盘进行存储
            nRet, strRetInfo = get_notfull_cntr_list( strLuaDEID, pac_cfg, sku_list, out_cntr_list )
            if nRet ~= 0 then
                return 1, strRetInfo
            end
        end
    else
        -- 先从未满的托盘\容器里呼出还有空间的托盘\容器进行存储
        nRet, strRetInfo = get_notfull_cntr_list( strLuaDEID, pac_cfg, sku_list, out_cntr_list )
        if nRet ~= 0 then
            return 1, strRetInfo
        end 
        get_plan_out_cntr_list( sku_list, cntr_max_scu_value, plan_out_cntr_list )  
        -- 从数据库查找出空托盘分配给 plan_out_cntr_list
        nRet, strRetInfo = get_out_empty_cntr( strLuaDEID, pac_cfg, sku_list, plan_out_cntr_list, out_cntr_list )
        if nRet ~= 0 then
            return 1, strRetInfo
        end        
    end

    local msg_list = {}                         -- 保存无法分配料格的货品数量
    for _, sku in ipairs( sku_list ) do
        if sku.ok == false then
            local qty = sku.qty-sku.alloc_qty
            local msg = "系统没有匹配合适的托盘/容器存储 货品编码 = '"..sku.S_ITEM_CODE.."' 的货品, 数量 = "..qty
            table.insert( msg_list, msg )
        end
    end   
    if #msg_list > 0 then
        -- 这些货品没有合适的料箱
        return 1,  lua.table2str( msg_list )
    end      
    return 0, out_cntr_list
end

-- 生成【预分配容器】和【预分配容器明细】数据对象并保存到数据库
-- @function wms_pac_ffd.Generate_Pac_Detail
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table pac_cfg 预分配配置参数
-- @tparam table bin 容器信息 { cntr_code, sku_list }
-- @tparam table pac_list 预分配容器对象列表（会被追加 Pre_Alloc_Container 对象）
-- @tparam table pac_detail_list 预分配容器明细对象列表（会被追加 Pre_Alloc_CNTR_Detail 对象）
-- @treturn number nRet 0: 成功, 1: 创建对象失败
-- @treturn string strRetInfo 错误信息（成功时为空字符串）
function wms_pac_ffd.Generate_Pac_Detail( strLuaDEID, pac_cfg, bin, pac_list, pac_detail_list )
    local nRet
    local pac = m3.AllocObject2( strLuaDEID, "Pre_Alloc_Container" )

    if pac == nil then
        return 1, "创建【预分配容器】对象失败!"
    end
    pac.S_CNTR_CODE = bin.cntr_code
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
    local item_base_attr_count = #ITEM_BASE_ATTRS
    local udf_attr_count = #UDF_ATTRS

    for _, sku in ipairs( bin.sku_list ) do 
        pac_detail = m3.AllocObject2( strLuaDEID, "Pre_Alloc_CNTR_Detail" )
        if pac_detail == nil then
            return 1, "创建【预分配容器明细】对象失败!"
        end
        pac_detail.S_PAC_NO = pac.S_PAC_NO
        pac_detail.S_CNTR_CODE = bin.cntr_code
        pac_detail.S_STATION_NO = pac_cfg.station

        for m = 1, item_base_attr_count do
            pac_detail[ITEM_BASE_ATTRS[m]] = sku[ITEM_BASE_ATTRS[m]]
        end
        for m = 1, udf_attr_count do
            pac_detail[UDF_ATTRS[m]] = sku[UDF_ATTRS[m]]
        end        

        pac_detail.F_QTY = sku.qty
        pac_detail.S_BS_TYPE = pac_cfg.bs_type
        pac_detail.S_BS_NO = pac_cfg.bs_no
        pac_detail.N_BS_ROW_NO = sku.row

        nRet, pac_detail = m3.CreateDataObj2(strLuaDEID, pac_detail)
        if nRet ~= 0 then 
            return 1, "创建【预分配容器明细】失败!"..pac_detail 
        end   
        table.insert( pac_detail_list, pac_detail )
    end
    return 0
end

return wms_pac_ffd