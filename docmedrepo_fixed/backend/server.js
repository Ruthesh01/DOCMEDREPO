'use strict';

require('dotenv').config();

const app = require('./src/app');
const { connectDB } = require('./src/config/db');
const { connectRedis } = require('./src/config/redis');
const { initWorker } = require('./src/workers/aiAnalysisWorker');

const PORT = process.env.PORT || 5000;

/**
 * Bootstraps the server: connects to DB, Redis, starts worker, then listens.
 */
async function bootstrap() {
  try {
    await connectDB();
    await connectRedis();
    initWorker();

    app.listen(PORT, () => {
      console.log(`[Server] Running on port ${PORT} in ${process.env.NODE_ENV} mode`);
    });
  } catch (err) {
    console.error('[Server] Fatal startup error:', err);
    process.exit(1);
  }
}

bootstrap();
