program toastersnap;

{$mode objfpc}{$H+}

{ Writes PPM frames of the software canvas (no window).
  Usage: toastersnap out-dir }

uses
  SysUtils, utoasterconfig, utoasterapp;

procedure WritePPM(const Path: string; C: TToasterController);
var
  F: File;
  X, Y: Integer;
  P: PByte;
  RGB: array[0..2] of Byte;
  Header: string;
begin
  C.Render;
  Header := Format('P6'#10'%d %d'#10'255'#10, [C.Canvas.Width, C.Canvas.Height]);
  AssignFile(F, Path);
  Rewrite(F, 1);
  BlockWrite(F, Header[1], Length(Header));
  for Y := 0 to C.Canvas.Height - 1 do
  begin
    P := C.Canvas.Ptr + Y * C.Canvas.Width * 4;
    for X := 0 to C.Canvas.Width - 1 do
    begin
      RGB[0] := P[0];
      RGB[1] := P[1];
      RGB[2] := P[2];
      BlockWrite(F, RGB[0], 3);
      Inc(P, 4);
    end;
  end;
  CloseFile(F);
end;

procedure ApplyLook(C: TToasterController; Stars, Karaoke: Boolean);
var
  Cfg: TToasterConfig;
begin
  Cfg := C.Model.Config;
  Cfg.Starfield := Stars;
  Cfg.Karaoke := Karaoke;
  Cfg.ShowHUD := False;
  C.Model.SetConfig(Cfg);
end;

var
  Dir: string;
  C: TToasterController;
  Cfg: TToasterConfig;
begin
  if ParamCount >= 1 then
    Dir := ParamStr(1)
  else
    Dir := 'build';
  ForceDirectories(Dir);
  Cfg := DefaultConfig;
  Cfg.ShowHUD := False;
  C := TToasterController.Create(800, 500, Cfg, False);
  try
    C.Model.PlaceCataloguePose(800, 500);
    ApplyLook(C, False, False);
    WritePPM(IncludeTrailingPathDelimiter(Dir) + 'snap-classic.ppm', C);

    ApplyLook(C, True, False);
    WritePPM(IncludeTrailingPathDelimiter(Dir) + 'snap-starfield.ppm', C);

    ApplyLook(C, False, True);
    WritePPM(IncludeTrailingPathDelimiter(Dir) + 'snap-karaoke.ppm', C);

    C.Resize(960, 540);
    C.Model.PlaceCataloguePose(960, 540);
    ApplyLook(C, True, True);
    WritePPM(IncludeTrailingPathDelimiter(Dir) + 'snap-wide.ppm', C);
  finally
    C.Free;
  end;
end.
