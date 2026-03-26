'use strict';

const mongoose = require('mongoose');
const fieldEncryption = require('mongoose-field-encryption').fieldEncryption;

const emergencyContactSchema = new mongoose.Schema({
  name:     { type: String, required: [true, 'Emergency contact name is required'], trim: true },
  phone:    {
    type:     String,
    required: [true, 'Emergency contact phone is required'],
    match:    [/^[0-9]{10}$/, 'Phone must be a 10-digit number'],
  },
  relation: { type: String, required: [true, 'Emergency contact relation is required'], trim: true },
}, { _id: false });

const patientSchema = new mongoose.Schema(
  {
    name: {
      type:      String,
      required:  [true, 'Name is required'],
      minlength: [2, 'Name must be at least 2 characters'],
      maxlength: [100, 'Name cannot exceed 100 characters'],
      trim:      true,
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
      select:   false, // never returned in queries by default
    },
    passwordChangedAt: {
      type: Date,
    },
    bloodGroup: {
      type: String,
      enum: {
        values:  ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'],
        message: '{VALUE} is not a valid blood group',
      },
    },
    allergies:        { type: [String], default: [] },
    diseases:         { type: [String], default: [] }, // encrypted
    medications:      { type: [String], default: [] }, // encrypted
    emergencyContact: { type: emergencyContactSchema, required: [true, 'Emergency contact is required'] },
    fcmToken:         { type: String },
    role:             { type: String, default: 'patient', enum: ['patient'], immutable: true },
  },
  { timestamps: true }
);

// ── Field-level encryption for sensitive health data ────────────────────────
patientSchema.plugin(fieldEncryption, {
  fields:    ['diseases', 'medications', 'allergies', 'bloodGroup'],
  secret:    process.env.FIELD_ENCRYPTION_SECRET,
  saltGenerator: (secret) => secret.slice(0, 16), // deterministic for querying
});

// ── Invalidate tokens issued before password change ─────────────────────────
patientSchema.methods.changedPasswordAfter = function (jwtIssuedAt) {
  if (this.passwordChangedAt) {
    const changedTimestamp = Math.floor(this.passwordChangedAt.getTime() / 1000);
    return jwtIssuedAt < changedTimestamp;
  }
  return false;
};

module.exports = mongoose.model('Patient', patientSchema);
