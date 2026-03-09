'use strict';

const { validationResult } = require('express-validator');
const Patient = require('../models/Patient');
const Report = require('../models/Report');
const Prescription = require('../models/Prescription');

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

    const patient = await Patient.findByIdAndUpdate(
      req.user._id,
      req.body,
      { new: true, runValidators: true }
    );

    res.status(200).json({ patient });
  } catch (err) {
    next(err);
  }
}

/**
 * Returns all reports belonging to the authenticated patient.
 * GET /api/patients/me/reports
 */
async function getMyReports(req, res, next) {
  try {
    const reports = await Report.find({ patientId: req.user._id })
      .sort({ createdAt: -1 })
      .select('-__v');

    res.status(200).json({ count: reports.length, reports });
  } catch (err) {
    next(err);
  }
}

/**
 * Returns all prescriptions for the authenticated patient.
 * GET /api/patients/me/prescriptions
 */
async function getMyPrescriptions(req, res, next) {
  try {
    const prescriptions = await Prescription.find({ patientId: req.user._id })
      .populate('doctorId', 'name specialization')
      .sort({ createdAt: -1 });

    res.status(200).json({ count: prescriptions.length, prescriptions });
  } catch (err) {
    next(err);
  }
}

/**
 * Returns a combined history of reports and prescriptions for the patient.
 * GET /api/patients/me/history
 */
async function getMyHistory(req, res, next) {
  try {
    const [reports, prescriptions] = await Promise.all([
      Report.find({ patientId: req.user._id }).sort({ createdAt: -1 }).limit(20),
      Prescription.find({ patientId: req.user._id })
        .populate('doctorId', 'name specialization')
        .sort({ createdAt: -1 })
        .limit(20),
    ]);

    res.status(200).json({ reports, prescriptions });
  } catch (err) {
    next(err);
  }
}

module.exports = { getMe, updateMe, getMyReports, getMyPrescriptions, getMyHistory };
