let listening = false;
export function readHash() {
  if (!listening) {
    window.addEventListener('hashchange', () => {
      if (/^#(?:v1|rep1):/.test(window.location.hash)) window.location.reload();
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
  anchor.download = content.includes('loophole.reputation.v1') ? 'loophole-reputation-v1.json' : 'loophole-replay-v1.json';
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
