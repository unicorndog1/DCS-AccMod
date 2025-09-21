This simple mod allows you to create modular windows that display instrument data in an adjustable window

INSTALLATION: Copy the contents of the ZIP file to the DCS saved games folder (X:\Users\...\Saved Games\DCS)

USAGE:
- Ctrl+Shift+1 adjusts the visibility of the window.  When the window is fully visibile, you can adjust font size and opacity. 
- Add a new window or modify the existing ones by editing the bottom of the DCS-SRS-AccMod.lua.

---                        <name>      <any lua function>         <format>  <scaling factor for unit conversion>
newitem  = AccOverlay.new("config1",base.Export.LoGetTrueAirSpeed,"%.2f",1.94384)
table.insert(AccModOverlayManager.windows,newitem)






CREDITS: I used DCS SRS's plugin as a starting point for this mod 
