--[[
    版本：    Version 2.1
    创建日期： 2023-6-16
    修改日期： 2026-6-17
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5
        
    功能：
        wms_dev Lua程序包整合了一些和设备通讯项相关的一些函数

        -- GetDeviceCommSInfo         获取 OIDeviceComms 服务的IP地址、访问Key和Secret
        -- GetDeviceCommSExtInfo      获取设备通讯项相关的扩展信息，比如和该设备通讯项相关的货位
        -- ReadS7PLCCommsData         从S7 PLC的通讯项里读取数据
        -- WriteS7PLCCommsData        写数据到S7 PLC的通讯项

    更改说明：

    AI CHECK
        -- 20260617 统一代码风格，统一函数注释格式，整理外部函数列表至文件头部
--]]

wms_base = require ("wms_base")

local wms_dev = {_version = "0.1.1"}
--//////////////////////////////////////// 设备通讯相关 //////////////////////////////////////////////////////////////
-- 获取 OIDeviceComms 服务的IP地址、访问Key和Secret
-- @function wms_dev.GetDeviceCommSInfo
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number nRet 0表示成功，1表示失败
-- @treturn string 成功时返回服务地址，失败时返回错误信息
-- @treturn string 成功时返回访问Key
-- @treturn string 成功时返回访问Secret
function wms_dev.GetDeviceCommSInfo( strLuaDEID )
    local strDeviceCommSvr, strKey, strSecret
    local nRet

    nRet, strDeviceCommSvr = mobox.getParameter(strLuaDEID, '9100')
    if nRet ~= 0 then 
        return 1, "系统无法获取9100参数(OIDeviceCommS服务器配置)! "..strDeviceCommSvr
    end 
    if strDeviceCommSvr == '' or strDeviceCommSvr == nil then 
        return 1, "9100参数值为空, 请到系统参数进行设置! "
    end

    nRet, strKey = mobox.getParameter(strLuaDEID, '9101')
    if nRet ~= 0 then 
        return 1, "系统无法获取9101参数(OIDeviceCommS服务器Key设置)! "..strKey
    end 
    if strKey == '' or strKey == nil then 
        return 1, "9101参数值为空, 请到系统参数进行设置! "
    end

    nRet, strSecret = mobox.getParameter(strLuaDEID, '9102')
    if nRet ~= 0 then 
        return 1, "系统无法获取9102参数(OIDeviceCommS服务器Key设置)! "..strSecret
    end 
    if strSecret == '' or strSecret == nil then 
        return 1, "9102参数值为空, 请到系统参数进行设置! "
    end

    return 0, strDeviceCommSvr, strKey, strSecret
end

-- 获取设备通讯项相关的扩展信息，比如和该设备通讯项相关的货位
-- @function wms_dev.GetDeviceCommSExtInfo
-- @tparam string device_code 设备编码
-- @tparam string comm_code 通讯项编码
-- @treturn number nRet 0表示成功，2表示失败
-- @treturn table 成功时返回扩展信息对象，失败时返回错误信息
function wms_dev.GetDeviceCommSExtInfo( device_code, comm_code )
    local nRet, strRetInfo

    nRet, strRetInfo = wms.wms_GetDevCommExt( device_code, comm_code )
    if nRet ~= 0 or strRetInfo == '' then 
        return 2, 'wms_GetDevCommExt 失败!'..strRetInfo 
    end
    local success
    local dev_comms_ext
    success, dev_comms_ext = pcall( json.decode, strRetInfo)
    if success == false then 
        return 2, "wms_GetDevCommExt 返回的结果不正确! 非法的JSON格式!"..dev_comms_ext
    end
    return 0, dev_comms_ext
end

-- 从S7 PLC的通讯项里读取数据
-- @function wms_dev.ReadS7PLCCommsData
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string device_code 设备编码
-- @tparam string comm_code 通讯项编码
-- @treturn number nRet 0表示成功，1表示失败
-- @treturn any 成功时返回读取到的数据值，失败时返回错误信息
function wms_dev.ReadS7PLCCommsData( strLuaDEID, device_code, comm_code )
    if device_code == nil or device_code == '' then 
        return 1, "ReadS7PLCCommsData 函数参数错误,设备编码不能为空! "
    end
    if comm_code == nil or comm_code == '' then 
        return 1, "ReadS7PLCCommsData 函数参数错误,通讯项编码不能为空! "
    end

    local strDeviceCommSvr, strKey, strSecret
    local nRet, strRetInfo

    strDeviceCommSvr, strKey, strSecret = wms_dev.GetDeviceCommSInfo( strLuaDEID )

    local strurl = strDeviceCommSvr..'/api/devctrl/readdata'
    local body = {}
    local strHeader = ''

    body.device_code = device_code
    body.comm_code = comm_code
    -- 获取Header
    nRet, strHeader = mobox.genReqVerify( strKey, strSecret )
    if nRet ~= 0 then 
        return 1, "获取PLC服务访问授权失败! "..strHeader
    end
    nRet, strRetInfo = mobox.sendHttpRequest( strurl, strHeader, lua.table2str(body) )

    if nRet ~= 0 or strRetInfo == '' then 
        return 1, "调用OIDeviceCommS接口ReadData失败! device_code = "..device_code.." comm_code = "..comm_code.."错误码:"..nRet.."  "..strRetInfo
    end
    local api_ret = json.decode(strRetInfo)
    if api_ret.err_code ~= 0 then 
        return 1, "调用OIDeviceCommS接口ReadData失败!  device_code = "..device_code.." comm_code = "..comm_code.."错误码:"..api_ret.err_code.."  "..api_ret.err_msg
    end
    return 0, api_ret.result.value
end

-- 写数据到S7 PLC的通讯项
-- @function wms_dev.WriteS7PLCCommsData
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table body 写入数据对象，需包含device_code和comm_code字段
-- @treturn number nRet 0表示成功，1表示失败
-- @treturn string 失败时返回错误信息
function wms_dev.WriteS7PLCCommsData( strLuaDEID, body )
    local strDeviceCommSvr, strKey, strSecret, nRet, strRetInfo
    strDeviceCommSvr, strKey, strSecret = wms_dev.GetDeviceCommSInfo( strLuaDEID )

    local strurl =  strDeviceCommSvr..'/api/devctrl/writedata'
    local strHeader = ''

    -- 获取Header
    nRet, strHeader = mobox.genReqVerify( strKey, strSecret )
    if nRet ~= 0 then 
        return 1, "获取PLC服务访问授权失败! "..strHeader
    end
    -- 写PLC地址
    nRet, strRetInfo = mobox.sendHttpRequest( strurl, strHeader, lua.table2str(body) )

    if nRet ~= 0 or strRetInfo == '' then 
        return 1, "S7PLC 写入失败!  device_code = "..body.device_code.." comm_code = "..body.comm_code.."错误码:"..nRet.."  "..strRetInfo
    end
    local api_ret = json.decode(strRetInfo)
    if api_ret.err_code ~= 0 then 
        return 1, "S7PLC 写入失败! device_code = "..body.device_code.." comm_code = "..body.comm_code.."错误码:"..api_ret.err_code.." --> "..api_ret.err_msg
    end
    return 0
end

return wms_dev
