// The welcome email (design §5.1): what it says, and that its HTML escapes what it's given. subscribe.js sends it once,
// when a contact is created.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { welcomeEmail } from '../../api/_lib/welcome.js';
import { unsubscribeUrl } from '../../api/_lib/unsubscribe-token.js';

const ADDRESS = 'PO Box 1234, Toronto ON M5W 1A1';
const UNSUBSCRIBE = unsubscribeUrl('sam@example.com', 'test-secret');
const PRIVACY = 'https://annotake.app/privacy';

const ENTITIES = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'" };
const fromHtml = html => html.replace(/&(amp|lt|gt|quot|#39);/g, entity => ENTITIES[entity]);

/** The HTML's text, as a reader sees it: no title or tags, entities decoded, whitespace collapsed. */
const textOf = html => fromHtml(html.replace(/<title>[\s\S]*?<\/title>/, '').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ');

/** Every link's href, as written in the HTML. */
const hrefs = html => [...html.matchAll(/<a href="([^"]*)"/g)].map(([, href]) => href);

const email = (options = {}) => welcomeEmail({ news: true, address: ADDRESS, unsubscribe: UNSUBSCRIBE, ...options });

test('the subject is Welcome to Annotake, whatever the choice', () => {
  for (const news of [true, false]) assert.equal(email({ news }).subject, 'Welcome to Annotake');
});

test('the text has the shortcut, the reply line, the unsubscribe link, and the footer', () => {
  for (const news of [true, false]) {
    const { text } = email({ news });
    for (const phrase of [
      'Hold Right ⌘', 'Reply to this email any time', 'Didn’t sign up?', UNSUBSCRIBE,
      `Fayzan Malik · ${ADDRESS} · annotake.app`, PRIVACY,
    ]) {
      assert.ok(text.includes(phrase), `${news}: ${phrase}`);
    }
    assert.doesNotMatch(text, /<|&amp;/, 'plain text, with the link as it is');
  }
});

test('what they’ll get follows the box: important notices, plus feedback requests and news only when ticked', () => {
  const ticked = email({ news: true });
  const unticked = email({ news: false });
  for (const body of [ticked.text, textOf(ticked.html)]) {
    assert.ok(body.includes('important notices, plus feedback requests and news'));
  }
  for (const body of [unticked.text, textOf(unticked.html)]) {
    assert.ok(body.includes('important notices'));
    assert.doesNotMatch(body, /feedback requests|news\./);
  }
});

test('the text, word for word', () => {
  assert.equal(email({ news: true }).text, [
    'Thanks for trying Annotake.',
    '',
    'Hold Right ⌘, click through anything on your screen, and let go. Then drag the card into ChatGPT, Claude, or Cursor.',
    '',
    'Reply to this email any time: I read every one.',
    '',
    'You’ll get important notices, plus feedback requests and news.',
    '',
    `Didn’t sign up? Unsubscribe: ${UNSUBSCRIBE}`,
    '',
    `Fayzan Malik · ${ADDRESS} · annotake.app`,
    `Privacy policy: ${PRIVACY}`,
    `Unsubscribe: ${UNSUBSCRIBE}`,
  ].join('\n'));
  assert.equal(email({ news: false }).text.split('\n')[6], 'You’ll get important notices.');
});

test('the HTML says what the text says, with the same links, HTML-escaped', () => {
  for (const news of [true, false]) {
    const { text, html } = email({ news });
    const shown = textOf(html);
    // Every line of the text, less its URLs, which the HTML puts behind links.
    for (const line of text.split('\n').filter(Boolean)) {
      const words = line.replace(/:? ?https:\/\/\S+/g, '').trim();
      assert.ok(shown.includes(words), `${news}: ${words}`);
    }
    // The unsubscribe link twice (Didn’t sign up?, and the footer), the site, and the privacy policy.
    const escaped = UNSUBSCRIBE.replaceAll('&', '&amp;');
    assert.notEqual(escaped, UNSUBSCRIBE, 'the link has an & to escape');
    assert.deepEqual(hrefs(html), [escaped, 'https://annotake.app', PRIVACY, escaped]);
    assert.ok(!html.includes(UNSUBSCRIBE), 'no unescaped & in the HTML');
    assert.equal(fromHtml(hrefs(html)[0]), UNSUBSCRIBE);
  }
});

test('the HTML escapes the mailing address and every link', () => {
  const { text, html } = email({
    address: 'Suite <5> & "Co", O\'Hara St', unsubscribe: 'https://annotake.app/api/unsubscribe?e=a"b<c>&s=\'x\'',
  });
  assert.ok(html.includes('Fayzan Malik · Suite &lt;5&gt; &amp; &quot;Co&quot;, O&#39;Hara St · '));
  assert.ok(html.includes('href="https://annotake.app/api/unsubscribe?e=a&quot;b&lt;c&gt;&amp;s=&#39;x&#39;"'));
  assert.doesNotMatch(html, /<5>|"Co"|O'Hara|a"b|<c>/);
  assert.ok(text.includes('Fayzan Malik · Suite <5> & "Co", O\'Hara St · annotake.app'), 'the text stays as given');
});

test('the HTML is a whole page with inline styles only, and no script or image', () => {
  const { html } = email();
  assert.match(html, /^<!DOCTYPE html>\n<html lang="en">\n<head><meta charset="utf-8">/);
  assert.match(html, /<title>Welcome to Annotake<\/title>/);
  assert.match(html, /<\/body>\n<\/html>$/);
  assert.doesNotMatch(html, /<script|<style|<img|<link/i);
});
