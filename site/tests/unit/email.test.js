// One email check, shared by the page and the function: loose enough for every real address, strict enough to stop
// header injection and obvious typos.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cleanEmail, emailKey, isPlausibleEmail } from '../../assets/email.js';

test('real-world addresses are accepted: plus addressing, capitals, spaces around, and non-ASCII', () => {
  for (const address of [
    'sam@example.com', '  Sam@Example.COM ', 'sam+annotake@gmail.com', 'jürgen@müller.de', '用户@例子.广告', 'a@b.co',
  ]) {
    assert.equal(isPlausibleEmail(address), true, address);
  }
});

test('what isn’t an address is rejected', () => {
  for (const address of [
    '', 'sam', 'sam@', '@example.com',
    'sam@example', 'sam@@example.com', 'sam@exa mple.com',
    'sam@example.com\r\nBcc: x@y.z',
    'sam@.example.com', 'sam@example.', 'sam@example..com',
    `${'a'.repeat(64)}@${'b'.repeat(186)}.com`,
    `${'a'.repeat(65)}@example.com`,
    'sam@exam\u0000ple.com', 'sam@example.com\u007F', 'sam @example.com',
    null, undefined,
  ]) {
    assert.equal(isPlausibleEmail(address), false, JSON.stringify(address));
  }
});

test('the length limits sit exactly at 254 characters and a 64-character local part', () => {
  const at254 = `${'a'.repeat(64)}@${'b'.repeat(185)}.com`;
  assert.equal(at254.length, 254);
  assert.equal(isPlausibleEmail(at254), true);
  assert.equal(isPlausibleEmail(`${'a'.repeat(64)}@${'b'.repeat(186)}.com`), false, '255 characters');
  assert.equal(isPlausibleEmail(`${'a'.repeat(64)}@example.com`), true, 'a 64-character local part');
});

test('cleanEmail trims, and composes accents into one form', () => {
  assert.equal(cleanEmail('  sam@example.com\n'), 'sam@example.com');
  assert.equal(cleanEmail('jürgen@müller.de'), 'jürgen@müller.de');
  assert.equal(cleanEmail(null), '');
  assert.equal(cleanEmail(undefined), '');
});

test('emailKey makes one key per address, whatever the capitals or the accents’ encoding', () => {
  assert.equal(emailKey('  Sam@Example.COM '), 'sam@example.com');
  assert.equal(emailKey('JÜRGEN@MÜLLER.DE'), emailKey('jürgen@müller.de'));
});

test('a key’s key is itself, even where lowercasing lets an accent compose', () => {
  // J and a combining caron (U+030C) have no composed capital, but ǰ (U+01F0) is one character.
  assert.equal(emailKey('J\u{30C}ohn@example.com'), '\u{1F0}ohn@example.com');
  for (const address of [
    '  Sam@Example.COM ', 'jürgen@müller.de', 'JÜRGEN@MÜLLER.DE', '用户@例子.广告',
    // Capitals with a mark that composes only once they're small: ǰ, ẖ, ẗ, ẘ, and ẙ.
    'J\u{30C}ohn@example.com', 'H\u{331}ana@example.com', 'T\u{308}om@example.com', 'W\u{30A}ill@example.com',
    'Y\u{30A}ara@example.com',
    // İ lowercases to i and a dot above, which then belongs after a mark below.
    '\u{130}\u{331}sa@example.com',
  ]) {
    const key = emailKey(address);
    assert.equal(emailKey(key), key, JSON.stringify(address));
    assert.equal(key, key.normalize('NFC'), `${JSON.stringify(address)} keys to NFC`);
  }
});
