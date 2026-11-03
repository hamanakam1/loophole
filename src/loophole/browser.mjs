let listening = false;
export function readHash() {
  if (!listening) {
    window.addEventListener('hashchange', () => {
      if (window.location.hash.startsWith('#v1:')) window.location.reload();
    });
    listening = true;
  }
  return window.location.hash.slice(1);
}
export function writeHash(fragment) {
  window.history.replaceState(null, '', fragment);
}
export function downloadReceipt(content) {
  const url = URL.createObjectURL(new Blob([content], { type: 'application/json' }));
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = 'loophole-replay-v1.json';
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
