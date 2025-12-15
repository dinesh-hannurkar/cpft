# Firebase Feedback Integration

This document explains how CPFT's feedback system works with Firebase Firestore.

## Overview

The feedback system now uses Firebase Firestore as the primary storage method with email fallback for offline scenarios.

## Firestore Structure

### Collection: `feedback`

Each feedback document contains:

```json
{
  "id": "fb_1703123456789_123",
  "type": "bug|feature|general|other",
  "description": "User's feedback description",
  "stepsToReproduce": "Steps for bug reports (optional)",
  "expectedBehavior": "Expected behavior for bug reports (optional)",
  "deviceInfo": "Platform: android\nOS Version: 13\nApp Version: 0.1.2",
  "appVersion": "0.1.2",
  "platform": "android",
  "timestamp": "2025-01-15T10:30:00.000Z",
  "userId": null
}
```

## Firebase Security Rules

Add these rules to your Firestore database:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow read/write access to feedback collection
    match /feedback/{document} {
      allow create: if request.auth != null || request.auth == null;
      allow read: if request.auth != null;
      allow update, delete: if false; // No updates or deletes
    }
  }
}
```

## Admin Access

### Firebase Console
1. Go to Firebase Console → Firestore Database
2. Navigate to the `feedback` collection
3. View, filter, and export feedback data

### Query Examples

**Get all feedback:**
```javascript
const feedback = await db.collection('feedback').orderBy('timestamp', 'desc').get();
```

**Get feedback by type:**
```javascript
const bugs = await db.collection('feedback')
  .where('type', '==', 'bug')
  .orderBy('timestamp', 'desc')
  .get();
```

**Get recent feedback (last 7 days):**
```javascript
const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
const recent = await db.collection('feedback')
  .where('timestamp', '>', weekAgo)
  .orderBy('timestamp', 'desc')
  .get();
```

## Email Fallback

When Firestore is unavailable (network issues, Firebase down), the app falls back to email:

- **Recipient**: `feedback@cpft.app`
- **Subject**: `CPFT [Type] - [Version] (Offline)`
- **Content**: Same structured format as Firestore data

## Analytics & Insights

### Feedback Metrics
- Total feedback count
- Feedback by type (bug/feature/general/other)
- Platform distribution (Android/iOS/Web)
- App version distribution
- Time-based trends

### Common Queries for Dashboard

```javascript
// Feedback count by type
const typeStats = await db.collection('feedback')
  .groupBy('type')
  .count();

// Feedback by platform
const platformStats = await db.collection('feedback')
  .groupBy('platform')
  .count();

// Recent bug reports
const recentBugs = await db.collection('feedback')
  .where('type', '==', 'bug')
  .where('timestamp', '>', lastWeek)
  .orderBy('timestamp', 'desc')
  .limit(50);
```

## Data Retention

- Feedback data is retained indefinitely for product improvement
- Consider implementing automatic cleanup for very old feedback
- Export important feedback before deletion

## Privacy Considerations

- Device information is optional (user-controlled)
- No personally identifiable information is stored
- Feedback is anonymized
- Users can request data deletion

## Monitoring & Alerts

Consider setting up Firebase Cloud Functions to:

1. Send email notifications for new feedback
2. Create Slack/Discord notifications for urgent issues
3. Generate weekly feedback summaries
4. Alert on high bug report volumes

## Future Enhancements

1. **User Authentication**: Link feedback to user accounts
2. **Feedback Status**: Add resolution tracking (open/in-progress/resolved)
3. **Admin Responses**: Allow replying to user feedback
4. **Priority System**: Mark urgent issues
5. **Categories**: Add sub-categories for better organization