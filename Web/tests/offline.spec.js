const { test, expect } = require('@playwright/test');
const fs = require('fs');
const http = require('http');
const path = require('path');

// The installed app started from nothing without a connection: a new page
// after the server is gone, so the worker, its scripts, the WASM and the ROMs
// can only come from the service worker. This test has its own server: with
// context.setOffline() the browser's HTTP cache still answers what the service
// worker doesn't, and hides a file it fails to serve. no-store keeps that
// cache out of it. Also runs in WebKit, the engine of the iPhone's installed
// app (playwright.config.js).

test.describe.configure({ timeout: 60000 });

const DIST = path.join(__dirname, '..', 'dist');
const PREFIX = '/anything/calc/';
const TYPES = {
  '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.woff2': 'font/woff2', '.txt': 'text/plain',
};

function serveDist() {
  const server = http.createServer((req, res) => {
    let url = decodeURIComponent(req.url.split('?')[0]);
    if (url.endsWith('/')) url += 'index.html';
    const file = path.join(DIST, url.slice(PREFIX.length));
    if (!url.startsWith(PREFIX) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404);
      res.end();
      return;
    }
    res.writeHead(200, {
      'content-type': TYPES[path.extname(file)] || 'application/octet-stream',
      'cache-control': 'no-store',
    });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, () => resolve(server)));
}

function stop(server) {
  server.closeAllConnections();
  return new Promise((resolve) => server.close(resolve));
}

test('the installed app starts without a connection and runs every model', async ({ page, context }) => {
  const server = await serveDist();
  const appUrl = `http://localhost:${server.address().port}${PREFIX}app/`;

  await page.goto(appUrl);
  await expect(page.locator('.calcu-key')).toHaveCount(45, { timeout: 30000 });
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.close();
  await stop(server);

  const app = await context.newPage();
  await app.goto(appUrl);
  await expect(app.locator('.calcu-key')).toHaveCount(45, { timeout: 30000 });

  // A model or module not started with is read later, by a synchronous request.
  const model = app.getByLabel('Calculator model');
  for (const name of ['TI-58C', 'TI-58', 'TI-59']) {
    await model.selectOption({ label: name });
    await expect(model).toHaveValue(await model.locator(`option:text-is("${name}")`).getAttribute('value'));
    await app.waitForTimeout(500);
    await expect(app.locator('.calcu-key')).toHaveCount(45);
  }
  await expect(app.locator('.calcu-status, [role=status]')).toHaveCount(0);

  await app.getByRole('button', { name: 'Settings' }).click();
  await app.getByLabel('Solid State Module').selectOption({ label: 'Applied Statistics' });
  await app.getByRole('button', { name: 'Done' }).click();
  await app.waitForTimeout(1000);
  // A module whose image can't be read is not selected: the dialog would still show ML.
  await app.getByRole('button', { name: 'Settings' }).click();
  await expect(app.getByLabel('Solid State Module')).toHaveValue('ST');
});
