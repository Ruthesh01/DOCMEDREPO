'use strict';

const Redis = require('ioredis');

let redisClient = null;

/**
 * Creates and connects a shared Redis client.
 * Used by Bull queues and workers.
 * @returns {Promise<Redis>}
 */
async function connectRedis() {
  const url = process.env.REDIS_URL;
  if (!url) throw new Error('REDIS_URL is not defined in environment variables');

  redisClient = new Redis(url, {
    maxRetriesPerRequest: null, // required by Bull
    enableReadyCheck: false,
    lazyConnect: true,
  });

  redisClient.on('connect', () => console.log('[Redis] Connected'));
  redisClient.on('error', (err) => console.error('[Redis] Error:', err));

  await redisClient.connect();
  return redisClient;
}

/**
 * Returns the active Redis client instance.
 * @returns {Redis}
 */
function getRedisClient() {
  if (!redisClient) throw new Error('Redis client not initialised. Call connectRedis() first.');
  return redisClient;
}

/**
 * Closes the Redis connection gracefully.
 * @returns {Promise<void>}
 */
async function disconnectRedis() {
  if (redisClient) {
    await redisClient.quit();
    redisClient = null;
    console.log('[Redis] Connection closed');
  }
}

module.exports = { connectRedis, getRedisClient, disconnectRedis };
