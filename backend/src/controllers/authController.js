'use strict';

const { validationResult } = require('express-validator');
const Patient = require('../models/Patient');
const Doctor = require('../models/Doctor');
const { hashPassword, verifyPassword } = require('../utils/hashPassword');
const {
  generateAccessToken,
  generateRefreshToken,
  verifyRefreshToken,
  generateOtp,
} = require('../utils/generateToken');
const { sendOtpEmail } = require('../services/emailService');
const bcrypt = require('bcryptjs');

// In-memory refresh token store (use Redis in production for multi-instance)
// Key: jti, Value: userId
const refreshTokenStore = new Map();

/**
 * Registers a new patient account.
 * POST /api/auth/register/patient
 */
async function registerPatient(req, res, next) {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    const { name, email, password, bloodGroup, emergencyContact } = req.body;

    const existing = await Patient.findOne({ email });
    if (existing) return res.status(409).json({ error: 'Email already registered' });

    const passwordHash = await hashPassword(password);
    const patient = await Patient.create({ name, email, passwordHash, bloodGroup, emergencyContact });

    res.status(201).json({
      message: 'Patient registered successfully',
      patient: { id: patient._id, name: patient.name, email: patient.email },
    });
  } catch (err) {
    next(err);
  }
}

/**
 * Registers a new doctor account.
 * POST /api/auth/register/doctor
 */
async function registerDoctor(req, res, next) {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    const { name, email, password, specialization, licenseNumber } = req.body;

    const existing = await Doctor.findOne({ email });
    if (existing) return res.status(409).json({ error: 'Email already registered' });

    const passwordHash = await hashPassword(password);
    const doctor = await Doctor.create({ name, email, passwordHash, specialization, licenseNumber });

    res.status(201).json({
      message: 'Doctor registered successfully',
      doctor: { id: doctor._id, name: doctor.name, email: doctor.email },
    });
  } catch (err) {
    next(err);
  }
}

/**
 * Logs in a patient or doctor.
 * For doctors, issues a pending OTP step before returning full tokens.
 * POST /api/auth/login
 */
async function login(req, res, next) {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    const { email, password, role } = req.body;

    let user;
    if (role === 'patient') {
      user = await Patient.findOne({ email }).select('+passwordHash');
    } else {
      user = await Doctor.findOne({ email }).select('+passwordHash +otpHash +otpExpiresAt');
    }

    if (!user || !(await verifyPassword(password, user.passwordHash))) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }

    // Doctors require 2FA — send OTP, do NOT return tokens yet
    if (role === 'doctor') {
      // DEVELOPMENT BYPASS: Skip OTP in dev so we don't need SMTP testing
      if (process.env.NODE_ENV === 'development' || process.env.NODE_ENV === 'test') {      
        const accessToken  = generateAccessToken({ id: user._id, role: 'doctor' });
        const refreshToken = generateRefreshToken({ id: user._id, role: 'doctor' });

        const decoded = require('jsonwebtoken').decode(refreshToken);
        refreshTokenStore.set(decoded.jti, user._id.toString());

        return res.status(200).json({ accessToken, refreshToken });
      }

      const otp = generateOtp();
      const otpHash = await bcrypt.hash(otp, 10);

      user.otpHash = otpHash;
      user.otpExpiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 min
      await user.save({ validateBeforeSave: false });

      await sendOtpEmail(user.email, user.name, otp);

      return res.status(200).json({
        message: 'OTP sent to your registered email. Please verify to continue.',
        requiresOtp: true,
        doctorId: user._id,
      });
    }

    // Patient: issue tokens directly
    const accessToken  = generateAccessToken({ id: user._id, role: 'patient' });
    const refreshToken = generateRefreshToken({ id: user._id, role: 'patient' });

    // Decode to get jti and store it
    const decoded = require('jsonwebtoken').decode(refreshToken);
    refreshTokenStore.set(decoded.jti, user._id.toString());

    res.status(200).json({ accessToken, refreshToken });
  } catch (err) {
    next(err);
  }
}

/**
 * Verifies the 2FA OTP for doctor login and returns tokens.
 * POST /api/auth/verify-otp
 */
async function verifyOtp(req, res, next) {
  try {
    const { doctorId, otp } = req.body;
    if (!doctorId || !otp) return res.status(400).json({ error: 'doctorId and otp are required' });

    const doctor = await Doctor.findById(doctorId).select('+otpHash +otpExpiresAt');
    if (!doctor) return res.status(404).json({ error: 'Doctor not found' });

    if (!doctor.otpHash || !doctor.otpExpiresAt) {
      return res.status(400).json({ error: 'No OTP pending. Please log in again.' });
    }

    if (new Date() > doctor.otpExpiresAt) {
      return res.status(401).json({ error: 'OTP has expired. Please log in again.' });
    }

    const isValid = await bcrypt.compare(otp, doctor.otpHash);
    if (!isValid) return res.status(401).json({ error: 'Invalid OTP' });

    // Clear OTP fields
    doctor.otpHash = undefined;
    doctor.otpExpiresAt = undefined;
    await doctor.save({ validateBeforeSave: false });

    const accessToken  = generateAccessToken({ id: doctor._id, role: doctor.role });
    const refreshToken = generateRefreshToken({ id: doctor._id, role: doctor.role });

    const decoded = require('jsonwebtoken').decode(refreshToken);
    refreshTokenStore.set(decoded.jti, doctor._id.toString());

    res.status(200).json({ accessToken, refreshToken });
  } catch (err) {
    next(err);
  }
}

/**
 * Rotates the refresh token — old token is invalidated, new pair issued.
 * POST /api/auth/refresh-token
 */
async function refreshToken(req, res, next) {
  try {
    const { refreshToken: token } = req.body;
    if (!token) return res.status(400).json({ error: 'Refresh token is required' });

    let decoded;
    try {
      decoded = verifyRefreshToken(token);
    } catch {
      return res.status(401).json({ error: 'Invalid or expired refresh token' });
    }

    // Check token is in our store (not already rotated/revoked)
    if (!refreshTokenStore.has(decoded.jti)) {
      return res.status(401).json({ error: 'Refresh token has been revoked' });
    }

    // Invalidate old token
    refreshTokenStore.delete(decoded.jti);

    // Issue new pair
    const newAccessToken  = generateAccessToken({ id: decoded.id, role: decoded.role });
    const newRefreshToken = generateRefreshToken({ id: decoded.id, role: decoded.role });

    const newDecoded = require('jsonwebtoken').decode(newRefreshToken);
    refreshTokenStore.set(newDecoded.jti, decoded.id);

    res.status(200).json({ accessToken: newAccessToken, refreshToken: newRefreshToken });
  } catch (err) {
    next(err);
  }
}

/**
 * Logs out the user by revoking the refresh token.
 * POST /api/auth/logout
 */
async function logout(req, res, next) {
  try {
    const { refreshToken: token } = req.body;
    if (token) {
      try {
        const decoded = verifyRefreshToken(token);
        refreshTokenStore.delete(decoded.jti);
      } catch {
        // Token invalid — nothing to revoke
      }
    }
    res.status(200).json({ message: 'Logged out successfully' });
  } catch (err) {
    next(err);
  }
}

/**
 * Changes the authenticated user's password and invalidates all tokens.
 * POST /api/auth/change-password
 */
async function changePassword(req, res, next) {
  try {
    const { currentPassword, newPassword } = req.body;
    if (!currentPassword || !newPassword) {
      return res.status(400).json({ error: 'currentPassword and newPassword are required' });
    }

    const Model = req.role === 'patient' ? Patient : Doctor;
    const user = await Model.findById(req.user._id).select('+passwordHash');

    if (!(await verifyPassword(currentPassword, user.passwordHash))) {
      return res.status(401).json({ error: 'Current password is incorrect' });
    }

    user.passwordHash      = await hashPassword(newPassword);
    user.passwordChangedAt = new Date();
    await user.save({ validateBeforeSave: false });

    // Revoke all refresh tokens for this user
    for (const [jti, userId] of refreshTokenStore.entries()) {
      if (userId === user._id.toString()) refreshTokenStore.delete(jti);
    }

    res.status(200).json({ message: 'Password changed successfully. Please log in again.' });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  registerPatient,
  registerDoctor,
  login,
  verifyOtp,
  refreshToken,
  logout,
  changePassword,
};
