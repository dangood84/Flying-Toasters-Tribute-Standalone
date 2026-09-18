unit uhostcocoa;

{$mode objfpc}{$H+}
{$modeswitch objectivec1}
{$linkframework AudioToolbox}

{ macOS titled, resizable window. Regular activation policy so there is a
  Dock icon. Same TToasterController as Windows/Linux; this unit presents
  pixels, runs the 30 Hz timer, and forwards fullscreen / keys.
  MIDI march uses AudioToolbox's DLS player, with an NSSound WAV fallback. }

interface

procedure HostRun;

implementation

uses
  SysUtils, Math, CocoaAll, utoasterconfig, utoasterapp, utoasteraudio;

const
  WinPointsW = 800;
  WinPointsH = 500;
  MinPointsW = 320;
  MinPointsH = 200;
  TickInterval = 1.0 / 30.0;

type
  TToasterView = objcclass;
  TToasterWindow = objcclass;

  NSBitmapImageRepToaster = objccategory external (NSBitmapImageRep)
    function initRGBA(planes: Pointer; aWidth: NSInteger; aHeight: NSInteger;
      aBits: NSInteger; aSamples: NSInteger; aAlpha: ObjCBOOL;
      aPlanar: ObjCBOOL; aSpace: NSString; aBpr: NSInteger;
      aBpp: NSInteger): id; message 'initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:';
  end;

  TAppDelegate = objcclass(NSObject, NSApplicationDelegateProtocol, NSWindowDelegateProtocol)
  public
    controller: TToasterController;
    window: TToasterWindow;
    view: TToasterView;
    frameImage: NSImage;
    animTimer: NSTimer;
    marchSound: NSSound;
    lastAudio: Integer;
    lastPlay: ObjCBOOL;
    scale: Double;
    ready: ObjCBOOL;
    procedure applicationDidFinishLaunching(notification: NSNotification); message 'applicationDidFinishLaunching:';
    function applicationShouldTerminateAfterLastWindowClosed(sender: NSApplication): ObjCBOOL; message 'applicationShouldTerminateAfterLastWindowClosed:';
    procedure quitAction(sender: id); message 'quitAction:';
    procedure aboutAction(sender: id); message 'aboutAction:';
    procedure fullscreenAction(sender: id); message 'fullscreenAction:';
    procedure muteAction(sender: id); message 'muteAction:';
    procedure marchAction(sender: id); message 'marchAction:';
    procedure choirAction(sender: id); message 'choirAction:';
    procedure windowDidResize(notification: NSNotification); message 'windowDidResize:';
    procedure windowDidEnterFullScreen(notification: NSNotification); message 'windowDidEnterFullScreen:';
    procedure windowDidExitFullScreen(notification: NSNotification); message 'windowDidExitFullScreen:';
    procedure tick(timer: NSTimer); message 'tick:';
    procedure redraw; message 'redraw';
    procedure syncCanvasSize; message 'syncCanvasSize';
    procedure syncAudio; message 'syncAudio';
    procedure setup; message 'setup';
  end;

  TToasterWindow = objcclass(NSWindow)
  public
    app: TAppDelegate;
    function canBecomeKeyWindow: ObjCBOOL; override;
  end;

  TToasterView = objcclass(NSView)
  public
    app: TAppDelegate;
    procedure drawRect(dirtyRect: NSRect); override;
    function acceptsFirstResponder: ObjCBOOL; override;
    function acceptsFirstMouse(theEvent: NSEvent): ObjCBOOL; override;
    procedure mouseDown(event: NSEvent); override;
    procedure keyDown(event: NSEvent); override;
  end;

var
  SharedApp: TAppDelegate;
  GMidiPlayer: Pointer;
  GMidiSeq: Pointer;

type
  MusicPlayer = Pointer;
  MusicSequence = Pointer;
  OSStatus = Int32;

function NewMusicPlayer(out inPlayer: MusicPlayer): OSStatus; cdecl; external;
function DisposeMusicPlayer(inPlayer: MusicPlayer): OSStatus; cdecl; external;
function NewMusicSequence(out outSequence: MusicSequence): OSStatus; cdecl; external;
function DisposeMusicSequence(inSequence: MusicSequence): OSStatus; cdecl; external;
function MusicPlayerSetSequence(inPlayer: MusicPlayer; inSequence: MusicSequence): OSStatus; cdecl; external;
function MusicPlayerStart(inPlayer: MusicPlayer): OSStatus; cdecl; external;
function MusicPlayerStop(inPlayer: MusicPlayer): OSStatus; cdecl; external;
function MusicPlayerSetTime(inPlayer: MusicPlayer; inTime: Double): OSStatus; cdecl; external;
function MusicPlayerGetTime(inPlayer: MusicPlayer; out outTime: Double): OSStatus; cdecl; external;
function MusicPlayerPreroll(inPlayer: MusicPlayer): OSStatus; cdecl; external;
function MusicSequenceFileLoadData(inSequence: MusicSequence; inData: Pointer;
  inFileTypeHint: UInt32; inFlags: UInt32): OSStatus; cdecl; external;

const
  kMusicSequenceFileMIDIType = $6D696469; { 'midi' }

procedure StopMidiEngine;
begin
  if GMidiPlayer <> nil then
  begin
    MusicPlayerStop(GMidiPlayer);
    DisposeMusicPlayer(GMidiPlayer);
    GMidiPlayer := nil;
  end;
  if GMidiSeq <> nil then
  begin
    DisposeMusicSequence(GMidiSeq);
    GMidiSeq := nil;
  end;
end;

function StartMidiEngine(Mode: TAudioMode): Boolean;
var
  Bytes: TBytes;
  Data: NSData;
  St: OSStatus;
begin
  Result := False;
  StopMidiEngine;
  if Mode = amMute then
    Exit;
  Bytes := BuildMidiFile(Mode);
  if Length(Bytes) < 20 then
    Exit;
  Data := NSData.dataWithBytes_length(@Bytes[0], Length(Bytes));
  if Data = nil then
    Exit;
  St := NewMusicSequence(GMidiSeq);
  if St = 0 then
    St := MusicSequenceFileLoadData(GMidiSeq, Pointer(Data), kMusicSequenceFileMIDIType, 0);
  if St <> 0 then
  begin
    StopMidiEngine;
    Exit;
  end;
  St := NewMusicPlayer(GMidiPlayer);
  if St = 0 then
    St := MusicPlayerSetSequence(GMidiPlayer, GMidiSeq);
  if St = 0 then
    St := MusicPlayerPreroll(GMidiPlayer);
  if St = 0 then
    St := MusicPlayerStart(GMidiPlayer);
  Result := St = 0;
  if not Result then
    StopMidiEngine;
end;

procedure PumpMidiLoop;
var
  T: Double;
begin
  if GMidiPlayer = nil then
    Exit;
  T := 0;
  if MusicPlayerGetTime(GMidiPlayer, T) <> 0 then
    Exit;
  if T >= MidiLoopBeats then
    MusicPlayerSetTime(GMidiPlayer, T - MidiLoopBeats * Floor(T / MidiLoopBeats));
end;

function NSStr(const S: string): NSString;
begin
  Result := NSString.stringWithUTF8String(PChar(S));
end;

function MakeImage(Pixels: PByte; PixelW, PixelH: Integer; PointW, PointH: Double): NSImage;
var
  Rep: NSBitmapImageRep;
  Dest: PByte;
  Bytes: Integer;
begin
  Rep := NSBitmapImageRep(NSBitmapImageRep.alloc.initRGBA(nil, PixelW, PixelH, 8, 4,
    True, False, NSCalibratedRGBColorSpace, PixelW * 4, 32));
  Result := NSImage.alloc.initWithSize(NSMakeSize(PointW, PointH));
  if Rep <> nil then
  begin
    Dest := PByte(Rep.bitmapData);
    Bytes := PixelW * PixelH * 4;
    if (Dest <> nil) and (Pixels <> nil) and (Bytes > 0) then
      Move(Pixels^, Dest^, Bytes);
    Result.addRepresentation(Rep);
    Rep.release;
  end;
  Result.setCacheMode(NSImageCacheNever);
end;

procedure TAppDelegate.redraw;
var
  B: NSRect;
begin
  if (controller = nil) or (view = nil) then
    Exit;
  controller.Render;
  B := view.bounds;
  if frameImage <> nil then
    frameImage.release;
  frameImage := MakeImage(controller.Canvas.Ptr, controller.Canvas.Width,
    controller.Canvas.Height, B.size.width, B.size.height);
  controller.ConsumePresent;
  view.setNeedsDisplay_(True);
end;

procedure TAppDelegate.syncCanvasSize;
var
  B: NSRect;
  PW, PH: Integer;
begin
  if (view = nil) or (controller = nil) then
    Exit;
  B := view.bounds;
  PW := Max(1, Round(B.size.width * scale));
  PH := Max(1, Round(B.size.height * scale));
  controller.Resize(PW, PH);
end;

procedure TAppDelegate.tick(timer: NSTimer);
var
  Pool: NSAutoreleasePool;
begin
  Pool := NSAutoreleasePool.alloc.init;
  if controller <> nil then
  begin
    controller.Tick;
    syncAudio;
    if controller.NeedsPresent then
      redraw;
  end;
  Pool.release;
end;

procedure TAppDelegate.syncAudio;
var
  Want: ObjCBOOL;
  Mode: TAudioMode;
  Wav: TBytes;
  Data: NSData;
begin
  if controller = nil then
    Exit;
  Mode := controller.Model.Config.Audio;
  Want := controller.AudioShouldPlay;
  if (Ord(Mode) = lastAudio) and (Want = lastPlay) then
  begin
    if Want then
      PumpMidiLoop;
    Exit;
  end;
  lastAudio := Ord(Mode);
  lastPlay := Want;
  if marchSound <> nil then
  begin
    marchSound.stop;
    marchSound.release;
    marchSound := nil;
  end;
  StopMidiEngine;
  if not Want then
    Exit;
  if StartMidiEngine(Mode) then
    Exit;
  { DLS player unavailable: same score as a looping 8-bit WAV. }
  Wav := BuildMarchWav(Mode);
  if Length(Wav) < 44 then
    Exit;
  Data := NSData.dataWithBytes_length(@Wav[0], Length(Wav));
  marchSound := NSSound.alloc.initWithData(Data);
  if marchSound <> nil then
  begin
    marchSound.setLoops(True);
    marchSound.play;
  end;
end;

procedure SetupMenu(Del: TAppDelegate);
var
  MainMenu, AppMenu, ViewMenu, SoundMenu: NSMenu;
  AppItem, ViewItem, SoundItem, Item: NSMenuItem;
begin
  MainMenu := NSMenu.alloc.init;

  AppItem := NSMenuItem.alloc.init;
  AppMenu := NSMenu.alloc.initWithTitle(NSStr('Flying Toasters'));
  Item := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSStr('About Flying Toasters'), objcselector('aboutAction:'), NSStr(''));
  Item.setTarget(Del);
  AppMenu.addItem(Item);
  Item.release;
  AppMenu.addItem(NSMenuItem.separatorItem);
  Item := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSStr('Quit Flying Toasters'), objcselector('quitAction:'), NSStr('q'));
  Item.setTarget(Del);
  AppMenu.addItem(Item);
  Item.release;
  AppItem.setSubmenu(AppMenu);
  MainMenu.addItem(AppItem);

  ViewItem := NSMenuItem.alloc.init;
  ViewMenu := NSMenu.alloc.initWithTitle(NSStr('View'));
  Item := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSStr('Full Screen'), objcselector('fullscreenAction:'), NSStr('f'));
  Item.setKeyEquivalentModifierMask(NSCommandKeyMask or NSControlKeyMask);
  Item.setTarget(Del);
  ViewMenu.addItem(Item);
  Item.release;
  ViewItem.setSubmenu(ViewMenu);
  MainMenu.addItem(ViewItem);

  SoundItem := NSMenuItem.alloc.init;
  SoundMenu := NSMenu.alloc.initWithTitle(NSStr('Sound'));
  Item := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSStr('Mute'), objcselector('muteAction:'), NSStr(''));
  Item.setTarget(Del);
  SoundMenu.addItem(Item);
  Item.release;
  Item := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSStr('MIDI March'), objcselector('marchAction:'), NSStr('m'));
  Item.setTarget(Del);
  SoundMenu.addItem(Item);
  Item.release;
  Item := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSStr('Choir'), objcselector('choirAction:'), NSStr(''));
  Item.setTarget(Del);
  SoundMenu.addItem(Item);
  Item.release;
  SoundItem.setSubmenu(SoundMenu);
  MainMenu.addItem(SoundItem);

  NSApplication.sharedApplication.setMainMenu(MainMenu);
  SoundMenu.release;
  SoundItem.release;
  ViewMenu.release;
  ViewItem.release;
  AppMenu.release;
  AppItem.release;
  MainMenu.release;
end;

procedure TAppDelegate.setup;
var
  PixelScale: Double;
  Style: NSUInteger;
  Rect, Vis: NSRect;
begin
  if ready then
    Exit;
  ready := True;

  PixelScale := 2;
  if NSScreen.mainScreen <> nil then
    PixelScale := NSScreen.mainScreen.backingScaleFactor;
  if PixelScale < 1 then
    PixelScale := 1;
  scale := PixelScale;

  controller := TToasterController.Create(
    Round(WinPointsW * scale), Round(WinPointsH * scale), LoadConfig);
  lastAudio := -1;
  lastPlay := False;
  marchSound := nil;

  SetupMenu(self);

  Style := NSTitledWindowMask or NSClosableWindowMask or
    NSMiniaturizableWindowMask or NSResizableWindowMask;
  Rect := NSMakeRect(80, 60, WinPointsW, WinPointsH);
  if NSScreen.mainScreen <> nil then
  begin
    Vis := NSScreen.mainScreen.visibleFrame;
    Rect := NSMakeRect(
      Vis.origin.x + Trunc((Vis.size.width - WinPointsW) / 2),
      Vis.origin.y + Trunc((Vis.size.height - WinPointsH) / 2),
      WinPointsW, WinPointsH);
  end;
  window := TToasterWindow.alloc.initWithContentRect_styleMask_backing_defer(
    Rect, Style, NSBackingStoreBuffered, False);
  window.app := self;
  window.setTitle(NSStr('Flying Toasters'));
  window.setReleasedWhenClosed(False);
  window.setOpaque(True);
  window.setBackgroundColor(NSColor.colorWithCalibratedRed_green_blue_alpha(0, 0, 0, 1.0));
  window.setContentMinSize(NSMakeSize(MinPointsW, MinPointsH));
  window.setCollectionBehavior(NSWindowCollectionBehaviorFullScreenPrimary);
  window.setDelegate(self);

  view := TToasterView.alloc.initWithFrame(NSMakeRect(0, 0, WinPointsW, WinPointsH));
  view.app := self;
  window.setContentView(view);
  window.makeFirstResponder(view);

  syncCanvasSize;
  redraw;

  animTimer := NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats(
    TickInterval, self, objcselector('tick:'), nil, True);
  animTimer.retain;
  NSRunLoop.currentRunLoop.addTimer_forMode(animTimer, NSRunLoopCommonModes);

  NSApplication.sharedApplication.activateIgnoringOtherApps(True);
  window.makeKeyAndOrderFront(nil);
end;

procedure TAppDelegate.applicationDidFinishLaunching(notification: NSNotification);
begin
  setup;
end;

function TAppDelegate.applicationShouldTerminateAfterLastWindowClosed(sender: NSApplication): ObjCBOOL;
begin
  Result := True;
end;

procedure TAppDelegate.quitAction(sender: id);
begin
  if marchSound <> nil then
  begin
    marchSound.stop;
    marchSound.release;
    marchSound := nil;
  end;
  StopMidiEngine;
  NSApplication.sharedApplication.terminate(nil);
end;

procedure TAppDelegate.aboutAction(sender: id);
var
  Alert: NSAlert;
begin
  Alert := NSAlert.alloc.init;
  Alert.setMessageText(NSStr(ToasterAboutTitle));
  Alert.setInformativeText(NSStr(ToasterAboutText));
  Alert.runModal;
  Alert.release;
end;

procedure TAppDelegate.fullscreenAction(sender: id);
begin
  if window <> nil then
    window.toggleFullScreen(nil);
end;

procedure TAppDelegate.muteAction(sender: id);
begin
  if controller <> nil then
    controller.SetAudioMode(amMute);
end;

procedure TAppDelegate.marchAction(sender: id);
begin
  if controller <> nil then
    controller.SetAudioMode(amMarch);
end;

procedure TAppDelegate.choirAction(sender: id);
begin
  if controller <> nil then
    controller.SetAudioMode(amChoir);
end;

procedure TAppDelegate.windowDidResize(notification: NSNotification);
begin
  syncCanvasSize;
  redraw;
end;

procedure TAppDelegate.windowDidEnterFullScreen(notification: NSNotification);
begin
  if controller <> nil then
    controller.SetFullScreen(True);
  syncCanvasSize;
  redraw;
end;

procedure TAppDelegate.windowDidExitFullScreen(notification: NSNotification);
begin
  if controller <> nil then
    controller.SetFullScreen(False);
  syncCanvasSize;
  redraw;
end;

procedure TToasterView.drawRect(dirtyRect: NSRect);
begin
  NSColor.colorWithCalibratedRed_green_blue_alpha(0, 0, 0, 1.0).set_;
  NSRectFill(self.bounds);
  if (app = nil) or (app.frameImage = nil) then
    Exit;
  app.frameImage.drawInRect_fromRect_operation_fraction(self.bounds, NSZeroRect,
    NSCompositeSourceOver, 1.0);
end;

function TToasterView.acceptsFirstResponder: ObjCBOOL;
begin
  Result := True;
end;

function TToasterView.acceptsFirstMouse(theEvent: NSEvent): ObjCBOOL;
begin
  Result := True;
end;

procedure TToasterView.mouseDown(event: NSEvent);
begin
  if app = nil then
    Exit;
  self.window.makeFirstResponder(self);
  if (event <> nil) and (event.clickCount >= 2) then
    app.fullscreenAction(nil);
end;

procedure TToasterView.keyDown(event: NSEvent);
var
  Code: Word;
  P: PChar;
  S: string;
begin
  if (app = nil) or (event = nil) then
  begin
    inherited keyDown(event);
    Exit;
  end;
  Code := event.keyCode;
  case Code of
    53:
      if app.controller.FullScreen then
        app.fullscreenAction(nil)
      else
        inherited keyDown(event);
    103:
      app.fullscreenAction(nil);
    else
      begin
        S := '';
        if event.charactersIgnoringModifiers <> nil then
        begin
          P := event.charactersIgnoringModifiers.UTF8String;
          if (P <> nil) and (P^ <> #0) then
            S := string(P);
        end;
        if S <> '' then
          app.controller.ApplyChar(S[1])
        else
          inherited keyDown(event);
      end;
  end;
end;

function TToasterWindow.canBecomeKeyWindow: ObjCBOOL;
begin
  Result := True;
end;

procedure HostRun;
var
  Pool: NSAutoreleasePool;
  App: NSApplication;
begin
  Pool := NSAutoreleasePool.alloc.init;
  App := NSApplication.sharedApplication;
  App.setActivationPolicy(NSApplicationActivationPolicyRegular);
  SharedApp := TAppDelegate.alloc.init;
  App.setDelegate(SharedApp);
  SharedApp.setup;
  App.run;
  if SharedApp <> nil then
  begin
    if SharedApp.marchSound <> nil then
    begin
      SharedApp.marchSound.stop;
      SharedApp.marchSound.release;
      SharedApp.marchSound := nil;
    end;
  end;
  StopMidiEngine;
  Pool.release;
end;

end.
