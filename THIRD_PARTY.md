# Third-party software

## TinyNES

The Tang target applies patches/tinynes-tang32.patch to TinyNES commit
f5011dd374cfc65f4f17616fec97c903a66b6cc8.
TinyNES is copyright (c) 2026 TinyNES contributors and is used under the MIT
License:

> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

## Meph's 32x tileset (the tile art)

Not yet drawn by the renderer: it is the tile set the project means to carry,
and `tools/convert_tiles.py` converts it. Meph ships 512 by 512 sheets of 32 by
32 tiles, 256 to a sheet, with `-top` and `-bg` variants for Dwarf Fortress's
layered drawing. The sheet's own manifest gives the credit line below; the
GitHub repository carries no licence file, and what terms there are, are the
author's, stated on the forum thread the set came from. The art is not committed
to this repository: the converter is, and the tiles are fetched and converted
locally, which is how the game's own landscape is handled too.

- Meph, Vordak and Denzi, "Meph-lite 32x", content version 5.5 of 2020-03-11
- https://github.com/DFgraphics/Meph
- http://www.bay12forums.com/smf/index.php?topic=139579.0

---

## Dungeon Crawl Stone Soup tile set (the cursor)

`firmware/terrain/terrain.c` carries the shape of the mouse cursor as two grids
of characters: the frame `misc/cursor_green.png`, drawn while no mouse button is
held, and the crosshair `misc/cursor_red.png`, drawn while the left or the right
button is held. Both are from the Dungeon Crawl Stone Soup Full tile set,
reduced to a silhouette and written out as source rather than shipped as an
image.

The set is released under CC0 1.0: the artists waived their copyright, so it
may be used for any purpose without attribution. Its README asks that users
credit the artists and say where the tiles came from, which this is.

- https://github.com/crawl/tiles/tree/master/releases
- https://opengameart.org/content/dungeon-crawl-32x32-tiles
