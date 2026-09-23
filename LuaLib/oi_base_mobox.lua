--[[
    版本：     Version 3.0
    创建日期： 2021-9-3
    修改日期： 2026-6-15
    创建人：   HAN

    功能:
        一些常用的和数据处理相关 Lua 函数

    ==============================================================================
    函数索引：
    ==============================================================================

    【 数据转换类】
    m3.KeyValueAttrsToObjAttr        把 [{"attr":"a1","value":"xxx"},..] 转成 {"a1":"xxx","b1":"xxx"}
    m3.KeyValueAttrsToObjAttr2       键值对转化为Json属性值对象（多表联查时点号替换为下划线）
    m3.ObjAttrToObjJson              把属性字符串 [{"attr":"xx","value":"1"},...] 转成字段格式Json
    m3.ObjAttrStrToLuaObj            把属性字符串 [{"attr":"xx","value":"1"},...] 转成Lua属性Json对象
    m3.AttrValueStrToLuaJson         把属性字符串转成Lua属性格式的table对象
    m3.objJsonToLuaJson              把数据字段格式table转化为Lua属性格式table{S_ITEM_CODE->item_code}

    【 系统参数获取类】
    m3.GetSysDataJson                获取Lua环境中的DataJson并转成Json对象
    m3.GetSysGloablAttr              获取Lua环境中的全局变量并转成Json对象
    m3.GetSysInputParameter          获取外部输入参数并转成table对象
    m3.GetRuntimeParam               获取当前运行时参数
    m3.GetRuntimePanel_InputParamter 获取运行时参数中指定面板的输入参数
    m3.Get_3053_PanelParameter       找到3053某一个面板的参数
    m3.GetMyFactory                  获取当前登录人员所属单位标识/编码
    m3.PrintLuaDEInfo                获取Lua数据交换区所有参数（用于调试）
    m3._GetFuncPointAttrs            获取功能点页面参数

    【 编辑对象操作类】
    m3.GetSysCurEditDataAttrs        获取当前编辑对象属性 [{"attr":"a1","value":"xxx"},..]
    m3.GetSysCurEditDataOneAttr      获取当前编辑对象属性中某一个属性值(字符串)
    m3.GetSysCurEditDataObj          获取当前编辑对象属性转成Lua属性Json对象
    m3.GetSysCurEditDataObj2         获取当前编辑对象属性转成字段名Json对象(attr为字段名)
    m3.GetSysCurEditOldDataObj       获取当前编辑对象变化前的属性Json对象
    m3.GetCurEditDataObj             获取当前编辑对象的属性和ID

    【 数据对象查询类】
    m3.QueryDataObject               查询数据对象（返回Lua属性）
    m3.QueryDataObject3              查询数据对象（分页版本，可指定条数）
    m3.QueryDataObjAttr2             分页查询数据对象
    m3.GetDataObjectByKey            通过关键字段获取数据对象（返回Lua属性）
    m3.GetDataObjectByKey2           通过关键字段获取数据对象（返回数据字段）
    m3.GetDataObject                 根据cls+obj_id获取对象属性（返回Lua属性）
    m3.GetDataObject2                根据cls+obj_id获取对象属性（返回数据字段）
    m3.GetDataObjByCondition         根据查询条件获取一条数据对象（返回Lua属性）
    m3.GetDataObjByCondition2        根据查询条件获取一条数据对象（返回数据字段）
    m3.GetDataFromCache              从内存缓存获取数据对象属性
    m3.ExistThisDataObject           是否存在关键字段=XX的数据对象
    m3.ExistThisDataByCondition      是否存在符合条件的数据对象

    【 数据对象创建/修改类】
    m3.AllocObject                   生成初始状态的数据类对象（Lua属性）
    m3.AllocObject2                  生成初始状态的数据类对象（字段名格式）
    m3.CreateDataObj                 创建数据对象（输入Lua属性table）
    m3.CreateDataObj2                创建数据对象（输入数据字段table）
    m3.CreateDataObj3                创建数据对象
    m3.SetDataObject                 根据cls+id设置数据表记录
    m3.SysInputParamToDataObj        获取外部输入参数并返回某数据类的属性键值对

    【 工作流/脚本类】
    m3.AddSysWFP                     新增一个后台处理脚本
    m3.RunScript                     在Lua程序里执行Lua脚本

    【 导出/接口类】
    m3.OI_DataObject_Export          导出满足条件的数据对象到文件
    m3.EPI_Return                    动态可编程接口返回函数

    【其它】
    m3.GetExtFunction                取外部Lua函数名称和module名称

    ---
    GetDataObjCount                 获取满足条件的数据对象数量

    变更记录:
    
    AI CHECK:
        -- 20260616 HAN
--]]

lua   = require ("oi_base_func")
mobox = require ("OILua_JavelinExt")

-- 多语言
package.path = package.path .. ";./locales/?.lua"
local i18n = require("i18n")
-- 创建实例
I18N = i18n.new("en")
-- 预加载语言
I18N:preload_languages({"en", "zh"})
-- 切换到中, 这里以后要改进一下从服务器获取当前的服务是支持什么语言？
I18N:set_language("zh")

local m3 = {_version = "0.1.1"} -- 定义一个空表，用于存储模块的函数和变量

-- 把 [{"attr":"a1","value":"xxx"},..] 的json对象转成 {"a1":"xxx","b1":"xxx"}
-- @function m3.KeyValueAttrsToObjAttr
-- @tparam table attrs 键值对数组 [{"attr":"attrName","value":"attrValue"},...]
-- @treturn table|nil 转换后的对象 {"attrName":"attrValue",...}，失败或空数组时返回 nil
function m3.KeyValueAttrsToObjAttr( attrs )
    local nCount

    if type(attrs) ~= "table" then
        return nil
    end
    nCount = #attrs
    local objattr = {}

    if nCount == 0 then
        return nil
    end
    for n = 1, nCount do
        if attrs[n].attr ~= '' then
            objattr[attrs[n].attr] = attrs[n].value
        end
    end
    return objattr
end

-- 导出数据类标识 = cls_id 条件满足 condition 的数据对象到文件 fn 中，导出的数据集的顺序为 order
-- @function m3.OI_DataObject_Export
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam userdata fn 文件IO对象，不能为空
-- @tparam string cls_id 数据类标识，不能为空
-- @tparam string condition 查询条件，可选
-- @tparam string order 排序字段，可选
-- @treturn number 0表示成功，非0表示错误码
-- @treturn string|nil 错误信息，成功时 nil
function m3.OI_DataObject_Export( strLuaDEID, fn, cls_id, condition, order )
    local nRet, strRetInfo

    if fn == nil then
        return 1, "OI_DataObject_Export 中参数 file_io 不能为空"
    end
    if cls_id == nil or cls_id == '' then
        return 1, "OI_DataObject_Export 中参数 cls_id不能为空"
    end
    if condition == nil then condition = '' end
    if order == nil then order = '' end

    -- 获取数据对象数量大于1000因此采用 queryDataObjAttr2      
    nRet, strRetInfo = mobox.queryDataObjAttr2( strLuaDEID, cls_id, condition, order, 100 )
    if nRet ~= 0 then
        return 2, "queryDataObjAttr2: "..strRetInfo
    end
    if strRetInfo == '' then
        return 0
    end

    local success, queryInfo
    success, queryInfo = pcall( json.decode, strRetInfo )
    if success == false then
        return 2, "queryDataObjAttr2 返回非法的JSON字符串!"
    end

    local nPageCount = queryInfo.pageCount
    local nPage = 1
    local dataSet = queryInfo.dataSet       -- 查询出来的数据集
    local obj_attrs

    while (nPage <= nPageCount) do
        for i = 1, #dataSet do
            obj_attrs = m3.KeyValueAttrsToObjAttr(dataSet[i].attrs)  
            if obj_attrs == nil then
                return 2, "KeyValueAttrsToObjAttr 失败!"
            end
            obj_attrs.cls_id = cls_id
            obj_attrs.obj_id = dataSet[i].id
            fn:write( lua.table2str(obj_attrs).."\n" )          
        end

        nPage = nPage + 1
        if nPage <= nPageCount then
            -- 取下一页
            nRet, strRetInfo = mobox.queryDataObjAttr2( strLuaDEID, nPage)
            if nRet ~= 0 then
                return 2, "queryDataObjAttr2失败! nPage="..nPage.."  "..strRetInfo
            end 

            success, queryInfo = pcall( json.decode, strRetInfo )  
            if not success then
                return 2, "queryDataObjAttr2 返回非法的JSON字符串!"
            end
            dataSet = queryInfo.dataSet 
        end
    end  
    return 0        
end

-- 获取当前Lua环境中的DataJson，并且转换成Json对象
-- @function m3.GetSysDataJson
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为解析后的Json对象，失败时为错误信息
function m3.GetSysDataJson( strLuaDEID )
    local nRet, strDataJson

    nRet, strDataJson = mobox.getCurEditDataPacket( strLuaDEID )
    if nRet ~= 0 then
        return nRet, "无法获取Lua数据包!"..strDataJson
    end  
    if strDataJson == '' then
        return 2, "Lua数据包为空!"
    end
    local jsonObj, success
    success, jsonObj = pcall( json.decode, strDataJson)
    if success == false then
        return 2, "Lua数据包的JSON格式非法! 原因:"..jsonObj..'  --> '..strDataJson
    end
    return 0, jsonObj
end

-- 获取当前Lua环境中的全局变量，并且转换成Json对象
-- @function m3.GetSysGloablAttr
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为解析后的全局属性Json对象，失败或为空时为错误信息
function m3.GetSysGloablAttr( strLuaDEID )
    local nRet, strGlobalAttr
    nRet, strGlobalAttr = mobox.getGlobalAttr2( strLuaDEID )
    if nRet ~=0 then
        return 2, "无法获取Lua中的全局变量!"
    end
    if strGlobalAttr == '' then
        return 0, ""
    end
    local global_attr, success
    success, global_attr = pcall( json.decode, strGlobalAttr)
    if success == false then
        return 2, "Lua数据包的JSON格式非法! 原因:"..global_attr..'  --> '..strGlobalAttr
    end
    return 0, global_attr
end

-- 获取外部输入的参数，并且把参数转化成一个table对象
-- 返回的参数格式为 {attrs = {"attr":"a1","value":"xxx"}, id = '', parameter = {x1=1,y1=2}}
-- @function m3.GetSysInputParameter
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为解析后的输入参数Json对象，失败或为空时返回错误信息
function m3.GetSysInputParameter( strLuaDEID )
    local nRet, strRetInfo
    nRet, strRetInfo = mobox.getInputParameter2(strLuaDEID)
    if nRet ~= 0 then
        return nRet, "getInputParameter2 失败!"
    end
    if strRetInfo == '' then
        return 0, ""
    end
    local attrs, success
    success, attrs = pcall( json.decode, strRetInfo )
    if success == false then
        return 1, "外部输入参数的Json格式非法!"..strRetInfo
    end
    return 0, attrs
end

-- 获取当前运行时参数
-- @function m3.GetRuntimeParam
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为解析后的运行环境参数，失败或为空时返回错误信息
function m3.GetRuntimeParam( strLuaDEID )
   local nRet, strRetInfo

   nRet, strRetInfo = mobox.getCurEditExtInfo(strLuaDEID)
    if nRet ~= 0 then
       return nRet, "getCurEditExtInfo 失败!"
   end
    if strRetInfo == '' then
       return 0, ""
   end
   local attrs, success
   success, attrs = pcall( json.decode, strRetInfo )
    if success == false then
       return 1, "运行环境参数的Json格式非法!"..strRetInfo
   end
   return 0, attrs
end

-- 获取当前运行时参数中的面板输入参数
-- 根据运行时参数中的 panel 属性，获取名为 panel_name 的面板的输入参数
-- @function m3.GetRuntimePanel_InputParamter
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table panel 运行时环境参数中的面板列表，必须是table类型
-- @tparam string panel_name 面板名称，必须是字符串
-- @treturn number 0表示找到，1表示不存在，2表示错误
-- @treturn table|string 成功时为面板输入参数，失败时为错误信息
function m3.GetRuntimePanel_InputParamter( strLuaDEID, panel, panel_name )
    if panel == nil or type(panel) ~= "table" then
       return 2, "GetRuntimePanel_InputParamter 函数的输入参数错误， panel 必须有值而且必须是 table 对象!"
   end

    if panel_name == nil or type(panel_name) ~= "string" then
       return 2, "GetRuntimePanel_InputParamter 函数的输入参数错误， panel_name 必须有值而且必须是字符串!"
   end    

    for n = 1, #panel do
        if panel[n].panel_name == panel_name then
           return 0, panel[n].input_parameter
       end
   end
   return 1, "运行时环境参数中不存在名为 '"..panel_name.."'的面板输入参数!"
end


-- 获取外部输入的参数，并且返回某个数据类的属性键值对 [{"attr":"a1","value":"xxx"},..]
-- @function m3.SysInputParamToDataObj
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strClsID 数据类标识，不能为空
-- @treturn number 0表示成功，1表示错误
-- @treturn table|string 成功时为转换后的Lua对象，失败时为错误信息
function m3.SysInputParamToDataObj( strLuaDEID, strClsID )
   local nRet, strRetInfo

    if strClsID == nil or strClsID == '' then 
        return 1, "SysInputParamToDataObj 函数中 strClsID 不能为空或nil!" 
    end

    nRet, strRetInfo = mobox.getInputParameter2(strLuaDEID)
    if nRet ~= 0 then
        return 1, "getInputParameter2 失败!"
    end
    -- 把 [{"attr":"xxx","value":""},...] 转换成 json object
    local strObjJson
    nRet, strObjJson = mobox.objAttrsToLuaJson( strClsID, strRetInfo )
    if nRet ~= 0 or strObjJson == '' then 
        return 1, "objAttrsToLuaJson 转 "..strClsID.." 失败! "..strObjJson 
    end
    local success
    local luaObj
    success, luaObj = pcall( json.decode, strObjJson )
    if success == false then 
        return 1, "objAttrsToLuaJson 转 "..strClsID.." 返回的的JSON格式不合法 !"..luaObj  
    end

   return 0, luaObj
end

-- 找到3053某一个面板的参数
-- @function m3.Get_3053_PanelParameter
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string panel_name 面板名称
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为面板参数table，失败时为错误信息
function m3.Get_3053_PanelParameter( strLuaDEID, panel_name )
    local nRet, runtime_parameter
    
    nRet, runtime_parameter = m3.GetRuntimeParam(strLuaDEID)
    if nRet ~= 0 or runtime_parameter == '' then 
        return 2, "GetRuntimeParam失败! "..runtime_parameter 
    end    
    local parameter
    nRet, parameter = m3.GetRuntimePanel_InputParamter( strLuaDEID, runtime_parameter.panel, panel_name )
    if nRet ~= 0 or parameter == nil then 
        -- 如果获取不到，则从外部输入的参数中获取
        local input_parameter
        nRet, input_parameter = m3.GetSysInputParameter( strLuaDEID ) 

        if nRet ~= 0 then 
            return 1, "m3.GetSysInputParameter 失败! "..input_parameter
        end
        if input_parameter == '' then
            return 1, "没有定义'"..panel_name.."'面板参数!"
        end
        parameter = nil
        for _, p in ipairs( input_parameter ) do
            if p.panel_name == panel_name then
                parameter = p.input_parameter
                break
            end
        end
        if parameter == nil then
            return 1, "没有定义'"..panel_name.."'面板参数!"
        end
    end

    return 0, parameter
end

-- 键值对转化为Json属性值对象
-- 和KeyValueAttrsToObjAttr不同的时，这个函数一般用在多表联查时返回的查询结果的处理上，多表查询返回时属性上会带a.如a.S_ITEM_CODE
-- 通过这个函数会转成  {a_S_ITEM_CODE ="xxx"}
-- @function m3.KeyValueAttrsToObjAttr2
-- @tparam table attrs 键值对数组 [{"attr":"attrName","value":"attrValue"},...]
-- @treturn table|nil 转换后的对象，点号替换为下划线，失败或空时返回 nil
function m3.KeyValueAttrsToObjAttr2( attrs )
   local nCount

    if type(attrs) ~= "table" then
       return nil
   end
   nCount = #attrs
   local objattr = {}
   local attr
   
    if nCount == 0 then
       return nil
   end
    for n = 1, nCount do
        if attrs[n].attr ~= '' then
         attr = attrs[n].attr
         attr = string.gsub( attr,"%.","_")
         objattr[attr] = attrs[n].value
       end
   end
   return objattr
end

-- 获取当前Lua数据交换区里的当前编辑对象属性，并且把参数转化成 [{"attr":"a1","value":"xxx"},..]一个table
-- 如：{"a1":xxx,"b1":"xxx"}
-- @function m3.GetSysCurEditDataAttrs
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为对象属性键值对table，失败时为错误信息
function m3.GetSysCurEditDataAttrs(strLuaDEID)
    local nRet, strRetInfo

    nRet, strRetInfo = mobox.getCurEditDataObjAttr(strLuaDEID)
    if nRet ~= 0 then
        return nRet, "getCurEditDataObjAttr 失败! "
    end
    if strRetInfo == '' then 
        return 0, {}
    end
    local attrs, success
    success, attrs = pcall( json.decode, strRetInfo )
    if success == false then
        return 2, "当前编辑数据对象属性的Json格式非法!"..strRetInfo
    end
    local obj_attrs = m3.KeyValueAttrsToObjAttr(attrs)
    if obj_attrs == nil then
        obj_attrs = {}
    end
    return 0, obj_attrs
end

-- 获取当前Lua数据交换区里的当前编辑对象属性中的一个名为 attr_name 的属性值，返回一个字符串值
-- @function m3.GetSysCurEditDataOneAttr
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string attr_name 属性名称
-- @treturn number 0表示成功，非0表示错误码
-- @treturn string 成功时为属性值字符串，失败时为错误信息
function m3.GetSysCurEditDataOneAttr(strLuaDEID, attr_name )
    local nRet, strRetInfo
    nRet, strRetInfo = mobox.getCurEditDataObjAttr( strLuaDEID, attr_name )
    if nRet ~= 0 or strRetInfo == '' then
        return 2, "无法获取当前编辑对象中的名为'"..attr_name.."'的值!"
    end

    local success, retAttrs = pcall( json.decode, strRetInfo )
    if not success then
        return 2, "无法获取当前编辑对象中的名为'"..attr_name.."'的值!"
    end
    return 0, retAttrs[1].value
end

-- 获取当前Lua数据交换区里的当前编辑对象属性，并且把参数转化成 Json 对象
-- 注意返回的是Json对象
-- @function m3.GetSysCurEditDataObj
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strClsID 数据类标识
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为包含id/cls的数据对象Json对象，失败时为错误信息
function m3.GetSysCurEditDataObj( strLuaDEID, strClsID )
    local nRet, strRetInfo, strErr

    strErr = ''
    if strClsID == nil or strClsID == '' then 
        return 2,"GetSysCurEditDataObj 函数中 strClsID 不能为空或nil!"
    end
    strClsID = lua.trim(strClsID)

    nRet, strRetInfo = mobox.getCurEditDataObjAttr( strLuaDEID )
    if nRet ~= 0 or strRetInfo == '' then
        strErr = "GetSysCurEditDataObj 失败!"..strRetInfo
        return 2, strErr
    end
    local strObjJson
    nRet, strObjJson = mobox.objAttrsToLuaJson( strClsID, strRetInfo )
    if nRet ~= 0 then
        strErr = "objAttrsToLuaJson 失败! 数据类标识 = "..strClsID.." 原因:"..strObjJson
        return 2, strErr
    end

    local obj, success
    success, obj = pcall( json.decode, strObjJson )
    if success == false then
        strErr = "objAttrsToLuaJson 返回的的JSON格式不合法 ! 数据类标识 = "..strClsID.." 原因:"..obj
        return 2, strErr
    end

    local strClsID1, strObjID
    nRet, strClsID1, strObjID = mobox.getCurEditDataObjID( strLuaDEID )
    if nRet == 0 then
        obj.id = strObjID
        obj.cls = strClsID
        return 0, obj
    end
    return nRet, strClsID1
end


-- 获取当前Lua数据交换区里的当前编辑对象属性，并且把参数转化属性是字段名的 Json 对象
-- 注意返回的是Json对象
-- @function m3.GetSysCurEditDataObj2
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strClsID 数据类标识
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为包含id/cls的数据对象Json对象(attr为字段名)，失败时为错误信息
function m3.GetSysCurEditDataObj2( strLuaDEID, strClsID )
    local nRet, strRetInfo, strErr

    strErr = ''
    if strClsID == nil or strClsID == '' then 
        return 2,"GetSysCurEditDataObj2 函数中 strClsID 不能为空或nil!"
    end
    strClsID = lua.trim(strClsID)

    nRet, strRetInfo = mobox.getCurEditDataObjAttr( strLuaDEID )
    if nRet ~= 0 or strRetInfo == '' then
        strErr = "GetSysCurEditDataObj2 失败!"..strRetInfo
        return 2, strErr
    end
    local strObjJson
    nRet, strObjJson = mobox.objAttrToObjJson( strClsID, strRetInfo )
    if nRet ~= 0 then
        strErr = "objAttrToObjJson 失败! 数据类标识 = "..strClsID.." 原因:"..strObjJson
        return 2, strErr
    end

    local obj, success
    success, obj = pcall( json.decode, strObjJson )
    if not success then
        strErr = "objAttrToObjJson 返回的的JSON格式不合法 ! 数据类标识 = "..strClsID.." 原因:"..obj
        return 2, strErr
    end

    local strClsID1, strObjID
    nRet, strClsID1, strObjID = mobox.getCurEditDataObjID( strLuaDEID )
    if nRet == 0 then
        obj.id = strObjID
        obj.cls = strClsID
        return 0, obj
    end
    return nRet, strClsID1

end

-- 获取当前Lua数据交换区里的当前编辑对象属性在变化前的属性，并且把参数转化成 Json 对象
-- @function m3.GetSysCurEditOldDataObj
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strClsID 数据类标识
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为变化前的数据对象Json对象，失败时为错误信息
function m3.GetSysCurEditOldDataObj( strLuaDEID, strClsID )
   local nRet, strRetInfo, strErr

   strErr = ''
   if strClsID == nil or strClsID == '' then 
       return 2,"GetSysCurEditOldDataObj 函数中 strClsID 不能为空或nil!"
   end
   strClsID = lua.trim(strClsID)

   nRet, strRetInfo = mobox.getCurEditOldDataObjAttr( strLuaDEID )
    if nRet ~= 0 or strRetInfo == '' then
       strErr = "GetSysCurEditOldDataObj 失败!"..strRetInfo
       return 2, strErr
   end
   local strObjJson
   nRet, strObjJson = mobox.objAttrToObjJson( strClsID, strRetInfo )
    if nRet ~= 0 then
       strErr = "objAttrToObjJson 失败! 数据类标识 = "..strClsID.." 原因:"..strObjJson
       return 2, strErr
   end

   local obj, success
   success, obj = pcall( json.decode, strObjJson )
    if success == false then
       strErr = "objAttrToObjJson 返回的的JSON格式不合法 ! 数据类标识 = "..strClsID.." 原因:"..obj
       return 2, strErr
   end

   return 0, obj
end

-- 获取当前登录人员所属单位标识/编码
-- @function m3.GetMyFactory
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number 0表示成功，非0表示错误码
-- @treturn string 成功时为单位编码(company_code)，失败时为错误信息
function m3.GetMyFactory( strLuaDEID )
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
       local success, orgInfo = pcall( json.decode, strRetInfo )
        if not success then
           return 2, "获取当前操作人员所属工厂失败! "..strRetInfo 
       end
       factory = orgInfo.company_code
    end
    return 0, factory
end

-- 自动生成一个初始状态的数据类对象
-- 创建数据对象前，调用该函数
-- @function m3.AllocObject
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strClsID 数据类标识
-- @treturn table|nil 成功时为分配的数据对象(含lua属性字段)，失败时返回 nil
function m3.AllocObject( strLuaDEID, strClsID )
   local nRet, strJson

   if strClsID == nil or strClsID == '' then 
       return nil
   end
   strClsID = lua.trim(strClsID)
   nRet, strJson = mobox.allocObject(strClsID)
    if nRet ~= 0 then
       lua.Warning( strLuaDEID, debug.getinfo(1), "allocObject失败:"..strJson )
       return nil
   end

   local object, success
   success, object = pcall( json.decode, strJson )
    if success == false then
       lua.Warning( strLuaDEID, debug.getinfo(1), "allocObject("..strClsID..") 返回的的JSON格式不合法!" )
       return nil
   end
   return object
end

-- 自动生成一个初始状态的数据类对象,返回的table里属性为字段名
-- @function m3.AllocObject2
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strClsID 数据类标识
-- @treturn table|nil 成功时为分配的数据对象(字段名格式)，失败时返回 nil
function m3.AllocObject2( strLuaDEID, strClsID )
    local nRet, strJson
 
    if strClsID == nil or strClsID == '' then 
       return nil
    end    
    strClsID = lua.trim(strClsID)
    nRet, strJson = mobox.allocObject2(strClsID)
    if nRet ~= 0 then
        lua.Warning( strLuaDEID, debug.getinfo(1), "allocObject2失败:"..strJson )
        return nil
    end
	
    local object_data, success
    success, object_data = pcall( json.decode, strJson )
    if success == false then
        lua.Warning( strLuaDEID, debug.getinfo(1), "allocObject2("..strClsID..") 返回的的JSON格式不合法!" )
        return nil
    end
    return object_data
 end

-- 查询数据对象
-- @function m3.QueryDataObject
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strClsID 数据类标识，不能为空
-- @tparam string strCondition 查询条件
-- @tparam string strOrder 排序，可选，不输入则默认空
-- @treturn number 非零表示错误，0 表示成功
-- @treturn table|string 成功时返回数据对象数组 [{"id":"","attrs":[{"attr":"S_CODE","value":""},...]}]，失败时返回错误信息
function m3.QueryDataObject( strLuaDEID, strClsID, strCondition, strOrder )
   local nRet, strRetInfo
   -- 参数检查
    if strClsID == nil or strClsID == '' then 
       return 1, "QueryDataObject 中 strClsID 不能为空!"
   end  
    if strCondition == nil then strCondition = "" end 
    if strOrder == nil then strOrder = '' end

   nRet, strRetInfo = mobox.queryDataObjAttr(strLuaDEID, strClsID, strCondition, strOrder)
    if nRet ~= 0 then
       return nRet, "queryDataObjAttr 发生错误!"..strRetInfo
   end

    if strRetInfo == '' then
       return 0, ""
   end

   local objects, success
   success, objects = pcall( json.decode, strRetInfo )
    if success == false then
       return 2, "queryDataObjAttr 返回的的JSON格式不合法!"
   end
   return 0, objects      
end

-- 查询数据对象（分页查询版本，可指定条数）
-- @function m3.QueryDataObject3
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strClsID 数据类标识，不能为空
-- @tparam string strCondition 查询条件，不能为空
-- @tparam string strOrder 排序，可选，不输入则默认空
-- @tparam number count 查询记录条数，默认1000
-- @treturn number 非零表示错误，0 表示成功
-- @treturn table|string 成功时返回数据对象数组 [{"id":"","attrs":[{"attr":"S_CODE","value":""},...]}]，失败时返回错误信息
function m3.QueryDataObject3( strLuaDEID, strClsID, strCondition, strOrder, count )
   local nRet, strRetInfo
   -- 参数检查
    if strClsID == nil or strClsID == '' then 
       return 1, "QueryDataObject3 中 strClsID 不能为空!"
   end  
    if strCondition == nil or strCondition == '' then 
       return 1, "QueryDataObject3 中 strCondition 不能为空!"
   end 
    if strOrder == nil then strOrder = '' end
    if count == nil or count <= 0 then count = 1000 end

   nRet, strRetInfo = mobox.queryDataObjAttr3(strLuaDEID, strClsID, strCondition, count, strOrder)
    if nRet ~= 0 then
       return nRet, "queryDataObjAttr3 发生错误!"..strRetInfo
   end

    if strRetInfo == '' then
       return 0, ""
   end

   local objects, success
   success, objects = pcall( json.decode, strRetInfo )
    if success == false then
       return 2, "queryDataObjAttr3 返回的的JSON格式不合法!"
   end
   return 0, objects      
end

-- 通过关键字段获取数据对象属性，返回的table属性为Lua属性
-- @function m3.GetDataObjectByKey
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cls_id 数据类标识，不能为空
-- @tparam string key_attr 关键字段名，不能为空
-- @tparam string key_value 关键字段值，不能为空
-- @treturn number 0成功，1表示不存在，2表示错误
-- @treturn table|string 成功时返回包含id/cls的数据对象，失败时返回错误信息
function m3.GetDataObjectByKey( strLuaDEID, cls_id, key_attr, key_value )
   -- 参数检查
    if cls_id == nil or cls_id == '' then 
       return 2, "GetDataObjectByKey 中 cls_id 不能为空!"
   end  
    if key_attr == nil or key_attr == '' then 
       return 2, "GetDataObjectByKey 中 key_attr 不能为空!"
   end             
    if key_value == nil or key_value == '' then
       return 2, "GetDataObjectByKey 中 key_value 不能为空!"
   end

   local nRet, strRetInfo, id
   local strCondition = key_attr.." = '"..string.gsub(key_value, "'", "''").."'"
   nRet, id, strRetInfo = mobox.getDataObjAttrByKeyAttr( strLuaDEID, cls_id, strCondition )

   if nRet == 1 then
      return 1, key_attr.."='"..key_value.."'的"..cls_id.."不存在!"
   end
    if nRet ~= 0 then
       return 2, "getDataObjAttrByKeyAttr 发生错误!"..id
   end

   local strJson
   nRet, strJson = mobox.objAttrsToLuaJson( cls_id, strRetInfo )
    if nRet ~= 0 then
       return 2, "objAttrsToLuaJson 失败!"..strJson
   end

   local object, success
   success, object = pcall( json.decode, strJson )
    if success == false then
       return 2, "objAttrsToLuaJson 返回的的JSON格式不合法!"
   end
   object.id = id
   object.cls = cls_id
   return 0, object
end

-- 通过关键字段获取数据对象属性，返回的table属性为数据字段
-- @function m3.GetDataObjectByKey2
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cls_id 数据类标识，不能为空
-- @tparam string key_attr 关键字段名，不能为空
-- @tparam string key_value 关键字段值，不能为空
-- @treturn number 0成功，1表示不存在，2表示错误
-- @treturn table|string 成功时返回字段格式的数据对象，失败时返回错误信息
function m3.GetDataObjectByKey2( strLuaDEID, cls_id, key_attr, key_value )
    -- 参数检查
    if cls_id == nil or cls_id == '' then 
        return 2, "GetDataObjectByKey2 中 cls_id 不能为空!"
    end  
    if key_attr == nil or key_attr == '' then 
        return 2, "GetDataObjectByKey2 中 key_attr 不能为空!"
    end             
    if key_value == nil or key_value == '' then
        return 2, "GetDataObjectByKey2 中 key_value 不能为空!"
    end
 
    local nRet, strRetInfo, id
    local strCondition = key_attr.." = '"..string.gsub(key_value, "'", "''").."'"
    nRet, id, strRetInfo = mobox.getDataObjAttrByKeyAttr( strLuaDEID, cls_id, strCondition )
 
    if nRet == 1 then
        return 1, key_attr.."='"..key_value.."'的"..cls_id.."不存在!"
    end
    if nRet ~= 0 then
        return 2, "getDataObjAttrByKeyAttr 发生错误!"..id
    end
 
    local strJson
    nRet, strJson = mobox.objAttrToObjJson( cls_id, strRetInfo )
    if nRet ~= 0 then
        return 2, "objAttrToObjJson 失败!"..strJson
    end
 
    local object, success
    success, object = pcall( json.decode, strJson )
    if success == false then
        return 2, "objAttrToObjJson 返回的的JSON格式不合法!"
    end
    object.id = id
    object.cls = cls_id
    return 0, object
 end

-- 根据数据类标识和数据对象标识获取对象属性，返回的table属性为Lua属性
-- @function m3.GetDataObject
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cls_id 数据类标识，不能为空
-- @tparam string obj_id 数据对象标识，不能为空
-- @treturn number 0正确，1对象不存在，>1表示错误
-- @treturn table|string 成功时返回包含id/cls的数据对象，失败时返回错误信息
function m3.GetDataObject( strLuaDEID, cls_id, obj_id )
   -- 参数检查
    if cls_id == nil or cls_id == '' then 
       return 1, "GetDataObjInfo 中 cls_id 不能为空!"
   end  
    if obj_id == nil or obj_id == '' then 
       return 1, "GetDataObjInfo 中 obj_id 不能为空!"
   end             

   local nRet, strRetInfo
   nRet, strRetInfo = mobox.getDataObjAttr( strLuaDEID, cls_id, obj_id )

    if nRet == 1 then
       return 1, "ID ='"..obj_id.."'的"..cls_id.."对象不存在!"
   end
    if nRet ~= 0 then
       return 2, "getDataObjAttr 发生错误!"..strRetInfo
   end

   local strJson
   nRet, strJson = mobox.objAttrsToLuaJson( cls_id, strRetInfo )
    if nRet ~= 0 then
       return 2, "objAttrsToLuaJson 失败!"..strRetInfo
   end

   local object, success
   success, object = pcall( json.decode, strJson )
    if success == false then
       return 2, "objAttrsToLuaJson 返回的的JSON格式不合法!"
   end
   object.id = obj_id
   object.cls = cls_id
   return 0, object
end

-- 根据数据类标识和数据对象标识获取对象属性，返回table中的属性为数据字段
-- @function m3.GetDataObject2
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cls_id 数据类标识，不能为空
-- @tparam string obj_id 数据对象标识，不能为空
-- @treturn number 0正确，1对象不存在，>1表示错误
-- @treturn table|string 成功时返回字段格式的数据对象，失败时返回错误信息
function m3.GetDataObject2( strLuaDEID, cls_id, obj_id )

    -- 参数检查
    if cls_id == nil or cls_id == '' then 
        return 1, "GetDataObject2 中 cls_id 不能为空!"
    end  
    if obj_id == nil or obj_id == '' then 
        return 1, "GetDataObject2 中 obj_id 不能为空!"
    end             
 
    local nRet, strRetInfo
    nRet, strRetInfo = mobox.getDataObjAttr( strLuaDEID, cls_id, obj_id )
    if nRet == 1 then
        return 1, "ID ='"..obj_id.."'的"..cls_id.."对象不存在!"
    end
    if nRet ~= 0 then
        return 2, "getDataObjAttr 发生错误!"..strRetInfo
    end
 
    local strJson
    nRet, strJson = mobox.objAttrToObjJson( cls_id, strRetInfo )
    if nRet ~= 0 then
        return 2, "objAttrToObjJson 失败!"..strRetInfo
    end
 
    local object, success
    success, object = pcall( json.decode, strJson )
    if success == false then
        return 2, "objAttrToObjJson 返回的的JSON格式不合法!"
    end
    object.id = obj_id
    object.cls = cls_id
    return 0, object
 end

-- 根据数据类标识和数据对象属性设置数据表记录
-- @function m3.SetDataObject
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table data_obj 数据对象table，必须包含cls和id字段
-- @treturn number 0表示成功，非0表示错误码
-- @treturn string|nil 错误信息，成功时 nil
function m3.SetDataObject( strLuaDEID, data_obj )
    local nRet, strRetInfo

    if data_obj == nil or type(data_obj) ~= "table" then
        return  1, "SetDataObject 函数中的 data_obj 必须有值，必须是table类型!"
    end
    -- 参数检查
    if data_obj.cls == nil or data_obj.cls == '' then 
        return 1, "SetDataObject 中 data_obj 类型非法!"
    end  
    if data_obj.id == nil or data_obj.id == '' then 
        return 1, "SetDataObject 中 data_obj 类型非法!"
    end             
    local strAttrs
    nRet, strAttrs = mobox.luaJsonToObjAttrs( data_obj.cls, lua.table2str(data_obj))
    if nRet ~= 0 then
        return nRet, strAttrs
    end

    nRet, strRetInfo = mobox.setDataObjAttr( strLuaDEID, data_obj.cls, data_obj.id, strAttrs )
    if nRet ~= 0 then
        return 2, "setDataObjAttr 发生错误!"..strRetInfo
    end
 
    return 0
end

-- 根据查询条件获取一条数据对象属性，返回数据类定义的Lua属性
-- nRet = 0 找到记录，1 表示找不到，2 错误
-- @function m3.GetDataObjByCondition
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cls_id 数据类标识，不能为空
-- @tparam string strCondition 查询条件，不能为空
-- @tparam string strOrder 排序，可选
-- @treturn number 0找到记录，1找不到，2表示错误
-- @treturn table|string 成功时返回包含id/cls的数据对象，失败时返回错误信息
function m3.GetDataObjByCondition( strLuaDEID, cls_id, strCondition, strOrder )
   -- 参数检查
    if cls_id == nil or cls_id == '' then 
       return 2, "GetDataObjByCondition 中 cls_id 不能为空!"
   end  
    if strCondition == nil or strCondition == '' then 
       return 2, "GetDataObjByCondition 中 strCondition 不能为空!"
   end       
    if strOrder == nil then strOrder = '' end

   local nRet, strRetInfo
   nRet, strRetInfo = mobox.queryOneDataObjAttr2( strLuaDEID, cls_id, strCondition, strOrder )
    if nRet ~= 0 then
       return 2, "GetDataObjByCondition 发生错误!"..strRetInfo
   end
    if strRetInfo == '' then
       return 1, "条件："..strCondition.."的"..cls_id.."不存在!"
   end
   local ret_info, success
   success, ret_info = pcall( json.decode, strRetInfo )
    if success == false then
       return 2, "queryOneDataObjAttr2 返回的的JSON格式不合法!"
   end

   local strJson
   nRet, strJson = mobox.objAttrsToLuaJson( cls_id, lua.table2str(ret_info.attrs) )
    if nRet ~= 0 then
       return 2, "objAttrsToLuaJson 失败!"..strJson
   end

   local object
   success, object = pcall( json.decode, strJson )
    if success == false then
       return 2, "objAttrsToLuaJson 返回的的JSON格式不合法!"
   end
   object.id = ret_info.id
   object.cls = cls_id
   return 0, object
end

-- 根据查询条件获取一条数据对象属性，返回的数据对象为字段格式
-- @function m3.GetDataObjByCondition2
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cls_id 数据类标识，不能为空
-- @tparam string strCondition 查询条件，不能为空
-- @tparam string strOrder 排序，可选
-- @treturn number 0找到记录，1找不到，2表示错误
-- @treturn table|string 成功时返回字段格式的数据对象，失败时返回错误信息
function m3.GetDataObjByCondition2( strLuaDEID, cls_id, strCondition, strOrder )
    -- 参数检查
    if cls_id == nil or cls_id == '' then 
        return 2, "GetDataObjByCondition2 中 cls_id 不能为空!"
    end  
    if strCondition == nil or strCondition == '' then 
        return 2, "GetDataObjByCondition2 中 strCondition 不能为空!"
    end       
    if strOrder == nil then strOrder = '' end
 
    local nRet, strRetInfo
    nRet, strRetInfo = mobox.queryOneDataObjAttr2( strLuaDEID, cls_id, strCondition, strOrder )
    if nRet ~= 0 then
        return 2, "queryOneDataObjAttr2 发生错误!"..strRetInfo
    end
    if strRetInfo == '' then
        return 1, "条件："..strCondition.."的"..cls_id.."不存在!"
    end
    local ret_info, success
    success, ret_info = pcall( json.decode, strRetInfo )
    if success == false then
        return 2, "queryOneDataObjAttr2 返回的的JSON格式不合法!"
    end
 
    local strJson
    nRet, strJson = mobox.objAttrToObjJson( cls_id, lua.table2str(ret_info.attrs) )
    if nRet ~= 0 then
        return 2, "objAttrToObjJson 失败!"..strJson
    end
 
    local object
    success, object = pcall( json.decode, strJson )
    if success == false then
        return 2, "objAttrToObjJson 返回的的JSON格式不合法!"
    end
    object.id = ret_info.id
    object.cls = cls_id
    return 0, object
end

-- 把数据对象属性（字符串）{{"attr"="S_ITEM_CODE","value"="xxx"},..} 转成Json {S_ITEM_CODE="XX",...}
-- @function m3.ObjAttrToObjJson
-- @tparam string cls_id 数据类标识
-- @tparam string str_data_attrs 数据对象属性字符串 [{"attr":"xxx","value":"xxx"},...]
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为字段格式的数据对象，失败时为错误信息
function m3.ObjAttrToObjJson( cls_id, str_data_attrs )
    local nRet, strJson = mobox.objAttrToObjJson( cls_id, str_data_attrs )
    if nRet ~= 0 then
        return 2, "objAttrToObjJson 失败!"..strJson
    end
 
    local success, object = pcall( json.decode, strJson )
    if success == false then
        return 2, "objAttrToObjJson 返回的的JSON格式不合法!"
    end
    return 0, object
end

-- 创建一个数据对象
-- @function m3.CreateDataObj
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table dataObj 数据对象table，必须包含cls字段
-- @tparam number update_exist 是否覆盖已存在对象，0不覆盖，1覆盖，默认0
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为创建的数据对象(含id/cls)，失败时为错误信息
function m3.CreateDataObj( strLuaDEID, dataObj, update_exist )
    local nRet, strRetInfo 

    if update_exist == nil then update_exist = 0 end
    if dataObj == nil or dataObj.cls == nil or dataObj.cls == '' then
        return 2, "CreateDataObj 中的dataObj不是一个mobox数据对象!"
    end

    local attrs
    nRet, attrs = mobox.luaJsonToObjAttrs(dataObj.cls, lua.table2str(dataObj))
    if nRet ~= 0 then
        return 2, 'luaJsonToObjAttrs时失败! 数据类标识 = '..dataObj.cls..' 原因:'..attrs.." dataobj = "..lua.table2str(dataObj)
    end    

    nRet, strRetInfo = mobox.createDataObj( strLuaDEID, dataObj.cls, attrs, 1, update_exist )        -- 返回的是Lua attr
    if nRet ~= 0 then
        return nRet, 'createDataObj失败! 数据类标识 = '..dataObj.cls..' 原因:'..strRetInfo
    end

    local retInfo, success
    success, retInfo = pcall( json.decode, strRetInfo )
    if success == false then
        return 2, "createDataObj 返回的的JSON格式不合法!"..strRetInfo
    end

    local strClsID = dataObj.cls

    dataObj = retInfo.lua_attr
    dataObj.id = retInfo.id
    dataObj.cls = strClsID

    return 0, dataObj
end

-- 创建一个数据对象，输入的数据对象table属性是数据字段
-- @function m3.CreateDataObj2
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table data 数据table，必须包含cls字段
-- @tparam number update_exist 是否覆盖已存在对象，0不覆盖，1覆盖，默认0
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为创建的数据对象(含id/cls)，失败时为错误信息
function m3.CreateDataObj2( strLuaDEID, data, update_exist )
    local nRet, strRetInfo 

    if update_exist == nil then update_exist = 0 end
    if data == nil or data.cls == nil or data.cls == '' then
        return 2, "CreateDataObj2 中的输入参数 data 不合规!"
    end
   
    nRet, strRetInfo = mobox.createDataObj2( strLuaDEID, data.cls, lua.table2str(data), update_exist ) 
    if nRet ~= 0 then
        return nRet, 'createDataObj2 失败! 数据类标识 = '..data.cls..' 原因:'..strRetInfo
    end

    local retInfo, success
    success, retInfo = pcall( json.decode, strRetInfo )
    if success == false then
        return 2, "createDataObj2 返回的的JSON格式不合法!"..strRetInfo
    end
    
    local dataObj = retInfo.attrs
    dataObj.id = retInfo.id
    dataObj.cls = data.cls

    return 0, dataObj
end

-- 创建一个数据对象
-- @function m3.CreateDataObj3
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table data 数据table，必须包含cls字段
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为创建的数据对象(含id/cls)，失败时为错误信息
function m3.CreateDataObj3( strLuaDEID, data )
    local nRet, strRetInfo 

    if data == nil or data.cls == nil or data.cls == '' then
        return 2, "CreateDataObj3 中的输入参数 data 不合规!"
    end
   
    nRet, strRetInfo = mobox.createDataObj3( strLuaDEID, data.cls, lua.table2str(data) ) 
    if nRet ~= 0 then
        return nRet, 'createDataObj3 失败! 数据类标识 = '..data.cls..' 原因:'..strRetInfo
    end

    local retInfo, success
    success, retInfo = pcall( json.decode, strRetInfo )
    if success == false then
        return 2, "createDataObj3 返回的的JSON格式不合法!"..strRetInfo
    end
    
    local dataObj = retInfo.attrs
    dataObj.id = retInfo.id
    dataObj.cls = data.cls

    return 0, dataObj
end

-- 把一个[{"attr": "XXXX", "value": "XXXX" },...]字符串转成一个json对象 {"item_code":"xxx","item_name":"xxx",...}
-- @function m3.ObjAttrStrToLuaObj
-- @tparam string strClsID 数据类标识
-- @tparam string strAttrs 属性字符串 [{"attr":"xxx","value":"xxx"},...]，也可以是table格式
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为Lua属性格式的数据对象，失败时为错误信息
function m3.ObjAttrStrToLuaObj( strClsID, strAttrs )
   local nRet, strRetInfo
    if type(strAttrs) == "table" then
       strAttrs = lua.table2str( strAttrs )
   end
   nRet, strRetInfo = mobox.objAttrsToLuaJson( strClsID, strAttrs )
    if nRet ~= 0 then
       return 2, "objAttrsToLuaJson Operation 失败!"..strRetInfo
   end

   local object, success
   success, object = pcall( json.decode, strRetInfo )
    if success == false then
       return 2, "objAttrsToLuaJson('Operation') 返回的的JSON格式不合法!"
   end
   return 0, object
end

-- 是否存在关键字段=XX的数据对象，适合数据类关键字段是单个的数据类
-- KeyAttr必须是字符串类型
-- @function m3.ExistThisDataObject
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strClsID 数据类标识，不能为空
-- @tparam string strKeyAttr 关键字段名，不能为空
-- @tparam string strKeyValue 关键字段值，不能为空
-- @treturn number 0表示成功，非0表示错误码
-- @treturn boolean|string 成功时返回true/false，失败时返回错误信息
function m3.ExistThisDataObject( strLuaDEID, strClsID, strKeyAttr, strKeyValue )
    local strCondition, nRet, strRetInfo

    if strClsID == nil or strClsID == '' then
        return 1, "ExistThisDataObject 函数 strClsID 必须有值"
    end
    if strKeyAttr == nil or strKeyAttr == '' then
        return 1, "ExistThisDataObject 函数 strKeyAttr 必须有值"
    end
    if strKeyValue == nil or strKeyValue == '' then
        return 1,  "ExistThisDataObject 函数 strKeyValue 必须有值"
    end

    strCondition = strKeyAttr.." = '"..string.gsub(strKeyValue, "'", "''").."'"
	nRet, strRetInfo = mobox.existThisData( strLuaDEID, strClsID, strCondition )
    if nRet ~= 0 then
        return 2, "existThisData 函数失败!"..strRetInfo
    end

    if strRetInfo == 'no' then
        return 0, false
    end
    return 0, true
end

-- 是否存在关键字段=XX的数据对象，如果存在返回数据对象标识 ID
-- KeyAttr必须是字符串类型
-- @function m3.GetDataObjectID
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strClsID 数据类标识，不能为空
-- @tparam string strKeyAttr 关键字段名，不能为空
-- @tparam string strKeyValue 关键字段值，不能为空
-- @treturn number 0表示成功，非0表示错误码
-- @treturn string 成功时返回 数据对象标识，失败时返回错误信息
function m3.GetDataObjectID( strLuaDEID, strClsID, strKeyAttr, strKeyValue )
    if strClsID == nil or strClsID == '' then
        return 1, "ExistThisDataObject2 函数 strClsID 必须有值"
    end
    if strKeyAttr == nil or strKeyAttr == '' then
        return 1, "ExistThisDataObject2 函数 strKeyAttr 必须有值"
    end
    if strKeyValue == nil or strKeyValue == '' then
        return 1,  "ExistThisDataObject2 函数 strKeyValue 必须有值"
    end

    local nRet, data_obj = m3.GetDataObjectByKey(strLuaDEID, strClsID, strKeyAttr, strKeyValue)

    if nRet == 0 then
        return 0, data_obj.id
    end
    if nRet == 1 then
        return 0, ""        -- 不
    end
    return 1, data_obj
end

-- 是否存在符合条件的数据对象
-- @function m3.ExistThisDataByCondition
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strClsID 数据类标识，不能为空
-- @tparam string strCondition 查询条件，不能为空
-- @treturn number 0表示成功，非0表示错误码
-- @treturn boolean|string 成功时返回true/false，失败时返回错误信息
function m3.ExistThisDataByCondition( strLuaDEID, strClsID, strCondition )
    local nRet, strRetInfo

    if strClsID == nil or strClsID == '' then 
        return 1, "ExistThisDataByCondition 函数 strClsID 必须有值" 
    end
    if strCondition == nil or strCondition == '' then 
        return 1, "ExistThisDataByCondition 函数 strCondition 必须有值"
    end

	nRet, strRetInfo = mobox.existThisData( strLuaDEID, strClsID, strCondition )
    if nRet ~= 0 then 
        return 2, "mobox.existThisData 函数失败!"..strRetInfo 
    end

    if strRetInfo == 'no' then 
        return 0, false 
    end
    return 0, true
end

-- 新增一个后台处理脚本
-- @function m3.AddSysWFP
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table paramter 参数table，包含以下字段：
--   {wfp_type, datajson, cls, obj_id, obj_name, trigger_type, trigger_time, trigger_event, trigger_event_code, wfp_name}
--   wfp_type: 0=按datajson触发, 1=触发数据对象/数据类事件, 2=触发Zone/Zon_Cls
--   trigger_type: 0=一次性, 1=指定时间, 2=每天指定时间, 3=永久循环
-- @treturn number 0表示成功，1表示错误
-- @treturn string|nil 错误信息，成功时 nil
function m3.AddSysWFP( strLuaDEID, paramter )
    local nRet, strRetInfo
    local wfp_list_show_name = ''

    if paramter == nil or type(paramter) ~= "table" then
        return 1, "AddSysWFP 参数paramter不能为空! 必须是table类型"
    end

    local cls = paramter.cls
    local id  = paramter.obj_id
    local obj_display_name = paramter.obj_name
    local trigger_time = paramter.trigger_time
    local trigger_event = ""
    local trigger_type = paramter.trigger_type
    local strDataJson = ''

    if paramter.datajson == nil then 
        strDataJson = ''
    elseif type(paramter.datajson) ~= "table" then
        strDataJson = paramter.datajson
    else
        strDataJson = lua.table2str( paramter.datajson )
    end

    if trigger_type == nil then trigger_type = 0 end
    if strDataJson == nil then strDataJson = '' end
    if obj_display_name == nil then obj_display_name = '' end
    if trigger_time == nil then trigger_time = '' end
    if id == nil then id = '' end
    if paramter.wfp_type == nil then 
        paramter.wfp_type = 1
    end

    if paramter.wfp_type == 1 then
        -- 触发数据类事件
        if paramter.cls == nil or paramter.cls == '' then
            return 1, "AddSysWFP 参数paramter缺少cls属性!"
        end
        if paramter.trigger_event == nil or paramter.trigger_event == '' then
            return 1, "AddSysWFP 参数paramter缺少trigger_event属性!"
        end  
        trigger_event = paramter.trigger_event
        if obj_display_name == '' then
            wfp_list_show_name = "触发数据类'"..paramter.cls.."'对象事件'"..paramter.trigger_event.."'"  
        else
            wfp_list_show_name = obj_display_name
        end
    elseif paramter.wfp_type == 2 then
        -- 触发Zone、Zon_Cls 
        if paramter.obj_id == nil or paramter.obj_id == '' then
            return 1, "AddSysWFP 参数paramter缺少obj_id属性!"
        end            
        if paramter.cls == nil or paramter.cls == '' then
            return 1, "AddSysWFP 参数paramter缺少cls属性!"
        end
        if paramter.trigger_event == nil or paramter.trigger_event == '' then
            return 1, "AddSysWFP 参数paramter缺少trigger_event属性!"
        end  
        wfp_list_show_name = "触发数据类'"..paramter.cls.."'对象事件'"..paramter.trigger_event.."'"         
        trigger_event = paramter.trigger_event
    elseif paramter.wfp_type == 0 then
        if strDataJson == '' then
            return 1, "AddSysWFP 参数paramter缺少 datajson 属性!"
        end
    else
        return 1, "AddSysWFP 参数paramter中的wfp_type属性值不正确只能是0,1,2!"        
    end

    nRet, strRetInfo = mobox.addSysWFP( strLuaDEID, paramter.wfp_type, strDataJson, cls, id, 
                                        obj_display_name, trigger_type, 
                                        trigger_time,
                                        trigger_event, 
                                        wfp_list_show_name, "", 0 )
    if nRet ~= 0 then
        return 1, "addSysWFP 失败!"..strRetInfo
    end

    return 0
end

-- 动态可编程接口返回函数
-- err_code = 0 表示接口成功
-- @function m3.EPI_Return
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam table json_return_value 返回给调用方的Json对象
function m3.EPI_Return( strLuaDEID, json_return_value )
    mobox.returnValue( strLuaDEID, 1, lua.table2str(json_return_value) )  
end

-- 获取当前编辑对象的属性和ID
-- @function m3.GetCurEditDataObj
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为包含id/cls的数据对象，失败时为错误信息
function m3.GetCurEditDataObj( strLuaDEID )
    local nRet, data_obj
    local strClsID, strObjID
    nRet, strClsID, strObjID = mobox.getCurEditDataObjID( strLuaDEID )
    if nRet ~= 0 then
        return 2, "getCurEditDataObjID失败!  "..strClsID
    end

    nRet, data_obj = m3.GetSysCurEditDataObj( strLuaDEID, strClsID )
    if nRet ~= 0 then
        return 2, "获取【'"..strClsID.."'】对象属性失败!"..data_obj
    end
    return 0, data_obj
end

-- 获取Lua数据交换区的所有参数，用于Lua调试时模拟Debug环境参数
-- @function m3.PrintLuaDEInfo
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @treturn number 0表示成功，非0表示错误码
-- @treturn string|nil 错误信息，成功时 nil
function m3.PrintLuaDEInfo( strLuaDEID )
    local nRet, obj_attr, runtime, input_paramter, global_attr
    local strClsID, strObjID

    nRet, strClsID, strObjID = mobox.getCurEditDataObjID( strLuaDEID )
    if nRet ~= 0 then 
        strClsID = ''
        strObjID = ''
    end
    if strClsID == nil then
        strClsID = ''
    end
    if strObjID == nil then
        strObjID = ''
    end

    obj_attr = {}
    nRet, obj_attr = m3.GetSysCurEditDataAttrs( strLuaDEID )
    if nRet ~= 0 then
        obj_attr = {}
    end
    local lua_ed = {
        cls_id = strClsID,
        obj_id = strObjID,
        obj_attr = obj_attr,
        data_json = {},
        ext_info = {},
        global_attr = {},
        input_param = {}
    }

    nRet, lua_ed.data_json = mobox.getCurEditDataPacket( strLuaDEID )
    if nRet ~= 0 then
        lua_ed.data_json = {}
    end
    nRet, global_attr = m3.GetSysGloablAttr( strLuaDEID )
    if nRet == 0 then 
        lua_ed.global_attr = global_attr
    end
    nRet, input_paramter = m3.GetSysInputParameter( strLuaDEID )
    if nRet == 0 then 
        lua_ed.input_param = input_paramter
    end
    nRet, runtime = m3.GetRuntimeParam( strLuaDEID )
    if nRet == 0 then 
        lua_ed.ext_info = runtime
    end        

    lua.DebugEx( strLuaDEID, "Lua脚本数据交换区内容-->", lua_ed )
    return 0
end

-- 从内存获取数据对象属性
-- @function m3.GetDataFromCache
-- @tparam string cls_id 数据类标识，不能为空
-- @tparam string key 缓存键值，不能为空
-- @treturn number 0表示成功，1表示不存在，2表示错误
-- @treturn table|string 成功时为数据对象，失败时为错误信息
function m3.GetDataFromCache( cls_id, key )
    local nRet, strRetInfo
    
    if lua.StrIsEmpty( cls_id ) then
        return 1, "函数 GetDataFromCache 中 cls_id 必须要有值!"
    end
    if lua.StrIsEmpty( key ) then
        return 1, "函数 GetDataFromCache 中 key 必须要有值!"
    end

    nRet, strRetInfo = mobox.getMemoryDataObjInfo( cls_id, key )
    if nRet ~= 0 then
        return 2, strRetInfo
    end
    if strRetInfo == '' then 
        return 1, " 数据类标识 '"..cls_id.."' 的缓存中不存在 key = '"..key.."'的数据对象!"
    end
    local success, data
    success, data = pcall( json.decode, strRetInfo )
    if success == false then
        return 2, "getMemoryDataObjInfo 返回非法的JSON字符串!"
    end
    return 0, data
end

-- 把一个[{"attr":"xx","value":"1"},...] 的字符串，转成是lua属性的json格式table对象
-- @function m3.AttrValueStrToLuaJson
-- @tparam string cls_id 数据类标识
-- @tparam string attr_value 属性字符串 [{"attr":"xx","value":"1"},...]
-- @treturn number 0表示成功，1表示错误
-- @treturn table|string 成功时为Lua属性格式的对象，失败时为错误信息
function m3.AttrValueStrToLuaJson( cls_id, attr_value )
    local nRet, strObjJson = mobox.objAttrsToLuaJson( cls_id, attr_value )
    if nRet ~= 0 then 
        return 1, "objAttrsToLuaJson 失败!"..strObjJson
    end
    local success, obj_lua
    success, obj_lua = pcall( json.decode, strObjJson )
    if success == false then 
        return 1, "objAttrsToLuaJson 返回的的JSON格式不合法 !"..obj_lua 
    end 
    return 0, obj_lua 
end

-- 在Lua程序里执行Lua脚本
-- @function m3.RunScript
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string strEventClsID 事件数据类标识，不能为空
-- @tparam string strEventName 事件名称，不能为空
-- @tparam string strEditDataCls 编辑数据类标识
-- @tparam string strEditDataObjID 编辑数据对象标识
-- @tparam table parameter 参数table
-- @tparam table data_json 数据Json table
-- @treturn number 0表示成功，非0表示错误码
-- @treturn table|string 成功时为执行结果，失败时为错误信息
function m3.RunScript( strLuaDEID, strEventClsID, strEventName, strEditDataCls, strEditDataObjID, parameter, data_json )
    local nRet, strRetInfo
    if lua.StrIsEmpty( strEventClsID ) then
        return 1, "m3.RunScript 函数 strEventClsID 必须有值!"
    end
    if lua.StrIsEmpty( strEventName ) then
        return 1, "m3.RunScript 函数 strEventName 必须有值!"
    end   
    local strParameter = ''
    local strDataJson = ''
    local success

    if lua.isTableEmpty( parameter ) then
        strParameter = ''
    else
        success, strParameter = pcall( json.encode, parameter )
        if success == false then
            return 1, "m3.RunScript 函数 parameter 不是合法的table参数!"
        end
    end

    if lua.isTableEmpty( data_json ) then
        strDataJson = ''
    else
        success, strDataJson = pcall( json.encode, data_json )
        if success == false then
            return 1, "m3.RunScript 函数 data_json 不是合法的table参数!"
        end        
    end    

    nRet, strRetInfo = mobox.runCustomEvent( strLuaDEID, strEventClsID, strEventName, strEditDataCls, strEditDataObjID,
                                             strParameter, strDataJson )
    if nRet ~= 0 then
        return nRet, strRetInfo
    end
    local ret_result

    success, ret_result = pcall( json.decode, strRetInfo )
    if success == false then 
        return 2, "解析返回的字符串错误: --> "..strRetInfo
    end
    return 0, ret_result
end

-- 把属性为数据字段的table转化为Lua属性格式的table
-- 格式为:{ S_ITEM_CODE = "xxx", F_QTY = "10",..} 的格式转换为{ item_code = "xxx", qty = 10,... }
-- @function m3.objJsonToLuaJson
-- @tparam string cls_id 数据类标识
-- @tparam table obj_json 数据表字段格式的table { S_ITEM_CODE = "xxx", ...}
-- @treturn number 0表示成功，1表示错误
-- @treturn table|string 成功时为Lua属性格式的对象，失败时为错误信息
function m3.objJsonToLuaJson( cls_id, obj_json )
    local nRet, strRetInfo
    local lua_json

    nRet, strRetInfo = mobox.objJsonToLuaJson( cls_id, lua.table2str(obj_json) )
    if nRet ~= 0 then
        return 1, "objJsonToLuaJson 失败!"..strRetInfo
    end
    local success
    success, lua_json = pcall( json.decode, strRetInfo )
    if success == false then 
        return 1, "解析返回的字符串错误: --> "..lua_json
    end
    return 0, lua_json
end

-- 分页查询数据对象
-- @function m3.QueryDataObjAttr2
-- @tparam string strLuaDEID Lua数据交换区句柄
-- @tparam string cls_id 数据类标识，不能为空
-- @tparam string condition 查询条件，可选
-- @tparam string order 排序，可选
-- @tparam number num 每页条数，默认100
-- @treturn number 0表示成功，1参数错误，2执行错误
-- @treturn table|string 成功时为查询信息(含pageCount/dataSet)，失败时为错误信息
function m3.QueryDataObjAttr2( strLuaDEID, cls_id, condition, order, num )
    local nRet, strRetInfo

    if cls_id == nil or cls_id == '' then
        return 1, "m3.QueryDataObjAttr2 函数 cls_id参数无效"
    end
    if num == nil or num == 0 then
        num = 100
    end
    if order == nil then
        order = ''
    end
    if condition == nil then
        condition = ''
    end
    nRet, strRetInfo = mobox.queryDataObjAttr2( strLuaDEID, cls_id, condition, order, num )
    if nRet ~= 0 then 
        return 2, "queryDataObjAttr2 失败! "..strRetInfo 
    end  
    local query_info = {}
    if strRetInfo == '' then 
        return 0, query_info 
    end 

    local success
    success, query_info = pcall( json.decode, strRetInfo )
    if not success then 
        return 2, "queryDataObjAttr2 返回非法的JSON字符串!"
    end
    return 0, query_info
end

-- 获取功能点页面参数
-- @function m3._GetFuncPointAttrs
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @treturn table function_point_attrs 功能点参数，失败为 nil
-- @treturn string|nil 错误信息，成功时 nil
function m3._GetFuncPointAttrs( strLuaDEID )
    local nRet, runtime_parameter = m3.GetRuntimeParam(strLuaDEID)
    if nRet ~= 0 then 
        return nil, "GetRuntimeParam失败! "..runtime_parameter
    end
    local function_point_attrs = m3.KeyValueAttrsToObjAttr( runtime_parameter.function_point_attrs )
    if function_point_attrs == nil then
        return nil, "功能点参数为空!"
    end
    return function_point_attrs
end

-- 获取外部Lua函数名称和module名称
-- @function m3.GetExtFunction
-- @tparam table ext_func = { module_name = "", func_name/function_name = "}
-- @treturn number 0表示成功，1参数错误，2执行错误
-- @treturn string module_name 模块名称, 错误时返回错误信息
-- @treturn string func_name 函数名称
function m3.GetExtFunction( ext_func )
    if ext_func == nil or type(ext_func) ~= "table" then
        return 1, "m3.GetExtFunction 函数中 ext_func 参数不能为空!"
    end
    local module_name = ext_func.module_name or ''
    local func_name = ext_func.function_name or ''
    if func_name == '' then
        func_name = ext_func.func_name or ''
    end
    if module_name == '' or func_name == '' then
        return 1, "m3.GetExtFunction 函数中参数 ext_func 参数中 module_name 或 func_name 不能为空!"
    end
    return 0, module_name, func_name
end

-- 获取满足条件的数据对象个数
-- @function m3.GetDataObjCount
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cls_id 数据类标识，不能为空
-- @tparam string condition 可以为空
-- @treturn number 0表示成功，1参数错误，2执行错误
-- @treturn number|string 成功时返回数量，失败为错误信息
function m3.GetDataObjCount( strLuaDEID, cls_id, condition )
    if condition == nil then
        condition = ''
    end
    if cls_id == nil or cls_id == '' then
        return 1, "m3.GetDataObjCount 函数 cls_id 参数无效!"
    end
    local nRet, strRetInfo = mobox.getDataObjCount( strLuaDEID, cls_id, condition )
    if nRet ~= 0 then 
        return nRet, strRetInfo 
    end 
    return 0, lua.StrToNumber( strRetInfo )
end

-- 获取指定数据类中的所有属性
-- @function m3.Get_Cls_Attrs
-- @tparam string strLuaDEID Lua数据交换区句柄, 必须有值
-- @tparam string cls_id 数据类标识，不能为空
-- @treturn number 0表示成功，1参数错误，2执行错误
-- @treturn table|string 成功时返回 attrs 属性数组，失败为错误信息
function m3.Get_Cls_Attrs( strLuaDEID, cls_id )
    local data_obj = m3.AllocObject2(strLuaDEID, cls_id )  

    if data_obj == nil then
        return 1, "AllocObject2 failed"
    end
    local attrs = {}
    for k in pairs(data_obj) do
        attrs[#attrs + 1] = tostring(k)
    end    
    return 0, attrs
end

return m3