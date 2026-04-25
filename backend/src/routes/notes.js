// backend-nodejs/src/routes/notes.js
// Caregiver_Notes — short-term / daily RAG collection.
// Caregivers write notes; Python searches them during each interaction.

import express from 'express';
import { body, validationResult } from 'express-validator';
import { CaregiverNote } from '../models/index.js';
import logger from '../../config/logger.js';

const router = express.Router();

// POST /api/notes — caregiver submits a note (embedding supplied by Python)
router.post('/',
  [
    body('patient_id').notEmpty().trim(),
    body('note').notEmpty().trim(),
    body('embedding').isArray({ min: 1 }),
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
    try {
      const { patient_id, caregiver_id = '', note, embedding } = req.body;
      const doc = await CaregiverNote.create({ patient_id, caregiver_id, note, embedding });
      res.status(201).json({ id: doc._id });
    } catch (err) {
      logger.error(`POST /notes: ${err.message}`);
      res.status(500).json({ error: 'Failed to save note.' });
    }
  }
);

// GET /api/notes?patient_id=X&limit=20
router.get('/', async (req, res) => {
  try {
    const { patient_id, limit = 20 } = req.query;
    if (!patient_id) return res.status(400).json({ error: 'patient_id required.' });
    const docs = await CaregiverNote
      .find({ patient_id }, { embedding: 0 })
      .sort({ created_at: -1 })
      .limit(Math.min(parseInt(limit), 100))
      .lean();
    res.json(docs);
  } catch (err) {
    logger.error(`GET /notes: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch notes.' });
  }
});

// DELETE /api/notes/:id?patient_id=X
router.delete('/:id', async (req, res) => {
  try {
    const { patient_id } = req.query;
    if (!patient_id) return res.status(400).json({ error: 'patient_id required.' });
    await CaregiverNote.findOneAndDelete({ _id: req.params.id, patient_id });
    res.json({ deleted: req.params.id });
  } catch (err) {
    logger.error(`DELETE /notes: ${err.message}`);
    res.status(500).json({ error: 'Failed to delete note.' });
  }
});

// POST /api/notes/search — Atlas Vector Search scoped to patient_id
router.post('/search',
  [
    body('embedding').isArray({ min: 1 }),
    body('patient_id').notEmpty(),
    body('topK').optional().isInt({ min: 1, max: 20 }),
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
    try {
      const { embedding, patient_id, topK = 2 } = req.body;
      const pipeline = [
        {
          $vectorSearch: {
            index:         'vector_index',
            path:          'embedding',
            queryVector:   embedding,
            numCandidates: topK * 10,
            limit:         topK,
            filter:        { patient_id },   // strict patient_id scoping
          },
        },
        {
          $project: {
            _id: 0, note: 1, caregiver_id: 1, created_at: 1,
            score: { $meta: 'vectorSearchScore' },
          },
        },
      ];
      const notes = await CaregiverNote.aggregate(pipeline);
      res.json({ notes });
    } catch (err) {
      logger.warn(`Vector search (notes) failed: ${err.message}`);
      res.json({ notes: [] });
    }
  }
);

export default router;
