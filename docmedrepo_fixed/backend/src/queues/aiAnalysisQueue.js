'use strict';

const Bull = require('bull');

// Jittered-exponential backoff: base delay doubles per attempt (5s → 10s → 20s)
// plus 0–2s random jitter. Must be passed in queue settings (Bull 4.x).
function jitteredExponential(attemptsMade) {
  const base   = 5000 * Math.pow(2, attemptsMade - 1);
  const jitter = Math.floor(Math.random() * 2000);
  return base + jitter;
}

let analysisQueue = null;

/**
 * Returns (or lazily creates) the AI analysis Bull queue.
 * Using lazy init so tests can run without Redis.
 * @returns {Bull.Queue}
 */
function getAnalysisQueue() {
  if (!analysisQueue) {
    const redisUrl = process.env.REDIS_URL;
    if (!redisUrl) throw new Error('REDIS_URL is not defined');

    analysisQueue = new Bull('ai-analysis', redisUrl, {
      defaultJobOptions: {
        attempts: 3,
        backoff: {
          type: 'jittered-exponential',
        },
        removeOnComplete: true,
        removeOnFail:     false, // keep failed jobs for debugging
      },
      settings: {
        backoffStrategies: {
          'jittered-exponential': jitteredExponential,
        },
      },
    });

    analysisQueue.on('error', (err) => {
      console.error('[AIQueue] Queue error:', err);
    });
  }
  return analysisQueue;
}

/**
 * Adds a new AI analysis job to the queue.
 * @param {{ reportId: string }} data
 * @returns {Promise<Bull.Job>}
 */
async function addAnalysisJob(data) {
  const queue = getAnalysisQueue();
  const job = await queue.add(data);
  console.log(`[AIQueue] Job ${job.id} queued for report ${data.reportId}`);
  return job;
}

module.exports = { getAnalysisQueue, addAnalysisJob };
