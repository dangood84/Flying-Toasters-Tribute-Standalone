unit utoasterconfig;

{$mode objfpc}{$H+}

{ Appearance model only. Positions and wing flaps live on TToasterModel,
  so a saved INI cannot freeze a toaster mid-flight. }

interface

type
  TToastDarkness = (tdLight, tdMedium, tdWellDone, tdBurnt);
  TToastAccessory = (taNone, taButter, taJam, taBagel);
  TAudioMode = (amMute, amMarch, amChoir);
  TEntityKind = (ekToaster, ekToast);

  TToasterConfig = record
    Density: Integer;
    Darkness: TToastDarkness;
    Accessories: Boolean;
    Starfield: Boolean;
    Karaoke: Boolean;
    Audio: TAudioMode;
    ShowHUD: Boolean;
  end;

const
  MinDensity = 5;
  MaxDensity = 30;
  DefaultDensity = 12;

function DefaultConfig: TToasterConfig;
function LoadConfig: TToasterConfig;
procedure SaveConfig(const Cfg: TToasterConfig);
procedure ClampConfig(var Cfg: TToasterConfig);

procedure SetDensity(var Cfg: TToasterConfig; Value: Integer);
procedure CycleDarkness(var Cfg: TToasterConfig);
procedure CycleAudio(var Cfg: TToasterConfig);

function DarknessName(Value: TToastDarkness): string;
function AudioName(Value: TAudioMode): string;
function AccessoryName(Value: TToastAccessory): string;

implementation

uses
  Classes, IniFiles, SysUtils;

const
  Section = 'display';

function ClampInt(Value, Lo, Hi: Integer): Integer;
begin
  if Value < Lo then
    Result := Lo
  else if Value > Hi then
    Result := Hi
  else
    Result := Value;
end;

function ConfigPath: string;
var
  Dir: string;
begin
  { Per-user OS config dir, not the repo, so relaunch keeps the last look. }
  Dir := GetAppConfigDir(False);
  ForceDirectories(Dir);
  Result := IncludeTrailingPathDelimiter(Dir) + 'flyingtoasters.ini';
end;

procedure ClampConfig(var Cfg: TToasterConfig);
begin
  Cfg.Density := ClampInt(Cfg.Density, MinDensity, MaxDensity);
  if (Cfg.Darkness < tdLight) or (Cfg.Darkness > tdBurnt) then
    Cfg.Darkness := tdMedium;
  if (Cfg.Audio < amMute) or (Cfg.Audio > amChoir) then
    Cfg.Audio := amMute;
end;

function DefaultConfig: TToasterConfig;
begin
  Result.Density := DefaultDensity;
  Result.Darkness := tdMedium;
  Result.Accessories := True;
  Result.Starfield := False;
  Result.Karaoke := False;
  Result.Audio := amMute;
  Result.ShowHUD := True;
end;

function LoadConfig: TToasterConfig;
var
  Ini: TIniFile;
begin
  Result := DefaultConfig;
  if not FileExists(ConfigPath) then
    Exit;
  Ini := TIniFile.Create(ConfigPath);
  try
    Result.Density := Ini.ReadInteger(Section, 'density', Result.Density);
    Result.Darkness := TToastDarkness(Ini.ReadInteger(Section, 'darkness', Ord(Result.Darkness)));
    Result.Accessories := Ini.ReadBool(Section, 'accessories', Result.Accessories);
    Result.Starfield := Ini.ReadBool(Section, 'starfield', Result.Starfield);
    Result.Karaoke := Ini.ReadBool(Section, 'karaoke', Result.Karaoke);
    Result.Audio := TAudioMode(Ini.ReadInteger(Section, 'audio', Ord(Result.Audio)));
    Result.ShowHUD := Ini.ReadBool(Section, 'hud', Result.ShowHUD);
    ClampConfig(Result);
  finally
    Ini.Free;
  end;
end;

procedure SaveConfig(const Cfg: TToasterConfig);
var
  Ini: TIniFile;
  C: TToasterConfig;
begin
  C := Cfg;
  ClampConfig(C);
  Ini := TIniFile.Create(ConfigPath);
  try
    Ini.WriteInteger(Section, 'density', C.Density);
    Ini.WriteInteger(Section, 'darkness', Ord(C.Darkness));
    Ini.WriteBool(Section, 'accessories', C.Accessories);
    Ini.WriteBool(Section, 'starfield', C.Starfield);
    Ini.WriteBool(Section, 'karaoke', C.Karaoke);
    Ini.WriteInteger(Section, 'audio', Ord(C.Audio));
    Ini.WriteBool(Section, 'hud', C.ShowHUD);
  finally
    Ini.Free;
  end;
end;

procedure SetDensity(var Cfg: TToasterConfig; Value: Integer);
begin
  Cfg.Density := ClampInt(Value, MinDensity, MaxDensity);
end;

procedure CycleDarkness(var Cfg: TToasterConfig);
begin
  if Cfg.Darkness = tdBurnt then
    Cfg.Darkness := tdLight
  else
    Cfg.Darkness := Succ(Cfg.Darkness);
end;

procedure CycleAudio(var Cfg: TToasterConfig);
begin
  if Cfg.Audio = amChoir then
    Cfg.Audio := amMute
  else
    Cfg.Audio := Succ(Cfg.Audio);
end;

function DarknessName(Value: TToastDarkness): string;
begin
  case Value of
    tdLight: Result := 'Light';
    tdMedium: Result := 'Medium';
    tdWellDone: Result := 'Well done';
    tdBurnt: Result := 'Burnt';
    else Result := 'Medium';
  end;
end;

function AudioName(Value: TAudioMode): string;
begin
  case Value of
    amMute: Result := 'Mute';
    amMarch: Result := 'MIDI';
    amChoir: Result := 'Choir';
    else Result := 'Mute';
  end;
end;

function AccessoryName(Value: TToastAccessory): string;
begin
  case Value of
    taButter: Result := 'Butter';
    taJam: Result := 'Jam';
    taBagel: Result := 'Bagel';
    else Result := 'Plain';
  end;
end;

end.
