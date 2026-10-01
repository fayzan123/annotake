// The footer logo's tripod: each leg pivots where the legs' center lines meet, inside the camera body, so the feet stay
// on the baseline and the camera rides up as the legs close. Open, it must be exactly the brand's A.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GEOMETRY, PATHS } from '../../assets/brand.js';
import { easeInOutCubic, easeOutBack, tripodPose } from '../../assets/logo.js';

const OPEN = GEOMETRY.splayDegrees * Math.PI / 180;
const MID = GEOMETRY.footSpan / 2;

/** The points of path data made of M, L, and Z. */
function points(d) {
  const numbers = d.match(/-?\d*\.?\d+/g).map(Number);
  const result = [];
  for (let i = 0; i < numbers.length; i += 2) result.push([numbers[i], numbers[i + 1]]);
  return result;
}

function assertNear(actual, expected, tolerance, message) {
  assert.ok(Math.abs(actual - expected) <= tolerance, `${message}: ${actual} isn't within ${tolerance} of ${expected}`);
}

function assertPoints(actual, expected, tolerance, message) {
  assert.equal(actual.length, expected.length, message);
  actual.forEach(([x, y], i) => {
    assertNear(x, expected[i][0], tolerance, `${message}, point ${i} x`);
    assertNear(y, expected[i][1], tolerance, `${message}, point ${i} y`);
  });
}

const mirrored = leg => leg.map(([x, y]) => [2 * MID - x, y]);
const xs = leg => leg.map(([x]) => x);

test('open, the legs and the brace are exactly the brand’s A, and the camera sits where it does', () => {
  const pose = tripodPose(OPEN);
  assertPoints(pose.leftLeg, points(PATHS.leftLeg), 0.01, 'the left leg');
  assertPoints(pose.rightLeg, points(PATHS.rightLeg), 0.01, 'the right leg');
  assertNear(pose.brace.x, 29.48, 0.01, 'brace x');
  assertNear(pose.brace.y, -46.8, 0.01, 'brace y');
  assertNear(pose.brace.width, 62.04, 0.01, 'brace width');
  assertNear(pose.brace.height, 17.6, 0.01, 'brace height');
  assert.ok(Math.abs(pose.cameraOffsetY) < 1e-9, `the camera doesn't move: ${pose.cameraOffsetY}`);
});

test('closed, the legs are one stem under the camera, with no brace, and the camera rides higher', () => {
  const pose = tripodPose(0);
  assertPoints(pose.leftLeg, mirrored(pose.rightLeg), 1e-9, 'the left leg is the mirrored right leg');
  assert.deepEqual([Math.min(...xs(pose.leftLeg)), Math.max(...xs(pose.leftLeg))],
    [Math.min(...xs(pose.rightLeg)), Math.max(...xs(pose.rightLeg))], 'the two legs overlap');
  assertNear(Math.min(...xs(pose.leftLeg)), 50.66, 0.02, 'the stem’s left edge');
  assertNear(Math.max(...xs(pose.leftLeg)), 70.34, 0.02, 'the stem’s right edge');
  assert.equal(pose.brace.width, 0);
  assertNear(pose.cameraOffsetY, -11.44, 0.05, 'the camera rides up');
});

test('the feet stay on the baseline, and the right leg mirrors the left, from 0° to 30°', () => {
  for (let degrees = 0; degrees <= 30; degrees += 0.5) {
    const pose = tripodPose(degrees * Math.PI / 180);
    for (const leg of [pose.leftLeg, pose.rightLeg]) {
      assert.equal(leg[0][1], 0, `${degrees}°`);
      assert.equal(leg[1][1], 0, `${degrees}°`);
    }
    assertPoints(pose.rightLeg, mirrored(pose.leftLeg), 1e-9, `${degrees}°`);
    assert.ok(pose.brace.width >= 0, `${degrees}°`);
  }
});

test('the easings start at 0 and end at 1, and the opening overshoots a little', () => {
  for (const ease of [easeOutBack, easeInOutCubic]) {
    assertNear(ease(0), 0, 1e-12, ease.name);
    assertNear(ease(1), 1, 1e-12, ease.name);
  }
  let peak = 0;
  for (let x = 0; x <= 1; x += 0.001) peak = Math.max(peak, easeOutBack(x));
  assert.ok(peak > 1.05, `easeOutBack peaks at ${peak}`);
  for (let x = 0; x <= 1; x += 0.01) assert.ok(easeInOutCubic(x) >= 0 && easeInOutCubic(x) <= 1);
});
