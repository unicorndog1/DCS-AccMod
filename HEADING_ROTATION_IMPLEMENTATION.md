# Unit Heading Rotation Feature - Implementation Summary

## Overview
Added comprehensive heading rotation support to the unit dragging system in the DCS-AccMod unit placer. Users can now:
1. Click and drag existing units to reposition them
2. Rotate the unit's heading while dragging using keyboard controls (+/- keys)
3. See real-time visual feedback of the current heading angle
4. Apply both position and heading changes in one operation

## What Changed

### 1. State Variables Added to UnitPlacerPanel.new()
- `dragCurrentHeading` - radians, current heading during drag
- `dragOriginalHeading` - radians, original heading before rotation
- `headingRotateStep` - π/18 radians = 10° per keystroke
- `headingWidget` - visual text widget displaying heading angle
- `headingArrowMarkers` - placeholder for future visual indicators

### 2. Enhanced Unit Detection (findUnitsNearScreenPoint)
- **Now returns heading data**: Each unit found includes its current heading
- Mission script queries `unit:getHeading()` in addition to position
- Heading parsed from result string in Lua format: `name|groupName|x|y|z|heading`

### 3. Drag Start Initialization (attemptDragStart)
- Captures the unit's current heading on drag start
- Stores in both `dragOriginalHeading` and `dragCurrentHeading`
- Creates heading widget to display angle
- Updates status text with keyword hint: "use +/- to rotate"
- Shows initial heading in degrees (converted from radians)

### 4. Heading Widget System (createWindow)
Three new methods for heading widget lifecycle:
- `createHeadingWidget()` - Creates yellow text widget near drag point, shows "Heading: XX.X° (+/-: rotate)"
- `destroyHeadingWidget()` - Removes widget from panel
- `updateHeadingWidget()` - Refreshes displayed heading angle

### 5. Keyboard Input Handling (update method)
Added keyboard polling during drag state:
```lua
if draggingUnit then
    if Gui.GetKey(Gui.Key.Equals) or Gui.GetKey(Gui.Key.Plus) then
        self:rotateHeadingCCW()  -- +10°
    end
    if Gui.GetKey(Gui.Key.Minus) or Gui.GetKey(Gui.Key.Subtract) then
        self:rotateHeadingCW()   -- -10°
    end
    -- Alternative keys: [ and ]
end
```

### 6. Heading Rotation Methods
- `rotateHeadingCCW()` - Counter-clockwise rotation, adds `headingRotateStep` (10°)
- `rotateHeadingCW()` - Clockwise rotation, subtracts `headingRotateStep` (10°)
- Both normalize heading to 0-2π radians range
- Both update widget and status text

### 7. Drag Position Update (updateDragPosition)
- Widget position follows cursor during drag
- Real-time heading display updates on rotation
- Status shows current heading angle in degrees

### 8. Unit Movement Enhancement (moveUnitTo)
- **New parameter**: `newHeading` in radians
- Mission script now calls both:
  - `u:setPosition(pos, false)` - Move unit
  - `u:setHeading(newHeading)` - Rotate unit
- Both changes applied atomically in mission environment

### 9. Drag Completion (completeDrag)
- Passes current heading to moveUnitTo
- Status shows final coordinates AND heading angle
- Cleans up heading widget
- Example output: "Moved UnitName to (x=1234.5 z=5678.9, heading: 45.0°)"

## Keyboard Controls

| Key | Effect |
|-----|--------|
| `+` | Add 10° (counter-clockwise) |
| `-` | Subtract 10° (clockwise) |
| `]` | Add 10° (alternative) |
| `[` | Subtract 10° (alternative) |

*Only active while actively dragging a unit*

## Heading Reference

In DCS mission coordinate system:
- **0°** = Facing North (positive X axis)
- **90°** = Facing East (negative Z axis)
- **180°** = Facing South (negative X axis)
- **270°** = Facing West (positive Z axis)

Internally all calculations use radians; display/input use degrees for user-friendliness.

## User Workflow Example

```
1. Player clicks on existing unit → enters drag mode
2. Heading widget appears showing current angle (e.g., "Heading: 45.0°")
3. Player drags mouse to new location
4. While dragging, player presses '+' key 9 times → heading rotates 90°
5. Widget updates: "Heading: 135.0°"
6. Player releases mouse
7. Unit moves to new position with new 135° heading
8. Status confirms: "Moved Tank to (x=1234 z=5678, heading: 135.0°)"
```

## Files Modified

### [DCS-SRS-AccMod.lua](c:\HELL\CODE\DCS-AccMod\Mods\Services\DCS-AccWidg\Scripts\DCS-SRS-AccMod.lua)

**Added/Modified Methods:**
- `UnitPlacerPanel.new()` - Added heading state variables
- `findUnitsNearScreenPoint()` - Returns heading data
- `attemptDragStart()` - Initialize heading tracking and widget
- `updateDragPosition()` - Update heading widget during drag
- `completeDrag()` - Pass heading to moveUnitTo
- `cancelDrag()` - Clean up heading widget
- `createHeadingWidget()` - Create yellow heading display widget
- `destroyHeadingWidget()` - Remove heading widget
- `updateHeadingWidget()` - Refresh heading display
- `rotateHeadingCCW()` - Rotate counter-clockwise
- `rotateHeadingCW()` - Rotate clockwise
- `moveUnitTo()` - Enhanced to accept and apply heading parameter
- `update()` - Added keyboard polling for rotation keys

**Key Code Changes:**
1. Mission script in `findUnitsNearScreenPoint()` queries unit heading
2. Mission script in `moveUnitTo()` now calls `setHeading()` 
3. Parsing of heading value from mission script results
4. Keyboard input handling in update loop

### [DRAG_MOVE_FEATURE.md](c:\HELL\CODE\DCS-AccMod\DRAG_MOVE_FEATURE.md)

Updated comprehensive documentation including:
- Heading rotation controls explanation
- Keyboard shortcuts table
- Heading reference angles (0°/90°/180°/270°)
- Usage examples involving heading
- Status message updates showing heading angles
- Technical implementation details for heading system

## Testing Checklist

- [ ] Can drag existing ground unit
- [ ] Heading widget appears on drag start
- [ ] Widget shows correct heading in degrees
- [ ] '+' key rotates heading counter-clockwise by 10°
- [ ] '-' key rotates heading clockwise by 10°
- [ ] '[' and ']' keys work as alternatives
- [ ] Widget updates show rotated heading in real-time
- [ ] Status text shows heading angle during rotation
- [ ] Unit is placed at new position with new heading on release
- [ ] Final heading persists after drop (verify in saved mission)
- [ ] Right-click cancels without applying changes
- [ ] Widget disappears after operation completes
- [ ] Multiple units can be moved/rotated in sequence
- [ ] Works with armed and disarmed placer modes

## Known Limitations

1. Rotation increments are fixed at 10° (code value: π/18)
   - Can be customized by changing `headingRotateStep` in `new()`
   
2. Heading widget displays in yellow text only
   - Could be enhanced with visual compass/arrow in future
   
3. No mouse scroll wheel rotation (yet)
   - Current design uses keyboard only
   
4. Heading updates are per-keystroke (no continuous rotation hold)
   - User must press key multiple times for larger rotations

## Comparison with DCS Mission Editor

Based on scraped DCS Mission Editor code (`me_action_edit_panel.lua`):
- DCS ME updates formation using trigonometric rotation matrices
- Our implementation: direct heading assignment to unit
- DCS stores heading and `psi = -heading` 
- Our implementation: sets heading directly via `setHeading()`

Both approaches work for reorienting units in the mission environment.

## Performance Impact

- Minimal: Heading rotation is lightweight math (π/18 scaling)
- Widget updates happen only during active drag
- Mission queries include heading in existing query (no extra overhead)
- No persistent overhead when not dragging

## Future Enhancement Opportunities

1. **Mouse wheel support** - Scroll to rotate heading
2. **Heading snap-to-grid** - 15°, 30°, 45° increments as option
3. **Visual heading indicator** - Arrow/compass showing direction
4. **Holding keys** - Continuous rotation while key held (vs single press)
5. **Relative heading** - Option to rotate by difference from original
6. **Group rotation** - Select multiple units and rotate together
7. **Formation helper** - Auto-arrange units in specific patterns

