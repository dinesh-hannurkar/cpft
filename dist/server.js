#!/usr/bin/env node
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

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

function getLocalIp() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return 'localhost';
}

const LOCAL_IP = getLocalIp();

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

server.listen(PORT, '0.0.0.0', () => {
  console.log(`
╔════════════════════════════════════════╗
║   CPFT Network Development Server       ║
╚════════════════════════════════════════╝

🚀 Server running on your network!

🏠 Local:   http://localhost:${PORT}
🌐 Network: http://${LOCAL_IP}:${PORT}

📍 URLs:
  • Landing page:    http://${LOCAL_IP}:${PORT}/
  • Flutter app:     http://${LOCAL_IP}:${PORT}/#/webshare
  • Privacy route:   http://${LOCAL_IP}:${PORT}/#/privacy

📦 Root Directory: ${ROOT_DIR}

💡 How it works:
   • Accessible from other devices on the same WiFi
   • / → Landing page (index.html)
   • /#/webshare → Flutter app handles routing via hash
   • Static files (JS, CSS, etc.) → Served directly from /app/

🛑 Press Ctrl+C to stop the server
  `);
});
