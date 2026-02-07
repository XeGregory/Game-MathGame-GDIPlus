object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'Math Game'
  ClientHeight = 424
  ClientWidth = 618
  Color = clBtnFace
  DoubleBuffered = True
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poDesktopCenter
  OnCreate = FormCreate
  TextHeight = 15
  object PaintBox1: TPaintBox
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 612
    Height = 418
    Align = alClient
    OnMouseDown = PaintBox1MouseDown
    OnMouseLeave = PaintBox1MouseLeave
    OnMouseMove = PaintBox1MouseMove
    OnPaint = PaintBox1Paint
    ExplicitLeft = 344
    ExplicitTop = 48
    ExplicitWidth = 105
    ExplicitHeight = 105
  end
  object TimerAnim: TTimer
    OnTimer = TimerAnimTimer
    Left = 32
    Top = 24
  end
end
