import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration for seqr end-to-end tests.
 *
 * By default, tests run against the local docker-compose seqr instance.
 * Override with the BASE_URL environment variable if needed:
 *
 *   BASE_URL=http://some-other-host:8000 npm test
 */
export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',

  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:8000',
    trace: 'on-first-retry',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
