// backend-nodejs/src/routes/patients.js
// Patient profile CRUD — strictly scoped to patient_id.

import express from 'express';
import { body, validationResult } from 'express-validator';
import { PatientProfile } from '../models/index.js';
import logger from '../../config/logger.js';

const router = express.Router();

// GET /api/patients/:patient_id
router.get('/:patient_id', async (req, res) => {
  try {
    const doc = await PatientProfile.findOne(
      { patient_id: req.params.patient_id }, { _id: 0, push_subscriptions: 0 }
    ).lean();
    if (!doc) return res.status(404).json({ error: 'Patient not found.' });
    res.json(doc);
  } catch (err) {
    logger.error(`GET /patients: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch patient.' });
  }
});

// POST /api/patients — create patient profile
router.post('/',
  [
    body('patient_id').notEmpty().trim(),
    body('name').notEmpty().trim(),
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
    try {
      const { patient_id, name, caregiver_ids = [] } = req.body;
      const doc = await PatientProfile.findOneAndUpdate(
        { patient_id },
        { $set: { name, caregiver_ids } },
        { upsert: true, new: true, setDefaultsOnInsert: true }
      );
      res.status(201).json({ id: doc._id, patient_id: doc.patient_id });
    } catch (err) {
      logger.error(`POST /patients: ${err.message}`);
      res.status(500).json({ error: 'Failed to create patient.' });
    }
  }
);

// POST /api/patients/:patient_id/subscribe — save web-push subscription
router.post('/:patient_id/subscribe', async (req, res) => {
  try {
    const { subscription } = req.body;
    await PatientProfile.updateOne(
      { patient_id: req.params.patient_id },
      { $addToSet: { push_subscriptions: subscription } }
    );
    res.json({ subscribed: true });
  } catch (err) {
    logger.error(`POST /subscribe: ${err.message}`);
    res.status(500).json({ error: 'Failed to save subscription.' });
  }
});

export default router;
