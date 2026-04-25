// backend-nodejs/src/services/reminderEngine.js
// Reminder scheduler with repeat nudges, snooze support, and escalation.

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
  const day = new Date().getDay(); // 0=Sun..6=Sat
  if (frequency === 'daily') return true;
  if (frequency === 'weekdays') return day >= 1 && day <= 5;
  if (frequency === 'weekends') return day === 0 || day === 6;
  return true;
}

function isDueForNudge(reminder, now) {
  const snoozedUntil = reminder.snoozed_until ? new Date(reminder.snoozed_until) : null;
  if (snoozedUntil && snoozedUntil > now) return false;

  const [hour, minute] = String(reminder.time || '00:00')
    .split(':')
    .map((part) => parseInt(part, 10) || 0);

  const scheduledForToday = new Date(now);
  scheduledForToday.setHours(hour, minute, 0, 0);
  if (now < scheduledForToday) return false;

  if (!reminder.last_notified) return true;

  const elapsed = (now.getTime() - new Date(reminder.last_notified).getTime()) / 60_000;
  return elapsed >= REPEAT_MINUTES;
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

    await Promise.allSettled(
      profile.push_subscriptions.map((sub) => webpush.sendNotification(sub, notification))
    );
    logger.info(`Push notifications sent for patient ${patientId}`);
  } catch (err) {
    logger.warn(`Push notification failed: ${err.message}`);
  }
}

async function reminderTick() {
  const now = new Date();
  const candidateReminders = await Reminder.find({ status: 'pending' }).lean();

  for (const reminder of candidateReminders) {
    if (!matchesFrequency(reminder.frequency)) continue;
    if (!isDueForNudge(reminder, now)) continue;

    const newAttempts = (reminder.attempts || 0) + 1;
    logger.info(
      `Reminder "${reminder.task}" | patient=${reminder.patient_id} | attempt ${newAttempts}/${MAX_ATTEMPTS}`
    );

    try {
      const aiResp = await axios.post(
        `${PYTHON_AI_URL}/generate-reminder`,
        { patient_id: reminder.patient_id, task: reminder.task },
        { timeout: 15_000 },
      );
      const audioUrl = `${PYTHON_AI_URL}${aiResp.data.audio_url}`;

      emitReminderAlert(reminder.patient_id, {
        reminderId: reminder._id.toString(),
        patientId: reminder.patient_id,
        task: reminder.task,
        time: reminder.time,
        audioUrl,
        reminderText: aiResp.data.reminder_text,
        attempts: newAttempts,
        maxAttempts: MAX_ATTEMPTS,
        timestamp: now.toISOString(),
      });

      if (newAttempts >= MAX_ATTEMPTS) {
        await Reminder.updateOne(
          { _id: reminder._id },
          {
            $set: {
              status: 'escalated',
              attempts: newAttempts,
              last_notified: now,
              snoozed_until: null,
            },
          },
        );
        logger.warn(`Reminder escalated: "${reminder.task}" patient=${reminder.patient_id}`);

        await pushToCaregiversOf(reminder.patient_id, {
          body: `Patient has not acknowledged "${reminder.task}" after ${MAX_ATTEMPTS} reminders.`,
          patientId: reminder.patient_id,
          task: reminder.task,
          type: 'REMINDER_ESCALATED',
        });
      } else {
        await Reminder.updateOne(
          { _id: reminder._id },
          {
            $inc: { attempts: 1 },
            $set: { last_notified: now, snoozed_until: null },
          },
        );
      }
    } catch (err) {
      logger.error(`Reminder processing error: ${err.message}`);
    }
  }
}

export async function dismissReminder(reminderId) {
  try {
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
    await Reminder.updateOne(
      { _id: reminderId, status: { $in: ['pending', 'escalated'] } },
      { $set: { status: 'completed', last_notified: new Date(), snoozed_until: null } },
    );
    logger.info(`Reminder ${reminderId} acknowledged and completed`);
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
