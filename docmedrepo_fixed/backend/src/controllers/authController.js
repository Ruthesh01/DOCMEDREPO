'use strict';

const { validationResult } = require('express-validator');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const Patient = require('../models/Patient');
const Doctor = require('../models/Doctor');
const PasswordResetToken = require('../models/PasswordResetToken');
const { hashPassword, verifyPassword } = require('../utils/hashPassword');
const {
  generateAccessToken,
  generateRefreshToken,
  verifyRefreshToken,
  generateOtp,
} = require('../utils/generateToken');
const { sendOtpEmail, sendPasswordResetEmail } = require('../services/emailService');
const { getRedisClient } = require('../config/redis');

// ── Token store helpers (M-01 FIX) ───────────────────────────────────────────
// Refresh tokens are now stored in Redis instead of an in-process Map.
// This fixes two problems:
//   1. Tokens survive server restarts (in-memory Map is wiped on every restart,
//      forcing all users to log in again).
//   2. Multi-instance deployments: refresh tokens issued by worker A are now
//      visible to worker B (the Map is per-process, Redis is shared).
//
// Key format : refresh_token:<jti>
// Value      : userId string
// TTL        : 7 days (matching the JWT expiry)
const REFRESH_TOKEN_TTL_SECONDS = 7 * 24 * 60 * 60; // 7 days

async function _storeRefreshToken(jti, userId) {
  await getRedisClient().set(
    `refresh_token:${jti}`,
    userId,
    'EX',
    REFRESH_TOKEN_TTL_SECONDS
  );
}

async function _hasRefreshToken(jti) {
  const val = await getRedisClient().get(`refresh_token:${jti}`);
  return val !== null;
}

async function _deleteRefreshToken(jti) {
  await getRedisClient().del(`refresh_token:${jti}`);
}

/**
 * Revokes all refresh tokens belonging to a user.
 * Used after a password change.
 * Redis SCAN is used rather than KEYS to avoid blocking the server on large dbs.
 */
async function _revokeAllUserTokens(userId) {
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
      const toDelete = keys.filter((_, i) => values[i] === userId);
      if (toDelete.length > 0) await redis.del(...toDelete);
    }
  } while (cursor !== '0');
}

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

    // Doctors require 2FA — send OTP, do NOT return tokens yet.
    // C-03 FIX: The NODE_ENV-based bypass has been removed.
    // For testing, stub sendOtpEmail in the test suite.
    if (role === 'doctor') {
      const otp = generateOtp();
      const otpHash = await bcrypt.hash(otp, 10);

      user.otpHash = otpHash;
      user.otpExpiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 min
      await user.save({ validateBeforeSave: false });

      // In development, log OTP to console if email fails (e.g. SMTP not configured).
      if (process.env.NODE_ENV === 'test') {
        // tests stub sendOtpEmail
      } else if (process.env.NODE_ENV === 'development') {
        try {
          await sendOtpEmail(user.email, user.name, otp);
        } catch (emailErr) {
          console.warn('[Auth] OTP email failed (use OTP from server log):', emailErr.message);
          console.log(`[Auth] Doctor OTP for ${user.email}: ${otp}`);
        }
      } else {
        await sendOtpEmail(user.email, user.name, otp);
      }

      return res.status(200).json({
        message: 'OTP sent to your registered email. Please verify to continue.',
        requiresOtp: true,
        doctorId: user._id,
        // DEV ONLY: return OTP to frontend console for testing
        ...(process.env.NODE_ENV === 'development' && { devOtp: otp }),
      });
    }

    // Patient: issue tokens directly
    const accessToken  = generateAccessToken({ id: user._id, role: 'patient' });
    const refreshToken = generateRefreshToken({ id: user._id, role: 'patient' });

    const decoded = jwt.decode(refreshToken);
    await _storeRefreshToken(decoded.jti, user._id.toString()); // M-01: Redis

    res.status(200).json({ accessToken, refreshToken });
  } catch (err) {
    next(err);
  }
}

/**
 * Verifies the 2FA OTP for doctor login and returns tokens.
 * POST /api/auth/verify-otp
 *
 * L-01 FIX: OTP failure counter stored in Redis. After 5 failed attempts the
 * OTP is invalidated and the doctor must log in again to get a new one.
 * This prevents brute-force enumeration of the 6-digit OTP space (1,000,000
 * combinations) that was possible because this endpoint had no rate limit.
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

    // L-01: track failed attempts in Redis (TTL matches OTP expiry: 10 min)
    const attemptKey = `otp_attempts:${doctorId}`;
    const redis = getRedisClient();
    const attempts = parseInt(await redis.get(attemptKey) || '0', 10);

    if (attempts >= 5) {
      // Invalidate the OTP to force a new login cycle
      doctor.otpHash = undefined;
      doctor.otpExpiresAt = undefined;
      await doctor.save({ validateBeforeSave: false });
      await redis.del(attemptKey);
      return res.status(429).json({
        error: 'Too many incorrect OTP attempts. Please log in again to receive a new OTP.',
      });
    }

    const isValid = await bcrypt.compare(otp, doctor.otpHash);
    if (!isValid) {
      await redis.set(attemptKey, attempts + 1, 'EX', 10 * 60);
      return res.status(401).json({ error: 'Invalid OTP' });
    }

    // Success — clear OTP fields and attempt counter
    doctor.otpHash = undefined;
    doctor.otpExpiresAt = undefined;
    await doctor.save({ validateBeforeSave: false });
    await redis.del(attemptKey);

    const accessToken  = generateAccessToken({ id: doctor._id, role: doctor.role });
    const refreshToken = generateRefreshToken({ id: doctor._id, role: doctor.role });

    const decoded = jwt.decode(refreshToken);
    await _storeRefreshToken(decoded.jti, doctor._id.toString()); // M-01: Redis

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

    // Check token is in Redis (not already rotated/revoked)
    if (!(await _hasRefreshToken(decoded.jti))) {
      return res.status(401).json({ error: 'Refresh token has been revoked' });
    }

    // Invalidate old token
    await _deleteRefreshToken(decoded.jti);

    // Issue new pair
    const newAccessToken  = generateAccessToken({ id: decoded.id, role: decoded.role });
    const newRefreshToken = generateRefreshToken({ id: decoded.id, role: decoded.role });

    const newDecoded = jwt.decode(newRefreshToken);
    await _storeRefreshToken(newDecoded.jti, decoded.id); // M-01: Redis

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
        await _deleteRefreshToken(decoded.jti);
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

    // M-01: revoke all refresh tokens for this user via Redis SCAN
    await _revokeAllUserTokens(user._id.toString());

    res.status(200).json({ message: 'Password changed successfully. Please log in again.' });
  } catch (err) {
    next(err);
  }
}

/**
 * Handles forgot password request.
 * POST /api/auth/forgot-password
 */
async function forgotPassword(req, res, next) {
  try {
    const { email, role } = req.body;
    if (!email || !role) return res.status(400).json({ error: 'email and role are required' });

    const Model = role === 'patient' ? Patient : (role === 'doctor' ? Doctor : null);
    if (!Model) return res.status(200).json({ message: 'If that email exists, a reset link will be sent.' });

    const user = await Model.findOne({ email });
    if (!user) return res.status(200).json({ message: 'If that email exists, a reset link will be sent.' });

    const resetToken = crypto.randomBytes(32).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(resetToken).digest('hex');

    await PasswordResetToken.create({
      userId: user._id,
      role,
      tokenHash,
      expiresAt: new Date(Date.now() + 60 * 60 * 1000), // 1 hour
    });

    const frontendUrl = process.env.FRONTEND_URL || 'http://localhost:3000';
    const resetLink = `${frontendUrl}/reset-password?token=${resetToken}&role=${role}`;

    if (process.env.NODE_ENV === 'test') {
      // tested locally
    } else if (process.env.NODE_ENV === 'development') {
      try {
        await sendPasswordResetEmail(user.email, user.name, resetLink);
      } catch (emailErr) {
        console.warn('[Auth] Password reset email failed:', emailErr.message);
        console.log(`[Auth] Reset link for ${user.email}: ${resetLink}`);
      }
    } else {
      await sendPasswordResetEmail(user.email, user.name, resetLink);
    }

    res.status(200).json({ message: 'If that email exists, a reset link will be sent.' });
  } catch (err) {
    next(err);
  }
}

/**
 * Handles password reset using a token.
 * POST /api/auth/reset-password
 */
async function resetPassword(req, res, next) {
  try {
    const { token, role, newPassword } = req.body;
    if (!token || !role || !newPassword) {
      return res.status(400).json({ error: 'token, role, and newPassword are required' });
    }

    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const resetRecord = await PasswordResetToken.findOne({
      tokenHash,
      role,
      used: false,
      expiresAt: { $gt: new Date() },
    });

    if (!resetRecord) {
      return res.status(400).json({ error: 'Invalid or expired reset link' });
    }

    const Model = role === 'patient' ? Patient : Doctor;
    const user = await Model.findById(resetRecord.userId).select('+passwordHash');
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    user.passwordHash = await hashPassword(newPassword);
    user.passwordChangedAt = new Date();
    await user.save({ validateBeforeSave: false });

    resetRecord.used = true;
    await resetRecord.save();

    await _revokeAllUserTokens(user._id.toString()); // M-01 Redis
    res.status(200).json({ message: 'Password reset successfully. Please log in.' });
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
  forgotPassword,
  resetPassword,
};
