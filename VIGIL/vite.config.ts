import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
export default defineConfig({
  plugins: [react()],
  server: { host: '0.0.0.0', allowedHosts: true, watch: { ignored: ['**/playwright-report/**', '**/test-results/**', '**/docs/screenshots/**'] } },
  preview: { host: '0.0.0.0', allowedHosts: true },
  test: { environment: 'jsdom', setupFiles: ['./src/test/setup.ts'], include: ['src/**/*.test.{ts,tsx}'], restoreMocks: true },
});
