// backend-nodejs/src/routes/distress.js
// Distress_Logs — written by Python pipeline after each audio analysis.
// Read by caregiver dashboard for history.

import express from 'express';
import { body, validationResult } from 'express-validator';
import { DistressLog } from '../models/index.js';
import logger from '../../config/logger.js';

const router = express.Router();

// POST /api/distress — Python pipeline writes a log entry
router.post('/',
  [
    body('patient_id').notEmpty(),
    body('emotion').notEmpty(),
    body('pitchVariance').isNumeric(),
    body('silenceRatio').isNumeric(),
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
    try {
      const {
        patient_id, timestamp, transcript = '',
        emotion, distressFlag = false,
        pitchVariance, silenceRatio, prosodicState = 'normal',
      } = req.body;

      const doc = await DistressLog.create({
        patient_id,
        timestamp:    timestamp ? new Date(timestamp) : new Date(),
        transcript,
        emotion,
        distressFlag,
        pitchVariance,
        silenceRatio,
        prosodicState,
      });
      res.status(201).json({ id: doc._id });
    } catch (err) {
      logger.error(`POST /distress: ${err.message}`);
      res.status(500).json({ error: 'Failed to save distress log.' });
    }
  }
);

// GET /api/distress?patient_id=X&limit=50
router.get('/', async (req, res) => {
  try {
    const { patient_id, limit = 50 } = req.query;
    if (!patient_id) return res.status(400).json({ error: 'patient_id required.' });
    const docs = await DistressLog
      .find({ patient_id })
      .sort({ timestamp: -1 })
      .limit(Math.min(parseInt(limit), 200))
      .lean();
    res.json(docs);
  } catch (err) {
    logger.error(`GET /distress: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch distress logs.' });
  }
});

export default router;
