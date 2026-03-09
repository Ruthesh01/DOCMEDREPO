'use strict';

const { Router } = require('express');
const { body } = require('express-validator');
const {
  registerPatient, registerDoctor, login,
  verifyOtp, refreshToken, logout, changePassword,
} = require('../controllers/authController');
const { authenticate } = require('../middleware/authMiddleware');
const { authLimiter } = require('../middleware/rateLimiter');
const { audit } = require('../middleware/auditLogger');

const router = Router();

// ── Validation chains ────────────────────────────────────────────────────────
const patientRegisterValidation = [
  body('name').trim().isLength({ min: 2, max: 100 }).withMessage('Name must be 2-100 characters'),
  body('email').isEmail().normalizeEmail().withMessage('Valid email required'),
  body('password').isLength({ min: 8 }).withMessage('Password must be at least 8 characters'),
  body('emergencyContact.name').notEmpty().withMessage('Emergency contact name is required'),
  body('emergencyContact.phone').matches(/^[0-9]{10}$/).withMessage('Emergency contact phone must be 10 digits'),
  body('emergencyContact.relation').notEmpty().withMessage('Emergency contact relation is required'),
];

const doctorRegisterValidation = [
  body('name').trim().notEmpty().withMessage('Name is required'),
  body('email').isEmail().normalizeEmail().withMessage('Valid email required'),
  body('password').isLength({ min: 8 }).withMessage('Password must be at least 8 characters'),
  body('specialization').notEmpty().withMessage('Specialization is required'),
  body('licenseNumber').notEmpty().withMessage('License number is required'),
];

const loginValidation = [
  body('email').isEmail().normalizeEmail(),
  body('password').notEmpty(),
  body('role').isIn(['patient', 'doctor']).withMessage('Role must be patient or doctor'),
];

// ── Routes ───────────────────────────────────────────────────────────────────
router.post('/register/patient', authLimiter, patientRegisterValidation, registerPatient);
router.post('/register/doctor',  authLimiter, doctorRegisterValidation,  registerDoctor);
router.post('/login',            authLimiter, loginValidation, audit('LOGIN'), login);
router.post('/verify-otp',       authLimiter, verifyOtp);
router.post('/refresh-token',    refreshToken);
router.post('/logout',           logout);
router.post('/change-password',  authenticate, audit('CHANGE_PASSWORD'), changePassword);

module.exports = router;
