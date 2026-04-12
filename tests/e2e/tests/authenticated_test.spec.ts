import { test, expect } from '@playwright/test';

test.describe('Authenticated user', () => {
  test('shows logged in status in the top banner', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Verify the page shows the logged-in user indicator
    await expect(page.getByText('Logged in as')).toBeVisible({ timeout: 10000 });
  });
});
