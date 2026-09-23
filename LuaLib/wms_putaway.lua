--[[
    版本：     Version 3.0
    创建日期： 2025-3-26
    修改日期： 2026-6-18
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    名称:   wms_putaway
    应用:   用于入库时计算库区中的可用货位，以及入库作业等相关操作
            和上架相关的一些函数

     【货位计算】
        Get_StorageCache_Loc  — 获取立库入库缓存区及立库内存储货位
        Get_Storage_LocArea   — 根据上架策略获取容器的储存位置

    更改记录:
        2025-3-26  HAN  创建
        2026-6-18        整理函数注释，完善 @tparam/@treturn 注解

    AI CHECK:
        -- 20260618
--]]

wms_wh   = require ("wms_wh")
wms_alg  = require ("wms_base_algorithm")
wms_wcs = require ("wms_wcs")
wms_station = require( "wms_station" )

local wms_putaway = {_version = "0.2.1"}
-- 巷道内任务+空料箱排序（table.sort 比较函数）
-- @function aisle_list_sort
-- @tparam table loc1 巷道对象 {abc_cls, aisle_empty_num}
-- @tparam table loc2 巷道对象 {abc_cls, aisle_empty_num}
-- @treturn boolean loc1优先返回true，否则false
local function aisle_list_sort( loc1, loc2 )
    if loc1.abc_cls < loc2.abc_cls then
        return true
    elseif loc1.abc_cls == loc2.abc_cls then
        -- 巷道空位多优先
        return loc1.aisle_empty_num > loc2.aisle_empty_num
    end
    return false
end

-- 任务数量ABC分类（按巷道任务数设置ABC分类并排序）
-- @function task_num_abc_cls
-- @tparam table aisle_list 巷道列表 [{task_num, aisle_empty_num}]，原地修改并排序
local function task_num_abc_cls( aisle_list )
    local max_task_num = 0
    local nCount

    nCount = #aisle_list
    if 0 == nCount then
        return 0
    end
    for n = 1, nCount do
        if aisle_list[n].task_num > max_task_num then
            max_task_num = aisle_list[n].task_num
        end
    end
    if max_task_num <= 3 then
        for n = 1, nCount do
            if aisle_list[n].task_num == 0 then
                aisle_list[n].abc_cls = "A"
            elseif aisle_list[n].task_num >= 2 then
                aisle_list[n].abc_cls = "C"
            else
                aisle_list[n].abc_cls = "B"
            end 
        end           
    else
        for n = 1, nCount do
            if aisle_list[n].task_num == 0 then
                aisle_list[n].abc_cls = "A"
            elseif aisle_list[n].task_num < max_task_num/2 then
                aisle_list[n].abc_cls = "B"
            else
                aisle_list[n].abc_cls = "C"
            end
        end
    end
    table.sort( aisle_list, aisle_list_sort )
end

--[[ ****
        适用于立库+输送线的入库作业生成
        来源: 巨星二期料箱库

        通过站台确定从立库的哪一个入库接驳区进入立库
        站台的扩展属性
        {
            "loc_code":"S-A",       -- 站台货位
            "entry_area_name":"A",  -- 接驳区名称
            "code":"A",             -- 站台编码
            "factory":"81",         -- 工厂标识
            "storage_area":"K2",    -- 存储区编码
            "entry_area_code":"K4", -- 接驳区
            "mac":"A"               -- 站台电脑的mac地址
        }
        entry_area -- 入库接驳区  storage_area -- 存储区 loc_orde = 0 根据列顺序 1 -- 倒序
        计算料箱库入库区货位（任务均衡），考虑巷道货位均衡, 基本原则是: 巷道任务少优先，巷道空货位多的优先
        返回入库缓存区货位和巷道内存储货位（2个货位）
        V2.0 HAN 20241120 根据站台位置获取相应的 堆垛机入库缓存区，增加一个站台编码 station

        参数:
        station -- 入库站台，站台和立库用输送线连接
--]]
-- 获取立库入库缓存区及立库内存储货位
-- 适用于立库+输送线的入库作业生成，通过站台确定从立库的哪一个入库接驳区进入立库
-- 计算料箱库入库区货位（任务均衡），考虑巷道货位均衡，基本原则：巷道任务少优先，巷道空货位多的优先
-- 返回入库缓存区货位和巷道内存储货位（2个货位）
-- @function wms_putaway.Get_StorageCache_Loc
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string station 入库站台，站台和立库用输送线连接
-- @treturn number nRet 0: 成功，1: 未找到合适货位，2: 错误
-- @treturn string cache_loc_code 立库巷道口入库货位（失败时为错误信息）
-- @treturn string storage_loc_code 巷道内存储货位
function wms_putaway.Get_StorageCache_Loc( strLuaDEID, station )
    local nRet, strRetInfo
    local station_attr
    --[[
        station_attr = {"loc_code":"S-A","entry_area_name":"A","code":"A","factory":"0001","storage_area":"K2","entry_area_code":"K4","mac":"A"}
        entry_area -- 入库接驳区  storage_area -- 存储区 loc_orde = 0 根据列顺序 1 -- 倒序
    ]]
    nRet, station_attr = wms_station.Get_Station_ExtData( strLuaDEID, station )    
    if nRet ~= 0 then
        return 2, station_attr
    end
    local loc_order = lua.Get_NumAttrValue( station_attr.loc_order )        -- 确定从这个站台进入堆垛机巷道的时候，列最靠近巷道口的是列值小最近，还是列值大最近

    -- 站台指定的入库接驳区（该算法支持一个站台一个堆垛机入库接驳区）
    local storage_cache_area = lua.Get_StrAttrValue( station_attr.entry_area_code )
    if storage_cache_area == '' then
        return 2, "'机台-"..station.."'没有定义入库口区域编码信息!"
    end

    -- 获取入库接驳区货位的使用情况
    local strCondition = "C_ENABLE = 'Y' AND S_AREA_CODE = '"..storage_cache_area.."'"
    local strOrder = "S_CODE"
    local loc_objs
    local aisle_connect_loc_set = {}
    nRet, loc_objs = m3.QueryDataObject( strLuaDEID, "Location", strCondition, strOrder )
    if nRet ~= 0 then 
        lua.Stop( strLuaDEID, "获取【Location】信息失败! " .. loc_objs ) 
        return
    end
    local obj_attrs, aisle
    for n = 1, #loc_objs do
        obj_attrs = m3.KeyValueAttrsToObjAttr(loc_objs[n].attrs)
        if obj_attrs == nil then
            return 2, "KeyValueAttrsToObjAttr 失败!"
        end
        -- 这些货位里把这个货位对应的巷道信息保存在 S_EXT_ATTR
        aisle = lua.StrToNumber( obj_attrs.S_EXT_ATTR )
        local connect_loc = {
            aisle = aisle,
            loc_code = obj_attrs.S_CODE,
       
        } 
        table.insert( aisle_connect_loc_set, connect_loc )     
    end

    -- 站台指定的入库存储区
    local storage_area = lua.Get_StrAttrValue( station_attr.storage_area )
    if storage_area == '' then
        return 2, "'机台-"..station.."'没有定义存储区编码信息!"
    end

    -- 获取库区 storage_area 内设备状态
    local stacker_dev
    nRet, stacker_dev = wms_wcs.Get_Area_Stacker_Dev_State( strLuaDEID, storage_area )
    if nRet ~= 0 then
        return 2, stacker_dev
    end

    local storage_cache_list = {}

    local task_num, max_task_num, empty_loc_num
    local loc_index

    -- 获取立库巷道口货位的基本信息，保存到 storage_cache_list
    max_task_num = 0
    for n = 1, #stacker_dev do
        -- 获取设备所在巷道
        aisle = stacker_dev[n].aisle
        -- enable = 1 表示巷道堆垛机可用
        if stacker_dev[n].enable == 1 then
            task_num = stacker_dev[n].cntr_num
            if task_num > max_task_num then
                max_task_num =  task_num
            end

            -- 查询货位启用、空货位、在本巷道、没被锁的货位数量
            strCondition = "N_AISLE = "..aisle.." AND S_AREA_CODE = '"..storage_area.."' AND C_ENABLE = 'Y' AND N_CURRENT_NUM = 0 AND  N_LOCK_STATE = 0"
            nRet, strRetInfo = mobox.getDataObjCount( strLuaDEID, "Location", strCondition )
            if nRet ~= 0 then
                return nRet, strRetInfo
            end
            empty_loc_num = lua.StrToNumber( strRetInfo )  
            if empty_loc_num > 0 then
                -- 获取该巷道的 入库接驳位
                loc_index = 0
                for m = 1, #aisle_connect_loc_set do
                    if aisle_connect_loc_set[m].aisle == aisle then
                        loc_index = m
                        break
                    end
                end
                if loc_index ~= 0 then
                    local cache_loc = {
                        loc_code = aisle_connect_loc_set[loc_index].loc_code,
                        aisle = aisle,
                        task_num = task_num,                                          -- 任务数量
                        aisle_empty_num = empty_loc_num,                              -- 对应巷道的空货位数量
                        abc_cls = ""                                                  -- ABC 分类
                    }
                    table.insert( storage_cache_list, cache_loc )
                end
            end
        end
    end    

    -- 计算 各入库缓存区的 任务数量 ABC 分类值 没有任务的为 A，任务数大于 0 小于 max_task_num/2 的为B，其余为 C
    local nCount = #storage_cache_list
    if nCount == 0 then
        return 1, "系统无法分配货位!"
    end

    -- 排序 abc_cls 按ABC排序，同样等级的abc_cls 根据 aisle_empty_num 排序，空货位多的在前面
    task_num_abc_cls( storage_cache_list )

    -- 获取巷道内空货位
    local ret_loc, loc

    -- strLuaDEID, 库区, 巷道号, 货位排序方法, 顺序/倒序, 附加条件, 取货位数量
    nRet, ret_loc = wms_alg.Get_Aisle_Empty_Loc( strLuaDEID, storage_area, storage_cache_list[1].aisle, 0, loc_order, "", 1 )

    if nRet ~= 0 then
        return 1, "计算巷道"..storage_cache_list[1].aisle.."内货位失败!"..ret_loc
    end       
    nRet, loc = wms_wh.GetLocInfo( ret_loc.loc_code )
    if nRet ~= 0 then 
        return 1, "获取货位'"..ret_loc.loc_code.."'信息失败! "..loc
    end 

    -- 返回 立库巷道口入库货位，巷道内存储货位
    return 0, storage_cache_list[1].loc_code, ret_loc.loc_code
end

-- 根据存储区域获取空货位数量和查询条件
-- @function get_empty_loc_num
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table storage_area 存储区域定义 {wh_code, area_code, aisle_code, col_set, layer_set, loc_set}
-- @treturn number nRet 0: 成功，2: 错误
-- @treturn number empty_loc_num 空货位数量
-- @treturn string strCondition 查询空货位的SQL条件
local function get_empty_loc_num( strLuaDEID, storage_area )

    local strCondition = "S_WH_CODE = '"..storage_area.wh_code.."'"
    
    if lua.StrIsEmpty( storage_area.loc_set ) then
        if not lua.StrIsEmpty( storage_area.area_code ) then 
            strCondition = strCondition.." AND S_AREA_CODE = '"..storage_area.area_code.."'"
        end
        if not lua.StrIsEmpty( storage_area.aisle_code ) then 
            strCondition = strCondition.." AND S_AISLE_CODE = '"..storage_area.aisle_code.."'"
        end
        if not lua.StrIsEmpty( storage_area.col_set ) then
            strCondition = strCondition.." AND N_COL = IN ("..storage_area.col_set..") "
        end
        if not lua.StrIsEmpty( storage_area.layer_set ) then
            strCondition = strCondition.." AND N_LAYER = IN ("..storage_area.layer_set..") "
        end
    else
        strCondition = strCondition.." AND S_CODE = IN ("..storage_area.loc_set..") "
    end 
    strCondition = strCondition.." AND C_ENABLE = 'Y' AND N_CURRENT_NUM = 0 AND N_LOCK_STATE = 0"

    local nRet, strRetInfo = mobox.getDataObjCount( strLuaDEID, "Location", strCondition )
    if nRet ~= 0 then 
        return 2, strRetInfo 
    end 
    local empty_loc_num = lua.StrToNumber( strRetInfo )    
    return 0, empty_loc_num, strCondition  
end

-- 根据上架策略获取容器的储存位置
-- 上架策略支持两种方法：rule（基于规则配置）和 script（脚本）
-- @function wms_putaway.Get_Storage_LocArea
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strategy_code 上架策略编码
-- @tparam string cntr_code 容器编码
-- @tparam string wh_code 仓库编码（可以为空）
-- @tparam string area_code 库区编码（可以为空）
-- @treturn number nRet 0: 找到货位，1: 没合适货位，2: 错误
-- @treturn string loc_code 上架货位
-- @treturn string/table area_code 上架库区
-- @treturn string/table ext_data 附加数据
function wms_putaway.Get_Storage_LocArea( strLuaDEID, strategy_code, cntr_code, wh_code, area_code )
    local nRet

    if wh_code == nil then wh_code = '' end
    if area_code == nil then area_code = '' end
    
    if lua.StrIsEmpty( strategy_code ) then
        return 2, " wms_putaway.Get_Storage_LocArea 函数中 strategy_code 必须有值"
    end
    if lua.StrIsEmpty( cntr_code ) then
        return 2, " wms_putaway.Get_Storage_LocArea 函数中 cntr_code 必须有值"
    end

    -- 获取上架策略定义
    local strategy
    nRet, strategy = wms_base.GetStrategyInfo( "Putaway_Strategy", strategy_code )
    if nRet ~= 0 then
        return 2, "在获取'上架策略' "..strategy_code.." 时失败! "..strategy
    end   

    -- 上架策略有2中方法来确定货位 1 -- rule/基于规则配置 2 -- script 脚本
    if strategy.alloc_method == 'script' then
        -- 根据脚本来计算货位
        local str_alloc_event = strategy.alloc_event or ''

        if str_alloc_event == '' then
            return 1, "上架策略编码 = '"..strategy_code.."' 的策略定义不合规，脚本类型的规则没定义脚本！"
        end
        local alloc_event = json.decode( str_alloc_event )
        local event_name = alloc_event.name or ''
        if event_name == '' then
            return 1, "上架策略编码 = '"..strategy_code.."' 的策略定义不合规，脚本类型的规则没定义脚本！"
        end        

        -- 执行脚本
        local ret_value
        local parameter = { cntr_code = cntr_code }
        nRet, ret_value = m3.RunScript( strLuaDEID, "Putaway_Strategy", event_name, "", "", parameter )
        --[[
            ret_value = { ..., result = {  err_code = 0, msg = "", loc_code = loc.code, area_code = loc.area_code, ext_data = {..} } }
            ext_data 是附加数据
        --]]

        if nRet ~= 0 then
            return 1, "执行 Putaway_Strategy 名为"..event_name.." 的脚本失败!"..ret_value
        end
        local result = ret_value.result
        if result == nil then
            return 1, "上架策略'"..strategy_code.."'的脚本中返回值的格式不正确!"
        end

        if result.err_code == 0 then
            local loc_code = result.loc_code or ''
            local area_code = result.area_code or ''
            local ext_data = result.ext_data or ''

            if loc_code == '' then
                return 1, "上架策略'"..strategy_code.."'的脚本中返回值的格式不正确(少loc_code)!"
            end
            return 0, loc_code, area_code, ext_data
        end
        return 1, "上架策略'"..strategy_code.."'的计算货位失败!"..result.msg

    elseif strategy.alloc_method == 'rule' then
        -- 根据规则来计算货位
        -- 获取容器的扩展属性（混箱属性）
        local cntr_ext_data = {}
        nRet, cntr_ext_data = wms_cntr.Get_Container_ExtInfo( strLuaDEID, cntr_code )
        if nRet ~= 0 then
            return 2, "获取容器'"..cntr_code.."'的扩展属性失败! -->"..cntr_ext_data
        end
    
        -- 根据容器获取匹配的上架规则
        local storage_area_set
        nRet, storage_area_set = wms_base.Get_Storage_Area_By_Strategy( strategy, cntr_ext_data )
        if nRet ~= 0 then
            return 2, storage_area_set
        end

        -- 根据优先级进行分级，同一优先级的要考虑货位均衡（选空货位多）
        local storage_area_group_list = {}       -- 把相同优先级的入库区域放一起

        for n, storage_area in ipairs( storage_area_set ) do
            if wh_code ~= '' then
                if storage_area.wh_code ~= wh_code then
                    return 2, "上架策略 '"..strategy_code.."' 中定义的仓库编码和入库单中的仓库不一致!"
                end
            end
            if lua.StrIsEmpty( storage_area.area_code ) then
                lua.Warning( strLuaDEID, debug.getinfo(1), "上架策略 '"..strategy_code.."' 中定义的第"..n.."条策略明细中没有设置库区!" )
            else   
                local find = false
                for _, group in ipairs( storage_area_group_list ) do
                    if group.priority == storage_area.priority then
                        table.insert( group.list, storage_area )
                        find = true
                        break
                    end
                end

                if not find then
                    local group = {
                        priority = storage_area.priority,
                        list = {}
                    }
                    table.insert( group.list, storage_area )
                    table.insert( storage_area_group_list, group )
                end
            end
        end    
        
        local strCondition, empty_loc_num, strOrder, loc_objs, data_attrs
        local loc_code = ''

        for _, group in ipairs( storage_area_group_list ) do
            for _, storage_area in ipairs( group.list ) do
                nRet, empty_loc_num, strCondition = get_empty_loc_num( strLuaDEID, storage_area )
                if nRet ~= 0 then
                    return 2, empty_loc_num
                end

                if empty_loc_num > 0 then
                    strOrder = "N_POS_WEIGHT"
                    nRet, loc_objs = m3.QueryDataObject3(strLuaDEID, "Location", strCondition, strOrder, 1 )
                    if nRet ~= 0 then 
                        return 2, "QueryDataObject失败!"..loc_objs 
                    end
                    if loc_objs ~= '' then 
                        data_attrs = m3.KeyValueAttrsToObjAttr(loc_objs[1].attrs)
                        if data_attrs == nil then
                            return 2, "KeyValueAttrsToObjAttr失败!"
                        end
                        loc_code = data_attrs.S_CODE
                    end
                    if not lua.StrIsEmpty( loc_code ) then
                        return 0, loc_code, storage_area
                    end
                end
            end
        end
        return 1, "没有空货位!"
    end

    return 1, "上架规则的计算货位方法没设置正确"
end

return wms_putaway