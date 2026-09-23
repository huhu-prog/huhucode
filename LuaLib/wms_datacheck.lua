--[[
    版本：    Version 2.1
    创建日期： 2024-6-10
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    功能：
        WMS 一些基础数据直接会影响后面的业务逻辑，因此需要做一些数据校验
        检验数据包括：
        Location_Group
              -- N_CAPACITY, N_CURRENT_NUM, N_OUT_LOCK_NUM, S_ITEM_CODE,...

        -- DataCheck_Loaction_Group  货位组

--]]
wms_base = require ("wms_base")

local wms_check = {_version = "0.2.1"}

local function upadte_location_group( strLuaDEID, id, strSetAttr, strCheckResult )
    local nRet, strRetInfo

    local curTime = os.date("%Y-%m-%d %H:%M:%S Checked -> ")
    if ( strCheckResult == '' ) then strCheckResult = "OK" end
    strCheckResult = curTime..strCheckResult
    strSetAttr = strSetAttr.."S_CHECK_RESULT = '"..strCheckResult.."'"

    strCondition = "S_ID = '"..id.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Location_Group", strCondition, strSetAttr )
    if ( nRet ~= 0 ) then  
        lua.Debug( strLuaDEID, debug.getinfo(1), "更新【货位组】失败!", strRetInfo )
        return 1, "更新【货位组】失败! 见调试日志"        
    end
    return 0, "ok"
end

--[[
    校验货位组属性的正确性（考虑作废）
--]]
function wms_check.Loaction_Group( strLuaDEID, id )
    local nRet, strValue

    if (id == '' or id == nil ) then
        return 1, "wms_check.Loaction_Group 参数id必须有值!"
    end
    -- 把GUID {xxxx-xxxx} 改成 xxxx-xxxx
    id = lua.trim_guid_str(id)

    local data_obj
    nRet, data_obj = m3.GetDataObject( strLuaDEID, "Location_Group", id ) 
    if ( nRet ~= 0 )  then 
        lua.Debug( strLuaDEID, debug.getinfo(1), "GetDataObject失败!", data_obj )
        return 1, "GetDataObject失败! 见调试日志" 
    end 

    -- 首先需要获取 货位组 有哪些货位组成
    local loc_set = {}
    local strOrder = ''
    local strLocCondition = "S_AREA_CODE ='"..data_obj.area_code.."' AND N_ROW_GROUP = "..data_obj.row_group.." AND N_COL = "..data_obj.col.." AND N_LAYER = "..data_obj.layer
    nRet, strRetInfo = mobox.queryDataObjAttr( strLuaDEID, "Location", strLocCondition, strOrder )
    if ( nRet ~= 0 ) then 
        lua.Debug( strLuaDEID, debug.getinfo(1), "获取【Location】失败!", strLocCondition )
        return 1, "获取【Location】失败! 见调试日志"
    end

    local ext_data = {}
    ext_data.id = id
    ext_data.cls = "Location_Group"
    local strSetAttr = ''
    local strCheckResult = ''           -- 校验结果

    if ( strRetInfo == '' ) then 
        -- 201 无效数据
        wms_base.Warning( strLuaDEID, 2, 201, "无效货位组，建议删除!", lua.table2str(ext_data), "", "DataCheck" )
        nRet, strRetInfo = upadte_location_group( strLuaDEID, id, "", "无效货位组，建议删除!" )
        return nRet, strRetInfo
    end

    local retObjs = json.decode( strRetInfo )
    local n
    local capacity = 0
    local cur_num = 0
    local in_lock_num = 0
    local out_lock_num = 0
    local loc = {}

    -- 获取同一个货位组的货位信息，重新计算 capacity 等数值量
    for n = 1, #retObjs do
        nRet, loc = m3.ObjAttrStrToLuaObj( "Location", lua.table2str(retObjs[n].attrs) )
        if ( nRet ~= 0 ) then 
            lua.Debug( strLuaDEID, debug.getinfo(1), "m3.ObjAttrStrToLuaObj(Location) 失败!", loc )
            return 1, "m3.ObjAttrStrToLuaObj(Location) 失败! 见调试日志"
        end  
        capacity = capacity + loc.capacity
        cur_num = cur_num + loc.cur_num
        -- 1 入库锁  2 出库锁
        if ( loc.lock_state == 1 ) then 
            in_lock_num = in_lock_num + 1
        elseif ( loc.lock_state == 2 ) then 
            out_lock_num = out_lock_num + 1
        end
    end   

    if ( data_obj.capacity ~= capacity ) then
        strSetAttr = strSetAttr.."N_CAPACITY = "..capacity..","
        strCheckResult = strCheckResult.."容量:("..data_obj.capacity.." -> "..capacity.."),"
    end

    if ( data_obj.cur_num ~= cur_num ) then
        strSetAttr = strSetAttr.."N_CURRENT_NUM = "..cur_num..","
        strCheckResult = strCheckResult.."容器数量:("..data_obj.cur_num.." -> "..cur_num.."),"
    end
    
    if ( data_obj.in_lock_num ~= in_lock_num ) then
        strSetAttr = strSetAttr.."N_IN_LOCK_NUM = "..in_lock_num..","
        strCheckResult = strCheckResult.."入库锁数量:("..data_obj.in_lock_num.." -> "..in_lock_num.."),"
    end
    
    if ( data_obj.out_lock_num ~= out_lock_num ) then
        strSetAttr = strSetAttr.."N_OUT_LOCK_NUM = "..out_lock_num..","
        strCheckResult = strCheckResult.."出库锁数量:("..data_obj.out_lock_num.." -> "..out_lock_num.."),"
    end    

    -- 获取货位组里的存储的货品信息
    local strCondition = "S_CNTR_CODE IN ( Select S_CNTR_CODE From TN_Loc_Container Where S_LOC_CODE In ( Select S_CODE From TN_Location "
    strCondition = strCondition.." Where "..strLocCondition.."))"
    local strOrder = "S_CNTR_CODE"
    nRet, strRetInfo = mobox.queryDataObjAttr( strLuaDEID, "INV_Detail", strCondition, strOrder )
    if ( nRet ~= 0 ) then  
        lua.Debug( strLuaDEID, debug.getinfo(1), "获取【INV_Detail】失败!", strCondition )
        return 1, "获取【INV_Detail】失败! 见调试日志"
    end 

    if ( strRetInfo ~= '' ) then
        local inv_detail
        local item_code = ''
        local item_name = ''
        local batch_no = ''
        local owner = ''
        local end_user = ''
        local supplier = ''

        retObjs = json.decode( strRetInfo )
        for n = 1, #retObjs do
            nRet, inv_detail = m3.ObjAttrStrToLuaObj( "INV_Detail", lua.table2str(retObjs[n].attrs) )
            if ( nRet ~= 0 ) then 
                lua.Debug( strLuaDEID, debug.getinfo(1), "m3.ObjAttrStrToLuaObj(INV_Detail) 失败!", loc )
                return 1, "m3.ObjAttrStrToLuaObj(INV_Detail)) 失败! 见调试日志"
            end 
            if ( n == 1 ) then
                item_code = inv_detail.item_code
                item_name = inv_detail.item_name
                batch_no = inv_detail.batch_no
                owner = inv_detail.owner
                end_user = inv_detail.end_user
                supplier = inv_detail.supplier
            else
                if ( item_code ~= inv_detail.item_code ) then item_code = '' end
                if ( item_name ~= inv_detail.item_name ) then item_name = '' end
                if ( batch_no ~= inv_detail.batch_no ) then batch_no = '' end
                if ( owner ~= inv_detail.owner ) then owner = '' end
                if ( end_user ~= inv_detail.end_user ) then end_user = '' end
                if ( supplier ~= inv_detail.supplier ) then supplier = '' end
            end 
        end  
        
        if ( data_obj.item_code ~= item_code ) then
            strSetAttr = strSetAttr.."S_ITEM_CODE = '"..item_code.."',"
            strCheckResult = strCheckResult..'物料编码:("'..data_obj.item_code..'" -> "'..item_code..'"),'
        end
        if ( data_obj.item_name ~= item_name ) then
            strSetAttr = strSetAttr.."S_ITEM_NAME = '"..item_name.."',"
            strCheckResult = strCheckResult..'物料名称:("'..data_obj.item_name..'" -> "'..item_name..'"),'
        end
        if ( data_obj.batch_no ~= batch_no ) then
            strSetAttr = strSetAttr.."S_BATCH_NO = '"..batch_no.."',"
            strCheckResult = strCheckResult..'批次号:("'..data_obj.batch_no..'" -> "'..batch_no..'"),'
        end
        if ( data_obj.owner ~= owner ) then
            strSetAttr = strSetAttr.."S_OWNER = '"..owner.."',"
            strCheckResult = strCheckResult..'货主:("'..data_obj.owner..'" -> "'..owner..'"),'
        end
        if ( data_obj.end_user ~= end_user ) then
            strSetAttr = strSetAttr.."S_ITEM_CODE = '"..end_user.."',"
            strCheckResult = strCheckResult..'使用单位:("'..data_obj.end_user..'" -> "'..end_user..'"),'
        end
        if ( data_obj.supplier ~= supplier ) then
            strSetAttr = strSetAttr.."S_ITEM_CODE = '"..supplier.."',"
            strCheckResult = strCheckResult..'供应商:("'..data_obj.supplier..'" -> "'..supplier..'"),'
        end     
    end

    nRet, strRetInfo = upadte_location_group( strLuaDEID, id, strSetAttr, strCheckResult )
    return nRet, strRetInfo
end

return wms_check