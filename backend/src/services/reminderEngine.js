// backend-nodejs/src/services/reminderEngine.js
// ================================================================
//  THE PERSISTENT NAGGER
//  Uses node-cron (ticks every minute) to drive the reminder loop.
//
//  Flow:
//    1. Find all Reminders WHERE status='pending' AND time=HH:MM
//    2. Call Python /generate-reminder to get personalised TTS audio
//    3. Emit play_audio to patient via Socket.io
//    4. Increment attempts; schedule re-check via last_notified
//    5. If patient ACKs → mark status='completed'
//    6. If attempts >= MAX (default 3) → mark status='escalated'
//       → send push notification to all caregiver devices
// ================================================================

import cron   from 'node-cron';
import axios  from 'axios';
import webpush from 'web-push';

import { Reminder, PatientProfile } from '../models/index.js';
import { emitReminderAlert } from '../sockets/socketHub.js';
import logger from '../../config/logger.js';

const PYTHON_AI_URL  = process.env.PYTHON_AI_URL  || 'http://localhost:8001';
const MAX_ATTEMPTS   = parseInt(process.env.REMINDER_MAX_ATTEMPTS || '3', 10);
const REPEAT_MINUTES = parseInt(process.env.REMINDER_REPEAT_INTERVAL_MINUTES || '5', 10);

// Configure VAPID for web-push notifications to caregiver devices
if (process.env.VAPID_PUBLIC_KEY && process.env.VAPID_PRIVATE_KEY) {
  webpush.setVapidDetails(
    process.env.VAPID_MAILTO || 'mailto:admin@alzcare.app',
    process.env.VAPID_PUBLIC_KEY,
    process.env.VAPID_PRIVATE_KEY,
  );
}

/** Returns true if a reminder is due for another nudge. */
function isDueForNudge(reminder) {
  if (!reminder.last_notified) return true;
  const elapsed = (Date.now() - new Date(reminder.last_notified).getTime()) / 60_000;
  return elapsed >= REPEAT_MINUTES;
}

/** Returns true if today matches the reminder's frequency. */
function matchesFrequency(frequency) {
  const day = new Date().getDay(); // 0=Sun…6=Sat
  if (frequency === 'daily')    return true;
  if (frequency === 'weekdays') return day >= 1 && day <= 5;
  if (frequency === 'weekends') return day === 0 || day === 6;
  return true;
}

/** Push a web-push notification to all caregiver devices. */
async function pushToCaregiversOf(patientId, payload) {
  try {
    const profile = await PatientProfile.findOne({ patient_id: patientId }).lean();
    if (!profile || !profile.push_subscriptions?.length) return;

    const notification = JSON.stringify({
      title: '⚠️  AlzCare Alert',
      body:  payload.body,
      data:  payload,
    });

    await Promise.allSettled(
      profile.push_subscriptions.map((sub) =>
        webpush.sendNotification(sub, notification)
      )
    );
    logger.info(`Push notifications sent for patient ${patientId}`);
  } catch (err) {
    logger.warn(`Push notification failed: ${err.message}`);
  }
}

/** Core reminder tick — called every minute by node-cron. */
async function reminderTick() {
  const now   = new Date();
  const hhmm  = now.toTimeString().slice(0, 5); // "HH:MM"

  // Find all pending reminders due now across all patients
  const dueReminders = await Reminder.find({ time: hhmm, status: 'pending' }).lean();

  for (const reminder of dueReminders) {
    // Skip if frequency doesn't match today
    if (!matchesFrequency(reminder.frequency)) continue;

    // Skip if not yet time for the next nudge
    if (!isDueForNudge(reminder)) continue;

    const newAttempts = (reminder.attempts || 0) + 1;
    logger.info(`⏰  Nagger: "${reminder.task}" | patient=${reminder.patient_id} | attempt ${newAttempts}/${MAX_ATTEMPTS}`);

    try {
      // 1. Ask Python to generate personalised, gentle TTS reminder
      const aiResp = await axios.post(
        `${PYTHON_AI_URL}/generate-reminder`,
        { patient_id: reminder.patient_id, task: reminder.task },
        { timeout: 15_000 }
      );
      const audioUrl = `${PYTHON_AI_URL}${aiResp.data.audio_url}`;

      // 2. Emit play_audio to patient's Flutter device via Socket.io
      emitReminderAlert(reminder.patient_id, {
        reminderId:  reminder._id.toString(),
        patientId:   reminder.patient_id,
        task:        reminder.task,
        audioUrl,
        reminderText: aiResp.data.reminder_text,
        attempts:    newAttempts,
        maxAttempts: MAX_ATTEMPTS,
        timestamp:   now.toISOString(),
      });

      // 3. Update DB — increment attempts + last_notified
      if (newAttempts >= MAX_ATTEMPTS) {
        // ESCALATE: mark escalated, notify caregivers
        await Reminder.updateOne(
          { _id: reminder._id },
          { $set: { status: 'escalated', attempts: newAttempts, last_notified: now } }
        );
        logger.warn(`🚨  Reminder escalated: "${reminder.task}" patient=${reminder.patient_id}`);

        await pushToCaregiversOf(reminder.patient_id, {
          body:      `Patient has not acknowledged "${reminder.task}" after ${MAX_ATTEMPTS} reminders.`,
          patientId: reminder.patient_id,
          task:      reminder.task,
          type:      'REMINDER_ESCALATED',
        });
      } else {
        await Reminder.updateOne(
          { _id: reminder._id },
          { $inc: { attempts: 1 }, $set: { last_notified: now } }
        );
      }
    } catch (err) {
      logger.error(`Reminder processing error: ${err.message}`);
    }
  }
}

/** Mark a reminder as completed (called when patient acknowledges via audio). */
export async function acknowledgeReminder(reminderId) {
  try {
    await Reminder.updateOne(
      { _id: reminderId, status: 'pending' },
      { $set: { status: 'completed', last_notified: new Date() } }
    );
    logger.info(`✅  Reminder ${reminderId} acknowledged and completed`);
  } catch (err) {
    logger.warn(`acknowledgeReminder failed: ${err.message}`);
  }
}

/** Start the cron scheduler. */
export function startReminderEngine() {
  cron.schedule('* * * * *', reminderTick, { timezone: 'UTC' });
  logger.info(`✅  Persistent Nagger started (every minute, max ${MAX_ATTEMPTS} attempts, re-nudge every ${REPEAT_MINUTES} min)`);
}
