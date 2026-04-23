// backend-nodejs/src/sockets/socketHub.js
// Socket.io hub for always-on patient/caregiver connections.
//
// Rooms:
//   patient:<patient_id>   — patient's Flutter device
//   caregiver:<user_id>    — caregiver's Flutter device
//
// Events emitted TO Flutter:
//   play_audio       { audioUrl, text, emotion }   — TTS reply / reminder
//   distress_alert   { patientId, emotion, transcript, timestamp }
//   reminder_alert   { patientId, task, time, attempts }
//   reminder_ack     { patientId, reminderId }     — echoed back to caregiver
//
// Events received FROM Flutter:
//   join_patient     { patientId }
//   join_caregiver   { caregiverId, patientId }
//   ack_reminder     { patientId, reminderId }     — patient confirmed reminder

import { Server } from 'socket.io';
import logger from '../../config/logger.js';

let _io = null;

export function initSocketHub(httpServer) {
  _io = new Server(httpServer, {
    cors: { origin: '*', methods: ['GET', 'POST'] },
    pingTimeout:  60_000,
    pingInterval: 25_000,
  });

  _io.on('connection', (socket) => {
    logger.info(`Socket connected: ${socket.id}`);

    // Patient joins their personal room
    socket.on('join_patient', ({ patientId }) => {
      socket.join(`patient:${patientId}`);
      logger.info(`Patient ${patientId} joined room patient:${patientId}`);
    });

    // Caregiver joins to monitor a patient
    socket.on('join_caregiver', ({ caregiverId, patientId }) => {
      socket.join(`caregiver:${caregiverId}`);
      socket.join(`monitor:${patientId}`);  // also watches patient's activity
      logger.info(`Caregiver ${caregiverId} monitoring patient ${patientId}`);
    });

    // Patient acknowledges a reminder ("Yes" / "Done" detected via audio)
    socket.on('ack_reminder', ({ patientId, reminderId }) => {
      logger.info(`Reminder ACK — patient=${patientId} reminder=${reminderId}`);
      // Forward ACK to all caregivers monitoring this patient
      _io.to(`monitor:${patientId}`).emit('reminder_ack', { patientId, reminderId });
    });

    socket.on('disconnect', () =>
      logger.info(`Socket disconnected: ${socket.id}`)
    );
  });

  logger.info('✅  Socket.io hub ready');
}

// ── Emission helpers ──────────────────────────────────────────────────────────

/** Push a TTS audio URL to the patient's device. */
export function emitPlayAudio(patientId, payload) {
  if (!_io) return;
  _io.to(`patient:${patientId}`).emit('play_audio', payload);
}

/** Send a distress alert to all caregivers monitoring this patient. */
export function emitDistressAlert(patientId, payload) {
  if (!_io) return;
  _io.to(`monitor:${patientId}`).emit('distress_alert', payload);
}

/** Send a reminder notification to the patient's device and caregiver monitors. */
export function emitReminderAlert(patientId, payload) {
  if (!_io) return;
  _io.to(`patient:${patientId}`).emit('reminder_alert', payload);
  _io.to(`monitor:${patientId}`).emit('reminder_alert', payload);
}

export function getIO() { return _io; }
