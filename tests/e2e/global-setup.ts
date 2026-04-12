import { chromium, FullConfig } from '@playwright/test';

async function globalSetup(config: FullConfig) {
  const testUserEmail = process.env.TEST_USER_EMAIL || 'test_user@seqr.org';
  const enableTestLogin = process.env.ENABLE_TEST_LOGIN;

  if (!enableTestLogin) {
    console.log('ENABLE_TEST_LOGIN not set, skipping test login setup. Authenticated tests will fail.');
    return;
  }

  const baseURL = (config.projects[0]?.use?.baseURL as string) || 'http://localhost:8000';

  const browser = await chromium.launch();
  const context = await browser.newContext();
  const page = await context.newPage();

  // Navigate to the app to get a CSRF cookie
  await page.goto(baseURL);
  const csrfToken = await page.evaluate(() => {
    const cookie = document.cookie.split('; ').find(c => c.startsWith('csrf_token='));
    return cookie ? cookie.split('=')[1] : '';
  });

  // Authenticate via the test login endpoint
  const response = await page.request.post(`${baseURL}/api/test_login`, {
    data: { email: testUserEmail },
    headers: { 'X-CSRFToken': csrfToken },
  });

  if (!response.ok()) {
    const body = await response.text();
    await browser.close();
    throw new Error(`Test login failed: ${response.status()} ${body}`);
  }

  // Save the authenticated session for all tests
  await context.storageState({ path: 'tests/e2e/auth.json' });
  await browser.close();
}

export default globalSetup;
