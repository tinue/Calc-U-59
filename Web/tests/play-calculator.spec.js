const { test, expect } = require('@playwright/test');

// The calculator end to end through the real WASM engine, on dist/index.html
// (PlayCalculator with controls and keyboard, as the website's /play/ mounts
// it) and dist/app/. URLs are relative to the project's baseURL — the server
// root or a sub-path (playwright.config.js).

// The WASM engine and ROM file fetches take a while — more room than the
// 10s default in playwright.config.js.
test.describe.configure({ timeout: 20000 });

async function gotoPlayReady(page) {
  await page.goto('./');
  await page.waitForSelector('main');
  // No dedicated "ready" DOM hook — wait for the transient startup status
  // text to clear, which the worker's `{type:"ready"}` message triggers.
  await expect(page.getByText('Starting the emulator')).toHaveCount(0, { timeout: 15000 });
  // The TI-59 boots in real time, as in the apps and on the hardware: a key
  // pressed in its first moments is lost. Give it time to reach the keyboard
  // scan loop.
  await page.waitForTimeout(500);
}

async function pressKey(page, label) {
  await page.getByRole('button', { name: label, exact: true }).click();
  await page.waitForTimeout(200); // the 100 ms minimum hold, then the ROM's reply
}

// The display is a single <canvas> (src/led-display.jsx), not a 12-cell DOM
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

test('the demo page loads the WASM engine with no console errors', async ({ page }) => {
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
  const viaAddition = await settledLedBitmap(page);

  // No DOM text to read off the canvas (see ledBitmap above), so arithmetic
  // correctness is verified by bitmap identity against a second,
  // independently-computed expression with the same result.
  await gotoPlayReady(page);
  for (const key of ['5', '−', '1', '=']) await pressKey(page, key);
  const viaSubtraction = await settledLedBitmap(page);

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

// ── Physical keyboard (Shared/KeyboardMap.cpp, in the worker) ────────────
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

// The display keeps changing for a while after a key: digits fade in and out
// (Shared/DisplayPov) and the C indicator dims smoothly. Any comparison has to
// use a settled frame or it reads that drift as a difference.
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
  await page.waitForTimeout(400); // a two-code binding is two taps of 100 ms + the scan-loop wait
}

test('typing 2 + 2 = drives the emulation core', async ({ page }) => {
  await gotoPlayReady(page);
  await focusCalculator(page);

  const before = await settledLedBitmap(page);
  for (const key of ['2', '+', '2', '=']) await typeKey(page, key);

  expect(await settledLedBitmap(page)).not.toBe(before);
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
  expect(await settledLedBitmap(page)).toBe(before);

  // ...and the calculator is still listening: a bound key still works.
  await typeKey(page, '5');
  expect(await settledLedBitmap(page)).not.toBe(before);
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

  expect(await settledLedBitmap(page)).toBe(before);
});

test('the standalone app does not capture keystrokes', async ({ page }) => {
  await page.goto('app/index.html');
  await expect(page.getByText('Starting the emulator')).toHaveCount(0, { timeout: 15000 });

  // PlayCalculator is mounted without the keyboard prop.
  expect(await page.locator('.calcu-device').getAttribute('tabindex')).toBeNull();
});

test('loading the Base Conversion preset shows its own cue card', async ({ page }) => {
  await gotoPlayReady(page);

  await page.locator('select').nth(1).selectOption({ label: 'Base conversion' });
  await page.waitForTimeout(1000);

  await expect(page.locator('.cuecard')).toHaveCount(1);
  await expect(page.locator('.cuecard')).toContainText('Base Conversion');
});

// ── Presets and the magnetic card (Shared/SessionController in the worker) ──

async function uploadPreset(page, text) {
  await page.locator('input[type=file]').setInputFiles({
    name: 'test.ti59', mimeType: 'text/plain', buffer: Buffer.from(text),
  });
  await page.waitForTimeout(500);
}

// Lbl A 1 2 3 R/S: pressing A shows 123.
const PROGRAM_123 = 'PROGRAM:\n76 11 01 02 03 91\n';

async function displayAfterA(page) {
  await pressKey(page, 'A');
  return settledLedBitmap(page);
}

test('a SKIP-RESET preset keeps the program in memory', async ({ page }) => {
  await gotoPlayReady(page);
  await uploadPreset(page, PROGRAM_123);
  const expected = await displayAfterA(page);

  await uploadPreset(page, 'SKIP-RESET: on\nREGISTERS:\n05 = 1\n');
  await pressKey(page, 'CLR');
  expect(await displayAfterA(page)).toBe(expected);
});

test('Queue Card writes the program and reads it back', async ({ page }) => {
  await gotoPlayReady(page);
  await uploadPreset(page, PROGRAM_123);
  await uploadPreset(page, 'SKIP-RESET: on\nKEYSTROKES:\n82 21 91\n');  // 1 2nd Write
  await page.waitForTimeout(1000);
  await page.getByRole('button', { name: 'Queue Card' }).click();  // the card passes: written
  await page.waitForTimeout(2000);

  await uploadPreset(page, 'PARTITION: 479\n');  // a fresh machine: no program
  await page.waitForTimeout(1000);
  await page.getByRole('button', { name: 'Queue Card' }).click();  // read it back
  await page.waitForTimeout(2000);
  await pressKey(page, 'CLR');
  const readBack = await displayAfterA(page);

  await uploadPreset(page, PROGRAM_123);
  expect(readBack).toBe(await displayAfterA(page));
});

// ── The standalone app (app/) ─────────────────────────────────────────────

test('the standalone app precaches its files for offline use', async ({ page }) => {
  await page.goto('app/');
  await expect(page.getByText('Starting the emulator')).toHaveCount(0, { timeout: 15000 });

  // cache.addAll() rejects if any precached path is wrong, and the worker
  // then never activates — so an active worker plus a full cache means every
  // relative path resolved under this base URL.
  const cached = await page.evaluate(async () => {
    const reg = await navigator.serviceWorker.ready;
    const names = await caches.keys();
    const name = names.find((n) => n.startsWith(`calcu59-app ${reg.scope} `));
    return name ? (await (await caches.open(name)).keys()).map((r) => r.url) : [];
  });
  expect(cached).toContain(new URL('../calc.js', page.url()).href);
  expect(cached).toContain(new URL('../wasm/ti59-core.wasm', page.url()).href);
});
