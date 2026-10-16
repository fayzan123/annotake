// The consent wording, the one source of truth: the app's email step shows it (EmailConsentTests checks the Swift copy
// against this file), and each contact's consent_wording names the version the person read. A wording change adds a new
// version and moves `current`; a shipped version is never edited.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import consent from '../../api/_lib/consent.json' with { type: 'json' };

/** What every version shows. A version that asks for consent adds the box. */
const STRINGS = ['footer', 'notice', 'title'];

test('current names a version that exists', () => {
  assert.deepEqual(Object.keys(consent).sort(), ['current', 'versions']);
  assert.equal(consent.current, 'consent-2026-10-15');
  assert.ok(Object.hasOwn(consent.versions, consent.current));
});

test('every version has the three strings, maybe the box, and nothing else', () => {
  assert.ok(Object.keys(consent.versions).length > 0);
  for (const [id, version] of Object.entries(consent.versions)) {
    const names = Object.keys(version).sort();
    assert.deepEqual(names.filter(name => name !== 'box'), STRINGS, id);
    for (const name of names) {
      assert.equal(typeof version[name], 'string', `${id} ${name}`);
      assert.ok(version[name].length > 0, `${id} ${name}`);
      assert.equal(version[name], version[name].trim(), `${id} ${name}`);
    }
  }
});

test('a version with the box has one {address} in its footer: CASL wants the mailing address beside a consent request', () => {
  for (const [id, { box, footer }] of Object.entries(consent.versions)) {
    const addresses = footer.split('{address}').length - 1;
    assert.ok(addresses <= 1, id);
    if (box !== undefined) assert.equal(addresses, 1, id);
  }
});

test('apostrophes are ’, as everywhere on the site', () => {
  for (const [id, version] of Object.entries(consent.versions)) {
    for (const [name, text] of Object.entries(version)) assert.doesNotMatch(text, /'/, `${id} ${name}`);
  }
  assert.ok(consent.versions['consent-2026-10-15'].notice.startsWith('We’ll'));
});

test('consent-2026-10-15 says what the plan says, word for word', () => {
  // No box and no mailing address: until the list has an address, the step asks for no consent (design §13, Checkpoint
  // 5). Changed before it shipped; the box comes back under a new version, with the address.
  assert.deepEqual(consent.versions['consent-2026-10-15'], {
    title: 'Stay in the loop',
    notice: 'We’ll email you about security fixes and important changes to Annotake. Every email has an unsubscribe link.',
    footer: 'From Fayzan Malik · annotake.app · Privacy policy',
  });
});
