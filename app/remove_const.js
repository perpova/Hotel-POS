const fs = require('fs');
const path = require('path');

function walkDir(dir, callback) {
  fs.readdirSync(dir).forEach(f => {
    let dirPath = path.join(dir, f);
    let isDirectory = fs.statSync(dirPath).isDirectory();
    if (isDirectory) {
      walkDir(dirPath, callback);
    } else {
      callback(path.join(dir, f));
    }
  });
}

const libDir = path.join(__dirname, 'lib');

walkDir(libDir, filePath => {
  if (path.extname(filePath) !== '.dart') return;

  let content = fs.readFileSync(filePath, 'utf8');
  let lines = content.split('\n');
  let changed = false;

  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];
    if (line.includes('AppTheme.primary')) {
      // Look for const keyword on this line or nearby
      if (line.includes('const ')) {
        lines[i] = line.replace(/\bconst\s+/g, '');
        changed = true;
      }
    }
  }

  if (changed) {
    fs.writeFileSync(filePath, lines.join('\n'), 'utf8');
    console.log(`Updated const in: ${filePath}`);
  }
});
