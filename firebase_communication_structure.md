# Firebase Communication Structure for Skybyn Mobile App

This document outlines the complete Firebase structure for all communication methods that the Skybyn mobile app can handle. This structure should be used to create a comprehensive PHP endpoint for sending updates and notifications to all mobile devices.

## Overview

The Skybyn app supports multiple communication channels:
1. **WebSocket Real-time Communication** - For live updates
2. **Firebase Cloud Messaging (FCM)** - For push notifications
3. **Local Notifications** - For in-app notifications
4. **OTA Updates** - For app updates
5. **HTTP API** - For standard API calls

## Firebase Collections Structure

### 1. Users Collection (`users`)

```json
{
  "userId": "string",
  "username": "string",
  "email": "string",
  "fcmTokens": {
    "android": ["token1", "token2"],
    "ios": ["token1", "token2"]
  },
  "deviceInfo": {
    "platform": "android|ios",
    "device": "Samsung Galaxy S21 (Android 12)",
    "appVersion": "1.0.0",
    "buildNumber": "1",
    "lastSeen": "2024-01-01T00:00:00Z",
    "isOnline": true
  },
  "notificationSettings": {
    "pushEnabled": true,
    "localEnabled": true,
    "channels": {
      "admin": true,
      "feature": true,
      "maintenance": true
    }
  },
  "websocketSession": {
    "sessionId": "string",
    "isConnected": true,
    "lastPing": "2024-01-01T00:00:00Z"
  },
  "createdAt": "2024-01-01T00:00:00Z",
  "updatedAt": "2024-01-01T00:00:00Z"
}
```

### 2. Notifications Collection (`notifications`)

```json
{
  "notificationId": "string",
  "userId": "string",
  "type": "new_post|new_comment|broadcast|app_update|admin|feature|maintenance",
  "title": "string",
  "body": "string",
  "payload": {
    "postId": "string",
    "commentId": "string",
    "action": "string",
    "data": {}
  },
  "priority": "high|normal|low",
  "channels": ["admin", "feature", "maintenance"],
  "deliveryMethods": {
    "websocket": true,
    "fcm": true,
    "local": true
  },
  "status": "pending|sent|delivered|failed",
  "scheduledFor": "2024-01-01T00:00:00Z",
  "createdAt": "2024-01-01T00:00:00Z",
  "sentAt": "2024-01-01T00:00:00Z",
  "deliveredAt": "2024-01-01T00:00:00Z"
}
```

### 3. App Updates Collection (`app_updates`)

```json
{
  "updateId": "string",
  "version": "1.0.1",
  "buildNumber": "2",
  "platform": "android|ios|both",
  "type": "minor|major|critical|hotfix",
  "forced": false,
  "downloadUrl": "https://api.skybyn.no/appUpdates/download.php?version=1.0.1",
  "changelog": "Bug fixes and improvements",
  "releaseNotes": "Detailed release notes",
  "fileSize": 50000000,
  "checksum": "sha256_hash",
  "minSupportedVersion": "1.0.0",
  "targetDevices": {
    "android": {
      "minSdk": 21,
      "maxSdk": 34,
      "architectures": ["arm64-v8a", "armeabi-v7a"]
    },
    "ios": {
      "minVersion": "12.0",
      "maxVersion": "17.0",
      "architectures": ["arm64"]
    }
  },
  "rolloutPercentage": 100,
  "targetUsers": ["all", "beta", "specific_users"],
  "isActive": true,
  "createdAt": "2024-01-01T00:00:00Z",
  "releasedAt": "2024-01-01T00:00:00Z"
}
```

### 4. WebSocket Sessions Collection (`websocket_sessions`)

```json
{
  "sessionId": "string",
  "userId": "string",
  "deviceInfo": {
    "platform": "android|ios",
    "device": "string",
    "browser": "Skybyn App"
  },
  "connectionInfo": {
    "ip": "string",
    "userAgent": "string",
    "lastPing": "2024-01-01T00:00:00Z",
    "isConnected": true
  },
  "capabilities": {
    "canReceiveWebSocket": true,
    "canReceiveFCM": true,
    "canReceiveLocal": true
  },
  "createdAt": "2024-01-01T00:00:00Z",
  "lastActivity": "2024-01-01T00:00:00Z"
}
```

### 5. Broadcast Messages Collection (`broadcasts`)

```json
{
  "broadcastId": "string",
  "type": "announcement|maintenance|feature|emergency",
  "title": "string",
  "message": "string",
  "priority": "high|normal|low",
  "targetAudience": {
    "allUsers": true,
    "specificUsers": ["userId1", "userId2"],
    "platforms": ["android", "ios"],
    "appVersions": ["1.0.0", "1.0.1"],
    "userGroups": ["beta", "premium"]
  },
  "deliverySettings": {
    "websocket": true,
    "fcm": true,
    "local": true,
    "scheduled": false,
    "scheduledFor": "2024-01-01T00:00:00Z"
  },
  "status": "draft|scheduled|sending|sent|completed",
  "statistics": {
    "totalSent": 0,
    "totalDelivered": 0,
    "totalFailed": 0,
    "deliveryRate": 0.0
  },
  "createdAt": "2024-01-01T00:00:00Z",
  "sentAt": "2024-01-01T00:00:00Z"
}
```

## Communication Types and Message Structures

### 1. WebSocket Messages

#### Connection Message
```json
{
  "type": "connect",
  "sessionId": "string",
  "userId": "string",
  "userName": "string",
  "deviceInfo": {
    "device": "Samsung Galaxy S21 (Android 12)",
    "browser": "Skybyn App",
    "platform": "Android",
    "version": "12",
    "brand": "Samsung",
    "model": "Galaxy S21"
  },
  "fcmToken": "string",
  "pushPlatform": "android|ios"
}
```

#### New Post Notification
```json
{
  "type": "new_post",
  "id": "postId",
  "sessionId": "string",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

#### New Comment Notification
```json
{
  "type": "new_comment",
  "pid": "postId",
  "cid": "commentId",
  "sessionId": "string",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

#### Broadcast Message
```json
{
  "type": "broadcast",
  "message": "Broadcast content",
  "sessionId": "string",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

#### App Update Notification
```json
{
  "type": "app_update",
  "updateInfo": {
    "version": "1.0.1",
    "forced": false,
    "downloadUrl": "https://api.skybyn.no/appUpdates/download.php",
    "changelog": "Bug fixes and improvements"
  },
  "sessionId": "string",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

#### Ping/Pong Messages
```json
{
  "type": "ping|pong",
  "sessionId": "string",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

### 2. Firebase Cloud Messaging (FCM) Messages

#### Data Message (Background)
```json
{
  "to": "fcm_token",
  "data": {
    "type": "new_post|new_comment|broadcast|app_update",
    "payload": "json_string",
    "postId": "string",
    "commentId": "string",
    "action": "string"
  },
  "priority": "high",
  "time_to_live": 3600
}
```

#### Notification Message (Foreground)
```json
{
  "to": "fcm_token",
  "notification": {
    "title": "Notification Title",
    "body": "Notification Body",
    "icon": "notification_icon",
    "color": "#2196F3",
    "sound": "default",
    "click_action": "FLUTTER_NOTIFICATION_CLICK"
  },
  "data": {
    "type": "new_post|new_comment|broadcast|app_update",
    "payload": "json_string"
  },
  "priority": "high",
  "time_to_live": 3600
}
```

#### Android-Specific FCM
```json
{
  "to": "fcm_token",
  "notification": {
    "title": "Notification Title",
    "body": "Notification Body",
    "icon": "notification_icon",
    "color": "#2196F3",
    "sound": "default"
  },
  "android": {
    "priority": "high",
    "notification": {
      "channel_id": "admin_notifications|feature_announcements|maintenance_alerts",
      "importance": "high",
      "visibility": "public",
      "enable_lights": true,
      "enable_vibration": true,
      "play_sound": true
    }
  },
  "data": {
    "type": "new_post|new_comment|broadcast|app_update",
    "payload": "json_string"
  }
}
```

#### iOS-Specific FCM
```json
{
  "to": "fcm_token",
  "notification": {
    "title": "Notification Title",
    "body": "Notification Body",
    "sound": "default",
    "badge": "1"
  },
  "apns": {
    "payload": {
      "aps": {
        "alert": {
          "title": "Notification Title",
          "body": "Notification Body"
        },
        "sound": "default",
        "badge": 1,
        "category": "GENERAL"
      }
    },
    "headers": {
      "apns-priority": "10",
      "apns-expiration": "3600"
    }
  },
  "data": {
    "type": "new_post|new_comment|broadcast|app_update",
    "payload": "json_string"
  }
}
```

### 3. Local Notification Structure

#### Android Local Notification
```json
{
  "channelId": "admin_notifications|feature_announcements|maintenance_alerts",
  "title": "Notification Title",
  "body": "Notification Body",
  "payload": "json_string",
  "priority": "high|normal|low",
  "importance": "max|high|default|low|min",
  "visibility": "public|private|secret",
  "enableVibration": true,
  "playSound": true,
  "enableLights": true,
  "icon": "@drawable/notification_icon",
  "color": "#2196F3"
}
```

#### iOS Local Notification
```json
{
  "title": "Notification Title",
  "body": "Notification Body",
  "payload": "json_string",
  "presentAlert": true,
  "presentBadge": true,
  "presentSound": true,
  "sound": "default",
  "badgeNumber": 1
}
```

## PHP Endpoint Structure

### Required PHP Endpoints

1. **Send WebSocket Message**
   - `POST /api/websocket/send.php`
   - Send real-time messages to connected clients

2. **Send FCM Notification**
   - `POST /api/fcm/send.php`
   - Send push notifications via Firebase

3. **Send Local Notification**
   - `POST /api/notification/local.php`
   - Trigger local notifications on devices

4. **Send Broadcast Message**
   - `POST /api/broadcast/send.php`
   - Send messages to multiple users

5. **Send App Update Notification**
   - `POST /api/update/notify.php`
   - Notify users about app updates

6. **Register FCM Token**
   - `POST /api/push/register_token.php`
   - Register device FCM tokens

7. **Update User Device Info**
   - `POST /api/user/device_info.php`
   - Update user's device information

### Sample PHP Endpoint Implementation

```php
<?php
// /api/communication/send.php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true);

// Validate required fields
$requiredFields = ['type', 'targetUsers', 'message'];
foreach ($requiredFields as $field) {
    if (!isset($input[$field])) {
        http_response_code(400);
        echo json_encode(['error' => "Missing required field: $field"]);
        exit;
    }
}

$type = $input['type'];
$targetUsers = $input['targetUsers'];
$message = $input['message'];

// Determine delivery methods based on type
$deliveryMethods = [];
switch ($type) {
    case 'new_post':
    case 'new_comment':
        $deliveryMethods = ['websocket', 'fcm', 'local'];
        break;
    case 'broadcast':
        $deliveryMethods = ['websocket', 'fcm', 'local'];
        break;
    case 'app_update':
        $deliveryMethods = ['websocket', 'fcm', 'local'];
        break;
    case 'admin':
        $deliveryMethods = ['fcm', 'local'];
        break;
    default:
        $deliveryMethods = ['fcm'];
}

// Send via each delivery method
$results = [];

if (in_array('websocket', $deliveryMethods)) {
    $results['websocket'] = sendWebSocketMessage($type, $targetUsers, $message);
}

if (in_array('fcm', $deliveryMethods)) {
    $results['fcm'] = sendFCMMessage($type, $targetUsers, $message);
}

if (in_array('local', $deliveryMethods)) {
    $results['local'] = sendLocalNotification($type, $targetUsers, $message);
}

echo json_encode([
    'success' => true,
    'results' => $results,
    'timestamp' => date('c')
]);

function sendWebSocketMessage($type, $targetUsers, $message) {
    // Implementation for WebSocket message sending
    // This would connect to your WebSocket server and broadcast the message
    return ['status' => 'sent', 'count' => count($targetUsers)];
}

function sendFCMMessage($type, $targetUsers, $message) {
    // Implementation for FCM message sending
    // This would use Firebase Admin SDK to send push notifications
    return ['status' => 'sent', 'count' => count($targetUsers)];
}

function sendLocalNotification($type, $targetUsers, $message) {
    // Implementation for local notification triggering
    // This would store the notification in database for devices to fetch
    return ['status' => 'sent', 'count' => count($targetUsers)];
}
?>
```

## Usage Examples

### 1. Send New Post Notification
```bash
curl -X POST https://api.skybyn.no/api/communication/send.php \
  -H "Content-Type: application/json" \
  -d '{
    "type": "new_post",
    "targetUsers": ["user1", "user2"],
    "message": {
      "postId": "post123",
      "title": "New Post",
      "body": "Someone posted something new"
    }
  }'
```

### 2. Send Broadcast Message
```bash
curl -X POST https://api.skybyn.no/api/communication/send.php \
  -H "Content-Type: application/json" \
  -d '{
    "type": "broadcast",
    "targetUsers": ["all"],
    "message": {
      "title": "Maintenance Notice",
      "body": "Scheduled maintenance will occur tonight at 2 AM"
    }
  }'
```

### 3. Send App Update Notification
```bash
curl -X POST https://api.skybyn.no/api/communication/send.php \
  -H "Content-Type: application/json" \
  -d '{
    "type": "app_update",
    "targetUsers": ["all"],
    "message": {
      "version": "1.0.1",
      "forced": false,
      "downloadUrl": "https://api.skybyn.no/appUpdates/download.php?version=1.0.1",
      "changelog": "Bug fixes and improvements"
    }
  }'
```

This structure provides a comprehensive foundation for implementing all communication methods that your Skybyn mobile app can handle, allowing you to send updates and notifications through multiple channels based on the specific requirements of each message type.
