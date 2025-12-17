# 🚀 CPFT - Quick Start Guide

## Project Structure

Your project is now set up with a hybrid deployment strategy:

```
cpft/
├── dist/                      # Ready for deployment
│   ├── index.html            # Landing page (SEO optimized)
│   ├── app/                  # Flutter web app
│   ├── server.js             # Local dev server
│   └── package.json
│
├── lib/
│   └── index.html            # Flutter's HTML template (don't edit)
│
├── build/web                 # Flutter build output (generated)
│
├── deploy.sh                 # Deployment script
└── DEPLOYMENT_GUIDE.md       # Full deployment documentation
```

## 🎯 What Changed

✅ **Landing Page at Root (`/`)**: SEO-optimized static HTML
✅ **Flutter App at `/app/`**: Your interactive web application
✅ **Proper Separation**: Landing page and app are in different folders
✅ **Easy Deployment**: Simple script to update the build

## 🏃 Quick Start

### 1️⃣ Test Locally

**Option A: Using Node.js (Recommended)**
```bash
cd dist
node server.js
```
Then visit:
- Landing page: http://localhost:3000/
- App: http://localhost:3000/app/

**Option B: Using Python**
```bash
cd dist
python -m http.server 8000
```
Then visit http://localhost:8000/

### 2️⃣ Build & Deploy

**When you make changes to the Flutter app:**
```bash
./deploy.sh
```

This will:
1. Build Flutter with `--base-href /app/`
2. Copy build to `dist/app/`
3. Show you the structure

### 3️⃣ Deploy to Production

Upload the `dist/` folder to your server:

```bash
# Using rsync
rsync -avz dist/ user@your-server.com:/var/www/cpft/

# Using FTP / SFTP / any other method
# Just upload the entire dist/ folder to your web root
```

## 🔄 Workflow

### When you update the app:
```bash
# Make changes to lib/ or other Flutter files
# Then run:
./deploy.sh

# This automatically updates dist/app/
# Ready to redeploy!
```

### When you update the landing page:
```bash
# Edit dist/index.html directly
# No rebuild needed!
# Changes are live immediately when you redeploy
```

## 📝 URLs After Deployment

If deployed to `cpft.io`:

| URL | Content |
|-----|---------|
| `https://cpft.io/` | Landing page |
| `https://cpft.io/app/` | Flutter app |
| `https://cpft.io/privacy` | Privacy (links to landing page anchor) |
| `https://cpft.io/terms` | Terms (links to landing page anchor) |

## 🌐 Server Configuration

### If using Nginx
See `DEPLOYMENT_GUIDE.md` for complete Nginx config

### If using Apache
See `DEPLOYMENT_GUIDE.md` for complete Apache config

### If using Vercel/Netlify
- Deploy the `dist/` folder as your static site
- They'll handle routing automatically
- No special config needed

## ✨ Features

✅ **SEO Optimized**: Landing page with proper meta tags
✅ **Responsive**: Works on all devices
✅ **Fast**: Static landing page loads instantly
✅ **Accessible**: Proper HTML structure
✅ **Offline Support**: Flutter app works offline
✅ **Mobile Ready**: Both pages are mobile-first

## 🐛 Troubleshooting

### App doesn't load at `/app/`
- Make sure `dist/app/index.html` exists
- Check that your server is configured to rewrite SPA routes
- See DEPLOYMENT_GUIDE.md for server configs

### Landing page looks wrong
- Check that `dist/index.html` exists
- Verify CSS is loading (check browser console)
- Try clearing cache (Ctrl+Shift+Delete in Chrome)

### Changes don't appear
- Did you run `./deploy.sh`?
- Did you refresh the page (Ctrl+F5)?
- Check browser cache

## 📚 More Info

See **DEPLOYMENT_GUIDE.md** for:
- Complete server configuration examples
- Advanced deployment options
- Caching strategies
- Performance optimization
- SEO best practices

## 🎉 Done!

Your CPFT project is ready for:
- ✅ Local development
- ✅ Testing
- ✅ Production deployment

Happy building! 🚀
