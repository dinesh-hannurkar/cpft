#!/usr/bin/env node
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 3000;
const ROOT_DIR = __dirname;

const mimeTypes = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.eot': 'application/vnd.ms-fontobject'
};

const server = http.createServer((req, res) => {
  // Log requests
  console.log(`${req.method} ${req.url}`);

  let filePath;

  // Get file path
  if (req.url === '/' || req.url === '/index.html') {
    filePath = path.join(ROOT_DIR, 'index.html');
  } else if (req.url === '/downloads' || req.url === '/downloads.html') {
    filePath = path.join(ROOT_DIR, 'downloads.html');
  } else {
    // 1. Check if file exists in the root directory (for landing page assets & releases.json)
    const rootPathFile = path.join(ROOT_DIR, req.url);
    if (fs.existsSync(rootPathFile) && fs.statSync(rootPathFile).isFile()) {
      filePath = rootPathFile;
    } else {
      // 2. Check if file exists in /app/ directory (for Flutter web assets)
      const appPathFile = path.join(ROOT_DIR, 'app', req.url);
      if (fs.existsSync(appPathFile) && fs.statSync(appPathFile).isFile()) {
        filePath = appPathFile;
      } else {
        // 3. Fallback to Flutter app's index.html for all other routes
        filePath = path.join(ROOT_DIR, 'app', 'index.html');
      }
    }
  }

  // Get file extension
  const ext = path.extname(filePath);
  const contentType = mimeTypes[ext] || 'application/octet-stream';

  // Read and serve file
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/html' });
      res.end('<h1>404 - File Not Found</h1>', 'utf-8');
      console.log(`  ❌ 404: ${filePath}`);
      return;
    }

    res.writeHead(200, {
      'Content-Type': contentType,
      'Cache-Control': ext === '.html' ? 'no-cache' : 'public, max-age=3600'
    });
    res.end(data);
    console.log(`  ✅ 200: ${filePath}`);
  });
});

server.listen(PORT, () => {
  console.log(`
╔════════════════════════════════════════╗
║   CPFT Local Development Server       ║
╚════════════════════════════════════════╝

🚀 Server running at http://localhost:${PORT}

📍 URLs:
  • Landing page:    http://localhost:${PORT}/
  • Flutter app:     http://localhost:${PORT}/#/webshare
  • Privacy route:   http://localhost:${PORT}/#/privacy
  • Any route:       http://localhost:${PORT}/#/your-route

📦 Root Directory: ${ROOT_DIR}

Structure:
  dist/
  ├── index.html         ← Landing page (served at /)
  ├── app/               ← Flutter app (base-href /)
  │   ├── index.html
  │   ├── main.dart.js
  │   └── ...
  └── package.json

💡 How it works:
   • / → Landing page (index.html)
   • /#/webshare → Flutter app handles routing via hash
   • Static files (JS, CSS, etc.) → Served directly from /app/

🛑 Press Ctrl+C to stop the server
  `);
});
