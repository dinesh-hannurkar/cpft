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
  
  // Root path serves landing page
  if (req.url === '/' || req.url === '/index.html') {
    filePath = path.join(ROOT_DIR, 'index.html');
  } else {
    const appPath = path.join(ROOT_DIR, 'app');
    
    // Try to find the requested file as a static asset in /app/
    const requestedFile = path.join(appPath, req.url);
    
    if (fs.existsSync(requestedFile) && fs.statSync(requestedFile).isFile()) {
      // It's a real file (JS, CSS, images, etc.), serve it
      filePath = requestedFile;
    } else {
      // For any route request (e.g., /webshare, /privacy), serve Flutter app's index.html
      // Flutter will handle routing via path-based routing (no hashes needed)
      filePath = path.join(appPath, 'index.html');
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
