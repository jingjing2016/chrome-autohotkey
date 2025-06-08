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
