--[[
    版本：     Version 3.0
    创建日期： 2025-4-10
    修改日期:  2026-6-19
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    名称:   wms_sync
    功能：   WMS 和上下游系统进行数据同步时用到的标准函数

    【数据同步】
        CreateDataSync  — 创建数据同步记录（WMS_Data_Sync）

    更改记录:
        2025-4-10  HAN  创建
        2026-6-19        整理函数注释，添加 @tparam/@treturn 注解

    AI CHECK:
        -- 20260619
--]]

m3 = require ("oi_base_mobox")

local wms_sync = {_version = "0.1.1"}

-- 创建数据同步记录（WMS_Data_Sync）
-- @function wms_sync.CreateDataSync
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string sync_cls 同步分类
-- @tparam string sync_obj_id 同步对象ID
-- @tparam string sync_bn 同步业务号
-- @tparam string note 备注（可以为空）
-- @treturn number nRet 0: 成功，1: 创建失败，2: 参数错误
-- @treturn table/string data_sync 成功返回 WMS_Data_Sync 对象，失败返回错误信息
function wms_sync.CreateDataSync( strLuaDEID, sync_cls, sync_obj_id, sync_bn, note )
    local nRet

    if lua.StrIsEmpty( sync_cls ) then
        return 2, "wms_sync.CreateDataSync 函数中 sync_cls 必须有值" 
    end
    if lua.StrIsEmpty( sync_obj_id ) then
        return 2, "wms_sync.CreateDataSync 函数中 sync_obj_id 必须有值" 
    end
    if lua.StrIsEmpty( sync_bn ) then
        return 2, "wms_sync.CreateDataSync 函数中 sync_bn 必须有值" 
    end
    if note == nil then
        note = ''
    end

    local data_sync = m3.AllocObject2(strLuaDEID,"WMS_Data_Sync")
    data_sync.S_SYNC_CLS = sync_cls
    data_sync.G_SYNC_OBJ_ID = sync_obj_id
    data_sync.S_SYNC_BN = sync_bn
    data_sync.S_NOTE = note

    nRet, data_sync = m3.CreateDataObj2( strLuaDEID, data_sync )   
    if nRet ~= 0 then 
        return 1, "创建【WMS_Data_Sync】失败!"..data_sync

    end  
    return 0, data_sync
    
end
return wms_sync
