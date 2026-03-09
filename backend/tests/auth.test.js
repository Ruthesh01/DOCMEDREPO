'use strict';

process.env.NODE_ENV          = 'test';
process.env.MONGODB_URI       = 'mongodb://127.0.0.1:27017/docmedrepo_test';
process.env.REDIS_URL         = 'redis://127.0.0.1:6379';
process.env.JWT_ACCESS_SECRET = 'test_access_secret_32chars_minimum!';
process.env.JWT_REFRESH_SECRET= 'test_refresh_secret_32chars_minimum';
process.env.FIELD_ENCRYPTION_SECRET = 'test_field_encryption_secret_32ch';

const request = require('supertest');
const mongoose = require('mongoose');
const app = require('../src/app');
const Patient = require('../src/models/Patient');
const Doctor  = require('../src/models/Doctor');

const validPatient = {
  name:             'Test Patient',
  email:            'patient@test.com',
  password:         'SecurePass123!',
  bloodGroup:       'A+',
  emergencyContact: { name: 'Jane Doe', phone: '9876543210', relation: 'Spouse' },
};

const validDoctor = {
  name:          'Dr. Smith',
  email:         'doctor@test.com',
  password:      'SecurePass123!',
  specialization:'Cardiology',
  licenseNumber: 'MED123456',
};

beforeAll(async () => {
  await mongoose.connect(process.env.MONGODB_URI);
});

afterEach(async () => {
  await Patient.deleteMany({});
  await Doctor.deleteMany({});
});

afterAll(async () => {
  await mongoose.connection.dropDatabase();
  await mongoose.connection.close();
});

// ── Patient Registration ─────────────────────────────────────────────────────
describe('POST /api/auth/register/patient', () => {
  it('201 — registers a patient with valid data', async () => {
    const res = await request(app).post('/api/auth/register/patient').send(validPatient);
    expect(res.status).toBe(201);
    expect(res.body.patient).toHaveProperty('id');
    expect(res.body.patient.email).toBe(validPatient.email);
  });

  it('409 — rejects duplicate email', async () => {
    await request(app).post('/api/auth/register/patient').send(validPatient);
    const res = await request(app).post('/api/auth/register/patient').send(validPatient);
    expect(res.status).toBe(409);
  });

  it('400 — rejects missing emergency contact', async () => {
    const { emergencyContact, ...without } = validPatient;
    const res = await request(app).post('/api/auth/register/patient').send(without);
    expect(res.status).toBe(400);
  });

  it('400 — rejects invalid emergency contact phone', async () => {
    const res = await request(app)
      .post('/api/auth/register/patient')
      .send({ ...validPatient, emergencyContact: { ...validPatient.emergencyContact, phone: '123' } });
    expect(res.status).toBe(400);
  });
});

// ── Doctor Registration ──────────────────────────────────────────────────────
describe('POST /api/auth/register/doctor', () => {
  it('201 — registers a doctor with valid data', async () => {
    const res = await request(app).post('/api/auth/register/doctor').send(validDoctor);
    expect(res.status).toBe(201);
    expect(res.body.doctor).toHaveProperty('id');
  });

  it('409 — rejects duplicate email', async () => {
    await request(app).post('/api/auth/register/doctor').send(validDoctor);
    const res = await request(app).post('/api/auth/register/doctor').send(validDoctor);
    expect(res.status).toBe(409);
  });
});

// ── Patient Login ────────────────────────────────────────────────────────────
describe('POST /api/auth/login (patient)', () => {
  beforeEach(async () => {
    await request(app).post('/api/auth/register/patient').send(validPatient);
  });

  it('200 — returns access and refresh tokens on valid credentials', async () => {
    const res = await request(app).post('/api/auth/login').send({
      email: validPatient.email, password: validPatient.password, role: 'patient',
    });
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('accessToken');
    expect(res.body).toHaveProperty('refreshToken');
  });

  it('401 — rejects wrong password', async () => {
    const res = await request(app).post('/api/auth/login').send({
      email: validPatient.email, password: 'wrongpassword', role: 'patient',
    });
    expect(res.status).toBe(401);
  });

  it('401 — rejects non-existent email', async () => {
    const res = await request(app).post('/api/auth/login').send({
      email: 'nobody@test.com', password: validPatient.password, role: 'patient',
    });
    expect(res.status).toBe(401);
  });
});

// ── Doctor Login (2FA) ───────────────────────────────────────────────────────
describe('POST /api/auth/login (doctor 2FA)', () => {
  beforeEach(async () => {
    await request(app).post('/api/auth/register/doctor').send(validDoctor);
  });

  it('200 — step 1 returns requiresOtp:true instead of tokens', async () => {
    const res = await request(app).post('/api/auth/login').send({
      email: validDoctor.email, password: validDoctor.password, role: 'doctor',
    });
    expect(res.status).toBe(200);
    expect(res.body.requiresOtp).toBe(true);
    expect(res.body).not.toHaveProperty('accessToken');
  });

  it('401 — verify-otp rejects wrong OTP', async () => {
    const loginRes = await request(app).post('/api/auth/login').send({
      email: validDoctor.email, password: validDoctor.password, role: 'doctor',
    });
    const res = await request(app).post('/api/auth/verify-otp').send({
      doctorId: loginRes.body.doctorId,
      otp:      '000000',
    });
    expect(res.status).toBe(401);
  });
});

// ── Refresh Token Rotation ───────────────────────────────────────────────────
describe('POST /api/auth/refresh-token', () => {
  it('rejects old refresh token after rotation', async () => {
    await request(app).post('/api/auth/register/patient').send(validPatient);
    const loginRes = await request(app).post('/api/auth/login').send({
      email: validPatient.email, password: validPatient.password, role: 'patient',
    });
    const { refreshToken } = loginRes.body;

    // First rotation — should succeed
    const firstRotation = await request(app)
      .post('/api/auth/refresh-token')
      .send({ refreshToken });
    expect(firstRotation.status).toBe(200);

    // Old token — must be rejected now
    const secondAttempt = await request(app)
      .post('/api/auth/refresh-token')
      .send({ refreshToken });
    expect(secondAttempt.status).toBe(401);
  });
});
