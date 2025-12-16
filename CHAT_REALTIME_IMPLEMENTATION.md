# Real-Time Chat Implementation Documentation

## Overview

The Skybyn app implements real-time chat messaging using WebSockets for instant delivery. This document explains the complete message flow, filtering logic, and recent improvements.

## Architecture

### Components

1. **WebSocketService** (`lib/services/websocket_service.dart`)
   - Maintains persistent WebSocket connection to server
   - Handles all real-time message types (chat, calls, notifications, etc.)
   - Manages message callbacks and routing

2. **ChatService** (`lib/services/chat_service.dart`)
   - Handles sending messages via WebSocket
   - Manages message caching and offline notifications
   - Provides API for chat operations

3. **ChatScreen** (`lib/screens/chat_screen.dart`)
   - Displays messages for a specific conversation
   - Registers WebSocket listener for real-time updates
   - Handles message rendering and user interactions

4. **Global Chat Listener** (`lib/main.dart`)
   - Monitors all incoming chat messages
   - Updates unread badge counts
   - Shows notifications (system/in-app)
   - **Filters out user's own messages to prevent self-notifications**

## Message Flow

### Sending a Message (User A → User B)

```
1. User A types message in ChatScreen
2. ChatScreen._sendMessage() called
3. ChatService.sendMessage() invoked
4. WebSocketService.sendChatMessage() sends to server
   ↓
   Message: {
     type: 'chat',
     from: 'user_a_id',
     to: 'user_b_id',
     message: 'Hello!'
   }
   ↓
5. Server receives and processes message
6. Server assigns permanent message ID and stores in database
7. Server sends TWO WebSocket messages:
   a) To User B: { type: 'chat', id: 'real_123', from: 'user_a_id', to: 'user_b_id', message: 'Hello!' }
   b) To User A: { type: 'chat_sent', id: 'real_123', from: 'user_a_id', to: 'user_b_id', message: 'Hello!' }
```

### Receiving Messages (User B)

```
1. WebSocketService._handleMessage() receives message
2. Case 'chat': Extracts messageId, fromUserId, toUserId, message
3. Triggers ALL registered callbacks in _onChatMessageCallbacks:
   
   a) Global Listener (main.dart):
      - Checks: toUserId == currentUserId? ✓ (message is for me)
      - Checks: fromUserId == currentUserId? ✗ (message is NOT from me)
      - ✅ Increments unread badge count
      - ✅ Shows notification (if not already in chat)
   
   b) ChatScreen Listener (if User B has chat open):
      - Checks: Is message for this conversation?
      - Checks: Message already exists (by ID)?
      - Checks: Duplicate by content/timestamp?
      - ✅ Adds message to UI immediately
      - ✅ Scrolls to bottom to show new message
```

### Message Confirmation (User A)

```
1. WebSocketService receives 'chat_sent' confirmation
2. Triggers callbacks with real message ID
3. ChatScreen Listener:
   - Finds optimistic message (temp_xxx)
   - Updates it with real ID from server
   - Prevents duplicate by early return
```

## Filtering Logic

### Global Listener (main.dart - Badge Counts & Notifications)

**Purpose**: Update unread counts and show notifications

**Filtering Rules**:
```dart
// Line 665-670 in main.dart
if (currentUserId == null) {
  // Skip - not logged in
} else if (toUserId != currentUserId) {
  // Skip - message not for current user
} else if (fromUserId == currentUserId) {
  // ✅ SKIP - message from self (prevents self-notifications)
} else {
  // Process - message is for me from someone else
}
```

**Result**: User A will **NEVER** get notifications for their own messages ✅

### ChatScreen Listener (chat_screen.dart - Display Messages)

**Purpose**: Display messages in the active chat conversation

**Filtering Rules**:
```dart
// Lines 421-429 in chat_screen.dart
if (!mounted || _currentUserId == null) return;

// Only handle messages between current user and this friend
final isMessageForThisChat =
  (fromUserId == _currentUserId && toUserId == widget.friend.id) ||  // We sent to friend
  (fromUserId == widget.friend.id && toUserId == _currentUserId);    // Friend sent to us

if (isMessageForThisChat) {
  _handleIncomingChatMessage(...);
}
```

**Duplicate Prevention**:
```dart
// Lines 447-462 in chat_screen.dart

// 1. Check by message ID
if (_messages.any((m) => m.id == messageId)) {
  return; // Already exists
}

// 2. Check by content, sender, and timestamp (prevents race condition)
final isDuplicateByContent = _messages.any((m) =>
  m.content == messageContent &&
  m.from == fromUserId &&
  m.to == toUserId &&
  now.difference(m.date).inSeconds.abs() < 5 // Within 5 seconds
);

if (isDuplicateByContent) {
  return; // Duplicate detected
}
```

**Result**: 
- User A sees their own messages in the chat (marked with `isFromMe: true`) ✅
- User A doesn't see duplicate messages (even with race conditions) ✅
- User A doesn't see messages from other conversations ✅

## Recent Improvements

### 1. Content-Based Duplicate Detection (Added)

**Problem**: Race condition where `chat_sent` arrives before optimistic message is added, causing brief duplicates.

**Solution**: Added content + timestamp duplicate detection in addition to ID-based detection.

**Code**: Lines 454-462 in `chat_screen.dart`

### 2. Stricter Message Filtering (Improved)

**Problem**: Old logic used `toUserId == friend.id OR fromUserId == friend.id` which could match unrelated messages.

**Solution**: Now explicitly checks that message is BETWEEN current user and friend only.

**Code**: Lines 421-429 in `chat_screen.dart`

### 3. Self-Message Filtering (Verified Correct)

**Status**: ✅ Already implemented correctly

**Behavior**:
- **Global Listener**: Skips messages from self (no self-notifications)
- **Chat Screen**: Processes messages from self (displays in chat with `isFromMe` flag)

## Test Scenarios

### Scenario 1: User A sends message to User B

**Expected Behavior**:
1. ✅ User A sees message immediately on right side (from me)
2. ✅ User B sees message immediately on left side (from friend)
3. ✅ User A does NOT get notification
4. ✅ User B gets notification (if not in chat)
5. ✅ User B's unread badge increments (if not in chat)

### Scenario 2: Both users in chat, sending back and forth

**Expected Behavior**:
1. ✅ Messages appear immediately for both users
2. ✅ No notifications shown (chat is open)
3. ✅ No unread badges increment
4. ✅ No duplicates appear
5. ✅ Messages correctly labeled (from me vs from friend)

### Scenario 3: User A sends message, User B offline

**Expected Behavior**:
1. ✅ User A sees message immediately
2. ✅ Server sends `chat_offline` to User A
3. ✅ User A's app sends Firebase push notification to User B
4. ✅ User B receives push notification
5. ✅ When User B opens app, message is there

### Scenario 4: Rapid message sending (race condition test)

**Expected Behavior**:
1. ✅ User sends multiple messages quickly
2. ✅ All messages appear once (no duplicates)
3. ✅ Content-based deduplication prevents race condition duplicates
4. ✅ Messages appear in correct order

## WebSocket Message Types

### Incoming Message Types

| Type | Description | Sender Gets | Recipient Gets |
|------|-------------|-------------|----------------|
| `chat` | New message | ❌ No | ✅ Yes |
| `chat_sent` | Confirmation | ✅ Yes | ❌ No |
| `chat_offline` | Recipient offline | ✅ Yes (trigger FCM) | ❌ No |

### Message Structure

```json
{
  "type": "chat",
  "id": "12345",
  "from": "user_a_id",
  "to": "user_b_id",
  "message": "Hello!",
  "date": "2024-01-15T10:30:00Z"
}
```

## Debugging

### Enable Chat Logging

Look for these log messages:

```dart
// In main.dart (Global Listener)
'[SKYBYN] 🔵 [Main Chat Listener] WebSocket message received'
'[SKYBYN] ⏭️ [Main Chat Listener] Skipping - message from self'
'[SKYBYN] ✅ [Main Chat Listener] Unread count incremented'

// In chat_screen.dart
'[SKYBYN] ✅ [Chat] Message stored in database successfully'
'[SKYBYN] ⚠️ [Chat] Failed to store message in database'
```

### Common Issues

1. **Messages not appearing**: Check WebSocket connection status
2. **Duplicate messages**: Verify deduplication logic is working
3. **Self-notifications**: Check global listener filtering
4. **Messages in wrong chat**: Verify conversation filtering logic

## Code References

- **WebSocket Service**: `lib/services/websocket_service.dart`
  - Message handling: Lines 437-800
  - Send chat message: Lines 1082-1110

- **Chat Service**: `lib/services/chat_service.dart`
  - Send message: Lines 195-280

- **Chat Screen**: `lib/screens/chat_screen.dart`
  - Setup WebSocket listener: Lines 406-430
  - Handle incoming message: Lines 444-575
  - Send message: Lines 752-835

- **Global Listener**: `lib/main.dart`
  - Setup global chat listener: Lines 645-900
  - Self-message filtering: Lines 665-670

## Conclusion

The real-time chat implementation is robust with proper filtering to ensure:

1. ✅ Both users receive messages immediately
2. ✅ User A ignores their own messages for notifications
3. ✅ User A sees their own messages in chat interface
4. ✅ No duplicate messages (with race condition protection)
5. ✅ Proper conversation isolation
6. ✅ Offline message handling with Firebase push notifications

The system correctly handles all edge cases including race conditions, offline users, and rapid message sending.