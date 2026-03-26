'use strict';

const { Router } = require('express');
const mongoose = require('mongoose');
const { getRedisClient } = require('../config/redis');
const pkg = require('../../package.json');

const router = Router();

router.get('/', async (req, res) => {
  try {
    const mongoStatus = mongoose.connection.readyState === 1 ? 'connected' : 'disconnected';
    
    let redisStatus = 'disconnected';
    try {
      const redisClient = getRedisClient();
      await redisClient.ping();
      redisStatus = 'connected';
    } catch (err) {
      redisStatus = 'error';
    }

    const isHealthy = mongoStatus === 'connected' && redisStatus === 'connected';

    res.status(isHealthy ? 200 : 503).json({
      status: isHealthy ? 'ok' : 'error',
      version: pkg.version,
      timestamp: new Date().toISOString(),
      services: {
        mongodb: mongoStatus,
        redis: redisStatus,
      }
    });
  } catch (error) {
    res.status(503).json({
      status: 'error',
      version: pkg.version,
      timestamp: new Date().toISOString(),
      error: error.message
    });
  }
});

module.exports = router;
