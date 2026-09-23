--[[
    版本：     Version 2.1
    创建日期： 2025-5-28
    创建人：   HAN

    WMS-Basis-Model-Version: V15.5

    功能：
        WMS 中用到的一些常量定义在这个程序包
--]]

json  = require ("json")
mobox = require ("OILua_JavelinExt")
lua   = require ("oi_base_func")
m3    = require ("oi_base_mobox")

-- 容器类型
WMS_CNTR_TYPE_NAME = {
    ["Pallet"] = "托盘",
    ["Normal"] = "常规",
    ["Cell_Box"] = "料格",
    ["Picking_Box"] = "拣料箱",
    ["Mobile_Rack"] = "移动料架",
    ["Tooling"] = "工位器具",
}
WMS_CNTR_TYPE = {
    ["托盘"] = "Pallet",
    ["常规"] = "Normal",
    ["料格"] = "Cell_Box",
    ["拣料箱"] = "Picking_Box",
    ["移动料架"] = "Mobile_Rack",
    ["工位器具"] = "Tooling",
}

ITEM_BASE_ATTRS = {
    "S_ITEM_CODE",
    "S_ITEM_NAME",
    "S_ITEM_SPEC",
    "S_STORER",    
    "S_ITEM_STATE",                        
    "S_SERIAL_NO",
    "S_BATCH_NO",
    "S_OWNER",
    "S_SUPPLIER_NO",
    "D_EXP_DATE",
    "D_PRD_DATE",
    "S_WMS_BN",
    "F_WEIGHT",
    "F_VOLUME",
    "F_SCU",
}  

ITEM_BASE_ATTRS2 = {
    "S_STORER", 
    "S_ITEM_CODE",
    "S_ITEM_STATE",      
    "S_ITEM_NAME",
    "S_ITEM_SPEC",
    "S_SERIAL_NO",
    "S_BATCH_NO",
    "S_OWNER",
    "S_SUPPLIER_NO",
    "D_EXP_DATE",
    "D_PRD_DATE",
    "S_WMS_BN"
}  

CNTR_CELL_BASE_ATTRS = {
    "S_CNTR_CODE",
    "S_CELL_NO",
    "S_STORER",   
    "S_ITEM_CODE",
    "S_ITEM_NAME",
    "S_ITEM_STATE",                        
    "S_SERIAL_NO",
    "S_BATCH_NO",
    "S_OWNER",
    "S_SUPPLIER_NO",
    "D_EXP_DATE",
    "D_PRD_DATE",
    "S_WMS_BN",
    "F_QTY"
} 
CNTR_CELL_BASE_ATTRS2 = {
    "S_STORER",   
    "S_ITEM_CODE",
    "S_ITEM_NAME",
    "S_ITEM_STATE",                        
    "S_SERIAL_NO",
    "S_BATCH_NO",
    "S_OWNER",
    "S_SUPPLIER_NO",
    "D_EXP_DATE",
    "D_PRD_DATE",
    "S_WMS_BN",
    "F_QTY"
}   

-- INV_FO_Detail明细表主要属性
INV_FO_DETAIL_BASE_ATTRS   = {
    "S_CNTR_CODE",
    "S_CELL_NO",
    "S_CELL_CODE",
    "S_STORER",
    "S_ITEM_CODE",
    "S_ITEM_STATE",
    "S_ITEM_NAME",
    "S_SERIAL_NO",
    "S_BATCH_NO",
    "S_WMS_BN",
    "S_OWNER",
    "S_SUPPLIER_NO",
    "F_QTY",
    "S_UOM",
    "D_PRD_DATE",
    "D_EXP_DATE"
}

-- INV_Change_Detail 明细表主要属性
INV_CHANGE_DETAIL_BASE_ATTRS   = {
    "N_ROW_NO",
    "S_CNTR_CODE",
    "S_CELL_NO",
    "S_CELL_CODE",
    "S_STORER",
    "S_ITEM_CODE",
    "S_ITEM_NAME",
    "S_SERIAL_NO",
    "S_BATCH_NO",
    "S_WMS_BN",
    "S_OWNER",
    "S_SUPPLIER_NO",
    "F_QTY",
    "S_UOM",
    "D_PRD_DATE",
    "D_EXP_DATE"
}

-- IWP_Range 货品查询字段
IWP_RANGE_QUERY_ATTRS = {
    "S_STORER",    
    "S_ITEM_CODE",
    "S_ITEM_STATE",                        
    "S_SERIAL_NO",
    "S_BATCH_NO",
    "S_OWNER",
    "S_SUPPLIER_NO",
    "D_EXP_DATE",
    "D_PRD_DATE",
    "S_WMS_BN"
}   

-- 盘点容器货品明细 IWP_CNTR_Detail
COUNT_CNTR_DETAIL_ATTRS = {
    "S_CNTR_CODE",
    "S_CELL_NO", 
    "S_CELL_CODE",
    "S_WH_CODE",
    "S_AREA_CODE",
    "S_LOC_CODE",   
    "S_STORER",    
    "S_ITEM_CODE",
    "S_ITEM_STATE",                        
    "S_ITEM_NAME",
    "S_SERIAL_NO",
    "S_BATCH_NO",
    "S_WMS_BN",
    "S_OWNER",
    "S_SUPPLIER_NO",
    "F_QTY",
    "S_UOM",
    "D_PRD_DATE",
    "D_EXP_DATE"
} 

-- 码盘明细 表中的属性
-- 预分配明细也一样的属性
INB_PALLET_DETAIL_ATTRS = {
                            "S_CELL_NO",
                            "S_ITEM_CODE",
                            "S_ITEM_NAME",
                            "S_SERIAL_NO",
                            "S_ITEM_STATE",
                            "S_BATCH_NO",
                            "S_WMS_BN",
                            "S_OWNER",
                            "S_STORER",
                            "S_SUPPLIER_NO",
                            "F_QTY",
                            "S_UOM",
                            "D_PRD_DATE",
                            "D_EXP_DATE",
                            "S_BS_NO",
                            "S_BS_TYPE",
                            "N_BS_ROW_NO",
                            "F_VOLUME",
                            "F_WEIGHT",                            
                            "S_UDF01",
                            "S_UDF02",
                            "S_UDF03",
                            "S_UDF04",
                            "S_UDF05",
                            "S_UDF06",
                            "S_UDF07",
                            "S_UDF08",
                            "S_UDF09",
                            "S_UDF10",
                            "S_UDF11",
                            "S_UDF12",
                            "S_UDF13",
                            "S_UDF14",
                            "S_UDF15",
                            "S_UDF16",
                            "S_UDF17",
                            "S_UDF18",
                            "S_UDF19",
                            "S_UDF20"
                        }
-- 配盘明细基本属性/Distribution_CNTR_Detail                     
DC_DETAIL_ATTRS = {
                           "S_CNTR_CODE",
                            "S_CELL_NO",
                            "S_STORER",
                            "S_WH_CODE",
                            "S_AREA_CODE",
                            "S_LOC_CODE",
                            "S_ITEM_CODE",
                            "S_ITEM_STATE",
                            "S_ITEM_NAME",
                            "S_SERIAL_NO",
                            "S_BATCH_NO",
                            "S_OWNER",
                            "S_SUPPLIER_NO",
                            "S_WMS_BN",
                            "F_QTY",
                            "S_UOM",
                            "D_PRD_DATE",
                            "D_EXP_DATE",
                            "S_UDF01",
                            "S_UDF02",
                            "S_UDF03",
                            "S_UDF04",
                            "S_UDF05",
                            "S_UDF06",
                            "S_UDF07",
                            "S_UDF08",
                            "S_UDF09",
                            "S_UDF10",
                            "S_UDF11",
                            "S_UDF12",
                            "S_UDF13",
                            "S_UDF14",
                            "S_UDF15",
                            "S_UDF16",
                            "S_UDF17",
                            "S_UDF18",
                            "S_UDF19",
                            "S_UDF20",
                            "S_BS_NO",
                            "S_BS_TYPE",
                            "N_BS_ROW_NO"
                        } 

DC_DETAIL_BASE_ATTRS = {                    -- 少了S_CNTR_CODE, SC_CELL_NO, S_BS_NO, S_BS_TYPE, N_BS_ROW_NO
                            "S_STORER",                            
                            "S_ITEM_CODE",
                            "S_ITEM_STATE",                            
                            "S_ITEM_NAME",
                            "S_SERIAL_NO",                            
                            "S_BATCH_NO",
                            "S_OWNER",
                            "S_SUPPLIER_NO",
                            "S_WMS_BN",
                            "F_QTY",
                            "S_UOM",
                            "D_PRD_DATE",
                            "D_EXP_DATE",
                            "S_UDF01",
                            "S_UDF02",
                            "S_UDF03",
                            "S_UDF04",
                            "S_UDF05",
                            "S_UDF06",
                            "S_UDF07",
                            "S_UDF08",
                            "S_UDF09",
                            "S_UDF10",
                            "S_UDF11",
                            "S_UDF12",
                            "S_UDF13",
                            "S_UDF14",
                            "S_UDF15",
                            "S_UDF16",
                            "S_UDF17",
                            "S_UDF18",
                            "S_UDF19",
                            "S_UDF20"
                        }
-- 预分配容器货品明细的基础属性
PAC_DETAIL_BASE_ATTRS = {
    "S_CNTR_CODE",
    "S_CELL_NO",    
    "S_STORER",    
    "S_ITEM_CODE",
    "S_ITEM_STATE",                        
    "S_ITEM_NAME",
    "S_SERIAL_NO",
    "S_BATCH_NO",
    "S_WMS_BN",
    "S_OWNER",
    "S_SUPPLIER_NO",
    "F_QTY",
    "F_VOLUME",
    "F_WEIGHT",
    "F_SCU",
    "S_UOM",
    "D_PRD_DATE",
    "D_EXP_DATE",
    "S_WMS_BN",
    "S_BS_NO",
    "S_BS_TYPE",
    "N_BS_ROW_NO"
}                    
-- 库存量表中主要属性
INV_DETAIL_BASE_ATTRS = {
                        "S_CNTR_CODE",
                        "S_CELL_NO",    
                        "S_STORER",    
                        "S_ITEM_CODE",
                        "S_ITEM_STATE",                        
                        "S_ITEM_NAME",
                        "S_SERIAL_NO",
                        "S_BATCH_NO",
                        "S_WMS_BN",
                        "S_OWNER",
                        "S_SUPPLIER_NO",
                        "F_QTY",
                        "F_ALLOC_QTY",
                        "F_QTY_FREEZE",
                        "F_QTY_MOVE",
                        "F_QTY_VALID",
                        "F_VOLUME",
                        "F_WEIGHT",
                        "F_SCU",
                        "S_UOM",
                        "D_PRD_DATE",
                        "D_EXP_DATE",
                        "S_WMS_BN",
                        "S_BS_NO",
                        "S_BS_TYPE",
                        "N_BS_ROW_NO"
                    }

-- 库存量表中主要属性
INV_TXT_LOG_ATTRS = {
                    "S_CNTR_CODE",
                    "S_CELL_NO",    
                    "S_STORER",    
                    "S_ITEM_CODE",
                    "S_ITEM_STATE",                        
                    "S_ITEM_NAME",
                    "S_SERIAL_NO",
                    "S_BATCH_NO",
                    "S_WMS_BN",
                    "S_OWNER",
                    "S_SUPPLIER_NO",
                    "F_QTY",
                    "S_UOM",
                    "D_PRD_DATE",
                    "D_EXP_DATE",
                    "S_WMS_BN",
                    "S_BS_NO",
                    "S_BS_TYPE",
                    "N_BS_ROW_NO"
}                    
-- 库内移动业务异常
INV_TRANS_ANOMALY_ATTRS = {
                    "S_CNTR_CODE",
                    "S_CELL_NO", 
                    "S_CELL_CODE",
                    "S_WH_CODE",
                    "S_AREA_CODE",
                    "S_LOC_CODE",   
                    "S_STORER",    
                    "S_ITEM_CODE",
                    "S_ITEM_STATE",                        
                    "S_ITEM_NAME",
                    "S_SERIAL_NO",
                    "S_BATCH_NO",
                    "S_WMS_BN",
                    "S_OWNER",
                    "S_SUPPLIER_NO",
                    "F_QTY",
                    "S_UOM",
                    "D_PRD_DATE",
                    "D_EXP_DATE",
                    "S_BS_NO",
                    "S_BS_TYPE",
                    "N_BS_ROW_NO"
}    
-- 扩展属性                                          
UDF_ATTRS = {
                    "S_UDF01",
                    "S_UDF02",
                    "S_UDF03",
                    "S_UDF04",
                    "S_UDF05",
                    "S_UDF06",
                    "S_UDF07",
                    "S_UDF08",
                    "S_UDF09",
                    "S_UDF10",
                    "S_UDF11",
                    "S_UDF12",
                    "S_UDF13",
                    "S_UDF14",
                    "S_UDF15",
                    "S_UDF16",
                    "S_UDF17",
                    "S_UDF18",
                    "S_UDF19",
                    "S_UDF20"
            } 
-- INV_TXN_Log, INV_Lock_Log 的基本属性                    
INV_LOG_BASE_ATTRS = {
                        "S_WH_CODE",
                        "S_AREA_CODE",
                        "S_LOC_CODE",    
                        "S_CNTR_CODE",
                        "S_CELL_NO",    
                        "S_STORER",    
                        "S_ITEM_CODE",
                        "S_ITEM_STATE",                        
                        "S_ITEM_NAME",
                        "S_SERIAL_NO",
                        "S_BATCH_NO",
                        "S_WMS_BN",
                        "S_OWNER",
                        "S_SUPPLIER_NO",
                        "D_PRD_DATE",
                        "D_EXP_DATE"
                    }                       
-- 出库单明细基础属性
OUTBOUND_DETAIL_BASE_ATTRS = {
                        "S_STORER",    
                        "S_ITEM_CODE",
                        "S_ITEM_STATE",                        
                        "S_ITEM_NAME",
                        "S_SERIAL_NO",
                        "S_BATCH_NO",
                        "S_OWNER",
                        "S_SUPPLIER_NO",
                        "F_QTY",
                        "S_UOM",
                        "F_WEIGHT",
                        "F_VOLUME",
                        "S_PICKING_RULE",
                        "S_MATCH_RULE",
                        "S_PICK_BOX_CODE",
                        "S_PUT_WALL_NO",
                        "S_OO_NO",
                        "N_ROW_NO",
                        "S_WMS_BN"
                    } 
                    
-- 出库波次明细基础属性
OW_DETAIL_BASE_ATTRS = {
                        "S_STORER",    
                        "S_ITEM_CODE",
                        "S_ITEM_STATE",                        
                        "S_ITEM_NAME",
                        "S_SERIAL_NO",
                        "S_BATCH_NO",
                        "S_OWNER",
                        "S_SUPPLIER_NO",
                        "F_QTY",
                        "S_UOM",
                        "F_WEIGHT",
                        "F_VOLUME",
                        "S_PICKING_RULE",
                        "S_MATCH_RULE",
                        "S_PICK_BOX_CODE",
                        "S_PUT_WALL_NO",
                        "S_WMS_BN"
                    }                     

-- 容器扩展数据基本属性
CNTR_EXT_BASE_ATTRS = {
    "S_STORER",    
    "S_ITEM_CODE",
    "S_ITEM_STATE",                        
    "S_SERIAL_NO",
    "S_BATCH_NO",
    "S_OWNER",
    "S_SUPPLIER_NO",
    "D_EXP_DATE",
    "D_PRD_DATE",
    "S_WMS_BN"
}    
-- 容器基本属性
CNTR_BASE_ATTRS = {
    "S_CODE",    
    "S_CTD_CODE",
    "S_TYPE",                        
    "F_WEIGHT",
    "F_MAX_WEIGHT",
    "N_DETAIL_COUNT",
    "F_GOOD_WEIGHT",
    "F_GOOD_VOLUME",
    "C_FULL",
    "N_EMPTY_FULL",
    "F_LENGTH",
    "F_WIDTH",
    "F_HEIGHT",
    "N_GOOD_NUM",
    "S_SOURCE",
    "F_ACT_WEIGHT"
}  

-- +----------------+
-- |    常量定义     |
-- +----------------+
-- 数据库类型
DB_TYPE = lua.MakeConstantTable({ 
    SQLServer = 0, 
    Oracle = 1,
    MySQL = 2
}) 

-- 绑定/解绑方法
METHOD_TYPE = lua.MakeConstantTable({ 
    System = 1,            -- 系统
    Manual = 2             -- 人工
}) 
-- 货位容器加解绑动作
CNTR_LOC_ACTION = lua.MakeConstantTable({ 
    Bind= 1,               -- 绑定
    Unbind = 2             -- 解绑
}) 

-- 锁类型
LOCK_TYPE = lua.MakeConstantTable({ 
    Inbound= 1,               -- 入库锁
    Outbound = 2,             -- 出库锁
    Other = 3                 -- 其它锁
}) 

-- 调度系统类型
SCHEDULE_SYS_TYPE  = lua.MakeConstantTable({ 
    Ndc= 1,               -- NDC系统
    Team = 2,             -- 天目系统
    Grace = 3,            -- 国自系统
    Conveyor = 4,         -- 输送线
    Stacker = 5           -- 堆垛机
}) 

-- mobox.returnValue 函数中返回字符串类型定义
RETSTR_TYPE = lua.MakeConstantTable({ 
    String = 0,            -- 字符串
    Json = 1               -- Json格式
}) 
-- mobox.returnValue 函数中返回结果类型定义
RETRES_TYPE = lua.MakeConstantTable({ 
    Normal = 0,            -- 常规
    Sql = 1,               -- 返回是一个Update 的SQL语句
    UpdateAttrValue = 2,   -- 返回是的更新数据对象属性的设置
    Stop = 3,              -- 停止当前操作
    Unfulfilled = 4,       -- 条件不具备，等待后处理，返回的是原因
    ProcessOk = 5,         -- 处理完成，但希望反馈结果异常，返回值是异常原因
    Error = -1,            -- 返回的字符串是错误信息
}) 

-- [Operation] N_TYPE/作业类型
OPERATION_TYPE = lua.MakeConstantTable({ 
    Inbound = 1,            -- 入库
    Outbound = 2,           -- 出库
    Move = 3                -- 移库
}) 

-- [Operation] N_B_STATE /作业状态
OPERATION_STATE = lua.MakeConstantTable({ 
    WaitStartup = 0,        -- 待启动
    Run = 1,                -- 执行
    Finish = 2,             -- 完成
    Error = 3,              -- 错误
    StartupFail = 4,        -- 启动失败
    Paused = 5,             -- 暂停
    Wait = 6,               -- 等待
    Cancel = 7,             -- 取消
    BeforeStartup = 8,      -- 待启动前
    BeforeEnqueue = 9,      -- 进入计算队列前
    ComputeError = 10,      -- 后台计算错误
}) 
OPERATION_STATE_NAME = {"待启动","执行","完成","错误","启动失败","暂停","等待","取消","待启动前","进入计算队列前","后台计算错误"}

-- 作业待启动前、待启动状态后台启动检查错误码
OP_PRESTART_CHECK_ERR_CODE = lua.MakeConstantTable({ 
    CompPending = 100,              -- 库位计算还没完成
    CompError = 101,                -- 库位计算错误
    Station_Mode_Mismacth = 110,    -- 站台模式不匹配
    Station_Busy = 111,             -- 站台忙
    Station_LocFull = 112,          -- 站台库位已满
    Station_AssignFail = 113,       -- 站台分配失败
    Cntr_Occ_By_Other = 120,        -- 容器被其它作业占用
    Cntr_NotIn_Storage = 121,       -- 容器不在存储库位
    Bus_Order_Cancel = 130,         -- 业务单据取消
    SoftLock = 500,                 -- 软锁    
    LuaError = 800,                 -- Lua脚本错误
    DataError = 801,                -- 数据错误
}) 

OP_LOG_TYPE = lua.MakeConstantTable({ 
    Create = 1,              -- 创建
    PendingStart = 2,        -- 待启动
    Paused = 3,              -- 暂停启动
    StartFailed = 4,         -- 启动失败
    Run = 5,                 -- 执行
    RunFailed = 6,           -- 执行失败
    Cancel = 7,              -- 取消         
    CancelFailed = 8,        -- 取消失败
    Finish = 9,              -- 完成    
    
    CompPending = 100,              -- 库位计算还没完成
    CompError = 101,                -- 库位计算错误
    Station_Mode_Mismacth = 110,    -- 站台模式不匹配
    Station_Busy = 111,             -- 站台忙
    Station_LocFull = 112,          -- 站台库位已满
    Station_AssignFail = 113,       -- 站台分配失败
    Cntr_Occ_By_Other = 120,        -- 容器被其它作业占用
    Cntr_NotIn_Storage = 121,       -- 容器不在存储库位
    Bus_Order_Cancel = 130,         -- 业务单据取消
    SoftLock = 500,                 -- 软锁    
    LuaError = 800,                 -- Lua脚本错误
    DataError = 801,                -- 数据错误    
}) 


-- [Operation] N_TASK_STATE/作业中任务状态
OP_TASK_STATE = lua.MakeConstantTable({ 
    None = 0,             -- 空
    Pushed = 1,           -- 已推送
    Run = 2               -- 已执行
}) 

--各种数据类中的状态，特别是 N_B_STATE
-- [码盘]状态
PALLET_STATE = lua.MakeConstantTable({ 
    -- Inbound_Palletization 中的 N_B_STATE 值
    Pallet = 10,            -- 码盘中
    PalletOK = 11,          -- 码盘完成
    Inbound_Pending = 12,   -- 待入库
    Stock_In = 20,          -- 开始入库
    Finish = 30,            -- 入库完成
    Cancel = 40             -- 取消
}) 

-- [加解绑]状态
BINDING_METHOD = lua.MakeConstantTable({ 
    -- Loc_Container 中的 N_BINDING_METHOD 值
    System = 1,            -- 系统
    Manual = 2             -- 人工
}) 

-- [入库波次/Inbound_Wave]状态
IN_WAVE_STATE = lua.MakeConstantTable({ 
    -- Inbound_Wave 中的 N_B_STATE 值
    Unalloc = 0,              -- 待分配
    PreAlloc_OK = 1,          -- 预分配完成
    Op_Start = 2,             -- 已经开始入库作业
    Finish = 3,               -- 入库完成
    Error = 4,                -- 错误
    Paused = 6,               -- 暂停
    On_Cancel = 7,            -- 取消中   
    Cancel = 8,               -- 取消
    CancelErr = 9              -- 取消失败
})

-- [入库单/Inbound_Order]状态
INBOUND_STATE = lua.MakeConstantTable({ 
    -- Inbound_Order 中的 N_B_STATE 值
    Unalloc = 0,            -- 待分配
    PreAlloc_OK = 1,        -- 预分配完成
    Op_Start = 2,           -- 已经开始入库作业
    Finish = 3,             -- 入库完成
    Error = 4,              -- 错误
    Paused = 6,             -- 暂停
    On_Cancel = 7,          -- 取消中   
    Cancel = 8,             -- 取消
    CancelErr = 9           -- 取消失败
})

-- 入库单/出库单 N_CR_STATE 完工回报状态
CR_STATE = lua.MakeConstantTable({ 
    No = 0,                 -- 没回报
    Success = 1,            -- 回报成功
    API_Call_Failure = 2,   -- 调接口错误 
    API_Return_Error = 3    -- 接口返回错误
})


-- [任务/Task]状态
TASK_STATE = lua.MakeConstantTable({ 
    -- Task 中的 N_B_STATE 值
    Wait = 0,               -- 等待
    Pushed = 1,             -- 已推送
    Run = 2,                -- 执行
    Finish = 3,             -- 完成
    Error = 4,              -- 错误
    OnCancel = 7,           -- 取消中下·
    Cancel = 8,             -- 取消
    CancelErr = 9           -- 取消失败    
})

-- [Task/任务]任务类型
TASK_TYPE = lua.MakeConstantTable({ 
    -- Task 中的 N_TYPE 值
    None = 0,            -- 无
    In_Conveyor = 1,     -- 输送线入库
    Out_Conveyor = 2,    -- 输送线出库
    In_Stacker = 5,      -- 堆垛机入库
    Out_Stacker = 6,     -- 堆垛机出库  
    In_AGV = 10,         -- AGV入库
    Out_AGV = 11,        -- AGV出库   
    In_Picking = 20,     -- Picking车入库
    Out_Picking = 21,    -- Picking车出库   
    Move_Picking = 22,   -- Picking车移库 
    EmptyOut_Picking = 23,   -- Picking车空箱出库 
    CountOut_Picking = 24,   -- Picking车盘点出库
    TallyOut_Picking = 25    -- Picking车理货出库            
})


-- [Pre_Alloc_Container/预分配容器]状态
PAC_STATE = lua.MakeConstantTable({ 
    -- Pre_Alloc_Container 中的 N_B_STATE 值
    InStock = 0,                -- 未出库
    Outbound = 1,               -- 出库中
    Arrive_Station = 2,         -- 到站台
    PalletOK = 3,               -- 码盘完成
    Inbound = 4,                -- 入库中
    Finish = 5,                 -- 完成
    Cancel = 6,                 -- 取消
    Error = 7                   -- 错误
})

-- [Pre_Alloc_CNTR_Detail/预分配容器]状态
PAC_DETAIL_STATE = lua.MakeConstantTable({ 
    -- Pre_Alloc_CNTR_Detail 中的 N_B_STATE 值
    None = 0,                -- 未执行
    Palletizing = 1,         -- 码盘
    PalletizingOK = 2,       -- 码盘完成
    Cancel = 3               -- 取消
})

-- [Outbound_Order/出库单]状态
-- N_B_STATE
OUTBOUND_ORDER_STATE = lua.MakeConstantTable({ 
    -- Outbound_Order 中的 N_B_STATE 值
    Unalloc = 0,                -- 未配货
    InAlloc = 1,                -- 配货中
    AllocOK = 2,                -- 配货完成
    OP_Star = 3,                -- 开始出库
    OutOK = 4,                 -- 完成
    Error = 5,                  -- 错误
    Paused = 6,                 -- 暂停
    On_Cancel = 7,              -- 取消中
    Cancel = 8,                 -- 取消
    CancelErr = 9,               -- 取消失败
    Finish = 10                  -- 完成
})
-- N_OOS_RULE 缺件处理规则
OOS_RULE = lua.MakeConstantTable({ 
    -- Outbound_Order 中的 N_OOS_RULE 缺件处理规则
    None = 0,                 -- 无规则
    FullShipmentRequired = 1, -- 必须齐套才出库
    AllowPartialShipment = 2  -- 允许缺件出库
})  

-- N_ERR_CODE 错误码
OO_ERR = lua.MakeConstantTable({ 
    -- Outbound_Order 中的 N_ERR_CODE 值
    NoStation = 100,              -- 没有可出库站台
})

-- N_OSA_STATE
OSA_STATE = lua.MakeConstantTable({ 
    -- Outbound_Order 中的 N_OSA_STATE 站台分配状态
    None = 0,               -- 没有分配出库站台
    AllocStation = 1,       -- 已经分配了出库站台
    Finish = 2              -- 完成所以配盘的站台分配
})

-- [Distribution_CNTR/配盘容器]状态
DIST_CNTR_STATE = lua.MakeConstantTable({ 
    -- Distribution_CNTR 中的 N_B_STATE 值
    None = 0,                -- 未配货
    PrePickingOK = 1,        -- 配货完成
    Out = 2,                 -- 出库中
    OutOK = 3,               -- 出库完成
    PickingOK = 4,           -- 拣货完成
    Back = 5,                -- 回库
    Finish = 6,              -- 完成
    Error = 7,               -- 错误
    Cancel  = 8,             -- 取消
    GoBackErr = 9,           -- 回库出错
    WaitBack = 10            -- 待回库
})

-- [Distribution_CNTR_Detail/配盘明细]状态
DC_DETAIL_STATE = lua.MakeConstantTable({ 
    -- Distribution_CNTR_Detail 中的 N_B_STATE 值
    None = 0,                -- 不可执行
    CanDoPicking = 1,        -- 可执行分拣
    PickingOK = 2,           -- 完成分拣
    Cancel  = 3              -- 取消
})

-- [Picking_CNTR/配盘明细]状态
PICKING_CNTR_STATE = lua.MakeConstantTable({ 
    -- Picking_CNTR 中的 N_B_STATE 值
    None = 0,
    WaitPicking = 1,           -- 待拣货
    PickingOK = 10             -- 拣货完成
})

--///////////////////////////////////////////////////////
--条件判断操作符号
CONDITION_SYMBOL = lua.MakeConstantTable({ 
    Equals = "=",                -- 等于
    Greater = ">",               -- 大于
    Less = "<",                  -- 小于
    LessOrEquals = "<=",         -- 小于等于
    GreaterOrEquals = ">=",      -- 大于等于
    NotEquals = "!=",            -- 不等于
    Include = "%",               -- 包含
    NotInclude = "!%",           -- 不包含
    IsEmpty = "null",            -- 为空
    NotEmpty = "notnull",        -- 不为空
    FrontInclude = "0%",         -- 前面有
    BehindInclude = "%0"         -- 后面有
})

-- [Area/库区类型]
AREA_TYPE = lua.MakeConstantTable({ 
    -- Area 中的 N_TYPE 值
    Storage_Area = 1,           -- 存储区
    Receiving_Area = 2,         -- 收货区
    Inspection_Area = 3,        -- 检验区
    Putaway_Area = 4,           -- 上架区
    Batch_Picking_Area = 5,     -- 播种区
    Picking_Area = 6,           -- 分拣区
    TransPoint_Area = 7,        -- 接驳区
    OnRoad_Area=8               -- 在途区
})

AREA_TYPE_NAME = {
    ["存储区"] = 1,
    ["收货区"] = 2,
    ["检验区"] = 3,
    ["上架区"] = 4,
    ["播种区"] = 5,
    ["分拣区"] = 6,
    ["接驳区"] = 7,
    ["在途区"] = 8,
}

-- [Location_Transfer/移库单]状态
LT_STATE = lua.MakeConstantTable({ 
    -- Location_Transfer 中的 N_B_STATE 值
    Wait = 0,            -- 作业未启动
    Run = 1,             -- 作业启动
    Finish = 2,          -- 完成
    Error = 3            -- 错误
})

-- [Inbound_Palletization/移库单]状态
INB_PALLET_STATE = lua.MakeConstantTable({ 
    -- Inbound_Palletization 中的 N_B_STATE 值
    Pallet  = 10,            -- 码盘中
    PalletFinish = 11,       -- 码盘完成（没和货位绑定）
    WaitIn = 12,             -- 等待入库（和货位已经绑定）
    Inbound = 20,            -- 入库
    Finish = 30,             -- 完成
    Cancel = 40,             -- 取消
    Error = 50               -- 错误
})

-- 码盘状态名称中英文
INB_PALLET_STATE_NAME_EN = {
    [INB_PALLET_STATE.Pallet] = "Pallet",
    [INB_PALLET_STATE.PalletFinish] = "PalletFinish",
    [INB_PALLET_STATE.WaitIn] = "WaitIn",
    [INB_PALLET_STATE.Inbound] = "Inbound",
    [INB_PALLET_STATE.Finish] = "Finish",
    [INB_PALLET_STATE.Cancel] = "Cancel",
    [INB_PALLET_STATE.Error] = "Error"
}

INB_PALLET_STATE_NAME_CN = {
    [INB_PALLET_STATE.Pallet] = "码盘中",
    [INB_PALLET_STATE.PalletFinish] = "码盘完成",
    [INB_PALLET_STATE.WaitIn] = "等待入库",
    [INB_PALLET_STATE.Inbound] = "入库中",
    [INB_PALLET_STATE.Finish] = "完成",
    [INB_PALLET_STATE.Cancel] = "取消",
    [INB_PALLET_STATE.Error] = "错误"
}

-- [IW_Process/库内作业流程]
-- N_TYPE 值
IWP_TYPE = lua.MakeConstantTable({ 
    Count  = 1,             -- 盘点
    Specific = 2,           -- 指定出库
    Tally = 3,              -- 理货
    Preservation = 4,       -- 养护
    Transfer = 5            -- 移库
})

-- N_B_STATE 值
IWP_STATE = lua.MakeConstantTable({ 
    Wait  = 0,             -- 等待
    Run = 1,               -- 执行
    Finish = 2,            -- 完成
    Error = 3,             -- 错误
    Paused = 6,            -- 暂停
    OnCancel = 7,          -- 取消中下·
    Cancel = 8,            -- 取消
    CancelErr = 9,         -- 取消失败  
    OnPlan = 10,           -- 规划中
    PlanOk = 11,           -- 规划完成
    PlanErr = 12           -- 规划失败
})

-- [Container/容器]
-- N_EMPTY_FULL 值
EMPTY_FULL = lua.MakeConstantTable({ 
    Empty  = 0,             -- 空
    NotEmpty = 1,           -- 有货
    Full = 2                -- 满
})

--[Outbound_Cancel_ProcDetail]
-- N_PROC_TYPE 值
OCP_TYPE = lua.MakeConstantTable({ 
    Cancel_DC  = 1,             -- 配盘取消
    Cancel_OP = 2,              -- 作业取消
    Cancel_Picking = 3,         -- 分拣取消
    Return_Goods = 4            -- 还货入库
})

-- N_B_STATE 值
OCP_STATE = lua.MakeConstantTable({ 
    Wait  = 0,             -- 待处理
    OnProce = 1,           -- 处理中
    Finish = 2,            -- 完成
    Error = 3              -- 错愕
})

--[[INV_Transfer_Anomaly]]
-- N_B_STATE 值
ITA_STATE = lua.MakeConstantTable({ 
    Wait  = 0,             -- 待处理
    Finish = 1,            -- 完成
    Error = 2              -- 错愕
})
-- N_PROC_STATE
ITA_PROC_STATE = lua.MakeConstantTable({ 
    None  = 0,             -- 待处理
    Success = 1,           -- 成功
    Fail = 2               -- 错失败愕
})

--[[Machine_Station]]
-- N_CUR_OP_TYPE 值 站台的作业类型
STATION_OP_TYPE = lua.MakeConstantTable({ 
    None  = 0,              -- 无
    Putaway = 1,            -- 上架
    Picking = 2,            -- 拣货
    Count = 3,              -- 盘点
    Replenishment = 4,      -- 移库下架
    Tally = 5               -- 理货
})

-- N_OP_MODEL 值 站台作业模式
STATION_OP_MODEL = lua.MakeConstantTable({ 
    None  = 0,              -- 无
    Single = 1,             -- 单一作业模式
    Mixed = 2,              -- 混合作业模式
})

--[[Tally_Detail]]
-- N_B_STATE 值 站台的作业类型
TALLY_DETAIL_STATE = lua.MakeConstantTable({ 
    Wait  = 0,              -- 无
    Run = 1,                -- 可执行
    Finish = 2,             -- 完成
})

--[[IWP_Container]]
-- N_B_STATE 值 
IWPC_STATE = lua.MakeConstantTable({ 
    Wait  = 0,              -- 等待
    Lock = 1,               -- 加锁,可执行
    Out = 2,                -- 出库中
    OutOK = 3,              -- 出库完成/可以执行相应的库内管理作业
    TaskFinish = 4,         -- 执行业务完成
    GoBack = 5,             -- 回库
    Finish = 6,             -- 完成
    Error = 7,              -- 错误
    Cancel = 8,             -- 取消
    GoBackErr = 9,          -- 回库失败
    PreLock = 10,           -- 预加锁
})

--[[IWP_Range]]
-- N_RANGE_TYPE 值 
IWP_RANGE_TYPE = lua.MakeConstantTable({ 
    Location  = 0,          -- 货位
    Goods = 1,              -- 货品
    Container = 2,          -- 容器
})

--[[Count_Plan]]
-- N_TYPE 盘点乐西 
COUNT_TYPE = lua.MakeConstantTable({ 
    Cycle_Count = 1,          -- 全盘
    Bin_Accuracy_Audit = 2,   -- 动碰
    Spot_Count = 3,           -- 抽盘
})

--[[INV_Transfer_Anomaly]]
-- N_ANOMALY_TYPE 异常原因 
N_ANOMALY_TYPE = lua.MakeConstantTable({ 
    Barcode_Error = 1,          -- 条码错误
    Expiry_Date_Error = 2,   -- 有效期错误
    Package_Damaged = 3,           -- 包装损坏
    Short_shipped = 4,          -- 实物短缺
    System_Error = 5,          -- 系统错误
    Unchecked = 6,             -- 未检查
    UOM_error = 7,             -- 单位错误
    Quality_Error = 8,         -- 质量异常
    Other = 9                   -- 其它
})

ANOMALY_TYPE_EN = {
    [N_ANOMALY_TYPE.Barcode_Error] = "Barcode_Error",
    [N_ANOMALY_TYPE.Expiry_Date_Error] = "Expiry_Date_Error",
    [N_ANOMALY_TYPE.Package_Damaged] = "Package_Damaged",
    [N_ANOMALY_TYPE.Short_shipped] = "Short_shipped",
    [N_ANOMALY_TYPE.System_Error] = "System_Error",
    [N_ANOMALY_TYPE.Unchecked] = "Unchecked",
    [N_ANOMALY_TYPE.UOM_error] = "UOM_error",
    [N_ANOMALY_TYPE.Quality_Error] = "Quality_Error",
    [N_ANOMALY_TYPE.Other] = "Other",
}
ANOMALY_TYPE_CN = {
    [N_ANOMALY_TYPE.Barcode_Error] = "条码错误",
    [N_ANOMALY_TYPE.Expiry_Date_Error] = "有效期错误",
    [N_ANOMALY_TYPE.Package_Damaged] = "包装损坏",
    [N_ANOMALY_TYPE.Short_shipped] = "实物缺货",
    [N_ANOMALY_TYPE.System_Error] = "系统错误",
    [N_ANOMALY_TYPE.Unchecked] = "未检查",
    [N_ANOMALY_TYPE.UOM_error] = "单位错误",
    [N_ANOMALY_TYPE.Quality_Error] = "质量异常",
    [N_ANOMALY_TYPE.Other] = "其它",
}

--[[Outbound_Wave]]
-- N_B_STATE 出库波次状态 
OW_STATE = lua.MakeConstantTable({ 
    Unalloc = 0,          -- 未配货
    InAlloc = 1,          -- 配货中
    AllocOK = 2,          -- 配货完成
    OP_Star = 3,          -- 作业中
    OutOK = 4,            -- 出库完成
    Error = 5,            -- 错误
    Paused = 6,           -- 暂停
    On_Cancel = 7,        -- 取消中   
    Cancel = 8,           -- 取消
    CancelErr = 9,        -- 取消失败
    Finish = 10 
})

--[[INV_Reservation]]
-- N_B_STATE 预留单状态 
INV_RESV_STATE = lua.MakeConstantTable({ 
    Alloc = 0,           -- 预占中
    Locked = 1,          -- 已锁定
    Cancel = 2,          -- 取消
    Release = 3,         -- 释放
})

INV_RESV_STATE_CN = {
    [INV_RESV_STATE.Alloc] = "预占中",
    [INV_RESV_STATE.Locked] = "已锁定",
    [INV_RESV_STATE.Cancel] = "取消",
    [INV_RESV_STATE.Release] = "释放",
}