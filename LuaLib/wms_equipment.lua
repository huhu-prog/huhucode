--[[
    版本：     Version 2.1
    创建日期： 2025-1-29
    修改日期： 2026-6-17
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    功能：
        wms_equipment Lua程序包整合了一些和设备，设备动作等相关的一些函数

        -- GetInfo                   根据设备号获取设备属性
        -- MQ_EQAction_Exist         判断消息队列中是否存在未处理的设备动作记录

    更改说明：

    AI CHECK
        -- 20260617 统一代码风格，统一函数注释格式，整理外部函数列表至文件头部
--]]
wms_base = require ("wms_base")

local wms_eq = {_version = "0.2.1"}

-- 根据设备号获取设备属性
-- @function wms_eq.GetInfo
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string eq_code 设备编码
-- @treturn number nRet 0获取设备信息，1不存在，2错误
-- @treturn table 成功时返回设备对象，失败时返回错误信息
function wms_eq.GetInfo( strLuaDEID, eq_code )
    local nRet, strRetInfo, id

    if eq_code == nil or eq_code == '' then
        return 1, "调用 wms_eq.Equipment_GetInfo 函数时参数不正确，设备编码不能为空!"
    end
    local strCondition = "S_CODE = '"..eq_code.."'"
    nRet, id, strRetInfo = mobox.getDataObjAttrByKeyAttr( strLuaDEID, "Equipment", strCondition )
    if nRet == 1 then
        return 1, "设备编码='"..eq_code.."'的设备不存在!"
    end
    if nRet ~= 0 then
        return 2, "getDataObjAttrByKeyAttr 发生错误!"..id
    end

    nRet, strRetInfo = mobox.objAttrsToLuaJson( "Equipment", strRetInfo )
    if nRet ~= 0 then
        return 2, "objAttrsToLuaJson Equipment 失败!"..strRetInfo
    end

    local object, success
    success, object = pcall( json.decode, strRetInfo )
    if success == false then
        return 0, "objAttrsToLuaJson('Equipment') 返回的的JSON格式不合法!"
    end
    object.id = id
    return 0, object
end

-- 判断消息队列中是否存在未处理的设备动作记录（N_B_STATE=0）
-- @function wms_eq.MQ_EQAction_Exist
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table mq_eq_action 查询对象，需包含action_code和eq_code字段
-- @treturn number nRet 0表示成功，非零表示有错
-- @treturn string strResult "no"表示不存在，"yes"表示存在
function wms_eq.MQ_EQAction_Exist( strLuaDEID, mq_eq_action )
    local strCondition, nRet, strRetInfo

    strCondition = "N_ACTION_CODE = "..mq_eq_action.action_code.." AND S_EQ_CODE = '"..mq_eq_action.eq_code.."' AND N_B_STATE = 0 "
    nRet, strRetInfo = mobox.existThisData( strLuaDEID, "MQ_EQAction", strCondition )
    return nRet, strRetInfo
end

return wms_eq