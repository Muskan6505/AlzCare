// backend-nodejs/src/app.js
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
import logger from '../config/logger.js';

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

// ── Gemini proxy — called by Python pipeline ──────────────────────────────────
app.post('/api/gemini', async (req, res) => {
  const apiKey = process.env.GEMINI_API_KEY;

  if (!apiKey) {
    logger.error('GEMINI_API_KEY is not set in environment variables.');
    return res.status(500).json({ error: 'Gemini API key not configured.' });
  }

  const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;

  try {
    const geminiResp = await fetch(geminiUrl, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(req.body),
    });

    const data = await geminiResp.json();

    if (!geminiResp.ok) {
      logger.error(`Gemini API error ${geminiResp.status}: ${JSON.stringify(data)}`);
      return res.status(geminiResp.status).json({ error: data });
    }

    return res.json(data);
  } catch (err) {
    logger.error(`Gemini proxy failed: ${err.message}`);
    return res.status(500).json({ error: 'Failed to reach Gemini API.' });
  }
});

// API routes
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