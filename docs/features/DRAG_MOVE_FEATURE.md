# Drag-and-Drop Unit Movement Feature with Heading Rotation

## Overview
The unit placer now supports moving existing units using drag-and-drop functionality, plus rotating their heading/orientation during the move. This allows players to reposition and reorient units already placed in the mission without having to delete and respawn them.

## Features Added

### 1. Drag Detection
- **Automatic Unit Detection**: Clicking on or near an existing unit automatically initiates drag mode
- **Smart Selection**: Selects the closest unit within ~80 pixels of the click point
- **Query System**: Uses the mission environment to find alive units within the search radius
- **Heading Preservation**: Unit's current heading is read and displayed during drag

### 2. Visual Feedback
- **Placement Mode** (Armed): Green marker (8x8px) appears at cursor
- **Drag Mode** (Active): Yellow marker (12x12px) follows cursor to indicate drag in progress
- **Heading Widget**: Yellow text box appears near cursor showing current heading in degrees with controls hint
- **Status Messages**: Real-time status updates in the info panel, including heading angle

### 3. User Interaction

#### Starting a Drag Operation
1. **Without Arming**: Simply left-click on or near an existing unit
2. The system automatically enters drag mode if a unit is found
3. A yellow marker appears, confirming active drag
4. A heading widget displays the current unit heading (in degrees)
5. Status text shows instructions for keyboard controls

#### During Drag - Movement
- Move the mouse while holding the button down
- The yellow marker follows your cursor
- Status text shows the unit being dragged
- Terrain height changes are automatically calculated
- Heading widget stays near the cursor

#### During Drag - Heading Rotation
While dragging, use keyboard keys to rotate the unit heading:
- **`+` or `]` key**: Rotate heading counter-clockwise (by 10° increments)
- **`-` or `[` key**: Rotate heading clockwise (by 10° increments)
- The heading widget updates in real-time showing the new angle
- Rotation is continuous - hold keys to rotate multiple steps
- Heading is automatically normalized to 0-360° range

#### Completing the Move
- Release the mouse button to drop the unit
- The system resolves the new terrain position
- Unit is moved to the new location with the final heading
- Status confirms success with new coordinates and heading angle
- Heading widget closes automatically

#### Canceling a Drag
- Press **Right Mouse Button** while dragging to cancel
- Unit returns to its original position and heading
- Status shows "Move cancelled"
- Heading widget closes automatically

## Behavior

### Co-existence with Placement Mode
- **Unit Placer Armed** (green click marker)
  - Left-click attempts to drag existing unit first
  - Falls back to placement if no unit found
  - Right-click cancels placement

- **Unit Placer Disarmed** (no marker)
  - Left-click on units enters drag mode
  - Heading can be rotated immediately
  - Right-click cancels drag

### Search Behavior
- Searches for units within ~80 pixels of click point
- Returns closest unit by screen distance (prioritizes units dead-center)
- Limits search to 10 closest units for efficiency
- Only considers alive units that can be positioned

### Movement and Heading Constraints
- Units can only be moved to terrain that supports their type
- Respects mission boundaries and terrain
- Heading rotation is unlimited (0-2π radians, 0-360°)
- Heading values are preserved during movement
- Heading uses industry-standard radians internally (displayed as degrees to user)
- Uses same distance limits as placement mode (~5km default)

## Technical Implementation

### State Tracking
- **draggingUnit**: Reference to the unit being moved (includes current heading)
- **dragStartX/Y**: Original screen coordinates
- **dragStartWorldPos**: Original world position (for reference)
- **dragCurrentHeading**: Current heading in radians (user rotates this)
- **dragOriginalHeading**: Original heading before any rotation
- **dragMarker**: Yellow visual indicator widget (12x12px)
- **headingWidget**: Yellow text display showing heading angle and keyboard hint
- **headingRotateStep**: Step size for rotation (π/18 = 10°)

### Methods Added / Modified
1. **findUnitsNearScreenPoint()** - Query mission for nearby units (now includes heading)
2. **attemptDragStart()** - Initialize drag operation and heading widget
3. **updateDragPosition()** - Update visual feedback including heading widget position
4. **completeDrag()** - Move unit to new position with new heading
5. **cancelDrag()** - Abort operation and clean up heading widget
6. **moveUnitTo()** - Execute unit movement AND heading rotation
7. **createHeadingWidget()** - Create yellow heading display widget
8. **destroyHeadingWidget()** - Clean up heading widget
9. **updateHeadingWidget()** - Update heading display text
10. **rotateHeadingCCW()** - Counter-clockwise rotation handler
11. **rotateHeadingCW()** - Clockwise rotation handler
12. **update()** - Added keyboard polling for +/- keys during drag

### Mission Script Integration
- **findUnitsNearScreenPoint()**: Returns unit position AND heading from mission environment
- **moveUnitTo()**: Calls both `setPosition()` and `setHeading()` on units
- Uses `coalition.getCoalition()` to enumerate groups
- Queries unit positions and headings
- Moves units and rotates them in a single operation

## Status Messages

| Message | Meaning |
|---------|---------|
| "Dragging: [unit name] (Heading: XX.X°, use +/- to rotate)" | Drag started, heading shown, rotation enabled |
| "Moving: [unit name] (Heading: XX.X°)" | Dragging in progress with current heading |
| "Rotating [unit name]: XX.X° (use +/- to rotate more)" | User rotated heading |
| "Moved [unit name] to (x=X z=Z, heading: XX.X°)" | Move successful with final heading |
| "Move failed: [error]" | Operation failed with reason |
| "Move cancelled: [unit name]" | User cancelled the drag |
| "[Error reason]" | Detection or positioning issue |

## Usage Tips

1. **Precise Positioning**: Use mouse positioning for location, then +/- keys to fine-tune heading
2. **Formation Assembly**: Multiple drag-rotate operations let you assemble groups in specific formations
3. **Heading Reference**: 0° typically faces North/positive X direction; 90° faces East/negative Z
4. **Keyboard Feedback**: Watch status string to confirm heading changes
5. **Multiple Operations**: You can drag multiple units in sequence without re-arming

## Heading Rotation Reference

- **0° / 0 rad**: Facing North (positive X direction)
- **90° / π/2 rad**: Facing East (negative Z direction) 
- **180° / π rad**: Facing South (negative X direction)
- **270° / 3π/2 rad**: Facing West (positive Z direction)

Each +/- key press rotates by **10°** (π/18 radians).

## Limitations

- Cannot drag static objects (cargo, fortifications) - only dynamic units/groups
- Cannot drag player-controlled units or in-flight AI aircraft
- Movement range is limited by distance constraints (default ~5km radius)
- Units must be alive and have valid positions
- Rotation degree increments are fixed at 10° (can be changed by modifying headingRotateStep)

## Examples

### Example 1: Reposition and Face Player
```
1. Click near a ground unit (tank, truck, etc.)
2. Drag to new location
3. Press + key 9 times to rotate 90° to face the player
4. Release mouse button to drop
```

### Example 2: Organize Patrol Formation
```
1. Click and drag Unit A, set heading
2. Click and drag Unit B, set heading
3. Click and drag Unit C, set heading
4. All units now in formation facing desired direction
```

### Example 3: Fine-Tune Existing Unit Heading
```
1. Click existing unit (no armed placer needed)
2. Don't move mouse, just press +/- keys to spin in place
3. Release mouse to apply rotation
```

### Example 4: Combine with Placement
```
1. Arm the unit placer
2. Place a new unit at approximate location  
3. Click to drag the newly placed unit
4. Reposition and rotate to exact position/heading
5. Continue without re-arming
```

## Keyboard Controls Summary

| Key | Action |
|-----|--------|
| Left Mouse Button + Drag | Start moving unit |
| `+` or `]` Key | Rotate heading counter-clockwise (+10°) |
| `-` or `[` Key | Rotate heading clockwise (-10°) |
| Right Mouse Button | Cancel drag operation |
| Mouse Release | Complete drag and move unit |

