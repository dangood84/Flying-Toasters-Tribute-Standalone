unit uhostgtk;

{$mode objfpc}{$H+}

{ Linux GTK 2 window. Same TToasterController as macOS; this unit presents
  a GdkPixbuf on a drawing area, a 33 ms timeout, F11 fullscreen, and
  option keys. GTK 2 is the Raspberry Pi OS-friendly toolkit the other
  Pascal apps use. }

interface

procedure HostRun;

implementation

{$IF DEFINED(UNIX) AND NOT DEFINED(DARWIN)}

uses
  SysUtils, ctypes, gtk2, gdk2, gdk2pixbuf, glib2, utoasterconfig, utoasterapp;

const
  WinW = 800;
  WinH = 500;
  MinW = 320;
  MinH = 200;
  TickMs = 33;

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
  g_signal_connect(G_OBJECT(Item), 'activate', TG_SIGNAL_FUNC(@OnAbout), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_separator_menu_item_new;
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_menu_item_new_with_label('Quit');
  g_signal_connect(G_OBJECT(Item), 'activate', TG_SIGNAL_FUNC(@OnQuit), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);

  Menu := gtk_menu_new;
  Root := gtk_menu_item_new_with_label('View');
  gtk_menu_item_set_submenu(PGtkMenuItem(Root), Menu);
  gtk_menu_shell_append(PGtkMenuShell(Bar), Root);
  Item := gtk_menu_item_new_with_label('Full Screen');
  g_signal_connect(G_OBJECT(Item), 'activate', TG_SIGNAL_FUNC(@OnFullScreen), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);

  Menu := gtk_menu_new;
  Root := gtk_menu_item_new_with_label('Sound');
  gtk_menu_item_set_submenu(PGtkMenuItem(Root), Menu);
  gtk_menu_shell_append(PGtkMenuShell(Bar), Root);
  Item := gtk_menu_item_new_with_label('Mute');
  g_signal_connect(G_OBJECT(Item), 'activate', TG_SIGNAL_FUNC(@OnMute), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_menu_item_new_with_label('MIDI March');
  g_signal_connect(G_OBJECT(Item), 'activate', TG_SIGNAL_FUNC(@OnMarch), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_menu_item_new_with_label('Choir');
  g_signal_connect(G_OBJECT(Item), 'activate', TG_SIGNAL_FUNC(@OnChoir), nil);
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

  MainWin := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(PGtkWindow(MainWin), 'Flying Toasters');
  gtk_window_set_resizable(PGtkWindow(MainWin), True);
  gtk_window_set_default_size(PGtkWindow(MainWin), WinW, WinH);
  gtk_widget_set_size_request(MainWin, MinW, MinH);
  g_signal_connect(G_OBJECT(MainWin), 'delete-event', TG_SIGNAL_FUNC(@OnDelete), nil);
  g_signal_connect(G_OBJECT(MainWin), 'key-press-event', TG_SIGNAL_FUNC(@OnKey), nil);
  g_signal_connect(G_OBJECT(MainWin), 'window-state-event', TG_SIGNAL_FUNC(@OnWindowState), nil);

  Box := gtk_vbox_new(False, 0);
  gtk_container_add(PGtkContainer(MainWin), Box);
  MenuBar := BuildMenuBar;
  gtk_box_pack_start(PGtkBox(Box), MenuBar, False, False, 0);

  DrawArea := gtk_drawing_area_new;
  gtk_widget_set_size_request(DrawArea, MinW, MinH);
  gtk_box_pack_start(PGtkBox(Box), DrawArea, True, True, 0);
  gtk_widget_add_events(DrawArea, GDK_BUTTON_PRESS_MASK or GDK_STRUCTURE_MASK);
  g_signal_connect(G_OBJECT(DrawArea), 'configure-event', TG_SIGNAL_FUNC(@OnConfigure), nil);
  g_signal_connect(G_OBJECT(DrawArea), 'expose-event', TG_SIGNAL_FUNC(@OnExpose), nil);
  g_signal_connect(G_OBJECT(DrawArea), 'button-press-event', TG_SIGNAL_FUNC(@OnButtonPress), nil);

  g_timeout_add(TickMs, TGSourceFunc(@OnTick), nil);
  Present;
  gtk_widget_show_all(MainWin);
  gtk_main;
  DestroyPix;
  Controller.Free;
end;

{$ELSE}

procedure HostRun;
begin
end;

{$ENDIF}

end.
