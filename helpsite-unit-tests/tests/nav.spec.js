const { test, expect } = require('@playwright/test');

// Helper: navigate to a real path and wait for React to render.
async function goto(page, path) {
  await page.goto(path);
  await page.waitForSelector('main');
}

// ── Nav links ────────────────────────────────────────────────
test('home loads by default', async ({ page }) => {
  await goto(page, '/');
  await expect(page.locator('h1')).toContainText('Calc-U');
});

test('Overview nav link → home', async ({ page }) => {
  await goto(page, '/debugger/');
  await page.click("nav a[href='/']");
  await expect(page).toHaveURL(/\/$/);
  await expect(page.locator('h1')).toContainText('Calc-U');
});

test('Getting Started nav link', async ({ page }) => {
  await goto(page, '/');
  await page.click("a[href='/getting-started/']");
  await expect(page).toHaveURL(/\/getting-started\/$/);
  await expect(page.locator('main')).toBeVisible();
});

test('App Reference nav link', async ({ page }) => {
  await goto(page, '/');
  await page.click("a[href='/reference/']");
  await expect(page).toHaveURL(/\/reference\/$/);
  await expect(page.locator('h1')).toContainText('annotated');
});

test('FAQ nav link', async ({ page }) => {
  await goto(page, '/');
  await page.click("a[href='/faq/']");
  await expect(page).toHaveURL(/\/faq\/$/);
  await expect(page.locator('h1')).toContainText('FAQ');
});

test('Modules nav link → stub page (not blank)', async ({ page }) => {
  await goto(page, '/');
  await page.click("a[href='/modules/']");
  await expect(page).toHaveURL(/\/modules\/$/);
  await expect(page.locator('main')).toBeVisible();
});

// ── Brand logo ───────────────────────────────────────────────
test('brand logo returns to home', async ({ page }) => {
  await goto(page, '/faq/');
  await page.click('a.brand');
  await expect(page).toHaveURL(/\/$/);
});

// ── Deep links ────────────────────────────────────────────────
test('deep link to /debugger/ loads correct page', async ({ page }) => {
  await goto(page, '/debugger/');
  await expect(page.locator('h1')).toContainText('debugger');
});

// ── Legacy #hash redirects ───────────────────────────────────
// routes.js's LEGACY_HASHES exists so old bookmarks and shared links to the
// pre-migration site (#faq, #debugger, ...) keep working: site.jsx rewrites
// them to the new real path with location.replace before React ever renders.
test('legacy #faq hash redirects to /faq/', async ({ page }) => {
  await page.goto('/index.html#faq');
  await page.waitForURL(/\/faq\/$/);
  await expect(page.locator('h1')).toContainText('FAQ');
});

test('legacy #start/printer hash redirects to /getting-started/printer/', async ({ page }) => {
  await page.goto('/index.html#start/printer');
  await page.waitForURL(/\/getting-started\/printer\/$/);
  await expect(page.locator('main')).toBeVisible();
});

test('unrecognized hash on index.html renders the home page', async ({ page }) => {
  // Not in LEGACY_HASHES, so there is no redirect target; the pathname
  // itself (/index.html) doesn't match a route either, so the router falls
  // back to home.
  await page.goto('/index.html#completely-unknown-page');
  await page.waitForSelector('main');
  await expect(page.locator('h1')).toContainText('Calc-U');
});

// ── Browser back / forward ───────────────────────────────────
test('browser Back returns to previous page', async ({ page }) => {
  await goto(page, '/');
  await page.click("a[href='/reference/']");
  await page.waitForURL(/\/reference\/$/);
  await page.goBack();
  await page.waitForURL(/\/$/);
});

test('browser Forward restores next page', async ({ page }) => {
  await goto(page, '/');
  await page.click("a[href='/faq/']");
  await page.waitForURL(/\/faq\/$/);
  await page.goBack();
  await page.waitForURL(/\/$/);
  await page.goForward();
  await expect(page).toHaveURL(/\/faq\/$/);
});

// ── Back buttons on detail pages ─────────────────────────────
test('"← Return to start" button uses browser history', async ({ page }) => {
  await goto(page, '/');
  await goto(page, '/debugger/');   // real navigation, creates a history entry
  await page.click('button.btn.secondary');
  await expect(page).toHaveURL(/\/$/);
});

// ── GettingStartedPage sub-topics ────────────────────────────
test('sidebar sub-topic updates path', async ({ page }) => {
  await goto(page, '/getting-started/');
  await page.click("a[href='/getting-started/printer/']");
  await expect(page).toHaveURL(/\/getting-started\/printer\/$/);
});

test('Back from sub-topic returns to previous sub-topic', async ({ page }) => {
  await goto(page, '/getting-started/install-iphone-ipad/');
  await page.click("a[href='/getting-started/debugger/']");
  await expect(page).toHaveURL(/\/getting-started\/debugger\/$/);
  await page.goBack();
  await expect(page).toHaveURL(/\/getting-started\/install-iphone-ipad\/$/);
});

// ── Nav active-class ─────────────────────────────────────────
test('active nav class matches current page', async ({ page }) => {
  await goto(page, '/faq/');
  const activeLink = page.locator('nav a.active');
  await expect(activeLink).toHaveAttribute('href', '/faq/');
});
