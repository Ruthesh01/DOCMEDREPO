'use strict';

process.env.NODE_ENV           = 'test';
process.env.MONGODB_URI        = 'mongodb://127.0.0.1:27017/docmedrepo_test';
process.env.REDIS_URL          = 'redis://127.0.0.1:6379';
process.env.JWT_ACCESS_SECRET  = 'test_access_secret_32chars_minimum!';
process.env.JWT_REFRESH_SECRET = 'test_refresh_secret_32chars_minimum';
process.env.FIELD_ENCRYPTION_SECRET = 'test_field_encryption_secret_32ch';

const request  = require('supertest');
const mongoose = require('mongoose');
const app      = require('../src/app');
const Patient  = require('../src/models/Patient');
const Doctor   = require('../src/models/Doctor');

const validPatient = {
  name:             'Test Patient',
  email:            'patient@test.com',
  password:         'SecurePass123!',
  bloodGroup:       'A+',
  emergencyContact: { name: 'Jane Doe', phone: '9876543210', relation: 'Spouse' },
};

const validDoctor = {
  name:           'Dr. Smith',
  email:          'doctor@test.com',
  password:       'SecurePass123!',
  specialization: 'Cardiology',
  licenseNumber:  'MED123456',
};

let patientToken;
let doctorToken;

beforeAll(async () => {
  await mongoose.connect(process.env.MONGODB_URI);
});

beforeEach(async () => {
  await Patient.deleteMany({});
  await Doctor.deleteMany({});

  // Register and login patient
  await request(app).post('/api/auth/register/patient').send(validPatient);
  const loginRes = await request(app).post('/api/auth/login').send({
    email: validPatient.email, password: validPatient.password, role: 'patient',
  });
  patientToken = loginRes.body.accessToken;

  // Register doctor (we'll manually set a token for doctor role tests)
  await request(app).post('/api/auth/register/doctor').send(validDoctor);
  // We can't complete the OTP flow in test — use a JWT directly
  const doctor = await Doctor.findOne({ email: validDoctor.email });
  const { generateAccessToken } = require('../src/utils/generateToken');
  doctorToken = generateAccessToken({ id: doctor._id, role: 'doctor' });
});

afterAll(async () => {
  await mongoose.connection.dropDatabase();
  await mongoose.connection.close();
});

// ── GET /api/patients/me ─────────────────────────────────────────────────────
describe('GET /api/patients/me', () => {
  it('200 — returns patient profile with valid token', async () => {
    const res = await request(app)
      .get('/api/patients/me')
      .set('Authorization', `Bearer ${patientToken}`);
    expect(res.status).toBe(200);
    expect(res.body.patient.email).toBe(validPatient.email);
    expect(res.body.patient).not.toHaveProperty('passwordHash');
  });

  it('401 — rejects request without token', async () => {
    const res = await request(app).get('/api/patients/me');
    expect(res.status).toBe(401);
  });

  it('403 — doctor token cannot access patient profile endpoint', async () => {
    const res = await request(app)
      .get('/api/patients/me')
      .set('Authorization', `Bearer ${doctorToken}`);
    expect(res.status).toBe(403);
  });
});

// ── PUT /api/patients/me ─────────────────────────────────────────────────────
describe('PUT /api/patients/me', () => {
  it('200 — updates allowed fields', async () => {
    const res = await request(app)
      .put('/api/patients/me')
      .set('Authorization', `Bearer ${patientToken}`)
      .send({ name: 'Updated Name', bloodGroup: 'B+' });
    expect(res.status).toBe(200);
    expect(res.body.patient.name).toBe('Updated Name');
    expect(res.body.patient.bloodGroup).toBe('B+');
  });

  it('400 — rejects invalid blood group', async () => {
    const res = await request(app)
      .put('/api/patients/me')
      .set('Authorization', `Bearer ${patientToken}`)
      .send({ bloodGroup: 'XYZ' });
    expect(res.status).toBe(400);
  });

  it('does not allow role change via this endpoint', async () => {
    const res = await request(app)
      .put('/api/patients/me')
      .set('Authorization', `Bearer ${patientToken}`)
      .send({ role: 'admin' });
    expect(res.status).toBe(200); // request succeeds but role is silently ignored
    const profile = await request(app)
      .get('/api/patients/me')
      .set('Authorization', `Bearer ${patientToken}`);
    expect(profile.body.patient.role).toBe('patient');
  });
});
