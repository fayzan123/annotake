// "Email me the link", for phones and computers that aren't Macs. The form works without scripts too: it posts to
// /api/link, which answers with a small page. With scripts it sends one JSON request and always ends in one of two
// states: sent, or a fallback that shows the link to copy or share. It never leaves a spinner.
import { cleanEmail, isPlausibleEmail } from './email.js';

export const LINK = 'https://annotake.app/download';

export function initLinkForm(form, {
  fetch = window.fetch,
  now = () => performance.now(),
  share = navigator.share?.bind(navigator),
  clipboard = navigator.clipboard,
  timeoutMs = 12000,
} = {}) {
  const box = form.parentElement;
  const field = form.querySelector('input[name="email"]');
  const trap = form.querySelector('input[name="website"]');
  const button = form.querySelector('button[type="submit"]');
  const error = form.querySelector('.linkform-error');
  const sent = box.querySelector('.linkform-sent');
  const fallback = box.querySelector('.linkform-fallback');
  const copy = fallback.querySelector('.linkform-copy');
  const shareButton = fallback.querySelector('.linkform-share');
  const loadedAt = now();
  let busy = false;

  /** Shows the form, the sent state, or the fallback, and moves focus into whichever replaced the form. */
  function show(state) {
    form.hidden = state !== 'form';
    sent.hidden = state !== 'sent';
    fallback.hidden = state !== 'fallback';
    if (state === 'sent') sent.focus();
    if (state === 'fallback') fallback.focus();
  }

  function showError() {
    error.hidden = false;
    field.setAttribute('aria-invalid', 'true');
    field.focus();
  }

  function clearError() {
    error.hidden = true;
    field.removeAttribute('aria-invalid');
  }

  function setBusy(on) {
    busy = on;
    button.disabled = on;
    button.textContent = on ? 'Sending…' : 'Send link';
  }

  async function send(email) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch('/api/link', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, website: trap.value, t: Math.round(now() - loadedAt) }),
        signal: controller.signal,
      });
      return response.status;
    } catch {
      return 0;  // the network, or the timeout
    } finally {
      clearTimeout(timer);
    }
  }

  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (busy) return;
    const email = cleanEmail(field.value);
    if (!isPlausibleEmail(email)) return showError();
    clearError();
    setBusy(true);
    const status = await send(email);
    setBusy(false);
    if (status === 200) {
      sent.querySelector('.linkform-sent-to').textContent = email;
      show('sent');
    } else if (status === 400) {
      showError();
    } else {
      show('fallback');
    }
  });

  sent.querySelector('.linkform-retry').addEventListener('click', () => {
    show('form');
    field.focus();
  });

  copy.addEventListener('click', async () => {
    try {
      await clipboard.writeText(LINK);
      copy.textContent = 'Copied';
    } catch {
      // No clipboard here: select the link, so it can be copied by hand.
      getSelection().selectAllChildren(fallback.querySelector('.linkform-link'));
    }
  });

  if (typeof share === 'function') {
    shareButton.hidden = false;
    shareButton.addEventListener('click', () => {
      share({ title: 'Annotake for Mac', url: LINK }).catch(() => {});  // a cancelled share sheet rejects
    });
  }

  // Opening the details focuses the field at once, inside the tap, so a phone shows its keyboard.
  const details = form.closest('details');
  details?.querySelector('summary').addEventListener('click', event => {
    if (details.open) return;
    event.preventDefault();
    details.open = true;
    if (!form.hidden) field.focus();
  });
}
