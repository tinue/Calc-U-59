const { test, expect } = require('@playwright/test');

// The web client end to end through the real WASM engine, on dist/index.html
// (PlayCalculator with the physical keyboard; ?layout=wide|portrait) and
// dist/app/. URLs are relative to the project's baseURL — the server root or
// a sub-path (playwright.config.js).

test.describe.configure({ timeout: 30000 });

async function gotoReady(page, query = 'layout=wide') {
  await page.goto(`./?${query}`);
  // The key buttons appear once the worker has posted its static data.
  await expect(page.locator('.calcu-key')).toHaveCount(45, { timeout: 15000 });
  // The calculator boots in real time, as the hardware: a key pressed in its
  // first moments is lost. Give it time to reach the keyboard scan loop.
  await page.waitForTimeout(600);
}

async function pressKey(page, label) {
  await page.getByRole('button', { name: label, exact: true }).click();
  await page.waitForTimeout(200); // the 100 ms minimum hold, then the ROM's reply
}

async function pressKeys(page, labels) {
  for (const l of labels) await pressKey(page, l);
}

// The display is a canvas: compare rendered bitmaps instead of reading text.
// Digits fade in and out (Shared/DisplayPov), so wait for a settled frame.
async function settledLed(page) {
  const led = page.locator('canvas.calcu-led');
  let previous = await led.evaluate((c) => c.toDataURL());
  for (let i = 0; i < 20; i++) {
    await page.waitForTimeout(250);
    const current = await led.evaluate((c) => c.toDataURL());
    if (current === previous) return current;
    previous = current;
  }
  throw new Error('LED display never settled');
}

async function showing(page, labels) {
  await pressKey(page, 'CLR');
  await pressKeys(page, labels);
  return settledLed(page);
}

// A point in the artwork, as fractions of the canvas, in page coordinates.
async function facePoint(page, nx, ny) {
  const box = await page.locator('canvas.calcu-keyboard').boundingBox();
  return { x: box.x + nx * box.width, y: box.y + ny * box.height };
}

async function keyRect(page, label) {
  return page.getByRole('button', { name: label, exact: true }).boundingBox();
}

async function uploadPreset(page, text, name = 'test.ti59') {
  await page.getByRole('button', { name: 'Preset' }).click();
  await page.locator('.calcu-dialog input[type=file]').setInputFiles({
    name, mimeType: 'text/plain', buffer: Buffer.from(text),
  });
  await page.waitForTimeout(600);
}

// Lbl A 1 2 3 R/S: pressing A shows 123.
const PROGRAM_123 = 'PROGRAM:\n76 11 01 02 03 91\n';

// ── Start-up ─────────────────────────────────────────────────────────────

test('both layouts load the engine with no console errors', async ({ page }) => {
  const errors = [];
  page.on('pageerror', (err) => errors.push(err.message));
  page.on('console', (msg) => { if (msg.type() === 'error') errors.push(msg.text()); });
  await gotoReady(page, 'layout=wide');
  await expect(page.locator('[data-layout=wide] [data-panel=printer]')).toBeVisible();
  await expect(page.locator('[data-panel=debug]')).toBeVisible();
  await gotoReady(page, 'layout=portrait');
  await expect(page.locator('[data-layout=portrait]')).toBeVisible();
  await expect(page.locator('[data-panel=debug]')).toHaveCount(0);
  expect(errors, `Console/page errors:\n${errors.join('\n')}`).toHaveLength(0);
});

// ── Keys ─────────────────────────────────────────────────────────────────

test('2 + 3 = computes through the real emulation core', async ({ page }) => {
  await gotoReady(page, 'layout=portrait');
  // Results against results: an entry shows no decimal point, a result does.
  const five = await showing(page, ['5', '=']);
  expect(await showing(page, ['2', '+', '3', '='])).toBe(five);
  expect(five).not.toBe(await showing(page, ['6', '=']));
});

test('a press just outside a key hits it (widened hit test)', async ({ page }) => {
  await gotoReady(page);
  const seven = await showing(page, ['7']);
  await pressKey(page, 'CLR');
  const r = await keyRect(page, '7');
  await page.mouse.click(r.x + r.width / 2, r.y - r.height * 0.2);  // within the 35 % expansion
  expect(await settledLed(page)).toBe(seven);
});

test('dragging moves the press to the key under the pointer', async ({ page }) => {
  await gotoReady(page);
  const eight = await showing(page, ['8']);
  await pressKey(page, 'CLR');
  const a = await keyRect(page, '7'), b = await keyRect(page, '8');
  await page.mouse.move(a.x + a.width / 2, a.y + a.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(30);
  await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2, { steps: 4 });
  await page.waitForTimeout(250);
  await page.mouse.up();
  // 7 was let go before the ROM's debounce took it: only 8 is entered... or 7
  // then 8. Either way the last digit entered is 8, and the drag ended on it.
  await expect(page.getByRole('button', { name: '8', exact: true })).toHaveAttribute('aria-pressed', 'false');
  const shown = await settledLed(page);
  expect([eight, await showing(page, ['7', '8'])]).toContain(shown);
});

test('holding the display runs at full speed', async ({ page }) => {
  await gotoReady(page);
  const p = await facePoint(page, 0.5, 0.075);
  await page.mouse.move(p.x, p.y);
  await page.mouse.down();
  await expect(page.locator('.calcu-face')).toHaveAttribute('data-full-speed', 'true');
  await page.mouse.up();
  await expect(page.locator('.calcu-face')).toHaveAttribute('data-full-speed', 'false');
});

test('the pressed key is shown pressed', async ({ page }) => {
  await gotoReady(page);
  const r = await keyRect(page, '5');
  await page.mouse.move(r.x + r.width / 2, r.y + r.height / 2);
  await page.mouse.down();
  await expect(page.getByRole('button', { name: '5', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await page.mouse.up();
  await expect(page.getByRole('button', { name: '5', exact: true })).toHaveAttribute('aria-pressed', 'false');
});

// ── Physical keyboard (Shared/KeyboardMap.cpp, in the worker) ────────────

async function typeKeys(page, keys) {
  for (const k of keys) {
    await page.keyboard.press(k);
    await page.waitForTimeout(400); // a two-code binding is two taps of 100 ms + the scan-loop wait
  }
}

test('typing 2 + 3 = matches clicking', async ({ page }) => {
  await gotoReady(page);
  const five = await showing(page, ['5', '=']);
  await pressKey(page, 'CLR');
  await page.locator('.calcu-device').focus();
  await typeKeys(page, ['2', '+', '3', '=']);
  expect(await settledLed(page)).toBe(five);
});

test('keystrokes are ignored until the calculator has focus', async ({ page }) => {
  await gotoReady(page);
  const before = await settledLed(page);
  await typeKeys(page, ['2', '+', '2', '=']);
  expect(await settledLed(page)).toBe(before);
});

test('Shift+A sends 2nd before A', async ({ page }) => {
  await gotoReady(page);
  await page.locator('.calcu-device').focus();
  await page.keyboard.press('Shift+A');
  await expect(page.getByRole('button', { name: '2nd', exact: true })).toHaveAttribute('aria-pressed', 'true', { timeout: 300 });
});

// ── Models, modules, cue cards ───────────────────────────────────────────

test('2nd Pgm 01 shows the Master Library diagnostic cue card', async ({ page }) => {
  await gotoReady(page);
  await pressKeys(page, ['2nd', 'LRN', '0', '1']);  // LRN's 2nd function is Pgm
  await expect(page.locator('.cuecard')).toHaveAttribute('aria-label', /MASTER LIBRARY DIAGNOSTIC/);
});

test('switching models: TI-58C has no card reader and keeps its constant memory', async ({ page }) => {
  await gotoReady(page);
  await expect(page.getByRole('button', { name: 'Crd' }).first()).toBeVisible();
  await page.getByLabel('Calculator model').selectOption({ label: 'TI-58C' });
  await expect(page.getByLabel('Calculator model')).toHaveValue('2');
  await expect(page.getByRole('button', { name: 'Crd' })).toHaveCount(0);
  await page.waitForTimeout(1500);  // the TI-58C boots
  const seven = await showing(page, ['7', '=']);
  await pressKeys(page, ['STO', '1', '2', 'CLR']);
  await page.waitForTimeout(1000);  // the 0.5 s persist debounce

  // The startup model is the last used; the constant memory survives.
  await gotoReady(page);
  await expect(page.getByLabel('Calculator model')).toHaveValue('2');
  await page.waitForTimeout(1500);
  expect(await showing(page, ['RCL', '1', '2'])).toBe(seven);
});

test('Settings: startup model and module are kept', async ({ page }) => {
  await gotoReady(page);
  await page.getByRole('button', { name: 'Settings' }).click();
  await page.getByLabel('Startup Calculator').selectOption({ label: 'TI-58' });
  await page.getByRole('button', { name: 'Done' }).click();
  await gotoReady(page);
  await expect(page.getByLabel('Calculator model')).toHaveValue('1');
});

// ── Presets ──────────────────────────────────────────────────────────────

test('a bundled preset shows its own cue card', async ({ page }) => {
  await gotoReady(page);
  await page.getByRole('button', { name: 'Preset' }).click();
  await page.getByRole('button', { name: /Base conversion/ }).click();
  await expect(page.locator('.cuecard')).toHaveAttribute('aria-label', /Base Conversion/, { timeout: 5000 });
});

test('an uploaded preset loads its program', async ({ page }) => {
  await gotoReady(page);
  const expected = await showing(page, ['1', '2', '3']);
  await uploadPreset(page, PROGRAM_123);
  await pressKey(page, 'A');
  expect(await settledLed(page)).toBe(expected);
});

test('a preset dropped on the calculator loads', async ({ page }) => {
  await gotoReady(page);
  const expected = await showing(page, ['1', '2', '3']);
  await pressKey(page, 'CLR');
  const dt = await page.evaluateHandle((text) => {
    const d = new DataTransfer();
    d.items.add(new File([text], 'drop.ti59'));
    return d;
  }, PROGRAM_123);
  await page.locator('.calcu-face').dispatchEvent('dragover', { dataTransfer: dt });
  await page.locator('.calcu-face').dispatchEvent('drop', { dataTransfer: dt });
  await page.waitForTimeout(800);
  await pressKey(page, 'A');
  expect(await settledLed(page)).toBe(expected);
});

// ── Magnetic cards (session folder) ──────────────────────────────────────

test('a blank card is written, listed, and read back', async ({ page }) => {
  await gotoReady(page);
  await uploadPreset(page, PROGRAM_123);
  const expected = await (async () => { await pressKey(page, 'A'); return settledLed(page); })();

  // The same program again, then CLR 1 2nd Write: waits for a card.
  await uploadPreset(page, PROGRAM_123 + 'KEYSTROKES:\n25 82 21 91\n');
  await page.waitForTimeout(1000);
  await page.getByRole('button', { name: 'Crd' }).nth(1).click();  // a blank card passes: written
  await page.getByLabel('Card name').fill('prog');
  await page.getByRole('button', { name: 'Save' }).click();
  // In the reader until the write is done, then ejected (and saved).
  await expect(page.getByRole('button', { name: 'Eject Card' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Eject Card' })).toHaveCount(0, { timeout: 15000 });

  await uploadPreset(page, 'PARTITION: 479\n');  // a fresh machine: no program
  await page.getByRole('button', { name: 'Crd' }).first().click();  // read
  await page.getByRole('button', { name: 'prog.U59', exact: true }).click();
  await page.getByRole('button', { name: 'Read', exact: true }).click();
  await page.waitForTimeout(3000);
  await pressKey(page, 'CLR');
  await pressKey(page, 'A');
  expect(await settledLed(page)).toBe(expected);
});

// ── Printer ──────────────────────────────────────────────────────────────

test('the printer prints, shows text, and cuts', async ({ page }) => {
  await gotoReady(page);
  const printer = page.locator('[data-panel=printer]');
  // Connected from the start, as in the apps.
  await expect(printer.getByRole('button', { name: /PC-100C/ })).toHaveAttribute('aria-pressed', 'true');
  await pressKeys(page, ['4', '2', '2nd', '+/-']);  // 42 Prt
  await expect(printer.getByRole('button', { name: 'Cut' })).toBeEnabled({ timeout: 5000 });
  await printer.getByRole('button', { name: 'Text view' }).click();
  await expect(printer.locator('.calcu-paper-text')).toContainText('42.');
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await printer.getByRole('button', { name: 'Cut' }).click();
  await expect(printer.getByRole('button', { name: 'Cut' })).toBeDisabled();
});

test('portrait: the chevron switches to the printer page and back', async ({ page }) => {
  await gotoReady(page, 'layout=portrait');
  await expect(page.locator('[data-panel=printer]')).toHaveCount(0);
  await page.getByRole('button', { name: 'Printer' }).click();
  await expect(page.locator('[data-panel=printer]')).toBeVisible();
  await page.getByRole('button', { name: 'Calculator' }).click();
  await expect(page.locator('canvas.calcu-keyboard')).toBeVisible();
});

// ── Debugger (wide) ──────────────────────────────────────────────────────

test('FREEZE, STEP and RESUME on the CALCULATOR tab', async ({ page }) => {
  await gotoReady(page);
  const debug = page.locator('[data-panel=debug]');
  await debug.getByRole('button', { name: 'FREEZE', exact: true }).click();
  await expect(debug.getByRole('button', { name: 'RESUME' })).toBeEnabled();
  await expect(debug.getByText(/← next/)).toBeVisible();
  await debug.getByRole('button', { name: 'RESUME' }).click();
  await expect(debug.getByRole('button', { name: 'RESUME' })).toBeDisabled();
});

test('a manual trace is downloaded when switched off', async ({ page }) => {
  await gotoReady(page);
  const debug = page.locator('[data-panel=debug]');
  await debug.getByRole('tab', { name: 'LOG' }).click();
  await debug.getByRole('button', { name: /^TRACE/ }).click();
  await pressKeys(page, ['1', '+', '1', '=']);
  const download = page.waitForEvent('download');
  await debug.getByRole('button', { name: /^TRACE/ }).click();
  const d = await download;
  expect(d.suggestedFilename()).toBe('CALCU59_TRACE.bin');
  expect((await (await d.createReadStream()).toArray()).reduce((n, b) => n + b.length, 0)).toBeGreaterThan(1000);
});

// ── The standalone app (app/) ────────────────────────────────────────────

test('the standalone app is portrait and precaches all three models', async ({ page }) => {
  await page.goto('app/');
  await expect(page.locator('.calcu-key')).toHaveCount(45, { timeout: 15000 });
  await expect(page.locator('[data-layout=portrait]')).toBeVisible();

  // cache.addAll() rejects if any precached path is wrong, and the worker
  // then never activates — so an active worker plus a full cache means every
  // relative path resolved under this base URL.
  const cached = await page.evaluate(async () => {
    const reg = await navigator.serviceWorker.ready;
    const names = await caches.keys();
    const name = names.find((n) => n.startsWith(`calcu59-app ${reg.scope} `));
    return name ? (await (await caches.open(name)).keys()).map((r) => r.url) : [];
  });
  for (const f of ['../calc.js', '../wasm/ti59-core.wasm', '../img/ti58_base.png', '../wasm/roms/CD2400.txt']) {
    expect(cached).toContain(new URL(f, page.url()).href);
  }
});
