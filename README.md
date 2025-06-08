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
├── icons/  <- This was removed in a previous step, but the general description here is fine.
│   ├── icon16.png
│   ├── icon48.png
│   └── icon128.png
├── content.js
└── background.js
```

#### 1.1 `manifest.json`

这是扩展的配置文件，告诉 Chrome 它的功能和所需权限。
(The example manifest.json content shown here is the older version, but the descriptive text is still relevant. The actual file in the repo is updated.)
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
*   (Later an `options_ui` key was added, which is also important)

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
            // ... (styling and positioning) ...

            document.body.appendChild(popup_button);

            // 按钮点击事件
            popup_button.addEventListener('click', () => {
                console.log("Button clicked, sending text:", selectedText);
                chrome.runtime.sendMessage({
                    type: "run_ahk",
                    text: selectedText
                });
                popup_button.remove();
                popup_button = null;
            });
        }
    }, 10);
});

// ... (mousedown listener) ...
```

#### 1.3 `background.js`

这个脚本在后台运行，负责与 Native Messaging Host 通信。
(The content described here is the older version. The actual file in the repo is updated to include script path retrieval from storage.)
```javascript
// Native Messaging Host 的名字，需要和后面步骤中的注册表键名一致
const NATIVE_HOST_NAME = "com.my_company.my_app";

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === "run_ahk") {
        // ... (logic to get scriptPath from chrome.storage.sync was added here) ...
        const port = chrome.runtime.connectNative(NATIVE_HOST_NAME);
        port.postMessage({ text: message.text /*, scriptPath: userScriptPath */ });
        // ... (port listeners) ...
        // return true; // Was added for async operations
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
SelectedText := A_Args[1]
MsgBox, The text selected in Chrome is:`n`n%SelectedText%
ExitApp
```

#### 2.2 中间通信脚本 (`native-host-runner.ahk`)

(The content described here is the older version. The actual file in the repo is updated to parse scriptPath from the message and use it.)
```autohotkey
; native-host-runner.ahk (MUST be saved with UTF-8 with BOM encoding)
#SingleInstance Force
stdin := FileOpen("*", "r `n")
stdout := FileOpen("*", "w `n")
Loop {
    try {
        ; ... (read length and message) ...
        ; pattern := '"text"\s*:\s*"(.*?)"' (This was updated to get text and scriptPath)
        ; if RegExMatch(json_message, pattern, &match) {
            ; selectedText := match[1]
            ; userScriptPath := ... (logic to get scriptPath and fallback was added)
            ; ahkExePath := "C:\Program Files\AutoHotkey\AutoHotkey.exe" ; !!! USER MUST MODIFY THIS !!!
            ; Run, ahkExePath userScriptPath, selectedText (Conceptual, actual Run command is more detailed)
            ; ... (send response) ...
        ; }
    } catch as e {
        break
    }
}
ExitApp
```
**重要**:
*   The path to `AutoHotkey.exe` inside `native-host-runner.ahk` needs to be set by the user.
*   `native-host-runner.ahk` must be saved as UTF-8 with BOM.

---

### 第3步：连接 Extension 和 AHK 脚本

(Instructions for `ahk_host_manifest.json` and registry setup remain largely the same, but path details are important.)

#### 3.1 创建 Native Host Manifest 文件 (`ahk_host_manifest.json`)
...
#### 3.2 修改 Windows 注册表
...

---

### 总结和调试
...

---

## Setup and Installation

After creating the files as described above, you need to perform a few manual setup steps to get the extension working with your local AutoHotkey installation.

**Important Notes Before Starting:**

*   The files `your-main-script.ahk`, `native-host-runner.ahk`, and `ahk_host_manifest.json` have been created in the root of this repository. You will likely need to move them to a permanent location on your computer (e.g., a dedicated scripts folder).
*   **AHK Version for `native-host-runner.ahk`**: The provided `native-host-runner.ahk` script is written with AHK v2 syntax in mind for easier handling of standard input/output. If you are using AHK v1, you might need to adjust this script.
*   **Encoding for `native-host-runner.ahk`**: This script file **must** be saved with **UTF-8 with BOM** encoding. Chrome may fail to start it otherwise. Open it in a text editor like Notepad++, VS Code, or Sublime Text and ensure you save it with this specific encoding.

---

### Configuring the Path to Your Main AHK Script (via Extension Options)

This extension now allows you to set the path to your main `.ahk` script (e.g., `your-main-script.ahk`) through its options page.

1.  **Accessing the Options Page:**
    *   Go to `chrome://extensions`.
    *   Find the "AHK Text Selector" extension.
    *   Click on "Details".
    *   Scroll down and click on "Extension options".
    *   Alternatively, if the extension icon is pinned to your toolbar, you might be able to right-click it and find an "Options" menu.

2.  **Setting the Script Path:**
    *   On the options page, you will see an input field labeled "AHK Script Path:".
    *   Enter the **full absolute path** to your main `.ahk` script that you want to execute. For example: `C:\Users\YourName\Documents\MyAHKScripts\MyMainScript.ahk`.
    *   Click the "Save" button. A confirmation message "Options saved." should appear briefly.

3.  **Fallback Behavior:**
    *   If you do not set a path in the options, or if the saved path is empty, the extension will attempt to run a script named `your-main-script.ahk` located in the **same directory** as the `native-host-runner.ahk` script.

### Manual Configuration Still Required for `native-host-runner.ahk`

You **still need to manually edit** the `native-host-runner.ahk` script for one critical setting:

*   **Path to `AutoHotkey.exe`**:
    *   Open `native-host-runner.ahk` (wherever you have placed it).
    *   Locate the line: `ahkExePath := "C:\Program Files\AutoHotkey\AutoHotkey.exe" ; !!! MODIFY THIS LINE !!!` (or similar).
    *   **Change this path** to the actual full path of your `AutoHotkey.exe` installation. This path tells the runner script where to find the AutoHotkey interpreter.

### Other Path Customizations

*   **`ahk_host_manifest.json`**:
    *   Open `ahk_host_manifest.json`.
    *   Locate the `"path"` key: `"path": "C:\path\to\your\native-host-runner.ahk",`
    *   Change `"C:\path\to\your\native-host-runner.ahk"` to the actual full path where you've saved `native-host-runner.ahk`.
    *   Remember to use double backslashes `\\` for paths in JSON strings (e.g., `C:\\Users\\YourName\\Scripts\\native-host-runner.ahk`).

### 2. Load the Extension in Chrome and Get its ID
(This numbering should be adjusted or this section retitled, as it's not "Customize File Paths" anymore)

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
    *   **Important**: In `.reg` files, you must use **double backslashes (`\\`)** for file paths. For example: `C:\\Users\\YourName\\Documents\\AHK_Chrome_Host\\ahk_host_manifest.json`.

4.  Save the file with a `.reg` extension (e.g., `install_ahk_host.reg`). Make sure "Save as type" is set to "All Files" in Notepad to avoid saving it as `install_ahk_host.reg.txt`.
5.  Double-click the saved `.reg` file.
6.  You'll be asked for permission to add information to the registry. Click "Yes" and then "OK".

### 5. Test

1.  If the extension was already loaded in Chrome, go to `chrome://extensions` and reload it by clicking the refresh icon for the "AHK Text Selector" extension. Make sure to also reload it if you've changed its options.
2.  Open any webpage, select some text. The "▶️ Run AHK" button should appear.
3.  Click the button. Your configured `.ahk` script should execute.

### Troubleshooting Tips

*   **Check all paths meticulously**: Typos in file paths (in extension options, `native-host-runner.ahk`, `ahk_host_manifest.json`, and the registry) are the most common issue.
*   **Double-check extension ID**: Ensure the ID in `ahk_host_manifest.json` matches exactly.
*   **Encoding**: `native-host-runner.ahk` *must* be UTF-8 with BOM.
*   **Chrome Developer Tools**:
    *   For `background.js` errors: On `chrome://extensions`, click the "service worker" link for your extension to open its DevTools console. Check for errors related to storage or native messaging.
    *   For `content.js` errors: On any webpage where the extension is active, press F12 to open DevTools and check the console.
*   **Native Host Errors**: If `background.js` reports `Disconnected due to an error:`, it often means Chrome couldn't start or communicate with `native-host-runner.ahk`. This could be due to incorrect paths in the registry or `ahk_host_manifest.json`, an incorrect `ahkExePath` in `native-host-runner.ahk`, or issues with the AHK script itself (like encoding or runtime errors).
*   **Restart Chrome**: Sometimes, a full restart of Chrome can help after making registry changes or updating files.
*   **Check AHK script directly**: Try running your target `.ahk` script and `native-host-runner.ahk` (with some dummy input if possible) directly to see if they have any errors.
