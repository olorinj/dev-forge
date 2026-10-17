const fs = require('fs');
const path = require('path');

const distDir = path.join(__dirname, 'dist');
if (!fs.existsSync(distDir)) {
  fs.mkdirSync(distDir, { recursive: true });
}

// 1. Copy index.js as hashforge-node.js
const srcJs = path.join(__dirname, 'index.js');
const dstJs = path.join(distDir, 'hashforge-node.js');
fs.copyFileSync(srcJs, dstJs);
try {
  fs.chmodSync(dstJs, 0o755);
} catch (e) {}

// 2. Copy index.html
const srcHtml = path.join(__dirname, 'public', 'index.html');
const dstHtml = path.join(distDir, 'index.html');
fs.copyFileSync(srcHtml, dstHtml);

console.log('[HashForge Node Build] Artefactos generados con éxito en:', distDir);
console.log(' -', dstJs);
console.log(' -', dstHtml);
