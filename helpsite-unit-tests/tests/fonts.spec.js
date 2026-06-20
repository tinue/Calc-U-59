const { test, expect } = require('@playwright/test');

// The only origin allowed is the local test server itself.
// No external CDNs, no Google Fonts, no anything else.
const ALLOWED_ORIGIN = 'http://localhost:8000';

// Font families that must be served locally (woff2 files in docs/fonts/).
const EXPECTED_FONT_FAMILIES = [
  'Archivo',
  'Barlow Condensed',
  'IBM Plex Mono',
  'DSEG7Classic',
];

test('no external font requests are made on page load', async ({ page }) => {
  const externalFontRequests = [];

  const FONT_EXTENSIONS = /\.(woff2?|ttf|otf|eot)(\?.*)?$/i;

  page.on('request', req => {
    const url = req.url();
    const isFontFile = FONT_EXTENSIONS.test(url);
    const isFontService =
      url.includes('fonts.googleapis.com') ||
      url.includes('fonts.gstatic.com') ||
      url.includes('use.typekit') ||
      url.includes('fast.fonts.net');

    if ((isFontFile || isFontService) && !url.startsWith(ALLOWED_ORIGIN)) {
      externalFontRequests.push(url);
    }
  });

  await page.goto('/index.html');
  await page.waitForSelector('main');

  expect(
    externalFontRequests,
    `External font requests detected:\n${externalFontRequests.join('\n')}`
  ).toHaveLength(0);
});

test('no Google Fonts requests on any page', async ({ page }) => {
  const googleFontRequests = [];

  page.on('request', req => {
    const url = req.url();
    if (url.includes('fonts.googleapis.com') || url.includes('fonts.gstatic.com')) {
      googleFontRequests.push(url);
    }
  });

  // Check every page that has a distinct hash route
  const hashes = ['', '#home', '#start', '#ref', '#faq', '#modules', '#debugger'];
  for (const hash of hashes) {
    await page.goto('/index.html' + hash);
    await page.waitForSelector('main');
  }

  expect(
    googleFontRequests,
    `Google Fonts requests detected:\n${googleFontRequests.join('\n')}`
  ).toHaveLength(0);
});

test('font woff2 files are served from local /fonts/ path', async ({ page }) => {
  const fontRequests = [];

  page.on('response', res => {
    const url = res.url();
    if (url.endsWith('.woff2') || url.endsWith('.woff') || url.endsWith('.ttf')) {
      fontRequests.push(url);
    }
  });

  await page.goto('/index.html');
  await page.waitForSelector('main');
  // Trigger rendering of all font families used in the design system
  await page.evaluate(() => document.fonts.ready);

  for (const url of fontRequests) {
    expect(url, `Font loaded from unexpected origin: ${url}`).toMatch(
      new RegExp(`^${ALLOWED_ORIGIN}`)
    );
    expect(url, `Font not under /fonts/ path: ${url}`).toContain('/fonts/');
  }
});

test('all required font families are available after load', async ({ page }) => {
  await page.goto('/index.html');
  await page.waitForSelector('main');

  const missingFamilies = await page.evaluate(async (families) => {
    // Explicitly trigger loading for each family/weight so the browser fetches
    // the woff2 even if no element on the page currently uses that variant.
    await Promise.allSettled(families.map(f => document.fonts.load(`600 16px "${f}"`)));
    await document.fonts.ready;
    return families.filter(family => !document.fonts.check(`600 16px "${family}"`));
  }, EXPECTED_FONT_FAMILIES);

  expect(
    missingFamilies,
    `Font families not loaded: ${missingFamilies.join(', ')}`
  ).toHaveLength(0);
});
