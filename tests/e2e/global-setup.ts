import { chromium, FullConfig } from '@playwright/test';

async function globalSetup(config: FullConfig) {
  const testUserEmail = process.env.TEST_USER_EMAIL || 'test_user@seqr.org';
  const baseURL = (config.projects[0]?.use?.baseURL as string) || 'http://localhost:8000';

  const browser = await chromium.launch();
  const context = await browser.newContext();
  const page = await context.newPage();

  // Navigate to a page that doesn't require login to get a CSRF cookie
  // Use the login page since it's in no_login_react_app_pages
  const loginResponse = await page.goto(`${baseURL}/login/`);
  await page.waitForLoadState('domcontentloaded');

  // Get the CSRF token from cookies
  const cookies = await context.cookies();
  const csrfCookie = cookies.find(c => c.name === 'csrf_token');
  const csrfToken = csrfCookie?.value || '';

  if (!csrfToken) {
    await browser.close();
    throw new Error('Failed to obtain CSRF token from login page');
  }

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
