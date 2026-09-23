--[[
    版本：Version 2.1
    名称: 
    作者：HAN
    日期：2025-3-29
    
    WMS-Basis-Model-Version: V15.5

    共用程序包
    名称:   wms_wcs
    应用:   涉及和设备层进行交互，比如库区中堆垛机的状态，延伸到库区哪个个巷道可用

    函数:
        -- Get_DVC_State 获取设备状态
        -- Get_Area_Stacker_Dev_State 获取库区里堆垛机状态

    更改记录:

--]]

wms_base = require ("wms_base")
wms_wh   = require ("wms_wh")

local wms_wcs = {_version = "0.2.1"}

--[[
    获取某个库区内设备的状态（在JX项目中特指库区内的堆垛机状态）
    输入参数:
        area_code   -- 库区编码
        get_dev_state_func -- 获取设备状态的外部函数定义 { module_name, function_name }, 可以为空

    返回参数:
        nRet = 0 成功 非零 失败
        stacker_dev = [{"dev_no":"xxx","aisle":1,"aisle_no":"A-01","enable":0/1,"cntr_num":0}]
        -- cntr_num 巷道入库接驳位容器数量
        -- aisle_no 巷道编码
        -- dev_no 堆垛机号
--]]
function wms_wcs.Get_Area_Stacker_Dev_State( strLuaDEID, area_code )
    local nRet, strRetInfo

    -- 获取 area_code 库区堆垛机设备工作状态，确定哪些巷道可以使用
    local area_data
    local stacker_dev_str = ''
    local get_const = false
    nRet, area_data = wms_wh.GetAreaInfo3( area_code )
    if nRet == 0 then
        stacker_dev_str = area_data.S_STACKER_DEV or ''
    end
    if stacker_dev_str == '' then
        -- 老版本是从下面的库区变量获取        
        nRet, stacker_dev_str = wms_base.Get_sConst2( "Area-"..area_code.."-StackerCrane" )
        if nRet ~= 0 then
            return 1, "系统无法获取常量'Area-"..area_code.."-StackerCrane'"
        end
        if stacker_dev_str == '' then
            return 1, "常量'Area-"..area_code.."-StackerCrane' 不能为空! 或库区数据对象中属性 S_STACKER_DEV 必须有值"
        end
        get_const = true
    end

    --stacker_dev 格式: [{"dev_no":"xxx","aisle":1,"enable":false/true}]
    local stacker_dev, success
    success, stacker_dev = pcall( json.decode, stacker_dev_str )
    if not success then
        if get_const then
            return 1, "常量'Area-"..area_code.."-StackerCrane' 格式错误! -- [{\"dev_no\":\"xxx\",\"aisle\":1,\"enable\":false},...]"
        else
            return 1, "库区数据对象中属性 S_STACKER_DEV 格式错误! -- [{\"dev_no\":\"xxx\",\"aisle\":1,\"enable\":false},...]"
        end
    end
    local dev_codes = ''
    for n = 1, #stacker_dev do
        if stacker_dev[n].dev_no == nil or stacker_dev[n].dev_no == '' then
            return 1, "库区'"..area_code.."'设备数据缺少 dev_no 字段!"
        end
        dev_codes = dev_codes..stacker_dev[n].dev_no..","
    end
    if ( dev_codes == '') then
        return 1, "库区'"..area_code.."'没有定义设备!"
    end
    dev_codes = lua.trim_laster_char( dev_codes )

    strRetInfo = area_data.S_GET_DEV_FUNC or ''
    local get_dev_state_func

    if strRetInfo ~= '' then
        success, get_dev_state_func = pcall( json.decode, strRetInfo )
        if not success then
             return 1, "库区数据对象中属性 S_GET_DEV_FUNC 格式错误! -- {\"module_name\":\"xxx\",\"function_name\":\"\"}"
        end
    else
        get_dev_state_func = ''
    end

    -- 调用WCS接口获取设备状态, IN_USE = 1 表示可以使用
    -- [{"DVC_NO":"TC21","IS_USE":0/1,"CON_NUM":1},...]    
    if get_dev_state_func == '' then
        -- 不调用WCS接口，默认所有设备是正常的
        for n = 1, #stacker_dev do
            stacker_dev[n].enable = 1
            stacker_dev[n].cntr_num = 0
        end 
    else
        -- 有外部函数调用定义
        -- 外部函数  function jx_base.Get_DVC_State( strLuaDEID, dev_codes )
        -- 返回参数 nRet, deb_state =
        --[[
                dev_state = {
                {DVC_NO = "ZD01", IS_USE = 1, CON_NUM = 1},
                {DVC_NO = "ZD02", IS_USE = 1, CON_NUM = 0},
                {DVC_NO = "ZD03", IS_USE = 0, CON_NUM = 0},
                {DVC_NO = "ZD04", IS_USE = 1, CON_NUM = 0}
                }
        --]]
        local module = get_dev_state_func.module_name or ''
        local function_name = get_dev_state_func.function_name or ''
        local nRet, dev_state = lua.callFunctionByName( module, function_name, strLuaDEID, dev_codes )
        if nRet ~= 0 then 
            return nRet, dev_state 
        end
        local find
        for n = 1, #stacker_dev do
            find = false
            for m = 1, #dev_state do
                if ( stacker_dev[n].dev_no == dev_state[m].DVC_NO ) then
                    find = true
                    stacker_dev[n].enable = lua.Get_NumAttrValue( dev_state[m].IS_USE )
                    stacker_dev[n].cntr_num = lua.Get_NumAttrValue( dev_state[m].CON_NUM )
                    break
                end
            end
            if not find then
                return 1, "WCS返回的设备状态中没有编码='"..stacker_dev[n].dev_no.."'的设备状态！"
            end
        end
    end
    return 0, stacker_dev
end

-- 获取库区库可用的堆垛机巷道号 -- 1, 2, 4
function wms_wcs.Get_Area_Available_Aisle( strLuaDEID, area_code )
    local nRet, stacker_dev

    nRet, stacker_dev = wms_wcs.Get_Area_Stacker_Dev_State( strLuaDEID, area_code )
    if nRet ~= 0 then 
        return nRet, stacker_dev 
    end

    local aisle = ''
    for n = 1, #stacker_dev do
        if ( stacker_dev[n].enable == 1 ) then
            aisle = aisle..stacker_dev[n].aisle..","
        end
    end
    aisle = lua.trim_laster_char( aisle )
    return 0, aisle
end

return wms_wcs