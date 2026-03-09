'use strict';

const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');

/**
 * Signs a short-lived JWT access token (15 minutes).
 * @param {{ id: string, role: string }} payload
 * @returns {string} Signed JWT
 */
function generateAccessToken(payload) {
  return jwt.sign(
    { id: payload.id, role: payload.role },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '15m' }
  );
}

/**
 * Signs a long-lived JWT refresh token (7 days).
 * Includes a unique jti (JWT ID) so each issued token can be tracked/revoked.
 * @param {{ id: string, role: string }} payload
 * @returns {string} Signed JWT
 */
function generateRefreshToken(payload) {
  return jwt.sign(
    { id: payload.id, role: payload.role, jti: uuidv4() },
    process.env.JWT_REFRESH_SECRET,
    { expiresIn: '7d' }
  );
}

/**
 * Verifies and decodes an access token.
 * @param {string} token
 * @returns {object} Decoded payload
 * @throws {JsonWebTokenError | TokenExpiredError}
 */
function verifyAccessToken(token) {
  return jwt.verify(token, process.env.JWT_ACCESS_SECRET);
}

/**
 * Verifies and decodes a refresh token.
 * @param {string} token
 * @returns {object} Decoded payload
 * @throws {JsonWebTokenError | TokenExpiredError}
 */
function verifyRefreshToken(token) {
  return jwt.verify(token, process.env.JWT_REFRESH_SECRET);
}

/**
 * Generates a cryptographically random 6-digit OTP string.
 * @returns {string}
 */
function generateOtp() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

module.exports = {
  generateAccessToken,
  generateRefreshToken,
  verifyAccessToken,
  verifyRefreshToken,
  generateOtp,
};
