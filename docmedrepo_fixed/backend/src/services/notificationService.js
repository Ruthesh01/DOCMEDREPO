'use strict';

let firebaseAdmin = null;

/**
 * Lazily initialises the Firebase Admin SDK.
 * Skipped in test environment.
 */
function getFirebaseAdmin() {
  if (process.env.NODE_ENV === 'test') return null;
  if (firebaseAdmin) return firebaseAdmin;

  const admin = require('firebase-admin');
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId:    process.env.FIREBASE_PROJECT_ID,
        clientEmail:  process.env.FIREBASE_CLIENT_EMAIL,
        privateKey:   (process.env.FIREBASE_PRIVATE_KEY || '').replace(/\\n/g, '\n'),
      }),
    });
  }
  firebaseAdmin = admin;
  return admin;
}

/**
 * Sends a push notification to a device via FCM.
 * @param {string} fcmToken - The device's FCM registration token
 * @param {{ title: string, body: string, data?: object }} notification
 * @returns {Promise<void>}
 */
async function sendPushNotification(fcmToken, { title, body, data = {} }) {
  const admin = getFirebaseAdmin();
  if (!admin) return; // no-op in test env

  try {
    await admin.messaging().send({
      token:        fcmToken,
      notification: { title, body },
      data:         Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
      ),
    });
    console.log(`[FCM] Notification sent: "${title}"`);
  } catch (err) {
    // Don't let FCM failure crash critical flows
    console.error('[FCM] Failed to send notification:', err.message);
  }
}

module.exports = { sendPushNotification };
