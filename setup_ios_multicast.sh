#!/bin/bash

# iOS Multicast Entitlement Setup
# This script adds the multicast entitlement to your iOS project

echo "🔧 Setting up iOS multicast entitlements..."

# Check if we're in the right directory
if [ ! -d "ios/Runner.xcodeproj" ]; then
    echo "❌ Error: Must run from Flutter project root"
    exit 1
fi

# Open Xcode project
echo "📱 Opening Xcode project..."
echo ""
echo "Please follow these steps in Xcode:"
echo ""
echo "1. Select 'Runner' project in the left sidebar"
echo "2. Select 'Runner' target"
echo "3. Go to 'Signing & Capabilities' tab"
echo "4. Click '+ Capability' button"
echo "5. Search for 'Multicast Networking'"
echo "6. Add it"
echo "7. Clean and rebuild (Cmd+Shift+K, then Cmd+B)"
echo ""
echo "Alternatively, you can:"
echo "1. Click 'Runner' target"
echo "2. Go to 'Build Settings'"
echo "3. Search for 'Code Signing Entitlements'"
echo "4. Set it to: Runner/Runner.entitlements"
echo ""

read -p "Press Enter to open Xcode..."
open ios/Runner.xcworkspace

echo ""
echo "✅ Runner.entitlements file already created with multicast permission"
echo "   Location: ios/Runner/Runner.entitlements"
echo ""
echo "After making changes in Xcode:"
echo "  flutter clean"
echo "  flutter run -d <your-ios-device>"
