
import { defineConfig } from '@playwright/test';

export default defineConfig({
  timeout: 10000,
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:8000',
  },
});
