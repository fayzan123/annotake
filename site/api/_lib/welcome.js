// The welcome email (design §5.1), sent once by subscribe.js when a contact is created: plain text and simple HTML,
// like the link email. Its footer is what CASL wants in every email: the sender's name, a mailing address, a contact
// (the site), and an unsubscribe link.

const HOME = 'https://annotake.app';
const PRIVACY = 'https://annotake.app/privacy';

const THANKS = 'Thanks for trying Annotake.';
const SHORTCUT = 'Hold Right ⌘, click through the bug in any app, and let go. Then drag the card into Claude Code, Cursor, or ChatGPT.';
const REPLY = 'Reply to this email any time: I read every one.';

const ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
const escapeHtml = text => text.replace(/[&<>"']/g, char => ESCAPES[char]);

/**
 * The email for a new contact: `news` is the box's choice, `address` the mailing address for the footer, and
 * `unsubscribe` the contact's one-click link (unsubscribeUrl). The HTML escapes the address and every link.
 */
export function welcomeEmail({ news, address, unsubscribe }) {
  const choice = news ? 'You’ll get important notices, plus feedback requests and news.' : 'You’ll get important notices.';
  const text = [
    THANKS,
    '',
    SHORTCUT,
    '',
    REPLY,
    '',
    choice,
    '',
    `Didn’t sign up? Unsubscribe: ${unsubscribe}`,
    '',
    `Fayzan Malik · ${address} · annotake.app`,
    `Privacy policy: ${PRIVACY}`,
    `Unsubscribe: ${unsubscribe}`,
  ].join('\n');
  const link = escapeHtml(unsubscribe);
  // Inline styles are fine here: it's an email, not the site.
  const html = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Welcome to Annotake</title></head>
<body style="margin:0;padding:24px;background:#ffffff;color:#1c1c1e;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:16px;line-height:1.5">
<p style="margin:0 0 16px">${THANKS}</p>
<p style="margin:0 0 16px">${SHORTCUT}</p>
<p style="margin:0 0 16px">${REPLY}</p>
<p style="margin:0 0 16px">${choice}</p>
<p style="margin:0 0 24px">Didn’t sign up? <a href="${link}" style="color:#1c1c1e">Unsubscribe</a></p>
<p style="margin:0;color:#6e6e73;font-size:14px">Fayzan Malik · ${escapeHtml(address)} · <a href="${escapeHtml(HOME)}" style="color:#6e6e73">annotake.app</a><br><a href="${escapeHtml(PRIVACY)}" style="color:#6e6e73">Privacy policy</a> · <a href="${link}" style="color:#6e6e73">Unsubscribe</a></p>
</body>
</html>`;
  return { subject: 'Welcome to Annotake', text, html };
}
