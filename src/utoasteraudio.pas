unit utoasteraudio;

{$mode objfpc}{$H+}

{ Original tribute march as MIDI (and a PCM stand-in). Not the After Dark
  theme — that recording is still theirs. Square-lead GM patch 80 is the
  8-bit "MIDI on" sound; choir uses GM 52. }

interface

uses
  utoasterconfig, SysUtils;

const
  MidiBpm = 120;
  MidiPpq = 480;
  MidiLoopBeats = 16; { 8 seconds at 120 BPM, 4/4 }

type
  TMidiMsg = record
    Status, D1, D2: Byte;
  end;
  TMidiMsgArray = array of TMidiMsg;

  TAudioSeq = record
    On: array of Boolean;
  end;

function MidiLoopSeconds: Double;
function BuildMidiFile(Mode: TAudioMode): TBytes;
function BuildMarchWav(Mode: TAudioMode): TBytes;
procedure AudioSeqInit(var Seq: TAudioSeq);
function AudioSeqAdvance(var Seq: TAudioSeq; SongTime: Double; Mode: TAudioMode;
  Playing: Boolean): TMidiMsgArray;
procedure AudioSeqSilence(var Seq: TAudioSeq; var Msgs: TMidiMsgArray);

implementation

uses
  Classes, Math;

type
  TScoreNote = record
    Start, Dur: Double; { beats }
    Pitch, Vel, Chan: Byte;
  end;

var
  Score: array of TScoreNote;

procedure AddNote(Start, Dur: Double; Pitch, Vel, Chan: Byte);
var
  N: Integer;
begin
  N := Length(Score);
  SetLength(Score, N + 1);
  Score[N].Start := Start;
  Score[N].Dur := Dur;
  Score[N].Pitch := Pitch;
  Score[N].Vel := Vel;
  Score[N].Chan := Chan;
end;

procedure EnsureScore;
begin
  if Length(Score) > 0 then
    Exit;
  { Melody — original fanfare, C major. Chan 0. }
  AddNote(0.0, 0.45, 60, 100, 0);
  AddNote(0.5, 0.45, 60, 96, 0);
  AddNote(1.0, 0.45, 64, 104, 0);
  AddNote(1.5, 0.45, 67, 108, 0);
  AddNote(2.0, 0.95, 72, 112, 0);
  AddNote(3.0, 0.45, 67, 100, 0);
  AddNote(3.5, 0.45, 64, 96, 0);

  AddNote(4.0, 0.45, 65, 100, 0);
  AddNote(4.5, 0.45, 65, 96, 0);
  AddNote(5.0, 0.45, 69, 104, 0);
  AddNote(5.5, 0.45, 72, 108, 0);
  AddNote(6.0, 0.95, 71, 110, 0);
  AddNote(7.0, 0.95, 67, 100, 0);

  AddNote(8.0, 0.45, 64, 100, 0);
  AddNote(8.5, 0.45, 67, 104, 0);
  AddNote(9.0, 0.45, 72, 108, 0);
  AddNote(9.5, 0.45, 76, 112, 0);
  AddNote(10.0, 0.95, 74, 108, 0);
  AddNote(11.0, 0.95, 72, 104, 0);

  AddNote(12.0, 0.45, 64, 100, 0);
  AddNote(12.5, 0.45, 62, 96, 0);
  AddNote(13.0, 0.45, 60, 100, 0);
  AddNote(13.5, 0.45, 55, 96, 0);
  AddNote(14.0, 1.90, 60, 114, 0);

  { Bass ostinato. Chan 1. }
  AddNote(0.0, 0.95, 36, 90, 1);
  AddNote(1.0, 0.95, 43, 82, 1);
  AddNote(2.0, 0.95, 36, 90, 1);
  AddNote(3.0, 0.95, 43, 82, 1);
  AddNote(4.0, 0.95, 41, 88, 1);
  AddNote(5.0, 0.95, 36, 82, 1);
  AddNote(6.0, 0.95, 43, 88, 1);
  AddNote(7.0, 0.95, 43, 80, 1);
  AddNote(8.0, 0.95, 36, 90, 1);
  AddNote(9.0, 0.95, 43, 82, 1);
  AddNote(10.0, 0.95, 36, 90, 1);
  AddNote(11.0, 0.95, 43, 82, 1);
  AddNote(12.0, 0.95, 36, 90, 1);
  AddNote(13.0, 0.95, 31, 84, 1);
  AddNote(14.0, 1.90, 36, 94, 1);
end;

function MidiLoopSeconds: Double;
begin
  Result := MidiLoopBeats * 60.0 / MidiBpm;
end;

function LeadProgram(Mode: TAudioMode): Byte;
begin
  if Mode = amChoir then
    Result := 52 { choir aahs }
  else
    Result := 80; { lead 1 square — the 8-bit MIDI voice }
end;

function BassProgram(Mode: TAudioMode): Byte;
begin
  if Mode = amChoir then
    Result := 48 { strings }
  else
    Result := 38; { synth bass }
end;

procedure WriteU8(S: TStream; V: Byte);
begin
  S.WriteBuffer(V, 1);
end;

procedure WriteBE16(S: TStream; V: Word);
var
  B: array[0..1] of Byte;
begin
  B[0] := Byte(V shr 8);
  B[1] := Byte(V);
  S.WriteBuffer(B[0], 2);
end;

procedure WriteBE32(S: TStream; V: Cardinal);
var
  B: array[0..3] of Byte;
begin
  B[0] := Byte(V shr 24);
  B[1] := Byte(V shr 16);
  B[2] := Byte(V shr 8);
  B[3] := Byte(V);
  S.WriteBuffer(B[0], 4);
end;

procedure WriteVLQ(S: TStream; Value: Cardinal);
var
  Buf: array[0..3] of Byte;
  N, I: Integer;
begin
  Buf[0] := Byte(Value and $7F);
  N := 1;
  Value := Value shr 7;
  while Value > 0 do
  begin
    Buf[N] := Byte((Value and $7F) or $80);
    Inc(N);
    Value := Value shr 7;
  end;
  for I := N - 1 downto 0 do
    WriteU8(S, Buf[I]);
end;

type
  TRawEv = record
    Tick: Cardinal;
    Data: array[0..7] of Byte;
    Len: Integer;
  end;

procedure AddEv(var Evs: array of TRawEv; var Count: Integer; Tick: Cardinal;
  const Payload: array of Byte);
var
  I: Integer;
begin
  if Count > High(Evs) then
    Exit;
  Evs[Count].Tick := Tick;
  Evs[Count].Len := Length(Payload);
  for I := 0 to High(Payload) do
    Evs[Count].Data[I] := Payload[I];
  Inc(Count);
end;

procedure SortEvs(var Evs: array of TRawEv; Count: Integer);
var
  I, J: Integer;
  Tmp: TRawEv;
begin
  for I := 1 to Count - 1 do
  begin
    Tmp := Evs[I];
    J := I;
    while (J > 0) and (Evs[J - 1].Tick > Tmp.Tick) do
    begin
      Evs[J] := Evs[J - 1];
      Dec(J);
    end;
    Evs[J] := Tmp;
  end;
end;

function BuildMidiFile(Mode: TAudioMode): TBytes;
var
  Body, FileSt: TMemoryStream;
  Evs: array[0..255] of TRawEv;
  N, I: Integer;
  LastTick, Delta, Tick: Cardinal;
  Tempo: Cardinal;
begin
  EnsureScore;
  N := 0;
  Tempo := Round(60000000.0 / MidiBpm);
  AddEv(Evs, N, 0, [$FF, $51, $03, Byte(Tempo shr 16), Byte(Tempo shr 8), Byte(Tempo)]);
  AddEv(Evs, N, 0, [$FF, $58, $04, $04, $02, $18, $08]);
  AddEv(Evs, N, 0, [$C0, LeadProgram(Mode)]);
  AddEv(Evs, N, 0, [$C1, BassProgram(Mode)]);
  for I := 0 to High(Score) do
  begin
    Tick := Round(Score[I].Start * MidiPpq);
    AddEv(Evs, N, Tick, [$90 or Score[I].Chan, Score[I].Pitch, Score[I].Vel]);
    Tick := Round((Score[I].Start + Score[I].Dur) * MidiPpq);
    AddEv(Evs, N, Tick, [$80 or Score[I].Chan, Score[I].Pitch, 0]);
  end;
  AddEv(Evs, N, MidiLoopBeats * MidiPpq, [$FF, $2F, $00]);
  SortEvs(Evs, N);

  Body := TMemoryStream.Create;
  FileSt := TMemoryStream.Create;
  try
    LastTick := 0;
    for I := 0 to N - 1 do
    begin
      Delta := Evs[I].Tick - LastTick;
      LastTick := Evs[I].Tick;
      WriteVLQ(Body, Delta);
      Body.WriteBuffer(Evs[I].Data[0], Evs[I].Len);
    end;
    FileSt.WriteBuffer('MThd', 4);
    WriteBE32(FileSt, 6);
    WriteBE16(FileSt, 0);
    WriteBE16(FileSt, 1);
    WriteBE16(FileSt, MidiPpq);
    FileSt.WriteBuffer('MTrk', 4);
    WriteBE32(FileSt, Body.Size);
    Body.Position := 0;
    FileSt.CopyFrom(Body, Body.Size);
    SetLength(Result, FileSt.Size);
    FileSt.Position := 0;
    FileSt.ReadBuffer(Result[0], Length(Result));
  finally
    Body.Free;
    FileSt.Free;
  end;
end;

function BuildMarchWav(Mode: TAudioMode): TBytes;
const
  Rate = 22050;
var
  Samples, I, N, SCount: Integer;
  Acc, Phase, Hz, Amp, T, Duty: Double;
  V: SmallInt;
  P: Integer;
begin
  EnsureScore;
  Samples := Round(Rate * MidiLoopSeconds);
  SetLength(Result, 44 + Samples * 2);
  FillChar(Result[0], Length(Result), 0);
  Result[0] := Ord('R'); Result[1] := Ord('I'); Result[2] := Ord('F'); Result[3] := Ord('F');
  P := 36 + Samples * 2;
  Result[4] := Byte(P); Result[5] := Byte(P shr 8); Result[6] := Byte(P shr 16); Result[7] := Byte(P shr 24);
  Result[8] := Ord('W'); Result[9] := Ord('A'); Result[10] := Ord('V'); Result[11] := Ord('E');
  Result[12] := Ord('f'); Result[13] := Ord('m'); Result[14] := Ord('t'); Result[15] := Ord(' ');
  Result[16] := 16; Result[20] := 1; Result[22] := 1;
  Result[24] := 34; Result[25] := 86; Result[26] := 0; Result[27] := 0; { 22050 Hz }
  Result[28] := 68; Result[29] := 172; Result[30] := 0; Result[31] := 0; { 44100 B/s }
  Result[32] := 2; Result[34] := 16;
  Result[36] := Ord('d'); Result[37] := Ord('a'); Result[38] := Ord('t'); Result[39] := Ord('a');
  P := Samples * 2;
  Result[40] := Byte(P); Result[41] := Byte(P shr 8); Result[42] := Byte(P shr 16); Result[43] := Byte(P shr 24);

  Duty := 0.5;
  if Mode = amChoir then
    Duty := 0.35;
  SCount := Length(Score);
  for I := 0 to Samples - 1 do
  begin
    T := I / Rate;
    Acc := 0;
    for N := 0 to SCount - 1 do
    begin
      if (T >= Score[N].Start * 60.0 / MidiBpm) and
         (T < (Score[N].Start + Score[N].Dur) * 60.0 / MidiBpm) then
      begin
        Hz := 440.0 * Power(2.0, (Score[N].Pitch - 69) / 12.0);
        Phase := Frac(T * Hz);
        Amp := Score[N].Vel / 127.0 * 0.22;
        if Score[N].Chan = 1 then
          Amp := Amp * 0.7;
        if Phase < Duty then
          Acc := Acc + Amp
        else
          Acc := Acc - Amp;
      end;
    end;
    if Acc > 0.95 then
      Acc := 0.95;
    if Acc < -0.95 then
      Acc := -0.95;
    V := Round(Acc * 32767);
    Result[44 + I * 2] := Byte(V);
    Result[45 + I * 2] := Byte(V shr 8);
  end;
end;

procedure AudioSeqInit(var Seq: TAudioSeq);
begin
  EnsureScore;
  SetLength(Seq.On, Length(Score));
  FillChar(Seq.On[0], Length(Seq.On) * SizeOf(Boolean), 0);
end;

procedure PushMsg(var Msgs: TMidiMsgArray; Status, D1, D2: Byte);
var
  N: Integer;
begin
  N := Length(Msgs);
  SetLength(Msgs, N + 1);
  Msgs[N].Status := Status;
  Msgs[N].D1 := D1;
  Msgs[N].D2 := D2;
end;

procedure AudioSeqSilence(var Seq: TAudioSeq; var Msgs: TMidiMsgArray);
var
  I: Integer;
begin
  SetLength(Msgs, 0);
  EnsureScore;
  if Length(Seq.On) <> Length(Score) then
    AudioSeqInit(Seq);
  for I := 0 to High(Score) do
    if Seq.On[I] then
    begin
      PushMsg(Msgs, $80 or Score[I].Chan, Score[I].Pitch, 0);
      Seq.On[I] := False;
    end;
end;

function AudioSeqAdvance(var Seq: TAudioSeq; SongTime: Double; Mode: TAudioMode;
  Playing: Boolean): TMidiMsgArray;
var
  I: Integer;
  Loop, T, A, B: Double;
  Want: Boolean;
begin
  SetLength(Result, 0);
  EnsureScore;
  if Length(Seq.On) <> Length(Score) then
    AudioSeqInit(Seq);
  if not Playing or (Mode = amMute) then
  begin
    AudioSeqSilence(Seq, Result);
    Exit;
  end;
  Loop := MidiLoopSeconds;
  if Loop <= 0 then
    Exit;
  T := SongTime;
  while T >= Loop do
    T := T - Loop;
  if T < 0 then
    T := 0;
  for I := 0 to High(Score) do
  begin
    A := Score[I].Start * 60.0 / MidiBpm;
    B := (Score[I].Start + Score[I].Dur) * 60.0 / MidiBpm;
    Want := (T >= A) and (T < B);
    if Want and not Seq.On[I] then
    begin
      if Length(Result) = 0 then
      begin
        { (Re)assert patches when the first note of a cycle starts. }
        PushMsg(Result, $C0, LeadProgram(Mode), 0);
        PushMsg(Result, $C1, BassProgram(Mode), 0);
      end;
      PushMsg(Result, $90 or Score[I].Chan, Score[I].Pitch, Score[I].Vel);
      Seq.On[I] := True;
    end
    else if (not Want) and Seq.On[I] then
    begin
      PushMsg(Result, $80 or Score[I].Chan, Score[I].Pitch, 0);
      Seq.On[I] := False;
    end;
  end;
end;

end.
