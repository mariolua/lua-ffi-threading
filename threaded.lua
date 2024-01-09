-- Import ffi library to use C data types and call functions in shared libraries
local ffi = require("ffi")

local string_match, string_len, string_gsub, string_gmatch, string_byte = string.match, string.len, string.gsub, string.gmatch, string.byte
local cast, typeof, ffi_string = ffi.cast, ffi.typeof, ffi.string

local pGetModuleHandle_sig = client.find_signature("engine.dll", "\xFF\x15\xCC\xCC\xCC\xCC\x85\xC0\x74\x0B") or error("pGetModuleHandle_sig not found")
local pGetProcAddress_sig = client.find_signature("engine.dll", "\xFF\x15\xCC\xCC\xCC\xCC\xA3\xCC\xCC\xCC\xCC\xEB\x05") or error("pGetProcAddress_sig not found")

-- Find the jmp ecx instruction in engine.dll or throw an error if not found
local jmp_ecx = client.find_signature("engine.dll", "\xFF\xE1") or error("jmp_ecx not found")

-- Initialize the GetProcAddress function using the previously found address and jmp instruction
local pGetProcAddress = cast("uint32_t**", cast("uint32_t", pGetProcAddress_sig) + 2)[0][0]
local fnGetProcAddress = cast("uint32_t(__fastcall*)(unsigned int, unsigned int, uint32_t, const char*)", jmp_ecx)

-- Initialize the GetModuleHandle function using the previously found address and jmp instruction
local pGetModuleHandle = cast("uint32_t**", cast("uint32_t", pGetModuleHandle_sig) + 2)[0][0]
local fnGetModuleHandle = cast("uint32_t(__fastcall*)(unsigned int, unsigned int, const char*)", jmp_ecx)

-- Function to bind a procedure to a module and function name with specified type definition
local function proc_bind(module_name, function_name, typedef)
    local ctype = typeof(typedef)
    local module_handle = fnGetModuleHandle(pGetModuleHandle, 0, module_name)
    local proc_address = fnGetProcAddress(pGetProcAddress, 0, module_handle, function_name)
    local call_fn = cast(ctype, jmp_ecx)

    -- Returns a function that can call the bound procedure with arguments
    return function(...)
        return call_fn(proc_address, 0, ...)
    end
end

-- Define Windows API threading data types and functions using ffi cdef´
ffi.cdef[[
    typedef void* HANDLE;
    typedef unsigned long DWORD;
    typedef int BOOL;
    typedef DWORD (__stdcall *LPTHREAD_START_ROUTINE) (void*);
    typedef void* LPVOID;

    HANDLE CreateThread(
        LPVOID lpThreadAttributes,
        DWORD dwStackSize,
        LPTHREAD_START_ROUTINE lpStartAddress,
        LPVOID lpParameter,
        DWORD dwCreationFlags,
        DWORD* lpThreadId
    );
    DWORD WaitForSingleObject(
        HANDLE hHandle,
        DWORD dwMilliseconds
    );
    BOOL CloseHandle(
        HANDLE hObject
    );
    typedef struct _SECURITY_ATTRIBUTES {
        DWORD nLength;
        LPVOID lpSecurityDescriptor;
        BOOL bInheritHandle;
    } SECURITY_ATTRIBUTES, *PSECURITY_ATTRIBUTES;
    
    DWORD GetLastError();
]]

-- Bind the Windows API functions for threading to Lua functions using proc_bind
local CreateThread = proc_bind("kernel32.dll", "CreateThread", "void*(__fastcall*)(uint32_t, uint32_t, void*, uint32_t, void*, void*, uint32_t, void*)")
local WaitForSingleObject = proc_bind("kernel32.dll", "WaitForSingleObject", "uint32_t(__fastcall*)(uint32_t, uint32_t, void*, uint32_t)")
local CloseHandle = proc_bind("kernel32.dll", "CloseHandle", "int32_t(__fastcall*)(uint32_t, uint32_t, void*)")
local TerminateThread = proc_bind("kernel32.dll", "TerminateThread", "bool(__fastcall*)(unsigned int, unsigned int, void*, unsigned long)")
local GetLastError = proc_bind("kernel32.dll", "GetLastError", "uint32_t(__fastcall*)(uint32_t)")
-- local Sleep = proc_bind("kernel32.dll", "Sleep", "void(__fastcall*)(unsigned int, unsigned int, unsigned long)")

-- Thread class to encapsulate thread-related functionalities
local Thread = {}
Thread.__index = Thread

-- Constructor for Thread class
function Thread.new()
    local self = setmetatable({}, Thread)
    self.shouldTerminate = ffi.new("bool[1]", false)
    self.threadHandle = nil
    
    -- Set a callback to stop the thread on shutdown event
	client.set_event_callback('shutdown', function() self:stop() end)
    return self
end

-- Destructor for Thread class, stops the thread when garbage collected
function Thread:__gc()
    self:stop()
end

-- Method to start the thread with specified function and arguments
function Thread:start(call, args)
    self.callWrapper = (args and function()
        local succ, err = pcall(call, args)
        if not succ then
            print('[Error] ' .. tostring(err))
        end
        return 0
    end or function()
        local succ, err = pcall(call)
        if not succ then
            print('[Error] ' .. tostring(err))
        end
        return 0
    end)
    
    local sec_attr = ffi.new("SECURITY_ATTRIBUTES")
    sec_attr.nLength = ffi.sizeof("SECURITY_ATTRIBUTES")
    sec_attr.bInheritHandle = 1

    self.threadFunc = ffi.cast("LPTHREAD_START_ROUTINE", self.callWrapper)
    self.threadHandle = CreateThread(sec_attr, 0, self.threadFunc, nil, 0, nil)
    if self.threadHandle == nil then
        local err_code = GetLastError()
        print("Failed to create thread! Error code: " .. tostring(err_code))
        return
    end
end

-- Method to stop the thread
function Thread:stop()
    if self.threadHandle ~= nil then
        self.shouldTerminate[0] = true
        WaitForSingleObject(self.threadHandle, 0xFFFFFFFF)
        TerminateThread(self.threadHandle, 0)
        CloseHandle(self.threadHandle)
        self.threadHandle = nil
        print("Thread terminated")
    end
end

return Thread
