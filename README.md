# Flying Toasters

A standalone tribute to Berkeley Systems' **After Dark** Flying Toasters: chrome toasters with wings, toast slices, and a 45° flight from the top-right to the bottom-left.

Written in **Free Pascal**. Lazarus and Delphi are not required — `fpc` plus the platform GUI libraries already on the machine are enough. There is no 3D engine and no widget-toolkit theme to fight. The whole sky is a software RGBA canvas; each host only uploads those bytes into a native window.

Sprites and karaoke lines are **original**. This is not affiliated with After Dark or Berkeley Systems, and it does not ship their bitmaps or theme song.

The flock:

- flies **top-right → bottom-left** on a 45° vector
- keeps **small toasters behind** large ones (After Dark's back-to-front stack)
- recycles sprites at the far edge, the same pooling idea as Goody's Flying Through Space
- lets you change density, toast darkness, extras, starfield, and karaoke **live**

How the pieces fit together (same style as Eyes, the calculator, Moiré, and the Java savers): `WORKINGS.md` for responsibilities and flight math, `EXECUTION_FLOW.md` for a tick-by-tick trace.

## Requirements

- **Free Pascal** 3.2+ (`fpc` on your `PATH`)

macOS (Homebrew), Sonoma-compatible:

```bash
brew install fpc
```

Debian / Raspberry Pi OS:

```bash
sudo apt install fpc libgtk2.0-dev
```

Windows 10+: a native Free Pascal install (the `Windows` unit ships with FPC).

## Run

From the project root:

```bash
make
make run
```

That compiles to `build/` and opens `FlyingToasters.app` on macOS. The window is a real app with a Dock icon.

Or with Make on other OSes:

```bash
make linux      # Linux / Raspberry Pi OS window
make windows    # FlyingToasters.exe
make test       # headless flight / option checks (no GUI)
make snap       # four PPM frames of the canvas
make clean      # remove build/
```

Manual compile on macOS (Make still has to wrap the binary in the `.app` bundle):

```bash
fpc -Mobjfpc -Scgi -O2 -Fusrc -FUbuild -FEbuild -obuild/FlyingToasters src/toasters.pas
make app
open build/FlyingToasters.app
```

## Using it

1. Toasters and toast drift across a black sky. Small ones are slower and sit behind.
2. **[** / **]** change how many toasters are in the air (5–30). **D** cycles toast: Light, Medium, Well done, Burnt. **A** toggles butter, jam, and bagels.
3. **S** sprinkles a quiet starfield (not the warp from Flying Through Space). **K** shows tribute karaoke. **Space** pauses. **H** hides the control strip.
4. **F11** (or **View → Full Screen**, or **double-click** the sky) goes fullscreen. **Esc** leaves it. On macOS the green traffic-light button and **Ctrl+Cmd+F** do the same native fullscreen.
5. **Flying Toasters → About** lists the keys. Closing the window quits. The last look is saved to a per-user INI, like Moiré.

**M** cycles Mute / MIDI march / Choir, or use **Sound → MIDI March**. That plays an original looping tribute (square-lead GM on Mac via the DLS synth, WAV fallback; Windows `PlaySound`). It is **not** Berkeley Systems' After Dark MIDI. Space pauses the flock and the music.

## Where it appears

| OS | Presence |
|----|----------|
| **macOS** | Titled, resizable window, Dock icon, native fullscreen Space. |
| **Windows** | Titled, resizable window on the taskbar, F11 monitor-filling popup. |
| **Linux** | GTK 2 window (Raspberry Pi OS friendly), F11 `gtk_window_fullscreen`. |

Closing the window **quits** the process. This is a desk toy, not an OS screensaver module (no `.scr` / `.saver` / xscreensaver hook yet).

## Project layout

```
src/
  toasters.pas       # program; picks the host with {$IFDEF}
  utoasterconfig.pas # density, darkness, extras, INI load/save
  utoastermodel.pas  # pool, 45° motion, wrap, karaoke clock
  utoasterrender.pas # software RGBA canvas (toasters, toast, HUD)
  utoasterapp.pas    # TToasterController: resize, tick, keys
  utoasteraudio.pas  # original MIDI march + WAV stand-in
  ubitmapfont.pas    # 8×8 UI / karaoke text
  uhostcocoa.pas     # macOS NSWindow
  uhostwin.pas       # Windows HWND
  uhostgtk.pas       # Linux GtkWindow
  toastertest.pas    # headless flight / option checks
  toastersnap.pas    # paints PPM frames without a window
bundle/
  Info.plist         # retina-capable app bundle
Makefile
```
