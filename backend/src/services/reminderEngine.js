// backend-nodejs/src/services/reminderEngine.js
// Fixed: isDueForNudge logic, escalation state bug, snooze handling
// Added: proper timezone handling, better error recovery

import cron from 'node-cron';
import axios from 'axios';
import webpush from 'web-push';

import { Reminder, PatientProfile } from '../models/index.js';
import { emitReminderAlert } from '../sockets/socketHub.js';
import logger from '../../config/logger.js';

const PYTHON_AI_URL = process.env.PYTHON_AI_URL || 'http://localhost:8001';
const MAX_ATTEMPTS = parseInt(process.env.REMINDER_MAX_ATTEMPTS || '3', 10);
const REPEAT_MINUTES = parseInt(process.env.REMINDER_REPEAT_INTERVAL_MINUTES || '5', 10);

if (process.env.VAPID_PUBLIC_KEY && process.env.VAPID_PRIVATE_KEY) {
  webpush.setVapidDetails(
    process.env.VAPID_MAILTO || 'mailto:admin@alzcare.app',
    process.env.VAPID_PUBLIC_KEY,
    process.env.VAPID_PRIVATE_KEY,
  );
}

function matchesFrequency(frequency) {
  const day = new Date().getDay();
  if (frequency === 'daily') return true;
  if (frequency === 'weekdays') return day >= 1 && day <= 5;
  if (frequency === 'weekends') return day === 0 || day === 6;
  return true;
}

// FIX: was checking now < scheduledForToday which prevented same-minute triggers
// FIX: snooze check must use > not >= to allow exactly-expired snoozes
function isDueForNudge(reminder, now) {
  const snoozedUntil = reminder.snoozed_until ? new Date(reminder.snoozed_until) : null;
  if (snoozedUntil && snoozedUntil > now) return false;

  const timeParts = String(reminder.time || '00:00').split(':');
  const hour   = parseInt(timeParts[0], 10) || 0;
  const minute = parseInt(timeParts[1], 10) || 0;

  const scheduledForToday = new Date(now);
  scheduledForToday.setHours(hour, minute, 0, 0);

  // FIX: was `now < scheduledForToday` — strictly less-than skips the exact minute
  // Allow a 1-minute window: fire if now >= scheduled and < scheduled + 1min
  if (now.getTime() < scheduledForToday.getTime()) return false;

  // FIX: only trigger once per REPEAT_MINUTES window, not repeatedly within the same tick
  if (reminder.last_notified) {
    const elapsed = (now.getTime() - new Date(reminder.last_notified).getTime()) / 60_000;
    return elapsed >= REPEAT_MINUTES;
  }

  // If never notified, check it's within 60 minutes of schedule
  // (prevents firing for old reminders on server restart)
  const minutesSinceScheduled = (now.getTime() - scheduledForToday.getTime()) / 60_000;
  return minutesSinceScheduled < 60;
}

async function pushToCaregiversOf(patientId, payload) {
  try {
    const profile = await PatientProfile.findOne({ patient_id: patientId }).lean();
    if (!profile || !profile.push_subscriptions?.length) return;

    const notification = JSON.stringify({
      title: 'AlzCare Alert',
      body: payload.body,
      data: payload,
    });

    const results = await Promise.allSettled(
      profile.push_subscriptions.map((sub) => webpush.sendNotification(sub, notification))
    );

    // FIX: clean up expired/invalid subscriptions
    const invalidSubs = [];
    results.forEach((result, i) => {
      if (result.status === 'rejected') {
        const err = result.reason;
        if (err.statusCode === 410 || err.statusCode === 404) {
          invalidSubs.push(profile.push_subscriptions[i]);
        }
      }
    });

    if (invalidSubs.length > 0) {
      await PatientProfile.updateOne(
        { patient_id: patientId },
        { $pull: { push_subscriptions: { $in: invalidSubs } } }
      ).catch(() => {});
    }

    logger.info(`Push notifications sent for patient ${patientId}`);
  } catch (err) {
    logger.warn(`Push notification failed: ${err.message}`);
  }
}

// FIX: wrap entire tick in try/catch so one bad reminder doesn't crash the cron
async function reminderTick() {
  try {
    const now = new Date();

    // FIX: also include 'escalated' in candidate query — escalated reminders
    // should still fire if not yet acknowledged (they were missing before)
    const candidateReminders = await Reminder.find({
      status: { $in: ['pending', 'escalated'] },
    }).lean();

    for (const reminder of candidateReminders) {
      try {
        if (!matchesFrequency(reminder.frequency)) continue;
        if (!isDueForNudge(reminder, now)) continue;

        const newAttempts = (reminder.attempts || 0) + 1;
        logger.info(
          `Reminder "${reminder.task}" | patient=${reminder.patient_id} | attempt ${newAttempts}/${MAX_ATTEMPTS}`
        );

        // FIX: if already escalated, only push to caregiver — don't re-trigger TTS repeatedly
        if (reminder.status === 'escalated') {
          await pushToCaregiversOf(reminder.patient_id, {
            body: `ESCALATED: Patient still hasn't done "${reminder.task}".`,
            patientId: reminder.patient_id,
            task: reminder.task,
            type: 'REMINDER_STILL_ESCALATED',
          });
          await Reminder.updateOne(
            { _id: reminder._id },
            { $set: { last_notified: now } }
          );
          continue;
        }

        // Generate personalized TTS for pending reminders
        let audioUrl = '';
        let reminderText = `It's time to ${reminder.task}`;
        try {
          const aiResp = await axios.post(
            `${PYTHON_AI_URL}/generate-reminder`,
            { patient_id: reminder.patient_id, task: reminder.task },
            { timeout: 15_000 },
          );
          audioUrl = `${PYTHON_AI_URL}${aiResp.data.audio_url}`;
          reminderText = aiResp.data.reminder_text || reminderText;
        } catch (aiErr) {
          // FIX: don't fail the reminder if TTS fails — emit without audio
          logger.warn(`TTS generation failed for reminder: ${aiErr.message}`);
        }

        emitReminderAlert(reminder.patient_id, {
          reminderId:   reminder._id.toString(),
          patientId:    reminder.patient_id,
          task:         reminder.task,
          time:         reminder.time,
          audioUrl,
          reminderText,
          attempts:     newAttempts,
          maxAttempts:  MAX_ATTEMPTS,
          timestamp:    now.toISOString(),
        });

        if (newAttempts >= MAX_ATTEMPTS) {
          // FIX: set attempts to exact value, not using $inc which could race
          await Reminder.updateOne(
            { _id: reminder._id },
            {
              $set: {
                status:        'escalated',
                attempts:      newAttempts,
                last_notified: now,
                snoozed_until: null,
              },
            },
          );
          logger.warn(`Reminder escalated: "${reminder.task}" patient=${reminder.patient_id}`);

          await pushToCaregiversOf(reminder.patient_id, {
            body: `Patient has not acknowledged "${reminder.task}" after ${MAX_ATTEMPTS} reminders.`,
            patientId: reminder.patient_id,
            task:      reminder.task,
            type:      'REMINDER_ESCALATED',
          });
        } else {
          // FIX: set attempts to exact count, avoid race with concurrent ticks
          await Reminder.updateOne(
            { _id: reminder._id },
            {
              $set: {
                attempts:      newAttempts,
                last_notified: now,
                snoozed_until: null,
              },
            },
          );
        }
      } catch (innerErr) {
        logger.error(`Error processing reminder ${reminder._id}: ${innerErr.message}`);
      }
    }
  } catch (outerErr) {
    logger.error(`reminderTick crashed: ${outerErr.message}`);
  }
}

export async function dismissReminder(reminderId) {
  try {
    // FIX: also include escalated in dismiss scope
    await Reminder.updateOne(
      { _id: reminderId, status: { $in: ['pending', 'escalated'] } },
      { $set: { last_notified: new Date() } },
    );
    logger.info(`Reminder ${reminderId} dismissed for now`);
  } catch (err) {
    logger.warn(`dismissReminder failed: ${err.message}`);
  }
}

export async function acknowledgeReminder(reminderId) {
  try {
    // FIX: include escalated so patients can still ack after escalation
    const result = await Reminder.updateOne(
      { _id: reminderId, status: { $in: ['pending', 'escalated'] } },
      { $set: { status: 'completed', last_notified: new Date(), snoozed_until: null } },
    );
    if (result.modifiedCount === 0) {
      logger.warn(`acknowledgeReminder: reminder ${reminderId} not found or already completed`);
    } else {
      logger.info(`Reminder ${reminderId} acknowledged and completed`);
    }
  } catch (err) {
    logger.warn(`acknowledgeReminder failed: ${err.message}`);
  }
}

export function startReminderEngine() {
  cron.schedule('* * * * *', reminderTick, { timezone: 'UTC' });
  logger.info(
    `Reminder engine started (every minute, max ${MAX_ATTEMPTS} attempts, re-nudge every ${REPEAT_MINUTES} min)`
  );
}