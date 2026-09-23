--[[
    版本：     Version 1.0
    创建日期： 2025-11-28
    创建人：   HAN

        WMS Putaway Algorithms
        上架策略算法集

    功能：
        这是一个创建上架策略算法函数命名空间的程序，具体的算法函数分别在:
        wms_pa_asrs  -- 适合自动化立库用的上架策略算法

--]]
local function create_namespace()
    local ns = {}
    
    -- 加载所有部分
    local parts = {}

    local ok, result = pcall(require, "wms_pa_asrs")
    if ok and type(result) == "table" then
        table.insert(parts, result)
    end
    -- 合并所有部分
    for _, part in ipairs(parts) do
        for k, v in pairs(part) do
            ns[k] = v
        end
    end
    
    return ns
end

return create_namespace()