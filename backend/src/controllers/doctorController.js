'use strict';

const { validationResult } = require('express-validator');
const Doctor = require('../models/Doctor');
const Patient = require('../models/Patient');
const Prescription = require('../models/Prescription');
const QrToken = require('../models/QrToken');

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
 * Fetches a patient's profile after verifying a valid (non-expired, unused) QR token.
 * The QR token is passed as a query param: ?token=<uuid>
 * GET /api/doctors/patients/:patientId
 */
async function getPatientByQr(req, res, next) {
  try {
    const { patientId } = req.params;
    const { token } = req.query;

    if (!token) return res.status(400).json({ error: 'QR token is required' });

    const qrRecord = await QrToken.findOne({ token, patientId, used: false });
    if (!qrRecord) return res.status(404).json({ error: 'QR token is invalid or already used' });

    if (new Date() > qrRecord.expiresAt) {
      return res.status(401).json({ error: 'QR token has expired' });
    }

    // Mark token as used (one-time access)
    qrRecord.used = true;
    await qrRecord.save();

    const patient = await Patient.findById(patientId);
    if (!patient) return res.status(404).json({ error: 'Patient not found' });

    res.status(200).json({ patient });
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
 * Returns all prescriptions written by the authenticated doctor.
 * GET /api/doctors/prescriptions
 */
async function getMyPrescriptions(req, res, next) {
  try {
    const prescriptions = await Prescription.find({ doctorId: req.user._id })
      .populate('patientId', 'name email bloodGroup')
      .sort({ createdAt: -1 });

    res.status(200).json({ count: prescriptions.length, prescriptions });
  } catch (err) {
    next(err);
  }
}

module.exports = { getMe, getPatientByQr, createPrescription, getMyPrescriptions };
