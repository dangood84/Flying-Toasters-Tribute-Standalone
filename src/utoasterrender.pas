unit utoasterrender;

{$mode objfpc}{$H+}

{ Software RGBA canvas for the Flying Toasters tribute. Hosts only upload
  the bytes. Sprites are original geometry — chrome bodies, flapping wings,
  crusted toast — not Berkeley Systems bitmaps. }

interface

uses
  utoasterconfig, utoastermodel;

type
  TPixelBuffer = class
  private
    FWidth, FHeight: Integer;
    FData: array of Byte;
  public
    constructor Create(AWidth, AHeight: Integer);
    procedure Resize(AWidth, AHeight: Integer);
    procedure Clear(R, G, B, A: Byte);
    function Ptr: PByte;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
  end;

procedure RenderToasters(Buf: TPixelBuffer; Model: TToasterModel);
procedure CopyBGRA(Buf: TPixelBuffer; Dest: PByte);

implementation

uses
  Math, SysUtils, ubitmapfont;

type
  TColor = record
    R, G, B: Byte;
  end;

function C(R, G, B: Byte): TColor;
begin
  Result.R := R;
  Result.G := G;
  Result.B := B;
end;

constructor TPixelBuffer.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  Resize(AWidth, AHeight);
end;

procedure TPixelBuffer.Resize(AWidth, AHeight: Integer);
begin
  if AWidth < 1 then
    AWidth := 1;
  if AHeight < 1 then
    AHeight := 1;
  FWidth := AWidth;
  FHeight := AHeight;
  SetLength(FData, FWidth * FHeight * 4);
end;

procedure TPixelBuffer.Clear(R, G, B, A: Byte);
var
  I: Integer;
  P: PByte;
begin
  P := @FData[0];
  I := 0;
  while I < Length(FData) do
  begin
    P[I] := R;
    P[I + 1] := G;
    P[I + 2] := B;
    P[I + 3] := A;
    Inc(I, 4);
  end;
end;

function TPixelBuffer.Ptr: PByte;
begin
  Result := @FData[0];
end;

procedure CopyBGRA(Buf: TPixelBuffer; Dest: PByte);
var
  I, N: Integer;
  S, D: PByte;
begin
  S := Buf.Ptr;
  D := Dest;
  N := Buf.Width * Buf.Height;
  for I := 0 to N - 1 do
  begin
    D[0] := S[2];
    D[1] := S[1];
    D[2] := S[0];
    D[3] := S[3];
    Inc(S, 4);
    Inc(D, 4);
  end;
end;

procedure BlendPixel(P: PByte; R, G, B: Byte; A: Double);
var
  SA, DA, OutA, Inv: Double;
begin
  if A <= 0.001 then
    Exit;
  if A > 1 then
    A := 1;
  SA := A;
  DA := P[3] / 255.0;
  Inv := 1.0 - SA;
  OutA := SA + DA * Inv;
  if OutA <= 0.001 then
    Exit;
  P[0] := Round((R * SA + P[0] * DA * Inv) / OutA);
  P[1] := Round((G * SA + P[1] * DA * Inv) / OutA);
  P[2] := Round((B * SA + P[2] * DA * Inv) / OutA);
  P[3] := Round(OutA * 255.0);
end;

function CoverEllipse(PX, PY, CX, CY, RX, RY: Double): Double;
var
  NX, NY, D, Edge: Double;
begin
  if (RX <= 0.2) or (RY <= 0.2) then
    Exit(0);
  NX := (PX - CX) / RX;
  NY := (PY - CY) / RY;
  D := Sqrt(NX * NX + NY * NY);
  Edge := (D - 1.0) * Min(RX, RY);
  if Edge <= -0.6 then
    Result := 1
  else if Edge >= 0.6 then
    Result := 0
  else
    Result := 1.0 - (Edge + 0.6) / 1.2;
end;

procedure FillEllipse(Buf: TPixelBuffer; CX, CY, RX, RY: Double; Col: TColor; Alpha: Double);
var
  X0, Y0, X1, Y1, X, Y, W: Integer;
  Cov: Double;
  P: PByte;
begin
  if (Alpha <= 0) or (RX <= 0) or (RY <= 0) then
    Exit;
  X0 := Max(0, Floor(CX - RX - 1));
  Y0 := Max(0, Floor(CY - RY - 1));
  X1 := Min(Buf.Width - 1, Ceil(CX + RX + 1));
  Y1 := Min(Buf.Height - 1, Ceil(CY + RY + 1));
  W := Buf.Width;
  for Y := Y0 to Y1 do
  begin
    P := Buf.Ptr + (Y * W + X0) * 4;
    for X := X0 to X1 do
    begin
      Cov := CoverEllipse(X + 0.5, Y + 0.5, CX, CY, RX, RY);
      if Cov > 0 then
        BlendPixel(P, Col.R, Col.G, Col.B, Cov * Alpha);
      Inc(P, 4);
    end;
  end;
end;

procedure StrokeEllipse(Buf: TPixelBuffer; CX, CY, RX, RY, Thickness: Double; Col: TColor; Alpha: Double);
var
  InnerX, InnerY: Double;
  X0, Y0, X1, Y1, X, Y, W: Integer;
  Cov: Double;
  P: PByte;
begin
  InnerX := RX - Thickness;
  InnerY := RY - Thickness;
  if InnerX < 0.4 then
    InnerX := 0.4;
  if InnerY < 0.4 then
    InnerY := 0.4;
  X0 := Max(0, Floor(CX - RX - 1));
  Y0 := Max(0, Floor(CY - RY - 1));
  X1 := Min(Buf.Width - 1, Ceil(CX + RX + 1));
  Y1 := Min(Buf.Height - 1, Ceil(CY + RY + 1));
  W := Buf.Width;
  for Y := Y0 to Y1 do
  begin
    P := Buf.Ptr + (Y * W + X0) * 4;
    for X := X0 to X1 do
    begin
      Cov := CoverEllipse(X + 0.5, Y + 0.5, CX, CY, RX, RY) *
             (1.0 - CoverEllipse(X + 0.5, Y + 0.5, CX, CY, InnerX, InnerY));
      if Cov > 0 then
        BlendPixel(P, Col.R, Col.G, Col.B, Cov * Alpha);
      Inc(P, 4);
    end;
  end;
end;

procedure FillRectAA(Buf: TPixelBuffer; X0, Y0, X1, Y1: Double; Col: TColor; Alpha: Double = 1);
var
  IX0, IY0, IX1, IY1, X, Y, W: Integer;
  PX, PY, CovX, CovY, Cov: Double;
  P: PByte;
begin
  if (X1 <= X0) or (Y1 <= Y0) or (Alpha <= 0) then
    Exit;
  IX0 := Max(0, Floor(X0 - 1));
  IY0 := Max(0, Floor(Y0 - 1));
  IX1 := Min(Buf.Width - 1, Ceil(X1 + 1));
  IY1 := Min(Buf.Height - 1, Ceil(Y1 + 1));
  W := Buf.Width;
  for Y := IY0 to IY1 do
  begin
    P := Buf.Ptr + (Y * W + IX0) * 4;
    PY := Y + 0.5;
    if PY < Y0 then
      CovY := 1.0 - (Y0 - PY)
    else if PY > Y1 then
      CovY := 1.0 - (PY - Y1)
    else
      CovY := 1.0;
    if CovY < 0 then
      CovY := 0;
    if CovY > 1 then
      CovY := 1;
    for X := IX0 to IX1 do
    begin
      PX := X + 0.5;
      if PX < X0 then
        CovX := 1.0 - (X0 - PX)
      else if PX > X1 then
        CovX := 1.0 - (PX - X1)
      else
        CovX := 1.0;
      if CovX < 0 then
        CovX := 0;
      if CovX > 1 then
        CovX := 1;
      Cov := CovX * CovY;
      if Cov > 0 then
        BlendPixel(P, Col.R, Col.G, Col.B, Cov * Alpha);
      Inc(P, 4);
    end;
  end;
end;

function EdgeDist(PX, PY, AX, AY, BX, BY: Double): Double;
var
  DX, DY, Len: Double;
begin
  DX := BX - AX;
  DY := BY - AY;
  Len := Sqrt(DX * DX + DY * DY);
  if Len < 0.001 then
    Exit(0);
  Result := (DX * (PY - AY) - DY * (PX - AX)) / Len;
end;

procedure FillTriangle(Buf: TPixelBuffer; AX, AY, BX, BY, CX, CY: Double; Col: TColor; Alpha: Double);
var
  Area, E0, E1, E2, Cov: Double;
  X0, Y0, X1, Y1, X, Y, W: Integer;
  PX, PY: Double;
  P: PByte;
begin
  Area := (BX - AX) * (CY - AY) - (CX - AX) * (BY - AY);
  if Abs(Area) < 0.5 then
    Exit;
  if Area < 0 then
  begin
    FillTriangle(Buf, AX, AY, CX, CY, BX, BY, Col, Alpha);
    Exit;
  end;
  X0 := Max(0, Floor(Min(AX, Min(BX, CX)) - 1));
  Y0 := Max(0, Floor(Min(AY, Min(BY, CY)) - 1));
  X1 := Min(Buf.Width - 1, Ceil(Max(AX, Max(BX, CX)) + 1));
  Y1 := Min(Buf.Height - 1, Ceil(Max(AY, Max(BY, CY)) + 1));
  W := Buf.Width;
  for Y := Y0 to Y1 do
  begin
    P := Buf.Ptr + (Y * W + X0) * 4;
    PY := Y + 0.5;
    for X := X0 to X1 do
    begin
      PX := X + 0.5;
      E0 := EdgeDist(PX, PY, AX, AY, BX, BY);
      E1 := EdgeDist(PX, PY, BX, BY, CX, CY);
      E2 := EdgeDist(PX, PY, CX, CY, AX, AY);
      if (E0 >= -0.6) and (E1 >= -0.6) and (E2 >= -0.6) then
      begin
        Cov := Min(E0, Min(E1, E2));
        if Cov >= 0.6 then
          Cov := 1
        else
          Cov := (Cov + 0.6) / 1.2;
        if Cov > 0 then
          BlendPixel(P, Col.R, Col.G, Col.B, Cov * Alpha);
      end;
      Inc(P, 4);
    end;
  end;
end;

procedure DrawWing(Buf: TPixelBuffer; AX, AY, Scale: Single; Flip: Integer; Pose: Integer);
var
  TipX, TipY, RootX, RootY, LeadX, LeadY, TrailX, TrailY, Lift, Spread: Single;
  Bone, Feather, Outline: TColor;
begin
  case Pose of
    0:
      begin
        Lift := -26 * Scale;
        Spread := 30 * Scale;
      end;
    1:
      begin
        Lift := -2 * Scale;
        Spread := 38 * Scale;
      end;
    else
      begin
        Lift := 20 * Scale;
        Spread := 32 * Scale;
      end;
  end;
  RootX := AX;
  RootY := AY;
  TipX := AX + Flip * Spread;
  TipY := AY + Lift;
  LeadX := AX + Flip * (Spread * 0.38);
  LeadY := AY + Lift * 0.12 - 6 * Scale;
  TrailX := AX + Flip * (Spread * 0.18);
  TrailY := AY + Lift * 0.42 + 12 * Scale;
  Outline := C(36, 40, 50);
  Bone := C(240, 244, 248);
  Feather := C(168, 180, 196);
  FillTriangle(Buf, RootX, RootY, TipX, TipY, TrailX, TrailY, Outline, 1);
  FillTriangle(Buf, RootX, RootY, TipX, TipY, LeadX, LeadY, Bone, 1);
  FillTriangle(Buf, RootX + Flip * 2 * Scale, RootY,
    TipX - Flip * 6 * Scale, TipY + 2 * Scale, TrailX, TrailY - 2 * Scale, Feather, 1);
  FillEllipse(Buf, RootX + Flip * 11 * Scale, RootY + Lift * 0.28, 11 * Scale, 6.5 * Scale, Feather, 1);
  FillEllipse(Buf, TipX, TipY, 5.5 * Scale, 3.6 * Scale, Bone, 1);
end;

procedure DrawToaster(Buf: TPixelBuffer; X, Y, Scale: Single; Pose: Integer);
var
  BW, BH: Single;
  Chrome, ChromeHi, ChromeLo, Slot, Lever, Jewel, Cord: TColor;
  I: Integer;
  CX, CY: Single;
begin
  BW := 62 * Scale;
  BH := 40 * Scale;
  Chrome := C(168, 178, 192);
  ChromeHi := C(228, 234, 242);
  ChromeLo := C(92, 100, 114);
  Slot := C(36, 32, 28);
  Lever := C(196, 58, 48);
  Jewel := C(220, 40, 36);
  Cord := C(42, 40, 38);

  FillEllipse(Buf, X + 3 * Scale, Y + BH * 0.46, BW * 0.46, BH * 0.16, C(0, 0, 0), 0.28);

  DrawWing(Buf, X - BW * 0.18, Y - BH * 0.02, Scale, -1, Pose);
  DrawWing(Buf, X + BW * 0.18, Y - BH * 0.02, Scale, 1, Pose);

  FillEllipse(Buf, X - BW * 0.30, Y, BH * 0.50, BH * 0.50, ChromeLo, 1);
  FillEllipse(Buf, X + BW * 0.30, Y, BH * 0.50, BH * 0.50, ChromeLo, 1);
  FillRectAA(Buf, X - BW * 0.30, Y - BH * 0.50, X + BW * 0.30, Y + BH * 0.50, Chrome);
  FillEllipse(Buf, X - BW * 0.30, Y, BH * 0.48, BH * 0.48, Chrome, 1);
  FillEllipse(Buf, X + BW * 0.30, Y, BH * 0.48, BH * 0.48, Chrome, 1);
  FillEllipse(Buf, X - BW * 0.10, Y - BH * 0.16, BW * 0.24, BH * 0.14, ChromeHi, 0.75);

  FillRectAA(Buf, X - BW * 0.20, Y - BH * 0.46, X + BW * 0.20, Y - BH * 0.22, Slot);
  FillRectAA(Buf, X - BW * 0.16, Y - BH * 0.42, X + BW * 0.16, Y - BH * 0.26, C(22, 18, 16));

  FillRectAA(Buf, X + BW * 0.36, Y - BH * 0.10, X + BW * 0.54, Y + BH * 0.10, Lever);
  FillEllipse(Buf, X + BW * 0.54, Y, 5.2 * Scale, 5.2 * Scale, Lever, 1);
  FillEllipse(Buf, X - BW * 0.34, Y + BH * 0.06, 3.4 * Scale, 3.4 * Scale, Jewel, 1);

  for I := 0 to 5 do
  begin
    CX := X + BW * 0.08 + I * 4.2 * Scale;
    CY := Y + BH * 0.52 + Sin(I * 0.9) * 5.5 * Scale + I * 3.2 * Scale;
    FillEllipse(Buf, CX, CY, 2.1 * Scale, 2.1 * Scale, Cord, 1);
  end;
end;

function ToastFill(Darkness: TToastDarkness): TColor;
begin
  case Darkness of
    tdLight: Result := C(226, 188, 128);
    tdMedium: Result := C(186, 128, 68);
    tdWellDone: Result := C(128, 78, 38);
    else Result := C(52, 34, 26);
  end;
end;

function ToastCrust(Darkness: TToastDarkness): TColor;
begin
  case Darkness of
    tdLight: Result := C(176, 118, 62);
    tdMedium: Result := C(122, 72, 32);
    tdWellDone: Result := C(78, 44, 22);
    else Result := C(28, 18, 14);
  end;
end;

procedure DrawToast(Buf: TPixelBuffer; Ent: TFlyingEntity);
var
  S, W, H: Single;
  Fill, Crust, Butter, Jam: TColor;
  Wobble: Single;
begin
  S := Ent.Scale;
  Wobble := Sin(Ent.Anim) * 3 * S;
  W := 28 * S;
  H := 28 * S;
  Fill := ToastFill(Ent.Darkness);
  Crust := ToastCrust(Ent.Darkness);
  Butter := C(255, 216, 78);
  Jam := C(188, 28, 48);

  FillEllipse(Buf, Ent.X + 2 * S, Ent.Y + H * 0.42 + Wobble, W * 0.55, H * 0.16, C(0, 0, 0), 0.22);

  if Ent.Accessory = taBagel then
  begin
    FillEllipse(Buf, Ent.X, Ent.Y + Wobble, W * 0.62, H * 0.58, Crust, 1);
    FillEllipse(Buf, Ent.X, Ent.Y + Wobble, W * 0.52, H * 0.48, Fill, 1);
    FillEllipse(Buf, Ent.X, Ent.Y + Wobble, W * 0.20, H * 0.18, C(8, 8, 10), 1);
    Exit;
  end;

  FillRectAA(Buf, Ent.X - W * 0.55, Ent.Y - H * 0.50 + Wobble,
    Ent.X + W * 0.55, Ent.Y + H * 0.50 + Wobble, Crust);
  FillRectAA(Buf, Ent.X - W * 0.42, Ent.Y - H * 0.38 + Wobble,
    Ent.X + W * 0.42, Ent.Y + H * 0.38 + Wobble, Fill);

  if Ent.Accessory = taButter then
    FillEllipse(Buf, Ent.X + 2 * S, Ent.Y - 2 * S + Wobble, 7 * S, 5 * S, Butter, 1)
  else if Ent.Accessory = taJam then
  begin
    FillEllipse(Buf, Ent.X - 2 * S, Ent.Y + Wobble, 9 * S, 7 * S, Jam, 0.92);
    FillEllipse(Buf, Ent.X + 4 * S, Ent.Y + 3 * S + Wobble, 5 * S, 4 * S, C(210, 48, 64), 0.85);
  end;
end;

procedure DrawStars(Buf: TPixelBuffer; Model: TToasterModel);
var
  I, SX, SY, Size: Integer;
  Star: TStarDot;
  Tw: Double;
  Col: TColor;
begin
  for I := 0 to Model.StarCount - 1 do
  begin
    Star := Model.Star(I);
    Tw := 0.55 + 0.45 * Sin(Model.SongTime * 2.4 + Star.Phase);
    SX := Round(Star.X * Buf.Width);
    SY := Round(Star.Y * Buf.Height);
    Size := 1;
    if Star.Bright > 0.8 then
      Size := 2;
    Col := C(Round(210 * Star.Bright * Tw), Round(220 * Star.Bright * Tw),
      Round(255 * Star.Bright * Tw));
    FillRectAA(Buf, SX, SY, SX + Size, SY + Size, Col);
  end;
end;

procedure DrawHud(Buf: TPixelBuffer; Model: TToasterModel);
var
  Line1, Line2: string;
  Scale, X, Y: Integer;
  Cfg: TToasterConfig;

  function OnOff(B: Boolean): string;
  begin
    if B then
      Result := 'on'
    else
      Result := 'off';
  end;

begin
  Cfg := Model.Config;
  Line1 := Format('toasters %d   toast %s   extras %s   audio %s',
    [Cfg.Density, DarknessName(Cfg.Darkness),
     OnOff(Cfg.Accessories), AudioName(Cfg.Audio)]);
  if Model.Paused then
    Line2 := '[ ] count  D toast  A extras  S stars  K lyrics  M midi  Space resume  H hide'
  else
    Line2 := '[ ] count  D toast  A extras  S stars  K lyrics  M midi  Space pause   H hide';
  Scale := Max(1, Buf.Width div 700);
  if Scale > 2 then
    Scale := 2;
  while (Scale > 1) and (TextWidth(Line2, Scale) > Buf.Width - 24) do
    Dec(Scale);
  Y := Buf.Height - TextHeight(Scale) * 2 - 10 * Scale;
  X := 8 * Scale;
  FillRectAA(Buf, 0, Y - 6 * Scale, Buf.Width, Buf.Height, C(0, 0, 0), 0.55);
  DrawText(Buf.Ptr, Buf.Width, Buf.Height, X, Y, Line1, 210, 210, 200, Scale);
  DrawText(Buf.Ptr, Buf.Width, Buf.Height, X, Y + TextHeight(Scale) + 2 * Scale,
    Line2, 170, 175, 180, Scale);
end;

procedure DrawKaraoke(Buf: TPixelBuffer; Model: TToasterModel);
var
  Line: string;
  Scale, TW, X, Y, BallX: Integer;
  Pulse: Single;
begin
  Line := Model.LyricLine;
  Scale := Max(2, Buf.Width div 480);
  if Scale > 3 then
    Scale := 3;
  while (Scale > 1) and (TextWidth(Line, Scale) > Buf.Width - 40) do
    Dec(Scale);
  TW := TextWidth(Line, Scale);
  X := (Buf.Width - TW) div 2;
  if X < 8 then
    X := 8;
  Y := Trunc(Buf.Height * 0.82);
  if Model.Config.ShowHUD then
    Y := Y - TextHeight(1) * 4;
  FillRectAA(Buf, X - 10, Y - 10, X + TW + 10, Y + TextHeight(Scale) + 10, C(0, 0, 0), 0.45);
  DrawText(Buf.Ptr, Buf.Width, Buf.Height, X + 1, Y + 1, Line, 40, 40, 40, Scale);
  DrawText(Buf.Ptr, Buf.Width, Buf.Height, X, Y, Line, 255, 214, 64, Scale);
  Pulse := Model.LyricPulse;
  BallX := X + Round(Pulse * Max(8, TW - 8));
  FillEllipse(Buf, BallX, Y - 8 * Scale, 5 * Scale, 5 * Scale, C(255, 230, 90), 1);
end;

procedure RenderToasters(Buf: TPixelBuffer; Model: TToasterModel);
var
  Order: array of Integer;
  I, J, Tmp: Integer;
  Ent: TFlyingEntity;
begin
  Buf.Clear(0, 0, 0, 255);
  if Model.Config.Starfield then
    DrawStars(Buf, Model);

  SetLength(Order, Model.EntityCount);
  for I := 0 to Model.EntityCount - 1 do
    Order[I] := I;
  { Small (far) first, large (near) last — After Dark's back-to-front stack. }
  for I := 1 to High(Order) do
  begin
    Tmp := Order[I];
    J := I;
    while (J > 0) and (Model.Entity(Order[J - 1]).Scale > Model.Entity(Tmp).Scale) do
    begin
      Order[J] := Order[J - 1];
      Dec(J);
    end;
    Order[J] := Tmp;
  end;

  for I := 0 to High(Order) do
  begin
    Ent := Model.Entity(Order[I]);
    if Ent.Kind = ekToaster then
      DrawToaster(Buf, Ent.X, Ent.Y, Ent.Scale, WingPoseOf(Ent.Anim))
    else
      DrawToast(Buf, Ent);
  end;

  if Model.Config.Karaoke then
    DrawKaraoke(Buf, Model);
  if Model.Config.ShowHUD then
    DrawHud(Buf, Model);
end;

end.
