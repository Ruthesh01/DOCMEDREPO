'use strict';

require('dotenv').config();
const mongoose = require('mongoose');
const Doctor = require('../src/models/Doctor');

const uri = process.env.MONGODB_URI || 'mongodb://localhost:27017/docmedrepo';

async function run() {
  await mongoose.connect(uri);
  const doctors = await Doctor.find({}).select('_id name email specialization').lean();
  console.log('Doctors in database:\n');
  if (doctors.length === 0) {
    console.log('  (none)');
  } else {
    doctors.forEach((d) => {
      console.log(`  id: ${d._id}`);
      console.log(`  name: ${d.name}`);
      console.log(`  email: ${d.email}`);
      console.log(`  specialization: ${d.specialization}`);
      console.log('');
    });
  }
  await mongoose.connection.close();
  process.exit(0);
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
