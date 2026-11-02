const {defineConfig} = require('@playwright/test');
module.exports = defineConfig({
  testDir: __dirname, testMatch: '*.spec.cjs', workers: 1, retries: 0,
  timeout: 30000, expect: {timeout: 5000},
  outputDir: '../../results/dev-tools-browser',
  reporter: 'list',
  use: {baseURL: 'http://127.0.0.1:47182', browserName: 'chromium', channel: process.env.FOG_OF_WAR_BROWSER_CHANNEL || 'chrome',
    headless: true, viewport: {width: 640, height: 800}, screenshot: 'only-on-failure', trace: 'retain-on-failure'},
  webServer: [
    {command: 'bash server.sh', cwd: __dirname, url: 'http://127.0.0.1:47183/', reuseExistingServer: false},
    {command: 'bash frontier-server.sh', cwd: __dirname, url: 'http://127.0.0.1:47192/', reuseExistingServer: false},
  ],
});
