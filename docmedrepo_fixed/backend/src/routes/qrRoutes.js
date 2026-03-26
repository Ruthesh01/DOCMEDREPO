'use strict';

const { Router } = require('express');
const { generateQr, scanQr } = require('../controllers/qrController');
const { authenticate } = require('../middleware/authMiddleware');
const { authorise } = require('../middleware/rbacMiddleware');
const { qrLimiter } = require('../middleware/rateLimiter');
const { audit } = require('../middleware/auditLogger');

const router = Router();

router.use(authenticate);

// Patients generate QR; doctors scan QR
router.post('/generate',
  authorise('patient'),
  qrLimiter,
  audit('GENERATE_QR'),
  generateQr
);
router.post('/scan',
  authorise('doctor', 'admin'),
  audit('SCAN_QR'),
  scanQr
);

module.exports = router;
