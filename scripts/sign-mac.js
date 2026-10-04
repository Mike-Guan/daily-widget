'use strict';

const path = require('path');
const { signAsync } = require('@electron/osx-sign');

async function main() {
  const appPath = process.argv[2];
  const identity = process.argv[3];
  if (!appPath || !identity) {
    throw new Error('Usage: node scripts/sign-mac.js <app-path> <Developer ID Application identity>');
  }

  await signAsync({
    app: path.resolve(appPath),
    identity,
    platform: 'darwin',
    hardenedRuntime: true,
    strictVerify: true,
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
