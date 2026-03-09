'use strict';

const { Router } = require('express');
const { body } = require('express-validator');
const {
  getMe, getPatientByQr, createPrescription, getMyPrescriptions,
} = require('../controllers/doctorController');
const { authenticate } = require('../middleware/authMiddleware');
const { authorise } = require('../middleware/rbacMiddleware');
const { audit } = require('../middleware/auditLogger');

const router = Router();

const prescriptionValidation = [
  body('patientId').isMongoId().withMessage('Valid patientId is required'),
  body('medications').isArray({ min: 1 }).withMessage('At least one medication is required'),
  body('medications.*.name').notEmpty().withMessage('Medication name is required'),
  body('medications.*.dosage').notEmpty().withMessage('Dosage is required'),
  body('medications.*.frequency').notEmpty().withMessage('Frequency is required'),
  body('medications.*.duration').notEmpty().withMessage('Duration is required'),
];

router.use(authenticate, authorise('doctor', 'admin'));

router.get('/me',                                   audit('VIEW_DOCTOR_PROFILE'),  getMe);
router.get('/patients/:patientId',
  audit('VIEW_PATIENT_RECORD', (req) => `patient:${req.params.patientId}`),
  getPatientByQr
);
router.post('/prescriptions', prescriptionValidation,
  audit('CREATE_PRESCRIPTION'), createPrescription
);
router.get('/prescriptions',  audit('VIEW_PRESCRIPTIONS'), getMyPrescriptions);

module.exports = router;
