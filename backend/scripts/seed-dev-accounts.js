'use strict';

require('dotenv').config();
const mongoose = require('mongoose');
const Doctor = require('../src/models/Doctor');
const Patient = require('../src/models/Patient');
const { hashPassword } = require('../src/utils/hashPassword');

const uri = process.env.MONGODB_URI || 'mongodb://localhost:27017/docmedrepo';

const testDoctor = {
  name:          'Dr. Smith',
  email:         'doctor@test.com',
  passwordHash: null, // set below
  specialization: 'Cardiology',
  licenseNumber: 'MED123456',
};

const testPatient = {
  name:             'Test Patient',
  email:            'patient@test.com',
  passwordHash:     null,
  bloodGroup:       'A+',
  emergencyContact: { name: 'Jane Doe', phone: '9876543210', relation: 'Spouse' },
};

const PASSWORD = 'SecurePass123!';

async function run() {
  await mongoose.connect(uri);

  const hash = await hashPassword(PASSWORD);
  testDoctor.passwordHash = hash;
  testPatient.passwordHash = hash;

  let doctor = await Doctor.findOne({ email: testDoctor.email }).select('+passwordHash');
  if (doctor) {
    doctor.passwordHash = hash;
    doctor.name = testDoctor.name;
    doctor.specialization = testDoctor.specialization;
    doctor.licenseNumber = testDoctor.licenseNumber;
    await doctor.save({ validateBeforeSave: false });
  } else {
    await Doctor.create({ ...testDoctor, passwordHash: hash });
  }
  console.log('Doctor ready: doctor@test.com');

  let patient = await Patient.findOne({ email: testPatient.email }).select('+passwordHash');
  if (patient) {
    patient.passwordHash = hash;
    patient.name = testPatient.name;
    patient.bloodGroup = testPatient.bloodGroup;
    patient.emergencyContact = testPatient.emergencyContact;
    await patient.save({ validateBeforeSave: false });
  } else {
    await Patient.create({ ...testPatient, passwordHash: hash });
  }
  console.log('Patient ready: patient@test.com');

  console.log('\nPassword for both: SecurePass123!');
  console.log('You can now log in with these credentials.\n');

  await mongoose.connection.close();
  process.exit(0);
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
