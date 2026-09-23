--[[
    版本：     Version 2.1
    创建日期： 2024-7-26
    修改日期： 2026-6-18
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    说明:
        INBP -- 是 Inbound_Palletization 的缩写，即组盘的意思

    ——————————————————————————————————
    导出函数列表（共 4 个）:
    ——————————————————————————————————

    【组盘操作】
        Post_Delete_Process              — 删除组盘数据对象后的后续处理
        Get_Current_INBP                 — 根据容器号获取系统最新创建的组盘对象
        Add_INB_Pallet_Detail            — 组盘操作：在容器里加入一个货品
        Set_INBP_State_Inbound_Pending   — 设置组盘为待入库状态

    ——————————————————————————————————

    NEW:
        INB_Pallet_Loc_Bind             — 组盘与库位绑定

    更改记录:
        2024-7-26  HAN  创建
        2026-6-18        整理函数注释、规范代码格式

    AI CHECK:
        -- 20260618
--]]

wms_base = require ("wms_base")
wms_wh   = require ("wms_wh")
wms_inv  = require ("wms_inventory")

local wms_pallet = {_version = "0.2.1"}

-- 删除组盘数据对象后的后续处理
-- 如果组盘状态是"码盘中/码盘完成"直接删除并更新关联入库明细中的绑定数量
-- 如果组盘状态是"待入库"说明组盘容器已和库位数据绑定，需先解绑库位再删除
-- 如果是完成状态则直接删除，错误状态不能删除
-- @function wms_pallet.Post_Delete_Process
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table ibp_data 组盘数据对象（Inbound_Palletization）
-- @treturn number nRet 0: 成功
function wms_pallet.Post_Delete_Process( strLuaDEID, ibp_data )
end

-- 根据容器号获取系统最新创建的组盘对象
-- @function wms_pallet.Get_Current_INBP
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cntr_code 容器编码
-- @treturn number nRet 0: 成功, 1: 参数错误, 2: 查询出错
-- @treturn table|nil inb_pallet 组盘对象，nil表示不存在
function wms_pallet.Get_Current_INBP( strLuaDEID, cntr_code )
    local nRet
    local inb_pallet
    if cntr_code == nil or cntr_code == '' then 
        return 1, "Get_Current_INBP 函数中输入参数 cntr_code 必须有值!"
    end
    local strCondition = "S_CNTR_CODE = '"..cntr_code.."'"
    local strOrder = "T_CREATE Desc"

    nRet, inb_pallet = m3.GetDataObjByCondition( strLuaDEID, "Inbound_Palletization", strCondition, strOrder )
    if nRet > 1 then
        return 2, "查询【Inbound_Palletization】出错!"..inb_pallet
    end
    if nRet == 1 then
        -- 组盘对象不存在
        inb_pallet = nil
    else
        -- 如果该容器的【组盘】对象已经存在，如果状态是完成或取消
        if inb_pallet.b_state >= PALLET_STATE.Finish then
            inb_pallet = nil
        end
    end
    return 0, inb_pallet
end
--[[
    组盘操作: 在容器里加入一个货品
    重要度:   ***

    数据类:   Inbound_Palletization/组盘 INB_Pallet_Detail/组盘明细
    说明:
        首先判断是否有 Inbound_Palletization 没有需要创建，
        如果容器有 混放规则 需要生成 Container_Ext
        需要根据混放规则判断是否可以加入 INB_Pallet_Detail
    参数:
        cntr_code -- 容器编码
        cell_no -- 料格编码可以为空
        detail_item_data -- 加入的货品信息数组{ { S_CELL_NO = "", S_ITEM_CODE = "", S_UDF01 = "", ..S_UDF20 } }
        bs_type -- 业务来源类型(可以为空)
        bs_no -- 来源业务编号(可以为空)
--]]

-- 组盘操作：在容器里加入一个货品
-- 首先判断是否有 Inbound_Palletization，没有则需要创建
-- 如果容器有混放规则需要生成 Container_Ext
-- 需要根据混放规则判断是否可以加入 INB_Pallet_Detail
-- @function wms_pallet.Add_INB_Pallet_Detail
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cntr_code 容器编码
-- @tparam table detail_item_data 加入的货品信息数组
-- @tparam string bs_type 业务来源类型（可为空）
-- @tparam string bs_no 来源业务编号（可为空）
-- @tparam string bs_row_no 来源业务单行号（可以为空）
-- @treturn number nRet 0: 成功, 1: 参数/业务错误, 2: 系统错误
-- @treturn string strRetInfo 错误信息（仅当 nRet ~= 0 时有意义）
function wms_pallet.Add_INB_Pallet_Detail( strLuaDEID, cntr_code, detail_item_data, bs_type, bs_no, bs_row_no )
    local nRet, strRetInfo

    -- 输入参数合规检查
    if lua.StrIsEmpty( cntr_code ) then
        return 1, "Add_INB_Pallet_Detail 函数中 cntr_code 必须有值!"
    end
    if type( detail_item_data ) ~= "table" or detail_item_data == nil then
        return 1, "Add_INB_Pallet_Detail 函数中 detail_item_data 必须有值!"
    end
    local item_count = #detail_item_data
    if item_count == 0 then
        return 1, "Add_INB_Pallet_Detail 函数中 detail_item_data 必须有值!"
    end
    if bs_type == nil then bs_type = '' end
    if bs_no == nil then bs_no = '' end
    if bs_row_no == nil then bs_row_no = 0 end

    -- 判断该容器是否可以进行组盘, 获取最近时间的 【组盘】对象
    local inb_pallet
    local new_inb_pallet = false


    nRet, inb_pallet = wms_pallet.Get_Current_INBP( strLuaDEID, cntr_code )
    if nRet ~= 0 then
        return 2, "查询【Inbound_Palletization】出错!"..inb_pallet
    end
    if inb_pallet == nil then
        -- 组盘对象不存在
        new_inb_pallet = true
    else
        -- 如果该容器的【组盘】对象组盘已经完成就不能继续组盘
        if inb_pallet.b_state >= PALLET_STATE.PalletOK then
            return 1, "容器'"..cntr_code.."'状态不能进行组盘!"
        end
        inb_no = inb_pallet.inb_no
    end
     
    -- 获取容器对象及容器类型定义
    local cntr
    nRet, cntr = wms_cntr.GetInfo( strLuaDEID, cntr_code )
    if nRet ~= 0 then 
        return 2, "获取【容器】信息失败! " .. cntr
    end  
    if lua.StrIsEmpty( cntr.ctd_code ) then
        return 1, "容器'"..cntr.ctd_code.."'没有定义容器类型定义!"
    end

    local ctd       -- 容器类型定义
    nRet, ctd = wms_cntr.GetCTDInfo( cntr.ctd_code )
    if nRet ~= 0 then
        return 2, ctd
    end

    -- 【组盘】对象是否存在，不存在新增
    if new_inb_pallet then
        inb_pallet  = m3.AllocObject( strLuaDEID, "Inbound_Palletization" )
        if inb_pallet == nil then
            return 2, "创建[Inbound_Palletization]失败!"
        end
        inb_pallet.cntr_code = cntr_code
        nRet, inb_pallet = m3.CreateDataObj( strLuaDEID, inb_pallet )
        if nRet ~= 0 then 
            return 2, "创建[Inbound_Palletization]失败!"..inb_pallet
        end
    end

    -- 新增【组盘明细】
    local item
    local cntr_minxing_value = {}           -- 容器的混箱属性值
    local cntr_ext_data
    local mixing_attrs_count = #ctd.mixing_attrs
    if ctd.have_mixing_rule and new_inb_pallet == false then
        -- 从 Container_Ext 获取混箱属性值
        nRet, cntr_ext_data = m3.GetDataObjectByKey2( strLuaDEID, "Container_Ext", "S_CNTR_CODE", cntr_code )
        if nRet > 1 then
            return 2, "获取[Container_Ext]失败!"..cntr_ext_data
        end
        if nRet == 0 then
            for m = 1, mixing_attrs_count do
                cntr_minxing_value[ctd.mixing_attrs[m]] = cntr_ext_data[ctd.mixing_attrs[m]]
            end            
        end         
    end

    local canot_mixing, cell_no, item_code, item_state, storer, qty
    local strUpdateSql
    local data_objs, data_attrs, add_inb_pallet_detail
    local attrs_count = #INB_PALLET_DETAIL_ATTRS

    for n = 1, item_count do
        item = detail_item_data[n]
        item_code = item.S_ITEM_CODE
        item_state = item.S_ITEM_STATE
        storer = item.S_STORER
        qty = lua.Get_NumAttrValue( item.F_QTY )
        add_inb_pallet_detail = false               -- 是否新增 INB_Pallet_Detail

        if item_code == '' or item_state == '' or storer == '' then
            return 1, "Add_INB_Pallet_Detail 函数中 item_list 中参数不全: 物料/货品编码，货品状态，货主必须有值!"
        end
        if qty <= 0 then
            return 1, "Add_INB_Pallet_Detail 函数中 item_list 中参数不全: F_QTY 必须大于 0!"
        end
        -- 如果存在混箱规则需要判断是否符合混箱要求
        -- 获取加入货品的混箱属性，这个属性必须在 detail_item_data 如果不存在就为空
        local item_minxing_value = {}
        if ctd.have_mixing_rule then
            canot_mixing = false
            for m = 1, mixing_attrs_count do
                item_minxing_value[ctd.mixing_attrs[m]] = item[ctd.mixing_attrs[m]] or ''
            end

            -- 判断容器本身是否已经存在混箱参数
            if lua.isTableEmpty(cntr_minxing_value) then
                -- 如果是新增的【组盘】第一个货品的混箱参数就是料箱的混箱参数
                cntr_minxing_value = item_minxing_value

                -- 同时增加 Container_Ext
                local cntr_ext_data = m3.AllocObject2( strLuaDEID, "Container_Ext" )
                cntr_ext_data.S_CNTR_CODE  = cntr_code 
                for m = 1, mixing_attrs_count do
                    cntr_ext_data[ctd.mixing_attrs[m]] = item_minxing_value[ctd.mixing_attrs[m]]
                end
                nRet, cntr_ext_data = m3.CreateDataObj2( strLuaDEID, cntr_ext_data, 1 )
                if nRet ~= 0 then 
                    return 2, "创建[Container_Ext]失败!"..cntr_ext_data
                end                
            else
                -- 判断新增组盘货品的混箱参数和料箱是否匹配
                for m = 1, mixing_attrs_count do
                    if item_minxing_value[ctd.mixing_attrs[m]] ~= cntr_minxing_value[ctd.mixing_attrs[m]] then
                        canot_mixing = true
                        break
                    end
                end
            end

            -- 判断后 不能混箱
            if canot_mixing then
                return 1, "编码'"..item_code.."'的物料/货品不能加入编号='"..cntr_code.."', 原因是不符合混箱规则!"
            end
        end

        -- 如果是带料格的料箱，需要进行料格判断，是否可以进行组盘 
        local strCondition
        if ctd.type == "Cell_Box" then
            -- 判断一下当前货品的料格是否已经存在 INB_Pallet_Detail
            cell_no = item.S_CELL_NO or ''
            if cell_no == '' then
                return 1, "编码'"..item_code.."'的物料/货品不能加入编号='"..cntr_code.."', 原因是不符合混箱规则!"
            end                
            -- 允许加入料格 必须 S_ITEM_CODE, S_ITEM_STATE, S_STORER 一样，如果料箱有定义 S_MERGE_ATTRS/附加数量合并属性
            strCondition = "S_IBP_NO = '"..inb_pallet.ibp_no.."' AND S_CNTR_CODE = '"..cntr_code.."' AND S_CELL_NO = '"..cell_no.."'"  
            nRet, data_objs = m3.QueryDataObject(strLuaDEID, "INB_Pallet_Detail", strCondition )
            if nRet ~= 0 then
                return 2, "查询[INB_Pallet_Detail]失败! "..data_objs
            end
            
            -- 如果 cell_no 料格已经有货品存在
            if data_objs ~= '' then
                -- 判断 S_ITEM_CODE, S_ITEM_STATE, S_STORER + ctd.cell_match_rule_attrs 是否一致，如果不一样表示输入参数有问题，不应该绑定在这个料格
                data_attrs = m3.KeyValueAttrsToObjAttr(data_objs[1].attrs)
                if data_attrs == nil then
                    return 1, "KeyValueAttrsToObjAttr 失败!"
                end
                if data_attrs.S_ITEM_CODE ~= item_code or
                     data_attrs.S_ITEM_STATE ~= item_state or
                     data_attrs.S_STORER ~= storer then
                    return 1, "容器编码'"..cntr_code.."'的料格'"..cell_no.."'已经绑定了其它标识的货品, 请仔细检查一下该料格的货品再进行组盘!"
                end
                for m = 1, #ctd.si_match_attrs do
                    if data_attrs[ctd.si_match_attrs[m]] ~= item[ctd.si_match_attrs[m]] then
                        return 1, "容器编码'"..cntr_code.."'的料格'"..cell_no.."'已经绑定了其它标识的货品, 请仔细检查一下该料格的货品再进行组盘!"
                    end
                end

                -- 继续判断是否可以合并数量, 如果可以合并，不需要新增 INB_Pallet_Detail
                if #ctd.merge_attrs == 0 then
                    -- 不需要合并数量
                    add_inb_pallet_detail = true
                else
                    -- 判断是否可以合并数量
                    local find
                    add_inb_pallet_detail = true
                    for i = 1, #data_objs do
                        data_attrs = m3.KeyValueAttrsToObjAttr(data_objs[i].attrs)
                        if data_attrs == nil then
                            return 1, "KeyValueAttrsToObjAttr 失败!"
                        end
                        if data_attrs.S_ITEM_CODE == item_code and
                             data_attrs.S_ITEM_STATE == item_state and
                             data_attrs.S_STORER == storer then
                            find = true
                            for m = 1, #ctd.merge_attrs do
                                if data_attrs[ctd.merge_attrs[m]] ~= item[ctd.merge_attrs[m]] then
                                    find = false
                                    break
                                end
                            end 
                            if find then
                                -- 更新数量
                                strCondition = "S_ID = '"..data_objs[i].id.."'"
                                strUpdateSql = "F_QTY = F_QTY + "..qty
                                nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "INB_Pallet_Detail", strCondition, strUpdateSql )
                                if nRet ~= 0 then  
                                    return 2, "更新[INB_Pallet_Detail]信息失败!"..strRetInfo 
                                end                                  
                                add_inb_pallet_detail = false
                                break
                            end      
                        end                   
                    end
                end
            else
                -- 新增 INB_Pallet_Detail
                add_inb_pallet_detail = true
            end
        else
            add_inb_pallet_detail = true
        end

        -- 新增 INB_Pallet_Detail
        if add_inb_pallet_detail then
            local detail_data = m3.AllocObject2( strLuaDEID, "INB_Pallet_Detail" )
            if detail_data == nil then
                return 1, "创建 INB_Pallet_Detail 失败!"
            end

            detail_data.S_IBP_NO = inb_pallet.ibp_no
            detail_data.S_CNTR_CODE = cntr_code

            detail_data.S_BS_TYPE = bs_type
            detail_data.S_BS_NO = bs_no
            detail_data.N_BS_ROW_NO = bs_row_no

            for m = 1, attrs_count do
                detail_data[INB_PALLET_DETAIL_ATTRS[m]] = item[INB_PALLET_DETAIL_ATTRS[m]] or ''
            end
            nRet, detail_data = m3.CreateDataObj2( strLuaDEID, detail_data ) 
            if nRet ~= 0 then 
                return 2, "创建[INB_Pallet_Detail]失败!"..detail_data
            end     
        end
    end
    return 0
end

--[[
    设置【组盘】为待入库状态
    重要度:   ***

    数据类:   Inbound_Palletization/组盘
    说明:
        -- 首先判断目前的 Inbound_Palletization 的状态是否可以设置“待入库”状态，
        -- 如果容器和货位没绑定，绑定货位
        -- 库存量表处理
    参数:
        cntr_code   -- 容器编码
        loc_code    -- 当前组盘容器需要绑定的货位，可以为空，为空的原因是容器已经和货位绑定
--]]

-- 设置组盘为待入库状态
-- 首先判断当前 Inbound_Palletization 的状态是否可以设置为"待入库"状态
-- 如果容器和货位没绑定，绑定货位
-- 库存量变更处理
-- @function wms_pallet.Set_INBP_State_Inbound_Pending
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cntr_code 容器编码
-- @tparam string loc_code 需绑定的货位编码（可为空，为空则取容器已绑定的货位）
-- @treturn number nRet 0: 成功, 1: 参数/业务错误, 2: 系统错误
-- @treturn string strRetInfo 错误信息（仅当 nRet ~= 0 时有意义）
function wms_pallet.Set_INBP_State_Inbound_Pending( strLuaDEID, cntr_code, loc_code )
    local nRet, strRetInfo
    local inb_pallet

    if loc_code == nil then loc_code = '' end

    -- 获取组盘数据对象
    nRet, inb_pallet = wms_pallet.Get_Current_INBP( strLuaDEID, cntr_code )
    if nRet ~= 0 then
        return 2, "查询【Inbound_Palletization】出错!"..inb_pallet
    end
    if inb_pallet == nil then
        -- 组盘对象不存在
        return 1, "容器'"..cntr_code.."'不存在可设置为待入库状态的组盘对象!"
    else
        -- 如果该容器的【组盘】对象组盘的状态已经是 待组盘状态 就不能再做 待组盘状态设置
        if inb_pallet.b_state >= PALLET_STATE.Inbound_Pending then
            return 1, "容器'"..cntr_code.."'状态不能再次被设置为待组盘状态!"
        end
    end

    local need_binding = true
    local str_loc_code

    -- 容器货位判断
    -- 获取容器当前绑定货位
    nRet, str_loc_code = wms_cntr.Get_Container_Loc( strLuaDEID, cntr_code )
    if nRet ~= 0 then
        return 2, "Get_Container_Loc 失败! --> "..str_loc_code
    end    
    if loc_code == '' then
        -- 没有容器需要绑定的货位
        if str_loc_code == '' then
            return 1, " Set_INBP_State_Inbound_Pending 需要输入一个绑定货位!"
        end
        loc_code = str_loc_code
        need_binding = false        -- 已经有绑定不需要继续绑定，可能在组盘前容器已经绑定了货位
    else
        if str_loc_code ~= '' then
            if loc_code ~= str_loc_code then
                return 1, "容器'"..cntr_code.."'已经和货位'"..str_loc_code.."'绑定，不能再绑定货位'"..loc_code.."'"
            end
            need_binding = false
        end
    end

    -- 绑定货位
    if need_binding then
        nRet, strRetInfo = wms_wh.Loc_Container_Binding( strLuaDEID, loc_code, cntr_code, "绑定解绑方法-系统", "组盘绑定" )
        if nRet ~= 0 then  
            return nRet, '货位容器绑定失败!'..strRetInfo
        end         
    end

    -- 库存量变变化
    nRet, strRetInfo = wms_inv.After_CntrLoc_Binding( strLuaDEID, inb_pallet, loc_code )
    if nRet ~= 0 then
        return nRet, strRetInfo
    end

    -- 设置【组盘】状态为 待入库
    local strUpdateSql = "N_B_STATE = "..PALLET_STATE.Inbound_Pending
    local strCondition = "S_IBP_NO = '"..inb_pallet.ibp_no.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Inbound_Palletization", strCondition, strUpdateSql )
    if nRet ~= 0 then  
        return 2, "更新[Inbound_Palletization]信息失败!"..strRetInfo 
    end   

    return 0
end

-- 组盘容器和库位进行绑定
-- @function wms_pallet.INB_Pallet_Loc_Bind
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cntr_code 容器编码
-- @tparam string loc_code 需绑定的货位编码,必须有值
-- @tparam string method_type 绑定解绑方法类型,默认 Manual
-- @tparam string method_name 绑定解绑方法名称,默认 手工绑定
-- @treturn number nRet 0: 成功, 1: 参数/业务错误, 2: 系统错误
-- @treturn string strRetInfo 错误信息（仅当 nRet ~= 0 时有意义）
function wms_pallet.INB_Pallet_Loc_Bind( strLuaDEID, cntr_code, loc_code, method_type, method_name)
    if loc_code == nil or loc_code == '' then
        return 2, "库位编码不能为空!" 
    end    
    if cntr_code == nil or cntr_code == '' then
        return 2, "容器编码不能为空!" 
    end
    if method_type == nil or method_type == '' then
        method_type = METHOD_TYPE.Manual
    end
    if method_name == nil or method_name == '' then
        method_name = "手工绑定"
    end
    local nRet, have_inv = wms_inv.INV_Detail_Exist( strLuaDEID, cntr_code )
    if nRet ~= 0 then
        return 2, "wms_inv.INV_Detail_Exist 失败!"..have_inv
    end
    if have_inv then
        return 1, "容器'"..cntr_code.."'已经有库存量不能进行绑定!" 
    end    

    -- 判断是否存在 码盘 Inbound_Palletization
    local inb_pallet
    nRet, inb_pallet = wms_pallet.Get_Current_INBP( strLuaDEID, cntr_code )
    if nRet ~= 0 or inb_pallet == nil then
        return 2, "查询【Inbound_Palletization】出错!"..inb_pallet
    end
    if inb_pallet.b_state ~= INB_PALLET_STATE.PalletFinish  then
        return 1, "容器'"..cntr_code.."'在码盘中只有码盘完成的容器才能绑定!"
    end

    local strRetInfo
    nRet, strRetInfo = wms_wh.Loc_Container_Binding( strLuaDEID, loc_code, cntr_code, method_type, method_name )
    if nRet ~= 0 then 
        return 2, '货位容器绑定失败!'..strRetInfo
    end   

    -- 库存量变变化
    nRet, strRetInfo = wms_inv.After_CntrLoc_Binding( strLuaDEID, inb_pallet, loc_code )
    if nRet ~= 0 then
        return 2, 'After_CntrLoc_Binding 失败!'..strRetInfo
    end

    -- 设置【码盘】状态为 待入库
    local strUpdateSql = "N_B_STATE = "..PALLET_STATE.Inbound_Pending
    local strCondition = "S_IBP_NO = '"..inb_pallet.ibp_no.."'"
    nRet, strRetInfo = mobox.updateDataAttrByCondition( strLuaDEID, "Inbound_Palletization", strCondition, strUpdateSql )
    if nRet ~= 0 then
        return 2, 'updateDataAttrByCondition 失败!'..strRetInfo
    end   
    return 0

end

return wms_pallet