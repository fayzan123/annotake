// Through the gate: film runs through a camera's gate under the hero. Three clicks in Acme; with each, the shutter
// flashes, the strip advances one frame, and the frame leaving the gate gets its click ring and caption, as Annotake
// captions a step. The recording pill stays over the live frame, never in a finished one. Decorative: the section is
// aria-hidden, and the hero's text carries the meaning.
import { AT, CLICKS, START, acmeWindow, element, instantly, place, replay, setAcme, stateAfter } from './acme.js';
import { createPlayer } from './player.js';

/** The slots run from i = -3 to 6; slot i = 0 is in the gate when the strip is at rest. */
const FIRST = -3;
const LAST = 6;

const frames = n => `${n} frame${n === 1 ? '' : 's'}`;

export function initGate(root, { reducedMotion }) {
  const strip = element('div', 'strip');
  const track = element('div', 'track');
  const slots = [];
  for (let i = FIRST; i <= LAST; i++) {
    const slot = element('div', 'slot');
    const frame = element('div', 'frame');
    const cap = element('div', 'cap');
    cap.append(element('b'), element('span', '', 'Acme — Settings'));
    frame.append(acmeWindow({ cursor: true }), cap);
    slot.append(frame, element('div', 'unexposed'));
    track.append(slot);
    slots.push(slot);
  }
  const gate = element('div', 'gate');
  for (const corner of ['tl', 'tr', 'bl', 'br']) gate.append(element('i', `corner ${corner}`));
  const flash = element('div', 'flash');
  const pill = element('div', 'pill');
  const pillText = element('span', 'pill-text', '0:00 · 0 frames');
  pill.append(element('span', 'dot'), pillText);
  gate.append(flash, pill);
  strip.append(element('div', 'holes top'), element('div', 'holes bottom'), track, gate);
  root.replaceChildren(strip);

  const slot = i => {
    const node = slots[i - FIRST];
    return { node, acme: node.querySelector('.acme'), cap: node.querySelector('.cap'), cover: node.querySelector('.unexposed') };
  };

  /** Back to the start: no frames taken, the live slot exposed, the strip at rest. */
  function reset() {
    instantly(strip, () => {
      strip.style.setProperty('--k', '0');
      for (let i = FIRST; i <= LAST; i++) {
        const { acme, cap, cover } = slot(i);
        setAcme(acme, START);
        place(acme.querySelector('.cursor'), AT.start);
        acme.querySelector('.ring').classList.remove('show');
        cap.classList.remove('show');
        cap.querySelector('b').textContent = '';
        cover.classList.toggle('open', i === 0);
      }
      pillText.textContent = '0:00 · 0 frames';
    });
    track.classList.remove('fade');
  }

  /** The frame taken by click `k` gets its ring and caption. */
  function caption(k) {
    const { acme, cap } = slot(k);
    const ring = acme.querySelector('.ring');
    place(ring, CLICKS[k].at);
    ring.classList.add('show');
    cap.querySelector('b').textContent = CLICKS[k].caption;
    cap.classList.add('show');
  }

  /** The finished recording, for Reduce Motion: three captioned frames, and the live one showing the toast. */
  function finished() {
    reset();
    instantly(strip, () => {
      CLICKS.forEach((click, k) => {
        const { acme, cover } = slot(k);
        setAcme(acme, stateAfter(k + 1));
        place(acme.querySelector('.cursor'), click.at);
        cover.classList.add('open');
        caption(k);
      });
      const live = slot(CLICKS.length);
      setAcme(live.acme, stateAfter(CLICKS.length));
      place(live.acme.querySelector('.cursor'), AT.save);
      live.cover.classList.add('open');
      strip.style.setProperty('--k', String(CLICKS.length));
      pillText.textContent = `${CLICKS.at(-1).time} · ${frames(CLICKS.length)}`;
    });
  }

  if (reducedMotion) {
    finished();
    return { stop() {} };
  }

  reset();
  const player = createPlayer(root, { threshold: 0.35 });
  player.run(async () => {
    for (;;) {
      await player.whenVisible();
      reset();
      await player.wait(700);
      let state = START;
      for (let k = 0; k < CLICKS.length; k++) {
        const click = CLICKS[k];
        const { acme } = slot(k);
        place(acme.querySelector('.cursor'), click.at);
        await player.wait(780);
        const press = acme.querySelector('.press');
        place(press, click.at);
        replay(press);
        state = click.change(state);
        setAcme(acme, state);
        await player.wait(240);
        replay(flash);
        await player.wait(110);
        const next = slot(k + 1);
        instantly(next.acme, () => {
          setAcme(next.acme, state);
          place(next.acme.querySelector('.cursor'), click.at);
        });
        next.cover.classList.add('open');
        strip.style.setProperty('--k', String(k + 1));
        pillText.textContent = `${click.time} · ${frames(k + 1)}`;
        await player.wait(560);
        caption(k);
        await player.wait(620);
      }
      await player.wait(1800);
      track.classList.add('fade');
      await player.wait(400);
    }
  });
  return { stop: player.stop };
}
