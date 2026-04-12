import { defineConfig } from '@playwright/test';

export default defineConfig({
  timeout: 10000,
  globalSetup: './global-setup',
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:8000',
  },
  projects: [
    {
      name: 'authenticated',
      use: {
        storageState: 'tests/e2e/auth.json',
      },
      testIgnore: /login_test/,
    },
    {
      name: 'unauthenticated',
      testMatch: /login_test/,
    },
  ],
});
