const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

// The website prerenders PlayCalculator server-side, in a sandbox whose
// fetch() and Worker throw: rendering must have no side effects — those
// belong in effects, which a static render never runs (reference/WebClient.md).
// This renders dist/calc.js the same way, in Node; no browser involved.

const WEB = path.join(__dirname, '..');

function sandbox() {
  const noop = () => {};
  const ctx = {
    console, URL, Math, Date, JSON, Uint8Array, TextEncoder, TextDecoder,
    setTimeout, clearTimeout, queueMicrotask,
    location: { href: 'https://example.org/somewhere/', pathname: '/somewhere/' },
    navigator: { userAgent: 'prerender' },
    fetch: () => { throw new Error('fetch() during render'); },
    Worker: function () { throw new Error('new Worker() during render'); },
    document: {
      currentScript: null,
      addEventListener: noop, removeEventListener: noop,
      createElement: () => ({ style: {} }), getElementById: () => null,
    },
  };
  ctx.window = ctx;
  ctx.self = ctx;
  return vm.createContext(ctx);
}

test('PlayCalculator renders server-side without fetch or Worker', async ({}, testInfo) => {
  test.skip(testInfo.project.name !== 'root', 'independent of the base URL');
  const ctx = sandbox();
  const run = (file) => vm.runInContext(fs.readFileSync(file, 'utf8'), ctx, { filename: file });
  run(path.join(WEB, 'vendor', 'react.production.min.js'));
  run(path.join(WEB, 'vendor', 'react-dom-server-legacy.browser.production.min.js'));
  run(path.join(WEB, 'dist', 'calc.js'));

  expect(Object.keys(ctx).filter((k) => /^(CalcKey|CALC_ROWS|CueCard|LedDisplayCanvas)$/.test(k)),
         'calc.js leaks its internals into the global scope').toEqual([]);

  for (const props of [{ controls: true, keyboard: true }, { controls: false }]) {
    const html = ctx.ReactDOMServer.renderToStaticMarkup(ctx.React.createElement(ctx.PlayCalculator, props));
    expect(html).toContain('calcu-device');
    expect(html.match(/<button/g).length).toBe(45 + (props.controls ? 2 : 0));
  }
});
