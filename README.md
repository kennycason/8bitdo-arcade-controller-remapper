# 8bitdo-arcade-controller-remapper

Small macOS command-line remapper for 8BitDo (or other GameController-compatible) pads.

It seizes the controller via IOKit HID (so macOS/GameController doesn't claim it), reads raw HID input, and emits keyboard events so emulators like RetroArch and OpenEmu can consume them.

## What this solves

- 8BitDo Arcade Controller has limited macOS support — no official remapping software.
- Works around GameController framework seizing the device and swallowing events.
- Lets you define your own button-to-key mappings via a JSON file.
- Includes an interactive `--configure` mode to build mappings by pressing keys.

## Requirements

- macOS with Swift toolchain (`swift --version`).
- Accessibility permission for Terminal (or whichever app launches this binary), because keyboard events are injected via Quartz.

## Build

```bash
cd /Users/kenny/code/8bitdo-arcade-controller-remapper
swift build -c release
```

## Run

Use built-in defaults:

```bash
swift run -c release 8bitdo-arcade-controller-remapper
```

Use a mapping profile:

```bash
# RetroArch (recommended)
swift run -c release 8bitdo-arcade-controller-remapper --mapping mappings/retroarch-default.json

# OpenEmu
swift run -c release 8bitdo-arcade-controller-remapper --mapping mappings/openemu-default.json
```

With debug output (shows all HID events):

```bash
swift run -c release 8bitdo-arcade-controller-remapper --mapping mappings/retroarch-default.json --debug
```

## Interactive Configure Mode

Build a custom mapping by pressing keys on your keyboard:

```bash
swift run -c release 8bitdo-arcade-controller-remapper --configure --mapping mappings/my-custom.json
```

This walks through each controller button and asks you to press the keyboard key you want it to emit. Press Delete/Backspace to skip a button. The result is saved as a JSON mapping file.

## Mapping profiles

| Profile | File | Best for |
|---------|------|----------|
| RetroArch default | `mappings/retroarch-default.json` | RetroArch + bsnes/snes9x/etc |
| OpenEmu default | `mappings/openemu-default.json` | OpenEmu (keyboard mode) |

### RetroArch default mapping

| Controller | Key | RetroArch action |
|-----------|-----|-----------------|
| A | x | RetroPad A |
| B | z | RetroPad B |
| X | s | RetroPad X |
| Y | a | RetroPad Y |
| L Shoulder | q | RetroPad L |
| R Shoulder | w | RetroPad R |
| L Trigger | 1 | — |
| R Trigger | 2 | — |
| D-pad | Arrow keys | D-pad |
| Start/Menu | Return | Start |
| Select/Options | Right Shift | Select |
| Home | Escape | Menu toggle |

## 8BitDo Arcade Controller: P1–P4 button setup

The P1–P4 buttons are programmable macro buttons. By default they don't send any HID data to the OS — they execute macros internally. To make them usable as regular buttons, use the **on-device fast mapping** feature:

1. Hold the **P button** you want to remap (e.g., P1)
2. Press the **standard button** you want it to act as (e.g., Left Trigger)
3. Press the **Star button** to confirm

Once remapped, P1–P4 will send regular HID button reports and our remapper will see them. You can map them to any standard button (L3, R3, LT, RT, etc.) and then the remapper translates those to keyboard keys.

To reset a P button mapping, repeat the same procedure.

## Mapping file format

```json
{
  "profile": "my-profile",
  "bindings": {
    "buttonA": "x",
    "buttonB": "z",
    "dpadUp": "upArrow"
  }
}
```

## Supported input names

`buttonA`, `buttonB`, `buttonX`, `buttonY`, `leftShoulder`, `rightShoulder`, `leftTrigger`, `rightTrigger`, `dpadUp`, `dpadDown`, `dpadLeft`, `dpadRight`, `leftThumbstickButton`, `rightThumbstickButton`, `buttonMenu`, `buttonOptions`, `buttonHome`

## Supported key names

Letters: `a`–`z`

Numbers: `zero`, `one`, `two`, `three`, `four`, `five`, `six`, `seven`, `eight`, `nine`

Special: `space`, `returnKey`, `escape`, `tab`, `delete`

Arrows: `upArrow`, `downArrow`, `leftArrow`, `rightArrow`

Modifiers: `leftShift`, `rightShift`

Punctuation: `period`, `comma`, `slash`, `semicolon`, `apostrophe`, `leftBracket`, `rightBracket`, `minus`, `equals`, `grave`

## Troubleshooting

- **No HID events on first connect**: Disconnect and reconnect the controller after starting the remapper. The HID seize must happen before GameController claims the device.
- **Keys work in TextEdit but not in emulator**: Make sure the emulator is set to keyboard input mode, not controller mode. RetroArch works well; OpenEmu's snes9x core may not pick up synthetic key events during gameplay.
- **P1–P4 buttons not detected**: They need to be fast-mapped to standard buttons first (see above).

## Sample Config Logs


```
$ swift run -c release 8bitdo-arcade-controller-remapper --configure --mapping mappings/retroarch-kenny.json
HID fallback initialized.
HID devices (1):
  - Pro Controller vendor=1406 product=8201 usagePage=0x1 usage=0x5
Listening for controller input...
Debug mode enabled. Polling + HID fallback active.

Interactive Mapping Configuration
For each button:
  1) Press a button on your CONTROLLER
  2) Then press the KEYBOARD key you want it to emit
Repeat for each button. Press Ctrl+C when done.
(If no response, disconnect and reconnect your controller.)

Press a controller button... [hid] page=0x1 usage=0x39 value=6
detected dpadLeft
  Now press the keyboard key for dpadLeft: [hid] page=0x1 usage=0x39 value=8
Left Arrow
  Mapped: dpadLeft -> leftArrow

Press a controller button... [hid] page=0x1 usage=0x39 value=4
detected dpadDown
  Now press the keyboard key for dpadDown: [hid] page=0x1 usage=0x39 value=8
Up Arrow
  Mapped: dpadDown -> upArrow

Press a controller button... [hid] page=0x1 usage=0x39 value=2
detected dpadRight
  Now press the keyboard key for dpadRight: [hid] page=0x1 usage=0x39 value=8
Right Arrow
  Mapped: dpadRight -> rightArrow

Press a controller button... [hid] page=0x1 usage=0x39 value=0
detected dpadUp
  Now press the keyboard key for dpadUp: [hid] page=0x1 usage=0x39 value=8
Down Arrow
  Mapped: dpadUp -> downArrow

Press a controller button... [hid] page=0x9 usage=0x6 value=1
detected rightShoulder
  Now press the keyboard key for rightShoulder: [hid] page=0x9 usage=0x6 value=0
q
  Mapped: rightShoulder -> q

Press a controller button... [hid] page=0x9 usage=0x5 value=1
detected leftShoulder
  Now press the keyboard key for leftShoulder: [hid] page=0x9 usage=0x5 value=0
w
  Mapped: leftShoulder -> w

Press a controller button... [hid] page=0x9 usage=0x4 value=1
detected buttonX
  Now press the keyboard key for buttonX: [hid] page=0x9 usage=0x4 value=0
s
  Mapped: buttonX -> s

Press a controller button... [hid] page=0x9 usage=0x3 value=1
detected buttonY
  Now press the keyboard key for buttonY: [hid] page=0x9 usage=0x3 value=0
a
  Mapped: buttonY -> a

Press a controller button... [hid] page=0x9 usage=0x2 value=1
detected buttonA
  Now press the keyboard key for buttonA: [hid] page=0x9 usage=0x2 value=0
x
  Mapped: buttonA -> x

Press a controller button... [hid] page=0x9 usage=0x1 value=1
detected buttonB
  Now press the keyboard key for buttonB: [hid] page=0x9 usage=0x1 value=0
z
  Mapped: buttonB -> z

Press a controller button... [hid] page=0x9 usage=0xa value=1
detected buttonMenu
  Now press the keyboard key for buttonMenu: [hid] page=0x9 usage=0xa value=0
Return
  Mapped: buttonMenu -> returnKey

Press a controller button... [hid] page=0x9 usage=0x9 value=1
detected buttonOptions
  Now press the keyboard key for buttonOptions: [hid] page=0x9 usage=0x9 value=0
Right Shift
  Mapped: buttonOptions -> rightShift

Press a controller button... ^C
Mapping saved to mappings/retroarch-kenny.json (12 bindings)
```

Run 8bitdo-arcade-controller-remapper with our new config.

```
swift run -c release 8bitdo-arcade-controller-remapper --mapping mappings/retroarch-kenny.json --debug
```
