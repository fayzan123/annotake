// The hero's "Watch the 20-second demo" opens the video in a dialog over the page and plays it with sound, which the
// click allows. Without scripts, or with a modifier held to open it elsewhere, the link goes to /demo, which plays the
// same video. Nothing loads until the first click, so the video never weighs on the page's first load.
import { element } from './acme.js';

export const VIDEO = '/assets/video/demo.v1.mp4';
export const POSTER = '/assets/img/demo-poster.v1.jpg';

const CLOSE = '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M5 5l10 10M15 5 5 15"/></svg>';

function buildDialog() {
  const dialog = element('dialog', 'demo-dialog');
  dialog.setAttribute('aria-label', 'Annotake demo');
  const close = element('button', 'demo-close');
  close.type = 'button';
  close.setAttribute('aria-label', 'Close the demo');
  close.innerHTML = CLOSE;
  const video = element('video', 'demo-video');
  Object.assign(video, { src: VIDEO, poster: POSTER, controls: true, playsInline: true, preload: 'auto' });
  video.width = 1920;
  video.height = 1080;
  dialog.append(close, video);
  close.addEventListener('click', () => dialog.close());
  // A click on the backdrop lands on the dialog itself; the video and the button cover everything inside it.
  dialog.addEventListener('click', event => {
    if (event.target === dialog) dialog.close();
  });
  dialog.addEventListener('close', () => video.pause());
  document.body.append(dialog);
  return { dialog, video };
}

export function initDemo(link) {
  if (typeof HTMLDialogElement !== 'function') return;
  let built = null;
  link.addEventListener('click', event => {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    built ??= buildDialog();
    built.dialog.showModal();
    built.video.currentTime = 0;
    // A browser that still refuses to start it leaves the controls to the visitor.
    built.video.play().catch(() => {});
  });
}
