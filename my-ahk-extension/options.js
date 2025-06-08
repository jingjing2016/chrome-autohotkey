// Saves options to chrome.storage
function save_options() {
  const scriptPath = document.getElementById('scriptPath').value;
  chrome.storage.sync.set({
    ahkScriptPath: scriptPath
  }, function() {
    // Update status to let user know options were saved.
    const status = document.getElementById('status');
    status.textContent = 'Options saved.';
    setTimeout(function() {
      status.textContent = '';
    }, 1500);
  });
}

// Restores input box state using the preferences
// stored in chrome.storage.
function restore_options() {
  chrome.storage.sync.get({
    ahkScriptPath: '' // Default to empty string if not set
  }, function(items) {
    document.getElementById('scriptPath').value = items.ahkScriptPath;
  });
}

document.addEventListener('DOMContentLoaded', restore_options);
document.getElementById('save').addEventListener('click', save_options);
