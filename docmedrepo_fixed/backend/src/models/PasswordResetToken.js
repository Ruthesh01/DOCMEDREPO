'use strict';

const mongoose = require('mongoose');

const passwordResetTokenSchema = new mongoose.Schema(
  {
    userId: {
      type:     mongoose.Schema.Types.ObjectId,
      required: true,
      index:    true,
    },
    role: {
      type:     String,
      enum:     ['patient', 'doctor'],
      required: true,
    },
    tokenHash: {
      type:     String,
      required: true,
    },
    expiresAt: {
      type:     Date,
      required: true,
    },
    used: {
      type:    Boolean,
      default: false,
    },
  },
  { timestamps: true }
);

// TTL index to automatically remove expired tokens from the collection after they expire
passwordResetTokenSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

module.exports = mongoose.model('PasswordResetToken', passwordResetTokenSchema);
