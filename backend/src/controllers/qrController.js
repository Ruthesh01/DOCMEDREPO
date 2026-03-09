'use strict';

const { v4: uuidv4 } = require('uuid');
const QrToken = require('../models/QrToken');
const Patient = require('../models/Patient');

const QR_TTL_MS = 15 * 60 * 1000; // 15 minutes

/**
 * Generates a one-time QR token for the authenticated patient.
 * Returns the token and expiry time so the mobile app can render the QR code
 * and show a countdown timer.
 * POST /api/qr/generate
 */
async function generateQr(req, res, next) {
  try {
    const token     = uuidv4();
    const expiresAt = new Date(Date.now() + QR_TTL_MS);

    await QrToken.create({ patientId: req.user._id, token, expiresAt });

    res.status(201).json({
      token,
      expiresAt,
      expiresInSeconds: QR_TTL_MS / 1000,
    });
  } catch (err) {
    next(err);
  }
}

/**
 * Validates a scanned QR token and returns the associated patient's basic profile.
 * Called by the doctor's app after scanning.
 * POST /api/qr/scan
 */
async function scanQr(req, res, next) {
  try {
    const { token } = req.body;
    if (!token) return res.status(400).json({ error: 'Token is required' });

    const qrRecord = await QrToken.findOne({ token, used: false });
    if (!qrRecord) return res.status(404).json({ error: 'Invalid or already-used QR token' });

    if (new Date() > qrRecord.expiresAt) {
      return res.status(401).json({ error: 'QR token has expired' });
    }

    // Mark as used immediately to prevent replay
    qrRecord.used = true;
    await qrRecord.save();

    const patient = await Patient.findById(qrRecord.patientId).select(
      'name email bloodGroup allergies diseases emergencyContact'
    );
    if (!patient) return res.status(404).json({ error: 'Patient not found' });

    res.status(200).json({ patient });
  } catch (err) {
    next(err);
  }
}

module.exports = { generateQr, scanQr };
