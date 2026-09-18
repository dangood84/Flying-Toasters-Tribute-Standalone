unit utoastermodel;

{$mode objfpc}{$H+}

{ Entity pool, 45-degree flight, wrap, karaoke clock. No pixels, no Cocoa/Win32/GTK.

  Same contract as the Java starfield: a fixed array whose length is the
  density setting, recycled rather than allocated when a sprite leaves
  the bottom-left. }

interface

uses
  utoasterconfig;

const
  InvSqrt2 = 0.7071067811865476;
  MaxStars = 80;
  LyricLineCount = 4;
  LyricLineSeconds: array[0..1] of Double = (3.6, 5.2); { march, choir }

  LyricLines: array[0..LyricLineCount - 1] of string = (
    'Chrome wings cut the night',
    'Toast takes off in golden light',
    'A pixel tribute after dark',
    'Toasters fly, a living spark'
  );

type
  TFlyingEntity = record
    Kind: TEntityKind;
    X, Y: Single;
    Speed: Single;
    Scale: Single;
    Anim: Single;
    FlapRate: Single;
    Darkness: TToastDarkness;
    Accessory: TToastAccessory;
  end;

  TStarDot = record
    X, Y: Single;
    Phase: Single;
    Bright: Single;
  end;

  TToasterModel = class
  private
    FRng: Cardinal;
    FEntities: array of TFlyingEntity;
    FStars: array of TStarDot;
    FConfig: TToasterConfig;
    FSongTime: Double;
    FPaused: Boolean;
    FViewW, FViewH: Integer;
    FFrozen: Boolean;
    function NextU32: Cardinal;
    function NextFloat: Single;
    procedure SpawnEntity(Index: Integer; Scatter: Boolean);
    procedure RebuildStars;
    procedure RebuildPool(Scatter: Boolean);
  public
    constructor Create;
    procedure Seed(Value: Cardinal);
    procedure SetConfig(const Cfg: TToasterConfig);
    procedure SyncPoolToConfig;
    procedure Update(Dt: Double; ViewW, ViewH: Integer);
    procedure PlaceCataloguePose(ViewW, ViewH: Integer);
    procedure TogglePaused;
    function EntityCount: Integer;
    function Entity(Index: Integer): TFlyingEntity;
    function StarCount: Integer;
    function Star(Index: Integer): TStarDot;
    function LyricIndex: Integer;
    function LyricLine: string;
    function LyricPulse: Single;
    property Config: TToasterConfig read FConfig;
    property SongTime: Double read FSongTime;
    property Paused: Boolean read FPaused;
    property Frozen: Boolean read FFrozen;
    property ViewW: Integer read FViewW;
    property ViewH: Integer read FViewH;
  end;

function FlightDX(Speed: Single): Single;
function FlightDY(Speed: Single): Single;
function WingPoseOf(Anim: Single): Integer;
function ToastCountFor(Density: Integer): Integer;

implementation

uses
  Math, SysUtils;

constructor TToasterModel.Create;
begin
  inherited Create;
  FRng := 2463534242;
  FConfig := DefaultConfig;
  FViewW := 800;
  FViewH := 500;
  FSongTime := 0;
  FPaused := False;
  FFrozen := False;
  RebuildStars;
  RebuildPool(True);
end;

procedure TToasterModel.Seed(Value: Cardinal);
begin
  if Value = 0 then
    Value := 1;
  FRng := Value;
end;

function TToasterModel.NextU32: Cardinal;
begin
  { xorshift32 — enough scramble for spawn positions, no sys random. }
  FRng := FRng xor (FRng shl 13);
  FRng := FRng xor (FRng shr 17);
  FRng := FRng xor (FRng shl 5);
  Result := FRng;
end;

function TToasterModel.NextFloat: Single;
begin
  Result := NextU32 * (1.0 / 4294967295.0);
end;

function FlightDX(Speed: Single): Single;
begin
  Result := -Speed * InvSqrt2;
end;

function FlightDY(Speed: Single): Single;
begin
  { Canvas is y-down, so +Y is toward the bottom-left destination. }
  Result := Speed * InvSqrt2;
end;

function WingPoseOf(Anim: Single): Integer;
var
  P: Integer;
begin
  P := Trunc(Anim) mod 4;
  if P < 0 then
    P := P + 4;
  if P = 3 then
    Result := 1
  else
    Result := P;
end;

function ToastCountFor(Density: Integer): Integer;
begin
  Result := Density div 2;
  if Result < 2 then
    Result := 2;
end;

procedure TToasterModel.RebuildStars;
var
  I: Integer;
begin
  SetLength(FStars, MaxStars);
  for I := 0 to High(FStars) do
  begin
    FStars[I].X := NextFloat;
    FStars[I].Y := NextFloat;
    FStars[I].Phase := NextFloat * 2 * Pi;
    FStars[I].Bright := 0.35 + NextFloat * 0.65;
  end;
end;

procedure TToasterModel.SpawnEntity(Index: Integer; Scatter: Boolean);
var
  IsToaster, Back: Boolean;
  ToastN, Total: Integer;
  T, Margin: Single;
begin
  Total := Length(FEntities);
  ToastN := ToastCountFor(FConfig.Density);
  if ToastN > Total then
    ToastN := Total;
  IsToaster := Index < Total - ToastN;

  FEntities[Index].Anim := NextFloat * 4;
  FEntities[Index].FlapRate := 7.0 + NextFloat * 5.0;
  FEntities[Index].Darkness := FConfig.Darkness;
  FEntities[Index].Accessory := taNone;

  if IsToaster then
  begin
    FEntities[Index].Kind := ekToaster;
    Back := NextFloat < 0.42;
    if Back then
      FEntities[Index].Scale := 0.42 + NextFloat * 0.28
    else
      FEntities[Index].Scale := 0.82 + NextFloat * 0.40;
    FEntities[Index].Speed := 58 + FEntities[Index].Scale * 96;
  end
  else
  begin
    FEntities[Index].Kind := ekToast;
    FEntities[Index].Scale := 0.52 + NextFloat * 0.55;
    FEntities[Index].Speed := 50 + FEntities[Index].Scale * 88;
    FEntities[Index].FlapRate := 1.6 + NextFloat * 1.4;
    if FConfig.Accessories then
    begin
      T := NextFloat;
      if T < 0.18 then
        FEntities[Index].Accessory := taBagel
      else if T < 0.40 then
        FEntities[Index].Accessory := taJam
      else if T < 0.62 then
        FEntities[Index].Accessory := taButter
      else
        FEntities[Index].Accessory := taNone;
    end;
  end;

  Margin := 70 * FEntities[Index].Scale;
  if Scatter then
  begin
    { First fill: scatter along the flight corridor so the sky is not empty. }
    T := NextFloat;
    FEntities[Index].X := FViewW * (0.05 + T * 1.15);
    FEntities[Index].Y := FViewH * (T * 1.20 - 0.28);
  end
  else if NextFloat < 0.5 then
  begin
    FEntities[Index].X := FViewW + Margin;
    FEntities[Index].Y := NextFloat * FViewH * 0.88 - Margin * 0.3;
  end
  else
  begin
    FEntities[Index].X := FViewW * (0.22 + NextFloat * 0.90);
    FEntities[Index].Y := -Margin;
  end;
end;

procedure TToasterModel.RebuildPool(Scatter: Boolean);
var
  I, Total: Integer;
begin
  Total := FConfig.Density + ToastCountFor(FConfig.Density);
  SetLength(FEntities, Total);
  for I := 0 to High(FEntities) do
    SpawnEntity(I, Scatter);
end;

procedure TToasterModel.SetConfig(const Cfg: TToasterConfig);
var
  NextCfg: TToasterConfig;
  DensityChanged, AccChanged: Boolean;
begin
  NextCfg := Cfg;
  ClampConfig(NextCfg);
  DensityChanged := NextCfg.Density <> FConfig.Density;
  AccChanged := NextCfg.Accessories <> FConfig.Accessories;
  FConfig := NextCfg;
  if DensityChanged then
    RebuildPool(True)
  else if AccChanged then
    RebuildPool(True);
end;

procedure TToasterModel.SyncPoolToConfig;
begin
  RebuildPool(True);
end;

procedure TToasterModel.Update(Dt: Double; ViewW, ViewH: Integer);
var
  I: Integer;
  Margin: Single;
  LineLen: Double;
begin
  if ViewW < 1 then
    ViewW := 1;
  if ViewH < 1 then
    ViewH := 1;
  FViewW := ViewW;
  FViewH := ViewH;
  if FFrozen or FPaused then
    Exit;
  if Dt < 0 then
    Dt := 0;
  if Dt > 0.05 then
    Dt := 0.05;

  for I := 0 to High(FEntities) do
  begin
    { State change: slide along the 45-degree After Dark vector. }
    FEntities[I].X := FEntities[I].X + FlightDX(FEntities[I].Speed) * Dt;
    FEntities[I].Y := FEntities[I].Y + FlightDY(FEntities[I].Speed) * Dt;
    FEntities[I].Anim := FEntities[I].Anim + FEntities[I].FlapRate * Dt;
    Margin := 80 * FEntities[I].Scale;
    if (FEntities[I].X < -Margin) or (FEntities[I].Y > FViewH + Margin) then
      SpawnEntity(I, False);
  end;

  LineLen := LyricLineSeconds[0];
  if FConfig.Audio = amChoir then
    LineLen := LyricLineSeconds[1];
  FSongTime := FSongTime + Dt;
  while FSongTime >= LyricLineCount * LineLen do
    FSongTime := FSongTime - LyricLineCount * LineLen;
end;

procedure TToasterModel.PlaceCataloguePose(ViewW, ViewH: Integer);
begin
  { State change: live flock → frozen catalogue composition for snaps. }
  if ViewW < 1 then
    ViewW := 800;
  if ViewH < 1 then
    ViewH := 500;
  FViewW := ViewW;
  FViewH := ViewH;
  FFrozen := True;
  FPaused := True;
  FConfig.ShowHUD := False;
  SetLength(FEntities, 7);

  FEntities[0].Kind := ekToaster;
  FEntities[0].X := ViewW * 0.62;
  FEntities[0].Y := ViewH * 0.34;
  FEntities[0].Scale := 1.12;
  FEntities[0].Speed := 0;
  FEntities[0].Anim := 0.2;
  FEntities[0].FlapRate := 0;
  FEntities[0].Accessory := taNone;

  FEntities[1].Kind := ekToaster;
  FEntities[1].X := ViewW * 0.38;
  FEntities[1].Y := ViewH * 0.52;
  FEntities[1].Scale := 0.78;
  FEntities[1].Speed := 0;
  FEntities[1].Anim := 1.4;
  FEntities[1].FlapRate := 0;
  FEntities[1].Accessory := taNone;

  FEntities[2].Kind := ekToaster;
  FEntities[2].X := ViewW * 0.78;
  FEntities[2].Y := ViewH * 0.18;
  FEntities[2].Scale := 0.50;
  FEntities[2].Speed := 0;
  FEntities[2].Anim := 2.1;
  FEntities[2].FlapRate := 0;
  FEntities[2].Accessory := taNone;

  FEntities[3].Kind := ekToast;
  FEntities[3].X := ViewW * 0.50;
  FEntities[3].Y := ViewH * 0.26;
  FEntities[3].Scale := 0.72;
  FEntities[3].Speed := 0;
  FEntities[3].Anim := 0;
  FEntities[3].FlapRate := 0;
  FEntities[3].Darkness := tdLight;
  FEntities[3].Accessory := taButter;

  FEntities[4].Kind := ekToast;
  FEntities[4].X := ViewW * 0.28;
  FEntities[4].Y := ViewH * 0.58;
  FEntities[4].Scale := 0.80;
  FEntities[4].Speed := 0;
  FEntities[4].Anim := 0;
  FEntities[4].FlapRate := 0;
  FEntities[4].Darkness := tdMedium;
  FEntities[4].Accessory := taJam;

  FEntities[5].Kind := ekToast;
  FEntities[5].X := ViewW * 0.70;
  FEntities[5].Y := ViewH * 0.62;
  FEntities[5].Scale := 0.68;
  FEntities[5].Speed := 0;
  FEntities[5].Anim := 0;
  FEntities[5].FlapRate := 0;
  FEntities[5].Darkness := tdBurnt;
  FEntities[5].Accessory := taNone;

  FEntities[6].Kind := ekToast;
  FEntities[6].X := ViewW * 0.20;
  FEntities[6].Y := ViewH * 0.30;
  FEntities[6].Scale := 0.74;
  FEntities[6].Speed := 0;
  FEntities[6].Anim := 0;
  FEntities[6].FlapRate := 0;
  FEntities[6].Darkness := tdWellDone;
  FEntities[6].Accessory := taBagel;

  FSongTime := 1.2;
end;

procedure TToasterModel.TogglePaused;
begin
  if FFrozen then
    Exit;
  FPaused := not FPaused;
end;

function TToasterModel.EntityCount: Integer;
begin
  Result := Length(FEntities);
end;

function TToasterModel.Entity(Index: Integer): TFlyingEntity;
begin
  Result := FEntities[Index];
end;

function TToasterModel.StarCount: Integer;
begin
  Result := Length(FStars);
end;

function TToasterModel.Star(Index: Integer): TStarDot;
begin
  Result := FStars[Index];
end;

function TToasterModel.LyricIndex: Integer;
var
  LineLen: Double;
begin
  LineLen := LyricLineSeconds[0];
  if FConfig.Audio = amChoir then
    LineLen := LyricLineSeconds[1];
  if LineLen <= 0 then
    Exit(0);
  Result := Trunc(FSongTime / LineLen) mod LyricLineCount;
  if Result < 0 then
    Result := 0;
end;

function TToasterModel.LyricLine: string;
begin
  Result := LyricLines[LyricIndex];
end;

function TToasterModel.LyricPulse: Single;
var
  LineLen, U: Double;
begin
  LineLen := LyricLineSeconds[0];
  if FConfig.Audio = amChoir then
    LineLen := LyricLineSeconds[1];
  if LineLen <= 0 then
    Exit(0);
  U := FSongTime / LineLen;
  U := U - Floor(U);
  Result := U;
end;

end.
