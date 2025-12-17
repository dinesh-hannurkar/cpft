#!/bin/bash

# CPFT Deployment Script
# This script rebuilds the Flutter web app and updates the dist folder

echo "🔨 Building Flutter web app with /app/ base href..."
flutter build web --base-href /app/ --release

if [ $? -ne 0 ]; then
    echo "❌ Flutter build failed"
    exit 1
fi

echo "📁 Removing old app build..."
rm -rf dist/app

echo "📋 Copying new app build to dist/app..."
cp -r build/web dist/app

echo "✅ Deployment ready!"
echo ""
echo "📦 Dist folder structure:"
echo "   dist/"
echo "   ├── index.html (root landing page)"
echo "   └── app/ (Flutter web app)"
echo ""
echo "🚀 To deploy:"
echo "   - Upload the 'dist' folder to your web server"
echo "   - Root (/) serves the landing page"
echo "   - /app/ serves the Flutter app"
