import { test, expect } from '@playwright/test';

test.describe('Smoke tests', () => {
  test('homepage loads and contains HTML', async ({ page }) => {
    const response = await page.goto('/');
    expect(response).not.toBeNull();
    expect(response!.status()).toBeLessThan(400);

    // The seqr SPA should render an HTML page with a <title>
    const title = await page.title();
    expect(title).toBeTruthy();
  });

});
