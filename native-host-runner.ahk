; native-host-runner.ahk (MUST be saved with UTF-8 with BOM encoding)
#SingleInstance Force

; 获取 stdin, stdout 的句柄
stdin := FileOpen("*", "r `n") ; AHK v2 syntax
stdout := FileOpen("*", "w `n") ; AHK v2 syntax

; Chrome Native Messaging 协议:
; 第一个 4 字节是消息长度 (little-endian integer).
Loop {
    try {
        ; 1. 读取消息长度 (4 bytes)
        length := 0
        length |= stdin.ReadUChar()
        length |= stdin.ReadUChar() << 8
        length |= stdin.ReadUChar() << 16
        length |= stdin.ReadUChar() << 24

        if (length = 0) {
            Continue
        }

        ; 2. 根据长度读取 JSON 消息字符串
        json_message := stdin.Read(length)

        ; 3. 解析 JSON (AHK v2 没有内置 JSON，但可以简单地手动解析或使用库)
        ; 对于我们这个简单的例子，我们可以假设格式是 {"text":"some value"}
        ; 一个简单的解析方法：
        pattern := '"text"\s*:\s*"(.*?)"'
        if RegExMatch(json_message, pattern, &match) {
            selectedText := match[1]

            ; 4. 运行你的主 AHK 脚本，并将文本作为参数传递
            ; !! 修改为你主脚本的绝对路径 !!
            Run, "C:\path\to\AutoHotkey\AutoHotkey.exe" "C:\path\to\your-main-script.ahk" "`"" . selectedText . "`""

            ; 5. (可选) 发送一个响应给 Chrome 扩展
            response := '{"status":"success"}'
            response_len := StrLen(response)

            ; 同样按照 4-byte length + message 的格式写回 stdout
            stdout.WriteChar(response_len & 0xFF)
            stdout.WriteChar((response_len >> 8) & 0xFF)
            stdout.WriteChar((response_len >> 16) & 0xFF)
            stdout.WriteChar((response_len >> 24) & 0xFF)
            stdout.Write(response)
            stdout.Flush()
        }
    } catch as e {
        ; 如果发生错误或 stdin 关闭，退出循环
        break
    }
}

ExitApp
