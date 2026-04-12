import { chromium, FullConfig } from '@playwright/test';

async function globalSetup(config: FullConfig) {
  const baseURL = config.projects[0].use.baseURL || 'http://localhost:8000';

  const browser = await chromium.launch();
  const context = await browser.newContext();
  const page = await context.newPage();

  // Fetch the CSRF token first
  await page.goto(baseURL);
  const csrfToken = await page.evaluate(() => {
    const cookie = document.cookie.split('; ').find(c => c.startsWith('csrf_token='));
    return cookie ? cookie.split('=')[1] : '';
  });

  // Authenticate via the test login endpoint
  const response = await page.request.post(`${baseURL}/api/test-login`, {
    data: { email: process.env.TEST_USER_EMAIL || 'test_user@seqr.org' },
    headers: { 'X-CSRFToken': csrfToken },
  });

  if (!response.ok()) {
    throw new Error(`Test login failed: ${response.status()} ${await response.text()}`);
  }

  // Save the authenticated session for all tests
  await context.storageState({ path: 'tests/e2e/auth.json' });
  await browser.close();
}

export default globalSetup;
