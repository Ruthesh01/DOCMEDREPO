'use strict';

const { verifyAccessToken } = require('../utils/generateToken');
const Patient = require('../models/Patient');
const Doctor = require('../models/Doctor');

/**
 * Verifies the JWT access token from the Authorization header.
 * Attaches req.user and req.role on success.
 * Rejects tokens issued before a password change.
 */
async function authenticate(req, res, next) {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'No authentication token provided' });
    }

    const token = authHeader.split(' ')[1];
    let decoded;

    try {
      decoded = verifyAccessToken(token);
    } catch (err) {
      const message = err.name === 'TokenExpiredError' ? 'Token has expired' : 'Invalid token';
      return res.status(401).json({ error: message });
    }

    // Load user from the correct collection based on role
    let user;
    if (decoded.role === 'patient') {
      user = await Patient.findById(decoded.id).select('+passwordChangedAt');
    } else {
      user = await Doctor.findById(decoded.id).select('+passwordChangedAt');
    }

    if (!user) {
      return res.status(401).json({ error: 'User no longer exists' });
    }

    // Reject token if password was changed after it was issued
    if (user.changedPasswordAfter(decoded.iat)) {
      return res.status(401).json({ error: 'Password was recently changed. Please log in again.' });
    }

    req.user = user;
    req.role = decoded.role;
    next();
  } catch (err) {
    next(err);
  }
}

module.exports = { authenticate };
