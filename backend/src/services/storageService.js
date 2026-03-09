'use strict';

const { S3Client, PutObjectCommand, DeleteObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs');
const path = require('path');

let s3Client = null;

/**
 * Returns (or creates) an S3 client instance.
 * @returns {S3Client}
 */
function getS3() {
  if (s3Client) return s3Client;
  s3Client = new S3Client({
    region: process.env.AWS_REGION || 'ap-south-1',
    credentials: {
      accessKeyId: process.env.AWS_ACCESS_KEY_ID,
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
    },
  });
  return s3Client;
}

const BUCKET = process.env.AWS_S3_BUCKET;
const SIGNED_URL_TTL = 15 * 60; // 15 minutes in seconds

/**
 * Uploads a file buffer to the private S3 bucket.
 * @param {Buffer} buffer - File data
 * @param {string} fileType - 'pdf' | 'jpg' | 'png'
 * @param {string} userId - Owner's user ID (used for folder prefix)
 * @returns {Promise<string>} The S3 key (NOT a public URL)
 */
async function uploadFileToS3(buffer, fileType, userId) {
  const key = `reports/${userId}/${uuidv4()}.${fileType}`;

  if (process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'development') {
    const uploadDir = path.join(__dirname, '../../uploads', path.dirname(key));
    await fs.promises.mkdir(uploadDir, { recursive: true });
    await fs.promises.writeFile(path.join(__dirname, '../../uploads', key), buffer);
    return key;
  }

  const mimeMap = { pdf: 'application/pdf', jpg: 'image/jpeg', png: 'image/png' };

  const command = new PutObjectCommand({
    Bucket: BUCKET,
    Key: key,
    Body: buffer,
    ContentType: mimeMap[fileType],
  });

  await getS3().send(command);

  return key;
}

/**
 * Generates a temporary pre-signed GET URL for a private S3 object.
 * Expires in 15 minutes.
 * @param {string} s3Key - The S3 object key
 * @returns {Promise<string>} Pre-signed URL
 */
async function generateSignedUrl(s3Key) {
  if (process.env.NODE_ENV === 'test') return `https://mock-signed-url/${s3Key}`;
  if (process.env.NODE_ENV === 'development') return `http://localhost:5000/api/reports/local/${encodeURIComponent(s3Key)}`;

  const command = new GetObjectCommand({
    Bucket: BUCKET,
    Key: s3Key,
  });

  return getSignedUrl(getS3(), command, { expiresIn: SIGNED_URL_TTL });
}

/**
 * Deletes an object from the private S3 bucket.
 * @param {string} s3Key
 * @returns {Promise<void>}
 */
async function deleteFileFromS3(s3Key) {
  if (process.env.NODE_ENV === 'test') return;
  if (process.env.NODE_ENV === 'development') {
    try {
      await fs.promises.unlink(path.join(__dirname, '../../uploads', s3Key));
    } catch (err) {
      console.error('Local file delete error:', err);
    }
    return;
  }

  const command = new DeleteObjectCommand({ Bucket: BUCKET, Key: s3Key });
  await getS3().send(command);
}

module.exports = { uploadFileToS3, getSignedUrl: generateSignedUrl, deleteFileFromS3 };
