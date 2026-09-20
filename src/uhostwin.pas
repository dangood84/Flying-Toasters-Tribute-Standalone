unit uhostwin;

{$mode objfpc}{$H+}

{ Windows titled, resizable window on the taskbar. Same TToasterController
  as macOS; this unit presents pixels (BGRA StretchDIBits), a 33 ms
  timer, F11 / double-click fullscreen, and option keys. }

interface

procedure HostRun;

implementation

{$IFDEF WINDOWS}

uses
  Windows, Messages, SysUtils, MMSystem, utoasterrender, utoasterconfig,
  utoasterapp, utoasteraudio;

{ FPC 3.2.2's Win32 Windows unit has no multi-monitor API. user32 does. }
{$if not declared(MonitorFromWindow)}
type
  HMONITOR = type THandle;
  TMonitorInfo = record
    cbSize: DWORD;
    rcMonitor: TRect;
    rcWork: TRect;
    dwFlags: DWORD;
  end;
  PMonitorInfo = ^TMonitorInfo;
{$endif}

const
  AppName = 'FlyingToastersWnd';
  CmdAbout = 1001;
  CmdQuit = 1002;
  CmdFullScreen = 1003;
  CmdMute = 1010;
  CmdMarch = 1011;
  CmdChoir = 1012;
  WinW = 800;
  WinH = 500;
  MinW = 320;
  MinH = 200;
  TickId = 1;
  TickMs = 33;
{$if not declared(MONITOR_DEFAULTTONEAREST)}
  MONITOR_DEFAULTTONEAREST = 2;
{$endif}

var
  Controller: TToasterController;
  MainWnd: HWND;
  Bgra: array of Byte;
  AppMenuBar: HMENU;
  FullScreen: Boolean;
  SavedStyle: LONG;
  SavedRect: TRect;
  SavedMenu: HMENU;
  WavHold: array of Byte;
  LastAudio: Integer;
  LastPlay: Boolean;

{$if not declared(MonitorFromWindow)}
function MonitorFromWindow(hwnd: HWND; dwFlags: DWORD): HMONITOR; stdcall;
  external 'user32.dll' name 'MonitorFromWindow';
function GetMonitorInfo(hMonitor: HMONITOR; lpmi: PMonitorInfo): BOOL; stdcall;
  external 'user32.dll' name 'GetMonitorInfoA';
{$endif}

procedure StopWinAudio;
begin
  PlaySound(nil, 0, 0);
  SetLength(WavHold, 0);
end;

procedure SyncWinAudio;
var
  Want: Boolean;
  Mode: TAudioMode;
begin
  if Controller = nil then
    Exit;
  Mode := Controller.Model.Config.Audio;
  Want := Controller.AudioShouldPlay;
  if (Ord(Mode) = LastAudio) and (Want = LastPlay) then
    Exit;
  LastAudio := Ord(Mode);
  LastPlay := Want;
  StopWinAudio;
  if not Want then
    Exit;
  WavHold := BuildMarchWav(Mode);
  if Length(WavHold) < 44 then
    Exit;
  PlaySound(PChar(@WavHold[0]), 0, SND_MEMORY or SND_ASYNC or SND_LOOP);
end;

procedure Present(Wnd: HWND);
begin
  Controller.Render;
  SetLength(Bgra, Controller.Canvas.Width * Controller.Canvas.Height * 4);
  CopyBGRA(Controller.Canvas, @Bgra[0]);
  Controller.ConsumePresent;
  InvalidateRect(Wnd, nil, False);
end;

procedure PaintSky(Wnd: HWND);
var
  PS: PAINTSTRUCT;
  DC: HDC;
  Info: BITMAPINFO;
  R: TRect;
begin
  DC := BeginPaint(Wnd, @PS);
  GetClientRect(Wnd, @R);
  if Length(Bgra) = Controller.Canvas.Width * Controller.Canvas.Height * 4 then
  begin
    FillChar(Info, SizeOf(Info), 0);
    Info.bmiHeader.biSize := SizeOf(BITMAPINFOHEADER);
    Info.bmiHeader.biWidth := Controller.Canvas.Width;
    Info.bmiHeader.biHeight := -Controller.Canvas.Height;
    Info.bmiHeader.biPlanes := 1;
    Info.bmiHeader.biBitCount := 32;
    Info.bmiHeader.biCompression := BI_RGB;
    StretchDIBits(DC, 0, 0, R.Right - R.Left, R.Bottom - R.Top,
      0, 0, Controller.Canvas.Width, Controller.Canvas.Height,
      @Bgra[0], Info, DIB_RGB_COLORS, SRCCOPY);
  end;
  EndPaint(Wnd, @PS);
end;

procedure SyncCanvas(Wnd: HWND);
var
  R: TRect;
  CW, CH: Integer;
begin
  if not GetClientRect(Wnd, R) then
    Exit;
  CW := R.Right - R.Left;
  CH := R.Bottom - R.Top;
  if (CW < 1) or (CH < 1) then
    Exit;
  Controller.Resize(CW, CH);
end;

procedure ShowAbout(Wnd: HWND);
begin
  MessageBox(Wnd, PChar(ToasterAboutText), ToasterAboutTitle, MB_OK or MB_ICONINFORMATION);
end;

procedure EnterFullScreen(Wnd: HWND);
var
  Mi: TMonitorInfo;
  Mon: HMONITOR;
  Style: LONG;
begin
  if FullScreen then
    Exit;
  GetWindowRect(Wnd, SavedRect);
  SavedStyle := GetWindowLong(Wnd, GWL_STYLE);
  SavedMenu := GetMenu(Wnd);
  SetMenu(Wnd, 0);
  Style := SavedStyle and not (WS_CAPTION or WS_THICKFRAME or WS_BORDER or WS_SYSMENU);
  SetWindowLong(Wnd, GWL_STYLE, Style or WS_POPUP);
  FillChar(Mi, SizeOf(Mi), 0);
  Mi.cbSize := SizeOf(Mi);
  Mon := MonitorFromWindow(Wnd, MONITOR_DEFAULTTONEAREST);
  GetMonitorInfo(Mon, @Mi);
  SetWindowPos(Wnd, HWND_TOP,
    Mi.rcMonitor.Left, Mi.rcMonitor.Top,
    Mi.rcMonitor.Right - Mi.rcMonitor.Left,
    Mi.rcMonitor.Bottom - Mi.rcMonitor.Top,
    SWP_FRAMECHANGED or SWP_SHOWWINDOW);
  FullScreen := True;
  Controller.SetFullScreen(True);
end;

procedure LeaveFullScreen(Wnd: HWND);
begin
  if not FullScreen then
    Exit;
  SetWindowLong(Wnd, GWL_STYLE, SavedStyle);
  SetMenu(Wnd, SavedMenu);
  SetWindowPos(Wnd, HWND_TOP,
    SavedRect.Left, SavedRect.Top,
    SavedRect.Right - SavedRect.Left,
    SavedRect.Bottom - SavedRect.Top,
    SWP_FRAMECHANGED or SWP_SHOWWINDOW);
  FullScreen := False;
  Controller.SetFullScreen(False);
end;

procedure ToggleFullScreen(Wnd: HWND);
begin
  if FullScreen then
    LeaveFullScreen(Wnd)
  else
    EnterFullScreen(Wnd);
end;

procedure HandleKey(Wnd: HWND; Key: WPARAM);
begin
  case Key of
    VK_F11:
      ToggleFullScreen(Wnd);
    VK_ESCAPE:
      if FullScreen then
        LeaveFullScreen(Wnd);
    VK_OEM_4:
      Controller.ApplyChar('[');
    VK_OEM_6:
      Controller.ApplyChar(']');
    VK_SPACE:
      Controller.ApplyChar(' ');
    Ord('D'), Ord('A'), Ord('S'), Ord('K'), Ord('H'), Ord('M'):
      Controller.ApplyChar(Chr(Key));
  end;
end;

function WndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  MinTrack: PMINMAXINFO;
begin
  Result := 0;
  case Msg of
    WM_CREATE:
      begin
        SetTimer(Wnd, TickId, TickMs, nil);
        SyncCanvas(Wnd);
        Present(Wnd);
      end;
    WM_TIMER:
      if WParam = TickId then
      begin
        Controller.Tick;
        SyncWinAudio;
        if Controller.NeedsPresent then
          Present(Wnd);
      end;
    WM_PAINT:
      PaintSky(Wnd);
    WM_SIZE:
      begin
        SyncCanvas(Wnd);
        Present(Wnd);
      end;
    WM_GETMINMAXINFO:
      begin
        MinTrack := PMINMAXINFO(LParam);
        MinTrack^.ptMinTrackSize.X := MinW + 32;
        MinTrack^.ptMinTrackSize.Y := MinH + 48;
      end;
    WM_LBUTTONDBLCLK:
      ToggleFullScreen(Wnd);
    WM_KEYDOWN:
      HandleKey(Wnd, WParam);
    WM_COMMAND:
      case LOWORD(WParam) of
        CmdAbout:
          ShowAbout(Wnd);
        CmdFullScreen:
          ToggleFullScreen(Wnd);
        CmdMute:
          Controller.SetAudioMode(amMute);
        CmdMarch:
          Controller.SetAudioMode(amMarch);
        CmdChoir:
          Controller.SetAudioMode(amChoir);
        CmdQuit:
          PostQuitMessage(0);
      end;
    WM_DESTROY:
      begin
        KillTimer(Wnd, TickId);
        StopWinAudio;
        PostQuitMessage(0);
      end;
    else
      Result := DefWindowProc(Wnd, Msg, WParam, LParam);
  end;
end;

function BuildMenu: HMENU;
var
  Bar, AppMenu, ViewMenu, SoundMenu: HMENU;
begin
  Bar := CreateMenu;
  AppMenu := CreatePopupMenu;
  AppendMenu(AppMenu, MF_STRING, CmdAbout, '&About Flying Toasters...');
  AppendMenu(AppMenu, MF_SEPARATOR, 0, nil);
  AppendMenu(AppMenu, MF_STRING, CmdQuit, 'E&xit');
  AppendMenu(Bar, MF_POPUP, AppMenu, '&Flying Toasters');
  ViewMenu := CreatePopupMenu;
  AppendMenu(ViewMenu, MF_STRING, CmdFullScreen, '&Full Screen'#9'F11');
  AppendMenu(Bar, MF_POPUP, ViewMenu, '&View');
  SoundMenu := CreatePopupMenu;
  AppendMenu(SoundMenu, MF_STRING, CmdMute, '&Mute');
  AppendMenu(SoundMenu, MF_STRING, CmdMarch, '&MIDI March');
  AppendMenu(SoundMenu, MF_STRING, CmdChoir, '&Choir');
  AppendMenu(Bar, MF_POPUP, SoundMenu, '&Sound');
  Result := Bar;
end;

procedure HostRun;
var
  WC: WNDCLASS;
  Msg: TMsg;
  Wr: TRect;
  Style: DWORD;
begin
  Controller := TToasterController.Create(WinW, WinH, LoadConfig);
  FullScreen := False;
  LastAudio := -1;
  LastPlay := False;
  AppMenuBar := BuildMenu;

  FillChar(WC, SizeOf(WC), 0);
  WC.lpfnWndProc := @WndProc;
  WC.hInstance := HInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := GetStockObject(BLACK_BRUSH);
  WC.lpszClassName := AppName;
  WC.style := CS_DBLCLKS or CS_HREDRAW or CS_VREDRAW;
  RegisterClass(WC);

  Style := WS_OVERLAPPEDWINDOW;
  Wr.Left := 0;
  Wr.Top := 0;
  Wr.Right := WinW;
  Wr.Bottom := WinH;
  AdjustWindowRect(Wr, Style, True);

  MainWnd := CreateWindowEx(WS_EX_APPWINDOW, AppName, 'Flying Toasters',
    Style,
    CW_USEDEFAULT, CW_USEDEFAULT, Wr.Right - Wr.Left, Wr.Bottom - Wr.Top,
    0, AppMenuBar, HInstance, nil);

  ShowWindow(MainWnd, SW_SHOW);
  UpdateWindow(MainWnd);

  while GetMessage(Msg, 0, 0, 0) do
  begin
    TranslateMessage(Msg);
    DispatchMessage(Msg);
  end;
  Controller.Free;
end;

{$ELSE}

procedure HostRun;
begin
end;

{$ENDIF}

end.
