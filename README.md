# Node Scanner

A World of Warcraft: Forever addon that shows the gathering nodes on your minimap
(ore, herbs, treasure chests) in a small window, with a rough distance and an arrow
pointing towards each one.

```
Gathering Nodes
Copper Vein     ~58  ↗
Silver Vein    ~106  ←
Peacebloom     ~120  ↓
```

## How it works

Since client build 1.60.1.70862 the minimap only reports the dot under the **real**
mouse cursor. Node Scanner therefore does what Minimap Alert does: for a moment it
moves the (invisible) minimap under your cursor, reads which dot is there, and puts
the minimap back. Each scan:

1. checks the nodes it already knows (one read each),
2. sweeps the rest of the minimap for new nodes, continuing where the last scan stopped.

A scan never takes longer than the configured maximum (2 s by default), and it
pauses when you are in combat, turning the camera, holding a mouse button, tabbed
out, or standing next to a node so you can click it.

## Features

- Name, rough distance (`~`) and arrow for every node on the minimap, nearest first
- Name coloured by the rarity of the item the node gives (white, green, blue, ...)
- Warning when Find Minerals / Find Herbs / Find Treasure is off - click to turn it on
- Minimap button and settings window, debug log
- Hovering a dot on the minimap adds it straight away

## Installation

Copy the `NodeScanner` folder into

```
World of Warcraft\_forever_\Interface\AddOns\
```

and restart the game.

## Usage

| Minimap button | Does |
|---|---|
| Left-click | Settings |
| Ctrl-click | Scan now |
| Shift-click | Show / hide the window |
| Right-click | Lock / unlock the window |
| Ctrl-right-click | Debug log |

Commands: `/nscan`, `/nscan options`, `/nscan debug`, `/nscan scan`,
`/nscan status`, `/nscan reset` (puts the minimap back if anything goes wrong),
`/nscan add <name> [herb|ore|treasure]`.

## Requirements

World of Warcraft: Forever, interface 16001.

## Credits

The minimap scanning technique is based on Minimap Alert (Loelalol) and its
Forever port, and on the research in NodeRadar's `FOREVER-PROBE.md`.

## License

MIT - see [LICENSE](LICENSE). Free to use, change and share.
