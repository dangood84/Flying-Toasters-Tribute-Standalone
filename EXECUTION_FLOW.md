# Execution flow: from `begin` to a flapping toaster

A step-by-step trace of what happens from `program FlyingToasters` through host initialisation and timer startup, down to how an individual sprite is moved and drawn.

Default launch (`make run`) opens the **macOS window**. `make windows` / `make linux` use the same model and renderer; only the present step changes. This trace is **macOS** (`uhostcocoa`) unless a step says otherwise.

One thread does everything after startup:

- **main (Pascal, then Cocoa run loop)** — `HostRun`, `setup`, `tick:`, `redraw`, AppKit drawing

There is no Swing EDT. `NSTimer` and `NSWindow` run on the same thread that called `NSApplication.run`. (The Java Starfield / Marquee savers used `javax.swing.Timer` on the EDT for the same reason: one thread owns both motion and paint.)

---

## Phase A — process entry

**1.** The OS loads `FlyingToasters.app/Contents/MacOS/FlyingToasters` (or `./build/FlyingToasters`). FPC unit initialisation runs (`TToasterModel` is not constructed yet).

**2.** `program FlyingToasters` executes `HostRun`.

```pascal
{ src/toasters.pas }
begin
  HostRun;
end.
```

**3.** `HostRun` (Cocoa):

```pascal
procedure HostRun;
begin
  ...
  App.setActivationPolicy(NSApplicationActivationPolicyRegular);
  SharedApp := TAppDelegate.alloc.init;
  App.setDelegate(SharedApp);
  SharedApp.setup;
  App.run;
end.
```

Regular policy (no `LSUIElement`) means: **Dock icon**, Cmd-Tab, a real window. `App.run` does not return until Quit.

Windows: `HostRun` registers a window class, `CreateWindowEx` with `WS_OVERLAPPEDWINDOW`, `SetTimer(33)`, then `GetMessage`.  
Linux: `gtk_init`, `gtk_window_new`, `g_timeout_add(33, ...)`, `gtk_main`.

---

## Phase B — window initialisation (`setup`)

**4.** `TAppDelegate.setup` is idempotent (`if ready then Exit`). `applicationDidFinishLaunching` calls it again after `App.run` has started; the second call is a no-op.

**5.** Pixel scale: `NSScreen.mainScreen.backingScaleFactor` (typically `2` on Sonoma retina). The controller buffer is in **pixels**; the window is in **points** (800×500 at launch).

**6.** `controller := TToasterController.Create(Round(800 * scale), …, LoadConfig)`:

- `TToasterModel.Create` — xorshift seed, star dots, pool sized to density + toast count
- First fill **scatters** along the flight corridor (Starfield's `scatterDepth` idea)
- `TPixelBuffer` allocated (RGBA)
- `NeedsPresent := True` so the first paint happens before the timer

**7.** Menu: About / Quit on the application menu, **Full Screen** (Ctrl+Cmd+F) on View.

**8.** Window: titled, closable, miniaturisable, **resizable**, `NSWindowCollectionBehaviorFullScreenPrimary`. Content view is `TToasterView` (unflipped, so the y-down buffer is not drawn upside down). Background is black.

**9.** `syncCanvasSize` reads `view.bounds × scale` and `Resize`s the buffer if AppKit's first layout is not exactly 800×500.

**10.** `redraw` → `controller.Render` → `RenderToasters` → copy into a fresh `NSImage` → `setNeedsDisplay`. The window is not blank when it appears.

**11.** Timer is armed at **1/30 s**. Unlike the clock (which only repaints on a new second), every tick moves and paints, because wings flap continuously.

```pascal
animTimer := NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats(
  1.0 / 30.0, self, objcselector('tick:'), nil, True);
```

---

## Phase C — one animation tick

**12.** `tick:` calls `controller.Tick`.

**13.** `Tick` samples `GetTickCount64`, converts to seconds, **caps `dt` at 0.05** (same hitch guard as StarfieldPanel), then `Model.Update(dt, width, height)`.

**14.** For each entity:

```
X += -Speed * √2/2 * dt
Y += +Speed * √2/2 * dt
Anim += FlapRate * dt
```

If the sprite has left the bottom-left, `SpawnEntity(index, scatter=False)` places it on the top or right edge with a new scale/speed. The array slot is reused; nothing is allocated.

**15.** `NeedsPresent` is set. `redraw` paints:

1. Clear black
2. Optional star dots
3. Entities sorted by `Scale` (small / far first)
4. Optional karaoke line + bouncing ball
5. Optional HUD

**16.** Cocoa copies the RGBA bytes into an `NSImage` and invalidates the view. Windows uses `CopyBGRA` + `StretchDIBits`. GTK copies into a `GdkPixbuf`.

---

## Phase D — a key

**17.** `[` `]` `D` `A` `S` `K` `H` `M` `Space` reach `TToasterController.ApplyChar`. Density and accessories rebuild the pool (scatter again). Darkness applies to **newly spawned** toast. Starfield / karaoke / HUD are flags the renderer reads on the next frame. Settings are written to the INI when the controller is destroyed.

**18.** F11 / double-click / View menu toggle fullscreen on the host. `SetFullScreen` only records the fact; `Resize` arrives with the new pixel size.

---

## Headless paths

`make test` never opens a window. It checks the 45° vector, wrap/freeze, and `ApplyChar`.

`make snap` builds a controller with `Persist=False`, calls `PlaceCataloguePose`, and writes PPM files so the chrome bodies and toast can be inspected without AppKit.
