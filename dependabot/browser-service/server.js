// browser-service/server.js
// Tiny HTTP server that uses Playwright to fetch JavaScript-rendered pages.
// Ballerina calls this for known SPA domains that reject plain HTTP requests.
//
// Setup:
//   npm install playwright express
//   npx playwright install chromium
//   node server.js
//
// Usage:
//   GET http://localhost:3456/fetch?url=https://developers.zoom.us/docs/api/meetings/
//
// Returns JSON:
//   { "html": "<rendered HTML content>" }
//   { "error": "error message" }

const express = require("express");
const { chromium } = require("playwright");

const app = express();
const PORT = 3456;

// Maximum simultaneous Playwright pages. Keeping this low avoids memory
// pressure and tab contention when many connectors run in the same batch.
const MAX_CONCURRENT_PAGES = 3;
let activePages = 0;
const waitQueue = [];

function acquirePage() {
  if (activePages < MAX_CONCURRENT_PAGES) {
    activePages++;
    return Promise.resolve();
  }
  return new Promise((resolve) => waitQueue.push(resolve));
}

function releasePage() {
  activePages--;
  if (waitQueue.length > 0) {
    const next = waitQueue.shift();
    activePages++;
    next();
  }
}

let browser = null;

// Launch browser once on startup
async function getBrowser() {
  if (!browser) {
    browser = await chromium.launch({
      headless: true,
      args: [
        "--no-sandbox",
        "--disable-setuid-sandbox",
        "--disable-dev-shm-usage",
        "--disable-gpu",
      ],
    });
  }
  return browser;
}

app.get("/fetch", async (req, res) => {
  const url = req.query.url;
  if (!url) {
    return res.status(400).json({ error: "url parameter required" });
  }

  console.log(`[browser-fetch] ${url}`);

  // Wait for a slot before opening a new page
  await acquirePage();

  let context = null;
  let page = null;
  try {
    const b = await getBrowser();
    context = await b.newContext({
      userAgent:
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      extraHTTPHeaders: {
        Accept:
          "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
      },
    });

    page = await context.newPage();

    // Use "load" (fires after scripts/images) instead of "networkidle".
    // Heavy SPAs (Stripe, Slack, HubSpot) never reach networkidle because
    // they fire continuous background XHR — that caused the 30s timeouts.
    // On timeout we fall through and grab whatever the page has rendered so
    // far, which is almost always enough to find spec links.
    try {
      await page.goto(url, {
        waitUntil: "load",
        timeout: 20000,
      });
    } catch (navErr) {
      // Navigation timed out or failed — use partial content rather than
      // returning an error. React/Vue apps often have all their DOM in place
      // before "load" fires, so this still gives us useful HTML.
      console.log(`[browser-fetch] navigation timeout — using partial content for ${url}`);
    }

    // Short extra wait for React/Vue hydration to inject links into the DOM
    await page.waitForTimeout(1500);

    const html = await page.content();
    await context.close();
    context = null;

    console.log(`[browser-fetch] OK — ${html.length} bytes`);
    res.json({ html });
  } catch (err) {
    console.error(`[browser-fetch] ERROR: ${err.message}`);
    if (context) {
      try { await context.close(); } catch (_) {}
    }
    res.status(500).json({ error: err.message });
  } finally {
    releasePage();
  }
});

app.listen(PORT, async () => {
  console.log(`Browser service listening on http://localhost:${PORT}`);
  // Pre-warm the browser
  try {
    await getBrowser();
    console.log("Chromium ready");
  } catch (err) {
    console.error("Failed to launch browser:", err.message);
  }
});

// Graceful shutdown
process.on("SIGTERM", async () => {
  if (browser) await browser.close();
  process.exit(0);
});
