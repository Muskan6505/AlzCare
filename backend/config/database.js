// backend-nodejs/config/database.js
import mongoose from 'mongoose';
import logger   from './logger.js';

export async function connectDB() {
  const uri = process.env.MONGO_URI;
  const dbName = process.env.DB_NAME || 'AlzCare';

  if (!uri) {
    logger.warn('MONGO_URI not configured — running without database.');
    return;
  }

  try {
    await mongoose.connect(uri, {
      dbName: dbName,
      serverSelectionTimeoutMS: 8000,
    });

    logger.info(`✅ MongoDB connected: ${mongoose.connection.host}`);
  } catch (err) {
    logger.error(`MongoDB connection failed: ${err.message}`);
    process.exit(1);
  }
}

mongoose.connection.on('disconnected', () =>
  logger.warn('MongoDB disconnected — will attempt reconnect …')
);
mongoose.connection.on('reconnected', () =>
  logger.info('MongoDB reconnected ✅')
);
