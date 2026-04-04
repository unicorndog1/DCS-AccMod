-- Test script for OpenXR UDP batching
-- Run with: lua test_openxr_udp.lua
-- Requires: LuaSocket (luarocks install luasocket)

local socket = require("socket")

-- Create UDP socket
local udp = socket.udp()
udp:settimeout(0)

local function sendPacket(packet)
    print("Sending: " .. packet:sub(1, 80) .. (string.len(packet) > 80 and "..." or ""))
    udp:sendto(packet, "127.0.0.1", 7779)
end

print("=== OpenXR UDP Batch Test ===\n")

-- Test 1: View config
print("Test 1: View configuration")
sendPacket("V,1.0000,1.7778,0,100.0000")
socket.sleep(0.1)

-- Test 2: Clear all
print("\nTest 2: Clear all circles")
sendPacket("A")
socket.sleep(0.1)

-- Test 3: Single circle (old format - backwards compatibility)
print("\nTest 3: Single circle (C format - backwards compatibility)")
sendPacket("C,0.5000,0.5000,0.0200,1.00,0.00,0.00,0.80,1,0.0012,1.00,0.00,0.00,0.95,TestUnit1")
socket.sleep(0.1)

-- Test 4: Batched circles (new format)
print("\nTest 4: Batched circles (B format - 5 circles)")
local batch = "B,5,"
    .. "0.3000,0.3000,0.0150,0.00,0.00,1.00,0.80,1,0.0009,0.00,0.00,1.00,0.95,Allied1;"
    .. "0.4000,0.4000,0.0150,0.00,0.00,1.00,0.80,1,0.0009,0.00,0.00,1.00,0.95,Allied2;"
    .. "0.6000,0.3000,0.0150,1.00,0.00,0.00,0.80,1,0.0009,1.00,0.00,0.00,0.95,Enemy1;"
    .. "0.7000,0.4000,0.0150,1.00,0.00,0.00,0.80,1,0.0009,1.00,0.00,0.00,0.95,Enemy2;"
    .. "0.5000,0.7000,0.0300,1.00,1.00,0.00,0.80,0,0.0018,1.00,1.00,0.00,0.95,ClosestUnit"
sendPacket(batch)
socket.sleep(0.1)

-- Test 5: Large batch (10 circles - max batch size)
print("\nTest 5: Large batch (B format - 10 circles)")
local largeBatch = "B,10,"
for i = 1, 10 do
    local x = (i - 1) * 0.1
    local y = 0.8
    local isAllied = (i % 2 == 0)
    local r = isAllied and 0.0 or 1.0
    local g = 0.0
    local b = isAllied and 1.0 or 0.0
    
    largeBatch = largeBatch 
        .. string.format("%.4f,%.4f,0.0100,%.2f,%.2f,%.2f,0.80,1,0.0006,%.2f,%.2f,%.2f,0.95,Unit%d", 
            x, y, r, g, b, r, g, b, i)
    
    if i < 10 then
        largeBatch = largeBatch .. ";"
    end
end
sendPacket(largeBatch)
socket.sleep(0.1)

-- Test 6: Mixed - clear then send batch
print("\nTest 6: Clear then batch (simulates frame update)")
sendPacket("A")
socket.sleep(0.05)
local mixedBatch = "B,3,"
    .. "0.2000,0.2000,0.0200,1.00,0.00,0.00,0.80,1,0.0012,1.00,0.00,0.00,0.95,Target1;"
    .. "0.5000,0.5000,0.0250,0.00,1.00,0.00,0.80,0,0.0015,0.00,1.00,0.00,0.95,Waypoint;"
    .. "0.8000,0.8000,0.0200,0.00,0.00,1.00,0.80,1,0.0012,0.00,0.00,1.00,0.95,Friendly"
sendPacket(mixedBatch)

print("\n=== Test Complete ===")
print("Check OpenXR layer log for parsing results:")
print("  %TEMP%\\DCS_AccMod_OpenXR.log")
print("\nExpected results:")
print("  - View config should be logged")
print("  - Test 3: 1 circle logged (C format)")
print("  - Test 4: 5 circles logged (batch)")
print("  - Test 5: 10 circles logged (batch)")
print("  - Test 6: 3 circles logged after clear")

udp:close()
