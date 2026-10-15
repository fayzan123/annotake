// The unsubscribe link's signature. Links never expire, so every link already sent depends on the scheme staying put:
// a known answer pins it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { emailKey } from '../../assets/email.js';
import { signEmail, unsubscribeUrl, verifyEmail } from '../../api/_lib/unsubscribe-token.js';

const SECRET = 'test-secret';
/** HMAC-SHA256 of "sam@example.com" under "test-secret", from `openssl dgst -sha256 -hmac test-secret`. */
const KNOWN = '29cef509b63b6941890ddfe5f289eb22c852d39501025ff8c6e7a6c0a9ffc58f';

test('signing is stable: a known answer, every time, and another for another address or secret', () => {
  assert.equal(signEmail('sam@example.com', SECRET), KNOWN);
  assert.equal(signEmail('sam@example.com', SECRET), signEmail('sam@example.com', SECRET));
  assert.equal(verifyEmail('sam@example.com', KNOWN, SECRET), true);
  assert.notEqual(signEmail('sam@example.org', SECRET), KNOWN);
  assert.notEqual(signEmail('sam@example.com', 'another-secret'), KNOWN);
});

test('Sam@Example.COM and " sam@example.com " sign the same, and so do both encodings of an accent', () => {
  for (const email of ['Sam@Example.COM', ' sam@example.com ', '  Sam@Example.COM ', 'SAM@EXAMPLE.COM\n']) {
    assert.equal(signEmail(email, SECRET), KNOWN, JSON.stringify(email));
    assert.equal(verifyEmail(email, KNOWN, SECRET), true, JSON.stringify(email));
  }
  const composed = 'jürgen@müller.de';
  const decomposed = 'jürgen@müller.de';
  assert.notEqual(composed, decomposed);
  assert.equal(signEmail(decomposed, SECRET), signEmail(composed, SECRET));
  assert.equal(signEmail('JÜRGEN@MÜLLER.DE', SECRET), signEmail(composed, SECRET));
});

test('verifyEmail rejects a wrong signature, the wrong length, non-hex, an empty secret, and undefined', () => {
  assert.match(KNOWN, /[a-f]/, 'the known answer has letters, so its uppercase form differs');
  const underEmptyKey = createHmac('sha256', '').update('sam@example.com').digest('hex');
  for (const [email, sig, secret, why] of [
    ['sam@example.com', signEmail('sam@example.org', SECRET), SECRET, 'another address’s signature'],
    ['sam@example.com', signEmail('sam@example.com', 'another-secret'), SECRET, 'another secret’s signature'],
    ['sam@example.com', KNOWN.slice(0, 63), SECRET, '63 characters'],
    ['sam@example.com', `${KNOWN}0`, SECRET, '65 characters'],
    ['sam@example.com', KNOWN.slice(0, 32), SECRET, '32 characters'],
    ['sam@example.com', KNOWN.repeat(2), SECRET, '128 characters'],
    ['sam@example.com', '', SECRET, 'an empty signature'],
    ['sam@example.com', 'z'.repeat(64), SECRET, 'not hex'],
    ['sam@example.com', `${KNOWN.slice(0, 62)}zz`, SECRET, 'hex, then not'],
    ['sam@example.com', `${KNOWN.slice(0, 63)}\n`, SECRET, 'a line break'],
    ['sam@example.com', ` ${KNOWN.slice(1)}`, SECRET, 'a space'],
    ['sam@example.com', KNOWN.toUpperCase(), SECRET, 'uppercase: only the lowercase form a link carries'],
    ['sam@example.com', underEmptyKey, '', 'an empty secret'],
    ['sam@example.com', KNOWN, undefined, 'no secret'],
    ['sam@example.com', KNOWN, null, 'a null secret'],
    [undefined, KNOWN, SECRET, 'no address'],
    ['sam@example.com', undefined, SECRET, 'no signature'],
    [['sam@example.com'], KNOWN, SECRET, 'an address that isn’t text'],
    ['sam@example.com', [KNOWN], SECRET, 'a signature that isn’t text'],
    ['sam@example.com', Buffer.from(KNOWN, 'hex'), SECRET, 'the signature’s bytes'],
  ]) {
    assert.equal(verifyEmail(email, sig, secret), false, why);
  }
});

test('signing without a secret throws: a link signed with an empty key would be anyone’s to make', () => {
  for (const secret of ['', undefined, null, 42]) {
    assert.throws(() => signEmail('sam@example.com', secret), TypeError, String(secret));
    assert.throws(() => unsubscribeUrl('sam@example.com', secret), TypeError, String(secret));
  }
  assert.throws(() => signEmail(undefined, SECRET), TypeError, 'no address');
});

test('unsubscribeUrl round-trips through URL to the same e and s', () => {
  assert.equal(
    unsubscribeUrl('  Sam@Example.COM ', SECRET),
    `https://annotake.app/api/unsubscribe?e=sam%40example.com&s=${KNOWN}`,
  );
  for (const email of [
    'sam@example.com', '  Sam@Example.COM ', 'sam+annotake@gmail.com', 'jürgen@müller.de', 'o’brien&co=x@example.com',
    "o'brien@example.com", '用户@例子.广告',
    // Capitals whose accent composes only once they're small, so a key that wasn't its own key would fail its check.
    'J\u{30C}ohn@example.com', '\u{130}\u{331}sa@example.com',
  ]) {
    const url = new URL(unsubscribeUrl(email, SECRET));
    assert.equal(`${url.origin}${url.pathname}`, 'https://annotake.app/api/unsubscribe', email);
    assert.deepEqual([...url.searchParams.keys()], ['e', 's'], email);
    assert.equal(url.searchParams.get('e'), emailKey(email), email);
    assert.equal(url.searchParams.get('s'), signEmail(email, SECRET), email);
    assert.equal(verifyEmail(url.searchParams.get('e'), url.searchParams.get('s'), SECRET), true, email);
  }
});
