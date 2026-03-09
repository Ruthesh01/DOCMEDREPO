'use strict';

const bcrypt = require('bcryptjs');

const SALT_ROUNDS = 12;

/**
 * Hashes a plain-text password using bcrypt.
 * @param {string} plainPassword - The raw password string
 * @returns {Promise<string>} The bcrypt hash
 */
async function hashPassword(plainPassword) {
  if (!plainPassword || typeof plainPassword !== 'string') {
    throw new Error('Password must be a non-empty string');
  }
  return bcrypt.hash(plainPassword, SALT_ROUNDS);
}

/**
 * Compares a plain-text password against a bcrypt hash.
 * @param {string} plainPassword - The raw password to verify
 * @param {string} hash - The stored bcrypt hash
 * @returns {Promise<boolean>} True if they match
 */
async function verifyPassword(plainPassword, hash) {
  return bcrypt.compare(plainPassword, hash);
}

module.exports = { hashPassword, verifyPassword };
