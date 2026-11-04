const { defineConfig, devices } = require('@playwright/test');

// run-tests.sh serves dist/ at a server root and, on the next port, only
// under a sub-path: the client must work unchanged wherever it is hosted
// (reference/WebClient.md). Every test runs once against each.
const PORT = Number(process.env.CALCU_WEB_PORT || 8059);

module.exports = defineConfig({
  testDir: './tests',
  timeout: 10000,
  use: { headless: true },
  projects: [
    { name: 'root', testIgnore: 'offline.spec.js', use: { ...devices['Desktop Chrome'], baseURL: `http://localhost:${PORT}/` } },
    { name: 'subpath', testIgnore: 'offline.spec.js', use: { ...devices['Desktop Chrome'], baseURL: `http://localhost:${PORT + 1}/anything/calc/` } },
    // The offline start brings its own server, and runs in both engines: the
    // iPhone's installed app is WebKit.
    { name: 'offline-chromium', testMatch: 'offline.spec.js', use: { ...devices['Desktop Chrome'] } },
    { name: 'offline-webkit', testMatch: 'offline.spec.js', use: { ...devices['Desktop Safari'] } },
  ],
});
