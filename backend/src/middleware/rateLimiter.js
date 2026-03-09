'use strict';

const rateLimit = require('express-rate-limit');

/**
 * Auth routes: max 10 requests per minute per IP.
 * Prevents brute force attacks on login/register endpoints.
 */
const authLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max:      10,
  message:  { error: 'Too many auth requests. Please wait a minute before trying again.' },
  standardHeaders: true,
  legacyHeaders:   false,
});

/**
 * Report upload: max 20 uploads per hour per authenticated user.
 */
const uploadLimiter = rateLimit({
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
const qrLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max:      5,
  keyGenerator: (req) => req.user?._id?.toString() || req.ip,
  message: { error: 'QR generation limit reached. Please wait 15 minutes.' },
  standardHeaders: true,
  legacyHeaders:   false,
});

module.exports = { authLimiter, uploadLimiter, qrLimiter };
