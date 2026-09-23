--[[
    版本：     Version 3.0
    创建日期： 2025-1-28
    修改日期:  2026-6-20
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    名称:   wms_base_algorithm
    功能：   WMS 过程中对一些货位分配方面的基本算法

    【货位任务统计】
        GetAreaLocTaskNumber           — 获取某个区域中货位已分配的任务数量

    【空货位计算】
        Get_Aisle_Empty_Loc            — 已知巷道号获取巷道内空货位
        Get_One_Available_Location_InArea — 从库区中获取一个可用空货位
        Get_One_Available_Location_InArea2 — 从库区中获取一个可用空货位        
        Get_Area_EmptyLocation_Num     — 获取库区空货位数量

    【容器货位】
        Get_One_Container_Slot_InArea  — 获取指定库区中一个存储了料箱的货位
        Get_Area_Location_With_Cntr_Num — 获取库区有绑定容器的货位数量

    【站台分配】
        Get_Station_Active_OutOp_Num   — 获取站台活跃出库作业数量
        Station_Allocation             — 站台分配（公平轮询）
    ----------------------------        
    【拣货箱计算】
        Calculate_Picking_Bin_Qty       — 计算拣货箱数量
    更改记录:
        2025-1-28  HAN  创建
        2026-6-20        整理函数注释，添加 @tparam/@treturn 注解

    AI CHECK:
        -- 20260620
--]]

json  = require ("json")
mobox = require ("OILua_JavelinExt")
wms   = require ("OILua_WMS")
lua   = require ("oi_base_func")
m3    = require ("oi_base_mobox")

local wms_alg = {_version = "0.2.1"}

-- 货位任务数量排序比较函数（table.sort 使用），任务少的优先
-- @function loc_tasknum_sort
-- @tparam table loc1 {task_num}
-- @tparam table loc2 {task_num}
-- @treturn boolean loc1.task_num < loc2.task_num
local function loc_tasknum_sort( loc1, loc2 )
    return loc1.task_num < loc2.task_num
end

-- 将 table 转换为 SQL IN 子句字符串
-- @function stringToSQLIn
-- @tparam table tbl 值数组
-- @treturn string SQL IN 子句，如 "'A','B'"
local function stringToSQLIn(tbl)
    if #tbl == 0 then
        return "''"
    end

    local result = {}
    for _, value in ipairs(tbl) do
        -- 对字符串进行处理，添加引号并转义单引号
        if type(value) == "string" then
            value = string.gsub(value, "'", "''")
            table.insert(result, "'" .. value .. "'")
        -- 处理布尔值
        elseif type(value) == "boolean" then
            table.insert(result, value and "true" or "false")
        -- 处理其他类型（主要是数字）
        else
            table.insert(result, tostring(value))
        end
    end
    return table.concat(result, ",")
end

-- 生成查询空货位的 SQL 条件
-- @function get_empty_loc_sql
-- @tparam table area_list 库区编码数组
-- @tparam string condition 附加条件
-- @treturn string SQL WHERE 条件
local function get_empty_loc_sql(area_list, condition)
    if condition == nil or condition == '' then
        condition = " 1=1 "
    end
    local strCondition
    if area_list ~= nil and #area_list > 0 then
        local area_list_in_condition = stringToSQLIn(area_list)
        strCondition = string.format([[N_LOCK_STATE = 0 AND C_ENABLE = 'Y' AND N_CAPACITY > N_CURRENT_NUM AND S_AREA_CODE IN (%s) AND %s 
        AND NOT EXISTS(SELECT 1 FROM TN_Loc_Container WHERE S_LOC_CODE=TN_Location.S_CODE)
        AND NOT EXISTS(SELECT 1 FROM TN_INV_Detail WHERE S_LOC_CODE=TN_Location.S_CODE AND F_QTY>0)
        AND NOT EXISTS(SELECT 1 FROM TN_Operation WHERE S_END_LOC=TN_Location.S_CODE AND N_B_STATE IN(0,1,3,4,5,6,8))]],
        area_list_in_condition, condition)
    else
        strCondition = string.format([[N_LOCK_STATE = 0 AND C_ENABLE = 'Y' AND N_CAPACITY > N_CURRENT_NUM AND %s
        AND NOT EXISTS(SELECT 1 FROM TN_Loc_Container WHERE S_LOC_CODE=TN_Location.S_CODE)
        AND NOT EXISTS(SELECT 1 FROM TN_INV_Detail WHERE S_LOC_CODE=TN_Location.S_CODE AND F_QTY>0)
        AND NOT EXISTS(SELECT 1 FROM TN_Operation WHERE S_END_LOC=TN_Location.S_CODE AND N_B_STATE IN(0,1,3,4,5,6,8))]],
        condition)
    end
    return strCondition
end

--[[
    获取某个区域中货位已经分配的任务数量，返回一个货位任务列表, 一般这样的区域是接驳区，理货区
    输入参数:
        area_code -- 库区编码
    返回参数:
        nRet
        loc_list  (area_code库区中货位基本信息)
--]]
-- 获取某个区域中货位已经分配的任务数量
-- @function wms_alg.GetAreaLocTaskNumber
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table loc_list 货位任务列表 [{loc_code, task_num}]
function wms_alg.GetAreaLocTaskNumber( strLuaDEID, area_code )
    local nRet, strRetInfo

    if  area_code == nil or area_code == '' then
        return 1, "wms_alg.GetAreaLocTaskNumber 函数中的 area_code 必须有值!"
    end

    -- 获取库区货位的使用情况
    local strCondition = "C_ENABLE = 'Y' AND S_AREA_CODE = '"..area_code.."'"
    local strOrder = "S_CODE"
    local loc_objs, loc_info
    local loc_list = {}
    local task_num

    nRet, loc_objs = m3.QueryDataObject( strLuaDEID, "Location", strCondition, strOrder )
    if nRet ~= 0 then
        return 1, "获取【Location】信息失败! " .. loc_objs
    end
    local obj_attrs
    for n = 1, #loc_objs do
        obj_attrs = m3.KeyValueAttrsToObjAttr(loc_objs[n].attrs)
        if obj_attrs == nil then
            return 1, "KeyValueAttrsToObjAttr 失败!"   
        end
        -- 获取该货位的出入库任务数量   
        -- N_B_STATE < 3 表示任务的状态为 0等待/1已推送/2执行中, 任务有一个点在 storage_area  的巷道 aisle
        -- 任务包括进出
        strCondition = "N_B_STATE < 3 AND ( S_START_LOC = '"..obj_attrs.S_CODE.."' or S_END_LOC = '"..obj_attrs.S_CODE.."')"
        nRet, strRetInfo = mobox.getDataObjCount( strLuaDEID, "Task", strCondition )
        if  nRet ~= 0  then
            return nRet, strRetInfo
        end
 
        task_num = lua.StrToNumber( strRetInfo )    
        local loc_info = {
            loc_code = obj_attrs.S_CODE,
            capacity = lua.StrToNumber( obj_attrs.N_CAPACITY ),
            cur_num = lua.StrToNumber( obj_attrs.N_CURRENT_NUM ),
            task_num = task_num,                                                -- 任务数量
            abc_cls = ""                                                        -- ABC 分类
        }
        table.insert( loc_list, loc_info )
    end
    table.sort( loc_list, loc_tasknum_sort )
    return 0, loc_list
end

-- 排序
-- 巷道内货位排序比较函数（table.sort 使用）
-- @function aisle_loc_sort
-- @tparam table loc1 {abc_cls, weight}
-- @tparam table loc2 {abc_cls, weight}
-- @treturn boolean loc1优先返回true，否则false
local function aisle_loc_sort( loc1, loc2 )
    if  loc1.abc_cls < loc2.abc_cls  then
        return true
    elseif  loc1.abc_cls == loc2.abc_cls  then
        -- 距离入口近的优先
        return loc1.weight < loc2.weight
    end
    return false
end

--[[
    已知巷道号获取巷道内空货位，如果一次搬运两个料箱希望货位在相邻列同层次，否则计算两个货位，优先级
    如果是双工位，货位计算优先级
        1 -- 有相邻2个货位
        2 -- 和第一个货位最近，比如上面，下面，左边，右边一格
    输入参数:
    area_code -- 巷道所在库区
    aisle -- 巷道号
    order_method -- 0 -- 根据货位中的 weight/weight2(权重) 进行排序 1 -- 先放满层  2 -- 先放满列

    loc_order -- 0 表示列值最小的就在出库口， 1 -- 相反列值最大的在巷道口
    strAddCondition -- 附加条件 （可以不输入默认为空）是针对 Loaction 表的附加条件
    loc_num -- 需要的货位数量 1个或2个 2 表示是双工位堆垛机 可以不输入默认=1
    返回：
    {
        loc_code
        adjacent_loc        -- 相邻空货位
    }
]]

-- 已知巷道号获取巷道内空货位
-- @function wms_alg.Get_Aisle_Empty_Loc
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 巷道所在库区
-- @tparam number aisle 巷道号
-- @tparam number order_method 排序方法 0:权重 1:先放满层 2:先放满列
-- @tparam number loc_order 列顺序 0:列值小近巷道口 1:列值大近巷道口
-- @tparam string strAddCondition 附加条件（可选）
-- @tparam number loc_num 需要的货位数量（默认1）
-- @treturn number nRet 0: 成功，1: 无空货位，2: 错误
-- @treturn table loc 货位对象 {loc_code, row, col, layer, weight, adjacent_loc}
function wms_alg.Get_Aisle_Empty_Loc( strLuaDEID, area_code, aisle, order_method, loc_order, strAddCondition, loc_num  )
    local nRet
    local loc_list = {}

    if  loc_num == nil or type(loc_num) ~= "number" then
        loc_num = 1
    end
    if  loc_order == nil or type(loc_order) ~= "number"  then
        loc_order = 0
    end
    if  order_method == nil or type(order_method) ~= "number"  then
        order_method = 0
    end
    if  strAddCondition == nil or type(strAddCondition) ~= "string"  then
        strAddCondition = ''
    end

    -- 获取巷道内所有空货位的顺序设置
    local strOrder = ""
    if  order_method == 0  then
        -- 根据权重排序
        strOrder = "N_POS_WEIGHT"
        -- 说明堆垛机是从列值最大的入口进入巷道
        if  loc_order == 1  then
            strOrder = "N_POS_WEIGHT_2"
        end
    elseif  order_method == 1  then
        -- 先放满最下面的层
        if  loc_order ==  0  then
            strOrder = "N_LAYER, N_COL"
        else
            strOrder = "N_LAYER, N_COL desc"
        end
    elseif  order_method == 2  then
        -- 先放满最靠近巷道口的列
        if  loc_order ==  0  then
            strOrder = "N_COL, N_LAYER"
        else
            strOrder = "N_COL desc, N_LAYER"
        end
    else
        return 1, "wms_alg.Get_Aisle_Empty_Loc 函数目前不支付 order_method = "..order_method.." 的算法!"
    end

    local loc_objs
    local count

    if  loc_num == 1  then
        count = 1
    else
        count = 100
    end
    local strCondition = "S_AREA_CODE = '"..area_code.."' AND N_CURRENT_NUM = 0 AND N_LOCK_STATE = 0 AND N_AISLE = "..aisle
    if  strAddCondition ~= ''  then
        strCondition = strCondition.." AND ("..strAddCondition..")"
    end

    nRet, loc_objs = m3.QueryDataObject3(strLuaDEID, "Location", strCondition, strOrder, count )
    if nRet ~= 0 then
        return 2, "QueryDataObject失败!"..loc_objs
    end
    if  loc_objs == '' then
        return 1, "没有空货位"
    end

    local loc_obj = {}
    local weight

    if  loc_num == 1  then
        loc_obj = m3.KeyValueAttrsToObjAttr(loc_objs[1].attrs)
        if loc_obj == nil then
            return 1, "KeyValueAttrsToObjAttr 失败!"
        end
        if  loc_order == 0  then
            weight = lua.Get_NumAttrValue( loc_obj.N_POS_WEIGHT )
        else
            weight = lua.Get_NumAttrValue( loc_obj.N_POS_WEIGHT2 )
        end
        local loc = {
            loc_code = loc_obj.S_CODE,
            row = lua.Get_NumAttrValue( loc_obj.N_ROW ),
            col = lua.Get_NumAttrValue( loc_obj.N_COL ),
            layer = lua.Get_NumAttrValue( loc_obj.N_LAYER ),
            weight = weight,
            abc_cls = '',                                         -- ABC 分类
            adjacent_loc = ''                                     -- 相邻货位
        }
        table.insert( loc_list, loc )
    else
        local nCount = #loc_objs
        if nCount < 2  then
            return 1, "没有空货位"
        end

        if nCount == 2  then
            local loc_obj = m3.KeyValueAttrsToObjAttr(loc_objs[1].attrs)
            if loc_obj == nil then
                return 1, "KeyValueAttrsToObjAttr 失败!"
            end
            local loc_obj2 = m3.KeyValueAttrsToObjAttr(loc_objs[2].attrs)
            if loc_obj2 == nil then
                return 1, "KeyValueAttrsToObjAttr 失败!"
            end
            if loc_order == 0  then
                weight = lua.Get_NumAttrValue( loc_obj.N_POS_WEIGHT )
            else
                weight = lua.Get_NumAttrValue( loc_obj.N_POS_WEIGHT2 )
            end            
            local loc = {
                loc_code = loc_obj.S_CODE,
                row = lua.Get_NumAttrValue( loc_obj.N_ROW ),
                col = lua.Get_NumAttrValue( loc_obj.N_COL ),
                layer = lua.Get_NumAttrValue( loc_obj.N_LAYER ),
                weight = weight,
                abc_cls = '',                                         -- ABC 分类
                adjacent_loc = loc_obj2.S_CODE                        -- 相邻货位
            }
            table.insert( loc_list, loc )            
        else
            for n = 1, nCount do
                loc_obj = m3.KeyValueAttrsToObjAttr(loc_objs[n].attrs)
                if loc_obj == nil then
                    return 1, "KeyValueAttrsToObjAttr 失败!"
                end
                if  loc_order == 0  then
                    weight = lua.Get_NumAttrValue( loc_obj.N_POS_WEIGHT )
                else
                    weight = lua.Get_NumAttrValue( loc_obj.N_POS_WEIGHT2 )
                end                   
                local loc = {
                    loc_code = loc_obj.S_CODE,
                    row = lua.Get_NumAttrValue( loc_obj.N_ROW ),
                    col = lua.Get_NumAttrValue( loc_obj.N_COL ),
                    layer = lua.Get_NumAttrValue( loc_obj.N_LAYER ),
                    weight = weight,
                    abc_cls = '',
                    adjacent_loc = ''
                }
                table.insert( loc_list, loc )
            end

            -- ABC分类，有两个紧邻的空货位的优先，设置为A，其余为B
            for n = 1, nCount do
                -- 不是最好一个空货位，最后一个空货位不需要判断是否有相邻货位
                if  n < nCount  then
                    -- 判断和下一个货位的weight的差距是否=1
                    for m = n+1, nCount do
                        if  loc_list[m].weight == (loc_list[n].weight + 1)  then
                            -- 判断是否同排同层
                            if  loc_list[m].row == loc_list[n].row and 
                                loc_list[m].layer == loc_list[n].layer  then
                                loc_list[n].abc_cls = "A"
                                loc_list[n].adjacent_loc = loc_list[m].loc_code
                                break
                            end
                        else
                            loc_list[n].abc_cls = "B"
                            break
                        end
                    end
                else
                    loc_list[n].abc_cls = "B"
                end
            end
            -- 重新排序
            table.sort( loc_list, aisle_loc_sort )

            if  loc_list[1].abc_cls ~= 'A'  then
                loc_list[1].adjacent_loc = loc_list[2].loc_code
            end
        end
    end
    return 0, loc_list[1]
end

--[[
    获取指定库区中一个可用的空货位
    参数:
        area_code -- 库区编码
        condition -- 查询条件，可以为空
        order -- 顺序，可以为空
    返回值:
        nRet, loc( 数据对象 )
--]]
-- 从库区中获取一个可用的空货位 (不推荐) 推荐用Get_One_Available_Location_InArea2
-- @function wms_alg.Get_One_Available_Location_InArea
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @tparam string condition 查询条件（可选）
-- @tparam string order 排序（可选）
-- @treturn number nRet 0: 成功，1: 无空货位，2: 错误
-- @treturn table/string loc 货位对象或空字符串
function wms_alg.Get_One_Available_Location_InArea( strLuaDEID, area_code, condition, order )
    local nRet

    if lua.StrIsEmpty( area_code ) then
        return 1, "Get_One_Available_Location_InArea 函数的输入参数 area_code 必须有值!"
    end
    if condition == nil then
        condition = ''
    end
    if order == nil then
        order = ''
    end

    local area_list={}
    table.insert(area_list,area_code)
    local strCondition = get_empty_loc_sql(area_list,condition)
    local loc
    nRet, loc = m3.GetDataObjByCondition( strLuaDEID, "Location", strCondition, order )
    if nRet == 0 then
        return 0, loc
    end
    if nRet == 1 then
        return 0, ""
    end
    return 2, loc
end

-- 从库区中获取一个可用的空货位
-- @function wms_alg.Get_One_Available_Location_InArea2
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @tparam string condition 查询条件（可选）
-- @tparam string order 排序（可选）
-- @treturn number nRet 0: 成功，1: 无空货位，2: 错误
-- @treturn table/string loc 库位对象（属性为字段名）或空字符串
function wms_alg.Get_One_Available_Location_InArea2( strLuaDEID, area_code, condition, order )
    local nRet

    if lua.StrIsEmpty( area_code ) then
        return 1, "Get_One_Available_Location_InArea 函数的输入参数 area_code 必须有值!"
    end
    if condition == nil then
        condition = ''
    end
    if order == nil then
        order = ''
    end

    local area_list={}
    table.insert(area_list,area_code)
    local strCondition = get_empty_loc_sql(area_list,condition)
    local loc
    nRet, loc = m3.GetDataObjByCondition2( strLuaDEID, "Location", strCondition, order )
    if nRet == 0 then
        return 0, loc
    end
    if nRet == 1 then
        return 0, ""
    end
    return 2, loc
end

--[[
    获取指定库区中一个有容器的货位
    参数:
        area_code -- 库区编码
        condition -- 查询条件，可以为空
        order -- 顺序，可以为空
    返回值:
        nRet, loc
--]]
-- 获取指定库区中一个存储了料箱的货位
-- @function wms_alg.Get_One_Container_Slot_InArea
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @tparam string condition 查询条件（可选）
-- @tparam string order 排序（可选）
-- @treturn number nRet 0: 成功，1: 无容器货位，2: 错误
-- @treturn table/string loc 货位对象或空字符串
function wms_alg.Get_One_Container_Slot_InArea( strLuaDEID, area_code, condition, order )
    local nRet

    if lua.StrIsEmpty( area_code ) then
        return 1, "Get_One_Container_Slot_InArea 函数的输入参数 area_code 必须有值!"
    end
    if condition == nil then
        condition = ''
    end
    if order == nil then
        order = ''
    end

    local strCondition = "N_LOCK_STATE = 0 AND C_ENABLE = 'Y' AND N_CURRENT_NUM > 0 AND S_AREA_CODE = '"..area_code.."'"
    if condition ~= '' then
        strCondition = strCondition.." AND ("..condition..")"
    end
    local loc
    nRet, loc = m3.GetDataObjByCondition(strLuaDEID, "Location", strCondition, order )
    if nRet == 0 then
        return 0, loc
    end
    if nRet == 1 then
        return 0, ""
    end
    return 2, loc
end

--[[
    获取库区空货位数量
--]]
-- 获取库区空货位数量
-- @function wms_alg.Get_Area_EmptyLocation_Num
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn number empty_loc_num 空货位数量
function wms_alg.Get_Area_EmptyLocation_Num( strLuaDEID, area_code )
    local nRet, strRetInfo

    if lua.StrIsEmpty( area_code ) then
        return 1, "Get_Area_EmptyLocation_Num 函数里 area_code 不能为空!"
    end 
    local area_list={}
    table.insert(area_list,area_code)
    local strCondition = get_empty_loc_sql(area_list,"")
    nRet, strRetInfo = mobox.getDataObjCount( strLuaDEID, "Location", strCondition )
    if nRet ~= 0 then
        return nRet, strRetInfo
    end
 
    local empty_loc_num = lua.StrToNumber( strRetInfo )  
    
    return 0, empty_loc_num
end

--[[
    获取库区有绑定容器的货位数量
--]]
-- 获取库区有绑定容器的货位数量
-- @function wms_alg.Get_Area_Location_With_Cntr_Num
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string area_code 库区编码
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn number loc_num 有容器货位数量
function wms_alg.Get_Area_Location_With_Cntr_Num( strLuaDEID, area_code )
    local nRet, strRetInfo

    if lua.StrIsEmpty( area_code ) then
        return 1, "Get_Area_Location_With_Cntr_Num 函数里 area_code 不能为空!"
    end 
    local strCondition = "N_CURRENT_NUM > 0 AND C_ENABLE = 'Y' AND S_AREA_CODE = '"..area_code.."'"
    nRet, strRetInfo = mobox.getDataObjCount( strLuaDEID, "Location", strCondition )
    if nRet ~= 0 then
        return nRet, strRetInfo
    end
 
    local loc_num = lua.StrToNumber( strRetInfo )  
    
    return 0, loc_num
end

--[[
    获取到某个站台的作业数量（出库）
--]]
-- 获取站台活跃出库作业数量
-- @function wms_alg.Get_Station_Active_OutOp_Num
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string station 站台号
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn number op_num 出库作业数量
function wms_alg.Get_Station_Active_OutOp_Num( strLuaDEID, station )
    local nRet, strRetInfo

    if lua.StrIsEmpty( station ) then
        return 1, "Get_Station_Active_OutOp_Num 函数里 station 不能为空!"
    end 
    --local strCondition = "N_B_STATE IN (0,1,6,8) AND S_STATION_NO = '"..station.."'"
    local strCondition = "N_B_STATE IN (0,1) AND S_STATION_NO = '"..station.."'"
    nRet, strRetInfo = mobox.getDataObjCount( strLuaDEID, "Operation", strCondition )
    if nRet ~= 0 then
        return nRet, strRetInfo
    end
 
    local op_num = lua.StrToNumber( strRetInfo )  
    
    return 0, op_num
end

--[[
    站台分配
    -- 一般用在分拣出库时，把需要出库的料箱根分配一个合适的站台
    -- 也可以用在需要盘点的料箱分配站台

    输入参数:
        available_station_set   站台编号数组 
            {
                station_no = "S1", 
                limit= 100,         站台最大作业数量
                cur_op_num = 0,     当前站台未完成作业
                alloc_num = 0       分配的作业数量
                used = 0
            }
        cntr_num 需要进行站台分配的料箱数量
--]]
-- 站台分配（公平轮询），用于分拣出库时将料箱分配到合适的站台
-- @function wms_alg.Station_Allocation
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table available_station_set 站台数组 [{station_no, limit, cur_op_num, alloc_num}]
-- @tparam number cntr_num 需要分配的料箱数量
-- @treturn number nRet 0: 成功，1: 失败
function wms_alg.Station_Allocation( strLuaDEID, available_station_set, cntr_num )
    local nRet, station_data
    local cur_op_num = 0
    local num_station = #available_station_set

    if num_station == 0  then
        return 1, "可分配的站台数量为0"
    end

    for _, as in ipairs( available_station_set ) do
        nRet, station_data = m3.GetDataFromCache( "Machine_Station", as.station_no )
        if  nRet ~= 0  then
            return 1, "获取站台信息失败!"..station_data
        end 
        as.tp_area = station_data.S_TP_AREA     -- 站台的接驳区（出库、入库作业区域）
        as.limit = lua.Get_NumAttrValue( station_data.N_MAX_OP_NUM )
        
        nRet, cur_op_num = wms_alg.Get_Station_Active_OutOp_Num( strLuaDEID, as.station_no )
        if nRet ~= 0 then
            return 1, "Get_Station_Active_OutOp_Num 失败!"..cur_op_num
        end
        as.cur_op_num = cur_op_num  
        as.total_num = cur_op_num    
        as.alloc_num = 0
        as.used = 0                     -- 已经使用 
    end

    local last_selected_index = 0

    for n = 1, cntr_num do
        local min_total = math.huge

        for _, as in ipairs( available_station_set ) do
            if as.total_num < as.limit and as.total_num < min_total then
                min_total = as.total_num
            end
        end

        if min_total == math.huge then
            break
        end

        -- 轮询选择站台（公平分配）
        local start_index = (last_selected_index % num_station) + 1
        local selected_index = nil
        local index = start_index
        
        repeat
            local as = available_station_set[index]
            if as.total_num == min_total and as.total_num < as.limit then
                selected_index = index
                break
            end
            index = (index % num_station) + 1  -- 移动到下一个站台
        until index == start_index
        
        -- 分配作业
        if selected_index then
            available_station_set[selected_index].alloc_num = available_station_set[selected_index].alloc_num + 1
            available_station_set[selected_index].total_num = available_station_set[selected_index].total_num + 1
            last_selected_index = selected_index
        else
            break  -- 安全终止
        end        
    end

    return 0
end

-- 插入SKU到SKU列表，如果id相同则合并数量
local function insert_sku_list( sku_list, sku_item )
    for _, sku in ipairs(sku_list) do
        if sku.id == sku_item.id then
            sku.F_QTY = sku.F_QTY + sku_item.F_QTY
            return
        end
    end
    table.insert(sku_list, sku_item)
end

-- 计算装这些SKU需要多少个拣料箱
-- @function wms_alg.Calculate_Picking_Bin_Qty
-- @tparam table sku_detail_list SKU清单，这些数据来自入库单明细或入库单波次明细
-- @tparam number picking_bin_volume 拣料箱的体积
-- @treturn number nRet 0: 成功，1: 失败
-- @treturn table picking_bin_list 需要的拣料箱列表，失败返回错误信息
--[[
sku_detail_list = {
                        {
                        id = "",
                        cls_id = "",
                        S_ITEM_CODE = "",
                        F_QTY = 1,
                        F_VOLUME = 20,
                        ...
                        }
                    }
]]
function wms_alg.Calculate_Picking_Bin_Qty( sku_detail_list, picking_bin_volume )
    local picking_bin_list = {}

    if ( picking_bin_volume == nil or picking_bin_volume <= 0 ) then 
        return 1, "拣料箱的体积不合法必须大于0"
    end

    -- 数据初始化
    for _, sku in ipairs(sku_detail_list) do
        if sku.id == nil or sku.id == '' then
            return 1, "输入参数 sku_detail_list 不正确, 链表里数据对象标识ID不能为空!"
        end
        if sku.S_ITEM_CODE == nil then
            return 1, "输入参数 sku_detail_list 不正确, 链表里货品编码不能为空"
        end
        sku.volume = lua.Get_NumAttrValue( sku.F_VOLUME )
        if sku.volume <= 0 then
            return 1, "货品编码 = '"..sku.S_ITEM_CODE.."' 的体积不合法 !"
        end
        if sku.volume > picking_bin_volume then
            return 1, "货品编码 = '"..sku.S_ITEM_CODE.."' 的体积不能大于拣料箱体积 !"
        end        
        sku.qty = sku.F_QTY
        sku.alloc_qty = 0
    end

    -- sku_detail_list 排序一下，体积大的先放
    table.sort( sku_detail_list, function(a, b) return a.volume > b.volume end )    

    for _, sku in ipairs(sku_detail_list) do
        local qty = sku.qty
        -- 1) 批量填充已有箱子：一个箱子一次能放 floor(剩余空间/单件体积) 件，一次扣完
        for _, picking_bin in ipairs(picking_bin_list) do
            if qty <= 0 then
                break
            end
            if picking_bin.x_volume >= sku.volume then
                local fit = math.floor( picking_bin.x_volume / sku.volume )
                if fit > qty then
                    fit = qty
                end
                local sku_item  = lua.table_copy(sku)
                sku_item.F_QTY = fit
                insert_sku_list( picking_bin.sku_list, sku_item )
                picking_bin.x_volume = picking_bin.x_volume - fit * sku.volume
                qty = qty - fit
            end
        end
        -- 2) 剩余件数一次性算出需要的新箱子数，批量创建
        if qty > 0 then
            local per_box = math.floor( picking_bin_volume / sku.volume )
            local need = math.ceil( qty / per_box )
            for i = 1, need do
                -- 最后一箱可能不满，剩余空间按实际件数计算
                local fit = math.min( per_box, qty )
                local bin_remain = picking_bin_volume - fit * sku.volume
                local new_picking_bin = {
                    x_volume = bin_remain,
                    sku_list = {}
                }
                local sku_item  = lua.table_copy(sku)
                sku_item.F_QTY = fit
                table.insert( new_picking_bin.sku_list, sku_item )
                table.insert( picking_bin_list, new_picking_bin )
                qty = qty - per_box
            end
        end
        sku.alloc_qty = sku.F_QTY   -- 该 SKU 全部已分配
    end
  
    return 0, picking_bin_list
end

return wms_alg