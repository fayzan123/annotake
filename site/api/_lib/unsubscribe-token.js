// The unsubscribe link's signature: an HMAC-SHA256 of the address's key under UNSUBSCRIBE_SECRET, so nobody can
// unsubscribe an address they weren't sent a link for. Links never expire, well past CASL's 60 days, so every link
// already sent depends on this scheme: the address's key (emailKey: trimmed, lowercased, in NFC), signed, in lowercase
// hex. A link carries the key, and the check keys it again, so a key must be its own key (email.test.js pins that).
// Every link already sent depends on the secret too, so UNSUBSCRIBE_SECRET is set once and never replaced: keep a copy
// (Vercel never shows a Secret again), and carry the same value to a new project or team. If it ever must change, keep
// accepting the old one beside the new, and sign with the new, rather than replace it.
import { createHmac, timingSafeEqual } from 'node:crypto';
import { emailKey } from '../../assets/email.js';

/** The hex HMAC-SHA256 of emailKey(email): any capitals, padding, or encoding of an accent signs the same. */
export function signEmail(email, secret) {
  // A link signed with an empty key would be anyone's to make. The messages never hold the address.
  if (typeof secret !== 'string' || secret === '') throw new TypeError('signEmail needs a secret');
  if (typeof email !== 'string') throw new TypeError('signEmail needs an address');
  return mac(email, secret).toString('hex');
}

/** True only for the signature signEmail gives, in the lowercase a link carries. False for anything malformed. */
export function verifyEmail(email, sig, secret) {
  if (typeof email !== 'string' || typeof secret !== 'string' || secret === '') return false;
  // timingSafeEqual throws on lengths that differ, and Buffer.from(…, 'hex') stops at the first character that isn't
  // hex, so only exactly 64 hex characters reach it.
  if (typeof sig !== 'string' || !/^[0-9a-f]{64}$/.test(sig)) return false;
  return timingSafeEqual(Buffer.from(sig, 'hex'), mac(email, secret));
}

/** The link the welcome email carries: absolute, since an email has no page to be relative to. */
export function unsubscribeUrl(email, secret) {
  return `https://annotake.app/api/unsubscribe?e=${encodeURIComponent(emailKey(email))}&s=${signEmail(email, secret)}`;
}

function mac(email, secret) {
  return createHmac('sha256', secret).update(emailKey(email)).digest();
}
