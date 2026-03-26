'use strict';

const mongoose = require('mongoose');

const doctorSchema = new mongoose.Schema(
  {
    name: {
      type:     String,
      required: [true, 'Name is required'],
      trim:     true,
    },
    email: {
      type:      String,
      required:  [true, 'Email is required'],
      unique:    true,
      lowercase: true,
      trim:      true,
      match:     [/^\S+@\S+\.\S+$/, 'Please provide a valid email address'],
    },
    passwordHash: {
      type:     String,
      required: [true, 'Password is required'],
      select:   false,
    },
    passwordChangedAt: {
      type: Date,
    },
    specialization: {
      type:     String,
      required: [true, 'Specialization is required'],
      trim:     true,
    },
    licenseNumber: {
      type:     String,
      required: [true, 'License number is required'],
      unique:   true,
      trim:     true,
    },
    // ── 2FA fields ────────────────────────────────────────────────────────
    otpHash: {
      type:   String,
      select: false,
    },
    otpExpiresAt: {
      type: Date,
      select: false,
    },
    fcmToken: {
      type: String,
    },
    role: {
      type:    String,
      default: 'doctor',
      enum:    {
        values:  ['doctor', 'admin', 'lab_technician'],
        message: '{VALUE} is not a valid role',
      },
    },
  },
  { timestamps: true }
);

/**
 * Returns true if the JWT was issued before the password was last changed.
 * Used in authMiddleware to invalidate stale tokens.
 * @param {number} jwtIssuedAt - Unix timestamp (seconds)
 * @returns {boolean}
 */
doctorSchema.methods.changedPasswordAfter = function (jwtIssuedAt) {
  if (this.passwordChangedAt) {
    const changedTimestamp = Math.floor(this.passwordChangedAt.getTime() / 1000);
    return jwtIssuedAt < changedTimestamp;
  }
  return false;
};

module.exports = mongoose.model('Doctor', doctorSchema);
