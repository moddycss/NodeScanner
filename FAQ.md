# Node Scanner – FAQ

Answers to the questions people ask most, and the reasons behind Node Scanner's design.

---

## How it works

### Why does Node Scanner move the minimap?

Because it's the only way an addon can read the minimap today.

The yellow dots on the minimap (ore, herbs, treasure) aren't available to addons through
any list or event. The only way to learn what a dot is, is the minimap's own mouseover:
"what is under the mouse right now?". Earlier clients let addons ask that for any point.
Since client build 70862, the game only answers for the point under the **real mouse
cursor** (Blizzard did this on purpose).

So Node Scanner does what the mouse would do, but the other way round. For one or two
frames at a time, it moves the minimap so the spot it wants to check sits under your
cursor. It reads the answer and moves the minimap back. During a scan the real minimap is
invisible and doesn't react to clicks, so you don't see it jump around.

### Why is there a second ("stand-in") map?

While a scan has the real minimap away, its place on screen would be empty for a second
or two. The stand-in map fills that gap so the minimap seems to stay put.

The game has only one real minimap, and an addon can't create another. So the stand-in map
is drawn by Node Scanner:

- the terrain uses the game's own minimap images. The addon only ships a table of which
  image belongs where, not the images themselves
- the ring, sun/moon, tracking button and coordinates are copied from the real minimap
- your arrow and the nodes Node Scanner has found are drawn on top

If the swap still bothers you, tick **Always use the stand-in map**. The real minimap is then
hidden for good and only the stand-in map is shown, so there's no swapping at all.

### Why does it show rough distances (`~`) instead of exact positions?

A single read only tells Node Scanner *"there is a Copper Vein somewhere under this
point"*. A dot can be read from anywhere within its hover area, which is about 25 minimap
units across (roughly 80 yards at normal zoom).

Finding the exact centre of every dot takes many extra reads per node. That makes scans
longer and means more time with the real minimap away. Most of the time you just want to
know *which way to go and roughly how far*, and the rough position answers that. When you
get closer, the distance becomes more precise, and hovering a dot on the real minimap
gives the exact spot at once.

If you want exact positions anyway, tick **Measure exact positions (slower)** in the settings.

### Why does it only scan every 10 seconds, and why can't a scan be faster?

Each read needs the game to draw at least one or two frames with the minimap in place. A
full sweep of the minimap is many reads, so a scan takes up to 2 seconds (you can change
that limit). Scanning non-stop would mean the real minimap is almost never where it
belongs. 10 seconds is a balance: you're always kept up to date, but a scan doesn't
happen all the time. You can change the interval in the settings.

Higher FPS does make scans finish faster, since each read takes a fixed number of frames.

---

## Pauses

### Why does scanning pause so often?

Because moving the minimap under your cursor takes the mouse away from whatever you were
pointing at. Clicks could land on the minimap, and the game would close the tooltip you
were reading. So Node Scanner waits when:

- you are **in combat** (unless **Also scan in combat** is ticked)
- you **hold a mouse button** or **turn the camera**
- the mouse is **at the minimap**, so you can use it normally
- the mouse is **over the interface**, a **tooltip is shown**, or a **game window is open**
  (talents, spellbook, flight master map, merchant, mailbox ...)
- you are **standing next to a node**, so you can click it
- the game **isn't in focus** (tabbed out)
- you are in a **dungeon, raid, battleground, arena or indoors** (unless ticked under
  **Also scan in**), and in **rested areas** if you turn that on

The window title shows why it's paused, e.g. "paused (a window is open)". Each pause can
be turned off in the settings.

### Why does the list empty out or turn grey when I tab out?

It shouldn't any more. When the game loses focus, scanning pauses and the list is kept.
A node turns grey when it hasn't been confirmed for a while (it might have been gathered
by someone else), and it disappears after several scans in a row without seeing it.

---

## Tracking

### Why does Node Scanner switch my tracking?

The minimap can only track one of Find Minerals, Find Herbs and the creature trackings at
a time. Find Treasure is the exception: it stacks, so it is simply kept on. To find both ore
and herbs, Node Scanner switches tracking between the types you ticked, either one type
per scan or several in one scan. The switch sound is muted.

If you only have one gathering profession, only that tracking is used and nothing switches.

### Why are some tracking types greyed out?

Your character doesn't have them. Hunters, druids, dwarves, etc. get different tracking spells.

### Why are mobs shown as "Defias Pillager (5)"?

Creature tracking can show many dots with the same name. Instead of filling the window with
them, Node Scanner shows one line per name. The arrow points at the nearest one and the
count says how many there are.

---

## The stand-in map

### Why doesn't the stand-in map show mailboxes, auctioneers, flight masters, quest areas ...?

Those icons are drawn by the game engine inside the real minimap, and the game doesn't
tell addons where they are. Node Scanner can only show what it has found itself: gathering
nodes, treasure and tracked creatures.

With the default setting this only matters during the 1–2 second scan. With **Always use
the stand-in map** they are never shown, which is the trade-off for no swapping.

### Why does the stand-in map only have terrain in Eastern Kingdoms and Kalimdor?

The terrain comes from the continents' minimap images. Caves, buildings and dungeons use
separate interior maps that aren't covered. Since scanning is paused in dungeons and
indoors anyway, they are left out. Elsewhere, the stand-in map falls back to world map art,
and "Always use the stand-in map" falls back to the real minimap.

### Why don't the buttons on the stand-in map light up when I hover them?

They are copies. The real buttons are still there, invisible, underneath. Clicking works
because you are clicking the real button. Only the hover glow is missing.

---

## Other

### Does it work together with other minimap addons?

Mostly, yes. Addons that also move the minimap to read it, such as **Minimap Alert**, clash
with Node Scanner, so use one or the other. Addons that change the minimap's shape or border
may make the stand-in map look different from the real one.

### Something went wrong and my minimap is gone. What do I do?

Type `/nscan reset`. It puts the minimap back where it belongs. Node Scanner also does this
on its own if anything goes wrong during a scan. `/nscan debug` opens a log you can copy and
send along with a bug report.

### Is this allowed?

Node Scanner only uses the normal addon interface, the same way other minimap addons do.
It doesn't play for you: it doesn't move your character, gather or click anything. It only
reads the minimap and shows what it found. As with any addon, it's your own choice to use it.

### Why was it made with AI?

Node Scanner was created with the help of AI (Claude). The ideas, testing and decisions are
the author's, and the code was written together with Claude. The whole source is open (MIT
license), so anyone can read exactly what it does.
