'use strict';

const mongoose = require('mongoose');

const qrTokenSchema = new mongoose.Schema({
  patientId: {
    type:     mongoose.Schema.Types.ObjectId,
    ref:      'Patient',
    required: [true, 'Patient ID is required'],
    index:    true,
  },
  token: {
    type:     String,
    required: [true, 'Token is required'],
    unique:   true,
  },
  expiresAt: {
    type:     Date,
    required: [true, 'Expiry date is required'],
    index:    { expireAfterSeconds: 0 }, // MongoDB TTL index — auto-deletes on expiry
  },
  used: {
    type:    Boolean,
    default: false,
  },
});

module.exports = mongoose.model('QrToken', qrTokenSchema);
