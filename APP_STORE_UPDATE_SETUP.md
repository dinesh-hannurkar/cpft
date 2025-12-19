# App Store Update Checking Setup

This guide explains how to configure the app to automatically check for updates from the actual app stores.

## Overview

The update system now automatically checks the official app stores for new versions:
- **iOS**: Uses Apple's iTunes Search API (official and reliable)
- **Android**: Uses multiple methods including appversion.io API and Play Store scraping

## Configuration

### 1. Update App IDs in Code

Edit `lib/services/update_service_simple.dart`:

```dart
// ===== CONFIGURATION =====
// CHANGE THESE TO YOUR ACTUAL APP STORE IDs
static const String androidPackageName = 'com.example.cpft'; // Your Android package name
static const String iosAppId = '1234567890'; // Your iOS App Store ID (numbers only)
// ===== END CONFIGURATION =====
```

### 2. Find Your App Store IDs

#### iOS App Store ID
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Select your app
3. Find the "Apple ID" in the App Information section
4. Use only the numbers (e.g., if Apple ID is "1234567890", use "1234567890")

#### Android Package Name
- This is your `applicationId` from `android/app/build.gradle`
- Usually in format: `com.company.appname`

### 3. Update Store URLs

```dart
static const String updateUrlAndroid = 'https://play.google.com/store/apps/details?id=YOUR_PACKAGE_NAME';
static const String updateUrlIos = 'https://apps.apple.com/app/id=YOUR_APP_ID';
```

## How It Works

### iOS (Apple App Store)
- Uses official iTunes Search API: `https://itunes.apple.com/lookup?id={APP_ID}`
- Always reliable and up-to-date
- No rate limits for reasonable usage

### Android (Google Play Store)
- **Primary**: Uses [appversion.io](https://appversion.io) API (free service)
- **Backup**: Scrapes Play Store page for version info
- **Recommended**: Set up your own backend API for production

## Production Setup (Recommended)

For production apps, create a backend API endpoint that returns version info:

### Backend API Response Format
```json
{
  "android": {
    "version": "1.2.3",
    "critical": false
  },
  "ios": {
    "version": "1.2.3",
    "critical": false
  }
}
```

### Update Service Code
```dart
Future<String?> _getAndroidLatestVersion() async {
  try {
    final url = 'https://your-api.com/api/app-versions';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['android']['version']?.toString();
    }
  } catch (e) {
    // Fallback methods...
  }
  return null;
}
```

## Testing

### Test iOS Version Check
```bash
curl "https://itunes.apple.com/lookup?id=YOUR_APP_ID"
```

### Test Android Version Check
```bash
curl "https://appversion.io/api/v1/android/YOUR_PACKAGE_NAME"
```

## Deployment Workflow

1. **Release new app version to stores**
2. **Update pubspec.yaml version** in your code
3. **Test update dialog** appears for older versions
4. **Monitor** that users are directed to correct store URLs

## Fallback Behavior

If app store checking fails:
- App continues to work normally
- No update dialog shown
- Debug logs indicate the failure
- User experience is unaffected

## Rate Limits & Reliability

- **iOS**: No rate limits, very reliable
- **appversion.io**: Free tier available, reliable
- **Play Store scraping**: May break if Google changes HTML structure
- **Custom API**: Most reliable for production

## Security Notes

- All API calls are HTTPS
- No sensitive data is transmitted
- Version checking is read-only
- Fails gracefully if services are unavailable