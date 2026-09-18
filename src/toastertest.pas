program toastertest;

{$mode objfpc}{$H+}

{ Headless checks for flight vector, wrap, density, and keys. No window. }

uses
  SysUtils, Math, utoasterconfig, utoastermodel, utoasterapp, utoasteraudio;

procedure ExpectNear(const LabelText: string; Got, Want, Eps: Double);
begin
  if Abs(Got - Want) > Eps then
  begin
    WriteLn('FAIL ', LabelText, ': got ', Got:0:6, ' want ', Want:0:6);
    Halt(1);
  end;
  WriteLn('ok   ', LabelText);
end;

procedure ExpectEq(const LabelText: string; Got, Want: Integer);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', LabelText, ': got ', Got, ' want ', Want);
    Halt(1);
  end;
  WriteLn('ok   ', LabelText);
end;

procedure ExpectTrue(const LabelText: string; Ok: Boolean);
begin
  if not Ok then
  begin
    WriteLn('FAIL ', LabelText);
    Halt(1);
  end;
  WriteLn('ok   ', LabelText);
end;

var
  M: TToasterModel;
  C: TToasterController;
  Cfg: TToasterConfig;
  E0: TFlyingEntity;
  X0, Y0, DX, DY: Single;
  I: Integer;
  Moved: Boolean;
  Midi, Wav: TBytes;
  FoundTrk: Boolean;
begin
  ExpectNear('45deg |dx|', Abs(FlightDX(100)), 100 * InvSqrt2, 1e-5);
  ExpectNear('45deg |dy|', Abs(FlightDY(100)), 100 * InvSqrt2, 1e-5);
  ExpectTrue('dx is left', FlightDX(100) < 0);
  ExpectTrue('dy is down', FlightDY(100) > 0);
  ExpectEq('wing 0', WingPoseOf(0), 0);
  ExpectEq('wing 1', WingPoseOf(1), 1);
  ExpectEq('wing 2', WingPoseOf(2), 2);
  ExpectEq('wing 3 mid', WingPoseOf(3), 1);
  ExpectEq('toast for 12', ToastCountFor(12), 6);
  ExpectEq('toast min', ToastCountFor(5), 2);

  Cfg := DefaultConfig;
  SetDensity(Cfg, 100);
  ExpectEq('density clamp high', Cfg.Density, MaxDensity);
  SetDensity(Cfg, 1);
  ExpectEq('density clamp low', Cfg.Density, MinDensity);

  M := TToasterModel.Create;
  try
    M.Seed(42);
    Cfg := DefaultConfig;
    Cfg.Density := 10;
    Cfg.ShowHUD := False;
    M.SetConfig(Cfg);
    ExpectEq('pool size', M.EntityCount, 10 + ToastCountFor(10));
    E0 := M.Entity(0);
    X0 := E0.X;
    Y0 := E0.Y;
    M.Update(1.0, 800, 500);
    E0 := M.Entity(0);
    DX := E0.X - X0;
    DY := E0.Y - Y0;
    { May have wrapped; if still on-screen the step is the 45-degree vector. }
    if (E0.X > 0) and (E0.Y < 500) and (Abs(DX) > 1) then
      ExpectNear('step ratio', Abs(DY / DX), 1.0, 0.08)
    else
      WriteLn('ok   step (wrapped this seed; ratio skipped)');

    M.PlaceCataloguePose(800, 500);
    E0 := M.Entity(0);
    X0 := E0.X;
    Y0 := E0.Y;
    M.Update(1.0, 800, 500);
    ExpectNear('catalogue frozen x', M.Entity(0).X, X0, 0.001);
    ExpectNear('catalogue frozen y', M.Entity(0).Y, Y0, 0.001);
  finally
    M.Free;
  end;

  C := TToasterController.Create(400, 300, DefaultConfig, False);
  try
    ExpectEq('start density', C.Model.Config.Density, DefaultDensity);
    C.ApplyChar('[');
    ExpectEq('density down', C.Model.Config.Density, DefaultDensity - 1);
    C.ApplyChar(']');
    C.ApplyChar(']');
    ExpectEq('density up', C.Model.Config.Density, DefaultDensity + 1);
    C.ApplyChar('d');
    ExpectEq('darkness cycles from medium', Ord(C.Model.Config.Darkness), Ord(tdWellDone));
    C.ApplyChar('s');
    ExpectTrue('starfield on', C.Model.Config.Starfield);
    C.ApplyChar('k');
    ExpectTrue('karaoke on', C.Model.Config.Karaoke);
    C.ApplyChar('m');
    ExpectEq('audio march', Ord(C.Model.Config.Audio), Ord(amMarch));
    ExpectTrue('audio should play', C.AudioShouldPlay);
    C.ApplyChar(' ');
    ExpectTrue('paused', C.Model.Paused);
    ExpectTrue('paused silences audio', not C.AudioShouldPlay);
    C.Tick;
    C.Render;
    ExpectTrue('canvas w', C.Canvas.Width = 400);
    Moved := False;
    for I := 0 to C.Model.EntityCount - 1 do
      if C.Model.Entity(I).Scale > 0 then
        Moved := True;
    ExpectTrue('entities exist', Moved);
  finally
    C.Free;
  end;

  Midi := BuildMidiFile(amMarch);
  ExpectTrue('midi header', (Length(Midi) > 40) and (Midi[0] = Ord('M')) and
    (Midi[1] = Ord('T')) and (Midi[2] = Ord('h')) and (Midi[3] = Ord('d')));
  FoundTrk := False;
  for I := 0 to Length(Midi) - 4 do
    if (Midi[I] = Ord('M')) and (Midi[I + 1] = Ord('T')) and
       (Midi[I + 2] = Ord('r')) and (Midi[I + 3] = Ord('k')) then
      FoundTrk := True;
  ExpectTrue('midi track', FoundTrk);
  ExpectNear('midi loop seconds', MidiLoopSeconds, 8.0, 0.01);
  Wav := BuildMarchWav(amMarch);
  ExpectTrue('wav header', (Length(Wav) > 1000) and (Wav[0] = Ord('R')) and
    (Wav[8] = Ord('W')));

  WriteLn('All toaster tests passed.');
end.
