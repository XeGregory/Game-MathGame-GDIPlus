unit MathGameForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.ExtCtrls,
  GDIPAPI, GDIPOBJ, System.Math, System.Types, System.Generics.Collections;

type
  TLevel = (lvCP, lvCE1, lvCE2, lvCM1, lvCM2);

  TOptionItem = record
    Rect: TGPRectF;
    Text: string;
    IsCorrect: Boolean;
    WasClicked: Boolean;
  end;

  TParticle = record
    X, Y, VX, VY, Size: Single;
    Color: TGPColor;
    Life: Single;
  end;

  TForm1 = class(TForm)
    PaintBox1: TPaintBox;
    TimerAnim: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure PaintBox1Paint(Sender: TObject);
    procedure PaintBox1MouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure TimerAnimTimer(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure PaintBox1MouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure PaintBox1MouseLeave(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    // état du jeu
    FLevel: TLevel;
    FQuestionText: string;
    FCorrectAnswer: Integer;
    FOptions: TArray<TOptionItem>;

    // animation / interaction
    FAnimPhase: Double;
    FSelectedOptionIndex: Integer;
    FHoverOptionIndex: Integer;
    FHoverLevelIndex: Integer;

    // zones dessinées
    FLevelRects: array [0 .. 4] of TGPRectF;
    FLevelLabels: array [0 .. 4] of string;
    FQuestionRect: TGPRectF;
    FMessageRect: TGPRectF; // zone du message entre question et réponses

    // ressources GDI+
    FCachedFontTitle: TGPFont;
    FCachedFontOption: TGPFont;
    FBrushBG: TGPSolidBrush;
    FBrushBtn: TGPSolidBrush;
    FBrushBtnHover: TGPSolidBrush;
    FBrushText: TGPSolidBrush;
    FPenBtn: TGPPen;

    // confettis
    FShowConfetti: Boolean;
    FParticles: TArray<TParticle>;

    // easing
    FOptionScale: TArray<Single>;
    FTargetScale: TArray<Single>;

    // message feedback
    FMessage: string;
    FMessageTimeLeft: Double; // délai avant de changer la question

    // progression & score
    FScore: Integer;
    FStreak: Integer;
    FTotalQuestions: Integer;
    FCorrectCount: Integer;

    // helpers
    function FlatColor(R, G, B: Byte): TGPColor;
    procedure NewQuestion;
    procedure GenerateOptions(Count: Integer);
    procedure LayoutOptions;
    // calcule FLevelRects, FQuestionRect, FMessageRect, FOptions[].Rect
    procedure DrawRoundedRect(G: TGPGraphics; const R: TGPRectF; Radius: Single;
      Pen: TGPPen; Brush: TGPSolidBrush);
    procedure DrawQuestion(G: TGPGraphics; const Rect: TGPRectF);
    function PointInRectF(const R: TGPRectF; X, Y: Single): Boolean;
    procedure EmitConfetti(const CenterX, CenterY: Single; Count: Integer);
    procedure UpdateScoreOnAnswer(Correct: Boolean);
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}
{ --- utilitaires --- }

function MakeRectF(X, Y, Width, Height: Single): TGPRectF;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Width := Width;
  Result.Height := Height;
end;

{ --- TForm1 --- }

function TForm1.FlatColor(R, G, B: Byte): TGPColor;
begin
  Result := MakeColor(255, R, G, B);
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  Randomize;

  // état initial
  FLevel := lvCP;
  FAnimPhase := 0;
  FSelectedOptionIndex := -1;
  FHoverOptionIndex := -1;
  FHoverLevelIndex := -1;
  FShowConfetti := False;
  FMessage := '';
  FMessageTimeLeft := 0;

  // labels niveaux (5 niveaux)
  FLevelLabels[0] := 'CP';
  FLevelLabels[1] := 'CE1';
  FLevelLabels[2] := 'CE2';
  FLevelLabels[3] := 'CM1';
  FLevelLabels[4] := 'CM2';

  // timer
  TimerAnim.Interval := 30;
  TimerAnim.Enabled := True;

  // ressources GDI+
  FCachedFontTitle := TGPFont.Create('Segoe UI', 40, FontStyleBold, UnitPixel);
  FCachedFontOption := TGPFont.Create('Segoe UI', 18, FontStyleBold, UnitPixel);
  FBrushBG := TGPSolidBrush.Create(FlatColor(236, 240, 241)); // #ecf0f1
  FBrushBtn := TGPSolidBrush.Create(FlatColor(255, 255, 255));
  FBrushBtnHover := TGPSolidBrush.Create(FlatColor(52, 152, 219)); // #3498db
  FBrushText := TGPSolidBrush.Create(FlatColor(44, 62, 80)); // #2c3e50
  FPenBtn := TGPPen.Create(FlatColor(189, 195, 199), 2);

  // progression & score initialisés
  FScore := 0;
  FStreak := 0;
  FTotalQuestions := 0;
  FCorrectCount := 0;

  // initialisation contenu
  NewQuestion;
  LayoutOptions;

  // handlers (au cas où non définis dans DFM)
  PaintBox1.OnPaint := PaintBox1Paint;
  PaintBox1.OnMouseDown := PaintBox1MouseDown;
  PaintBox1.OnMouseMove := PaintBox1MouseMove;
  PaintBox1.OnMouseLeave := PaintBox1MouseLeave;
  Self.OnResize := FormResize;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  if Assigned(FCachedFontTitle) then
    FCachedFontTitle.Free;
  if Assigned(FCachedFontOption) then
    FCachedFontOption.Free;
  if Assigned(FBrushBG) then
    FBrushBG.Free;
  if Assigned(FBrushBtn) then
    FBrushBtn.Free;
  if Assigned(FBrushBtnHover) then
    FBrushBtnHover.Free;
  if Assigned(FBrushText) then
    FBrushText.Free;
  if Assigned(FPenBtn) then
    FPenBtn.Free;
end;

{ --- génération question/options --- }

procedure TForm1.NewQuestion;
var
  a, B, rndOp, resultVal: Integer;
  opChar: Char;
  i: Integer;
  promptText: string;
begin
  a := 0;
  B := 0;
  resultVal := 0;
  opChar := '+';

  case FLevel of
    lvCP:
      begin
        a := Random(9) + 1;
        B := Random(9) + 1;
        if a + B > 10 then
        begin
          if a > B then
            a := 10 - B
          else
            B := 10 - a;
          if a <= 0 then
            a := 1;
          if B <= 0 then
            B := 1;
        end;
        resultVal := a + B;
        opChar := '+';
      end;
    lvCE1:
      begin
        rndOp := Random(2);
        if rndOp = 0 then
        begin
          a := Random(19) + 1;
          B := Random(19) + 1;
          if a + B > 20 then
            if a > B then
              a := 20 - B
            else
              B := 20 - a;
          if a <= 0 then
            a := 1;
          if B <= 0 then
            B := 1;
          resultVal := a + B;
          opChar := '+';
        end
        else
        begin
          a := Random(20) + 1;
          B := Random(a + 1);
          resultVal := a - B;
          opChar := '-';
        end;
      end;
    lvCE2:
      begin
        rndOp := Random(3);
        if rndOp = 2 then
        begin
          a := Random(12) + 1;
          B := Random(9) + 1;
          resultVal := a * B;
          opChar := '×';
        end
        else if rndOp = 0 then
        begin
          a := Random(99) + 1;
          B := Random(99) + 1;
          if a + B > 100 then
            if a > B then
              a := 100 - B
            else
              B := 100 - a;
          if a <= 0 then
            a := 1;
          if B <= 0 then
            B := 1;
          resultVal := a + B;
          opChar := '+';
        end
        else
        begin
          a := Random(100) + 1;
          B := Random(a + 1);
          resultVal := a - B;
          opChar := '-';
        end;
      end;
    lvCM1:
      begin
        rndOp := Random(3);
        if rndOp = 0 then
        begin
          a := Random(199) + 1;
          B := Random(199) + 1;
          resultVal := a + B;
          opChar := '+';
        end
        else if rndOp = 1 then
        begin
          a := Random(199) + 1;
          B := Random(a + 1);
          resultVal := a - B;
          opChar := '-';
        end
        else
        begin
          a := Random(12) + 2;
          B := Random(12) + 2;
          resultVal := a * B;
          opChar := '×';
        end;
      end;
    lvCM2:
      begin
        rndOp := Random(4);
        if rndOp = 0 then
        begin
          a := Random(499) + 1;
          B := Random(499) + 1;
          resultVal := a + B;
          opChar := '+';
        end
        else if rndOp = 1 then
        begin
          a := Random(499) + 1;
          B := Random(a + 1);
          resultVal := a - B;
          opChar := '-';
        end
        else if rndOp = 2 then
        begin
          a := Random(20) + 2;
          B := Random(12) + 2;
          resultVal := a * B;
          opChar := '×';
        end
        else
        begin
          B := Random(12) + 2;
          resultVal := Random(20) + 2;
          a := B * resultVal;
          opChar := '÷';
        end;
      end;
  end;

  FQuestionText := Format('%d %s %d =', [a, opChar, B]);
  FCorrectAnswer := resultVal;

  GenerateOptions(4);

  SetLength(FOptionScale, Length(FOptions));
  SetLength(FTargetScale, Length(FOptions));
  for i := 0 to Length(FOptionScale) - 1 do
  begin
    FOptionScale[i] := 1.0;
    FTargetScale[i] := 1.0;
    FOptions[i].WasClicked := False;
  end;

  case opChar of
    '+':
      promptText := 'Quelle est la somme de cette addition ?';
    '-':
      promptText := 'Quel est le résultat de cette soustraction ?';
    '×':
      promptText := 'Quel est le produit de cette multiplication ?';
    '÷':
      promptText := 'Quel est le quotient de cette division ?';
  else
    promptText := 'Quelle est la réponse de cette opération ?';
  end;

  FSelectedOptionIndex := -1;
  FHoverOptionIndex := -1;
  FHoverLevelIndex := -1;

  // afficher le prompt (persistant jusqu'à réponse ou remplacement)
  FMessage := promptText;
  FMessageTimeLeft := 0; // message persistant par défaut

  // ne pas toucher à FShowConfetti ici (EmitConfetti gère l'affichage)
  LayoutOptions;
  PaintBox1.Invalidate;
end;

procedure TForm1.GenerateOptions(Count: Integer);
var
  vals: TList<Integer>;
  candidate, delta: Integer;
  i, j: Integer;
begin
  vals := TList<Integer>.Create;
  try
    vals.Add(FCorrectAnswer);
    while vals.Count < Count do
    begin
      delta := 1 + Random(Max(8, Abs(FCorrectAnswer div 4) + 1));
      if Random(2) = 0 then
        candidate := FCorrectAnswer + delta
      else
        candidate := FCorrectAnswer - delta;
      if candidate < 0 then
        candidate := Abs(candidate) + 1;
      if not vals.Contains(candidate) then
        vals.Add(candidate);
    end;

    for i := 0 to vals.Count - 1 do
    begin
      j := Random(vals.Count);
      if i <> j then
        vals.Exchange(i, j);
    end;

    SetLength(FOptions, vals.Count);
    for i := 0 to vals.Count - 1 do
    begin
      FOptions[i].Text := vals[i].ToString;
      FOptions[i].IsCorrect := (vals[i] = FCorrectAnswer);
      FOptions[i].Rect := MakeRectF(0, 0, 0, 0);
      FOptions[i].WasClicked := False;
    end;
  finally
    vals.Free;
  end;
end;

{ --- layout centralisé --- }

procedure TForm1.LayoutOptions;
var
  pbW, pbH: Integer;
  margin, topMargin: Integer;
  levelH, questionH, messageH: Integer;
  btnAreaTop: Integer;
  cols, rows: Integer;
  btnW, btnH: Integer;
  idx, R, c: Integer;
  totalLevels: Integer;
  scoreAreaWidth: Integer;
begin
  pbW := PaintBox1.Width;
  pbH := PaintBox1.Height;
  margin := 12;
  topMargin := 8;

  // 1) zone niveaux (en haut)
  levelH := Max(36, Round(pbH * 0.08));
  totalLevels := 5;
  // réserver un petit espace à droite pour afficher le score à la suite des boutons niveaux
  scoreAreaWidth := Max(140, Round(pbW * 0.20));
  btnW := Max(64, (pbW - margin * (totalLevels + 2) - scoreAreaWidth)
    div totalLevels);
  for idx := 0 to totalLevels - 1 do
    FLevelRects[idx] := MakeRectF(margin + idx * (btnW + margin), topMargin,
      btnW, levelH);

  // 2) zone question : juste sous les niveaux
  questionH := Max(72, Round(pbH * 0.20));
  FQuestionRect := MakeRectF(10, topMargin + levelH + margin, pbW - 20,
    questionH);

  // 3) zone message (entre question et réponses)
  messageH := Max(40, Round(pbH * 0.07));
  FMessageRect := MakeRectF(10, FQuestionRect.Y + FQuestionRect.Height + margin,
    pbW - 20, messageH);

  // 4) zone réponses : sous la zone message
  btnAreaTop := Round(FMessageRect.Y + FMessageRect.Height + margin);
  cols := 2;
  rows := Ceil(Length(FOptions) / cols);
  btnW := Max(80, (pbW - margin * (cols + 1)) div cols);
  btnH := Max(56, (pbH - btnAreaTop - margin * (rows + 1)) div rows);

  idx := 0;
  for R := 0 to rows - 1 do
    for c := 0 to cols - 1 do
    begin
      if idx >= Length(FOptions) then
        Break;
      FOptions[idx].Rect := MakeRectF(margin + c * (btnW + margin),
        btnAreaTop + margin + R * (btnH + margin), btnW, btnH);
      Inc(idx);
    end;
end;

{ --- dessin --- }

procedure TForm1.DrawRoundedRect(G: TGPGraphics; const R: TGPRectF;
  Radius: Single; Pen: TGPPen; Brush: TGPSolidBrush);
var
  path: TGPGraphicsPath;
  X, Y, w, h: Single;
begin
  X := R.X;
  Y := R.Y;
  w := R.Width;
  h := R.Height;
  path := TGPGraphicsPath.Create;
  try
    path.AddArc(X, Y, Radius * 2, Radius * 2, 180, 90);
    path.AddArc(X + w - Radius * 2, Y, Radius * 2, Radius * 2, 270, 90);
    path.AddArc(X + w - Radius * 2, Y + h - Radius * 2, Radius * 2,
      Radius * 2, 0, 90);
    path.AddArc(X, Y + h - Radius * 2, Radius * 2, Radius * 2, 90, 90);
    path.CloseFigure;
    if Assigned(Brush) then
      G.FillPath(Brush, path);
    if Assigned(Pen) then
      G.DrawPath(Pen, path);
  finally
    path.Free;
  end;
end;

procedure TForm1.DrawQuestion(G: TGPGraphics; const Rect: TGPRectF);
var
  titleFont, opFont: TGPFont;
  Brush: TGPSolidBrush;
  sf: TGPStringFormat;
  qRectLeft, opRect, qRectRight: TGPRectF;
  parts: TArray<string>;
  sA, sOp, sB: string;
  penLine: TGPPen;
  lineY: Single;
  dynSize: Integer;
begin
  Brush := TGPSolidBrush.Create(FlatColor(44, 62, 80));
  try
    dynSize := Max(28, Round(Rect.Height * 0.45));
    titleFont := TGPFont.Create('Segoe UI', dynSize, FontStyleBold, UnitPixel);
    opFont := TGPFont.Create('Segoe UI', Max(18, Round(dynSize * 0.7)),
      FontStyleBold, UnitPixel);
    try
      sf := TGPStringFormat.Create;
      sf.SetAlignment(StringAlignmentNear);
      sf.SetLineAlignment(StringAlignmentCenter);

      qRectLeft := MakeRectF(Rect.X + 10, Rect.Y, Rect.Width * 0.45,
        Rect.Height);
      opRect := MakeRectF(Rect.X + 10 + Rect.Width * 0.45, Rect.Y,
        Rect.Width * 0.1, Rect.Height);
      qRectRight := MakeRectF(Rect.X + 10 + Rect.Width * 0.55, Rect.Y,
        Rect.Width * 0.35, Rect.Height);

      parts := FQuestionText.Split([' ']);
      sA := '';
      sOp := '';
      sB := '';
      if Length(parts) >= 3 then
      begin
        sA := parts[0];
        sOp := parts[1];
        sB := parts[2];
      end
      else
        sA := FQuestionText;

      sf.SetAlignment(StringAlignmentFar);
      G.DrawString(PWideChar(sA), -1, titleFont, qRectLeft, sf, Brush);

      var
      sfOp := TGPStringFormat.Create;
      try
        sfOp.SetAlignment(StringAlignmentCenter);
        sfOp.SetLineAlignment(StringAlignmentCenter);
        G.DrawString(PWideChar(sOp), -1, opFont, opRect, sfOp, Brush);
      finally
        sfOp.Free;
      end;

      sf.SetAlignment(StringAlignmentNear);
      G.DrawString(PWideChar(sB), -1, titleFont, qRectRight, sf, Brush);

      penLine := TGPPen.Create(FlatColor(189, 195, 199), 3);
      try
        lineY := Rect.Y + Rect.Height - 8;
        G.DrawLine(penLine, Rect.X + 10, lineY, Rect.X + Rect.Width -
          10, lineY);
      finally
        penLine.Free;
      end;

      sf.Free;
    finally
      titleFont.Free;
      opFont.Free;
    end;
  finally
    Brush.Free;
  end;
end;

procedure TForm1.PaintBox1Paint(Sender: TObject);
var
  G: TGPGraphics;
  i, k: Integer;
  R: TGPRectF;
  useBrush: TGPSolidBrush;
  fontSize: Integer;
  gFont: TGPFont;
  sf: TGPStringFormat;
  scaledRect: TGPRectF;
  CenterX, CenterY, scale: Double;
  tempBrush: TGPSolidBrush;
  pBrush: TGPSolidBrush;
  fbFormat: TGPStringFormat;
  levelBrush, levelTextBrush, whiteBrush: TGPSolidBrush;
  penCross: TGPPen;
  scoreArea: TGPRectF;
  scoreText, statsText: string;
begin
  G := TGPGraphics.Create(PaintBox1.Canvas.Handle);
  try
    G.SetSmoothingMode(SmoothingModeHighQuality);

    // fond
    G.FillRectangle(FBrushBG, MakeRectF(0, 0, PaintBox1.Width,
      PaintBox1.Height));

    // préparer brushes temporaires
    levelBrush := TGPSolidBrush.Create(FlatColor(255, 255, 255));
    levelTextBrush := TGPSolidBrush.Create(FlatColor(44, 62, 80));
    whiteBrush := TGPSolidBrush.Create(FlatColor(255, 255, 255));
    try
      // dessiner boutons niveaux (5)
      for i := 0 to 4 do
      begin
        if i = FHoverLevelIndex then
          DrawRoundedRect(G, FLevelRects[i], 8, FPenBtn, FBrushBtnHover)
        else if (Ord(FLevel) = i) then
          DrawRoundedRect(G, FLevelRects[i], 8, FPenBtn,
            TGPSolidBrush.Create(FlatColor(230, 245, 255)))
        else
          DrawRoundedRect(G, FLevelRects[i], 8, FPenBtn, levelBrush);

        // texte
        gFont := TGPFont.Create('Segoe UI', 14, FontStyleBold, UnitPixel);
        try
          sf := TGPStringFormat.Create;
          sf.SetAlignment(StringAlignmentCenter);
          sf.SetLineAlignment(StringAlignmentCenter);
          if i = FHoverLevelIndex then
            G.DrawString(PWideChar(FLevelLabels[i]), -1, gFont, FLevelRects[i],
              sf, whiteBrush)
          else
            G.DrawString(PWideChar(FLevelLabels[i]), -1, gFont, FLevelRects[i],
              sf, levelTextBrush);
          sf.Free;
        finally
          gFont.Free;
        end;
      end;

      // dessiner la zone score à la suite des boutons niveaux (droite)
      // calculer position : alignée verticalement avec les boutons niveaux
      scoreArea := MakeRectF(PaintBox1.Width - 160, FLevelRects[0].Y, 150,
        FLevelRects[0].Height);
      DrawRoundedRect(G, scoreArea, 8, FPenBtn,
        TGPSolidBrush.Create(FlatColor(255, 255, 255)));
      // afficher score et combo
      gFont := TGPFont.Create('Segoe UI', 12, FontStyleBold, UnitPixel);
      try
        sf := TGPStringFormat.Create;
        sf.SetAlignment(StringAlignmentCenter);
        sf.SetLineAlignment(StringAlignmentNear);
        scoreText := Format('Score : %d', [FScore]);
        G.DrawString(PWideChar(scoreText), -1, gFont,
          MakeRectF(scoreArea.X + 8, scoreArea.Y + 6, scoreArea.Width - 16, 18),
          sf, FBrushText);
        statsText := Format('Bonnes : %d / %d',
          [FCorrectCount, FTotalQuestions]);
        sf.SetLineAlignment(StringAlignmentFar);
        G.DrawString(PWideChar(statsText), -1, gFont,
          MakeRectF(scoreArea.X + 8, scoreArea.Y + 24, scoreArea.Width - 16,
          18), sf, FBrushText);
        sf.Free;
      finally
        gFont.Free;
      end;

    finally
      levelBrush.Free;
      levelTextBrush.Free;
      whiteBrush.Free;
    end;

    // dessiner question
    DrawQuestion(G, FQuestionRect);

    // dessiner message feedback (entre question et réponses)
    if FMessage <> '' then
    begin
      gFont := TGPFont.Create('Segoe UI', 18, FontStyleBold, UnitPixel);
      pBrush := TGPSolidBrush.Create(FlatColor(44, 62, 80));
      try
        fbFormat := TGPStringFormat.Create;
        fbFormat.SetAlignment(StringAlignmentCenter);
        fbFormat.SetLineAlignment(StringAlignmentCenter);
        DrawRoundedRect(G, FMessageRect, 10, FPenBtn,
          TGPSolidBrush.Create(FlatColor(255, 255, 255)));
        G.DrawString(PWideChar(FMessage), -1, gFont, FMessageRect,
          fbFormat, pBrush);
        fbFormat.Free;
      finally
        gFont.Free;
        pBrush.Free;
      end;
    end;

    // dessiner options (2x2)
    for i := 0 to Length(FOptions) - 1 do
    begin
      R := FOptions[i].Rect;
      if (R.Width <= 0) or (R.Height <= 0) then
        Continue;

      // scale easing
      scale := 1.0;
      if i < Length(FOptionScale) then
        scale := FOptionScale[i];
      CenterX := R.X + R.Width / 2;
      CenterY := R.Y + R.Height / 2;
      scaledRect := MakeRectF(CenterX - R.Width * scale / 2,
        CenterY - R.Height * scale / 2, R.Width * scale, R.Height * scale);

      // brush selection
      tempBrush := nil;
      if i = FHoverOptionIndex then
        useBrush := FBrushBtnHover
      else if (i = FSelectedOptionIndex) and FOptions[i].IsCorrect then
      begin
        tempBrush := TGPSolidBrush.Create(FlatColor(46, 204, 113));
        useBrush := tempBrush;
      end
      else
        useBrush := FBrushBtn;

      try
        DrawRoundedRect(G, scaledRect, 12, FPenBtn, useBrush);

        // texte : blanc si fond coloré (hover or selected correct)
        if (i = FHoverOptionIndex) or
          ((i = FSelectedOptionIndex) and Assigned(tempBrush)) then
          pBrush := TGPSolidBrush.Create(FlatColor(255, 255, 255))
        else
          pBrush := FBrushText;

        try
          fontSize :=
            Max(14, Round(Min(scaledRect.Width, scaledRect.Height) / 4));
          gFont := TGPFont.Create('Segoe UI', fontSize, FontStyleBold,
            UnitPixel);
          try
            sf := TGPStringFormat.Create;
            sf.SetAlignment(StringAlignmentCenter);
            sf.SetLineAlignment(StringAlignmentCenter);
            G.DrawString(PWideChar(FOptions[i].Text), -1, gFont, scaledRect,
              sf, pBrush);
            sf.Free;
          finally
            gFont.Free;
          end;
        finally
          if pBrush <> FBrushText then
            pBrush.Free;
        end;

        // si cliqué et faux => dessiner croix rouge
        if FOptions[i].WasClicked and (not FOptions[i].IsCorrect) then
        begin
          penCross := TGPPen.Create(FlatColor(231, 76, 60), 6);
          try
            G.DrawLine(penCross, scaledRect.X + 10, scaledRect.Y + 10,
              scaledRect.X + scaledRect.Width - 10,
              scaledRect.Y + scaledRect.Height - 10);
            G.DrawLine(penCross, scaledRect.X + scaledRect.Width - 10,
              scaledRect.Y + 10, scaledRect.X + 10,
              scaledRect.Y + scaledRect.Height - 10);
          finally
            penCross.Free;
          end;
        end;

      finally
        if Assigned(tempBrush) then
          tempBrush.Free;
      end;
    end;

    // confettis
    if FShowConfetti and (Length(FParticles) > 0) then
    begin
      for k := 0 to High(FParticles) do
      begin
        if FParticles[k].Life <= 0 then
          Continue;
        pBrush := TGPSolidBrush.Create(FParticles[k].Color);
        try
          G.FillEllipse(pBrush, MakeRectF(FParticles[k].X, FParticles[k].Y,
            FParticles[k].Size, FParticles[k].Size));
        finally
          pBrush.Free;
        end;
      end;
    end;

  finally
    G.Free;
  end;
end;

{ --- interaction --- }

function TForm1.PointInRectF(const R: TGPRectF; X, Y: Single): Boolean;
begin
  Result := (X >= R.X) and (X <= R.X + R.Width) and (Y >= R.Y) and
    (Y <= R.Y + R.Height);
end;

procedure TForm1.UpdateScoreOnAnswer(Correct: Boolean);
var
  basePoints, bonus: Integer;
begin
  Inc(FTotalQuestions);
  if Correct then
  begin
    Inc(FCorrectCount);
    Inc(FStreak);
    basePoints := 10;
    bonus := (FStreak - 1) * 2; // +2 points par combo supplémentaire
    Inc(FScore, basePoints + bonus);
  end
  else
  begin
    FStreak := 0;
  end;
end;

procedure TForm1.PaintBox1MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
  ptX, ptY: Single;
begin
  ptX := X;
  ptY := Y;

  // 1) clic sur niveau ? (priorité)
  for i := 0 to 4 do
    if PointInRectF(FLevelRects[i], ptX, ptY) then
    begin
      case i of
        0:
          FLevel := lvCP;
        1:
          FLevel := lvCE1;
        2:
          FLevel := lvCE2;
        3:
          FLevel := lvCM1;
        4:
          FLevel := lvCM2;
      end;
      // réinitialiser session si on change de niveau
      FScore := 0;
      FStreak := 0;
      FTotalQuestions := 0;
      FCorrectCount := 0;
      NewQuestion;
      PaintBox1.Invalidate;
      Exit; // important : ne pas tester les options
    end;

  // 2) clic sur option ?
  for i := 0 to Length(FOptions) - 1 do
    if PointInRectF(FOptions[i].Rect, ptX, ptY) then
    begin
      FSelectedOptionIndex := i;
      FOptions[i].WasClicked := True;

      if FOptions[i].IsCorrect then
      begin
        // afficher message et lancer animation, puis attendre avant de changer la question
        FMessage := 'Bravo !';
        FMessageTimeLeft := 1.6;
        // durée en secondes pendant laquelle on garde le message + confettis
        UpdateScoreOnAnswer(True);
        EmitConfetti(FOptions[i].Rect.X + FOptions[i].Rect.Width / 2,
          FOptions[i].Rect.Y + FOptions[i].Rect.Height / 2, 40);
        // NE PAS appeler NewQuestion ici : TimerAnimTimer s'en chargera après le délai
      end
      else
      begin
        FMessage := 'Essaie encore';
        FMessageTimeLeft := 0; // court délai pour afficher le message d'erreur
        UpdateScoreOnAnswer(False);
      end;

      PaintBox1.Invalidate;
      Exit;
    end;
end;

procedure TForm1.PaintBox1MouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  i: Integer;
  ptX, ptY: Single;
begin
  ptX := X;
  ptY := Y;

  // reset
  FHoverLevelIndex := -1;
  FHoverOptionIndex := -1;

  // priorité hover niveaux
  for i := 0 to 4 do
    if PointInRectF(FLevelRects[i], ptX, ptY) then
    begin
      FHoverLevelIndex := i;
      PaintBox1.Invalidate;
      Exit;
    end;

  // hover options
  for i := 0 to Length(FOptions) - 1 do
    if PointInRectF(FOptions[i].Rect, ptX, ptY) then
    begin
      FHoverOptionIndex := i;
      PaintBox1.Invalidate;
      Exit;
    end;

  PaintBox1.Invalidate;
end;

procedure TForm1.PaintBox1MouseLeave(Sender: TObject);
begin
  FHoverLevelIndex := -1;
  FHoverOptionIndex := -1;
  PaintBox1.Invalidate;
end;

procedure TForm1.TimerAnimTimer(Sender: TObject);
var
  i, k: Integer;
  allDead: Boolean;
begin
  FAnimPhase := Frac(FAnimPhase + 0.02);

  // easing scales for options
  for i := 0 to Length(FOptionScale) - 1 do
  begin
    // garder toutes les cibles à 1.0 (pas de shrink au clic)
    FTargetScale[i] := 1.0;
    FOptionScale[i] := FOptionScale[i] +
      (FTargetScale[i] - FOptionScale[i]) * 0.18;
  end;

  // update particles
  if FShowConfetti and (Length(FParticles) > 0) then
  begin
    allDead := True;
    for k := 0 to High(FParticles) do
    begin
      if FParticles[k].Life > 0 then
      begin
        FParticles[k].VY := FParticles[k].VY + 0.25;
        FParticles[k].X := FParticles[k].X + FParticles[k].VX;
        FParticles[k].Y := FParticles[k].Y + FParticles[k].VY;
        FParticles[k].Life := FParticles[k].Life - 0.02;
        if FParticles[k].Life > 0 then
          allDead := False;
      end;
    end;
    if allDead then
    begin
      FShowConfetti := False;
      SetLength(FParticles, 0);
    end;
  end;

  // message timer : décrémente et déclenche la nouvelle question si nécessaire
  if FMessageTimeLeft > 0 then
  begin
    FMessageTimeLeft := FMessageTimeLeft - (TimerAnim.Interval / 1000);
    if FMessageTimeLeft <= 0 then
    begin
      // si message de succès, on génère la nouvelle question
      if FMessage = 'Bravo !' then
      begin
        // réinitialiser le message avant la nouvelle question
        FMessage := '';
        NewQuestion;
      end
      else
      begin
        // pour message d'erreur, on efface simplement le message
        FMessage := '';
        PaintBox1.Invalidate;
      end;
    end;
  end;

  PaintBox1.Invalidate;
end;

procedure TForm1.EmitConfetti(const CenterX, CenterY: Single; Count: Integer);
var
  i: Integer;
  p: TParticle;
  flatPalette: array [0 .. 4] of TGPColor;
begin
  flatPalette[0] := FlatColor(52, 152, 219);
  flatPalette[1] := FlatColor(46, 204, 113);
  flatPalette[2] := FlatColor(241, 196, 15);
  flatPalette[3] := FlatColor(231, 76, 60);
  flatPalette[4] := FlatColor(155, 89, 182);

  SetLength(FParticles, Count);
  for i := 0 to Count - 1 do
  begin
    p.X := CenterX;
    p.Y := CenterY;
    p.VX := (Random - 0.5) * 8;
    p.VY := -Random * 8 - 2;
    p.Size := 3 + Random * 10;
    p.Color := flatPalette[Random(Length(flatPalette))];
    p.Life := 1.0;
    FParticles[i] := p;
  end;
  FShowConfetti := True;
end;

procedure TForm1.FormResize(Sender: TObject);
begin
  LayoutOptions;
  PaintBox1.Invalidate;
end;

end.
