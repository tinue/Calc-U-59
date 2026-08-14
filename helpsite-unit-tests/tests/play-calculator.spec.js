const { test, expect } = require('@playwright/test');

// The WASM module + ROM/module JSON fetches take longer than the site's
// other pages (which are pure static HTML) — give #play tests more room
// than the 10s default in playwright.config.js.
test.describe.configure({ timeout: 20000 });

async function gotoPlayReady(page) {
  await page.goto('/play/');
  await page.waitForSelector('main');
  // No dedicated "ready" DOM hook — wait for the transient startup status
  // text to clear, which the worker's `{type:"ready"}` message triggers.
  await expect(page.getByText('Starting the emulator')).toHaveCount(0, { timeout: 15000 });
}

async function pressKey(page, label) {
  await page.getByRole('button', { name: label, exact: true }).click();
  await page.waitForTimeout(200); // matches the worker's press/release pacing
}

// The display is a single <canvas> (docs/led-display.jsx), not a 12-cell DOM
// grid, so there is no text to read off it — the same reason the
// physical-keyboard tests below compare rendered bitmaps instead of decoding
// segments. toDataURL() captures the whole display.
async function ledBitmap(page) {
  return page.locator('canvas').first().evaluate((c) => c.toDataURL());
}

// The C (calculate) indicator only ever occupies the canvas's leftmost
// twelfth (led-display.jsx draws it at digit index 11, i.e. x=0..digitWidth)
// — cropping to that slice keeps the comparison from being diluted by
// unrelated digits changing elsewhere on the display.
async function leftDigitBitmap(page) {
  const box = await page.locator('canvas').first().boundingBox();
  const buf = await page.screenshot({ clip: { x: box.x, y: box.y, width: box.width / 12, height: box.height } });
  return buf.toString('base64');
}

test('play page loads the WASM engine with no console errors', async ({ page }) => {
  const errors = [];
  page.on('pageerror', (err) => errors.push(err.message));
  page.on('console', (msg) => { if (msg.type() === 'error') errors.push(msg.text()); });

  await gotoPlayReady(page);

  expect(errors, `Console/page errors:\n${errors.join('\n')}`).toHaveLength(0);
});

test('module 01 (Master Library) is loaded by default', async ({ page }) => {
  await gotoPlayReady(page);
  await expect(page.locator('select').first()).toHaveValue('ML');
});

test('pressing 2 + 2 = computes through the real emulation core', async ({ page }) => {
  await gotoPlayReady(page);
  for (const key of ['2', '+', '2', '=']) await pressKey(page, key);
  await page.waitForTimeout(300);
  const viaAddition = await ledBitmap(page);

  // No DOM text to read off the canvas (see ledBitmap above), so arithmetic
  // correctness is verified by bitmap identity against a second,
  // independently-computed expression with the same result.
  await gotoPlayReady(page);
  for (const key of ['5', '−', '1', '=']) await pressKey(page, key);
  await page.waitForTimeout(300);
  const viaSubtraction = await ledBitmap(page);

  expect(viaAddition).toBe(viaSubtraction);
});

test('the C (calculate) indicator lights the leftmost cell while a program runs', async ({ page }) => {
  await gotoPlayReady(page);
  const idle = await leftDigitBitmap(page);

  await page.locator('select').nth(1).selectOption({ label: 'Calculator diagnostic' });
  await page.waitForTimeout(1000);
  await pressKey(page, 'E'); // diag.ti59's own documented "press E to start"

  const duringRun = await leftDigitBitmap(page);
  expect(duringRun).not.toBe(idle);
});

test('2nd -> Pgm -> 01 shows the Master Library diagnostic cue card', async ({ page }) => {
  await gotoPlayReady(page);

  await pressKey(page, '2nd');
  await pressKey(page, 'LRN'); // physical key whose 2nd-function is "Pgm"
  await pressKey(page, '0');
  await pressKey(page, '1');
  await page.waitForTimeout(300);

  await expect(page.locator('.cuecard')).toHaveCount(1);
  await expect(page.locator('.cuecard')).toContainText('MASTER LIBRARY DIAGNOSTIC');
  await expect(page.locator('.cuecard')).toContainText('ML-01');
});

// ── Physical keyboard (docs/keyboard-map.js) ────────────────────────────
//
// These tests compare the rendered canvas bitmap (ledBitmap, above) before
// and after typing: it changes if and only if the keys reached the
// emulation core and the display updated. That sidesteps decoding segments
// while still exercising the whole path.
//
// Only 26 of the 45 keys are bound — white keys, yellow keys except 2nd, A-E,
// and EE/(/) — so the "unbound keys" test below is load-bearing, not padding.

// Focus without clicking — a click would land on a key and press it.
async function focusCalculator(page) {
  await page.locator('.calcu-device').focus();
}

// The display keeps changing for a while after the worker reports "ready" (the
// core runs POWER_ON_STEPS to stabilize, and the decimal point has an afterglow
// animation). Any before/after comparison has to start from a settled frame or
// it reads that drift as a keypress.
async function settledLedBitmap(page) {
  let previous = await ledBitmap(page);
  for (let i = 0; i < 20; i++) {
    await page.waitForTimeout(250);
    const current = await ledBitmap(page);
    if (current === previous) return current;
    previous = current;
  }
  throw new Error('LED display never settled');
}

async function typeKey(page, key) {
  await page.keyboard.press(key);
  await page.waitForTimeout(250); // covers the 80 ms hold + 120 ms gap per code
}

test('typing 2 + 2 = drives the emulation core', async ({ page }) => {
  await gotoPlayReady(page);
  await focusCalculator(page);

  const before = await settledLedBitmap(page);
  for (const key of ['2', '+', '2', '=']) await typeKey(page, key);
  await page.waitForTimeout(300);

  expect(await ledBitmap(page)).not.toBe(before);
});

test('typing matches clicking for the same keys', async ({ page }) => {
  await gotoPlayReady(page);
  for (const label of ['2', '+', '2', '=']) await pressKey(page, label);
  await page.waitForTimeout(300);
  const clicked = await settledLedBitmap(page);

  await gotoPlayReady(page);
  await focusCalculator(page);
  for (const key of ['2', '+', '2', '=']) await typeKey(page, key);
  await page.waitForTimeout(300);

  expect(await settledLedBitmap(page)).toBe(clicked);
});

test('unbound keys do nothing', async ({ page }) => {
  await gotoPlayReady(page);
  await focusCalculator(page);

  const before = await settledLedBitmap(page);
  // STO, LRN, x², R/S, CE, 2nd — all deliberately click-only.
  for (const key of ['s', 'l', 'q', ' ', 'Backspace', "'"]) await typeKey(page, key);
  await page.waitForTimeout(300);
  expect(await ledBitmap(page)).toBe(before);

  // ...and the calculator is still listening: a bound key still works.
  await typeKey(page, '5');
  await page.waitForTimeout(300);
  expect(await ledBitmap(page)).not.toBe(before);
});

test('Shift+A sends 2nd before A', async ({ page }) => {
  await gotoPlayReady(page);
  await focusCalculator(page);

  const second = page.getByRole('button', { name: '2nd', exact: true });
  await page.keyboard.press('Shift+A');

  // The 2nd key lights first, for its own full tap, before A is pressed —
  // proof the shorthand is played back as two presses and not one.
  await expect(second).toHaveCSS('transform', /matrix/, { timeout: 200 });
});

test('keystrokes are ignored until the calculator has focus', async ({ page }) => {
  await gotoPlayReady(page);

  // No focusCalculator() here — the page never auto-focuses it.
  const before = await settledLedBitmap(page);
  for (const key of ['2', '+', '2', '=']) await typeKey(page, key);
  await page.waitForTimeout(300);

  expect(await ledBitmap(page)).toBe(before);
});

test('the standalone app does not capture keystrokes', async ({ page }) => {
  await page.goto('/app/index.html');
  await expect(page.getByText('Starting the emulator')).toHaveCount(0, { timeout: 15000 });

  // keyboard-map.js is deliberately not loaded there, and PlayCalculator is
  // mounted without the keyboard prop.
  expect(await page.evaluate(() => typeof ti59KeyboardMatrixCodes)).toBe('undefined');
  expect(await page.locator('.calcu-device').getAttribute('tabindex')).toBeNull();
});

test('loading the Base Conversion preset shows its own cue card', async ({ page }) => {
  await gotoPlayReady(page);

  await page.locator('select').nth(1).selectOption({ label: 'Base conversion' });
  await page.waitForTimeout(1000);

  await expect(page.locator('.cuecard')).toHaveCount(1);
  await expect(page.locator('.cuecard')).toContainText('Base Conversion');
});
