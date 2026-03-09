'use strict';

const mongoose = require('mongoose');

const abnormalValueSchema = new mongoose.Schema({
  test:  { type: String, required: true },
  value: { type: String, required: true },
  flag:  { type: String, enum: ['HIGH', 'LOW', 'NORMAL'], required: true },
}, { _id: false });

const aiSummarySchema = new mongoose.Schema({
  diagnoses:            { type: [String], default: [] },
  abnormalValues:       { type: [abnormalValueSchema], default: [] },
  medicationsMentioned: { type: [String], default: [] },
  summaryForPatient:    { type: String },
  summaryForDoctor:     { type: String },
  confidenceScore:      { type: Number, min: 0, max: 1 },
  source:               { type: String, enum: ['primary', 'fallback'], default: 'primary' },
}, { _id: false });

const reportSchema = new mongoose.Schema(
  {
    patientId: {
      type:     mongoose.Schema.Types.ObjectId,
      ref:      'Patient',
      required: [true, 'Patient ID is required'],
      index:    true,
    },
    uploadedBy: {
      type:     mongoose.Schema.Types.ObjectId,
      ref:      'Patient',
      required: [true, 'Uploader ID is required'],
    },
    fileUrl: {
      type:     String,
      required: [true, 'File URL (S3 key) is required'],
    },
    fileType: {
      type:     String,
      enum:     { values: ['pdf', 'jpg', 'png'], message: '{VALUE} is not an allowed file type' },
      required: [true, 'File type is required'],
    },
    description: {
      type:    String,
      maxlength: [500, 'Description cannot exceed 500 characters'],
    },
    analysisStatus: {
      type:    String,
      enum:    ['pending', 'processing', 'complete', 'failed'],
      default: 'pending',
    },
    aiSummary: {
      type:    aiSummarySchema,
      default: null,
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Report', reportSchema);
