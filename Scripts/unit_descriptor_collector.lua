-- DCS Unit Descriptor Collector
-- Spawns units, gets their descriptors via getDesc(), and saves to a loadable Lua file

local unitDatabase = {}

-- Unit categories from the provided data
local unitData = {
    ["Ground Units"] = {
        category = "Cars",
        subcategory = "Car",
        units = {
            "1L13 EWR", "2B11 mortar", "2S6 Tunguska", "55G6 EWR", "5p73 s-125 ln", "AAV7", "AA8", "ATMZ-5", 
            "ATZ-10", "ATZ-5", "ATZ-60_Maz", "ATZ-60_TANK", "Blitz_36-6700A", "BMD-1", "BMP-1", "BMP-2", 
            "BMP-3", "BRDM-2", "BTR-60", "BTR-70", "BTR-82A", "BTR-80", "BTR_D", "Bedford_MWD", "Boxcartrinity", 
            "Bunker", "CCKW_353", "Centaur_IV", "Challenger2", "Chieftain_mk3", "Coach a passenger", 
            "Coach a platform", "Coach a tank blue", "Coach a tank yellow", "Coach cargo", "Coach cargo open", 
            "Cobra", "Cromwell_IV", "DR_50Ton_Flat_Wagon", "DRG_Class_86", "Daimler_AC", "Dog Ear radar", 
            "ES44AH", "Electric locomotive", "FPS-117", "FPS-117 Dome", "FPS-117 ECS", "GAZ-3307", "GAZ-3308", 
            "GAZ-66", "Gepard", "German_covered_wagon_G10", "German_tank_wagon", "Grad-URAL", "Grad_FDDM", 
            "HQ-7_LN_SP", "HQ-7_STR_SP", "HL_B8M1", "HL_DSHK", "HL_KORD", "HL_ZU-23", "HEMTT TFFT", 
            "HEMTT_C-RAM_Phalanx", "Hawk cwar", "Hawk ln", "Hawk pcp", "Hawk sr", "Hawk tr", 
            "Horch_901_typ_40_kfz_21", "Hummer", "IKARUS Bus", "Igla manpad INS", "Infantry AK", 
            "Infantry AK Ins", "Infantry AK ver2", "Infantry AK ver3", "JTAC", "KAMAZ Truck", "KS-19", 
            "KrAZ6322", "Kub 1S91 str", "Kub 2P25 ln", "LAV-25", "LAZ Bus", "Land_Rover_101_FC", 
            "Land_Rover_109_S3", "Leclerc", "LeFH_18-40-105", "Leopard-2", "Leopard-2A5", "Leopard1A3", 
            "LiAZ Bus", "Locomotive", "M 818", "M-1 Abrams", "M-109", "M-113", "M-2 Bradley", "M-60", 
            "M10_GMC", "M12_GMC", "M1043 HMMWV Armament", "M1045 HMMWV TOW", "M1097 Avenger", 
            "M1126 Stryker ICV", "M1128 Stryker MGS", "M1134 Stryker ATGM", "M1A2C_SEP_V3", "M2A1_halftrack", 
            "M30_CC", "M45_Quadmount", "M48 Chaparral", "M4_Sherman", "M4A4_Sherman_FF", "M4_Tractor", 
            "M6 Linebacker", "M78 HEMTT Tanker", "M8_Greyhound", "MAZ-6303", "MCV-80", "MLRS", "MLRS FDDM", 
            "MTLB", "Marder", "MaxxPro_MRAP", "Merkava_Mk4", "NASAMS_Command_Post", "NASAMS_LN_B", 
            "NASAMS_LN_C", "NASAMS_Radar_MPQ64F1", "Osa 9A33 ln", "PLZ05", "PT_76", "Patriot AMG", 
            "Patriot ECS", "Patriot EPP", "Patriot cp", "Patriot ln", "Patriot str", "Predator GCS", 
            "Predator TrojanSpirit", "QF_37_AA", "RLS_19J6", "RPC_5N62V", "Roland ADS", "Roland Radar", 
            "S-200_Launcher", "S-300PS 40B6M tr", "S-300PS 40B6MD sr", "S-300PS 40B6MD sr_19J6", 
            "S-300PS 54K6 cp", "S-300PS 5H63C 30H6_tr", "S-300PS 5P85C ln", "S-300PS 5P85D ln", 
            "S-300PS 64H6E sr", "S-60_Type59_Artillery", "S_75M_Volhov", "S_75_ZIL", "S_75_Zil_Trailer", 
            "SA-11 Buk CC 9S470M1", "SA-11 Buk LN 9A310M1", "SA-11 Buk SR 9S18M1", "SA-18 Igla comm", 
            "SA-18 Igla manpad", "SA-18 Igla-S comm", "SA-18 Igla-S manpad", "SAU 2-C9", "SAU Akatsia", 
            "SAU Gvozdika", "SAU Msta", "SKP-11", "SNR_75V", "SON_9", "Sandbox", "Scud_B", "Silkworm_SR", 
            "Smerch", "Smerch_HE", "Soldier AK", "Soldier M249", "Soldier M4", "Soldier M4 GRG", 
            "Soldier RPG", "Soldier stinger", "SpGH_Dana", "Stinger comm", "Stinger comm dsr", 
            "Strela-1 9P31", "Strela-10M3", "Stug_III", "Sd_Kfz_251", "SK_C_28_naval_gun", "T-34-85", 
            "T-55", "T-72B", "T-72B3", "T-80UD", "T-90", "T155_Firtina", "TPZ", "TZ-22_KrAZ", "TZ-22_TANK", 
            "Tankcartrinity", "Tetrarch", "Tigr_233036", "Tor 9A331", "Trolley bus", "UAZ-469", 
            "US Carrier Technician", "US Carrier Technician Static Brown", "US Carrier Technician Static Green", 
            "US Carrier Technician Static Purple", "US Carrier Technician Static Red", 
            "US Carrier Technician Static White", "US Carrier Technician Static Yellow", "Ural ATsP-6", 
            "Ural-375", "Ural-375 PBU", "Ural-375 ZU-23", "Ural-375 ZU-23 Insurgent", "Ural-4320 APA-5D", 
            "Ural-4320-31", "Ural-4320T", "Uragan_BM-27", "VAB_Mephisto", "VAZ Car", "Vulcan", "Wellcarnsc", 
            "Willys_MB", "ZBD04A", "ZIL-131 KUNG", "ZIL-135", "ZIL-4331", "ZSU-23-4 Shilka", "ZSU_57_2", 
            "ZTZ96B", "ZU-23 Closed Insurgent", "ZU-23 Emplacement", "ZU-23 Emplacement Closed", 
            "ZU-23 Insurgent", "ZiL-131 APA-80", "bofors40", "fire_control", "generator_5i57", 
            "hl_launcher", "house1arm", "house2arm", "houseA_arm", "hy_launcher", "leopard-2A4", 
            "leopard-2A4_trs", "outpost", "outpost_road", "outpost_road_l", "outpost_road_r", 
            "p-19 s-125 sr", "rapier_fsa_blindfire_radar", "rapier_fsa_launcher", 
            "rapier_fsa_optical_tracker_unit", "snr s-125 tr", "soldier_mauser98", "soldier_wwii_br_01", 
            "tt_B8M1", "tt_DSHK", "tt_KORD", "tt_ZU-23"
        }
    },
    ["Fixed-Wing Aircraft"] = {
        category = "Planes",
        subcategory = "Plane",
        units = {
            "A-10A", "A-10C", "A-10C_2", "AJS37", "AV8BNA", "An-26B", "An-30M", "B-17G", "B-1B", "B-52H", 
            "Bf-109K-4", "C-130", "C-17A", "C-47", "Christen Eagle II", "E-2C", "E-3A", "F-117A", 
            "F-14A-135-GR", "F-14A-95-GR", "F-14B", "F-15C", "F-15E", "F-16A", "F-16A MLU", "F-16C bl.50", 
            "F-16C bl.52d", "F-16C_50", "F-5E", "F-5E-3", "F-5E-3_FC", "F-86F Sabre", "F-86F_FC", 
            "F/A-18A", "F/A-18C", "FA-18C_hornet", "FW-190A8", "FW-190D9", "FULCRUM-LAB", "Hawk", "I-16", 
            "IL-76MD", "IL-78M", "J-11A", "JF-17", "KC-135", "KC130", "KC135MPRS", "KJ-2000", "L-39C", 
            "L-39ZA", "La-7", "MB-339A", "MB-339A/PAN", "MQ-9 Reaper", "M-2000C", "MiG-15bis", 
            "MiG-15bis_FC", "MiG-19P", "MiG-21Bis", "MiG-23MLD", "MiG-25PD", "MiG-25RBT", "MiG-27K", 
            "MiG-29A", "MiG-29G", "MiG-29S", "MiG-31", "Mirage 2000-5", "MosquitoFBMkVI", "P-47D-30", 
            "P-47D-30bl1", "P-47D-40", "P-51D", "P-51D-30-NA", "RQ-1A Predator", "S-3B", "S-3B Tanker", 
            "SpitfireLFMkIX", "SpitfireLFMkIXCW", "Su-17M4", "Su-24M", "Su-24MR", "Su-25", "Su-25T", 
            "Su-25TM", "Su-27", "Su-30", "Su-33", "Su-34", "TF-51D", "Tornado GR4", "Tornado IDS", 
            "Tu-142", "Tu-160", "Tu-22M3", "Tu-95MS", "WingLoong-I", "Yak-40", "Yak-52", 
            "F-16C (New Zealand entry)"
        }
    },
    ["Helicopters"] = {
        category = "Helicopters",
        subcategory = "Helicopter",
        units = {
            "AH-1W", "AH-64A", "AH-64D", "AH-64D_BLK_II", "CH-47D", "CH-53E", "Ka-27", "Ka-50", "Ka-50_3", 
            "Mi-24P", "Mi-24V", "Mi-26", "Mi-28N", "Mi-8MT", "OH-58D", "SA342L", "SA342Minigun", 
            "SA342Mistral", "SA342M", "SH-60B", "UH-1H", "UH-60A"
        }
    },
    ["Ships"] = {
        category = "Ships",
        subcategory = "Ship",
        units = {
            "ALBATROS", "BDK-775", "CVN_71", "CVN_72", "CVN_73", "CVN_75", "Dry-cargo ship-1", 
            "Dry-cargo ship-2", "ELNYA", "HandyWind", "Higgins_boat", "IMPROVED_KILO", "KILO", "KUZNECOW", 
            "LST_Mk2", "LHA_Tarawa", "La_Combattante_II", "MOLNIYA", "MOSCOW", "NEUSTRASH", "PERRY", 
            "PIOTR", "REZKY", "Schnellboot_type_S130", "Seawise_Giant", "Stennis", "TICONDEROG", 
            "Type_052B", "Type_052C", "Type_054A", "Type_071", "Type_093", "USS_Arleigh_Burke_IIa", 
            "USS_Samuel_Chase", "ZWEZDNY", "speedboat"
        }
    },
    ["Cargo"] = {
        category = "Cargo",
        subcategory = "Cargo",
        units = {
            "ammo_cargo", "barrels_cargo", "container_cargo", "f_bar_cargo", "fueltank_cargo", 
            "gbu_43b_airdrop", "iso_container", "iso_container_small", "m117_cargo", "oiltank_cargo", 
            "pipes_big_cargo", "pipes_small_cargo", "tetrapod_cargo", "trunks_long_cargo", 
            "trunks_small_cargo", "uh1h_cargo"
        }
    }
}

-- Utility function to serialize a table to a string
local function serializeTable(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0

    local tmp = string.rep(" ", depth)

    if name then
        tmp = tmp .. name .. " = "
    end

    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")

        for k, v in pairs(val) do
            tmp = tmp .. serializeTable(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end

        tmp = tmp .. string.rep(" ", depth) .. "}"
    elseif type(val) == "number" then
        tmp = tmp .. tostring(val)
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "\"[unknowndatatype:" .. type(val) .. "]\""
    end

    return tmp
end

-- Function to get unit descriptor by spawning it
local function getUnitDescriptor(unitTypeName, category)
    local success, result = pcall(function()
        -- For ground units, use coalition.addGroup
        -- For aircraft/helicopters, similar approach
        -- This is a template - actual spawning depends on DCS API context
        
        local spawnPos = {x = 0, y = 0, z = 0}  -- Neutral spawn position
        
        local groupData = {
            ["visible"] = false,
            ["taskSelected"] = true,
            ["hidden"] = true,
            ["units"] = {
                [1] = {
                    ["type"] = unitTypeName,
                    ["unitId"] = 9999,
                    ["skill"] = "Average",
                    ["x"] = spawnPos.x,
                    ["y"] = spawnPos.z,
                    ["name"] = "TempUnit_" .. unitTypeName,
                    ["heading"] = 0,
                }
            },
            ["y"] = spawnPos.z,
            ["x"] = spawnPos.x,
            ["name"] = "TempGroup_" .. unitTypeName,
            ["start_time"] = 0,
        }
        
        -- Determine coalition and country (neutral)
        local countryId = 0  -- Neutral
        local coalitionId = 0  -- Neutral
        
        -- Spawn the group based on category
        local group
        if category == "Planes" or category == "Helicopters" then
            group = coalition.addGroup(countryId, Group.Category.AIRPLANE, groupData)
            if category == "Helicopters" then
                groupData.category = Group.Category.HELICOPTER
                group = coalition.addGroup(countryId, Group.Category.HELICOPTER, groupData)
            end
        elseif category == "Ships" then
            groupData.category = Group.Category.SHIP
            group = coalition.addGroup(countryId, Group.Category.SHIP, groupData)
        elseif category == "Cargo" then
            -- Cargo is typically static objects
            local staticData = {
                ["type"] = unitTypeName,
                ["x"] = spawnPos.x,
                ["y"] = spawnPos.z,
                ["name"] = "TempStatic_" .. unitTypeName,
                ["heading"] = 0,
            }
            return coalition.addStaticObject(countryId, staticData):getDesc()
        else  -- Ground units
            groupData.category = Group.Category.GROUND
            group = coalition.addGroup(countryId, Group.Category.GROUND, groupData)
        end
        
        if group then
            local unit = group:getUnit(1)
            if unit then
                local desc = unit:getDesc()
                -- Clean up the spawned unit
                group:destroy()
                return desc
            end
        end
        
        return nil
    end)
    
    if success and result then
        return result
    else
        return {error = tostring(result), typeName = unitTypeName}
    end
end

-- Main collection function
local function collectUnitDescriptors()
    log.write("DCS Unit Descriptor Collector", log.INFO, "Starting unit descriptor collection...")
    
    for categoryName, categoryData in pairs(unitData) do
        log.write("DCS Unit Descriptor Collector", log.INFO, "Processing category: " .. categoryName)
        
        unitDatabase[categoryName] = {
            category = categoryData.category,
            subcategory = categoryData.subcategory,
            units = {}
        }
        
        for _, unitTypeName in ipairs(categoryData.units) do
            log.write("DCS Unit Descriptor Collector", log.INFO, "Getting descriptor for: " .. unitTypeName)
            
            local descriptor = getUnitDescriptor(unitTypeName, categoryData.category)
            
            unitDatabase[categoryName].units[unitTypeName] = {
                typeName = unitTypeName,
                descriptor = descriptor,
                timestamp = os.date("%Y-%m-%d %H:%M:%S")
            }
            
            -- Small delay to avoid overwhelming the system
            -- Note: In actual DCS scripting, timer.scheduleFunction might be better
        end
    end
    
    log.write("DCS Unit Descriptor Collector", log.INFO, "Collection complete. Saving to file...")
    
    -- Save the data
    saveUnitDatabase()
end

-- Function to save the database to a file
function saveUnitDatabase()
    local filePath = lfs.writedir() .. "Logs\\unit_descriptors.lua"
    
    local file = io.open(filePath, "w")
    if file then
        file:write("-- DCS Unit Descriptor Database\n")
        file:write("-- Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
        file:write("return " .. serializeTable(unitDatabase, nil, false, 0))
        file:close()
        
        log.write("DCS Unit Descriptor Collector", log.INFO, "Database saved to: " .. filePath)
        trigger.action.outText("Unit descriptor database saved to: " .. filePath, 30)
    else
        log.write("DCS Unit Descriptor Collector", log.ERROR, "Failed to open file for writing: " .. filePath)
        trigger.action.outText("ERROR: Failed to save unit descriptor database!", 30)
    end
end

-- Function to load the database from file
function loadUnitDatabase(filePath)
    filePath = filePath or (lfs.writedir() .. "Logs\\unit_descriptors.lua")
    
    local file = io.open(filePath, "r")
    if file then
        local content = file:read("*all")
        file:close()
        
        local loadedData = loadstring(content)
        if loadedData then
            return loadedData()
        else
            log.write("DCS Unit Descriptor Collector", log.ERROR, "Failed to parse database file")
            return nil
        end
    else
        log.write("DCS Unit Descriptor Collector", log.ERROR, "Failed to open file: " .. filePath)
        return nil
    end
end

-- Execution entry point
-- To run this script, call: collectUnitDescriptors()
-- To load saved data, call: local data = loadUnitDatabase()

-- Export functions for external use
return {
    collectUnitDescriptors = collectUnitDescriptors,
    saveUnitDatabase = saveUnitDatabase,
    loadUnitDatabase = loadUnitDatabase,
    unitData = unitData,
    unitDatabase = unitDatabase
}
