#Warn
#SingleInstance
#HotIf WinActive("ahk_class Chrome_WidgetWin_1") or WinActive("ahk_class MozillaWindowClass") or WinActive("ahk_class TTOTAL_CMD") or WinActive("ahk_exe WXWork.exe")
RButton::Send "{Blind}{RButton}"
RButton & WheelDown::Send "^{Tab}"
RButton & WheelUp::Send "^+{Tab}"