'use strict';

const { validationResult } = require('express-validator');
const Doctor = require('../models/Doctor');
const Patient = require('../models/Patient');
const Prescription = require('../models/Prescription');
const QrToken = require('../models/QrToken');
const Report = require('../models/Report');

/**
 * Returns the authenticated doctor's profile.
 * GET /api/doctors/me
 */
async function getMe(req, res, next) {
  try {
    const doctor = await Doctor.findById(req.user._id);
    if (!doctor) return res.status(404).json({ error: 'Doctor not found' });
    res.status(200).json({ doctor });
  } catch (err) {
    next(err);
  }
}

/**
 * Updates the authenticated doctor's profile.
 * Only allows safe fields — role, password, email, licenseNumber cannot be changed here.
 * PUT /api/doctors/me
 */
async function updateMe(req, res, next) {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    // Allowed fields: name, specialization, fcmToken
    const prohibited = ['role', 'passwordHash', 'email', 'licenseNumber', 'otpHash', 'otpExpiresAt'];
    prohibited.forEach((field) => delete req.body[field]);

    const doctor = await Doctor.findByIdAndUpdate(
      req.user._id,
      { $set: req.body },
      { new: true, runValidators: true }
    ).select('-passwordHash -otpHash -otpExpiresAt -__v');

    if (!doctor) return res.status(404).json({ error: 'Doctor not found' });

    res.status(200).json({ doctor });
  } catch (err) {
    next(err);
  }
}

/**
 * Fetches a patient's profile after verifying a valid (non-expired, unused) QR token.
 * The QR token is passed as a query param: ?token=<uuid>
 * GET /api/doctors/patients/:patientId
 *
 * H-03 FIX: Token consumption is now atomic using findOneAndUpdate.
 *   Previously used findOne + save in two steps, creating a race window where
 *   concurrent requests could both read the token as unused. The atomic update
 *   ensures only one request can ever consume a given token.
 *
 * H-04 FIX: Patient data returned is scoped to clinical fields only.
 *   Full profile (all fields) is no longer returned after a QR scan.
 *   The audit trail records which doctor accessed which patient and when.
 */
async function getPatientByQr(req, res, next) {
  try {
    const { patientId } = req.params;
    const { token } = req.query;

    if (!token) return res.status(400).json({ error: 'QR token is required' });

    // H-03: atomic check-and-consume scoped to this specific patientId
    const qrRecord = await QrToken.findOneAndUpdate(
      { token, patientId, used: false },
      { $set: { used: true } },
      { new: false }  // return pre-update doc to check expiry
    );

    if (!qrRecord) {
      return res.status(404).json({ error: 'QR token is invalid or already used' });
    }

    if (new Date() > qrRecord.expiresAt) {
      return res.status(401).json({ error: 'QR token has expired' });
    }

    // H-04: return only the clinical fields a doctor needs during a consult.
    // Full PII fields (passwordHash, fcmToken, role, __v) are never included.
    // The audit log (attached in doctorRoutes.js) records this access.
    const patient = await Patient.findById(patientId).select(
      'name bloodGroup allergies diseases medications emergencyContact'
    );
    if (!patient) return res.status(404).json({ error: 'Patient not found' });

    res.status(200).json({ patient });
  } catch (err) {
    next(err);
  }
}

/**
 * Fetches reports of a patient.
 * Requires the same QR token as used for viewing the profile.
 * GET /api/doctors/patients/:patientId/reports
 */
async function getPatientReports(req, res, next) {
  try {
    const { patientId } = req.params;
    const { token } = req.query;

    if (!token) return res.status(400).json({ error: 'QR token is required' });

    const qrRecord = await QrToken.findOne({ token, patientId });
    if (!qrRecord) return res.status(404).json({ error: 'QR token is invalid' });
    if (new Date() > qrRecord.expiresAt) return res.status(401).json({ error: 'QR token has expired' });

    const reports = await Report.find({ patientId }).sort({ createdAt: -1 });

    res.status(200).json({ reports });
  } catch (err) {
    next(err);
  }
}

/**
 * Creates a new prescription for a patient.
 * POST /api/doctors/prescriptions
 */
async function createPrescription(req, res, next) {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    const { patientId, medications, notes } = req.body;

    const patient = await Patient.findById(patientId);
    if (!patient) return res.status(404).json({ error: 'Patient not found' });

    const prescription = await Prescription.create({
      doctorId: req.user._id,
      patientId,
      medications,
      notes,
    });

    res.status(201).json({ prescription });
  } catch (err) {
    next(err);
  }
}

/**
 * Cancels a prescription (soft delete).
 * DELETE /api/doctors/prescriptions/:id
 */
async function cancelPrescription(req, res, next) {
  try {
    const prescription = await Prescription.findOneAndUpdate(
      { _id: req.params.id, doctorId: req.user._id, active: true },
      { $set: { active: false } },
      { new: true }
    );
    if (!prescription) {
      return res.status(404).json({ error: 'Prescription not found or already cancelled' });
    }
    res.status(200).json({ message: 'Prescription cancelled successfully' });
  } catch (err) {
    next(err);
  }
}

/**
 * Returns all prescriptions written by the authenticated doctor.
 * GET /api/doctors/prescriptions
 *
 * H-05 FIX: Added pagination via page and limit query params.
 * Defaults: page=1, limit=20. Max limit capped at 100.
 */
async function getMyPrescriptions(req, res, next) {
  try {
    const page  = Math.max(1, parseInt(req.query.page,  10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 20));
    const skip  = (page - 1) * limit;

    const [prescriptions, total] = await Promise.all([
      Prescription.find({ doctorId: req.user._id, active: true })
        .populate('patientId', 'name email bloodGroup')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit),
      Prescription.countDocuments({ doctorId: req.user._id, active: true }),
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
 * Updates the doctor's FCM token for push notifications.
 * POST /api/doctors/me/fcm-token
 */
async function updateFcmToken(req, res, next) {
  try {
    const { fcmToken } = req.body;
    if (!fcmToken || typeof fcmToken !== 'string' || fcmToken.trim() === '') {
      return res.status(400).json({ error: 'Valid FCM token is required' });
    }
    await Doctor.findByIdAndUpdate(req.user._id, { fcmToken });
    res.status(200).json({ message: 'FCM token updated successfully' });
  } catch (err) {
    next(err);
  }
}

module.exports = { getMe, updateMe, getPatientByQr, getPatientReports, createPrescription, cancelPrescription, getMyPrescriptions, updateFcmToken };
