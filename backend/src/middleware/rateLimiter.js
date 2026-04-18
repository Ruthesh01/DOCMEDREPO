'use strict';

const rateLimit = require('express-rate-limit');

const isTestEnv = process.env.NODE_ENV === 'test';

const noopLimiter = (_req, _res, next) => next();

/**
 * Helper: in test environment, disable rate limiting entirely so Jest specs
 * can perform multiple rapid requests without receiving 429 responses.
 */
function createLimiter(options) {
  if (isTestEnv) return noopLimiter;
  return rateLimit(options);
}

/**
 * Auth routes: max 10 requests per minute per IP.
 * Prevents brute force attacks on login/register endpoints.
 */
const authLimiter = createLimiter({
  windowMs: 60 * 1000, // 1 minute
  max:      10,
  message:  { error: 'Too many auth requests. Please wait a minute before trying again.' },
  standardHeaders: true,
  legacyHeaders:   false,
});

/**
 * OTP verification: max 5 attempts per 10 minutes per IP.
 * L-01 FIX: The /verify-otp endpoint was not behind any rate limiter,
 * allowing brute-force enumeration of the 6-digit OTP space.
 * A separate, tighter limiter is applied here (5 per 10 min vs 10 per min
 * for general auth routes). Per-doctorId attempt tracking is also done
 * inside verifyOtp() in authController.js.
 */
const otpLimiter = createLimiter({
  windowMs: 10 * 60 * 1000, // 10 minutes (matches OTP validity window)
  max:      5,
  message:  { error: 'Too many OTP attempts. Please wait before trying again.' },
  standardHeaders: true,
  legacyHeaders:   false,
});

/**
 * Report upload: max 20 uploads per hour per authenticated user.
 */
const uploadLimiter = createLimiter({
  windowMs: 60 * 60 * 1000, // 1 hour
  max:      20,
  keyGenerator: (req) => req.user?._id?.toString() || req.ip,
  message: { error: 'Upload limit reached. You can upload up to 20 reports per hour.' },
  standardHeaders: true,
  legacyHeaders:   false,
});

/**
 * QR generation: max 5 per 15 minutes per patient.
 */
const qrLimiter = createLimiter({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max:      5,
  keyGenerator: (req) => req.user?._id?.toString() || req.ip,
  message: { error: 'QR generation limit reached. Please wait 15 minutes.' },
  standardHeaders: true,
  legacyHeaders:   false,
});

module.exports = { authLimiter, otpLimiter, uploadLimiter, qrLimiter };
