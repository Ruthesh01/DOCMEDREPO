'use strict';

const AuditLog = require('../models/AuditLog');

/**
 * Middleware factory that writes an audit log entry after the response is sent.
 * Fires asynchronously — never blocks the response.
 *
 * Usage: router.get('/route', authenticate, audit('VIEW_PATIENT_RECORD'), handler)
 *
 * @param {string} action - Human-readable action label (e.g. 'LOGIN', 'VIEW_REPORT')
 * @param {Function} [getTarget] - Optional fn(req) => string to derive the targetResource
 * @returns {Function} Express middleware
 */
function audit(action, getTarget) {
  return (req, res, next) => {
    res.on('finish', () => {
      // Only log successful or client-error responses (skip 5xx server crashes)
      if (res.statusCode >= 500) return;

      const userId = req.user?._id;
      if (!userId) return; // skip unauthenticated requests

      const targetResource = getTarget ? getTarget(req) : req.originalUrl;

      AuditLog.create({
        userId,
        role:           req.role || 'unknown',
        action,
        targetResource,
        ip:             req.ip || req.headers['x-forwarded-for'],
        userAgent:      req.headers['user-agent'],
      }).catch((err) => {
        // Never let audit failure crash the app — just log it
        console.error('[AuditLog] Failed to write audit entry:', err.message);
      });
    });

    next();
  };
}

module.exports = { audit };
