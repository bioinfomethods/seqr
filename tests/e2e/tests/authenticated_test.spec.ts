import { test, expect } from '@playwright/test';

test.describe('Authenticated user', () => {
  test('shows logged in status in the top banner', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Dismiss the cookie consent modal if present
    const cookieBanner = page.getByText('This website uses cookies');
    if (await cookieBanner.isVisible({ timeout: 3000 }).catch(() => false)) {
      await page.getByRole('button', { name: 'Accept' }).click();
    }

    // Verify the page shows the logged-in user indicator
    await expect(page.getByText('Logged in as')).toBeVisible({ timeout: 10000 });

    // Accept the Seqr Policies if the dialog appears
    const policiesHeading = page.getByText('Seqr Policies');
    if (await policiesHeading.isVisible({ timeout: 3000 }).catch(() => false)) {
      await page.getByText('I accept the').click();
      await page.getByRole('button', { name: 'Submit' }).click();
    }
  });
});
