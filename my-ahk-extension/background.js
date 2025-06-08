// Native Messaging Host 的名字，需要和后面步骤中的注册表键名一致
const NATIVE_HOST_NAME = "com.my_company.my_app";

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === "run_ahk") {
        console.log("Received message from content script. Attempting to retrieve script path.");
        chrome.storage.sync.get({
            ahkScriptPath: '' // Default to empty string if not set
        }, function(items) {
            if (chrome.runtime.lastError) {
                console.error("Error retrieving script path:", chrome.runtime.lastError.message);
                // Optionally, send a response to the content script indicating failure
                // sendResponse({status: "error", message: "Failed to retrieve script path"});
                return;
            }

            const userScriptPath = items.ahkScriptPath;
            console.log("Retrieved script path:", userScriptPath, "for text:", message.text);

            if (!userScriptPath) {
                console.warn("AHK script path is not set in options. Native host might not know which script to run.");
                // Optionally, inform the user through the content script or a notification
                // sendResponse({status: "error", message: "AHK script path not configured."});
                // Or, decide if you want to proceed with a default/empty path or not.
                // For this example, we'll proceed, and the native host runner will need to handle it.
            }

            console.log("Now connecting to native host.");
            const port = chrome.runtime.connectNative(NATIVE_HOST_NAME);

            // Send message including the script path
            port.postMessage({ text: message.text, scriptPath: userScriptPath });

            port.onMessage.addListener((response) => {
                console.log("Received from native host:", response);
                // You could send a response back to the content script if needed
                // sendResponse({status: "success", response: response});
            });

            port.onDisconnect.addListener(() => {
                if (chrome.runtime.lastError) {
                    console.error("Disconnected due to an error:", chrome.runtime.lastError.message);
                    // sendResponse({status: "error", message: "Disconnected from native host: " + chrome.runtime.lastError.message});
                } else {
                    console.log("Disconnected from native host.");
                    // sendResponse({status: "info", message: "Disconnected from native host."});
                }
            });
        });
        // Return true to indicate you wish to send a response asynchronously.
        // This is important because chrome.storage.sync.get is asynchronous.
        return true;
    }
    // If the message type is not "run_ahk", we don't need to return true
    // as we are not doing anything asynchronous that would require sendResponse later.
});
