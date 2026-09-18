# How Flying Toasters works

This note is for someone who wants to **build and run** the tribute on each OS, and to see how a small Free Pascal desktop flock is structured: where it starts, who owns motion, who paints pixels, and how fullscreen is wired.

You do not need to be a Cocoa, Win32, or GTK expert. The same ideas show up in Eyes, the calculator, Moiré, and the Java Starfield / Marquee savers: an entry point, a model, a software canvas, and a native host that only presents bytes.

There is **no Lazarus form**. Each toaster is a few numbers (position, speed, scale, wing phase). Each tick those numbers are turned into RGBA pixels. The host uploads that buffer to a window.

## Build / run workflows

Work from the project root. `fpc` must be on `PATH`. Output always lands in `build/` (gitignored).

| What you want | Command | What you get |
|---------------|---------|--------------|
| macOS app | `make` then `make run` | `build/FlyingToasters.app`, opened |
| Linux / Raspberry Pi OS | `sudo apt install fpc libgtk2.0-dev` then `make linux` then `./build/flyingtoasters` | GTK 2 window |
| Windows 10+ | from a native FPC prompt: `make windows` then `build\FlyingToasters.exe` | taskbar window |
| Headless checks | `make test` | prints `ok` lines; non-zero if flight math or keys are wrong |
| Frozen canvas frames | `make snap` | `build/snap-classic.ppm`, `snap-starfield.ppm`, `snap-karaoke.ppm`, `snap-wide.ppm` |
| Start over | `make clean` | deletes `build/` |

macOS (Homebrew, Sonoma+):

```bash
brew install fpc
make
make run
```

Debian / Raspberry Pi OS:

```bash
sudo apt install fpc libgtk2.0-dev
make linux
./build/flyingtoasters
```

Windows: install FPC, open its command prompt so `fpc` is on `PATH`, then `make windows`. The `Windows` unit ships with FPC; no extra SDK is required for this app.

Only **one** host unit is compiled. `{$IFDEF DARWIN}` / `WINDOWS` / else picks `uhostcocoa`, `uhostwin`, or `uhostgtk`. Cross-compiling the GUI hosts is not a supported workflow — build on the OS you want to run on.

## Fullscreen workflow (all three hosts)

| Action | macOS | Windows | Linux |
|--------|-------|---------|-------|
| Menu | **View → Full Screen** | **View → Full Screen** | **View → Full Screen** |
| Key | **Ctrl+Cmd+F**, **F11** | **F11** | **F11** |
| Mouse | double-click the sky | double-click the sky | double-click the sky |
| Leave | **Esc**, or the same toggle | **Esc** or **F11** | **Esc** or **F11** |
| What the OS does | native fullscreen Space (`toggleFullScreen`) | popup covering the current monitor | `gtk_window_fullscreen` |

Resize (drag a corner, maximise, or enter fullscreen) always **rebuilds** the pixel buffer to the new client size. Sprites keep their world positions; they are not stretched.

## Mental model

```
toasters.pas begin
  → HostRun                    # uhostcocoa / uhostwin / uhostgtk
      → create TToasterController (model + pixel buffer)
      → create titled, resizable window
      → timer (~30 Hz)
           → Model.Update(dt)   # 45° slide, wrap, flap
           → RenderToasters (RGBA pixels)
           → host shows the buffer
```

| Layer | Unit | Tester-friendly analogy |
|-------|------|-------------------------|
| Entry / routing | `toasters.pas` | Test runner that picks the OS host at compile time |
| Settings | `utoasterconfig` | Fixture: density, darkness, extras, INI |
| State | `utoastermodel` | The starfield-style pool: spawn, move, recycle |
| Composer | `utoasterapp` | Holds the model and the canvas; `NeedsPresent` is the dirty flag |
| View | `utoasterrender` | Paints chrome toasters, toast, karaoke, HUD |
| Window shell | `uhostcocoa` / `uhostwin` / `uhostgtk` | Window, timer, fullscreen, About / Quit |

The hosts are **event-driven**. Almost everything after `HostRun` runs on the GUI thread. That is why the flock uses `NSTimer` / `SetTimer` / `g_timeout_add` instead of a raw `while true` loop.

Patterns borrowed (not copied) from the other standalone savers:

- **Flying Through Space (Java):** fixed-length entity array, `dt` cap of 0.05 s, recycle when off-screen, first fill scatters so the sky is not empty.
- **Marquee (Java):** overlay text whose timing is independent of sprite physics.
- **Moiré (Pascal):** software canvas, live keys, INI in the per-user config dir, fullscreen quit with Esc.

## Flight math

All entities share one After Dark vector. Speed `v` is in pixels per second; canvas `Y` grows downward:

```
dx = -v · cos(45°) = -v · √2/2
dy = +v · sin(45°) = +v · √2/2
```

Scale is depth: ~0.45 background, ~1.1 foreground. Speed grows with scale so near toasters overtake far ones. Draw order is scale ascending (small first).

When `X < -margin` or `Y > height + margin`, the slot is **respawned** along the top or right edge — the same recycle as a star hitting `zNear`.

## Unit responsibilities

### `toasters.pas` — composition root

Picks one host with `{$IFDEF}` and calls `HostRun`. Nothing else.

### `utoasterconfig` — the look

Density 5–30, toast darkness, accessories, starfield, karaoke, audio mode, HUD. `LoadConfig` / `SaveConfig` write `flyingtoasters.ini` under `GetAppConfigDir`. **M** / **Sound → MIDI March** plays an original looping GM square-lead march (not After Dark's theme). Choir is the same score on GM choir aahs. Pause mutes playback.

### `utoastermodel` — the flock

`TFlyingEntity` records, xorshift spawn, `Update(dt, w, h)`, wrap, `PlaceCataloguePose` for snapshots. No pixels.

### `utoasterrender` — the sky

`TPixelBuffer` plus ellipses, rectangles, triangles. Original toaster / toast geometry. Back-to-front sort, optional stars and karaoke, HUD strip.

### `utoasterapp` — glue

Timer → `Tick` → `Update` + dirty flag. Keys through `ApplyChar`. Hosts never touch the entity array.

### Hosts — present bytes

Cocoa copies RGBA into an `NSImage`. Windows flips to BGRA for `StretchDIBits`. GTK copies into a `GdkPixbuf`. Same controller on all three.
