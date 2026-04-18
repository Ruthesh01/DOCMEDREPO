'use strict';

const { validationResult } = require('express-validator');
const Patient = require('../models/Patient');
const Report = require('../models/Report');
const Prescription = require('../models/Prescription');
const QrToken = require('../models/QrToken');
const PasswordResetToken = require('../models/PasswordResetToken');
const { verifyPassword } = require('../utils/hashPassword');
const { getRedisClient } = require('../config/redis');
const { deleteFileFromS3 } = require('../services/storageService');

/**
 * Returns the authenticated patient's profile.
 * GET /api/patients/me
 */
async function getMe(req, res, next) {
  try {
    const patient = await Patient.findById(req.user._id);
    if (!patient) return res.status(404).json({ error: 'Patient not found' });
    res.status(200).json({ patient });
  } catch (err) {
    next(err);
  }
}

/**
 * Updates the authenticated patient's profile.
 * Only allows safe fields — role and email cannot be changed here.
 * PUT /api/patients/me
 */
async function updateMe(req, res, next) {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    // Block attempts to change role or password via this endpoint
    const prohibited = ['role', 'passwordHash', 'email'];
    prohibited.forEach((field) => delete req.body[field]);

    const patient = await Patient.findById(req.user._id);
    if (!patient) return res.status(404).json({ error: 'Patient not found' });

    Object.assign(patient, req.body);
    await patient.save();

    res.status(200).json({
      patient: {
        id:             patient._id,
        name:           patient.name,
        email:          patient.email,
        bloodGroup:     req.body.bloodGroup || patient.bloodGroup,
        emergencyContact: patient.emergencyContact,
        role:           patient.role,
      },
    });
  } catch (err) {
    next(err);
  }
}

/**
 * Returns reports belonging to the authenticated patient.
 * GET /api/patients/me/reports
 *
 * H-05 FIX: Added pagination via page and limit query params.
 * Defaults: page=1, limit=20. Max limit capped at 100.
 * Previously returned an unbounded list which would OOM the process
 * for patients with many reports.
 */
async function getMyReports(req, res, next) {
  try {
    const page  = Math.max(1, parseInt(req.query.page,  10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 20));
    const skip  = (page - 1) * limit;

    const query = { patientId: req.user._id };

    if (req.query.status) {
      query.analysisStatus = req.query.status;
    }
    if (req.query.fileType) {
      query.fileType = req.query.fileType.toLowerCase();
    }
    if (req.query.search) {
      const escaped = req.query.search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      query.description = { $regex: escaped, $options: 'i' };
    }
    if (req.query.startDate || req.query.endDate) {
      query.createdAt = {};
      if (req.query.startDate) query.createdAt.$gte = new Date(req.query.startDate);
      if (req.query.endDate)   query.createdAt.$lte = new Date(req.query.endDate);
    }

    const [reports, total] = await Promise.all([
      Report.find(query)
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .select('-__v'),
      Report.countDocuments(query),
    ]);

    res.status(200).json({
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
      count: reports.length,
      reports,
    });
  } catch (err) {
    next(err);
  }
}

/**
 * Returns prescriptions for the authenticated patient.
 * GET /api/patients/me/prescriptions
 *
 * H-05 FIX: Added pagination.
 */
async function getMyPrescriptions(req, res, next) {
  try {
    const page  = Math.max(1, parseInt(req.query.page,  10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 20));
    const skip  = (page - 1) * limit;

    const [prescriptions, total] = await Promise.all([
      Prescription.find({ patientId: req.user._id, active: true })
        .populate('doctorId', 'name specialization')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit),
      Prescription.countDocuments({ patientId: req.user._id, active: true }),
    ]);

    res.status(200).json({
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
      count: prescriptions.length,
      prescriptions,
    });
  } catch (err) {
    next(err);
  }
}

/**
 * Returns a combined history of reports and prescriptions for the patient.
 * GET /api/patients/me/history
 *
 * H-05 FIX: Limit is now exposed as a query param instead of being a
 * hardcoded .limit(20) buried in the query.
 */
async function getMyHistory(req, res, next) {
  try {
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit, 10) || 20));

    const [reports, prescriptions] = await Promise.all([
      Report.find({ patientId: req.user._id })
        .sort({ createdAt: -1 })
        .limit(limit),
      Prescription.find({ patientId: req.user._id, active: true })
        .populate('doctorId', 'name specialization')
        .sort({ createdAt: -1 })
        .limit(limit),
    ]);

    res.status(200).json({ reports, prescriptions });
  } catch (err) {
    next(err);
  }
}

/**
 * Updates the patient's FCM token for push notifications.
 * POST /api/patients/me/fcm-token
 */
async function updateFcmToken(req, res, next) {
  try {
    const { fcmToken } = req.body;
    if (!fcmToken || typeof fcmToken !== 'string' || fcmToken.trim() === '') {
      return res.status(400).json({ error: 'Valid FCM token is required' });
    }
    await Patient.findByIdAndUpdate(req.user._id, { fcmToken });
    res.status(200).json({ message: 'FCM token updated successfully' });
  } catch (err) {
    next(err);
  }
}

/**
 * Deletes the patient account and all associated data.
 * Requires the current password for confirmation.
 * DELETE /api/patients/me
 */
async function deleteMe(req, res, next) {
  try {
    const { password } = req.body;
    if (!password) {
      return res.status(400).json({ error: 'Password is required to delete account' });
    }

    const patient = await Patient.findById(req.user._id).select('+passwordHash');
    if (!patient) return res.status(404).json({ error: 'Patient not found' });

    if (!(await verifyPassword(password, patient.passwordHash))) {
      return res.status(401).json({ error: 'Incorrect password' });
    }

    const userIdStr = patient._id.toString();

    // 1. Delete reports from S3
    const reports = await Report.find({ patientId: patient._id });
    for (const r of reports) {
      if (r.fileUrl) {
        try {
          await deleteFileFromS3(r.fileUrl);
        } catch (s3err) {
          console.error(`Failed to delete S3 object ${r.fileUrl}:`, s3err);
        }
      }
    }

    // 2. Delete database records
    await Report.deleteMany({ patientId: patient._id });
    await Prescription.deleteMany({ patientId: patient._id });
    await QrToken.deleteMany({ patientId: patient._id });
    await PasswordResetToken.deleteMany({ userId: patient._id, role: 'patient' });

    // 3. Revoke all refresh tokens in Redis
    const redis = getRedisClient();
    let cursor = '0';
    do {
      const [nextCursor, keys] = await redis.scan(
        cursor,
        'MATCH', 'refresh_token:*',
        'COUNT', 100
      );
      cursor = nextCursor;
      if (keys.length > 0) {
        const values = await redis.mget(...keys);
        const toDelete = keys.filter((_, i) => values[i] === userIdStr);
        if (toDelete.length > 0) await redis.del(...toDelete);
      }
    } while (cursor !== '0');

    // 4. Delete the user
    await Patient.findByIdAndDelete(patient._id);

    res.status(200).json({ message: 'Account and all associated data deleted successfully' });
  } catch (err) {
    next(err);
  }
}

module.exports = { getMe, updateMe, getMyReports, getMyPrescriptions, getMyHistory, updateFcmToken, deleteMe };
