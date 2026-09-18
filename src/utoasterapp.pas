unit utoasterapp;

{$mode objfpc}{$H+}

{ One model, one canvas. Hosts call Tick on a timer, Resize when the
  window changes, and present Canvas when NeedsPresent is set.

  FullScreen is *reported* here; the host is the one that actually asks
  Cocoa / Win32 / GTK to go full screen. }

interface

uses
  utoasterconfig, utoastermodel, utoasterrender;

const
  ToasterAboutTitle = 'Flying Toasters';
  ToasterAboutText =
    'A tribute to Berkeley Systems'' After Dark Flying Toasters.' + LineEnding + LineEnding +
    'Original sprites and lyrics — not affiliated with After Dark.' + LineEnding + LineEnding +
    '[ ]  toaster density' + LineEnding +
    'D    toast: Light / Medium / Well done / Burnt' + LineEnding +
    'A    butter, jam, bagels' + LineEnding +
    'S    starfield' + LineEnding +
    'K    karaoke' + LineEnding +
    'M    mute / MIDI march / choir (original tribute tune — not After Dark''s MIDI)' + LineEnding +
    'H    hide controls   Space pause   F11 fullscreen' + LineEnding + LineEnding +
    'Resize the window, or press F11 (Esc to leave) for fullscreen. ' +
    'Double-click the sky to toggle. Closing the window quits.';

type
  TToasterController = class
  private
    FNeedsPresent: Boolean;
    FFullScreen: Boolean;
    FLastMs: QWord;
    FPersist: Boolean;
  public
    Model: TToasterModel;
    Canvas: TPixelBuffer;
    constructor Create(PixelW, PixelH: Integer; const Cfg: TToasterConfig;
      Persist: Boolean = True);
    destructor Destroy; override;
    procedure Resize(PixelW, PixelH: Integer);
    procedure Tick;
    procedure Render;
    procedure ApplyChar(Ch: Char);
    procedure SetAudioMode(Mode: TAudioMode);
    function AudioShouldPlay: Boolean;
    procedure SetFullScreen(Value: Boolean);
    procedure ConsumePresent;
    procedure SaveIfNeeded;
    property NeedsPresent: Boolean read FNeedsPresent;
    property FullScreen: Boolean read FFullScreen;
  end;

implementation

uses
  SysUtils;

constructor TToasterController.Create(PixelW, PixelH: Integer;
  const Cfg: TToasterConfig; Persist: Boolean);
begin
  inherited Create;
  FPersist := Persist;
  Model := TToasterModel.Create;
  Model.SetConfig(Cfg);
  Canvas := TPixelBuffer.Create(PixelW, PixelH);
  Model.Update(0, PixelW, PixelH);
  FNeedsPresent := True;
  FFullScreen := False;
  FLastMs := 0;
end;

destructor TToasterController.Destroy;
begin
  SaveIfNeeded;
  Canvas.Free;
  Model.Free;
  inherited Destroy;
end;

procedure TToasterController.SaveIfNeeded;
begin
  if FPersist then
    SaveConfig(Model.Config);
end;

procedure TToasterController.Resize(PixelW, PixelH: Integer);
begin
  if (PixelW = Canvas.Width) and (PixelH = Canvas.Height) then
    Exit;
  Canvas.Resize(PixelW, PixelH);
  FNeedsPresent := True;
end;

procedure TToasterController.Tick;
var
  NowMs: QWord;
  Dt: Double;
begin
  NowMs := GetTickCount64;
  if FLastMs = 0 then
  begin
    FLastMs := NowMs;
    FNeedsPresent := True;
    Exit;
  end;
  Dt := (NowMs - FLastMs) / 1000.0;
  FLastMs := NowMs;
  if Dt > 0.05 then
    Dt := 0.05;
  Model.Update(Dt, Canvas.Width, Canvas.Height);
  FNeedsPresent := True;
end;

procedure TToasterController.Render;
begin
  RenderToasters(Canvas, Model);
  FNeedsPresent := True;
end;

procedure TToasterController.ApplyChar(Ch: Char);
var
  Cfg: TToasterConfig;
begin
  if Ch in ['A'..'Z'] then
    Ch := Chr(Ord(Ch) + 32);
  Cfg := Model.Config;
  case Ch of
    '[':
      SetDensity(Cfg, Cfg.Density - 1);
    ']':
      SetDensity(Cfg, Cfg.Density + 1);
    'd':
      CycleDarkness(Cfg);
    'a':
      Cfg.Accessories := not Cfg.Accessories;
    's':
      Cfg.Starfield := not Cfg.Starfield;
    'k':
      Cfg.Karaoke := not Cfg.Karaoke;
    'h':
      Cfg.ShowHUD := not Cfg.ShowHUD;
    'm':
      CycleAudio(Cfg);
    ' ':
      begin
        Model.TogglePaused;
        FNeedsPresent := True;
        Exit;
      end;
    else
      Exit;
  end;
  { State change: a live option. Density/accessories rebuild the pool;
    darkness applies to newly spawned toast. }
  Model.SetConfig(Cfg);
  FNeedsPresent := True;
end;

procedure TToasterController.SetAudioMode(Mode: TAudioMode);
var
  Cfg: TToasterConfig;
begin
  Cfg := Model.Config;
  Cfg.Audio := Mode;
  Model.SetConfig(Cfg);
  FNeedsPresent := True;
end;

function TToasterController.AudioShouldPlay: Boolean;
begin
  Result := (Model.Config.Audio <> amMute) and not Model.Paused;
end;

procedure TToasterController.SetFullScreen(Value: Boolean);
begin
  if FFullScreen = Value then
    Exit;
  FFullScreen := Value;
  FNeedsPresent := True;
end;

procedure TToasterController.ConsumePresent;
begin
  FNeedsPresent := False;
end;

end.
