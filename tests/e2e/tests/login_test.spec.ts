import { test, expect } from '@playwright/test';

test.describe('Login flow', () => {
  test('clicking Sign In navigates to the login page', async ({ page }) => {
    await page.goto('/');

    // Dismiss the cookie consent modal
    await page.getByRole('button', { name: 'Accept' }).click();

    // Click the Sign In button
    await page.getByRole('button', { name: 'Sign In' }).click();

    // Wait for navigation to complete after clicking Sign In
    await page.waitForLoadState('networkidle');

    // Verify we've navigated to the Keycloak/federated login page
    const url = page.url();
    const isKeycloakOrFederatedIdP = url.includes('keycloak.mcri.edu.au') || url.includes('login.microsoftonline.com');
    expect(isKeycloakOrFederatedIdP).toBe(true);

    // Verify the page doesn't contain a Django exception
    const pageContent = await page.content();
    expect(pageContent).not.toContain('Exception Location');
  });
});
