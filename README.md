# Lua FFI Threading
# Lua Script for Gamesense CS:GO Cheat

Example:
```lua
-- Create a new thread and start it with specified function
-- In this case it is an infinite loop, which should freeze csgo if it would not be threaded
-- The loop writes "test" to a file and prints it

local function example_function()
    while true do
        local str = readfile("thread.txt") or ""
        writefile("thread.txt", str .. "test")
        print(str .. "test")
        -- Sleep(100) -- sleep for 0.1 second
    end
end

local myThread = Thread.new()
myThread:start(example_function)
```
