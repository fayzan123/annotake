// How it works: three frames of a recording of Annotake itself, on a desktop with Acme open. Each canvas is 720 × 450
// units, 1 em to the unit, built here and hidden from screen readers; each figure's caption is real text in the page.
// Each figure fades up when it first comes into view, and plays only while it's on screen.
import { AT, CLICKS, START, acmeWindow, cursorSvg, element, instantly, place, replay, setAcme, stateAfter } from './acme.js';
import { MARK_VIEWBOX } from './brand.js';
import { createPlayer } from './player.js';

const SVG = 'http://www.w3.org/2000/svg';

/** The keys Annotake offers, each with its alternatives. */
const KEYS = [
  { glyph: '⌘', word: 'command', name: 'Right ⌘', others: 'or Right ⌥, or fn' },
  { glyph: '⌥', word: 'option', name: 'Right ⌥', others: 'or Right ⌘, or fn' },
  { glyph: 'fn', word: 'globe', name: 'fn', others: 'or Right ⌘, or Right ⌥' },
];

const TYPED = "dark mode doesn't stick after Save";

const frames = n => `${n} frame${n === 1 ? '' : 's'}`;

/** The menu bar: Acme's menus on the left, and Annotake's mark and the clock on the right. */
function menubar(canvas) {
  const bar = element('div', 'menubar');
  const menus = element('div', 'menus');
  menus.append(element('b', '', 'Acme'), ...['File', 'Edit', 'View', 'Window'].map(name => element('span', '', name)));
  const mark = document.createElementNS(SVG, 'svg');
  mark.setAttribute('viewBox', `0 0 ${MARK_VIEWBOX[2]} ${MARK_VIEWBOX[3]}`);
  const use = document.createElementNS(SVG, 'use');
  use.setAttribute('href', '/assets/img/brand.svg#mark');
  mark.append(use);
  const status = element('div', 'status');
  status.append(mark, element('span', '', '9:41'));
  bar.append(menus, status);
  canvas.append(bar);
  return bar;
}

/** An Acme window on the canvas at [x, y], `scale` times its own size. */
function windowAt(canvas, at, scale) {
  const win = element('div', 'win');
  place(win, at);
  win.style.setProperty('--s', String(scale));
  const acme = acmeWindow();
  win.append(acme);
  canvas.append(win);
  return acme;
}

function pill(canvas) {
  const node = element('div', 'pill');
  const text = element('span', 'pill-text');
  node.append(element('span', 'dot'), text);
  canvas.append(node);
  return { node, text };
}

/** The card Annotake shows when a recording is ready: its three frames stacked, back to front. */
function card() {
  const node = element('div', 'appcard');
  const stack = element('div', 'stack');
  for (let n = 1; n <= 3; n++) {
    const frame = element('div', `s s${n}`);
    const acme = acmeWindow();
    setAcme(acme, stateAfter(n));
    frame.append(acme);
    stack.append(frame);
  }
  node.append(stack, element('p', 'card-title', '3 frames · 0:04'), element('p', 'card-hint', 'Drag into a chat · click to review'));
  return node;
}

/** The hand that drags the card. */
function handSvg() {
  const svg = document.createElementNS(SVG, 'svg');
  svg.setAttribute('class', 'hand');
  svg.setAttribute('viewBox', '0 0 24 24');
  const path = document.createElementNS(SVG, 'path');
  path.setAttribute('d', 'M8 10V6.5a1.5 1.5 0 0 1 3 0V10m0-.5V5a1.5 1.5 0 0 1 3 0v4.5m0 0V6.5a1.5 1.5 0 0 1 3 0V12c0 4-2.2 7-6 7-3.2 0-4.6-1.6-6.1-4.2L3.7 12.4A1.5 1.5 0 0 1 6.3 11l1.7 2.2V10');
  for (const [name, value] of [['fill', '#FFFFFF'], ['stroke', '#1C1C1E'], ['stroke-width', '1.5'],
    ['stroke-linejoin', 'round'], ['stroke-linecap', 'round']]) path.setAttribute(name, value);
  svg.append(path);
  return svg;
}

/** Step 1: double-tap the key. The pill rises, the mark's front reel turns red, and the key cycles ⌘, ⌥, fn. */
function stepKey(canvas, reducedMotion) {
  const bar = menubar(canvas);
  windowAt(canvas, [286, 70], 1.95);
  const key = element('div', 'keycap');
  const glyph = element('span', 'glyph');
  const word = element('span', 'word');
  key.append(glyph, word);
  const name = element('div', 'keyname');
  const title = element('b');
  const others = element('small');
  name.append(title, others);
  canvas.append(key, name);
  const { node: pillNode, text: pillText } = pill(canvas);
  const status = (seconds, keyGlyph) => `0:0${seconds} · 0 frames · double-tap ${keyGlyph} to stop`;
  const showKey = k => {
    glyph.textContent = k.glyph;
    word.textContent = k.word;
    title.textContent = k.name;
    others.textContent = k.others;
    pillText.textContent = status(0, k.glyph);
  };
  showKey(KEYS[0]);
  if (reducedMotion) {
    pillText.textContent = status(2, KEYS[0].glyph);
    pillNode.classList.add('show');
    bar.classList.add('rec');
    return null;
  }
  return async player => {
    const doubleTap = async () => {
      for (let tap = 0; tap < 2; tap++) {
        key.classList.add('down');
        await player.wait(110);
        key.classList.remove('down');
        await player.wait(120);
      }
    };
    for (let i = 0; ; i++) {
      await player.whenVisible();
      const k = KEYS[i % KEYS.length];
      showKey(k);
      await player.wait(650);
      await doubleTap();
      await player.wait(120);
      pillNode.classList.add('show');
      bar.classList.add('rec');
      for (let seconds = 1; seconds <= 2; seconds++) {
        await player.wait(1000);
        pillText.textContent = status(seconds, k.glyph);
      }
      await player.wait(700);
      await doubleTap();
      pillNode.classList.remove('show');
      bar.classList.remove('rec');
      await player.wait(1100);
    }
  };
}

/** Step 2: click through it. Each click leaves a ring and a caption chip; then the card appears. */
function stepClick(canvas, reducedMotion) {
  const bar = menubar(canvas);
  const origin = [96, 52];
  const scale = 2.65;
  const acme = windowAt(canvas, origin, scale);
  const onCanvas = ([x, y]) => [origin[0] + x * scale, origin[1] + y * scale];
  const press = element('div', 'press');
  const pointer = cursorSvg();
  const chipOffset = [[24, 20], [-236, -38], [-236, 26]];
  const rings = [];
  const chips = [];
  CLICKS.forEach((click, k) => {
    const [x, y] = onCanvas(click.at);
    const ring = element('div', 'ring');
    place(ring, [x, y]);
    const chip = element('div', 'chip');
    const text = element('span', 'chip-text');
    text.append(element('span', 'n', `${k + 1}/3`), ` ${click.chip}`);
    chip.append(text);
    place(chip, [x + chipOffset[k][0], y + chipOffset[k][1]]);
    rings.push(ring);
    chips.push(chip);
  });
  const theCard = card();
  place(theCard, [478, 208]);
  canvas.append(press, ...rings, ...chips, pointer, theCard);
  const { node: pillNode, text: pillText } = pill(canvas);
  const marks = on => {
    for (const node of [...rings, ...chips]) node.classList.toggle('show', on);
  };
  place(pointer, onCanvas(AT.start));
  if (reducedMotion) {
    setAcme(acme, stateAfter(CLICKS.length));
    place(pointer, onCanvas(AT.save));
    marks(true);
    theCard.classList.add('show');
    return null;
  }
  return async player => {
    for (;;) {
      await player.whenVisible();
      instantly(canvas, () => {
        setAcme(acme, START);
        marks(false);
        theCard.classList.remove('show');
        place(pointer, onCanvas(AT.start));
        pointer.classList.remove('gone');
      });
      bar.classList.add('rec');
      pillNode.classList.add('show');
      pillText.textContent = '0:00 · 0 frames · double-tap ⌘ to stop';
      await player.wait(700);
      let state = START;
      for (let k = 0; k < CLICKS.length; k++) {
        const click = CLICKS[k];
        place(pointer, onCanvas(click.at));
        await player.wait(760);
        place(press, onCanvas(click.at));
        replay(press);
        state = click.change(state);
        setAcme(acme, state);
        await player.wait(160);
        rings[k].classList.add('show');
        await player.wait(140);
        chips[k].classList.add('show');
        pillText.textContent = `${click.time} · ${frames(k + 1)} · double-tap ⌘ to stop`;
        await player.wait(650);
      }
      await player.wait(700);
      pillNode.classList.remove('show');
      bar.classList.remove('rec');
      await player.wait(250);
      marks(false);
      theCard.classList.add('show');
      await player.wait(2300);
      theCard.classList.remove('show');
      pointer.classList.add('gone');
      await player.wait(600);
    }
  };
}

/** Step 3: drag the card into Claude Code. It arrives as three images, and the prompt types in. */
function stepDrag(canvas, reducedMotion) {
  menubar(canvas);
  const term = element('div', 'term');
  const titlebar = element('div', 'titlebar');
  titlebar.append(element('i'), element('i'), element('i'), element('span', '', 'acme — claude'));
  const input = element('div', 'input');
  const line = element('div', 'line');
  const chips = [1, 2, 3].map(n => element('span', 'tchip', `[Image #${n}]`));
  const typed = element('span', 'typed');
  line.append(element('span', 'prompt', '>'), ...chips, typed, element('span', 'caret'));
  input.append(line);
  const body = element('div', 'body');
  body.append(element('div', 'dim', '~/acme · main'), input);
  term.append(titlebar, body);
  const theCard = card();
  theCard.classList.add('show');
  const hand = handSvg();
  canvas.append(term, theCard, hand);
  const home = [64, 214];
  const drop = [364, 150];
  const handOver = ([x, y]) => [x + 150, y + 70];
  const reset = () => instantly(canvas, () => {
    theCard.classList.remove('lift', 'drag', 'gone');
    place(theCard, home);
    hand.classList.remove('show', 'drag');
    place(hand, handOver(home));
    for (const chip of chips) chip.classList.remove('show');
    typed.textContent = '';
    input.classList.remove('drop');
  });
  reset();
  if (reducedMotion) {
    theCard.classList.add('gone');
    for (const chip of chips) chip.classList.add('show');
    typed.textContent = TYPED;
    return null;
  }
  return async player => {
    for (;;) {
      await player.whenVisible();
      reset();
      await player.wait(700);
      hand.classList.add('show');
      await player.wait(350);
      theCard.classList.add('lift');
      await player.wait(250);
      theCard.classList.add('drag');
      hand.classList.add('drag');
      place(theCard, drop);
      place(hand, handOver(drop));
      await player.wait(500);
      input.classList.add('drop');
      await player.wait(480);
      theCard.classList.add('gone');
      input.classList.remove('drop');
      hand.classList.remove('show');
      for (const chip of chips) {
        await player.wait(140);
        chip.classList.add('show');
      }
      await player.wait(250);
      for (const character of TYPED) {
        typed.textContent += character;
        await player.wait(32);
      }
      await player.wait(2000);
    }
  };
}

const STEPS = { 'step-key': stepKey, 'step-click': stepClick, 'step-drag': stepDrag };

export function initSteps(section, { reducedMotion }) {
  const players = [];
  // The fade-up hides the figures until they're in view, so it starts only once scripts run.
  section.classList.add('ready');
  for (const figure of section.querySelectorAll('figure.step')) {
    const loop = STEPS[figure.id](figure.querySelector('.canvas'), reducedMotion);
    if (!loop) {
      figure.classList.add('in');
      continue;
    }
    const player = createPlayer(figure, {
      threshold: 0.35,
      onChange: visible => visible && figure.classList.add('in'),
    });
    if (player.visible) figure.classList.add('in');
    player.run(() => loop(player));
    players.push(player);
  }
  return { stop: () => players.forEach(player => player.stop()) };
}
