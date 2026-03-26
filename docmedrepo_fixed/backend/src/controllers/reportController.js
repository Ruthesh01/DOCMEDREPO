'use strict';

const multer = require('multer');
const Report = require('../models/Report');
const fs = require('fs');
const path = require('path');
const { uploadFileToS3, getSignedUrl, deleteFileFromS3 } = require('../services/storageService');
const { addAnalysisJob } = require('../queues/aiAnalysisQueue');

// ── Magic byte signatures for allowed file types ─────────────────────────────
const MAGIC_BYTES = {
  pdf: Buffer.from([0x25, 0x50, 0x44, 0x46]),        // %PDF
  jpg: Buffer.from([0xFF, 0xD8, 0xFF]),               // JPEG SOI
  png: Buffer.from([0x89, 0x50, 0x4E, 0x47]),         // PNG signature
};

const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10 MB

/**
 * Detects file type by reading magic bytes.
 * @param {Buffer} buffer - File buffer
 * @returns {'pdf'|'jpg'|'png'|null}
 */
function detectFileType(buffer) {
  for (const [type, signature] of Object.entries(MAGIC_BYTES)) {
    if (buffer.slice(0, signature.length).equals(signature)) return type;
  }
  return null;
}

// Store file in memory for validation before S3 upload
const upload = multer({
  storage: multer.memoryStorage(),
  limits:  { fileSize: MAX_FILE_SIZE },
}).single('report');

/**
 * Handles report upload: validates file type via magic bytes, stores in S3,
 * creates Report record, and queues AI analysis job.
 * POST /api/reports/upload
 */
async function uploadReport(req, res, next) {
  upload(req, res, async (err) => {
    if (err instanceof multer.MulterError && err.code === 'LIMIT_FILE_SIZE') {
      return res.status(400).json({ error: 'File exceeds the 10MB size limit' });
    }
    if (err) return next(err);
    if (!req.file) return res.status(400).json({ error: 'No file provided' });

    try {
      const fileType = detectFileType(req.file.buffer);
      if (!fileType) {
        return res.status(400).json({ error: 'Invalid file type. Only PDF, JPG, and PNG are allowed.' });
      }

      const s3Key = await uploadFileToS3(req.file.buffer, fileType, req.user._id.toString());

      const report = await Report.create({
        patientId:   req.user._id,
        uploadedBy:  req.user._id,
        fileUrl:     s3Key,
        fileType,
        description: req.body.description || '',
      });

      // Queue async AI analysis
      await addAnalysisJob({ reportId: report._id.toString() });

      res.status(201).json({
        message:        'Report uploaded. AI analysis has been queued.',
        report: {
          id:             report._id,
          fileType:       report.fileType,
          description:    report.description,
          analysisStatus: report.analysisStatus,
          createdAt:      report.createdAt,
        },
      });
    } catch (uploadErr) {
      next(uploadErr);
    }
  });
}

/**
 * Returns a pre-signed S3 URL (15 min expiry) for a specific report.
 * GET /api/reports/:id/url
 */
async function getReportUrl(req, res, next) {
  try {
    const report = await Report.findById(req.params.id);
    if (!report) return res.status(404).json({ error: 'Report not found' });

    if (req.role === 'patient') {
      if (report.patientId.toString() !== req.user._id.toString()) {
        return res.status(403).json({ error: 'Access denied' });
      }
    } else if (req.role === 'doctor' || req.role === 'admin') {
      const { token } = req.query;
      if (!token) return res.status(400).json({ error: 'QR token is required' });
      
      const QrToken = require('../models/QrToken');
      const qrRecord = await QrToken.findOne({ token, patientId: report.patientId });
      if (!qrRecord || new Date() > qrRecord.expiresAt) {
        return res.status(401).json({ error: 'Valid QR token is required' });
      }
    }

    const url = await getSignedUrl(report.fileUrl);
    res.status(200).json({ url, expiresInSeconds: 900 });
  } catch (err) {
    next(err);
  }
}

/**
 * Retrieves a single report's details.
 * GET /api/reports/:id
 */
async function getReport(req, res, next) {
  try {
    const report = await Report.findById(req.params.id);
    if (!report) return res.status(404).json({ error: 'Report not found' });

    if (req.role === 'patient') {
      if (report.patientId.toString() !== req.user._id.toString()) {
        return res.status(403).json({ error: 'Access denied' });
      }
    } else if (req.role === 'doctor' || req.role === 'admin') {
      const { token } = req.query;
      if (!token) return res.status(400).json({ error: 'QR token is required' });
      
      const QrToken = require('../models/QrToken');
      const qrRecord = await QrToken.findOne({ token, patientId: report.patientId });
      if (!qrRecord || new Date() > qrRecord.expiresAt) {
        return res.status(401).json({ error: 'Valid QR token is required' });
      }
    }

    res.status(200).json({ report });
  } catch (err) {
    next(err);
  }
}

/**
 * Retrieves only the analysis status of a report.
 * GET /api/reports/:id/status
 */
async function getReportStatus(req, res, next) {
  try {
    const report = await Report.findById(req.params.id).select('analysisStatus updatedAt patientId');
    if (!report) return res.status(404).json({ error: 'Report not found' });

    if (req.role === 'patient') {
      if (report.patientId.toString() !== req.user._id.toString()) {
        return res.status(403).json({ error: 'Access denied' });
      }
    } else if (req.role === 'doctor' || req.role === 'admin') {
      const { token } = req.query;
      if (!token) return res.status(400).json({ error: 'QR token is required' });
      
      const QrToken = require('../models/QrToken');
      const qrRecord = await QrToken.findOne({ token, patientId: report.patientId });
      if (!qrRecord || new Date() > qrRecord.expiresAt) {
        return res.status(401).json({ error: 'Valid QR token is required' });
      }
    }

    res.status(200).json({
      id: report._id,
      analysisStatus: report.analysisStatus,
      updatedAt: report.updatedAt
    });
  } catch (err) {
    next(err);
  }
}

/**
 * Deletes a report and its associated S3 file.
 * DELETE /api/reports/:id
 */
async function deleteReport(req, res, next) {
  try {
    const report = await Report.findById(req.params.id);
    if (!report) return res.status(404).json({ error: 'Report not found' });

    if (report.patientId.toString() !== req.user._id.toString()) {
      return res.status(403).json({ error: 'Access denied' });
    }

    await deleteFileFromS3(report.fileUrl);
    await report.deleteOne();

    res.status(200).json({ message: 'Report deleted successfully' });
  } catch (err) {
    next(err);
  }
}

/**
 * Serves a locally stored report file. (Development/Test only)
 * GET /api/reports/local/*
 */
function getLocalReportFile(req, res, next) {
  try {
    const s3Key = req.params[0]; // the * part of the route
    if (!s3Key) return res.status(400).json({ error: 'No file specified' });

    const uploadsDir = path.resolve(__dirname, '../../../uploads');
    const filePath = path.resolve(uploadsDir, s3Key);

    // Security: prevent directory traversal
    if (!filePath.startsWith(uploadsDir + path.sep) && filePath !== uploadsDir) {
      return res.status(403).json({ error: 'Access denied' });
    }

    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ error: 'Local file not found' });
    }

    res.sendFile(filePath);
  } catch (err) {
    next(err);
  }
}

module.exports = { uploadReport, getReport, getReportStatus, getReportUrl, deleteReport, getLocalReportFile };
