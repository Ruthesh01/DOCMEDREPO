'use strict';

const { Router } = require('express');
const { body } = require('express-validator');
const {
  getMe, updateMe, getMyReports, getMyPrescriptions, getMyHistory, updateFcmToken, deleteMe,
} = require('../controllers/patientController');
const { authenticate } = require('../middleware/authMiddleware');
const { authorise } = require('../middleware/rbacMiddleware');
const { audit } = require('../middleware/auditLogger');

const router = Router();

const updateValidation = [
  body('name').optional().trim().isLength({ min: 2, max: 100 }),
  body('bloodGroup').optional().isIn(['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'])
    .withMessage('Invalid blood group'),
  body('emergencyContact.phone').optional().matches(/^[0-9]{10}$/)
    .withMessage('Phone must be 10 digits'),
];

router.use(authenticate, authorise('patient'));

router.get('/me',                  audit('VIEW_PROFILE'),       getMe);
router.put('/me',                  updateValidation, audit('UPDATE_PROFILE'), updateMe);
router.get('/me/reports',          audit('VIEW_MY_REPORTS'),    getMyReports);
router.get('/me/prescriptions',    audit('VIEW_PRESCRIPTIONS'), getMyPrescriptions);
router.get('/me/history',          audit('VIEW_HISTORY'),       getMyHistory);
router.post('/me/fcm-token',       audit('UPDATE_FCM_TOKEN'),   updateFcmToken);
router.delete('/me',               audit('DELETE_ACCOUNT'),     deleteMe);

module.exports = router;
