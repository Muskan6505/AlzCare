// backend-nodejs/src/routes/memories.js
// Patient_Memories — long-term RAG collection.
// All queries are strictly scoped to patient_id.

import express from 'express';
import { body, validationResult } from 'express-validator';
import { PatientMemory } from '../models/index.js';
import logger from '../../config/logger.js';

const router = express.Router();

// POST /api/memories — store a new memory (embedding supplied by Python)
router.post('/',
  [
    body('patient_id').notEmpty().trim(),
    body('content').notEmpty().trim(),
    body('embedding').isArray({ min: 1 }),
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
    try {
      const { patient_id, content, embedding, tags = [] } = req.body;
      const doc = await PatientMemory.create({ patient_id, content, embedding, tags });
      await PatientMemory.updateOne(
        { patient_id },
        { $inc: { anchor_memories_count: 1 } }
      ).catch(() => {});
      res.status(201).json({ id: doc._id });
    } catch (err) {
      logger.error(`POST /memories: ${err.message}`);
      res.status(500).json({ error: 'Failed to save memory.' });
    }
  }
);

// GET /api/memories?patient_id=X&limit=20 — list memories (caregiver dashboard)
router.get('/', async (req, res) => {
  try {
    const { patient_id, limit = 20 } = req.query;
    if (!patient_id) return res.status(400).json({ error: 'patient_id required.' });
    const docs = await PatientMemory
      .find({ patient_id }, { embedding: 0 })
      .sort({ createdAt: -1 })
      .limit(Math.min(parseInt(limit), 100))
      .lean();
    res.json(docs);
  } catch (err) {
    logger.error(`GET /memories: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch memories.' });
  }
});

// DELETE /api/memories/:id?patient_id=X — scoped delete
router.delete('/:id', async (req, res) => {
  try {
    const { patient_id } = req.query;
    if (!patient_id) return res.status(400).json({ error: 'patient_id required.' });
    await PatientMemory.findOneAndDelete({ _id: req.params.id, patient_id });
    res.json({ deleted: req.params.id });
  } catch (err) {
    logger.error(`DELETE /memories: ${err.message}`);
    res.status(500).json({ error: 'Failed to delete memory.' });
  }
});

// POST /api/memories/search — Atlas Vector Search (called by Python pipeline)
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
      const { embedding, patient_id, topK = 3 } = req.body;
      const pipeline = [
        {
          $vectorSearch: {
            index:         'vector_index',   // Atlas index name
            path:          'embedding',
            queryVector:   embedding,
            numCandidates: topK * 10,
            limit:         topK,
            filter:        { patient_id },   // strict patient_id scoping
          },
        },
        {
          $project: {
            _id: 0, content: 1, tags: 1,
            score: { $meta: 'vectorSearchScore' },
          },
        },
      ];
      const memories = await PatientMemory.aggregate(pipeline);
      res.json({ memories });
    } catch (err) {
      logger.warn(`Vector search (memories) failed: ${err.message}`);
      res.json({ memories: [] });
    }
  }
);

export default router;
