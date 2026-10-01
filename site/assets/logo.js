// The footer's full logo, live: when it comes into view the tripod's legs swing open into the A, the camera settles,
// and the front reel winds red, as the menu-bar icon turns while recording. Its shapes and numbers come from brand.js,
// generated from the app's BrandMark.swift, so open, it is exactly the brand's logo.
import { FRONT_REEL, GEOMETRY, LOGO_VIEWBOX, PATHS } from './brand.js';
import { createPlayer } from './player.js';

const SVG = 'http://www.w3.org/2000/svg';

/**
 * The legs, the brace, and the camera's offset with the legs splayed `theta` radians from vertical. Each leg pivots on
 * the point where the two center lines meet, hidden in the camera body, so the feet stay on the baseline and the camera
 * rides up as the legs close.
 */
export function tripodPose(theta, g = GEOMETRY) {
  const MID = g.footSpan / 2;
  const HALF = g.legThickness / 2;
  const OPEN = g.splayDegrees * Math.PI / 180;
  const LC = (MID - HALF / Math.cos(OPEN)) / Math.sin(OPEN);  // a center line, foot to pivot: about 113.04
  const PIVOT_OPEN = -LC * Math.cos(OPEN);  // about -101.6
  const ABOVE = g.legTop - PIVOT_OPEN;  // about -10.4: the legs run past the pivot, inside the body
  const foot = MID - LC * Math.sin(theta);
  const pivot = -LC * Math.cos(theta);
  const top = pivot + ABOVE;
  const w = HALF / Math.cos(theta);
  const xAt = y => foot + (-y) * Math.tan(theta);  // the left leg's center line at height y
  const leftLeg = [[xAt(0) - w, 0], [xAt(0) + w, 0], [xAt(top) + w, top], [xAt(top) - w, top]];
  const rightLeg = leftLeg.map(([x, y]) => [2 * MID - x, y]);
  const braceX = xAt(g.crossbarY);
  return {
    leftLeg,
    rightLeg,
    brace: {
      x: braceX,
      width: Math.max(0, 2 * (MID - braceX)),
      y: g.crossbarY - g.braceThickness / 2,
      height: g.braceThickness,
    },
    cameraOffsetY: pivot - PIVOT_OPEN,
  };
}

export function easeOutBack(x) {
  const c1 = 1.55;
  const c3 = c1 + 1;
  return 1 + c3 * (x - 1) ** 3 + c1 * (x - 1) ** 2;
}

export function easeInOutCubic(x) {
  return x < 0.5 ? 4 * x ** 3 : 1 - (-2 * x + 2) ** 3 / 2;
}

const clamp01 = x => Math.max(0, Math.min(1, x));

function svgElement(tag, attributes = {}) {
  const node = document.createElementNS(SVG, tag);
  for (const [name, value] of Object.entries(attributes)) node.setAttribute(name, String(value));
  return node;
}

/**
 * Replaces the container's static logo with a live one: the legs and brace, the camera (body, lens, and both reels,
 * in ink) with the red sweep over the front reel, and the letters. Its view box is the logo's, raised 13 units so the
 * closed pose's raised camera fits.
 */
export function buildLogo(container) {
  const [x, y, width, height] = LOGO_VIEWBOX;
  const svg = svgElement('svg', { viewBox: `${x} ${y - 13} ${width} ${height + 13}`, role: 'img', 'aria-label': 'Annotake' });
  const tripod = svgElement('g', { fill: 'currentColor' });
  tripod.append(svgElement('polygon', { class: 'leg' }), svgElement('polygon', { class: 'leg' }),
    svgElement('rect', { class: 'brace' }));
  const camera = svgElement('g', { class: 'camera' });
  const ink = svgElement('g', { fill: 'currentColor' });
  for (const name of ['body', 'lens', 'backReel', 'frontReel']) {
    ink.append(svgElement('path', { d: PATHS[name], ...(name.endsWith('Reel') ? { 'fill-rule': 'evenodd' } : {}) }));
  }
  const r = (FRONT_REEL.outer + FRONT_REEL.inner) / 2;
  const sweep = svgElement('circle', {
    class: 'sweep', cx: FRONT_REEL.cx, cy: FRONT_REEL.cy, r, fill: 'none',
    'stroke-width': FRONT_REEL.outer - FRONT_REEL.inner, 'stroke-dasharray': 2 * Math.PI * r,
    transform: `rotate(-90 ${FRONT_REEL.cx} ${FRONT_REEL.cy})`,
  });
  camera.append(ink, sweep);
  svg.append(tripod, camera, svgElement('path', { d: PATHS.letters, fill: 'currentColor' }));
  container.replaceChildren(svg);
  return svg;
}

/** Shows the legs at `theta` and the front reel `wind` of the way red. */
function pose(svg, theta, wind) {
  const { leftLeg, rightLeg, brace, cameraOffsetY } = tripodPose(theta);
  const [left, right] = svg.querySelectorAll('polygon.leg');
  const points = leg => leg.map(([x, y]) => `${x},${y}`).join(' ');
  left.setAttribute('points', points(leftLeg));
  right.setAttribute('points', points(rightLeg));
  const rect = svg.querySelector('rect.brace');
  for (const name of ['x', 'y', 'width', 'height']) rect.setAttribute(name, String(brace[name]));
  svg.querySelector('g.camera').setAttribute('transform', `translate(0 ${cameraOffsetY})`);
  const sweep = svg.querySelector('circle.sweep');
  sweep.setAttribute('stroke-dashoffset', String(Number(sweep.getAttribute('stroke-dasharray')) * (1 - wind)));
}

/**
 * Plays the opening whenever the logo comes into view (60% of it), and closes it again when it leaves, so it replays.
 * With Reduce Motion, it's simply open and wound.
 */
export function playLogo(svg, { reducedMotion }) {
  const OPEN = GEOMETRY.splayDegrees * Math.PI / 180;
  if (reducedMotion) {
    pose(svg, OPEN, 1);
    return { stop() {} };
  }
  let frame = 0;
  function play() {
    cancelAnimationFrame(frame);
    const start = performance.now();
    const step = () => {
      const ms = performance.now() - start;
      pose(svg, OPEN * easeOutBack(clamp01((ms - 250) / 950)), easeInOutCubic(clamp01((ms - 1150) / 650)));
      if (ms < 1900) frame = requestAnimationFrame(step);
    };
    pose(svg, 0, 0);
    frame = requestAnimationFrame(step);
  }
  function close() {
    cancelAnimationFrame(frame);
    pose(svg, 0, 0);
  }
  close();
  const player = createPlayer(svg.parentElement, { threshold: 0.6, onChange: visible => (visible ? play() : close()) });
  if (player.visible) play();
  return {
    stop() {
      player.stop();
      cancelAnimationFrame(frame);
    },
  };
}
