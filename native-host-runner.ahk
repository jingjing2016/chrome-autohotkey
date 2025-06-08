; native-host-runner.ahk (MUST be saved with UTF-8 with BOM encoding)
#SingleInstance Force

; 获取 stdin, stdout 的句柄
stdin := FileOpen("*", "r `n") ; AHK v2 syntax
stdout := FileOpen("*", "w `n") ; AHK v2 syntax

; Chrome Native Messaging 协议:
; 第一个 4 字节是消息长度 (little-endian integer).
Loop {
    try {
        length := 0
        length |= stdin.ReadUChar()
        length |= stdin.ReadUChar() << 8
        length |= stdin.ReadUChar() << 16
        length |= stdin.ReadUChar() << 24

        if (length = 0) {
            Continue
        }

        json_message := stdin.Read(length)

        ; Simple JSON parsing for "text" and "scriptPath"
        selectedText := ""
        userScriptPath := ""

        textPattern := '"text"\s*:\s*"(.*?)"'
        if RegExMatch(json_message, textPattern, &textMatch) {
            selectedText := textMatch[1]
            ; AHK v2's RegExMatch typically decodes JSON string escape sequences like \" to " automatically.
            ; If issues arise with other sequences like \\n, further processing might be needed,
            ; but for typical text selection, this should be okay.
        }

        scriptPathPattern := '"scriptPath"\s*:\s*"(.*?)"'
        if RegExMatch(json_message, scriptPathPattern, &scriptMatch) {
            userScriptPath := scriptMatch[1]
            ; Paths in JSON from JavaScript (via chrome.storage.sync and postMessage)
            ; are typically sent with escaped backslashes (e.g., "C:\\folder\\script.ahk").
            ; AHK v2's RegExMatch should capture this as "C:\\folder\\script.ahk".
            ; StrReplace is used to convert "C:\\folder\\script.ahk" to "C:\folder\script.ahk".
            userScriptPath := StrReplace(userScriptPath, "\\\\", "\")
        }

        if (userScriptPath = "") {
            ; Fallback: Assume "your-main-script.ahk" is in the same directory as this runner script.
            ; A_ScriptDir is the directory of the current script.
            userScriptPath := A_ScriptDir . "\your-main-script.ahk"
            ; Log this fallback for easier debugging by the user if necessary
            ; FileAppend, "LOG: userScriptPath was empty, defaulted to: " . userScriptPath . "`n", "*" ; (Sends to stdout for debugging in some contexts)
        }

        ; --- USER CONFIGURATION REQUIRED ---
        ; The user MUST set this path to their AutoHotkey.exe installation.
        ; Examples:
        ; ahkExePath := "C:\Program Files\AutoHotkey\AutoHotkey.exe"
        ; ahkExePath := "C:\Program Files\AutoHotkey\v2\AutoHotkey.exe"
        ; ahkExePath := A_AhkPath ; This might work if the script is run by an AHK version that sets it correctly.
        ahkExePath := "C:\Program Files\AutoHotkey\AutoHotkey.exe" ; !!! MODIFY THIS LINE !!!
        ; --- END USER CONFIGURATION ---


        if (selectedText != "" and userScriptPath != "") {
            ; Ensure userScriptPath and selectedText are quoted for the Run command
            Run, '"' . ahkExePath . '" "' . userScriptPath . '" "' . selectedText . '"'

            response := '{"status":"success", "executedScript":"' . userScriptPath . '", "textSent":"' . selectedText . '"}'
            response_len := StrLen(response)

            stdout.WriteChar(response_len & 0xFF)
            stdout.WriteChar((response_len >> 8) & 0xFF)
            stdout.WriteChar((response_len >> 16) & 0xFF)
            stdout.WriteChar((response_len >> 24) & 0xFF)
            stdout.Write(response)
            stdout.Flush()
        } else {
            errorMessage := "Missing text or scriptPath."
            if (selectedText = "") {
                errorMessage := "Missing text in message."
            } else if (userScriptPath = "") {
                ; This case should be handled by the fallback, but as a safeguard:
                errorMessage := "Script path is effectively empty even after fallback."
            }
            response := '{"status":"error", "message":"' . errorMessage . '"}'
            response_len := StrLen(response)

            stdout.WriteChar(response_len & 0xFF)
            stdout.WriteChar((response_len >> 8) & 0xFF)
            stdout.WriteChar((response_len >> 16) & 0xFF)
            stdout.WriteChar((response_len >> 24) & 0xFF)
            stdout.Write(response)
            stdout.Flush()
        }

    } catch as e {
        ; Attempt to send an error message back to Chrome if possible
        try {
            errorResponse := '{"status":"error", "message":"AHK runner script error: ' . e.Message . '"}'
            errorResponse_len := StrLen(errorResponse)
            stdout.WriteChar(errorResponse_len & 0xFF)
            stdout.WriteChar((errorResponse_len >> 8) & 0xFF)
            stdout.WriteChar((errorResponse_len >> 16) & 0xFF)
            stdout.WriteChar((errorResponse_len >> 24) & 0xFF)
            stdout.Write(errorResponse)
            stdout.Flush()
        } catch {
            ; If sending error fails, nothing more can be done here.
        }
        break ; Exit loop on error
    }
}
ExitApp
