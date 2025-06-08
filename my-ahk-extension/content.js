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
