'use strict';

const mongoose = require('mongoose');

const medicationItemSchema = new mongoose.Schema({
  name:      { type: String, required: [true, 'Medication name is required'], trim: true },
  dosage:    { type: String, required: [true, 'Dosage is required'], trim: true },
  frequency: { type: String, required: [true, 'Frequency is required'], trim: true },
  duration:  { type: String, required: [true, 'Duration is required'], trim: true },
}, { _id: false });

const prescriptionSchema = new mongoose.Schema(
  {
    doctorId: {
      type:     mongoose.Schema.Types.ObjectId,
      ref:      'Doctor',
      required: [true, 'Doctor ID is required'],
      index:    true,
    },
    patientId: {
      type:     mongoose.Schema.Types.ObjectId,
      ref:      'Patient',
      required: [true, 'Patient ID is required'],
      index:    true,
    },
    medications: {
      type:     [medicationItemSchema],
      required: [true, 'At least one medication is required'],
      validate: {
        validator: (arr) => arr.length >= 1,
        message:   'Prescription must include at least one medication',
      },
    },
    notes: {
      type:      String,
      maxlength: [1000, 'Notes cannot exceed 1000 characters'],
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Prescription', prescriptionSchema);
