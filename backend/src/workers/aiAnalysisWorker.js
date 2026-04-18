'use strict';

const axios = require('axios');
const FormData = require('form-data');
const fs = require('fs');
const path = require('path');
const Report = require('../models/Report');
const { getAnalysisQueue } = require('../queues/aiAnalysisQueue');
const { sendPushNotification } = require('../services/notificationService');
const Patient = require('../models/Patient');

const AI_SERVICE_URL = process.env.AI_ANALYZER_URL || 'http://localhost:8000';

// Shared secret sent as a header so FastAPI can reject unknown callers.
// Must match AI_SERVICE_SECRET in the FastAPI environment (H-01 fix).
const AI_SERVICE_SECRET = process.env.AI_SERVICE_SECRET || '';

if (process.env.NODE_ENV === 'production' && !AI_SERVICE_SECRET) {
  throw new Error('AI_SERVICE_SECRET must be set in production to encrypt inter-service traffic');
}

/**
 * Processes a single AI analysis job.
 * Fetches the report, calls the FastAPI analyzer, updates the DB,
 * and sends a push notification to the patient.
 * @param {Bull.Job} job
 */
async function processAnalysisJob(job) {
  const { reportId } = job.data;
  console.log(`[AIWorker] Processing job ${job.id} for report ${reportId}`);

  // Mark as processing
  await Report.findByIdAndUpdate(reportId, { analysisStatus: 'processing' });

  const report = await Report.findById(reportId).populate('patientId', 'fcmToken name');
  if (!report) {
    throw new Error(`Report ${reportId} not found`);
  }

  let result;
  // L-05 FIX: Pass the Bull job ID as X-Correlation-Id so FastAPI logs and
  // Node logs can be matched when debugging a specific report failure.
  const correlationHeaders = { 'X-Correlation-Id': String(job.id) };

  if (process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'development') {
    // In dev mode, the file is saved locally. We read it and POST as multipart to FastAPI.
    const filePath = path.join(__dirname, '../../uploads', report.fileUrl);
    if (!fs.existsSync(filePath)) throw new Error(`Local file missing at ${filePath}`);

    const form = new FormData();
    form.append('file', fs.createReadStream(filePath), {
      contentType: report.fileType === 'pdf'
        ? 'application/pdf'
        : `image/${report.fileType === 'jpg' ? 'jpeg' : report.fileType}`,
    });

    const response = await axios.post(`${AI_SERVICE_URL}/analyze/upload`, form, {
      headers: {
        ...form.getHeaders(),
        'X-Internal-Secret': AI_SERVICE_SECRET,
        ...correlationHeaders,  // L-05: correlation ID for cross-service tracing
      },
      timeout: 60000,
    });
    result = response.data;
  } else {
    // In production, send the S3 key and let FastAPI download it securely.
    const response = await axios.post(
      `${AI_SERVICE_URL}/analyze`,
      { s3_key: report.fileUrl, file_type: report.fileType },
      {
        headers: {
          'X-Internal-Secret': AI_SERVICE_SECRET,
          ...correlationHeaders,  // L-05: correlation ID for cross-service tracing
        },
        timeout: 60000,
      }
    );
    result = response.data;
  }

  // H-02 FIX: The FastAPI analyzer already appends the low-confidence warning
  // to both summaries when confidence_score < 0.6. The previous code appended
  // it again here, causing every low-confidence report to show the warning
  // twice to the patient and doctor. The duplicate append is removed entirely.
  await Report.findByIdAndUpdate(reportId, {
    analysisStatus: 'complete',
    aiSummary: {
      diagnoses:            result.diagnoses             || [],
      abnormalValues:       result.abnormal_values       || [],
      medicationsMentioned: result.medications_mentioned || [],
      summaryForPatient:    result.summary_for_patient   || '',
      summaryForDoctor:     result.summary_for_doctor    || '',
      confidenceScore:      result.confidence_score      || 0,
      source:               result.source                || 'primary',
    },
  });

  // Push notification to patient
  if (report.patientId?.fcmToken) {
    await sendPushNotification(
      report.patientId.fcmToken,
      {
        title: 'Your report is ready',
        body:  'AI analysis complete. Tap to view your results.',
        data:  { type: 'report_ready', reportId: report._id.toString() },
      }
    );
  }

  console.log(`[AIWorker] Job ${job.id} completed for report ${reportId}`);
}

/**
 * Handles permanent job failure after all retries are exhausted.
 * Marks the report as 'failed' and notifies the patient.
 * @param {Bull.Job} job
 * @param {Error} err
 */
async function handleFailedJob(job, err) {
  const { reportId } = job.data;
  console.error(`[AIWorker] Job ${job.id} permanently failed for report ${reportId}:`, err.message);

  const report = await Report.findByIdAndUpdate(
    reportId,
    { analysisStatus: 'failed' },
    { new: true }
  ).populate('patientId', 'fcmToken');

  if (report?.patientId?.fcmToken) {
    await sendPushNotification(
      report.patientId.fcmToken,
      {
        title: 'Analysis failed',
        body:  'We could not analyse your report. Please try re-uploading.',
        data:  { type: 'report_failed', reportId },
      }
    );
  }
}

/**
 * Registers the worker process on the analysis queue.
 * Should be called once at server startup.
 */
function initWorker() {
  const queue = getAnalysisQueue();

  queue.process(1, processAnalysisJob); // concurrency: 1 to avoid overloading AI service

  queue.on('failed', (job, err) => {
    // Only call handleFailedJob when all retries are exhausted
    if (job.attemptsMade >= job.opts.attempts) {
      handleFailedJob(job, err).catch(console.error);
    }
  });

  console.log('[AIWorker] Worker initialised and listening for jobs');
}

module.exports = { initWorker, processAnalysisJob };
