// "Acme Settings", the made-up app every picture on the page records: a window drawn in HTML and CSS, so it stays
// sharp at any size and in both themes. It's 196 × 104 units, and everything inside is sized in em, where 1 em is one
// unit; the container sets the font size. The CSP allows no inline styles, so it's built from elements and classes, and
// the only styles set from here are positions.

/** Where things are, in Acme units. */
export const AT = { start: [118, 74], appearance: [27, 43], dark: [175, 51], save: [164, 88] };

/** The sidebar's selected tab, the "Dark mode" switch, and the "Couldn’t save settings" toast. */
export const START = { side: 0, dark: false, toast: false };

/** The three clicks every animation shows, with what each changes and its caption. */
export const CLICKS = [
  {
    at: AT.appearance,
    change: state => ({ ...state, side: 1 }),
    caption: '1/3 · 0:01 · Clicked tab "Appearance"',
    chip: 'Clicked tab "Appearance"',
    time: '0:01',
  },
  {
    at: AT.dark,
    change: state => ({ ...state, dark: true }),
    caption: '2/3 · 0:02 · Clicked switch "Dark mode"',
    chip: 'Clicked switch "Dark mode"',
    time: '0:02',
  },
  {
    at: AT.save,
    change: state => ({ ...state, toast: true }),
    caption: '3/3 · 0:04 · Clicked button "Save"',
    chip: 'Clicked button "Save"',
    time: '0:04',
  },
];

/** The state after the first `n` clicks. */
export function stateAfter(n) {
  return CLICKS.slice(0, n).reduce((state, click) => click.change(state), START);
}

const SVG = 'http://www.w3.org/2000/svg';

/** An element with a class and text, the page's only way of building markup. */
export function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text) node.textContent = text;
  return node;
}

/** The pointer, drawn: a dark arrow with a white edge. */
export function cursorSvg(className = 'cursor') {
  const svg = document.createElementNS(SVG, 'svg');
  svg.setAttribute('class', className);
  svg.setAttribute('viewBox', '-1 -1 15 22');
  const path = document.createElementNS(SVG, 'path');
  path.setAttribute('d', 'M0 0 L0 17 L4.5 12.8 L7.6 19.6 L10.4 18.4 L7.4 11.8 L13.2 11.4 Z');
  path.setAttribute('fill', '#1C1C1E');
  path.setAttribute('stroke', '#FFFFFF');
  path.setAttribute('stroke-width', '1.4');
  path.setAttribute('stroke-linejoin', 'round');
  svg.append(path);
  return svg;
}

/** A switch row: a label bar and a switch. */
function row() {
  const line = element('div', 'row');
  line.append(element('div', 'label'), element('div', 'switch'));
  return line;
}

/**
 * The Acme window: the title bar, the sidebar's four tabs, the main pane with two switch rows and Save, the toast, and
 * the click ring, the press ripple, and (with `cursor`) the pointer, which the animations place.
 */
export function acmeWindow({ cursor = false } = {}) {
  const win = element('div', 'acme');
  const bar = element('div', 'titlebar');
  bar.append(element('i'), element('i'), element('i'));
  const side = element('div', 'side');
  for (let i = 0; i < 4; i++) side.append(element('b'));
  const main = element('div', 'main');
  main.append(element('div', 'heading'), row(), row(), element('div', 'save'));
  win.append(bar, side, main, element('div', 'toast', 'Couldn’t save settings'), element('div', 'ring'),
    element('div', 'press'));
  if (cursor) win.append(cursorSvg());
  return win;
}

/** Shows `state`: the selected tab, the switch, and the toast. */
export function setAcme(win, state) {
  win.querySelectorAll('.side b').forEach((tab, i) => tab.classList.toggle('on', i === state.side));
  win.querySelector('.switch').classList.toggle('on', state.dark);
  win.querySelector('.toast').classList.toggle('show', state.toast);
}

/** Moves an element to [x, y] in its container's units, in em. */
export function place(node, [x, y]) {
  node.style.left = `${x}em`;
  node.style.top = `${y}em`;
}

/** Runs `change` with transitions off on `node`, so it happens at once. */
export function instantly(node, change) {
  node.classList.add('instant');
  change();
  void node.offsetWidth;  // apply it before the transitions come back
  node.classList.remove('instant');
}

/** Restarts a one-shot CSS animation by toggling its class. */
export function replay(node, className = 'go') {
  node.classList.remove(className);
  void node.offsetWidth;
  node.classList.add(className);
}
