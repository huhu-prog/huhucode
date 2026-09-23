--[[
    版本：     Version 3.0
    创建日期： 2025-1-28
    修改日期:  2026-6-12
    创建人：   HAN

    WMS-Basis-Model-Version: V19.8

    功能：
        WMS 过程中一些常用功能封装

    ——————————————————————————————————
    导出函数列表（共 38 个）:
    ——————————————————————————————————

    【常量相关】                
        Get_sConst2          — 获取常量返回字符串类型（推荐使用）
        Get_nConst           — 获取常量返回数值类型（不建议使用，兼容保留）
        Get_nConst2          — 获取常量返回数值类型（推荐使用）
        Get_bConst2          — 获取常量返回bool类型

    【字典相关】                
        GetDictItemName      — 获取字典项的附加值（旧版）
        GetDictItemName2     — 获取字典项的附加值（推荐使用）

    【警告/提示/语音】          
        Warning              — 创建一条WMS警告信息
        Set_Business_Warning — 设置业务类型警告（固定KEY）
        Error_Audio          — 播放错误语音并返回错误信息
        Notice_Audio         — 播放提示语音并返回信息

    【功能区相关】              
        GetFuncArea          — 获取货位/库区/仓库等功能区定义列表
        Get_Warehouse_FuncArea — 获取仓库的功能区定义列表
        Get_Area_FuncArea    — 获取库区的功能区定义列表
        Get_Zone_FuncArea    — 获取逻辑库区的功能区定义列表
        Get_Loc_FuncArea     — 获取货位的功能区定义列表

    【入库相关】                
        InboundWave_Finish_PostProce — 入库波次完成后批分入库数量（不建议使用）

    【用户/登录相关】           
        Get_CurLoginUserInfo — 获取当前登录人员账号信息及MAC/站台
        GetMyFactory         — 获取当前登录人员所属单位（工厂）编码

    【料箱/预分配】             
        PreAllocCntr_CFG_Check — 料箱预分配配置参数检查
        Get_Matching_cntr_list — 获取满足条件的料箱列表（含巷道任务均衡）
        Add_Aisle_Task_Num   — 获取巷道任务数量并加一

    【库存查询/匹配/排序】      
        Get_INV_Detail_MatchSql — 根据匹配规则生成查询 INV_Detail 的SQL条件
        SKU_Match            — 判断两个SKU的匹配属性是否全部一致
        Get_INV_Detail_QueryOrder — 根据分拣规则生成 INV_Detail 查询排序

    【料格/装载限制】           
        Get_LoadingLimit     — 获取SKU在某料箱料格类型的最大装载数量
        GetSKU_LoadingLimit  — 获取SKU在料格中最大装载数量（便捷版）

    【作业/策略】               
        GetOpDefInfo         — 获取WMS作业定义信息
        GetStrategyInfo      — 获取策略信息
        Get_Storage_Area_By_Strategy — 根据策略获取仓库/库区等存储区域

    【库位锁】                  
        Unlock_Location      — 解锁库位（清除Lock记录+更新货位锁状态）
        Lock_Location        — 货位加锁（创建Lock记录+更新货位锁状态）

    【来源业务】                
        Get_BS_State         — 获取来源事务的状态（N_B_STATE）
        BS_IsCancel          — 判断来源业务是否已取消

    【异常处理】                
        GetAnomalyIndex      — 根据异常类型字符串获取异常类型索引

    【货品合并/预分配检查】     
        get_merge_item_list  — 合并有相同补料匹配规则的SKU
        item_list_is_all_ok  — 检测货品清单是否已全部预分配

    【静态资源】                
        Get_ImgUrl           — 获取图片静态资源URL前缀

    [其它]
        WaitForPostEventProcess — 等待后台事件处理完成
        GetDataObjList        — 获取数据对象列表
    ——————————————————————————————————

    更改记录:
    2025-1-28  HAN  创建
    2026-6-12  HAN  Get_Warehouse_FuncArea,Get_Loc_FuncArea, Get_Zone_FuncArea 函数的返回值变成2个，这个要注意调整

    AI CHECK:
        -- 20260613
--]]

require ("wms_const")
wms   = require ("OILua_WMS")

local wms_base = {_version = "0.2.1 "}
--//////////////////////////////////////////////////////常量相关///////////////////////////////////////////////////////////
-- 获取常量返回字符串类型（建议用这个函数）
-- @function wms_base.Get_sConst2
-- @tparam string strConstName 常量名称
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string strValue 常量值
function wms_base.Get_sConst2( strConstName )
    local nRet, strValue
    if strConstName == nil or strConstName == '' then
        return 1, "Get_sConst2 strConstName 参数不能为空!"
    end
    strConstName = lua.trim(strConstName)
    nRet, strValue = wms.wms_GetConst(strConstName)
    if nRet ~= 0 then 
        return 2, strValue 
    end
    return 0, strValue
end

-- 获取常量返回数值类型，如果没有返回一个巨大的值（不建议使用）
-- 不建议使用, 为了老的程序保留,使用 Get_nConst2( strConstName ) ****
-- @function wms_base.Get_nConst
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strConstName 常量名称
-- @treturn number nRet 0: 成功，非零失败，失败返回 2^53
-- @treturn number/string 成功返回数值，失败返回 2^53
function wms_base.Get_nConst( strLuaDEID, strConstName )
    local nRet, strValue

    if strConstName == nil or strConstName == '' then
        return 2^53
    end
    strConstName = lua.trim(strConstName)
    nRet, strValue = wms.wms_GetConst(strConstName)
    if nRet ~= 0 then
        return 2^53
    end
    return lua.StrToNumber( strValue )
end

-- 获取常量返回数值类型
-- @function wms_base.Get_nConst2
-- @tparam string strConstName 常量名称
-- @treturn number nRet 0: 成功，非零失败
-- @treturn number/string 成功返回数值，失败返回错误信息
function wms_base.Get_nConst2( strConstName )
    local nRet, strValue

    if strConstName == nil or strConstName == '' then
        return 1, "Get_nConst2 strConstName参数不能为空字符串!"
    end
    strConstName = lua.trim(strConstName)
    nRet, strValue = wms.wms_GetConst(strConstName)
    if nRet ~= 0 then
        return 2, strValue
    end
    return 0, lua.StrToNumber( strValue )
end

-- 获取常量返回bool类型
-- @function wms_base.Get_bConst2
-- @tparam string strConstName 常量名称
-- @treturn number nRet 0: 成功，非零失败
-- @treturn boolean/string 成功返回 true/false，失败返回错误信息
function wms_base.Get_bConst2( strConstName )
    local nRet, strValue

    if strConstName == nil or strConstName == '' then
        return 1, "Get_bConst2 strConstName参数不能为空字符串!"
    end
    strConstName = lua.trim(strConstName)
    nRet, strValue = wms.wms_GetConst(strConstName)
    if nRet ~= 0 then
        return 2, strValue
    end
    if strValue == '1' or strValue == 'Y' or strValue == 'y' then
        return 0, true
    end
    return 0, false
end

-- 获取字典项的附加值
-- @function wms_base.GetDictItemName
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strDictName 字典名称
-- @tparam number nItemValue 字典项的值（必须是数值类型）
-- @treturn string str_item_name 字典项名称，失败返回空字符串
function wms_base.GetDictItemName( strLuaDEID, strDictName, nItemValue )
    local str_item_name = ''
    local nRet

    if nItemValue == nil then
        lua.Warning( strLuaDEID, 0, "wms_base.GetDictItemName 的输入参数 nItemValue 必须有值！请检查 wms_base.GetDictItemName 函数的输入参数!" )
        return ""
    end
    if type(nItemValue) ~= "number" then
        lua.Warning( strLuaDEID, 0, "wms_base.GetDictItemName 的输入参数 nItemValue 必须要是一个数值类型！" )
        return ""
    end

    nRet, str_item_name = wms.wms_GetDictTypeName( strDictName, nItemValue ) 
    if nRet ~= 0 then
        lua.Warning( strLuaDEID, 0, strDictName.."不存在或者字典定义中不存在值 = "..nItemValue.." 的字典项!" )
        return ""
    end
    return str_item_name
end

-- 获取字典项的附加值
-- @function wms_base.GetDictItemName2
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strDictName 字典名称
-- @tparam number nItemValue 字典项的值（必须是数值类型）
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string str_item_name 字典项名称，失败返回错误信息
function wms_base.GetDictItemName2( strLuaDEID, strDictName, nItemValue )
    local str_item_name = ''
    local nRet

    if nItemValue == nil then
        return 1, "wms_base.GetDictItemName2 的输入参数 nItemValue 必须有值！请检查 wms_base.GetDictItemName 函数的输入参数!"
    end
    if type(nItemValue) ~= "number" then
        return 1,  "wms_base.GetDictItemName2 的输入参数 nItemValue 必须要是一个数值类型！"
    end

    nRet, str_item_name = wms.wms_GetDictTypeName( strDictName, nItemValue ) 
    if nRet ~= 0 then
        return 2, strDictName.."不存在或者字典定义中不存在值 = "..nItemValue.." 的字典项!"
    end
    return 0, str_item_name
end

-- 创建一条WMS警告信息，方便使用者了解系统执行情况
-- @function wms_base.Warning
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam number nLvl 错误等级
-- @tparam number nErrCode 错误码
-- @tparam string strMsg 错误信息
-- @tparam string strExtData 扩展数据
-- @tparam string strNote 备注
-- @tparam string strFrom 来源
-- @tparam string factory 工厂
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string/table 失败时返回错误信息
function wms_base.Warning( strLuaDEID, nLvl, nErrCode, strMsg, strExtData, strNote, strFrom, factory )
    local nRet

     if factory == nil or factory == "" then
        factory = "0000"
    end
     if strFrom == nil or strFrom == "" then
        strFrom = "Unknown"
    end
     if strExtData == nil then
        strExtData = ""
    end
     if strNote == nil then
        strNote = ""
    end

    local warning = m3.AllocObject(strLuaDEID,"WMS_Warning")
    warning.factory = factory
    warning.msg = strMsg
    warning.from = strFrom
    warning.lvl = nLvl
    warning.err_code = nErrCode
    warning.ext_data = strExtData
    warning.note = strNote

    -- 获取创建容器时需要的属性
    nRet, warning = m3.CreateDataObj( strLuaDEID, warning )
    if nRet ~= 0 then
        return 1, "创建 wms_base.Warning 失败! "..warning
    end
    return 0
end

-- 设置业务类型警告（固定一条，有特定KEY作为CODE）
-- @function wms_base.Set_Business_Warning
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string key_code 警告的KEY编码
-- @tparam string strMsg 警告信息，为空时删除该条警告, 说明这个报警可以删除
-- @tparam string strFrom 来源
-- @tparam number nLvl 错误等级
-- @tparam string strNote 备注
-- @tparam string factory 工厂
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string 失败时的错误信息
function wms_base.Set_Business_Warning( strLuaDEID, key_code, strMsg, strFrom, nLvl, strNote, factory )
    local nRet, strRetInfo
    
    if lua.StrIsEmpty( key_code ) then
        return 1, "Set_Business_Warning 函数中 key_code 必须有值!"
    end

    if strMsg == nil then
        strMsg = ''
    end
    if factory == nil or factory == "" then
        nRet, factory = wms_base.Get_sConst2( "WMS_Default_Factory" )
        if nRet ~= 0 then
            return 1, "系统无法获取常量'WMS_Default_Factory'"
        end          
    end

    if strMsg == '' then
        local strCondition = "S_FACTORY = '" .. factory .."' AND S_CODE = '"..key_code.."'"
        nRet, strRetInfo = mobox.dbdeleteData(strLuaDEID, "WMS_Warning", strCondition)
        if nRet ~= 0 then 
            return 1, "删除【WMS_Warning】失败!"..strRetInfo 
        end  
        return 0  
    end
    
    if strFrom == nil or strFrom == "" then
        strFrom = "Unknown"
    end
    if strNote == nil then
        strNote = ""
    end

    local warning = m3.AllocObject(strLuaDEID,"WMS_Warning")
    warning.code = key_code
    warning.factory = factory
    warning.msg = strMsg
    warning.from = strFrom
    warning.lvl = nLvl
    warning.note = strNote
    warning.type = 1

    -- 获取创建容器时需要的属性
    nRet, warning = m3.CreateDataObj( strLuaDEID, warning, 1 )
    if nRet ~= 0 then
        return 1, "创建 wms_base.Warning 失败! "..warning
    end
    return 0
end

-- 获取货位、库区、仓库等相关的功能区定义列表
-- 这里的位置是一个比较宽泛的范围：库区、货位、仓库、逻辑库区
-- @function wms_base.GetFuncArea
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strPosClsID 位置类型：Area、Zone、Warehouse、Location
-- @tparam string strPosCode 位置编码
-- @tparam string strFuncType 功能类型
-- @treturn number nRet 非零失败
-- @treturn table func_pos 功能区/位列表对象 [{type:0~2, class:"Zone", code:"xxx"}]
function wms_base.GetFuncArea( strLuaDEID, strPosClsID, strPosCode, strFuncType )
    local nRet, strRetInfo, nFuncType

    if type(strFuncType) == "string" then
        nFuncType = wms_base.Get_nConst(strLuaDEID, strFuncType)
    else
        nFuncType = strFuncType
    end
    nRet, strRetInfo = wms.wms_GetFuncArea( strPosClsID, strPosCode, nFuncType )
    if nRet ~= 0 then
        return 1, "wms_GetFuncArea 失败!"..strRetInfo
    end
    if strRetInfo == '' then
        return 1, strPosClsID.."编码 = '"..strPosCode.."' 没有定义类型值 = "..nFuncType.."名称 = '"..strFuncType.."'的功能区"
    end
    local success, ret_pos
    success, ret_pos = pcall( json.decode, strRetInfo )
    if success == false then
        return 1, "wms_GetFuncArea返回值为非法的JSON格式!"..ret_pos
    end
    return 0, ret_pos
end

-- 获取仓库的功能区定义列表
-- @function wms_base.Get_Warehouse_FuncArea
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strWHCode 仓库编码
-- @tparam string strFuncType 功能类型
-- @treturn table func_area 功能区列表
function wms_base.Get_Warehouse_FuncArea( strLuaDEID, strWHCode, strFuncType )
    local nRet, strRetInfo
    nRet, strRetInfo = wms_base.GetFuncArea( strLuaDEID, "Warehouse", strWHCode, strFuncType )
    if nRet ~= 0 then
        return 2, "wms_base.GetFuncArea 失败!"..strRetInfo
    end
    return 0, strRetInfo
end

-- 获取库区的功能区定义列表
-- @function wms_base.Get_Area_FuncArea
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strAreaCode 库区编码
-- @tparam string strFuncType 功能类型
-- @treturn table func_area 功能区列表
function wms_base.Get_Area_FuncArea( strLuaDEID, strAreaCode, strFuncType )
    local nRet, strRetInfo
    nRet, strRetInfo = wms_base.GetFuncArea( strLuaDEID, "Area", strAreaCode, strFuncType )
    if nRet ~= 0 then
        return 2, "wms_base.GetFuncArea 失败!"..strRetInfo
    end
    return 0, strRetInfo
end

-- 获取逻辑库区的功能区定义列表
-- @function wms_base.Get_Zone_FuncArea
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strZoneCode 逻辑库区编码
-- @tparam string strFuncType 功能类型
-- @treturn table func_area 功能区列表
function wms_base.Get_Zone_FuncArea( strLuaDEID, strZoneCode, strFuncType )
    local nRet, strRetInfo
    nRet, strRetInfo = wms_base.GetFuncArea( strLuaDEID, "Zone", strZoneCode, strFuncType )
    if nRet ~= 0 then
        return 2, "wms_base.GetFuncArea 失败!"..strRetInfo
    end
    return 0, strRetInfo
end

-- 获取货位的功能区定义列表
-- @function wms_base.Get_Loc_FuncArea
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strLocCode 货位编码
-- @tparam string strFuncType 功能类型
-- @treturn table func_area 功能区列表
function wms_base.Get_Loc_FuncArea( strLuaDEID, strLocCode, strFuncType )
    local nRet, strRetInfo
    nRet, strRetInfo = wms_base.GetFuncArea( strLuaDEID, "Location", strLocCode, strFuncType )
    if nRet ~= 0 then
        return 2, "wms_base.GetFuncArea 失败!"..strRetInfo
    end
    return 0, strRetInfo
end

-- 入库波次完成后需要把入库波次明细中的入库数量批分到入库明细中的 F_ACC_I_QTY，F_ACC_C_QTY
-- 不建议使用，为了保持兼容，用 wms_in.InboundWave_Finish_PostProce
-- 否则以入库单进行回报时会没有入库数量
-- ****这个函数以后大版本调整时不放在这个程序包处理
-- @function wms_base.InboundWave_Finish_PostProce
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string wave_no 波次号
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string 失败时的错误信息
function wms_base.InboundWave_Finish_PostProce( strLuaDEID, wave_no )
    local nRet, strRetInfo

    if lua.StrIsEmpty( wave_no ) then
        return 1, "wms_base.InboundWave_Finish_PostProce 函数中 wave_no 不能为空!" 
    end

    local iw_detail_objs
    local strCondition = "S_WAVE_NO = '"..wave_no.."'"
    nRet, iw_detail_objs = m3.QueryDataObject(strLuaDEID, "IW_Detail", strCondition, "N_ROW_NO" )
    if nRet ~= 0 then
        return 1, "QueryDataObject失败!"..iw_detail_objs
    end

    if iw_detail_objs == '' then
        return 0
    end
    
    -- 获取入库单明细里的数量
    local inbound_order_objs
    nRet, inbound_order_objs = m3.QueryDataObject(strLuaDEID, "Inbound_Order", strCondition, "S_NO" )
    if nRet ~= 0 then
        return 1, "QueryDataObject失败!"..inbound_order_objs
    end

    if inbound_order_objs == '' then
        return 0
    end
    local io_no_set = {}        -- 入库单号
    local obj_attrs
    for n = 1, #inbound_order_objs do
        obj_attrs  = m3.KeyValueAttrsToObjAttr(inbound_order_objs[n].attrs)
        if obj_attrs == nil then
            return 1, "m3.KeyValueAttrsToObjAttr失败!"
        end
        table.insert( io_no_set, obj_attrs.S_NO )
    end

    local io_detail_objs
    strCondition = "S_IO_NO IN ("..lua.strArray2string( io_no_set )..")"
    nRet, io_detail_objs = m3.QueryDataObject(strLuaDEID, "Inbound_Detail", strCondition, "S_ITEM_CODE" )
    if nRet ~= 0 then
        return 1, "QueryDataObject失败!"..io_detail_objs
    end

    if io_detail_objs == '' then
        return 0
    end
    local nCount = #io_detail_objs
    local io_detail_list = {}
    for n = 1, nCount do
        obj_attrs = m3.KeyValueAttrsToObjAttr(io_detail_objs[n].attrs) 
        if obj_attrs == nil then
            return 1, "m3.KeyValueAttrsToObjAttr失败!"
        end
        local io_detail = {
            id = io_detail_objs[n].id,
            item_code = obj_attrs.S_ITEM_CODE,
            qty = lua.Get_NumAttrValue( obj_attrs.F_QTY ),
            in_qty = 0, cancel_qty = 0, ok = false
        }
        table.insert( io_detail_list, io_detail )
    end

    local cancel_qty, in_qty, x_value, qty
    for n = 1, #iw_detail_objs do
        obj_attrs  = m3.KeyValueAttrsToObjAttr(iw_detail_objs[n].attrs)  
        if obj_attrs == nil then
            return 1, "m3.KeyValueAttrsToObjAttr失败!"
        end
        -- 入库数量
        in_qty = lua.Get_NumAttrValue( obj_attrs.F_ACC_I_QTY )  
        -- 取消数量
        cancel_qty = lua.Get_NumAttrValue( obj_attrs.F_ACC_C_QTY )  
        -- 把 in_qty, cancel_qty 批分到 Inbound_Detail
        for m = 1, nCount do
            if io_detail_list[m].ok == false then
                if io_detail_list[m].item_code == obj_attrs.S_ITEM_CODE then
                    -- 批分入库数量
                    if in_qty > 0 then                        
                        x_value = io_detail_list[m].qty - io_detail_list[m].in_qty - io_detail_list[m].cancel_qty  -- 可以批分的入库数量
                        if in_qty > x_value then
                            qty = x_value
                        else
                            qty = in_qty
                        end
                        in_qty = in_qty - qty
                        io_detail_list[m].in_qty = io_detail_list[m].in_qty + qty 
                    end
                    -- 批分取消数量
                    if cancel_qty > 0 then                        
                        x_value = io_detail_list[m].qty - io_detail_list[m].in_qty - io_detail_list[m].cancel_qty  -- 可以批分的取消数量
                        if cancel_qty > x_value then
                            qty = x_value
                        else
                            qty = cancel_qty
                        end
                        cancel_qty = cancel_qty - qty
                        io_detail_list[m].cancel_qty = io_detail_list[m].cancel_qty + qty 
                    end
                    if io_detail_list[m].qty == (io_detail_list[m].in_qty+io_detail_list[m].cancel_qty) then
                        io_detail_list[m].ok = true
                    end
                end
            end
            if in_qty == 0 and cancel_qty == 0 then
                break
            end
        end
    end

    -- 更新入库单明细中的入库数量，取消数量
    local strSetAttr
    for n = 1, nCount do
        strCondition = "S_ID = '"..io_detail_list[n].id.."'"
        strSetAttr = "F_ACC_I_QTY = "..io_detail_list[n].in_qty..", F_ACC_C_QTY = "..io_detail_list[n].cancel_qty
        nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Inbound_Detail", strCondition, strSetAttr )
        if nRet ~= 0 then
            return 1, "updateDataAttrByCondition(Inbound_Detail)失败"..strRetInfo
        end
    end
    return 0
end

-- 得到当前登录人员的账号信息，并且获取登录人员的PC MAC地址
-- 可以根据这个地址获取绑定的站台
-- @function wms_base.Get_CurLoginUserInfo
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number nRet 0: 成功，非零失败
-- @treturn table ret_value { login, user_name, mac, station }
function wms_base.Get_CurLoginUserInfo( strLuaDEID )
    local nRet, strRetInfo
    local ret_value = {}

    local strUserLogin, strUserName
    nRet, strUserLogin, strUserName = mobox.getCurUserInfo( strLuaDEID )
    if nRet ~= 0 then
        return 2, "获取当前操作人员信息失败! "..strUserLogin
    end
    
    ret_value.login = strUserLogin
    ret_value.user_name = strUserName
    ret_value.mac = ""
    ret_value.station = ""

    -- 获取当前登录账号的电脑MAC地址（如果在MBC上登录是可以获取的）
    nRet, strRetInfo = mobox.getCacheValue( strUserLogin, "__user_terminal__" )
    if nRet == 0 then
        local user_terminal = json.decode( strRetInfo ) 
        ret_value.mac = lua.Get_StrAttrValue( user_terminal.mac )

        -- 根据 MAC-站台 绑定常量获取 站台
        if ret_value.mac ~= '' then
            nRet, ret_value.station = wms_base.Get_sConst2( ret_value.mac )
            if nRet ~= 0 then
                return 1, "系统无法获取常量'"..ret_value.mac.."'"
            end
        end
    end

   return 0, ret_value
end

-- 料箱预分配配置参数检查
-- @function wms_base.PreAllocCntr_CFG_Check
-- @tparam table pac_cfg 预分配配置参数 { wh_code, area_code, station, bs_type, bs_no }
-- @treturn boolean 结果 true/false
-- @treturn string 错误信息
function wms_base.PreAllocCntr_CFG_Check( pac_cfg )
    if pac_cfg == nil or type( pac_cfg ) ~= "table" then
        return false, "料箱预分配配置参数 pac_cfg 必须有值，必须是 table 类型!"
    end    
    if lua.StrIsEmpty( pac_cfg.wh_code ) then
        return false, "料箱预分配配置参数 pac_cfg 中的 wh_code 必须有值!"
    end
    if lua.StrIsEmpty( pac_cfg.bs_type ) then
        return false, "料箱预分配配置参数 pac_cfg 中的 bs_type 必须有值!"
    end
    if lua.StrIsEmpty( pac_cfg.bs_no ) then
        return false, "料箱预分配配置参数 pac_cfg 中的 bs_no 必须有值!"
    end        
    return true
end

-- 根据匹配规则生成查询 INV_Detail 的和 SKU 相关的查询条件
-- @function wms_base.Get_INV_Detail_MatchSql
-- @tparam table item 货品信息（含 S_ITEM_CODE, S_ITEM_STATE, S_STORER 等）
-- @tparam string match_rule 匹配规则，如果为空只是查询 S_ITEM_CODE;S_ITEM_STATE;S_STORER
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string item_sql 生成的 SQL 查询条件
function wms_base.Get_INV_Detail_MatchSql( item, match_rule )
    local value
    local item_sql =  " a.S_ITEM_CODE = '"..item.S_ITEM_CODE.."' AND a.S_ITEM_STATE = '"..item.S_ITEM_STATE.."' AND a.S_STORER = '"..item.S_STORER.."' "

    if match_rule == '' then
        return 0, item_sql
    end

    local seg_attrs = lua.split( match_rule, ';' )
    
    -- MDF BY HAN @20251107
    local nRet, strRetInfo
    nRet, strRetInfo = mobox.getClassAttrDef( "INV_detail", lua.table2str( seg_attrs ))
    if nRet ~= 0 then
        return 1, strRetInfo
    end
    if strRetInfo == '' then
        return 1, "getClassAttrDef 函数返回空值!"
    end
    local success, attr_def_set
    success, attr_def_set = pcall( json.decode, strRetInfo )
    if success == false then
        return 1, "getClassAttrDef 函数返回的字符串格式不对!"..strRetInfo
    end
    local attr_null_in_condition = {}
    -- is_null_in_cond 是‘属性为空也要判断’
    for _, attr_def in ipairs( attr_def_set ) do
        attr_null_in_condition[attr_def.name] = attr_def.is_null_in_cond
    end
    
    local is_null_in_cond
    for _, attr in ipairs( seg_attrs ) do
        -- 匹配规则里的属性没值就不做判断，比如批次号为空的就不做判断
        value = item[attr] or ''
        if value ~= '' then
            item_sql = item_sql.." AND a."..attr.." = '"..item[attr].."' "
        else
            -- MDF BY HAN @20251107 判断值为空的时候是否一定要判断
            is_null_in_cond = attr_null_in_condition[attr] or false
            if is_null_in_cond then
                item_sql = item_sql.." AND a."..attr.." = '' "
            end
        end
    end
    return 0, item_sql
end

-- 判断 sku1, sku2 的 match_attrs 里定义的属性是否全部一样
-- @function wms_base.SKU_Match
-- @tparam table match_attrs 需要匹配的属性列表
-- @tparam table sku1 第一个 SKU 的属性
-- @tparam table sku2 第二个 SKU 的属性
-- @treturn boolean 全部匹配返回 true，否则 false
function wms_base.SKU_Match( match_attrs, sku1, sku2 )
    if match_attrs == nil or sku1 == nil or sku2 == nil then
        return false
    end

    for _, attr in ipairs( match_attrs ) do
        if sku1[attr] ~= sku2[attr] then
            return false
        end
    end
    return true
end

-- 根据分拣规则生成 查询 INV_Detail 时的排序条件
-- 规则说明: FIFO--先进先出 S_WMS_BN, FILO--先进后出 S_WMS_BN Desc, FMFO--生产日期优先 D_PRD_DATE
--          FEFO--有效期优先 D_EXP_DATE, SMALL_QTY--数量小的优先 F_QTY_VALID, BIG_QTY--数量大的优先 F_QTY_VALID Desc
-- @function wms_base.Get_INV_Detail_QueryOrder
-- @tparam string picking_rule 拣货规则，多个规则用 ; 分隔
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string order SQL ORDER BY 子句
-- @treturn table picking_rule_attrs 拣货规则对应的属性列表
function wms_base.Get_INV_Detail_QueryOrder( picking_rule )
    local order = ''

    if picking_rule == '' then
        return 0,"",{}
    end

    local seg_rules = lua.split( picking_rule, ';' )
    local picking_rule_attrs = {}
    for _, rule in ipairs( seg_rules ) do
        if rule == "FIFO" then
            order = order.."a.S_WMS_BN,"
            if lua.IsInTable("S_WMS_BN", picking_rule_attrs) then
                return 1, "分拣规则中 FIFO不能和FILO 同时出现!"
            end
            table.insert( picking_rule_attrs, "S_WMS_BN" )
        elseif rule == "FILO" then
            order = order.."a.S_WMS_BN Desc,"
            if lua.IsInTable("S_WMS_BN", picking_rule_attrs) then
                return 1, "分拣规则中 FILO不能和FIFO 同时出现!"
            end             
            table.insert( picking_rule_attrs, "S_WMS_BN" )
        elseif rule == "FMFO" then
            order = order.."a.D_PRD_DATE,"
            table.insert( picking_rule_attrs, "D_PRD_DATE" )
        elseif rule == "FEFO" then
            order = order.."a.D_EXP_DATE,"
            table.insert( picking_rule_attrs, "D_EXP_DATE" )
        elseif rule == "SMALL_QTY" then
            order = order.."a.F_QTY_VALID," 
            if lua.IsInTable("F_QTY_VALID", picking_rule_attrs) then
                return 1, "分拣规则中 SMALL_QTY不能和BIG_QTY 同时出现!"
            end              
            table.insert( picking_rule_attrs, "F_QTY_VALID" )
        elseif rule == "BIG_QTY" then
            order = order.."a.F_QTY_VALID Desc,"
            if lua.IsInTable("F_QTY_VALID", picking_rule_attrs) then
                return 1, "分拣规则中 BIG_QTY不能和SMALL_QTY 同时出现!"
            end              
            table.insert( picking_rule_attrs, "F_QTY_VALID" )
        end                                                    
    end

    return 0, lua.trim_laster_char( order ), picking_rule_attrs
end

-- 根据SKU的料格定义获取SKU在ctd_code的料箱中,某料格类型 cell_type 的最大装载数量
-- @function wms_base.Get_LoadingLimit
-- @tparam string item_key SKU编码/货主编码，仅仅用于错误时组织信息显示
-- @tparam table sku_grid_parm 料格参数 [{ ctd_code, cell_def: [{ cell_type, loading_limit }] }]
-- @tparam string ctd_code 料箱类型编码
-- @tparam string cell_type 料格类型
-- @treturn number nRet 0: 成功，非零失败
-- @treturn number/string loading_limit 成功返回装载上限，失败返回错误信息
function wms_base.Get_LoadingLimit( item_key, sku_grid_parm, ctd_code, cell_type ) 
    if item_key == nil or item_key == '' then
        return 1, "wms_base.Get_LoadingLimit 函数中 参数 item_key 为空!"
    end
    if lua.isTableEmpty( sku_grid_parm ) then
        return 1, "SKU '"..item_key.."'中没定义料格参数或参数不合规!"
    end   
    local loading_limit
    for _, grid_parm in ipairs( sku_grid_parm ) do
        if grid_parm.ctd_code == ctd_code then
            for _, cell_def in ipairs( grid_parm.cell_def ) do
                if cell_def.cell_type == cell_type then
                    loading_limit = cell_def.loading_limit or 0
                    if loading_limit <= 0 then
                        return 1, "SKU '"..item_key.."'中没定义容器类型='"..ctd_code.."' 料格类型 = '"..cell_type.."' 的装载上限设置错误!"
                    end
                    return 0, loading_limit
                end
            end
        end
    end
    return 1, "SKU '"..item_key.."'中没定义容器类型='"..ctd_code.."' 料格类型 = '"..cell_type.."' 的装载上限设置!"
end

-- 获取SKU在cell_type料格中最大装载数量
-- @function wms_base.GetSKU_LoadingLimit
-- @tparam table sku SKU对象（含 S_ITEM_CODE, S_STORER, sku_grid_parm）
-- @tparam string ctd_code 料箱类型编码
-- @tparam string cell_type 料格类型
-- @treturn number nRet 0: 成功，非零失败
-- @treturn number/string loading_limit 成功返回装载上限，失败返回错误信息
function wms_base.GetSKU_LoadingLimit( sku, ctd_code, cell_type )
    if sku == nil or cell_type == nil or ctd_code == nil or ctd_code == '' then
        return 1, "wms_base.GetSKU_LoadingLimit 输入参数不合规!"
    end
    local nRet, loading_limit
    local item_key = sku.S_ITEM_CODE..'/'..sku.S_STORER
    nRet, loading_limit = wms_base.Get_LoadingLimit( item_key, sku.sku_grid_parm, ctd_code, cell_type )

    return nRet, loading_limit
end

-- 获取WMS作业定义信息
-- @function wms_base.GetOpDefInfo
-- @tparam string factory 工厂编码
-- @tparam string op_def_name 操作定义名称
-- @treturn number nRet 0: 成功，非零失败
-- @treturn table/string op_def 成功返回操作定义对象 { code, name, putaway_rule, ec_callout_rule, hand_proc, priority, type }，失败返回错误信息
function wms_base.GetOpDefInfo( factory, op_def_name )
    local nRet, strRetInfo

    if lua.StrIsEmpty( factory ) then
        return 1, "输入参数 factory 不能为空!"
    end
    if lua.StrIsEmpty( op_def_name ) then
        return 1, "输入参数 op_def_name 不能为空!"
    end  
    nRet, strRetInfo = wms.wms_GetOpDefInfo( factory, op_def_name )
    if nRet ~= 0 then
        return 2, strRetInfo
    end
    local op_def = json.decode( strRetInfo ) 
    if op_def.hand_proc == nil then
        op_def.hand_proc = ''
    end
    if op_def.putaway_rule == nil then
        op_def.putaway_rule = ''
    end
    return 0, op_def
end

-- 获取当前登录人员所属单位标识/编码
-- @function wms_base.GetMyFactory
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string factory 工厂编码
function wms_base.GetMyFactory( strLuaDEID )
    local strUserLogin, strUserName, nRet, strRetInfo
    
    nRet, strUserLogin, strUserName = mobox.getCurUserInfo( strLuaDEID )
    if nRet ~= 0 then
        return 2, "获取当前操作人员信息失败! "..strUserLogin
    end
    -- 获取当前操作人员的单位编码，作为工厂标识
    nRet, strRetInfo = mobox.getUserSectionUnit( strUserLogin )
    if nRet ~= 0 then
        return 2, "获取当前操作人员所属单位失败! "..strRetInfo
    end
    local factory = ''
    if strRetInfo ~= '' then
       local orgInfo = json.decode( strRetInfo ) 
       factory = orgInfo.company_code
    end
    if factory == '' then
        nRet, factory = wms_base.Get_sConst2( "WMS_Default_Factory")
        if nRet ~= 0 then
            return 2, "系统无法获取常量'WMS_Default_Factory'"
        end  
    end
    return 0, factory
end

-- 获取策略信息
-- @function wms_base.GetStrategyInfo
-- @tparam string strategy_type 策略类型
-- @tparam string strategy_code 策略编码
-- @treturn number nRet 0: 成功，非零失败
-- @treturn table/string 成功返回策略对象，失败返回错误信息
function wms_base.GetStrategyInfo( strategy_type, strategy_code )
    local nRet, strRetInfo
    local strategy = {}

    nRet, strRetInfo = wms.wms_GetStrategyInfo( strategy_type, strategy_code )
    if nRet ~= 0 then
        return 1, "在获取'"..strategy_type.."'策略时失败! "..strRetInfo
    end
    local success
    success, strategy = pcall( json.decode, strRetInfo )
    if success == false then
        return 2, "解析 wms_GetStrategyInfo 返回的字符串错误: --> "..strategy
    end  

    return 0, strategy
end

-- 判断字符串末尾是否包含指定子字符串
-- @function string_end_with
-- @tparam string str 原字符串
-- @tparam string ending 目标子字符串
-- @treturn boolean 包含返回 true，否则 false
local function string_end_with( str, ending ) 
    -- 获取原字符串的长度 
    local strLen = #str 
    -- 获取目标子字符串的长度 
    local endingLen = #ending 
    -- 如果原字符串长度小于目标子字符串长度，直接返回 false 
    if strLen < endingLen then 
        return false 
    end 
    -- 提取原字符串末尾与目标子字符串长度相同的部分 
    local endPart = string.sub(str, -endingLen) 
    -- 比较提取的部分与目标子字符串是否相等 
    return endPart == ending 
end 
     
-- 根据策略（上架策略/空料箱呼出策略）获取仓库、库区、巷道等存储区域
-- @function wms_base.Get_Storage_Area_By_Strategy
-- @tparam table strategy 策略对象 { no, name, enable, detail_list: [{ title, priority, enable, match_attr, wh_code, area_code, aisle_code, loc_set }] }
-- @tparam table input_data_attr 料箱扩展属性值（混箱规则）{ S_BATCH_NO, S_UDF01, ... }
-- @treturn number nRet 0: 成功，非零失败
-- @treturn table storage_list 存储库区列表 [{ wh_code, area_code, aisle_no, colume, layer, location, priority }]
function wms_base.Get_Storage_Area_By_Strategy( strategy, input_data_attr )
    if strategy == nil or type( strategy ) ~= "table" then
        return 1, "wms_base.Get_Storage_Area_By_Strategy 函数中参数 strategy 不合规! "
    end
    if strategy.detail_list == nil or type( strategy.detail_list ) ~= "table" then
        return 1, "wms_base.Get_Storage_Area_By_Strategy 函数中参数 strategy.detail_list 不合规! "
    end    

    if input_data_attr == nil or type( input_data_attr ) ~= "table" then
        return 1, "wms_base.Get_Storage_Area_By_Strategy 函数中参数 input_data_attr 不合规! "
    end    

    if not strategy.enable then
        return 1, "策略'"..strategy.no.."'没有启用!"
    end

    local match
    local str_value, n_data_attr_value, str_data_attr_value, n_value
    local storage_list = {}

    for _, strategy_detail in ipairs( strategy.detail_list ) do
        if strategy_detail.enable then
            match = true
            if strategy_detail.match_attr ~= nil and not lua.isTableEmpty( strategy_detail.match_attr ) then
                for _, match_attr in ipairs( strategy_detail.match_attr ) do
                    str_data_attr_value = input_data_attr[match_attr.attr] or ''
                    str_value = match_attr.value or ''
                    if match_attr.type == "string" then
                        -- 等于
                        if match_attr.op == CONDITION_SYMBOL.Equals then
                            if str_value ~= str_data_attr_value then
                                match = false
                                break
                            end
                        -- 不等于
                        elseif match_attr.op == CONDITION_SYMBOL.NotEquals then
                            if str_value == str_data_attr_value then
                                match = false
                                break
                            end
                        -- 为空
                        elseif match_attr.op == CONDITION_SYMBOL.IsEmpty then
                            if str_data_attr_value ~= '' then
                                match = false
                                break
                            end  
                        -- 不为空
                        elseif match_attr.op == CONDITION_SYMBOL.NotEmpty then
                            if str_data_attr_value == '' then
                                match = false
                                break
                            end  
                        -- 包含
                        elseif match_attr.op == CONDITION_SYMBOL.Include then
                            if not string.find( str_data_attr_value, str_value ) then
                                match = false
                                break
                            end
                        -- 不包含
                        elseif match_attr.op == CONDITION_SYMBOL.NotInclude then
                            if string.find( str_data_attr_value, str_value ) then
                                match = false
                                break
                            end  
                        -- 前面有
                        elseif match_attr.op == CONDITION_SYMBOL.FrontInclude then
                            if string.sub( str_data_attr_value, 1, #str_value ) ~= str_value then
                                match = false
                                break
                            end  
                        -- 后面有
                        elseif match_attr.op == CONDITION_SYMBOL.BehindInclude then
                            if not string_end_with( str_data_attr_value, str_value ) then
                                match = false
                                break
                            end                              
                        end                                                      
                    elseif match_attr.type == "number" then
                        n_value = lua.Get_NumAttrValue( str_value )
                        n_data_attr_value = lua.Get_NumAttrValue( str_data_attr_value )
                        -- 等于
                        if match_attr.op == CONDITION_SYMBOL.Equals then
                            if not lua.equation( n_data_attr_value, n_value ) then
                                match = false
                                break
                            end
                        -- 不等于
                        elseif match_attr.op == CONDITION_SYMBOL.NotEquals then
                            if lua.equation( n_data_attr_value, n_value ) then
                                match = false
                                break
                            end
                        -- 大于
                        elseif match_attr.op == CONDITION_SYMBOL.Greater then
                            if n_data_attr_value <= n_value then
                                match = false
                                break
                            end      
                        -- 大于等于
                        elseif match_attr.op == CONDITION_SYMBOL.GreaterOrEquals then
                            if n_data_attr_value < n_value then
                                match = false
                                break
                            end                                                    
                        -- 小于
                        elseif match_attr.op == CONDITION_SYMBOL.Less then
                            if n_data_attr_value >= n_value then
                                match = false
                                break
                            end      
                        -- 小于等于
                        elseif match_attr.op == CONDITION_SYMBOL.LessOrEquals then
                            if n_data_attr_value > n_value then
                                match = false
                                break
                            end                                                    
                        end                        
                    elseif match_attr.type == "date" then 
                        -- 等于
                        if match_attr.op == CONDITION_SYMBOL.Equals then
                            if str_data_attr_value ~= str_value then
                                match = false
                                break
                            end
                        -- 不等于
                        elseif match_attr.op == CONDITION_SYMBOL.NotEquals then
                            if str_data_attr_value == str_value then
                                match = false
                                break
                            end
                        -- 大于
                        elseif match_attr.op == CONDITION_SYMBOL.Greater then
                            if str_data_attr_value <= str_value then
                                match = false
                                break
                            end      
                        -- 大于等于
                        elseif match_attr.op == CONDITION_SYMBOL.GreaterOrEquals then
                            if str_data_attr_value < str_value then
                                match = false
                                break
                            end                                                    
                        -- 小于
                        elseif match_attr.op == CONDITION_SYMBOL.Less then
                            if str_data_attr_value >= str_value then
                                match = false
                                break
                            end      
                        -- 小于等于
                        elseif match_attr.op == CONDITION_SYMBOL.LessOrEquals then
                            if str_data_attr_value > str_value then
                                match = false
                                break
                            end                                                    
                        end                                 
                    end
                end
            end

            if match then
                local storage = {
                    wh_code = strategy_detail.wh_code,
                    area_code = strategy_detail.area_code,
                    aisle_no = strategy_detail.aisle_code,
                    colume = strategy_detail.col_set,
                    layer = strategy_detail.layer_set,
                    location = strategy_detail.loc_set,
                    priority = strategy_detail.priority
                }
                table.insert( storage_list, storage)
            end 
        end
    end

    return 0, storage_list
end

-- 播放一个错误语音（默认 error.mp3），并且设置返回错误信息
-- @function wms_base.Error_Audio
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string err_msg 错误信息
-- @tparam string audio_file 音频文件名，默认为 error.mp3
function wms_base.Error_Audio( strLuaDEID, err_msg, audio_file )
    local nRet, wms_url

    if lua.StrIsEmpty( audio_file ) then
        audio_file = "error.mp3"
    end
    nRet, wms_url = wms_base.Get_sConst2( "Website_URL" ) 
    if nRet ~= 0 then
        lua.Stop( strLuaDEID, "系统无法获取常量'Website_URL'")
        return
    end
    local action = 
    {
        {
            action_type = "play_audio",
            value = wms_url.."/static/audio/"..audio_file        
        }
    } 
    mobox.setAction( strLuaDEID, lua.table2str(action)  )
    lua.Stop( strLuaDEID, err_msg ) 
end

-- 播放一个提示语音（默认 notexist.mp3），并且设置返回信息
-- @function wms_base.Notice_Audio
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string msg 提示信息
-- @tparam string audio_file 音频文件名，默认为 notexist.mp3
function wms_base.Notice_Audio( strLuaDEID, msg, audio_file )
    local nRet, wms_url

    if lua.StrIsEmpty( audio_file ) then
        audio_file = "notexist.mp3"
    end
    nRet, wms_url = wms_base.Get_sConst2( "Website_URL" ) 
    if nRet ~= 0 then
        lua.Stop( strLuaDEID, "系统无法获取常量'Website_URL'")
        return
    end
    local action = 
    {
        {
            action_type = "play_audio",
            value = wms_url.."/static/audio/"..audio_file       
        }
    } 
    mobox.setAction( strLuaDEID, lua.table2str(action)  )
    mobox.setInfo( strLuaDEID, msg ) 
end

-- 获取图片静态资源 URL 地址
-- @function wms_base.Get_ImgUrl
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string img_url 图片 URL 前缀
function wms_base.Get_ImgUrl( )
    local nRet, img_url

    nRet, img_url = wms_base.Get_sConst2( "Website_URL" ) 
    if nRet ~= 0 then
        return 2, "系统无法获取常量'Website_URL'"
    end
    if img_url == '' then
        return 1, "常量'Website_URL'不能为空!"
    end
    img_url = img_url.."/static/img/"
    return 0, img_url
end

-- 解锁库位，把库位上的 N_LOCK_STATE 设为 0，同时删除 Lock 记录
-- @function wms_base.Unlock_Location
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string loc_code 货位编码
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string 失败时的错误信息
function wms_base.Unlock_Location( strLuaDEID, loc_code )
    local nRet, strRetInfo

    if lua.StrIsEmpty( loc_code ) then
        return 1, "wms_base.Unlock_Location 函数中 loc_code 必须有值不能为空!"
    end
    -- 删除 Lock 数据对象
    local strCondition = " S_OBJ_CODE = '"..loc_code.."'"
    nRet, strRetInfo = mobox.dbdeleteData(strLuaDEID, "Lock", strCondition)
    if nRet ~= 0 then 
        return 1, "删除【Lock】失败!"..strRetInfo
    end    
    -- 更新货位表中锁属性
    local strUpdateAttr = "N_LOCK_STATE = 0, S_LOCK_STATE = '', S_LOCK_OP = '' "
    strCondition = "S_CODE = '"..loc_code.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Location", strCondition, strUpdateAttr )
    if nRet ~= 0 then  
        return 1, "更新【Location】信息失败!"..strRetInfo
    end   
    return 0
end

-- 货位加锁，在 Lock 表和 Location 表中记录锁状态
-- @function wms_base.Lock_Location
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string loc_code 货位编码
-- @tparam number lock_state 锁状态（1: 入库锁, 2: 出库锁, 其他: 其它锁）
-- @tparam string task_code 任务编码
-- @tparam string op_code 作业编码
-- @tparam string op_name 作业名称
-- @treturn number nRet 0: 成功，非零失败
-- @treturn string 失败时的错误信息
function wms_base.Lock_Location( strLuaDEID, loc_code, lock_state, task_code, op_code, op_name )
    local nRet, strRetInfo

    if lua.StrIsEmpty( loc_code ) then
        return 1, "wms_base.Lock_Location 函数中 loc_code 必须有值不能为空!"
    end
    if lock_state == nil or type( lock_state ) ~= "number" or lock_state == 0 then
        return 1, "wms_base.Lock_Location 函数中 lock_state 必须有值不能为零!"
    end
    if task_code == nil then
        task_code = ''
    end
    if op_code == nil then
        op_code = ''
    end
    if op_name == nil then
        op_name = ''
    end

    -- 获取货位的锁状态
    local strCondition = "S_CODE = '"..loc_code.."'"
    local loc
    nRet, loc = m3.GetDataObjByCondition( strLuaDEID, "Location", strCondition, "" )
    if nRet ~= 0 then  
        return 1, "获取【Location】信息失败!"..loc 
    end  
    -- 判断 N_LOCK_STATE
    if loc.lock_state ~= 0 then
        return 1, "货位'"..loc_code.."'已经有锁("..loc.lock_state..")"
    end
    -- 判断 是否有 Lock 表
    strCondition =  "S_OBJ_CODE = '"..loc_code.."'"
	nRet, strRetInfo = mobox.existThisData( strLuaDEID, "Lock", strCondition )
    if nRet ~= 0 then 
        return 2, "existThisData 函数失败!"..strRetInfo 
    end
    if strRetInfo ~= 'no' then 
        return 1, "货位'"..loc_code.."'已经Lock记录"
    end

    local lock = m3.AllocObject2(strLuaDEID,"Lock")
    lock.N_OBJ_TYPE = 1
    lock.S_OBJ_CODE = loc_code
    lock.N_TYPE = lock_state
    lock.S_WH_CODE = loc.wh_code
    lock.S_AREA_CODE = loc.area_code
    lock.S_TASK_CODE = task_code
    lock.S_OP_CODE = op_code
    lock.S_OP_NAME = op_name
    nRet, lock = m3.CreateDataObj2( strLuaDEID, lock )     
    if nRet ~= 0 then
        return 2, "创建 【Lock】失败!"..lock 
    end   
    
    local lock_state_name=''
    if lock_state == 1 then
        lock_state_name = "入库锁"
    elseif lock_state == 2 then
        lock_state_name = "出库锁"
    else
        lock_state_name = "其它锁"
    end

    local strUpdateAttr = "N_LOCK_STATE = "..lock_state..", S_LOCK_STATE = '"..lock_state_name.."', S_LOCK_OP = '"..op_code.."'"
    strCondition = "S_CODE = '"..loc_code.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Location", strCondition, strUpdateAttr )
    if nRet ~= 0 then  
        return 1, "更新【Location】信息失败!"..strRetInfo
    end       

    return 0,''
end

-- 获取来源事务的状态（必须有 N_B_STATE）
-- @function wms_base.Get_BS_State
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string bs_type 来源类型：Inbound_Order/Outbound_Order/Inbound_Wave/Outbound_Wave/Count_Plan/Maint_Order/IW_Process
-- @tparam string bs_no 来源单号
-- @treturn number nRet 0: 成功，非零失败
-- @treturn number b_state 来源事务状态
function wms_base.Get_BS_State( strLuaDEID, bs_type, bs_no )
    local nRet, key_attr

    if lua.StrIsEmpty( bs_type ) then
        return 1, " wms_base.Get_BS_State 函数中的参数不合规, bs_type 必须有值!"
    end
    if lua.StrIsEmpty( bs_no ) then
        return 1, " wms_base.Get_BS_State 函数中的参数不合规, bs_no 必须有值!"
    end    
    if bs_type == "Inbound_Order" or bs_type == "Outbound_Order" then
        key_attr = "S_NO"
    elseif bs_type == "Inbound_Wave" or bs_type == "Outbound_Wave" then
        key_attr = "S_WAVE_NO"
    elseif bs_type == "Count_Plan" then
        key_attr = "S_CP_NO"
    elseif bs_type == "Maint_Order" then
        key_attr = "S_M_NO"   
    elseif bs_type == "IW_Process" then
        key_attr = "S_IWP_NO"               
    else
        return 1, "wms_base.Get_BS_State 函数中的参数不合规, bs_type 只能是入库单/入库波次或出库单/出库波次"
    end
    local data_obj
    nRet, data_obj = m3.GetDataObjectByKey( strLuaDEID, bs_type, key_attr, bs_no )
    if nRet ~= 0 then  
        return 2, "获取数据对象'"..bs_type.."', 编号 = '"..bs_no.."'失败!"..data_obj
    end   
    return 0, data_obj.b_state    
end

-- 判断来源业务的状态是否是取消（b_state 在 7-9 之间）
-- @function wms_base.BS_IsCancel
-- @tparam number b_state 业务状态值
-- @treturn boolean 已取消返回 true，否则 false
function wms_base.BS_IsCancel( b_state )
    if b_state >= 7 and b_state <= 9 then 
        return true
    end
    return false
end

-- 获取异常类型索引
-- @function wms_base.GetAnomalyIndex
-- @tparam string str_anomaly 异常类型字符串（中文或英文）
-- @treturn number 异常类型索引（N_ANOMALY_TYPE 枚举值），未匹配返回 0
function wms_base.GetAnomalyIndex( str_anomaly ) 
    if lua.StrIsEmpty( str_anomaly ) then
        return 0
    end
    if str_anomaly == "实物缺货" or str_anomaly == "Short_shipped" then
        return N_ANOMALY_TYPE.Short_shipped
    elseif str_anomaly == "质量异常" or str_anomaly == "Quality_Error" then
        return N_ANOMALY_TYPE.Quality_Error
    elseif str_anomaly == "条码错误" or str_anomaly == "Barcode_Error" then
        return N_ANOMALY_TYPE.Quality_Error
    elseif str_anomaly == "有效期错误" or str_anomaly == "Expiry_Date_Error" then
        return N_ANOMALY_TYPE.Quantity_Error    
    elseif str_anomaly == "包装损坏" or str_anomaly == "Package_Damaged" then
        return N_ANOMALY_TYPE.Quality_Error
    elseif str_anomaly == "系统错误" or str_anomaly == "System_Error" then
        return N_ANOMALY_TYPE.Quantity_Error    
    elseif str_anomaly == "未检查" or str_anomaly == "Unchecked" then
        return N_ANOMALY_TYPE.Quality_Error
    elseif str_anomaly == "单位错误" or str_anomaly == "UOM_error" then
        return N_ANOMALY_TYPE.Quantity_Error            
    end
    return 0
end

-- 合并有相同补料匹配规则的SKU，把合并的行加入 merge_item_list
-- @function wms_base.get_merge_item_list
-- @tparam table ctd 料箱定义（含 si_match_attrs 匹配属性）
-- @tparam table item_list 货品列表
-- @treturn number nRet 0: 有合并，非零: 没有合并
-- @treturn table merge_item_list 合并后的货品列表
function wms_base.get_merge_item_list( ctd, item_list )
    local si_match_attrs = ctd.si_match_attrs or {}

    -- 匹配属性要加上 S_ITEM_CODE, S_STORER, S_ITEM_STATE
    if not lua.IsInTable( "S_STORER", si_match_attrs ) then
        table.insert( si_match_attrs, "S_STORER" )
    end
    if not lua.IsInTable( "S_ITEM_STATE", si_match_attrs ) then
        table.insert( si_match_attrs, "S_ITEM_STATE" )
    end 
    if not lua.IsInTable( "S_ITEM_CODE", si_match_attrs ) then
        table.insert( si_match_attrs, "S_ITEM_CODE" )
    end    
    local match_attr_count = #si_match_attrs
    local find
    local merge_item_list = {}
    local have_merge = false

    for _, item in ipairs( item_list ) do
        find = false
        for _, merge in ipairs( merge_item_list ) do
            find = true
            -- 先判断 S_ITEM_CODE 这样效率高一些
            for n = match_attr_count, 1, -1 do
                if item[si_match_attrs[n]] ~= merge[si_match_attrs[n]] then
                    find = false
                    break
                end
            end

            if find then
                have_merge = true
                merge.qty = merge.qty + item.qty
                merge.is_qty_merge = true
                -- detail_row_list 合并的SKU的行号
                table.insert( merge.detail_row_list, item.row )
                break
            end

        end

        if not find then
            local merge_item = {}
            merge_item = lua.table_deepcopy( item )
            merge_item.is_qty_merge = false
            merge_item.detail_row_list = {}
            table.insert( merge_item.detail_row_list, item.row )
            table.insert( merge_item_list, merge_item )
        end
    end
    if not have_merge then
        return 1
    end
    return 0, merge_item_list
end

-- 从巷道任务数量表获取 aisle_code 巷道的任务数量，并且该巷道的任务数量加一
-- @function wms_base.Add_Aisle_Task_Num
-- @tparam table aisle_set 巷道任务信息数组
-- @tparam string aisle_code 巷道编码
-- @treturn number task_num 返回巷道任务数量
function wms_base.Add_Aisle_Task_Num( aisle_set, aisle_code )
    for _, aisle in ipairs( aisle_set ) do
        if aisle.aisle_code == aisle_code then
            aisle.task_num = aisle.task_num + 1
            return aisle.task_num
        end
    end
    return 0
end

-- 获取满足查询条件的料箱列表，考虑巷道任务均衡
-- @function wms_base.Get_Matching_cntr_list
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须int有值
-- @tparam table pac_cfg 料箱预分配配置参数
-- @tparam string strTable 联表查询的表信息
-- @tparam string strAttrs 查询的属性
-- @tparam int aisle_attr_index 巷道属性在查询结果中的索引
-- @tparam string strCondition 查询条件
-- @tparam string strOrder 排序table/
-- @treturn int nRet 0: 成功, 非零失败
-- @treturn table/string cntr_list nRet = 0 返回cntr_list，nRet != 0返回错误信息
-- 注意: strAttrs 这里第一属性必须是 容器编码
function wms_base.Get_Matching_cntr_list( strLuaDEID, pac_cfg, strTable, strAttrs, aisle_attr_index, strCondition, strOrder)
    local cntr_list = {}    
    -- 获取所有符合条件的料箱
    local nRet, strRetInfo = mobox.queryMultiTable2( strLuaDEID, strAttrs, strTable, 200, strCondition, strOrder)
    if nRet ~= 0 then
        return 1, "queryMultiTable2: " .. strRetInfo
    end
    if strRetInfo == '' then
        -- 没有找到空料箱, 返回空列表
        return 0, cntr_list
    end

    local queryInfo = json.decode(strRetInfo)
    local nPageCount = queryInfo.page_count
    local nPage = 1
    local data_list = queryInfo.data_list
    local aisle_code, task_num

    local aisle_set = lua.table_deepcopy( pac_cfg.aisle_set )
    while nPage <= nPageCount do
        for n = 1, #data_list do
            task_num = 0
            -- 获取返回值中的巷道属性
            aisle_code = ''
            if pac_cfg.aisle_lb == 1 then
                aisle_code = data_list[n][aisle_attr_index]
                -- 获取巷道任务数量，并且给当前巷道的任务数量+1
                task_num = wms_base.Add_Aisle_Task_Num( aisle_set, aisle_code )
            end
            local cntr = {
                cntr_code = data_list[n][1],
                aisle_code = aisle_code,
                task_num = task_num,
                attrs = data_list[n]
            }
            table.insert(cntr_list, cntr)
        end

        nPage = nPage + 1
        if nPage <= nPageCount then
            -- 取下一页
            nRet, strRetInfo = mobox.queryMultiTable2(strLuaDEID, nPage)
            if nRet ~= 0 then
                return 1, "查询【容器】失败! nPage=" .. nPage .. "  " .. strRetInfo
            end
            queryInfo = json.decode(strRetInfo)
            data_list = queryInfo.data_list
        end
    end    

    if pac_cfg.aisle_lb == 1 then
        -- 根据任务数量进行排序
        table.sort( cntr_list, function(a, b) return a.task_num < b.task_num end )
    end    
    return 0, cntr_list
end

-- 检测需要入库预分配的货品清单是否已经全部有了预分配
-- @function wms_base.item_list_is_all_ok
-- @tparam table item_list 货品列表
-- @treturn boolean 全部已预分配返回 true，否则 false
function wms_base.item_list_is_all_ok( item_list )
    for _, item in ipairs( item_list ) do
        if not item.ok then
            return false
        end
    end
    return true
end

-- 通过 addBackendScriptProc 启动后台脚本进程并轮询等待处理结果（带超时控制）
-- @function wms_base.WaitForPostEventProcess
-- @tparam string cls_id 数据类标识，不能为空
-- @tparam string event_name 事件名称，不能为空
-- @tparam string data_json 传递给后台进程的 JSON 数据（可选）
-- @tparam number timeout 超时时间（毫秒），默认 6000（6秒）
-- @tparam number interval 轮询间隔（毫秒），默认 50
-- @treturn number nRet 0: 处理完成，1: 超时，2: 进程错误
-- @treturn string result 成功时返回处理结果，失败/超时时返回错误信息
function wms_base.WaitForPostEventProcess( cls_id, event_name, data_json, timeout, interval )
    if cls_id == nil or cls_id == '' then
        return 2, "cls_id 不能为空"
    end
    if event_name == nil or event_name == '' then
        return 2, "event_name 不能为空"
    end
    if data_json == nil then
        data_json = ''
    end
    local nRet, process_id = mobox.addBackendScriptProc( cls_id, event_name, data_json )
    if nRet ~= 0 then
        return 2, "后台进程启动失败!"..process_id
    end

    if timeout == nil then
        timeout = 6 * 1000          -- 6秒超时
    end
    if interval == nil then
        interval = 50               -- 轮询间隔 50ms
    end

    local elapsed = 0
    local result = ''
    local loop_count = 0

    while true do
        while elapsed < timeout do
            nRet, result = mobox.getBackendScriptProcResult( process_id )
            if nRet == 1 then
                -- 处理完成
                return 0, result
            elseif nRet == 2 then
                -- 处理出错s
                return 2, "后台进程执行错误: " .. result
            end
            -- nRet == 0 表示尚未完成，继续等待
            mobox.sleep( interval )
            elapsed = elapsed + interval
        end
        elapsed = 0
        -- 超时
        -- 移除后台进程
        nRet, result = mobox.removeBackendScriptProc( process_id )
        if nRet == 3 then
            --移除进程无法移除，说明已经在处理
            loop_count = loop_count + 1
        elseif nRet == 0 then
            -- 移除成功
            return 1, "后台进程超时! process_id = " .. process_id
        else
            return 2, "后台进程移除失败: " .. result
        end
        if loop_count > 2 then
            break
        end
    end
    return 2, "后台进程超时！"
end

-- 获取符合查询条件的数据对象列表
-- @function wms_base.GetDataObjList
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须int有值
-- @tparam string cls_id 数据类标识，不能为空
-- @tparam string strCondition 查询条件
-- @treturn number nRet 0: 处理完成，非零错误
-- @treturn table dataobj_list 成功时返回数据对象列表，失败/超时时返回错误信息
function wms_base.GetDataObjList( strLuaDEID, cls_id, strCondition )
    local nRet, data_objs = m3.QueryDataObject( strLuaDEID, cls_id, strCondition )
    if nRet ~= 0 then 
        return 1, "获取'"..cls_id.."'信息失败! " .. data_objs
    end
    
    local data_obj_list = {}

    if data_objs == '' then
        return 0, data_obj_list 
    end
    for _, obj in ipairs( data_objs ) do
        local data_obj = m3.KeyValueAttrsToObjAttr( obj.attrs )
        if data_obj == nil then
            return 1, "获取'"..cls_id.."'信息失败! "
        end
        table.insert( data_obj_list, data_obj )
    end
    return 0, data_obj_list
end

-- 重新装载和WMS基础数据相关的所有数据对象
function wms_base.Reload_WMS_Resident( strLuaDEID, factory_no )

    if factory_no == nil or factory_no == '' then
        return 1, "工厂编码不能为空!"
    end
    local strCondition = "S_FACTORY = '"..factory_no.."'"
    mobox.reloadMemoryDataObjByCondition( strLuaDEID, "Container_Type_Def", strCondition )
    mobox.reloadMemoryDataObjByCondition( strLuaDEID, "Warehouse", strCondition )
    mobox.reloadMemoryDataObjByCondition( strLuaDEID, "Machine_Station", strCondition )    

    strCondition = "S_WH_CODE IN ( select S_CODE from Warehouse where S_FACTORY = '"..factory_no.."')"
    mobox.reloadMemoryDataObjByCondition( strLuaDEID, "Area", strCondition )
    mobox.reloadMemoryDataObjByCondition( strLuaDEID, "Aisle", strCondition )
    mobox.reloadMemoryDataObjByCondition( strLuaDEID, "Rack", strCondition )
    mobox.reloadMemoryDataObjByCondition( strLuaDEID, "Location", strCondition )

end

-- 清空指定条件的数据对象，并且返回删除的数据对象列表
-- @function wms_base.Clear_Data
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须int有值
-- @tparam string cls_id 数据类标识，不能为空
-- @tparam string strCondition 查询条件
-- @treturn number nRet 0: 处理完成，非零错误
-- @treturn table dataobj_list 成功时返回删除的数据对象列表，失败/超时时返回错误信息
function wms_base.Clear_Data( strLuaDEID, cls_id, strCondition )
    local nRet, data_objs = m3.QueryDataObject( strLuaDEID, cls_id, strCondition )
    if nRet ~= 0 then 
        return 1, "获取'"..cls_id.."'信息失败! " .. data_objs
    end
    
    local data_obj_list = {}
    local err

    if data_objs == '' then
        return 0, data_obj_list 
    end
    for _, obj in ipairs( data_objs ) do
        local data_obj = m3.KeyValueAttrsToObjAttr( obj.attrs )
        if data_obj == nil then
            return 1, "获取'"..cls_id.."'信息失败! "
        end
        table.insert( data_obj_list, data_obj )
    end
    nRet, err = mobox.dbdeleteData(strLuaDEID, cls_id, strCondition)    
    if nRet ~= 0 then 
        return 1, "删除'"..cls_id.."'数据失败! " .. err
    end
    return 0, data_obj_list
end

return wms_base