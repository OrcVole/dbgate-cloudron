// Single-page-application screenshot capture. The plain `--screenshot` flag captures on
// the load event, which for a Svelte SPA like DbGate is the "Loading..." splash, not the
// rendered app. Drive a real browser instead and wait for the splash to clear and real
// controls to exist. Copied from the Speaches package's working recipe and generalised:
// that one waited for Gradio-specific "Loading" text, this one waits for a generic
// element-count threshold since DbGate's splash markup is not yet characterised.
const puppeteer = require('puppeteer-core');
(async () => {
  const [url, out] = [process.argv[2], process.argv[3]];
  const browser = await puppeteer.launch({
    executablePath: '/usr/bin/chromium-browser',
    args: ['--no-sandbox', '--disable-gpu', '--hide-scrollbars'],
    defaultViewport: { width: 1280, height: 800 },
  });
  const page = await browser.newPage();
  await page.goto(url, { waitUntil: 'networkidle2', timeout: 120000 });
  try {
    await page.waitForFunction(
      () => document.querySelectorAll('button, input, a, [class*="app"], [class*="login"]').length > 3,
      { timeout: 90000 });
  } catch (e) { console.error('render wait timed out, capturing anyway'); }
  await new Promise(r => setTimeout(r, 3000));
  await page.screenshot({ path: out });
  console.error('captured');
  await browser.close();
})();
