'use strict';

const crypto = require('crypto');

const ALGORITHM = 'aes-256-gcm';
const IV_LENGTH = 16;
const TAG_LENGTH = 16;

/**
 * Encrypts a string value using AES-256-GCM.
 * @param {string} text - Plain text to encrypt
 * @returns {string} Base64-encoded ciphertext (iv:tag:encrypted)
 */
function encrypt(text) {
  const secret = process.env.FIELD_ENCRYPTION_SECRET;
  if (!secret || secret.length < 32) throw new Error('FIELD_ENCRYPTION_SECRET must be at least 32 chars');

  const key = Buffer.from(secret.slice(0, 32), 'utf8');
  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv(ALGORITHM, key, iv);

  const encrypted = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();

  return `${iv.toString('base64')}:${tag.toString('base64')}:${encrypted.toString('base64')}`;
}

/**
 * Decrypts a string encrypted by the encrypt() function.
 * @param {string} encryptedText - The (iv:tag:encrypted) string
 * @returns {string} Original plain text
 */
function decrypt(encryptedText) {
  const secret = process.env.FIELD_ENCRYPTION_SECRET;
  const key = Buffer.from(secret.slice(0, 32), 'utf8');

  const [ivB64, tagB64, dataB64] = encryptedText.split(':');
  const iv = Buffer.from(ivB64, 'base64');
  const tag = Buffer.from(tagB64, 'base64');
  const encrypted = Buffer.from(dataB64, 'base64');

  const decipher = crypto.createDecipheriv(ALGORITHM, key, iv);
  decipher.setAuthTag(tag);

  return decipher.update(encrypted, undefined, 'utf8') + decipher.final('utf8');
}

module.exports = { encrypt, decrypt };
