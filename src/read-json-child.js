'use strict';

const fs = require('fs');

try {
  const value = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  process.stdout.write(JSON.stringify({ ok: true, value }));
} catch (error) {
  process.stdout.write(JSON.stringify({
    ok: false,
    code: error && error.code,
    name: error && error.name,
    message: error && error.message,
  }));
  process.exitCode = 1;
}
