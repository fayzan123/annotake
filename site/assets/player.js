// Runs an animation's loop only while its element is on screen. The loop awaits `player.wait(ms)` between steps; while
// the element is out of view, each wait holds at its end until the element is back, so a hidden loop costs nothing and
// picks up where it was. The element's data-visible attribute says which, so CSS can pause its own animations too.

/** How much of `node` is inside the viewport, from 0 to 1. */
function shareInView(node) {
  const rect = node.getBoundingClientRect();
  if (rect.height <= 0) return 0;
  const top = Math.max(rect.top, 0);
  const bottom = Math.min(rect.bottom, window.innerHeight);
  return Math.max(0, bottom - top) / rect.height;
}

const STOPPED = Symbol('stopped');

export function createPlayer(root, { threshold = 0.35, onChange = () => {} } = {}) {
  const timers = new Set();
  let waiting = [];
  let stopped = false;
  // Checked at once as well, so a loop on screen at load starts without waiting for the observer's first report.
  let visible = shareInView(root) >= threshold;
  root.dataset.visible = String(visible);

  const observer = new IntersectionObserver(([entry]) => {
    const now = entry.isIntersecting && entry.intersectionRatio >= threshold - 0.001;
    if (now === visible) return;
    visible = now;
    root.dataset.visible = String(visible);
    onChange(visible);
    if (visible) for (const resolve of waiting.splice(0)) resolve();
  }, { threshold: [0, threshold] });
  observer.observe(root);

  function check() {
    if (stopped) throw STOPPED;
  }

  async function whenVisible() {
    check();
    if (!visible) await new Promise(resolve => waiting.push(resolve));
    check();
  }

  async function wait(ms) {
    check();
    await new Promise(resolve => {
      const id = setTimeout(() => {
        timers.delete(id);
        resolve();
      }, ms);
      timers.add(id);
    });
    await whenVisible();
  }

  return {
    get visible() { return visible; },
    whenVisible,
    wait,
    /** Starts `loop`, an async function, and keeps its errors other than stopping. */
    run(loop) {
      loop().catch(error => {
        if (error !== STOPPED) throw error;
      });
    },
    stop() {
      stopped = true;
      observer.disconnect();
      for (const id of timers) clearTimeout(id);
      timers.clear();
      for (const resolve of waiting.splice(0)) resolve();
    },
  };
}
