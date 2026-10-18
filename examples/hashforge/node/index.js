#!/usr/bin/env node
// =============================================================================
// HashForge (Node.js & Web) - Implementación de Referencia Multi-Lenguaje
// =============================================================================
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const VERSION = '1.0.0';

function hashString(str) {
  const sha256 = crypto.createHash('sha256').update(str, 'utf8').digest('hex');
  const md5 = crypto.createHash('md5').update(str, 'utf8').digest('hex');
  return { target: str, sha256, md5 };
}

function hashFile(filePath) {
  const buffer = fs.readFileSync(filePath);
  const sha256 = crypto.createHash('sha256').update(buffer).digest('hex');
  const md5 = crypto.createHash('md5').update(buffer).digest('hex');
  return { target: filePath, sha256, md5 };
}

function printHelp() {
  console.log(`HashForge ${VERSION} (Node.js & Web)`);
  console.log('Uso:');
  console.log('  node index.js -s <texto>    Calcula hash de una cadena');
  console.log('  node index.js -f <archivo>  Calcula hash de un archivo');
  console.log('  node index.js -j            Formato JSON');
  console.log('  node index.js --web         Muestra ruta de la interfaz Web');
  console.log('  node index.js -h            Muestra esta ayuda');
}

function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    printHelp();
    return;
  }

  let inputString = null;
  let inputFile = null;
  let jsonOutput = false;

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '-s':
      case '--string':
        inputString = args[++i];
        break;
      case '-f':
      case '--file':
        inputFile = args[++i];
        break;
      case '-j':
      case '--json':
        jsonOutput = true;
        break;
      case '-w':
      case '--web':
      case '--gui':
        const htmlPath = path.join(__dirname, 'dist', 'index.html');
        console.log(`Interfaz Web disponible en: file://${htmlPath}`);
        return;
      case '-h':
      case '--help':
        printHelp();
        return;
      default:
        console.error(`Opción desconocida: ${args[i]}`);
        printHelp();
        process.exit(1);
    }
  }

  let res;
  try {
    if (inputString !== null) {
      res = hashString(inputString);
    } else if (inputFile !== null) {
      res = hashFile(inputFile);
    } else {
      printHelp();
      return;
    }

    if (jsonOutput) {
      console.log(JSON.stringify(res));
    } else {
      console.log(`Objetivo: ${res.target}`);
      console.log(`SHA-256:  ${res.sha256}`);
      console.log(`MD5:      ${res.md5}`);
    }
  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}

module.exports = { hashString, hashFile };

