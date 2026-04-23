// backend-nodejs/src/app.js
// Express application factory — routes, security middleware, CORS.

import express  from 'express';
import cors     from 'cors';
import helmet   from 'helmet';
import morgan   from 'morgan';

import patientsRouter  from './routes/patients.js';
import memoriesRouter  from './routes/memories.js';
import notesRouter     from './routes/notes.js';
import remindersRouter from './routes/reminders.js';
import distressRouter  from './routes/distress.js';
import alertsRouter    from './routes/alerts.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';

const app = express();

app.use(helmet());
app.use(cors({ origin: '*' }));
app.use(morgan('dev'));
app.use(express.json({ limit: '4mb' }));
app.use(express.urlencoded({ extended: true }));

// Health
app.get('/health', (_req, res) =>
  res.json({ service: 'alzcare-backend-nodejs', version: '2.0.0', status: 'ok' })
);

// API routes — all patient-data routes enforce patient_id query or body param
app.use('/api/patients',  patientsRouter);
app.use('/api/memories',  memoriesRouter);
app.use('/api/notes',     notesRouter);
app.use('/api/reminders', remindersRouter);
app.use('/api/distress',  distressRouter);
app.use('/api/alerts',    alertsRouter);

// Error handlers (must be last)
app.use(notFoundHandler);
app.use(errorHandler);

export default app;
