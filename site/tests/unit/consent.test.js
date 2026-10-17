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
  assert.equal(consent.current, 'consent-2026-10-17');
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
  assert.ok(consent.versions[consent.current].notice.startsWith('We’ll'));
});

test('consent-2026-10-15 says what the plan says, word for word', () => {
  // No box and no mailing address: until the list has an address, the step asks for no consent (design §13, Checkpoint
  // 5). Changed before it shipped; the box comes back under a new version, with the address. It reached Production on
  // 2026-10-17, so it stays as it was: a contact may name it.
  assert.deepEqual(consent.versions['consent-2026-10-15'], {
    title: 'Stay in the loop',
    notice: 'We’ll email you about security fixes and important changes to Annotake. Every email has an unsubscribe link.',
    footer: 'From Fayzan Malik · annotake.app · Privacy policy',
  });
});

test('consent-2026-10-17 is consent-2026-10-15 without the unsubscribe line, word for word', () => {
  // The step asks for no consent, and /privacy, linked from its footer, says how to unsubscribe. The box's version brings
  // the line back: CASL wants a consent request to say that consent can be withdrawn (Checkpoint 5's parked list).
  assert.deepEqual(consent.versions['consent-2026-10-17'], {
    title: 'Stay in the loop',
    notice: 'We’ll email you about security fixes and important changes to Annotake.',
    footer: 'From Fayzan Malik · annotake.app · Privacy policy',
  });
});
