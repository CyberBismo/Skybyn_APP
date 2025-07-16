import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// Send notification to all devices where the current user is logged in
export const sendToAllUserDevices = functions.https.onCall(async (data, context) => {
  try {
    // Check if user is authenticated
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const userId = context.auth.uid;
    const { title, body, payload, data: notificationData } = data;

    console.log(`Sending notification to all devices for user: ${userId}`);

    // Get all FCM tokens for this user
    const userTokensSnapshot = await db
      .collection('user_tokens')
      .where('userId', '==', userId)
      .get();

    if (userTokensSnapshot.empty) {
      console.log(`No tokens found for user: ${userId}`);
      return { success: true, message: 'No devices found for user' };
    }

    const tokens = userTokensSnapshot.docs.map(doc => doc.data().fcmToken);
    console.log(`Found ${tokens.length} tokens for user: ${userId}`);

    // Send notification to all user devices
    const message: admin.messaging.MulticastMessage = {
      tokens: tokens,
      notification: {
        title: title,
        body: body,
      },
      data: {
        ...notificationData,
        payload: payload || '',
        timestamp: new Date().toISOString(),
      },
      android: {
        notification: {
          channelId: 'admin_notifications',
          priority: 'high',
        },
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title: title,
              body: body,
            },
            badge: 1,
            sound: 'default',
          },
        },
      },
    };

    const response = await messaging.sendMulticast(message);
    console.log(`Successfully sent messages: ${response.successCount}/${tokens.length}`);

    if (response.failureCount > 0) {
      const failedTokens: string[] = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          failedTokens.push(tokens[idx]);
        }
      });
      console.log('List of tokens that caused failures: ' + failedTokens);
    }

    return {
      success: true,
      message: `Successfully sent to ${response.successCount}/${tokens.length} devices`,
      successCount: response.successCount,
      failureCount: response.failureCount,
    };

  } catch (error) {
    console.error('Error sending notification:', error);
    throw new functions.https.HttpsError('internal', 'Failed to send notification');
  }
});

// Send notification to a specific user by user ID
export const sendToUser = functions.https.onCall(async (data, context) => {
  try {
    // Check if user is authenticated
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const { userId, title, body, payload, data: notificationData } = data;

    console.log(`Sending notification to user: ${userId}`);

    // Get all FCM tokens for the specified user
    const userTokensSnapshot = await db
      .collection('user_tokens')
      .where('userId', '==', userId)
      .get();

    if (userTokensSnapshot.empty) {
      console.log(`No tokens found for user: ${userId}`);
      return { success: true, message: 'No devices found for user' };
    }

    const tokens = userTokensSnapshot.docs.map(doc => doc.data().fcmToken);
    console.log(`Found ${tokens.length} tokens for user: ${userId}`);

    // Send notification to all user devices
    const message: admin.messaging.MulticastMessage = {
      tokens: tokens,
      notification: {
        title: title,
        body: body,
      },
      data: {
        ...notificationData,
        payload: payload || '',
        timestamp: new Date().toISOString(),
      },
      android: {
        notification: {
          channelId: 'admin_notifications',
          priority: 'high',
        },
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title: title,
              body: body,
            },
            badge: 1,
            sound: 'default',
          },
        },
      },
    };

    const response = await messaging.sendMulticast(message);
    console.log(`Successfully sent messages: ${response.successCount}/${tokens.length}`);

    return {
      success: true,
      message: `Successfully sent to ${response.successCount}/${tokens.length} devices`,
      successCount: response.successCount,
      failureCount: response.failureCount,
    };

  } catch (error) {
    console.error('Error sending notification:', error);
    throw new functions.https.HttpsError('internal', 'Failed to send notification');
  }
});

// Send notification to all users (admin function)
export const sendToAllUsers = functions.https.onCall(async (data, context) => {
  try {
    // Check if user is authenticated
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    // TODO: Add admin check here if needed
    // const userDoc = await db.collection('users').doc(context.auth.uid).get();
    // if (!userDoc.exists || !userDoc.data()?.isAdmin) {
    //   throw new functions.https.HttpsError('permission-denied', 'Admin access required');
    // }

    const { title, body, payload, data: notificationData } = data;

    console.log('Sending notification to all users');

    // Get all FCM tokens
    const allTokensSnapshot = await db.collection('user_tokens').get();

    if (allTokensSnapshot.empty) {
      console.log('No tokens found for any users');
      return { success: true, message: 'No devices found' };
    }

    const tokens = allTokensSnapshot.docs.map(doc => doc.data().fcmToken);
    console.log(`Found ${tokens.length} total tokens`);

    // Send notification to all devices
    const message: admin.messaging.MulticastMessage = {
      tokens: tokens,
      notification: {
        title: title,
        body: body,
      },
      data: {
        ...notificationData,
        payload: payload || '',
        timestamp: new Date().toISOString(),
      },
      android: {
        notification: {
          channelId: 'admin_notifications',
          priority: 'high',
        },
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title: title,
              body: body,
            },
            badge: 1,
            sound: 'default',
          },
        },
      },
    };

    const response = await messaging.sendMulticast(message);
    console.log(`Successfully sent messages: ${response.successCount}/${tokens.length}`);

    return {
      success: true,
      message: `Successfully sent to ${response.successCount}/${tokens.length} devices`,
      successCount: response.successCount,
      failureCount: response.failureCount,
    };

  } catch (error) {
    console.error('Error sending notification:', error);
    throw new functions.https.HttpsError('internal', 'Failed to send notification');
  }
});

// Function to store FCM token when user logs in
export const storeFCMToken = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const { fcmToken, deviceInfo } = data;
    const userId = context.auth.uid;

    console.log(`Storing FCM token for user: ${userId}`);

    // Store the token in Firestore
    await db.collection('user_tokens').add({
      userId: userId,
      fcmToken: fcmToken,
      deviceInfo: deviceInfo || {},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastUsed: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`FCM token stored for user: ${userId}`);

    return { success: true, message: 'Token stored successfully' };

  } catch (error) {
    console.error('Error storing FCM token:', error);
    throw new functions.https.HttpsError('internal', 'Failed to store token');
  }
});

// Function to update FCM token (called by notification service)
export const updateFcmToken = functions.https.onCall(async (data, context) => {
  try {
    // Allow unauthenticated calls for token updates (needed for hybrid auth)
    const { token, deviceInfo } = data;
    
    if (!token) {
      throw new functions.https.HttpsError('invalid-argument', 'FCM token is required');
    }

    console.log('Updating FCM token');

    // If user is authenticated, store with user ID
    if (context.auth) {
      const userId = context.auth.uid;
      
      // Check if token already exists for this user
      const existingToken = await db
        .collection('user_tokens')
        .where('userId', '==', userId)
        .where('fcmToken', '==', token)
        .get();

      if (existingToken.empty) {
        // Store new token
        await db.collection('user_tokens').add({
          userId: userId,
          fcmToken: token,
          deviceInfo: deviceInfo || {},
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          lastUsed: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`New FCM token stored for user: ${userId}`);
      } else {
        // Update last used timestamp
        await existingToken.docs[0].ref.update({
          lastUsed: admin.firestore.FieldValue.serverTimestamp(),
          deviceInfo: deviceInfo || {},
        });
        console.log(`FCM token updated for user: ${userId}`);
      }
    } else {
      // Store token without user ID (for hybrid auth systems)
      await db.collection('user_tokens').add({
        fcmToken: token,
        deviceInfo: deviceInfo || {},
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastUsed: admin.firestore.FieldValue.serverTimestamp(),
        authType: 'hybrid',
      });
      console.log('FCM token stored for hybrid auth system');
    }

    return { success: true, message: 'Token updated successfully' };

  } catch (error) {
    console.error('Error updating FCM token:', error);
    throw new functions.https.HttpsError('internal', 'Failed to update token');
  }
}); 