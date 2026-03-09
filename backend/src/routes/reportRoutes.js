'use strict';

const { Router } = require('express');
const { uploadReport, getReportUrl, deleteReport, getLocalReportFile } = require('../controllers/reportController');
const { authenticate } = require('../middleware/authMiddleware');
const { uploadLimiter } = require('../middleware/rateLimiter');
const { audit } = require('../middleware/auditLogger');

const router = Router();

router.use(authenticate);

router.post('/upload',
  uploadLimiter,
  audit('UPLOAD_REPORT'),
  uploadReport
);
router.get('/:id/url',
  audit('ACCESS_REPORT', (req) => `report:${req.params.id}`),
  getReportUrl
);
router.delete('/:id',
  audit('DELETE_REPORT', (req) => `report:${req.params.id}`),
  deleteReport
);

if (process.env.NODE_ENV === 'development') {
  router.get('/local/*', getLocalReportFile);
}

module.exports = router;
