'use strict';

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const mongoSanitize = require('express-mongo-sanitize');
const hpp = require('hpp');

const { globalErrorHandler } = require('./middleware/errorHandler');
const authRoutes = require('./routes/authRoutes');
const patientRoutes = require('./routes/patientRoutes');
const doctorRoutes = require('./routes/doctorRoutes');
const reportRoutes = require('./routes/reportRoutes');
const qrRoutes = require('./routes/qrRoutes');

const app = express();

// ── HTTP Security Headers ────────────────────────────────────────────────────
app.use(helmet());

// ── CORS (only allow known origins) ─────────────────────────────────────────
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '').split(',').filter(Boolean);
app.use(cors({
  origin: (origin, cb) => {
    // Allow requests with no origin, matched origins, or when in test/dev environments
    if (!origin || allowedOrigins.includes(origin) || process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'development') {
      return cb(null, true);
    }
    cb(new Error(`CORS policy: origin ${origin} not allowed`));
  },
  credentials: true,
}));

// ── Body Parsing ─────────────────────────────────────────────────────────────
app.use(express.json({ limit: '10kb' }));
app.use(express.urlencoded({ extended: true, limit: '10kb' }));

// ── NoSQL Injection Prevention ───────────────────────────────────────────────
app.use(mongoSanitize());

// ── HTTP Parameter Pollution Prevention ─────────────────────────────────────
app.use(hpp());

// ── Request Logging (skip in test) ──────────────────────────────────────────
if (process.env.NODE_ENV !== 'test') {
  app.use(morgan('combined'));
}

// ── Routes ───────────────────────────────────────────────────────────────────
app.use('/api/auth', authRoutes);
app.use('/api/patients', patientRoutes);
app.use('/api/doctors', doctorRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/qr', qrRoutes);

// ── Health Check ─────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => res.json({ status: 'ok' }));

// ── 404 Handler ──────────────────────────────────────────────────────────────
app.use((_req, res) => res.status(404).json({ error: 'Route not found' }));

// ── Global Error Handler ─────────────────────────────────────────────────────
app.use(globalErrorHandler);

module.exports = app;
