// backend-nodejs/src/routes/alerts.js
// Receives alert signals from the Python AI pipeline and
// broadcasts them to the correct caregiver rooms via Socket.io.

import express from 'express';
import { emitDistressAlert } from '../sockets/socketHub.js';
import logger from '../../config/logger.js';

const router = express.Router();

// POST /api/alerts/agitation — called by Python when distress_flag=True
router.post('/agitation', (req, res) => {
  const {
    patient_id, emotion, transcript = '',
    logId = null, timestamp,
  } = req.body;

  if (!patient_id) return res.status(400).json({ error: 'patient_id required.' });

  const payload = {
    type:       'DISTRESS',
    patientId:  patient_id,
    emotion,
    transcript,
    logId,
    timestamp:  timestamp || new Date().toISOString(),
  };

  logger.warn(`🚨  Distress alert — patient=${patient_id}, emotion=${emotion}`);
  emitDistressAlert(patient_id, payload);

  res.json({ broadcasted: true });
});

export default router;
