'use strict';

process.env.NODE_ENV           = 'test';
process.env.MONGODB_URI        = 'mongodb://127.0.0.1:27017/docmedrepo_test';
process.env.REDIS_URL          = 'redis://127.0.0.1:6379';
process.env.JWT_ACCESS_SECRET  = 'test_access_secret_32chars_minimum!';
process.env.JWT_REFRESH_SECRET = 'test_refresh_secret_32chars_minimum';
process.env.FIELD_ENCRYPTION_SECRET = 'test_field_encryption_secret_32ch';
process.env.AWS_S3_BUCKET      = 'mock-bucket';

const request  = require('supertest');
const mongoose = require('mongoose');
const path     = require('path');
const fs       = require('fs');
const app      = require('../src/app');
const Patient  = require('../src/models/Patient');
const Report   = require('../src/models/Report');
const { connectRedis, disconnectRedis } = require('../src/config/redis');

// ── Minimal valid PDF buffer (magic bytes %PDF) ──────────────────────────────
const validPdfBuffer = Buffer.concat([
  Buffer.from([0x25, 0x50, 0x44, 0x46]), // %PDF magic bytes
  Buffer.from('-1.4 fake pdf content for testing'),
]);

// ── Invalid file buffer (EXE magic bytes MZ) ────────────────────────────────
const invalidExeBuffer = Buffer.concat([
  Buffer.from([0x4D, 0x5A]), // MZ header
  Buffer.from('fake exe content'),
]);

const validPatient = {
  name:             'Test Patient',
  email:            'patient@test.com',
  password:         'SecurePass123!',
  bloodGroup:       'A+',
  emergencyContact: { name: 'Jane Doe', phone: '9876543210', relation: 'Spouse' },
};

const secondPatient = {
  name:             'Other Patient',
  email:            'other@test.com',
  password:         'SecurePass123!',
  bloodGroup:       'O+',
  emergencyContact: { name: 'Bob Doe', phone: '9876543211', relation: 'Parent' },
};

let patientToken;
let otherPatientToken;

beforeAll(async () => {
  await mongoose.connect(process.env.MONGODB_URI);
  await connectRedis();
});

beforeEach(async () => {
  await Patient.deleteMany({});
  await Report.deleteMany({});

  await request(app).post('/api/auth/register/patient').send(validPatient);
  const loginRes = await request(app).post('/api/auth/login').send({
    email: validPatient.email, password: validPatient.password, role: 'patient',
  });
  patientToken = loginRes.body.accessToken;

  await request(app).post('/api/auth/register/patient').send(secondPatient);
  const loginRes2 = await request(app).post('/api/auth/login').send({
    email: secondPatient.email, password: secondPatient.password, role: 'patient',
  });
  otherPatientToken = loginRes2.body.accessToken;
});

afterAll(async () => {
  await mongoose.connection.dropDatabase();
  await mongoose.connection.close();
  await disconnectRedis();
});

// ── POST /api/reports/upload ─────────────────────────────────────────────────
describe('POST /api/reports/upload', () => {
  it('201 — uploads a valid PDF and creates report with status pending', async () => {
    const tmpPath = path.join('/tmp', 'test.pdf');
    fs.writeFileSync(tmpPath, validPdfBuffer);

    const res = await request(app)
      .post('/api/reports/upload')
      .set('Authorization', `Bearer ${patientToken}`)
      .attach('report', tmpPath)
      .field('description', 'Blood test results');

    expect(res.status).toBe(201);
    expect(res.body.report.analysisStatus).toBe('pending');
    expect(res.body.report.fileType).toBe('pdf');
  });

  it('400 — rejects file with invalid magic bytes (exe)', async () => {
    const tmpPath = path.join('/tmp', 'malicious.pdf'); // disguised as PDF
    fs.writeFileSync(tmpPath, invalidExeBuffer);

    const res = await request(app)
      .post('/api/reports/upload')
      .set('Authorization', `Bearer ${patientToken}`)
      .attach('report', tmpPath);

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Invalid file type/i);
  });

  it('400 — rejects file exceeding 10MB', async () => {
    const bigBuffer = Buffer.alloc(11 * 1024 * 1024, 0); // 11MB
    const tmpPath = path.join('/tmp', 'toobig.pdf');
    // Prepend valid PDF magic bytes
    const buf = Buffer.concat([Buffer.from([0x25, 0x50, 0x44, 0x46]), bigBuffer]);
    fs.writeFileSync(tmpPath, buf);

    const res = await request(app)
      .post('/api/reports/upload')
      .set('Authorization', `Bearer ${patientToken}`)
      .attach('report', tmpPath);

    expect(res.status).toBe(400);
  });

  it('401 — rejects unauthenticated upload', async () => {
    const res = await request(app)
      .post('/api/reports/upload');

    expect(res.status).toBe(401);
  });
});

// ── GET /api/reports/:id/url ─────────────────────────────────────────────────
describe('GET /api/reports/:id/url', () => {
  it('200 — returns pre-signed URL for own report', async () => {
    const tmpPath = path.join('/tmp', 'test.pdf');
    fs.writeFileSync(tmpPath, validPdfBuffer);

    const uploadRes = await request(app)
      .post('/api/reports/upload')
      .set('Authorization', `Bearer ${patientToken}`)
      .attach('report', tmpPath);

    const reportId = uploadRes.body.report.id;

    const res = await request(app)
      .get(`/api/reports/${reportId}/url`)
      .set('Authorization', `Bearer ${patientToken}`);

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('url');
  });

  it('403 — another patient cannot access the report', async () => {
    const tmpPath = path.join('/tmp', 'test.pdf');
    fs.writeFileSync(tmpPath, validPdfBuffer);

    const uploadRes = await request(app)
      .post('/api/reports/upload')
      .set('Authorization', `Bearer ${patientToken}`)
      .attach('report', tmpPath);

    const reportId = uploadRes.body.report.id;

    const res = await request(app)
      .get(`/api/reports/${reportId}/url`)
      .set('Authorization', `Bearer ${otherPatientToken}`);

    expect(res.status).toBe(403);
  });
});
