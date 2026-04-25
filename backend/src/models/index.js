// backend-nodejs/src/models/index.js
// Mongoose schemas for the unified MongoDB design.
// All patient-data collections carry patient_id for strict data isolation.

import mongoose from 'mongoose';
const { Schema, model } = mongoose;

// ── Patient_Profile ───────────────────────────────────────────────────────────
const PatientProfileSchema = new Schema({
  patient_id:            { type: String, required: true, unique: true, index: true },
  name:                  { type: String, required: true, trim: true },
  caregiver_ids:         [{ type: String }],
  anchor_memories_count: { type: Number, default: 0 },
  push_subscriptions:    [{ type: Object }],  // web-push subscription objects
}, { timestamps: true, collection: 'Patient_Profile' });

// ── Patient_Memories  (long-term RAG) ────────────────────────────────────────
const PatientMemorySchema = new Schema({
  patient_id: { type: String, required: true, index: true },
  content:    { type: String, required: true, trim: true },
  embedding:  { type: [Number], required: true },   // 384-dim MiniLM
  tags:       [{ type: String, trim: true }],
}, { timestamps: true, collection: 'Patient_Memories' });

// ── Caregiver_Notes  (short-term / daily RAG) ─────────────────────────────────
const CaregiverNoteSchema = new Schema({
  patient_id:   { type: String, required: true, index: true },
  caregiver_id: { type: String, default: '' },
  note:         { type: String, required: true, trim: true },
  embedding:    { type: [Number], required: true },  // 384-dim MiniLM
  created_at:   { type: Date, default: Date.now },
}, { collection: 'Caregiver_Notes' });

// ── Reminders  (Persistent Nagger) ───────────────────────────────────────────
const ReminderSchema = new Schema({
  patient_id:    { type: String, required: true, index: true },
  task:          { type: String, required: true, trim: true },
  time:          { type: String, required: true },     // "HH:MM" 24-hour
  frequency:     { type: String, enum: ['daily', 'weekdays', 'weekends'], default: 'daily' },
  attempts:      { type: Number, default: 0 },
  status:        { type: String, enum: ['pending', 'completed', 'escalated', 'paused', 'deleted'], default: 'pending' },
  last_notified: { type: Date, default: null },
  snoozed_until: { type: Date, default: null },
}, { timestamps: true, collection: 'Reminders' });

// ── Distress_Logs ─────────────────────────────────────────────────────────────
const DistressLogSchema = new Schema({
  patient_id:    { type: String, required: true, index: true },
  timestamp:     { type: Date, default: Date.now },
  transcript:    { type: String, default: '' },
  emotion:       { type: String, required: true },
  distressFlag:  { type: Boolean, default: false },
  pitchVariance: { type: Number, default: 0 },
  silenceRatio:  { type: Number, default: 0 },
  prosodicState: { type: String, default: 'normal' },
}, { collection: 'Distress_Logs' });

export const PatientProfile  = model('PatientProfile',  PatientProfileSchema);
export const PatientMemory   = model('PatientMemory',   PatientMemorySchema);
export const CaregiverNote   = model('CaregiverNote',   CaregiverNoteSchema);
export const Reminder        = model('Reminder',        ReminderSchema);
export const DistressLog     = model('DistressLog',     DistressLogSchema);
