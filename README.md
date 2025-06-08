当然可以！这是一个非常棒且实用的想法。实现这个功能需要结合三个主要部分：

1.  **Chrome Extension (前端)**: 负责检测用户的文字选择行为，并创建一个可点击的按钮。
2.  **Native Messaging Host (桥梁)**: 这是关键部分。由于浏览器出于安全考虑，不能直接执行本地程序，我们需要一个“原生消息主机”作为扩展和本地程序之间的安全通信桥梁。
3.  **AutoHotkey 脚本 (后端)**: 接收来自浏览器的指令（包含选中的文本）并执行相应的操作。

下面我将为你详细分解每一步的实现方法。

---

### 总体工作流程

1.  **用户在网页上选择文本**。
2.  **Content Script (`content.js`)** 检测到 `mouseup` 事件，并发现有文本被选中。
3.  `content.js` 在选中文本旁边创建一个小按钮。
4.  **用户点击这个小按钮**。
5.  `content.js` 将选中的文本发送给 **Background Script (`background.js`)**。
6.  `background.js` 通过 **Native Messaging API** 将数据发送给 **Native Messaging Host**。
7.  Chrome 启动一个中间 AHK 脚本（作为 Host），并通过标准输入（stdin）将数据传递给它。
8.  这个中间 AHK 脚本接收到数据后，再调用你**真正想要运行的目标 AHK 脚本**，并将选中的文本作为参数传递过去。

---

### 第1步：创建 Chrome Extension

你的扩展项目文件夹结构大致如下：

```
my-ahk-extension/
├── manifest.json
├── icons/
│   ├── icon16.png
│   ├── icon48.png
│   └── icon128.png
├── content.js
└── background.js
```

#### 1.1 `manifest.json`

这是扩展的配置文件，告诉 Chrome 它的功能和所需权限。

```json
{
  "manifest_version": 3,
  "name": "AHK Text Selector",
  "version": "1.0",
  "description": "Select text and click a button to run a local AutoHotkey script.",
  "permissions": [
    "activeTab",
    "nativeMessaging"
  ],
  "background": {
    "service_worker": "background.js"
  },
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["content.js"],
      "css": [] // 你可以添加一个 CSS 文件来美化按钮
    }
  ],
  "icons": {
    "16": "icons/icon16.png",
    "48": "icons/icon48.png",
    "128": "icons/icon128.png"
  }
}
```

**关键点**:
*   `"permissions": ["nativeMessaging"]`: 这是允许扩展与本地应用通信的核心权限。
*   `"content_scripts"`: 将 `content.js` 注入到所有网页中。
*   `"background"`: 注册我们的后台服务工作线程。

#### 1.2 `content.js`

这个脚本在网页上运行，负责处理UI。

```javascript
let popup_button = null;

// 监听鼠标抬起事件，这是选择文本结束的标志
document.addEventListener('mouseup', function(e) {
    // 稍微延迟以确保 getSelection() 能获取到最新内容
    setTimeout(() => {
        const selection = window.getSelection();
        const selectedText = selection.toString().trim();

        // 如果已经有按钮，先移除
        if (popup_button) {
            popup_button.remove();
            popup_button = null;
        }

        if (selectedText.length > 0) {
            // 创建按钮
            popup_button = document.createElement('button');
            popup_button.innerHTML = '▶️ Run AHK';
            popup_button.style.position = 'absolute';
            popup_button.style.zIndex = '99999';
            popup_button.style.border = '1px solid #ccc';
            popup_button.style.borderRadius = '5px';
            popup_button.style.padding = '5px 8px';
            popup_button.style.backgroundColor = 'white';
            popup_button.style.cursor = 'pointer';

            // 定位按钮
            const range = selection.getRangeAt(0);
            const rect = range.getBoundingClientRect();
            popup_button.style.top = `${window.scrollY + rect.bottom + 5}px`;
            popup_button.style.left = `${window.scrollX + rect.left}px`;
            
            document.body.appendChild(popup_button);

            // 按钮点击事件
            popup_button.addEventListener('click', () => {
                console.log("Button clicked, sending text:", selectedText);
                // 向 background.js 发送消息
                chrome.runtime.sendMessage({
                    type: "run_ahk",
                    text: selectedText
                });
                // 点击后隐藏按钮
                popup_button.remove();
                popup_button = null;
            });
        }
    }, 10);
});

// 如果用户点击页面其他地方，也移除按钮
document.addEventListener('mousedown', function(e) {
    if (popup_button && e.target !== popup_button) {
        popup_button.remove();
        popup_button = null;
    }
});
```

#### 1.3 `background.js`

这个脚本在后台运行，负责与 Native Messaging Host 通信。

```javascript
// Native Messaging Host 的名字，需要和后面步骤中的注册表键名一致
const NATIVE_HOST_NAME = "com.my_company.my_app";

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === "run_ahk") {
        console.log("Received message from content script. Connecting to native host.");
        
        // 连接到 Native Host
        const port = chrome.runtime.connectNative(NATIVE_HOST_NAME);
        
        // 发送消息
        port.postMessage({ text: message.text });

        // (可选) 监听来自 Native Host 的响应
        port.onMessage.addListener((response) => {
            console.log("Received from native host:", response);
        });

        // (可选) 监听断开连接事件
        port.onDisconnect.addListener(() => {
            if (chrome.runtime.lastError) {
                console.error("Disconnected due to an error:", chrome.runtime.lastError.message);
            } else {
                console.log("Disconnected from native host.");
            }
        });
    }
});
```

---

### 第2步：创建 Native Messaging Host

这部分是在你的本地电脑上设置的，而不是在扩展里。

#### 2.1 目标 AutoHotkey 脚本 (`your-main-script.ahk`)

这是你最终想执行的脚本。它可以接收一个命令行参数（即选中的文本）。

```autohotkey
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
; FileAppend, %SelectedText%`n, C:\path\to\your\log.txt

ExitApp
```

#### 2.2 中间通信脚本 (`native-host-runner.ahk`)

这个脚本是 Chrome 直接调用的，它的任务是**标准地**读取 Chrome 通过 stdin 发来的数据，然后运行你的目标脚本。

**注意**: AHK v1 处理二进制 `stdin` 比较复杂，强烈建议使用 **AutoHotkey v2** 来编写这个中间脚本，因为它处理 `FileObject` 更方便。

**`native-host-runner.ahk` (推荐使用 AHK v2 编写)**

```autohotkey
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
```
**重要**:
*   将 `"C:\path\to\AutoHotkey\AutoHotkey.exe"` 和 `"C:\path\to\your-main-script.ahk"` 替换成你电脑上的真实路径。
*   这个脚本文件必须以 **UTF-8 with BOM** 编码保存，否则 Chrome 可能无法正确启动它。

---

### 第3步：连接 Extension 和 AHK 脚本

这是最后也是最关键的一步，通过注册表和 manifest 文件告诉 Chrome 如何找到你的 `native-host-runner.ahk`。

#### 3.1 创建 Native Host Manifest 文件

创建一个 JSON 文件，例如 `ahk_host_manifest.json`。

```json
{
    "name": "com.my_company.my_app",
    "description": "AHK Host for Chrome Extension",
    "path": "C:\\path\\to\\your\\native-host-runner.ahk",
    "type": "stdio",
    "allowed_origins": [
        "chrome-extension://YOUR_EXTENSION_ID/"
    ]
}
```

**你需要修改**:
*   `"name"`: `com.my_company.my_app`。这个名字必须和 `background.js` 中 `NATIVE_HOST_NAME` 的值完全一致。
*   `"path"`: `native-host-runner.ahk` 的**绝对路径**。注意 JSON 中路径的反斜杠 `\` 需要转义成 `\\`。
*   `"allowed_origins"`: 这是最重要的安全设置。
    1.  先把你的扩展加载到 Chrome 中（进入 `chrome://extensions`，打开开发者模式，点击“加载已解压的扩展程序”，选择 `my-ahk-extension` 文件夹）。
    2.  加载后，Chrome 会为你的扩展分配一个唯一的 ID。
    3.  复制这个 ID，替换上面的 `YOUR_EXTENSION_ID`。

#### 3.2 修改 Windows 注册表

你需要创建一个注册表项，告诉 Chrome 去哪里找你的 manifest 文件。

1.  打开记事本，粘贴以下内容：

    ```reg
    Windows Registry Editor Version 5.00

    [HKEY_CURRENT_USER\Software\Google\Chrome\NativeMessagingHosts\com.my_company.my_app]
    @="C:\\path\\to\\your\\ahk_host_manifest.json"
    ```

2.  **修改**:
    *   `com.my_company.my_app` 必须和 manifest 文件中的 `name` 一致。
    *   `C:\\path\\to\\your\\ahk_host_manifest.json` 替换为你的 `ahk_host_manifest.json` 文件的**绝对路径**。注意这里也需要双反斜杠。

3.  将文件另存为 `install.reg`，然后双击它导入注册表。

---

### 总结和调试

1.  **检查所有路径**：注册表、native manifest、AHK 脚本中的路径都必须是正确的绝对路径，且转义正确。
2.  **检查所有名称/ID**：扩展ID、`NATIVE_HOST_NAME`、`com.my_company.my_app` 这三者必须匹配。
3.  **编码**：`native-host-runner.ahk` 最好是 `UTF-8 with BOM`。
4.  **调试**：
    *   在 `chrome://extensions` 页面，点击你的扩展下方的“服务工作线程”可以打开 `background.js` 的开发者工具，查看 `console.log` 的输出。
    *   按 F12 打开网页的开发者工具，查看 `content.js` 的 `console.log` 输出。
    *   如果 Native Messaging 连接失败，`background.js` 的控制台通常会显示 `Disconnected due to an error` 的详细信息。

完成以上所有步骤后，刷新网页，选择文本，你应该就能看到弹出的按钮了。点击它，你的 `your-main-script.ahk` 就会被执行！

---

## Setup and Installation

After creating the files as described above, you need to perform a few manual setup steps to get the extension working with your local AutoHotkey installation.

**Important Notes Before Starting:**

*   The files `your-main-script.ahk`, `native-host-runner.ahk`, and `ahk_host_manifest.json` have been created in the root of this repository. You will likely need to move them to a permanent location on your computer (e.g., a dedicated scripts folder).
*   **AHK Version for `native-host-runner.ahk`**: The provided `native-host-runner.ahk` script is written with AHK v2 syntax in mind for easier handling of standard input/output. If you are using AHK v1, you might need to adjust this script.
*   **Encoding for `native-host-runner.ahk`**: This script file **must** be saved with **UTF-8 with BOM** encoding. Chrome may fail to start it otherwise. Open it in a text editor like Notepad++, VS Code, or Sublime Text and ensure you save it with this specific encoding.

### 1. Customize File Paths

You need to edit two files to point to the correct locations of your scripts and AutoHotkey executable:

*   **`native-host-runner.ahk`**:
    *   Open `native-host-runner.ahk`.
    *   Locate the line: `Run, "C:\path\to\AutoHotkey\AutoHotkey.exe" "C:\path\to\your-main-script.ahk" "`"" . selectedText . "`""`
    *   Change `"C:\path\to\AutoHotkey\AutoHotkey.exe"` to the actual full path of your `AutoHotkey.exe` (e.g., `"C:\Program Files\AutoHotkey\AutoHotkey.exe"`).
    *   Change `"C:\path\to\your-main-script.ahk"` to the actual full path where you've saved `your-main-script.ahk`.
    *   Remember to use double backslashes `\\` for paths in AHK strings.

*   **`ahk_host_manifest.json`**:
    *   Open `ahk_host_manifest.json`.
    *   Locate the `"path"` key: `"path": "C:\path\to\your\native-host-runner.ahk",`
    *   Change `"C:\path\to\your\native-host-runner.ahk"` to the actual full path where you've saved `native-host-runner.ahk`.
    *   Remember to use double backslashes `\\` for paths in JSON strings.

### 2. Load the Extension in Chrome and Get its ID

1.  Open Chrome and navigate to `chrome://extensions`.
2.  Enable "Developer mode" using the toggle switch (usually in the top right corner).
3.  Click the "Load unpacked" button.
4.  Navigate to and select the `my-ahk-extension` folder (the one containing `manifest.json`).
5.  Once loaded, the "AHK Text Selector" extension will appear in your list of extensions. Find its **ID** (it will be a long string of characters, e.g., `abcdefghijklmnopabcdefghijklmnop`). Copy this ID.

### 3. Update `ahk_host_manifest.json` with Extension ID

1.  Open `ahk_host_manifest.json` again.
2.  Locate the `"allowed_origins"` key:
    ```json
    "allowed_origins": [
        "chrome-extension://YOUR_EXTENSION_ID/"
    ]
    ```
3.  Replace `YOUR_EXTENSION_ID` with the actual ID you copied from `chrome://extensions`. For example:
    ```json
    "allowed_origins": [
        "chrome-extension://abcdefghijklmnopabcdefghijklmnop/"
    ]
    ```
4.  Save the `ahk_host_manifest.json` file.

### 4. Register the Native Messaging Host with Windows

This step tells Chrome where to find your `ahk_host_manifest.json` file.

1.  Open a plain text editor (like Notepad).
2.  Paste the following content into the editor:

    ```reg
    Windows Registry Editor Version 5.00

    [HKEY_CURRENT_USER\Software\Google\Chrome\NativeMessagingHosts\com.my_company.my_app]
    @="C:\path\to\your\ahk_host_manifest.json"
    ```

3.  **Crucially, edit the path**:
    *   Change `C:\path\to\your\ahk_host_manifest.json` to the **actual full path** where you saved your `ahk_host_manifest.json` file.
    *   **Important**: In `.reg` files, you must use **double backslashes (`\\`)** for file paths. For example: `C:\Users\YourName\Documents\AHK_Chrome_Host\ahk_host_manifest.json`.

4.  Save the file with a `.reg` extension (e.g., `install_ahk_host.reg`). Make sure "Save as type" is set to "All Files" in Notepad to avoid saving it as `install_ahk_host.reg.txt`.
5.  Double-click the saved `.reg` file.
6.  You'll be asked for permission to add information to the registry. Click "Yes" and then "OK".

### 5. Test

1.  If the extension was already loaded in Chrome, go to `chrome://extensions` and reload it by clicking the refresh icon for the "AHK Text Selector" extension.
2.  Open any webpage, select some text. The "▶️ Run AHK" button should appear.
3.  Click the button. Your `your-main-script.ahk` should execute (e.g., display a message box with the selected text).

### Troubleshooting Tips

*   **Check all paths meticulously**: Typos in file paths are the most common issue.
*   **Double-check extension ID**: Ensure the ID in `ahk_host_manifest.json` matches exactly.
*   **Encoding**: `native-host-runner.ahk` *must* be UTF-8 with BOM.
*   **Chrome Developer Tools**:
    *   For `background.js` errors: On `chrome://extensions`, click the "service worker" link for your extension to open its DevTools console.
    *   For `content.js` errors: On any webpage where the extension is active, press F12 to open DevTools and check the console.
*   **Native Host Errors**: If `background.js` reports `Disconnected due to an error:`, it often means Chrome couldn't start or communicate with `native-host-runner.ahk`. This could be due to incorrect paths in the registry or `ahk_host_manifest.json`, or issues with the AHK script itself (like encoding).
*   **Restart Chrome**: Sometimes, a full restart of Chrome can help after making registry changes or updating files.
