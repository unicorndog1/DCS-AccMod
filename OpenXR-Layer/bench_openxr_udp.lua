-- bench_openxr_udp.lua - synthetic UDP stress harness for the OpenXR layer.
--
-- Usage (standalone, with luasocket installed):
--   lua bench_openxr_udp.lua [scenario] [duration_sec] [count] [hz]
--
-- Scenarios:
--   idle       - send only V config + clear; no circles. Validates baseline.
--   static_50  - 50 stationary circles at 30 Hz.
--   jitter_100 - 100 circles, sub-pixel jitter, at 30 Hz.
--   custom     - use [count] [hz] from CLI args.
--
-- The script writes ACCMOD_BENCH log lines to stdout and asks the layer to
-- flush perf snapshots via the 'P' command at the start, midpoint, and end.

local socket = require("socket")

local args = arg or {}
local scenario   = args[1] or "static_50"
local duration   = tonumber(args[2]) or 30
local cliCount   = tonumber(args[3]) or nil
local cliHz      = tonumber(args[4]) or nil

local presets = {
    idle       = { count = 0,   hz = 5,  jitter = 0 },
    static_50  = { count = 50,  hz = 30, jitter = 0 },
    jitter_100 = { count = 100, hz = 30, jitter = 0.002 },
    custom     = { count = cliCount or 50, hz = cliHz or 30, jitter = 0.001 },
}

local cfg = presets[scenario] or presets.static_50
if cliCount then cfg.count = cliCount end
if cliHz    then cfg.hz    = cliHz    end

local PORT = 7779
local HOST = "127.0.0.1"
local udp = socket.udp()
udp:settimeout(0)

local function send(packet)
    udp:sendto(packet, HOST, PORT)
end

print(string.format("ACCMOD_BENCH start scenario=%s count=%d hz=%d duration=%ds jitter=%.4f",
    scenario, cfg.count, cfg.hz, duration, cfg.jitter))

-- View config (~16:9, ~70 deg vertical FOV, distance=100 to match Lua sender).
local tanHalfFov = math.tan(70 * math.pi / 180 / 2)
local aspect     = 16 / 9
send(string.format("V,%.4f,%.4f,0,100.0000", tanHalfFov, aspect))

-- Build base circle layout: even grid in [0.1,0.9]x[0.1,0.9].
local circles = {}
do
    local n = cfg.count
    if n > 0 then
        local cols = math.ceil(math.sqrt(n))
        local rows = math.ceil(n / cols)
        local idx = 0
        for r = 0, rows - 1 do
            for c = 0, cols - 1 do
                idx = idx + 1
                if idx > n then break end
                local x = 0.1 + (c + 0.5) * (0.8 / cols)
                local y = 0.1 + (r + 0.5) * (0.8 / rows)
                local isAllied = (idx % 2 == 0)
                circles[idx] = {
                    x = x, y = y,
                    r = isAllied and 0.0 or 1.0,
                    g = 0.0,
                    b = isAllied and 1.0 or 0.0,
                    a = 0.8,
                    radius = 0.012,
                    thickness = 0.0007,
                    label = string.format("U%d", idx),
                }
            end
        end
    end
end

-- Send loop.
local interval = (cfg.hz > 0) and (1.0 / cfg.hz) or 1.0
local startT = socket.gettime()
local nextSend = startT
local mid = startT + duration / 2
local frame = 0
local sentSnapshotMid = false

send("P") -- start-of-run snapshot

while true do
    local t = socket.gettime()
    if t >= startT + duration then break end
    if t >= nextSend then
        nextSend = nextSend + interval
        frame = frame + 1

        if cfg.count > 0 then
            -- Clear and rebuild batch.
            send("A")

            -- Send circles in batches of 10 (matches BATCH_SIZE in Lua sender).
            local BATCH = 10
            local batch = {}
            for i = 1, #circles do
                local c = circles[i]
                local x = c.x
                local y = c.y
                if cfg.jitter > 0 then
                    x = x + (math.random() - 0.5) * cfg.jitter * 2
                    y = y + (math.random() - 0.5) * cfg.jitter * 2
                end
                batch[#batch + 1] = string.format(
                    "%.4f,%.4f,%.4f,%.2f,%.2f,%.2f,%.2f,1,%.4f,%.2f,%.2f,%.2f,%.2f,%s",
                    x, y, c.radius, c.r, c.g, c.b, c.a,
                    c.thickness, c.r, c.g, c.b, 0.0, c.label)
                if #batch >= BATCH then
                    send(string.format("B,%d,%s", #batch, table.concat(batch, ";")))
                    batch = {}
                end
            end
            if #batch > 0 then
                send(string.format("B,%d,%s", #batch, table.concat(batch, ";")))
            end
        end

        if (frame % math.max(1, cfg.hz)) == 0 then
            local elapsed = t - startT
            print(string.format("ACCMOD_BENCH tick frame=%d elapsed=%.1fs circles=%d hz=%d",
                frame, elapsed, cfg.count, cfg.hz))
        end
    end

    if not sentSnapshotMid and t >= mid then
        send("P")
        sentSnapshotMid = true
    end

    socket.sleep(0.001)
end

send("P") -- end-of-run snapshot
send("A") -- leave cleared
print(string.format("ACCMOD_BENCH done scenario=%s frames=%d", scenario, frame))
udp:close()
