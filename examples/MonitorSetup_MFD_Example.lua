-- DCS AccMod - Example MonitorSetup Configuration for MFD Export
-- This file demonstrates how to export MFDs to virtual monitors
--
-- SETUP INSTRUCTIONS:
-- 1. Create 2 virtual monitors (800x800) using Virtual Display Driver
-- 2. Note their screen positions in Windows Display Settings
-- 3. Update the x/y coordinates below to match your virtual monitor positions
-- 4. Copy this file to: %USERPROFILE%\Saved Games\DCS\Config\MonitorSetup\
-- 5. Rename to match your aircraft (e.g., FA-18C.lua, F-16C_50.lua, A-10C_2.lua)
-- 6. Restart DCS
--
-- COORDINATE SYSTEM:
-- - (0, 0) is the top-left of your PRIMARY monitor
-- - x increases to the right
-- - y increases downward
-- - If virtual monitor 2 is at position (1920, 0), MFD viewport x should be 1920
--
-- AIRCRAFT-SPECIFIC NOTES:
-- - FA-18C: LEFT_MFCD, RIGHT_MFCD, AMPCD
-- - F-16C: LEFT_MFD, RIGHT_MFD
-- - A-10C: LEFT_MFCD, RIGHT_MFCD
-- - Adjust viewport indices and names per aircraft

_  = function(p)
    return {
        -- ===== PRIMARY DISPLAY (Main cockpit view) =====
        -- This is your main monitor where the 3D cockpit renders
        [1] = {
            x = 0,                  -- Starts at left edge of primary monitor
            y = 0,                  -- Starts at top edge
            width = 1920,           -- Full HD width (adjust to your monitor)
            height = 1080,          -- Full HD height (adjust to your monitor)
        },
        
        -- ===== LEFT MFD VIEWPORT =====
        -- Renders the left MFD/MFCD to virtual monitor
        -- CHANGE x/y to match your virtual monitor position!
        [2] = {
            -- VIRTUAL MONITOR POSITION
            -- Example: If virtual monitor is labeled "Display 2" at (1920, 0)
            x = 1920,               -- X position of virtual monitor (CHANGE THIS)
            y = 0,                  -- Y position of virtual monitor (CHANGE THIS)
            width = 800,            -- MFD resolution width
            height = 800,           -- MFD resolution height
            
            -- VIEWPORT CONFIGURATION
            viewDx = 0,             -- Horizontal view offset (0 = centered)
            viewDy = 0,             -- Vertical view offset (0 = centered)
            aspect = 1.0,           -- Aspect ratio (1.0 = square for MFD)
            
            -- UI CONFIGURATION
            UIMainView = {
                x = 0,
                y = 0,
                width = 800,
                height = 800
            }
        },
        
        -- ===== RIGHT MFD VIEWPORT =====
        -- Renders the right MFD/MFCD to virtual monitor
        -- CHANGE x/y to match your virtual monitor position!
        [3] = {
            -- VIRTUAL MONITOR POSITION
            -- Example: If virtual monitor is labeled "Display 3" at (2720, 0)
            x = 2720,               -- X position of virtual monitor (CHANGE THIS)
            y = 0,                  -- Y position of virtual monitor (CHANGE THIS)
            width = 800,            -- MFD resolution width
            height = 800,           -- MFD resolution height
            
            -- VIEWPORT CONFIGURATION
            viewDx = 0,
            viewDy = 0,
            aspect = 1.0,
            
            -- UI CONFIGURATION
            UIMainView = {
                x = 0,
                y = 0,
                width = 800,
                height = 800
            }
        },
        
        -- ===== OPTIONAL: CENTER MFD/AMPCD =====
        -- Uncomment this section if aircraft has a center display (FA-18C AMPCD, etc.)
        --[[
        [4] = {
            -- VIRTUAL MONITOR POSITION
            x = 3520,               -- X position of virtual monitor (CHANGE THIS)
            y = 0,                  -- Y position of virtual monitor (CHANGE THIS)
            width = 800,
            height = 800,
            viewDx = 0,
            viewDy = 0,
            aspect = 1.0,
            UIMainView = {
                x = 0,
                y = 0,
                width = 800,
                height = 800
            }
        },
        ]]--
    }
end

-- AIRCRAFT-SPECIFIC CONFIGURATIONS
-- Copy the appropriate section below and modify viewport names as needed

--[[
=== F/A-18C HORNET ===
Displays: LEFT_MFCD, RIGHT_MFCD, AMPCD
- Use viewports [2], [3], [4]
- All are 800x800 square displays
- AMPCD is center display

=== F-16C VIPER ===
Displays: LEFT_MFD, RIGHT_MFD
- Use viewports [2], [3]
- Both are 800x800 square displays
- No center display

=== A-10C WARTHOG ===
Displays: LEFT_MFCD, RIGHT_MFCD
- Use viewports [2], [3]
- Both are 600x600 square displays (adjust width/height to 600)
- No center display

=== AH-64D APACHE ===
Displays: PLT_LEFT_MPD, PLT_RIGHT_MPD, CPG_LEFT_MPD, CPG_RIGHT_MPD
- Pilot and Co-Pilot have separate displays
- Use 4 viewports for full export
- All are 800x800 square displays

=== MULTI-MONITOR TIPS ===
1. Use Windows Display Settings to find virtual monitor positions
2. Arrange virtual monitors far from main display to avoid mouse cursor issues
3. Virtual monitors can be positioned anywhere (negative coordinates work too)
4. Test with NVIDIA/AMD virtual super resolution if VDD has issues
5. Restart DCS after changing this file
]]--
