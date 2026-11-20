parent.postMessage('extension-resource', '*');
if (location.hash === '#bridge' && globalThis.chrome?.runtime) {
  chrome.runtime.onMessage.addListener((message, _, reply) => {
    if (message.kind === 'resource-reply') reply('extension-page-reply');
  });
  chrome.runtime.sendMessage({kind: 'resource-sender'}).then(
    result => parent.postMessage({resourceBridge: result}, '*'),
    error => parent.postMessage({resourceBridge: {error: String(error)}}, '*'));
}
