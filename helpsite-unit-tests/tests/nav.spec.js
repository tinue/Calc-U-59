const { test, expect } = require('@playwright/test');

const BASE = '/index.html';

// Helper: navigate and wait for React to render
async function goto(page, hash) {
  await page.goto(BASE + (hash ? '#' + hash : ''));
  await page.waitForSelector('main');
}

// ── Nav links ────────────────────────────────────────────────
test('home loads by default (empty hash)', async ({ page }) => {
  await goto(page, '');
  // Empty hash normalizes to #home on initial load
  await page.waitForURL(/#home/);
  await expect(page.locator('h1')).toContainText('Calc-U');
});

test('Overview nav link → home', async ({ page }) => {
  await goto(page, 'debugger');
  await page.click("a[href='#home']");
  await expect(page).toHaveURL(/#home/);
  await expect(page.locator('h1')).toContainText('Calc-U');
});

test('Getting Started nav link', async ({ page }) => {
  await goto(page, '');
  await page.click("a[href='#start']");
  await expect(page).toHaveURL(/#start/);
  await expect(page.locator('main')).toBeVisible();
});

test('App Reference nav link', async ({ page }) => {
  await goto(page, '');
  await page.click("a[href='#ref']");
  await expect(page).toHaveURL(/#ref/);
  await expect(page.locator('h1')).toContainText('annotated');
});

test('FAQ nav link', async ({ page }) => {
  await goto(page, '');
  await page.click("a[href='#faq']");
  await expect(page).toHaveURL(/#faq/);
  await expect(page.locator('h1')).toContainText('FAQ');
});

test('Modules nav link → stub page (not blank)', async ({ page }) => {
  await goto(page, '');
  await page.click("a[href='#modules']");
  await expect(page).toHaveURL(/#modules/);
  await expect(page.locator('main')).toBeVisible();
});

// ── Brand logo ───────────────────────────────────────────────
test('brand logo returns to home', async ({ page }) => {
  await goto(page, 'faq');
  await page.click('a.brand');
  await expect(page).toHaveURL(/#home/);
});

// ── Hash / deep link ─────────────────────────────────────────
test('deep link to #debugger loads correct page', async ({ page }) => {
  await goto(page, 'debugger');
  await expect(page.locator('h1')).toContainText('debugger');
});

test('unknown hash falls back to home', async ({ page }) => {
  await page.goto(BASE + '#completely-unknown-page');
  await page.waitForSelector('main');
  // Unknown page hash renders home page content (without redirecting the hash)
  await expect(page.locator('h1')).toContainText('Calc-U');
});

// ── Browser back / forward ───────────────────────────────────
test('browser Back returns to previous page', async ({ page }) => {
  // Navigate to create history: home → ref → back → home
  await goto(page, 'home');
  await page.click("a[href='#ref']");  // click App Reference nav link
  await page.waitForURL(/#ref/);
  await page.goBack();
  await page.waitForURL(/#home/);
});

test('browser Forward restores next page', async ({ page }) => {
  await goto(page, 'home');
  await page.click("a[href='#faq']");
  await page.goBack();
  await page.goForward();
  await expect(page).toHaveURL(/#faq/);
});

// ── Back buttons on detail pages ─────────────────────────────
test('"← Return to start" button uses browser history', async ({ page }) => {
  await goto(page, 'home');
  await goto(page, 'debugger');          // creates a history entry
  await page.click('button.btn.secondary');
  await expect(page).toHaveURL(/#home/);
});

// ── GettingStartedPage sub-topics ────────────────────────────
test('sidebar sub-topic updates hash', async ({ page }) => {
  await goto(page, 'start');
  await page.click("a[href='#start/printer']");
  await expect(page).toHaveURL(/#start\/printer/);
});

test('Back from sub-topic returns to previous sub-topic', async ({ page }) => {
  await goto(page, 'start/install-mobile');
  await page.click("a[href='#start/debugger']");
  await expect(page).toHaveURL(/#start\/debugger/);
  await page.goBack();
  await expect(page).toHaveURL(/#start\/install-mobile/);
});

// ── Nav active-class ─────────────────────────────────────────
test('active nav class matches current page', async ({ page }) => {
  await goto(page, 'faq');
  const activeLink = page.locator('nav a.active');
  await expect(activeLink).toHaveAttribute('href', '#faq');
});
