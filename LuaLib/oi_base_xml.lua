local xml = {_version = "0.1.1"} -- 定义一个空表，用于存储模块的函数和变量'

-- 数据清洗函数（处理命名空间和空值）把 <soap:Body> 改成 <Body>
local function clean_data(data)
    local function process(tbl)
        local result = {}
        for k, v in pairs(tbl) do
            -- 去除命名空间前缀[6,9](@ref)
            local new_key = k:gsub("v1:", ""):gsub("soap:", ""):gsub("soapenv:", "")
            
            if type(v) == "table" then
                -- 处理数组结构[4](@ref)
                if #v > 0 then
                    local arr = {}
                    for i, item in ipairs(v) do
                        arr[i] = process(item)
                    end
                    result[new_key] = arr
                else
                    result[new_key] = process(v)
                end
            else
                result[new_key] = v ~= "" and v or nil
            end
        end
        if next(result) == nil then result = "" end
        return result
    end
    return process(data)
end

function xml.parse(xml_str)
    local handler = require("xmlhandler.tree")
    local xml2lua = require("xml2lua")

    local h = handler:new()
    -- 使用 pcall 捕获异常
    local ok, err = pcall( function() xml2lua.parser(h):parse(xml_str) end )
    if not ok then
        return 1, "XML解析失败:"..err
    end
    return 0, clean_data( h.root )
end

function xml.jsonToSoap(xmlStr, namespace, responseName)
    
    -- 使用更安全的字符串构建方式
    return string.format(
        '<?xml version="1.0" encoding="UTF-8"?>\n'..
        '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">\n'..
        '    <soap:Body>\n'..
        '        <ns2:%sResponse xmlns:ns2="%s">\n'..
        '            <return>\n'..
        '                <![CDATA[%s]]>\n'..
        '            </return>\n'..
        '        </ns2:%sResponse>\n'..
        '    </soap:Body>\n'..
        '</soap:Envelope>',
        responseName, namespace, xmlStr, responseName
    )
end

function xml.generate_soap_request(arg0, arg3_data)
    -- 参数验证
    if type(arg0) ~= "string" or arg0 == "" then
        return nil, "操作名(arg0)不能为空"
    end
    
    if type(arg3_data) ~= "table" then
        return nil, "XML内容(arg3)必须是表"
    end
    
    local arg1 = "interfacesource"  -- 接口调用用户名
    local arg2 = "123456"           -- 接口调用密码

    -- 通用表转XML函数（支持嵌套表和数组）
    local function table_to_xml(data, root_name)
        root_name = root_name or "root"
        local xml_parts = {}
        
        local function build_xml(value, tag, indent)
            indent = indent or 0
            local spaces = string.rep(" ", indent)
            
            if type(value) == "table" then
                if #value > 0 then -- 处理数组
                    xml_parts[#xml_parts + 1] = spaces .. "<"..tag..">"
                    for _, item in ipairs(value) do
                        build_xml(item, tag:match("^(.*)s$") or "item", indent + 2)
                    end
                    xml_parts[#xml_parts + 1] = spaces .. "</"..tag..">"
                else -- 处理对象
                    xml_parts[#xml_parts + 1] = spaces .. "<"..tag..">"
                    for k, v in pairs(value) do
                        build_xml(v, k, indent + 2)
                    end
                    xml_parts[#xml_parts + 1] = spaces .. "</"..tag..">"
                end
            else -- 基本类型
                local content = tostring(value)
                    :gsub("&", "&amp;")
                    :gsub("<", "&lt;")
                    :gsub(">", "&gt;")
                xml_parts[#xml_parts + 1] = spaces .. "<"..tag..">"..content.."</"..tag..">"
            end
        end
        
        build_xml(data, root_name, 0)
        return '<?xml version="1.0" encoding="UTF-8"?>' .. table.concat(xml_parts)
    end

    -- 生成动态XML
    local arg3_xml = table_to_xml(arg3_data, "request")
    
    -- 处理CDATA中的特殊序列
    arg3_xml = arg3_xml:gsub("%]%]>", "]]]]><![CDATA[>")
    
    -- 构建SOAP报文（使用多行字符串避免换行符问题）
    local result_xml = string.format(
    '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:act="http://action.service.prolog.com/">\n'..
    '    <soapenv:Header/>\n'..
    '    <soapenv:Body>\n'..
    '        <act:requestService>\n'..
    '            <arg0>%s</arg0>\n'..
    '            <arg1>%s</arg1>\n'..
    '            <arg2>%s</arg2>\n'..
    '            <arg3><![CDATA[%s]]></arg3>\n'..
    '        </act:requestService>\n'..
    '    </soapenv:Body>\n'..
    '</soapenv:Envelope>',
    arg0, arg1, arg2, arg3_xml)
    return string.gsub(result_xml, "#", "")
end

-- 解析 SOAP 响应并返回 JSON 字符串
function xml.parse_soap_response(soap_response)
    -- 1. 提取 CDATA 内容
    local cdata_start = "<![CDATA["
    local cdata_end = "]]>"
    local cdata_start_pos = soap_response:find(cdata_start, 1, true)
    local cdata_end_pos = soap_response:find(cdata_end, cdata_start_pos, true)
    
    if not cdata_start_pos or not cdata_end_pos then
        return nil, "CDATA section not found"
    end
    
    local inner_xml = soap_response:sub(
        cdata_start_pos + #cdata_start, 
        cdata_end_pos - 1
    )
    
    -- 2. 解析内部 XML
    local function extract_tag(tag, xml_str)
        local pattern = "<"..tag..">(.-)</"..tag..">"
        local value = xml_str:match(pattern)
        if not value then
            return nil, "Tag <"..tag.."> not found"
        end
        return value
    end
    
    local flag, err1 = extract_tag("flag", inner_xml)
    local code, err2 = extract_tag("code", inner_xml)
    local message, err3 = extract_tag("message", inner_xml)
    
    if err1 or err2 or err3 then
        return nil, (err1 or err2 or err3)
    end
    
    -- 3. 转换为 JSON 字符串（手动构建）
    local json_str = string.format(
        '{"flag":"%s","code":%s,"message":"%s"}',
        escape_json(flag),
        code,
        escape_json(message))
    
    return json_str
end

-- JSON 特殊字符转义
function escape_json(str)
    if not str then return "" end
    return str:gsub('"', '\\"'):gsub("\\", "\\\\"):gsub("/", "\\/")
             :gsub("\b", "\\b"):gsub("\f", "\\f"):gsub("\n", "\\n")
             :gsub("\r", "\\r"):gsub("\t", "\\t")
end


function xml.json_to_xml(data, root_tag)
    local xml = {}
    local function build_xml(node, tag)
        if type(node) == "table" then
            xml[#xml + 1] = "<" .. tag .. ">"
            for k, v in pairs(node) do
                build_xml(v, k) -- 递归处理子节点
            end
            xml[#xml + 1] = "</" .. tag .. ">"
        else
            xml[#xml + 1] = "<" .. tag .. ">" .. tostring(node) .. "</" .. tag .. ">"
        end
    end
    build_xml(data, root_tag or "root")
    return table.concat(xml)
end

return xml