// backend-nodejs/src/routes/reminders.js
// Reminders collection — Persistent Nagger CRUD + ACK endpoint.
// patient_id is enforced on every operation.

import express from 'express';
import { body, validationResult } from 'express-validator';
import { Reminder } from '../models/index.js';
import { acknowledgeReminder, dismissReminder } from '../services/reminderEngine.js';
import { emitReminderAlert } from '../sockets/socketHub.js';
import logger from '../../config/logger.js';

const router = express.Router();

// GET /api/reminders?patient_id=X
router.get('/', async (req, res) => {
  try {
    const { patient_id } = req.query;
    if (!patient_id) return res.status(400).json({ error: 'patient_id required.' });
    const docs = await Reminder
      .find({ patient_id, status: { $ne: 'deleted' } })
      .sort({ time: 1 })
      .lean();
    res.json(docs);
  } catch (err) {
    logger.error(`GET /reminders: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch reminders.' });
  }
});

// POST /api/reminders — caregiver creates a reminder
router.post('/',
  [
    body('patient_id').notEmpty().trim(),
    body('task').notEmpty().trim(),
    body('time').matches(/^\d{2}:\d{2}$/).withMessage('time must be HH:MM'),
    body('frequency').optional().isIn(['daily', 'weekdays', 'weekends']),
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
    try {
      const { patient_id, task, time, frequency = 'daily' } = req.body;
      const doc = await Reminder.create({
        patient_id, task, time, frequency,
        status: 'pending', attempts: 0, last_notified: null,
      });
      res.status(201).json({ id: doc._id, task: doc.task, time: doc.time });
    } catch (err) {
      logger.error(`POST /reminders: ${err.message}`);
      res.status(500).json({ error: 'Failed to create reminder.' });
    }
  }
);

// PATCH /api/reminders/:id — update task/time/frequency/status
router.patch('/:id', async (req, res) => {
  try {
    const { patient_id } = req.query;
    if (!patient_id) return res.status(400).json({ error: 'patient_id required.' });
    const allowed = ['task', 'time', 'frequency', 'status'];
    const updates = {};
    for (const k of allowed) {
      if (req.body[k] !== undefined) updates[k] = req.body[k];
    }
    // Reset attempts when re-activating
    if (updates.status === 'pending') {
      updates.attempts      = 0;
      updates.last_notified = null;
      updates.snoozed_until = null;
    }
    const doc = await Reminder.findOneAndUpdate(
      { _id: req.params.id, patient_id },
      { $set: updates },
      { new: true }
    );
    if (!doc) return res.status(404).json({ error: 'Reminder not found.' });
    res.json(doc);
  } catch (err) {
    logger.error(`PATCH /reminders: ${err.message}`);
    res.status(500).json({ error: 'Failed to update reminder.' });
  }
});

// DELETE /api/reminders/:id?patient_id=X — soft delete
router.delete('/:id', async (req, res) => {
  try {
    const { patient_id } = req.query;
    if (!patient_id) return res.status(400).json({ error: 'patient_id required.' });
    await Reminder.findOneAndUpdate(
      { _id: req.params.id, patient_id },
      { $set: { status: 'deleted' } }
    );
    res.json({ deleted: req.params.id });
  } catch (err) {
    logger.error(`DELETE /reminders: ${err.message}`);
    res.status(500).json({ error: 'Failed to delete reminder.' });
  }
});

// POST /api/reminders/:id/snooze?patient_id=X
router.post('/:id/snooze', async (req, res) => {
  try {
    const { patient_id } = req.query;
    if (!patient_id) return res.status(400).json({ error: 'patient_id required.' });

    const snoozeMinutes = Math.min(
      Math.max(parseInt(req.body?.minutes ?? '10', 10) || 10, 1),
      120
    );
    const snoozedUntil = new Date(Date.now() + snoozeMinutes * 60_000);

    const doc = await Reminder.findOneAndUpdate(
      { _id: req.params.id, patient_id, status: { $in: ['pending', 'escalated'] } },
      {
        $set: {
          status: 'pending',
          last_notified: new Date(),
          snoozed_until: snoozedUntil,
        },
      },
      { new: true }
    );

    if (!doc) return res.status(404).json({ error: 'Reminder not found.' });
    res.json({
      snoozed: true,
      reminderId: req.params.id,
      snoozedUntil: snoozedUntil.toISOString(),
      minutes: snoozeMinutes,
    });
  } catch (err) {
    logger.error(`POST /reminders/snooze: ${err.message}`);
    res.status(500).json({ error: 'Failed to snooze reminder.' });
  }
});

// POST /api/reminders/:id/dismiss?patient_id=X
router.post('/:id/dismiss', async (req, res) => {
  try {
    const { patient_id } = req.query;
    if (!patient_id) return res.status(400).json({ error: 'patient_id required.' });

    const reminder = await Reminder.findOne({ _id: req.params.id, patient_id });
    if (!reminder) return res.status(404).json({ error: 'Reminder not found.' });

    await dismissReminder(req.params.id);
    res.json({ dismissed: true, reminderId: req.params.id });
  } catch (err) {
    logger.error(`POST /reminders/dismiss: ${err.message}`);
    res.status(500).json({ error: 'Failed to dismiss reminder.' });
  }
});

// POST /api/reminders/:id/ack?patient_id=X
// Patient says "Yes" or "Done" — detected by audio stream → Flutter emits ack_reminder
// → Node REST endpoint marks reminder as completed
router.post('/:id/ack', async (req, res) => {
  try {
    const { patient_id } = req.query;
    if (!patient_id) return res.status(400).json({ error: 'patient_id required.' });

    // Verify ownership before acknowledging
    const reminder = await Reminder.findOne({ _id: req.params.id, patient_id });
    if (!reminder) return res.status(404).json({ error: 'Reminder not found.' });

    await acknowledgeReminder(req.params.id);

    // Notify caregiver monitors that patient acknowledged
    emitReminderAlert(patient_id, {
      type:       'ACK',
      reminderId: req.params.id,
      patientId:  patient_id,
      task:       reminder.task,
      timestamp:  new Date().toISOString(),
    });

    res.json({ acknowledged: true, reminderId: req.params.id });
  } catch (err) {
    logger.error(`POST /reminders/ack: ${err.message}`);
    res.status(500).json({ error: 'Failed to acknowledge reminder.' });
  }
});

export default router;
