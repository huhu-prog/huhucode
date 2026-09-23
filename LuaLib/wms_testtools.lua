--[[
    版本：Version 2.1
    名称: WMS 测试工具
    作者：HAN
    日期：2025-1-29
    
    WMS-Basis-Model-Version: V15.5

    级别：固定
    
    函数： 
        -- TaskSimulate 模拟出N个Task，一般用于一些出入库货位算法执行时的数据铺垫
        -- Batch_Set_LocInfo 批量设置货位中当前容器数量，前提是这些货位的 cur_num = 0
    更改记录:
       
--]]

wms_base = require ("wms_base")
wms_wh   = require ("wms_wh")

local wms_test = {_version = "0.2.1"}

--[[ 
    批量设置满足条件的货位中当前容器数量，是否启用这两个属性，用于构建一些货位计算时需要用到的基础数据

    输入参数:
    1 -- area_code
    2 -- set_info
        { 
            mark:"xxxx", 
            batch_set:{cur_num = 1, enable = false, condition = "xxxx"}, 
            exception:[{loc_code:"", cur_num = 0, enable = true, condition = "xxx" },... ]
        }

        mark 必须有值，本函数执行后变更的 货位都会在加 这个标记

    功能说明：
        该函数首先会批量设置满足 batch_set 中 condition 条件的货位的  cur_num 或 enable 信息，=
        exception 是例外设置就是把这些货位如果指定了 loc_code，如果没有loc_code 根据 condition 来设置
]]

function wms_test.Batch_Set_LocInfo ( strLuaDEID, area_code, set_info )
    local nRet, strRetInfo

    -- step1 输入参数合规检测
    if ( area_code == '' or area_code == nil ) then
        return 1, "TEST_Batch_Set_Loc_CurNum 函数 area_code 必须有值!"
    end
    if ( set_info == nil or type(set_info) ~= "table" ) then
        return 1, "TEST_Batch_Set_Loc_CurNum 函数 set_info 非法!"
    end
    local mark = set_info.mark
    if ( mark == nil or mark == "" ) then
        return 1, "TEST_Batch_Set_Loc_CurNum 函数 set_info 中必须要有 mark 属性!"
    end

    local batch_set = set_info.batch_set
    local exception = set_info.exception
    local strCondition = "S_AREA_CODE = '"..area_code.."'"
    local strSetAttr = ''
    
    -- step2 批量处理
    if ( batch_set ~= nil ) then

        local cur_num = batch_set.cur_num
        local enable = batch_set.enable
        
        if ( batch_set.condition ~= nil ) then
            strCondition = strCondition.." AND ("..batch_set.condition..")"
        end

        strSetAttr = ''
        if ( batch_set.cur_num ~= nil and type(batch_set.cur_num) == "number" ) then
            strSetAttr = "N_CURRENT_NUM = "..batch_set.cur_num
        end
        if ( batch_set.enable ~= nil and type(batch_set.enable) == "boolean" ) then
            if ( strSetAttr ~= '' ) then
                strSetAttr = strSetAttr..","
            end
            if ( batch_set.enable ) then
                strSetAttr = strSetAttr.."C_ENABLE = 'Y'"
            else
                strSetAttr = strSetAttr.."C_ENABLE = 'N'"
            end
        end        
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Location", strCondition, strSetAttr )
        if ( nRet ~= 0 ) then return 1, "设置Location属性失败1!"..strRetInfo end
    end

    -- step3 例外设置   
    if ( exception ~= nil and type(exception) == "table") then
        local n

        for n = 1, #exception do
            strCondition = "S_AREA_CODE = '"..area_code.."'"
            if ( exception[n].loc_code ~= nil ) then
                strCondition = strCondition.." AND S_CODE = '"..exception[n].loc_code.."'"
            elseif ( exception[n].condition ~= nil) then
                strCondition = strCondition.." AND ("..exception[n].condition..")"
            else
                strCondition = ''
            end
            if  ( strCondition ~= '') then
                strSetAttr = ''
                if ( exception[n].cur_num ~= nil and type(exception[n].cur_num) == "number" ) then
                    strSetAttr = "N_CURRENT_NUM = "..exception[n].cur_num
                end
                if ( exception[n].enable ~= nil and type(exception[n].enable) == "boolean" ) then
                    if ( strSetAttr ~= '' ) then
                        strSetAttr = strSetAttr..","
                    end
                    if ( exception[n].enable ) then
                        strSetAttr = strSetAttr.."C_ENABLE = 'Y'"
                    else
                        strSetAttr = strSetAttr.."C_ENABLE = 'N'"
                    end
                end  
                nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Location", strCondition, strSetAttr )
                if ( nRet ~= 0 ) then return 1, "设置Location属性失败2!"..strRetInfo end                                 
            end
        end
    end

    return 0
end

--[[ 
    批量创建Task对象，Task可以指定起点、终点，用于一些算法测试做数据铺垫
    输入参数:
        task_info 是一个需要创建的任务数据包，table类型，格式如下：
                [{from:"xx",to:"",task_num:10},..]
                from -- 任务出发货位 to 任务去向货位 task_num 任务数量
        delete_ts_first: true、false 是否先删除模拟任务
]]

function wms_test.TaskSimulate ( strLuaDEID, task_info, delete_ts_first )
    local nRet, strRetInfo

    if ( delete_ts_first == nil ) then delete_ts_first = true end

    -- 删除以前的模拟任务
    if ( delete_ts_first ) then
        local strCondition = "S_CODE like 'TEST-%'"
        nRet, strRetInfo = mobox.dbdeleteData(strLuaDEID, "Task", strCondition)
        if (nRet ~= 0) then return 1, "删除【Task】失败!"..strRetInfo end
    end

    local n, m
    local from_loc, to_loc
    local task
    local strHeader, strCode

    for n = 1, #task_info do
        nRet, from_loc = wms_wh.GetLocInfo( task_info[n].from )
        if ( nRet ~= 0 ) then return 1, '获取货位信息失败! '..from_loc end  

        nRet, to_loc = wms_wh.GetLocInfo( task_info[n].to )
        if ( nRet ~= 0 ) then return 1, '获取货位信息失败! '..to_loc end  

        for m = 1, task_info[n].task_num do

            strHeader = 'TEST-'..os.date("%m%d")..'-'
            nRet,strCode = mobox.getSerialNumber( "测试任务", strHeader, 3 )  
            if ( nRet ~= 0 ) then return 1, '申请【任务】编码失败!'..strCode end

            task = m3.AllocObject(strLuaDEID,"Task")
            task.factory = "0001"
            task.code = strCode
            -- 起点
            task.start_wh_code = from_loc.wh_code
            task.start_area_code  = from_loc.area_code
            task.start_loc_code  = from_loc.code
            -- 终点
            task.end_wh_code  = to_loc.wh_code
            task.end_area_code  = to_loc.area_code
            task.end_loc_code  = to_loc.code
            
            nRet, task = m3.CreateDataObj(strLuaDEID, task) 
            if ( nRet ~= 0 ) then return 1, '创建【任务】失败!'..task end           
        end
    end

    return 0
end 

return wms_test