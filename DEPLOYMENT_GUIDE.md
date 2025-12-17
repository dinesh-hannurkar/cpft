# CPFT Deployment Structure

This project now uses a hybrid approach for optimal SEO and functionality:

## 📋 Overview

- **Root (`/`)**: Static HTML landing page for SEO
- **`/app/`**: Flutter web application

## 📁 Folder Structure

```
dist/
├── index.html           # Landing page served at root (/)
├── app/                 # Flutter web app served at /app/
│   ├── index.html
│   ├── main.dart.js
│   ├── flutter_bootstrap.js
│   ├── flutter_service_worker.js
│   ├── manifest.json
│   ├── canvaskit/
│   ├── assets/
│   └── ...
└── [static assets if added]
```

## 🚀 Deployment Process

### Step 1: Build the Flutter Web App

```bash
flutter build web --base-href /app/ --release
```

This creates the Flutter app build with all assets pointing to `/app/` URLs.

### Step 2: Copy to Dist Folder

Use the provided deploy script:

```bash
./deploy.sh
```

Or manually:

```bash
cp -r build/web dist/app
```

### Step 3: Deploy to Server

Upload the entire `dist/` folder to your web server:

```bash
# Example with rsync
rsync -avz dist/ user@server:/var/www/cpft/

# Or with FTP/other deployment tool
# Upload dist/ → /var/www/cpft/ (or equivalent root)
```

## 🌐 Serving Configuration

### Apache (.htaccess)

```apache
<IfModule mod_rewrite.c>
  RewriteEngine On
  
  # Landing page at root
  RewriteRule ^index\.html$ - [L]
  RewriteRule ^favicon\.ico$ - [L]
  
  # For Flutter app, let index.html handle routing
  RewriteCond %{REQUEST_FILENAME} !-f
  RewriteCond %{REQUEST_FILENAME} !-d
  RewriteRule ^app/(.*)$ app/index.html [L]
  
  # For root, serve root index.html
  RewriteCond %{REQUEST_FILENAME} !-f
  RewriteCond %{REQUEST_FILENAME} !-d
  RewriteCond %{REQUEST_URI} !^/app/
  RewriteRule . index.html [L]
</IfModule>
```

### Nginx

```nginx
server {
  listen 80;
  server_name cpft.io;
  root /var/www/cpft;
  
  # Landing page at root
  location = / {
    try_files /index.html =404;
  }
  
  # Flutter app at /app/
  location /app/ {
    try_files $uri $uri/ /app/index.html;
    add_header Cache-Control "public, max-age=3600";
  }
  
  # Assets (cache longer)
  location ~ \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
    add_header Cache-Control "public, max-age=31536000";
  }
}
```

## 📊 URL Routing

| URL | Served From | Purpose |
|-----|------------|---------|
| `/` | `dist/index.html` | Landing page (SEO optimized) |
| `/app/` | `dist/app/index.html` | Flutter web app |
| `/app/main.dart.js` | `dist/app/main.dart.js` | Flutter app code |
| `/privacy` | `dist/index.html` (with anchor) | Privacy page |
| `/terms` | `dist/index.html` (with anchor) | Terms page |

## 🔍 SEO Benefits

✅ **Landing page at root** (`/`) - Better for search engines  
✅ **Proper meta tags** - OG tags, descriptions, canonical URLs  
✅ **Fast initial load** - Static HTML serves immediately  
✅ **Semantic HTML** - Proper heading structure  
✅ **Mobile responsive** - All breakpoints covered  

## 🔄 Local Development

To test locally:

```bash
# Option 1: Using Python
cd dist && python -m http.server 8000

# Option 2: Using Node.js
cd dist && npx http-server

# Option 3: Using Docker
docker run -d -p 8000:80 -v $(pwd)/dist:/usr/share/nginx/html nginx:alpine

# Then visit:
# http://localhost:8000/          (landing page)
# http://localhost:8000/app/      (Flutter app)
```

## 🔨 Build Commands

### Full Build & Deploy

```bash
./deploy.sh
```

### Just Flutter Build

```bash
flutter build web --base-href /app/ --release
```

### Development Build (faster, larger)

```bash
flutter build web --base-href /app/
```

### Update just the Flutter app

```bash
flutter build web --base-href /app/ --release
rm -rf dist/app
cp -r build/web dist/app
```

## 📝 Notes

- The Flutter app's base href must always be `/app/` for assets to resolve correctly
- The landing page (`index.html`) at root is SEO-optimized with meta tags
- Both pages are fully responsive (mobile, tablet, desktop)
- Service workers are configured for offline support in the app
- Cache headers should be configured based on your deployment platform

## 🚨 Troubleshooting

### App doesn't load at `/app/`
- Ensure server rewrites are configured correctly
- Check that `app/index.html` exists
- Verify Flutter base href is `/app/`

### Assets 404 at `/app/`
- Check that assets are served from correct paths
- Ensure `main.dart.js` exists in `dist/app/`
- Verify no URL rewriting conflicts

### SEO not improving
- Ensure root `index.html` has proper meta tags
- Test with Google Search Console
- Check `robots.txt` and `sitemap.xml` exist
- Verify canonical URLs are set

## 📦 File Sizes

Example deployment sizes:
- Root landing page: ~20KB
- Flutter app (compressed): ~3-5MB
- Total with assets: ~5-7MB
