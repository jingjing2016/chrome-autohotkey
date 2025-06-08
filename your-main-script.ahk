; your-main-script.ahk
#SingleInstance, Force

; AHK 脚本启动时，命令行参数存储在 A_Args 数组中
; 第一个参数是 A_Args[1]
SelectedText := A_Args[1]

; 你可以在这里对 SelectedText 做任何你想做的事情
; 例如，弹出一个消息框显示它
MsgBox, The text selected in Chrome is:`n`n%SelectedText%

; 或者用它在谷歌上搜索
; Run, https://www.google.com/search?q=%SelectedText%

; 或者将它追加到文件中
; FileAppend, %SelectedText%`n, C:\path	o\your\log.txt

ExitApp
