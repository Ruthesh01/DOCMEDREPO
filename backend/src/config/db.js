'use strict';

const mongoose = require('mongoose');

/**
 * Connects to MongoDB using the URI from environment variables.
 * Exits the process on failure so the app never starts in a broken state.
 * @returns {Promise<void>}
 */
async function connectDB() {
  const uri = process.env.MONGODB_URI;
  if (!uri) throw new Error('MONGODB_URI is not defined in environment variables');

  mongoose.connection.on('connected', () => console.log('[MongoDB] Connected'));
  mongoose.connection.on('error', (err) => console.error('[MongoDB] Error:', err));
  mongoose.connection.on('disconnected', () => console.warn('[MongoDB] Disconnected'));

  await mongoose.connect(uri, {
    autoIndex: process.env.NODE_ENV !== 'production', // disable in prod for perf
  });
}

/**
 * Gracefully closes the MongoDB connection.
 * @returns {Promise<void>}
 */
async function disconnectDB() {
  await mongoose.connection.close();
  console.log('[MongoDB] Connection closed');
}

module.exports = { connectDB, disconnectDB };
