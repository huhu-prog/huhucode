--[[
    版本：     Version 3.0
    创建日期： 2026-07-07
    修改日期:  2026-07-07
    创建人：

    WMS-Basis-Model-Version: V19.3

    名称:   wms_utility

    说明:   wms 相关的一些可重用的函数库


    更改记录:

--]]
wms_base = require("wms_base")
mobox = require("OILua_JavelinExt")
local wms_utility = {
    _version = "0.2.1"
}

-- PDA根据输入参数paramter获取外部输入的 factory wh_code area_codes 信息
-- @function wms_utility.GetFactoryWHArea
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam table parameter 输入参数，可以为空
-- @treturn int 0 成功，非0失败
-- @treturn string factory 非零为错误信息，成功时返回工厂编码
-- @treturn string wh_code 成功时返回仓库编码
-- @treturn table area_codes 成功时返回库区编码数组{"A01","A02"}
function wms_utility.GetFactoryWHArea(strLuaDEID, parameter)
    if parameter == nil then
        parameter = {}
    end
    local factory = parameter.factory or ''
    local wh_code = parameter.wh_code or ''
    local area_code = parameter.area_code or ''
    local nRet

    --参数中未有工厂时获取当前用户所在工厂
    if factory == '' then
        nRet, factory = wms_base.GetMyFactory(strLuaDEID)
        if nRet ~= 0 then
            factory = ''
        end
        if factory == '' then
            nRet, factory = wms_base.Get_sConst2("WMS_Default_Factory")
            if nRet ~= 0 then
                return 1, "系统无法获取常量'WMS_Default_Factory'"
            end
            if factory == '' then
                return 2, "无法获取工厂信息"
            end
        end
    end

    local area_codes
    if area_code ~= '' then
        area_codes = lua.split(area_code, ",")
    else
        area_codes = {}
    end
    return 0, factory, wh_code, area_codes
end

-- 清空指定编辑属性、设置聚集焦点并设置提示信息(一般用于PDA功能点)
-- @function wms_utility.ClearDlgAttr_SetFocus
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string focusId 聚集焦点的属性 必须有值
-- @tparam string clearIds 置空值的属性,多个属性用逗号隔开，如"S_CODE,S_NAME",可为空
-- @tparam string info提示的信息，可为空
-- @treturn int 0 成功，非0失败
function wms_utility.ClearDlgAttr_SetFocus(strLuaDEID, focusId, clearIds, info)
    local action_array
    if focusId == nil or focusId == '' then
        lua.Stop(strLuaDEID, "未设置聚集焦点属性")
        return 1
    end

    local focus_action = {
        action_type = "set_dlg_current_edit_attr",
        value = {
            ctrl_id = focusId,
            value = ""
        }
    }
    if clearIds ~= nil and clearIds ~= '' then
        local fieldIds     = lua.split(clearIds, ",")
        local dlgAttrValue = {}
        for n = 1, #fieldIds do
            dlgAttrValue[n] = {
                attr = fieldIds[n],
                value = "",
            }
        end
        action_array = {
            {
                action_type = "set_dlg_attr",
                value = dlgAttrValue
            },
            focus_action
        }
    else
        action_array = {
            focus_action
        }
    end

    local nRet, strRetInfo
    nRet, strRetInfo = mobox.setAction(strLuaDEID, lua.table2str(action_array))
    if nRet ~= 0 then
        lua.Stop(strLuaDEID, strRetInfo)
        return 1
    end
    if info == nil or info == '' then
        return 0
    end
    mobox.setInfo(strLuaDEID, info)
    return 0
end

return wms_utility
