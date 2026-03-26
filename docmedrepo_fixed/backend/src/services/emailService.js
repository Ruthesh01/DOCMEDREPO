'use strict';

const nodemailer = require('nodemailer');

let transporter = null;

/**
 * Returns (or creates) a nodemailer transporter.
 * Uses SMTP settings from environment variables.
 * @returns {nodemailer.Transporter}
 */
function getTransporter() {
  if (transporter) return transporter;

  transporter = nodemailer.createTransport({
    host:   process.env.SMTP_HOST,
    port:   Number(process.env.SMTP_PORT) || 587,
    secure: process.env.SMTP_SECURE === 'true',
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });

  return transporter;
}

/**
 * Sends a 2FA OTP email to a doctor.
 * @param {string} to - Doctor's email address
 * @param {string} name - Doctor's name
 * @param {string} otp - 6-digit OTP code
 * @returns {Promise<void>}
 */
async function sendOtpEmail(to, name, otp) {
  if (process.env.NODE_ENV === 'test') return; // skip in tests

  const t = getTransporter();

  await t.sendMail({
    from:    `"DocMedRepo Security" <${process.env.SMTP_USER}>`,
    to,
    subject: 'Your DocMedRepo Login OTP',
    html: `
      <div style="font-family: sans-serif; max-width: 480px; margin: auto;">
        <h2>Hello, Dr. ${name}</h2>
        <p>Your one-time password (OTP) for login is:</p>
        <div style="font-size: 36px; font-weight: bold; letter-spacing: 8px; 
                    color: #1a73e8; padding: 16px 0;">${otp}</div>
        <p>This OTP is valid for <strong>10 minutes</strong>.</p>
        <p>If you did not request this, please change your password immediately.</p>
        <hr/>
        <p style="font-size: 12px; color: #999;">DocMedRepo — Secure Medical Records</p>
      </div>
    `,
  });

  console.log(`[Email] OTP sent to ${to}`);
}

/**
 * Sends a password reset email.
 * @param {string} to - User's email address
 * @param {string} name - User's name
 * @param {string} resetLink - Password reset link
 * @returns {Promise<void>}
 */
async function sendPasswordResetEmail(to, name, resetLink) {
  if (process.env.NODE_ENV === 'test') return;

  const t = getTransporter();

  await t.sendMail({
    from:    `"DocMedRepo Security" <${process.env.SMTP_USER}>`,
    to,
    subject: 'Reset Your DocMedRepo Password',
    html: `
      <div style="font-family: sans-serif; max-width: 480px; margin: auto;">
        <h2>Hello, ${name}</h2>
        <p>You recently requested to reset your password for your DocMedRepo account. Click the button below to reset it.</p>
        <p>
          <a href="${resetLink}" style="display: inline-block; padding: 12px 24px; background-color: #1a73e8; color: white; text-decoration: none; border-radius: 4px; font-weight: bold;">Reset Password</a>
        </p>
        <p>If the button doesn't work, you can copy and paste the following link into your browser:</p>
        <p><a href="${resetLink}">${resetLink}</a></p>
        <p>This password reset link is only valid for <strong>1 hour</strong>.</p>
        <p>If you did not request a password reset, please ignore this email.</p>
        <hr/>
        <p style="font-size: 12px; color: #999;">DocMedRepo — Secure Medical Records</p>
      </div>
    `,
  });

  console.log(`[Email] Password reset sent to ${to}`);
}

module.exports = { sendOtpEmail, sendPasswordResetEmail };
