'use strict';

const mongoose = require('mongoose');

const auditLogSchema = new mongoose.Schema({
  userId: {
    type:     mongoose.Schema.Types.ObjectId,
    required: [true, 'User ID is required'],
    index:    true,
  },
  role: {
    type:     String,
    required: [true, 'Role is required'],
  },
  action: {
    type:     String,
    required: [true, 'Action is required'],
  },
  targetResource: {
    type: String,
  },
  ip: {
    type: String,
  },
  userAgent: {
    type: String,
  },
  timestamp: {
    type:    Date,
    default: Date.now,
    index:   true,
  },
});

// Prevent modification of audit records
auditLogSchema.set('strict', true);

module.exports = mongoose.model('AuditLog', auditLogSchema);
