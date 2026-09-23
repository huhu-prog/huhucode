--[[
    版本：     Version 1.0
    创建日期： 2025-6-10
    修改日期： 2026-6-17
    创建人：   HAN

    功能：
        WMS 库内管理

        -- Create_SOO_ByContainer     根据容器号创建一个指定出库作业
        -- CNTR_Move                  容器从当前绑定的货位移动到新的货位

    更改说明：

    AI CHECK
        -- 20260617 统一代码风格，统一函数注释格式，整理外部函数列表至文件头部
--]]

wms_cntr = require ("wms_container")
wms_wh   = require ("wms_wh")

local wms_mang = {_version = "0.1.1"}

local function create_so_cntr_detail( strLuaDEID, station, cntr_code, so_no, soc_no, item_code )
    local nRet, strRetInfo
    local obj_attrs, data_objs
    local strCondition = "S_CNTR_CODE = '"..cntr_code.."'"
    local so_cntr_detail

    if ( item_code ~= nil and item_code ~= '' ) then
        strCondition = strCondition.." AND S_ITEM_CODE = '"..item_code.."'"
    end

    nRet, data_objs = m3.QueryDataObject( strLuaDEID, "INV_Detail", strCondition )
    if ( nRet ~= 0 ) then return 1, "获取【INV_Detail】失败! "..data_objs end
    if ( data_objs == '' ) then return 0 end

    for n = 1, #data_objs do
        obj_attrs = m3.KeyValueAttrsToObjAttr(data_objs[n].attrs)

        so_cntr_detail = m3.AllocObject(strLuaDEID,"SO_CNTR_Detail")
        so_cntr_detail.soc_no = soc_no
        so_cntr_detail.station = station
        so_cntr_detail.so_no = so_no
        so_cntr_detail.cntr_code = cntr_code
        so_cntr_detail.qty = lua.Get_NumAttrValue( obj_attrs.F_QTY )
        so_cntr_detail.cell_no = obj_attrs.S_CELL_NO
        so_cntr_detail.item_code = obj_attrs.S_ITEM_CODE
        so_cntr_detail.item_name = obj_attrs.S_ITEM_NAME
        so_cntr_detail.item_state = lua.StrToNumber( obj_attrs.N_ITEM_STATE )
        so_cntr_detail.batch_no = obj_attrs.S_BATCH_NO  
        so_cntr_detail.serial_no = obj_attrs.S_SERIAL_NO  
        so_cntr_detail.erp_wh_code = obj_attrs.S_ERP_WH_CODE  
        so_cntr_detail.end_user = obj_attrs.S_END_USER  
        so_cntr_detail.owner = obj_attrs.S_OWNER  
        so_cntr_detail.supplier = obj_attrs.S_SUPPLIER_NO   
        
        so_cntr_detail.uom = obj_attrs.S_UOM        
        so_cntr_detail.ext_attr1 = obj_attrs.S_EXT_ATTR1      
        so_cntr_detail.ext_attr2 = obj_attrs.S_EXT_ATTR2 
        so_cntr_detail.ext_attr3 = obj_attrs.S_EXT_ATTR3 
        so_cntr_detail.ext_attr4 = obj_attrs.S_EXT_ATTR4 
        so_cntr_detail.ext_attr5 = obj_attrs.S_EXT_ATTR5                                                       

        nRet, so_cntr_detail = m3.CreateDataObj( strLuaDEID, so_cntr_detail )
        if ( nRet ~= 0 ) then 
            return 1, 'mobox 创建【指定出库容器货品明细】对象失败!'..so_cntr_detail
        end         
    end  
    return 0  
end

-- 根据指(so)定出库货品，创建指定出库容器和 指定出库容器明细
local function create_so_cntr_operation( strLuaDEID, station, so_no, cntr_code, to_loc, item_code, source_sys )
    local nRet, strRetInfo

    if ( source_sys == nil ) then source_sys = "" end
    -- 获取容器所在的货位
    local from_loc_code
    nRet, from_loc_code = wms_cntr.Get_Container_Loc( strLuaDEID, cntr_code )    
    if nRet ~= 0 or from_loc_code == '' then 
        return 1, "容器'"..cntr_code.."'无法获取货位！" 
    end
    local from_loc
    nRet, from_loc = wms_wh.GetLocInfo( from_loc_code )
    if ( nRet ~= 0 ) then return 1, '获取货位信息失败! '..from_loc end       

    -- 创建 指定出库容器
    local so_cntr = m3.AllocObject(strLuaDEID,"Specify_Outbound_CNTR")

    so_cntr.so_no = so_no
    so_cntr.cntr_code = cntr_code
    so_cntr.wh_code = from_loc.wh_code
    so_cntr.area_code = from_loc.area_code
    so_cntr.loc_code = from_loc.code
    so_cntr.to_loc_code = to_loc.code
    so_cntr.station = station
    nRet, so_cntr = m3.CreateDataObj( strLuaDEID, so_cntr )   
    if (nRet ~= 0) then return 1, "创建【盘点单】失败!"..so_cntr end  
    
    nRet, strRetInfo = create_so_cntr_detail( strLuaDEID, station, cntr_code, so_no, so_cntr.soc_no, item_code )
    if ( nRet ~= 0 ) then return nRet, strRetInfo end

    local operation = m3.AllocObject(strLuaDEID,"Operation")
    operation.b_state = OPERATION_STATE.BeforeStartup   -- 作业状态：待启动前
    operation.source_sys = source_sys
    operation.start_wh_code = from_loc.wh_code
    operation.start_area_code = from_loc.area_code
    operation.start_loc_code = from_loc.code

    operation.end_wh_code = to_loc.wh_code
    operation.end_area_code = to_loc.area_code
    operation.end_loc_code = to_loc.code
    operation.lock_cntr = "N"                                   -- 作业启动时不需要锁容器
    operation.cntr_code = cntr_code

    operation.op_type = OPERATION_TYPE.Outbound
    operation.op_def_name = "指定出库"
    operation.bs_type = "Specify_Outbound"
    operation.bs_no = so_no
    nRet, operation = m3.CreateDataObj( strLuaDEID, operation )
    if nRet ~= 0 then 
        return 2, '创建【作业】失败!'..operation 
    end  

    return 0
end

-- 根据容器号创建一个指定出库作业
-- @function wms_mang.Create_SOO_ByContainer
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string station 站台
-- @tparam string so_no 指定出库指令号
-- @tparam string cntr_code 容器编码
-- @tparam string to_loc_code 出库口货位编码
-- @tparam string op_def_name 作业类型名称
-- @tparam string source_sys 来源系统
-- @treturn number nRet 0表示成功，1或2表示失败
-- @treturn string 失败时返回错误信息
function wms_mang.Create_SOO_ByContainer( strLuaDEID, station, so_no, cntr_code, to_loc_code, op_def_name, source_sys )
    local nRet, strRetInfo, n

    -- step1：输入参数合法性检查
    if ( so_no == nil or so_no == '') then return 1, "so_no 必须有值!" end    
    if ( cntr_code == nil or cntr_code == '') then return 1, "cntr 必须有值!" end
    if ( to_loc_code == nil or to_loc_code == '') then return 1, "loc_code 必须有值!" end
    if ( station == nil or station == '') then return 1, "station 必须有值!" end
    if ( source_sys == nil ) then source_sys = "" end
    -- 判断目标货位是否正确
    local to_loc
    nRet, to_loc = wms_wh.GetLocInfo( to_loc_code )
    if ( nRet ~= 0 ) then return 1, '获取货位信息失败! '..to_loc end   

    -- 创建指定出库容器+容器明细+作业
    nRet, strRetInfo = create_so_cntr_operation( strLuaDEID, station, so_no, cntr_code, to_loc, "", source_sys )
    if ( nRet ~= 0 ) then 
        return nRet, strRetInfo 
    end   
    
    -- 设置 Specify_Outbound 状态为执行 N_B_STATE = 2 执行中
    strUpdateSql = "N_B_STATE = 2, N_CNTR_TOTAL = 1"
    strCondition = "S_SO_NO = '"..so_no.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Specify_Outbound", strCondition, strUpdateSql )
    if ( nRet ~= 0 ) then  
        return 2, "更新【Specify_Outbound】信息失败!"..strRetInfo
    end  
    return 0
end

-- 容器从当前绑定的货位移动到新的货位，这些容器必须已绑定货位且在INV_Detail中
-- @function wms_mang.CNTR_Move
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cntr_code 容器编码
-- @tparam string to_loc_code 目标货位编码
-- @tparam table ext_parameter 扩展参数，可包含note字段
-- @treturn number nRet 0表示成功，1或2表示失败
-- @treturn string 失败时返回错误信息
function wms_mang.CNTR_Move( strLuaDEID, cntr_code, to_loc_code, ext_parameter )
    local nRet, strRetInfo

    if lua.StrIsEmpty( cntr_code ) or lua.StrIsEmpty( to_loc_code ) then
        return 1, "wms_mang.CNTR_Move 函数输入参数不合规!"
    end

    local note
    if ext_parameter == nil then 
        note = '' 
    else
        note = ext_parameter.note or ''
    end

    -- 得到容器当前货位（担心上传上来的 start_location 和当前容器的绑定货位不一致，还是从 Loc_Container 获取比较保险）
    local cntr_cur_loc
    nRet, cntr_cur_loc = wms_cntr.Get_Container_Loc( strLuaDEID, cntr_code )
    if nRet ~= 0 or cntr_cur_loc == '' then
        return 1,"容器 '"..cntr_code.."' 没有绑定货位!"
    end

    -- 解绑原来的位置
    nRet, strRetInfo = wms_wh.Loc_Container_Unbinding( strLuaDEID, cntr_cur_loc, cntr_code, METHOD_TYPE.System, note )
    if ( nRet ~= 0 ) then 
        return 1, '货位容器绑定失败!'..strRetInfo
    end 

    -- 绑定新的货位
    nRet, strRetInfo = wms_wh.Loc_Container_Binding( strLuaDEID, to_loc_code, cntr_code, METHOD_TYPE.System, note )
    if ( nRet ~= 0 ) then 
        return 1, '货位容器绑定失败!'..strRetInfo
    end 

    -- 库存量转移
    nRet, strRetInfo = wms_inv.Move( strLuaDEID, cntr_code, cntr_cur_loc, to_loc_code, ext_parameter )
    if ( nRet ~= 0 )  then 
        return 1, "wms_inv.Move 失败! "..strRetInfo
    end     

    -- 更新容器中的位置信息
    local strCondition = "S_CODE = '"..cntr_code.."'"       
    local strSetAttr = "S_POSITION = '"..to_loc_code.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Container", strCondition, strSetAttr )
    if ( nRet ~= 0 ) then  
        return 2, "更新【容器料格】信息失败!"..strRetInfo 
    end     
    return 0
end

return wms_mang