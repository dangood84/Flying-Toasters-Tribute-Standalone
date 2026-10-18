unit uhostgtk;

{$mode objfpc}{$H+}

{ Linux GTK 2 window. Same TToasterController as macOS; this unit presents
  a GdkPixbuf on a drawing area, a 33 ms timeout, F11 fullscreen, and
  option keys. GTK 2 is the Raspberry Pi OS-friendly toolkit the other
  Pascal apps use.

  Sound is one raw pw-play / paplay / aplay stream for the life of the
  window. NoBugs on a Panasonic television taught this: a fresh player
  for every shout lets HDMI fall asleep, so the first pip is late or
  missing. Silence keeps the port awake; MIDI/choir is mixed into the
  next short slice. }

interface

procedure HostRun;

implementation

{$IF DEFINED(UNIX) AND NOT DEFINED(DARWIN)}

uses
  SysUtils, ctypes, Process, BaseUnix, gtk2, gdk2, gdk2pixbuf, glib2,
  utoasterconfig, utoasterapp, utoasteraudio;

const
  WinW = 800;
  WinH = 500;
  MinW = 320;
  MinH = 200;
  TickMs = 33;
  ChunkFrames = 728; { one paint tick, ~33 ms at MarchSampleRate }

  GDK_Escape = $FF1B;
  GDK_F11 = $FFC8;
  GDK_space = $020;
  GDK_bracketleft = $05B;
  GDK_bracketright = $05D;

var
  Controller: TToasterController;
  MainWin: PGtkWidget;
  DrawArea: PGtkWidget;
  MenuBar: PGtkWidget;
  Pix: PGdkPixbuf;
  FullScreen: Boolean;
  AreaW, AreaH: Integer;
  Player: TProcess;
  Pending, MarchPcm: TBytes;
  MarchPos: Integer;
  LastAudio: Integer;
  LastPlay: Boolean;
  NextFeed: QWord;
  RetryAt: QWord;
  Reported: Boolean;

function PlayerExe: string;
begin
  if FileExists('/usr/bin/pw-play') then
    Result := '/usr/bin/pw-play'
  else if FileExists('/usr/bin/pw-cat') then
    Result := '/usr/bin/pw-cat'
  else if FileExists('/usr/bin/paplay') then
    Result := '/usr/bin/paplay'
  else if FileExists('/usr/bin/aplay') then
    Result := '/usr/bin/aplay'
  else
    Result := '';
end;

procedure Unblock(H: THandle);
var
  Flags: cint;
begin
  Flags := fpfcntl(H, F_GETFL);
  if Flags >= 0 then
    fpfcntl(H, F_SETFL, Flags or O_NONBLOCK);
end;

procedure SpeakPlayer;
var
  Buf: array[0..511] of Byte;
  N, At: Integer;
  Msg: string;
begin
  if (Player = nil) or (Player.Output = nil) then
    Exit;
  Msg := '';
  repeat
    N := FileRead(Player.Output.Handle, Buf, SizeOf(Buf));
    if N > 0 then
    begin
      At := Length(Msg);
      SetLength(Msg, At + N);
      Move(Buf[0], Msg[At + 1], N);
    end;
  until N <= 0;
  if Msg <> '' then
  begin
    Writeln(Msg);
    Flush(Output);
  end;
end;

procedure ClosePlayer;
begin
  FreeAndNil(Player);
  Pending := nil;
end;

function OpenPlayer: Boolean;
var
  Exe, Name: string;
begin
  Result := False;
  if GetTickCount64 < RetryAt then
    Exit;
  Exe := PlayerExe;
  if Exe = '' then
  begin
    if not Reported then
    begin
      Writeln('audio channel: no pw-play, paplay, or aplay');
      Flush(Output);
      Reported := True;
    end;
    RetryAt := GetTickCount64 + 5000;
    Exit;
  end;
  ClosePlayer;
  Player := TProcess.Create(nil);
  Player.Executable := Exe;
  Name := ExtractFileName(Exe);
  if (Name = 'pw-play') or (Name = 'pw-cat') then
  begin
    if Name = 'pw-cat' then
      Player.Parameters.Add('--playback');
    Player.Parameters.Add('--raw');
    Player.Parameters.Add('--format=s16');
    Player.Parameters.Add('--rate=' + IntToStr(MarchSampleRate));
    Player.Parameters.Add('--channels=1');
    Player.Parameters.Add('-');
  end
  else if Name = 'paplay' then
  begin
    Player.Parameters.Add('--raw');
    Player.Parameters.Add('--format=s16le');
    Player.Parameters.Add('--rate=' + IntToStr(MarchSampleRate));
    Player.Parameters.Add('--channels=1');
  end
  else
  begin
    Player.Parameters.Add('-q');
    Player.Parameters.Add('-t');
    Player.Parameters.Add('raw');
    Player.Parameters.Add('-f');
    Player.Parameters.Add('S16_LE');
    Player.Parameters.Add('-r');
    Player.Parameters.Add(IntToStr(MarchSampleRate));
    Player.Parameters.Add('-c');
    Player.Parameters.Add('1');
  end;
  Player.Options := [poUsePipes, poStderrToOutPut];
  try
    Player.Execute;
  except
    ClosePlayer;
    RetryAt := GetTickCount64 + 1000;
    Exit;
  end;
  if Player.Input <> nil then
    Unblock(Player.Input.Handle);
  if Player.Output <> nil then
    Unblock(Player.Output.Handle);
  if not Player.Running then
  begin
    SpeakPlayer;
    Writeln('audio channel did not stay open');
    Flush(Output);
    ClosePlayer;
    RetryAt := GetTickCount64 + 1000;
    Exit;
  end;
  { State change: raw stream open. Silence from the timer keeps HDMI awake. }
  Writeln('audio channel open (', Name, ')');
  Flush(Output);
  NextFeed := 0;
  Result := True;
end;

procedure FlushPending;
var
  Got: Integer;
  Err: cint;
begin
  if (Player = nil) or (Player.Input = nil) or (Length(Pending) = 0) then
    Exit;
  Got := FileWrite(Player.Input.Handle, Pending[0], Length(Pending));
  if Got > 0 then
    Delete(Pending, 0, Got)
  else if Got < 0 then
  begin
    Err := fpgeterrno;
    if (Err = ESysEINTR) or (Err = ESysEAGAIN) or (Err = ESysEWOULDBLOCK) then
      Exit;
    SpeakPlayer;
    Writeln('audio channel closed');
    Flush(Output);
    ClosePlayer;
    RetryAt := GetTickCount64 + 1000;
  end;
end;

procedure FillChunk(var Frames: array of SmallInt);
var
  I, N: Integer;
  Src: PSmallInt;
  Want: Boolean;
  Mode: TAudioMode;
begin
  Want := (Controller <> nil) and Controller.AudioShouldPlay;
  if Controller <> nil then
    Mode := Controller.Model.Config.Audio
  else
    Mode := amMute;
  if Want and ((Ord(Mode) <> LastAudio) or (Want <> LastPlay) or (Length(MarchPcm) = 0)) then
  begin
    MarchPcm := BuildMarchPcm(Mode);
    MarchPos := 0;
  end;
  LastAudio := Ord(Mode);
  LastPlay := Want;
  if (not Want) or (Length(MarchPcm) < 2) then
  begin
    FillChar(Frames[0], Length(Frames) * SizeOf(SmallInt), 0);
    Exit;
  end;
  N := Length(MarchPcm) div 2;
  Src := PSmallInt(@MarchPcm[0]);
  for I := 0 to High(Frames) do
  begin
    Frames[I] := Src[MarchPos];
    Inc(MarchPos);
    if MarchPos >= N then
      MarchPos := 0;
  end;
end;

procedure PumpAudio;
var
  Now: QWord;
  Frames: array[0..ChunkFrames - 1] of SmallInt;
  Old: Integer;
begin
  if (Player = nil) or not Player.Running then
  begin
    if (Player <> nil) and not Player.Running then
    begin
      SpeakPlayer;
      Writeln('audio channel closed');
      Flush(Output);
      ClosePlayer;
      RetryAt := GetTickCount64 + 1000;
    end;
    if not OpenPlayer then
      Exit;
  end;
  SpeakPlayer;
  Now := GetTickCount64;
  if Now >= NextFeed then
  begin
    { One slice per tick. A second slice would sit in the pipe and
      the march would drift away from the wings. }
    if Length(Pending) < ChunkFrames * 2 then
    begin
      FillChunk(Frames);
      Old := Length(Pending);
      SetLength(Pending, Old + SizeOf(Frames));
      Move(Frames[0], Pending[Old], SizeOf(Frames));
    end;
    NextFeed := Now + TickMs;
  end;
  FlushPending;
end;

procedure DestroyPix;
begin
  if Pix <> nil then
  begin
    g_object_unref(Pix);
    Pix := nil;
  end;
end;

procedure EnsurePixbuf;
begin
  if (Controller.Canvas.Width < 1) or (Controller.Canvas.Height < 1) then
    Exit;
  if (Pix <> nil) and
     (gdk_pixbuf_get_width(Pix) = Controller.Canvas.Width) and
     (gdk_pixbuf_get_height(Pix) = Controller.Canvas.Height) then
    Exit;
  DestroyPix;
  Pix := gdk_pixbuf_new(GDK_COLORSPACE_RGB, True, 8,
    Controller.Canvas.Width, Controller.Canvas.Height);
end;

procedure PixbufFromBuffer;
var
  Pixels: PByte;
  Row: Integer;
  Src, Dst: PByte;
  BufW: Integer;
begin
  EnsurePixbuf;
  if Pix = nil then
    Exit;
  BufW := Controller.Canvas.Width;
  Pixels := PByte(gdk_pixbuf_get_pixels(Pix));
  for Row := 0 to Controller.Canvas.Height - 1 do
  begin
    Src := Controller.Canvas.Ptr + Row * BufW * 4;
    Dst := Pixels + Row * gdk_pixbuf_get_rowstride(Pix);
    Move(Src^, Dst^, BufW * 4);
  end;
end;

procedure Present;
begin
  Controller.Render;
  PixbufFromBuffer;
  Controller.ConsumePresent;
  if DrawArea <> nil then
    gtk_widget_queue_draw(DrawArea);
end;

procedure ShowAbout(Parent: PGtkWidget);
var
  Dlg: PGtkWidget;
begin
  Dlg := gtk_message_dialog_new(PGtkWindow(Parent), GTK_DIALOG_MODAL,
    GTK_MESSAGE_INFO, GTK_BUTTONS_OK, PChar(ToasterAboutText));
  gtk_window_set_title(PGtkWindow(Dlg), ToasterAboutTitle);
  gtk_dialog_run(PGtkDialog(Dlg));
  gtk_widget_destroy(Dlg);
end;

procedure ApplyFullScreen(Enter: Boolean);
begin
  if Enter = FullScreen then
    Exit;
  FullScreen := Enter;
  Controller.SetFullScreen(Enter);
  if Enter then
  begin
    gtk_widget_hide(MenuBar);
    gtk_window_fullscreen(PGtkWindow(MainWin));
  end
  else
  begin
    gtk_window_unfullscreen(PGtkWindow(MainWin));
    gtk_widget_show(MenuBar);
  end;
end;

procedure ToggleFullScreen;
begin
  ApplyFullScreen(not FullScreen);
end;

procedure OnQuit(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  gtk_main_quit;
end;

procedure OnAbout(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  ShowAbout(MainWin);
end;

procedure OnFullScreen(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  ToggleFullScreen;
end;

procedure OnMute(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  Controller.SetAudioMode(amMute);
end;

procedure OnMarch(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  Controller.SetAudioMode(amMarch);
end;

procedure OnChoir(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  Controller.SetAudioMode(amChoir);
end;

function OnDelete(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
begin
  gtk_main_quit;
  Result := False;
end;

function OnTick(Data: gpointer): gboolean; cdecl;
begin
  Controller.Tick;
  PumpAudio;
  if Controller.NeedsPresent then
    Present;
  Result := True;
end;

function OnConfigure(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
var
  W, H: Integer;
begin
  W := Event^.configure.width;
  H := Event^.configure.height;
  if W < 1 then
    W := 1;
  if H < 1 then
    H := 1;
  if (W <> AreaW) or (H <> AreaH) then
  begin
    AreaW := W;
    AreaH := H;
    Controller.Resize(W, H);
    Present;
  end;
  Result := False;
end;

function OnExpose(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
var
  DestW, DestH: Integer;
begin
  Result := False;
  if (Pix = nil) or (Widget^.window = nil) then
    Exit;
  DestW := gdk_pixbuf_get_width(Pix);
  DestH := gdk_pixbuf_get_height(Pix);
  gdk_pixbuf_render_to_drawable(Pix, Widget^.window,
    Widget^.style^.fg_gc[GTK_WIDGET_STATE(Widget)],
    0, 0, 0, 0, DestW, DestH, GDK_RGB_DITHER_NONE, 0, 0);
end;

function OnButtonPress(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
begin
  Result := False;
  if Event^.button._type = GDK_2BUTTON_PRESS then
  begin
    ToggleFullScreen;
    Result := True;
  end;
end;

function OnKey(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
var
  KV: guint;
  Ch: Char;
begin
  Result := False;
  KV := Event^.key.keyval;
  if KV = GDK_F11 then
  begin
    ToggleFullScreen;
    Result := True;
  end
  else if (KV = GDK_Escape) and FullScreen then
  begin
    ApplyFullScreen(False);
    Result := True;
  end
  else if KV = GDK_space then
  begin
    Controller.ApplyChar(' ');
    Result := True;
  end
  else if KV = GDK_bracketleft then
  begin
    Controller.ApplyChar('[');
    Result := True;
  end
  else if KV = GDK_bracketright then
  begin
    Controller.ApplyChar(']');
    Result := True;
  end
  else if ((KV >= Ord('A')) and (KV <= Ord('Z'))) or
          ((KV >= Ord('a')) and (KV <= Ord('z'))) then
  begin
    Ch := Chr(KV);
    Controller.ApplyChar(Ch);
    Result := True;
  end;
end;

function OnWindowState(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
var
  NowFull: Boolean;
begin
  NowFull := (Event^.window_state.new_window_state and GDK_WINDOW_STATE_FULLSCREEN) <> 0;
  if NowFull <> FullScreen then
  begin
    FullScreen := NowFull;
    Controller.SetFullScreen(NowFull);
    if NowFull then
      gtk_widget_hide(MenuBar)
    else
      gtk_widget_show(MenuBar);
  end;
  Result := False;
end;

function BuildMenuBar: PGtkWidget;
var
  Bar, Menu, Item, Root: PGtkWidget;
begin
  Bar := gtk_menu_bar_new;

  Menu := gtk_menu_new;
  Root := gtk_menu_item_new_with_label('Flying Toasters');
  gtk_menu_item_set_submenu(PGtkMenuItem(Root), Menu);
  gtk_menu_shell_append(PGtkMenuShell(Bar), Root);
  Item := gtk_menu_item_new_with_label('About Flying Toasters');
  { Linux FPC gtk2 has TGCallback (glib GCallback), not TG_SIGNAL_FUNC. }
  g_signal_connect(G_OBJECT(Item), 'activate', TGCallback(@OnAbout), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_separator_menu_item_new;
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_menu_item_new_with_label('Quit');
  g_signal_connect(G_OBJECT(Item), 'activate', TGCallback(@OnQuit), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);

  Menu := gtk_menu_new;
  Root := gtk_menu_item_new_with_label('View');
  gtk_menu_item_set_submenu(PGtkMenuItem(Root), Menu);
  gtk_menu_shell_append(PGtkMenuShell(Bar), Root);
  Item := gtk_menu_item_new_with_label('Full Screen');
  g_signal_connect(G_OBJECT(Item), 'activate', TGCallback(@OnFullScreen), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);

  Menu := gtk_menu_new;
  Root := gtk_menu_item_new_with_label('Sound');
  gtk_menu_item_set_submenu(PGtkMenuItem(Root), Menu);
  gtk_menu_shell_append(PGtkMenuShell(Bar), Root);
  Item := gtk_menu_item_new_with_label('Mute');
  g_signal_connect(G_OBJECT(Item), 'activate', TGCallback(@OnMute), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_menu_item_new_with_label('MIDI March');
  g_signal_connect(G_OBJECT(Item), 'activate', TGCallback(@OnMarch), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_menu_item_new_with_label('Choir');
  g_signal_connect(G_OBJECT(Item), 'activate', TGCallback(@OnChoir), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);

  Result := Bar;
end;

procedure HostRun;
var
  Box: PGtkWidget;
begin
  gtk_init(@argc, @argv);
  Controller := TToasterController.Create(WinW, WinH, LoadConfig);
  FullScreen := False;
  AreaW := WinW;
  AreaH := WinH;
  Pix := nil;
  LastAudio := -1;
  LastPlay := False;
  MarchPos := 0;
  NextFeed := 0;
  RetryAt := 0;
  Reported := False;

  MainWin := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(PGtkWindow(MainWin), 'Flying Toasters');
  gtk_window_set_resizable(PGtkWindow(MainWin), True);
  gtk_window_set_default_size(PGtkWindow(MainWin), WinW, WinH);
  gtk_widget_set_size_request(MainWin, MinW, MinH);
  g_signal_connect(G_OBJECT(MainWin), 'delete-event', TGCallback(@OnDelete), nil);
  g_signal_connect(G_OBJECT(MainWin), 'key-press-event', TGCallback(@OnKey), nil);
  g_signal_connect(G_OBJECT(MainWin), 'window-state-event', TGCallback(@OnWindowState), nil);

  Box := gtk_vbox_new(False, 0);
  gtk_container_add(PGtkContainer(MainWin), Box);
  MenuBar := BuildMenuBar;
  gtk_box_pack_start(PGtkBox(Box), MenuBar, False, False, 0);

  DrawArea := gtk_drawing_area_new;
  gtk_widget_set_size_request(DrawArea, MinW, MinH);
  gtk_box_pack_start(PGtkBox(Box), DrawArea, True, True, 0);
  gtk_widget_add_events(DrawArea, GDK_BUTTON_PRESS_MASK or GDK_STRUCTURE_MASK);
  g_signal_connect(G_OBJECT(DrawArea), 'configure-event', TGCallback(@OnConfigure), nil);
  g_signal_connect(G_OBJECT(DrawArea), 'expose-event', TGCallback(@OnExpose), nil);
  g_signal_connect(G_OBJECT(DrawArea), 'button-press-event', TGCallback(@OnButtonPress), nil);

  g_timeout_add(TickMs, TGSourceFunc(@OnTick), nil);
  Present;
  gtk_widget_show_all(MainWin);
  OpenPlayer;
  gtk_main;
  ClosePlayer;
  DestroyPix;
  Controller.Free;
end;

{$ELSE}

procedure HostRun;
begin
end;

{$ENDIF}

end.
