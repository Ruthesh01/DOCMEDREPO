'use strict';

/**
 * Creates a standardised operational error with an HTTP status code.
 * @param {string} message
 * @param {number} statusCode
 * @returns {Error}
 */
function createError(message, statusCode) {
  const err = new Error(message);
  err.statusCode = statusCode;
  err.isOperational = true;
  return err;
}

/**
 * Global Express error handler. Must be registered last in app.js.
 * Distinguishes operational errors (user-facing) from programming errors (500).
 */
function globalErrorHandler(err, req, res, _next) {
  // Mongoose validation error
  if (err.name === 'ValidationError') {
    const messages = Object.values(err.errors).map((e) => e.message);
    return res.status(400).json({ error: 'Validation failed', details: messages });
  }

  // Mongoose duplicate key error
  if (err.code === 11000) {
    const field = Object.keys(err.keyValue || {})[0] || 'field';
    return res.status(409).json({ error: `Duplicate value for ${field}. Please use a different value.` });
  }

  // JWT errors (should be caught in middleware but as a fallback)
  if (err.name === 'JsonWebTokenError') {
    return res.status(401).json({ error: 'Invalid token' });
  }
  if (err.name === 'TokenExpiredError') {
    return res.status(401).json({ error: 'Token has expired' });
  }

  // Operational errors (safe to expose to the client)
  if (err.isOperational) {
    return res.status(err.statusCode || 400).json({ error: err.message });
  }

  // Programming / unknown errors — log full details, send generic message
  console.error('[ERROR]', err);
  res.status(500).json({ error: 'Something went wrong. Please try again later.' });
}

module.exports = { globalErrorHandler, createError };
