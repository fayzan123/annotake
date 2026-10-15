// The consent wording, the one source of truth: the app's email step shows it (EmailConsentTests checks the Swift copy
// against this file), and each contact's consent_wording names the version the person read. A wording change adds a new
// version and moves `current`; a shipped version is never edited.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import consent from '../../api/_lib/consent.json' with { type: 'json' };

const STRINGS = ['box', 'footer', 'notice', 'title'];

test('current names a version that exists', () => {
  assert.deepEqual(Object.keys(consent).sort(), ['current', 'versions']);
  assert.equal(consent.current, 'consent-2026-10-15');
  assert.ok(Object.hasOwn(consent.versions, consent.current));
});

test('every version has the four strings, and nothing else', () => {
  assert.ok(Object.keys(consent.versions).length > 0);
  for (const [id, version] of Object.entries(consent.versions)) {
    assert.deepEqual(Object.keys(version).sort(), STRINGS, id);
    for (const name of STRINGS) {
      assert.equal(typeof version[name], 'string', `${id} ${name}`);
      assert.ok(version[name].length > 0, `${id} ${name}`);
      assert.equal(version[name], version[name].trim(), `${id} ${name}`);
    }
  }
});

test('every footer has one {address}, for the mailing address', () => {
  for (const [id, { footer }] of Object.entries(consent.versions)) {
    assert.equal(footer.split('{address}').length, 2, id);
  }
});

test('apostrophes are ’, as everywhere on the site', () => {
  for (const [id, version] of Object.entries(consent.versions)) {
    for (const name of STRINGS) assert.doesNotMatch(version[name], /'/, `${id} ${name}`);
  }
  assert.ok(consent.versions['consent-2026-10-15'].notice.startsWith('We’ll'));
});

test('consent-2026-10-15 says what the plan says, word for word', () => {
  assert.deepEqual(consent.versions['consent-2026-10-15'], {
    title: 'Stay in the loop',
    notice: 'We’ll email you about security fixes and important changes to Annotake. Every email has an unsubscribe link.',
    box: 'Also email me feedback requests and news',
    footer: 'From Fayzan Malik · {address} · annotake.app · Privacy policy',
  });
});
