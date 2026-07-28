const { test, expect } = require('@playwright/test');

// The WASM module + ROM/module JSON fetches take longer than the site's
// other pages (which are pure static HTML) — give #play tests more room
// than the 10s default in playwright.config.js.
test.describe.configure({ timeout: 20000 });

async function gotoPlayReady(page) {
  await page.goto('/index.html#play');
  await page.waitForSelector('main');
  // No dedicated "ready" DOM hook — wait for the transient startup status
  // text to clear, which the worker's `{type:"ready"}` message triggers.
  await expect(page.getByText('Starting the emulator')).toHaveCount(0, { timeout: 15000 });
}

async function pressKey(page, label) {
  await page.getByRole('button', { name: label, exact: true }).click();
  await page.waitForTimeout(200); // matches the worker's press/release pacing
}

// The display is a 12-cell grid (docs/PlayCalculator.jsx's <LedCell>), not
// a single text string — read cell-by-cell in DOM order (which matches
// left-to-right visual order) and reassemble, dots included. The "C"
// (calculate) indicator is its own 4-bar shape (.led-cell-c), not a text
// glyph, so it's represented here as a literal "C" for readability.
async function readLedText(page) {
  return page.evaluate(() => {
    let out = '';
    for (const cell of document.querySelectorAll('.led-cell')) {
      if (cell.querySelector('.led-cell-c')) {
        out += 'C';
      } else if (cell.querySelector('.led-cell-7')) {
        out += '7';
      } else {
        out += cell.querySelector('.led-cell-fg')?.textContent ?? '';
      }
      if (cell.querySelector('.led-cell-dot')) out += '.';
    }
    return out;
  });
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

  await pressKey(page, '2');
  await pressKey(page, '+');
  await pressKey(page, '2');
  await pressKey(page, '=');
  await page.waitForTimeout(300);

  expect((await readLedText(page)).trim()).toBe('4.');
});

test('the C (calculate) indicator lights the leftmost cell while a program runs', async ({ page }) => {
  await gotoPlayReady(page);

  await page.locator('select').nth(1).selectOption({ label: 'Calculator diagnostic' });
  await page.waitForTimeout(1000);
  await pressKey(page, 'E'); // diag.ti59's own documented "press E to start"

  const duringRun = await readLedText(page);
  expect(duringRun.startsWith('C')).toBe(true);
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
// The cue card is the assertion target rather than the display: the LED is a
// <canvas>, so there is no DOM text to read, but "2nd, Pgm, 01" puts a cue card
// in the DOM and only does so if the keys actually reached the emulation core.

// Focus without clicking — a click would land on a key and press it.
async function focusCalculator(page) {
  await page.locator('.calcu-device').focus();
}

async function typeKey(page, key) {
  await page.keyboard.press(key);
  await page.waitForTimeout(250); // covers the 80 ms hold + 120 ms gap per code
}

test('typing 2nd Pgm 01 on the keyboard shows the cue card', async ({ page }) => {
  await gotoPlayReady(page);
  await focusCalculator(page);

  await typeKey(page, "'");  // 2nd
  await typeKey(page, 'l');  // LRN, whose 2nd-function is Pgm
  await typeKey(page, '0');
  await typeKey(page, '1');
  await page.waitForTimeout(300);

  await expect(page.locator('.cuecard')).toContainText('MASTER LIBRARY DIAGNOSTIC');
});

test('Shift+letter is shorthand for 2nd then that key', async ({ page }) => {
  await gotoPlayReady(page);
  await focusCalculator(page);

  // Shift+L alone should do what "'" then "l" did above.
  await page.keyboard.press('Shift+L');
  await page.waitForTimeout(500);  // two full taps, not one
  await typeKey(page, '0');
  await typeKey(page, '1');
  await page.waitForTimeout(300);

  await expect(page.locator('.cuecard')).toContainText('MASTER LIBRARY DIAGNOSTIC');
});

test('keystrokes are ignored until the calculator has focus', async ({ page }) => {
  await gotoPlayReady(page);

  // No focusCalculator() here — the page never auto-focuses it.
  await typeKey(page, "'");
  await typeKey(page, 'l');
  await typeKey(page, '0');
  await typeKey(page, '1');
  await page.waitForTimeout(300);

  await expect(page.locator('.cuecard')).toHaveCount(0);
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
