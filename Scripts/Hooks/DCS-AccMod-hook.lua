
status, result =  pcall(function() local dcsSr=require('lfs');dofile(dcsSr.writedir()..[[Mods\Services\DCS-AccWidg\Scripts\DCS-SRS-AccMod.lua]]); end,nil) 
 if not status then
 	net.log(result)
 end