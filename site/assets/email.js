// The email check, shared by the page (linkform.js) and the functions in api/. It accepts every real address,
// plus addressing and non-ASCII included, and rejects what can't be one, line breaks above all, which could inject
// headers. It never decides deliverability; the email does that.

/** The address as the visitor meant it: trimmed, with accents in one composed form. */
export function cleanEmail(input) {
  return String(input ?? '').trim().normalize('NFC');
}

export function isPlausibleEmail(input) {
  const email = cleanEmail(input);
  if (email.length < 3 || email.length > 254) return false;
  if (/[\s\u0000-\u001F\u007F]/u.test(email)) return false;
  const parts = email.split('@');
  if (parts.length !== 2) return false;
  const [local, domain] = parts;
  if (local.length < 1 || local.length > 64) return false;
  return domain.includes('.') && !domain.startsWith('.') && !domain.endsWith('.') && !domain.includes('..');
}

/**
 * One key per address, whatever the capitals, for "one email per address per day" and the email list's contacts. It's
 * composed again after lowercasing: J with a combining caron has no composed capital, but lowercased it composes to ǰ.
 * So a key's key is itself, which the unsubscribe link's check relies on: the link carries the key, and the check keys
 * it again.
 */
export function emailKey(input) {
  return cleanEmail(input).toLowerCase().normalize('NFC');
}
