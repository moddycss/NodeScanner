# Node Scanner tools - created with the help of AI (Claude). MIT licensed.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# Usage: python gen_tiles.py <folder with azeroth/azeroth.wdt and kalimdor/kalimdor.wdt> <output MinimapTiles.lua>
# (export the two WDT files with wow.export from your own WoW Forever client)
root, out_path = sys.argv[1], sys.argv[2]
import wdt
out = ["-- Node Scanner - created with the help of AI (Claude). MIT licensed.",
       "-- Minimap terrain tiles: FileDataID of the minimap image for each 533.33-yard square.",
       "-- Generated from the continents' WDT files (MAID chunk) of the WoW Forever client.",
       "-- Index = y * 64 + x, same grid as the game's ADT tiles. No images are shipped, only numbers.",
       "local _, ns = ...",
       "ns.MinimapTiles = {"]
for cont, name in [(0, 'azeroth'), (1, 'kalimdor')]:
    rows = wdt.maid(f'{root}/{name}/{name}.wdt', 'MAID')
    parts = [f"[{i}]={r[7]}" for i, r in enumerate(rows) if r[7]]
    out.append(f"    [{cont}] = {{ -- {name}, {len(parts)} tiles")
    for k in range(0, len(parts), 10):
        out.append("        " + ",".join(parts[k:k+10]) + ",")
    out.append("    },")
out.append("}")
open(out_path,'w').write("\n".join(out) + "\n")
