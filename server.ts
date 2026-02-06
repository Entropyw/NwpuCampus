import http from 'node:http';
import { createReadStream, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { URL, fileURLToPath } from 'node:url';
import { extname, join } from 'node:path';
import nodemailer from 'nodemailer';
import Database from 'better-sqlite3';

interface User {
  id: string;
  username: string;
  password: string;
  isAdmin: boolean;
  email?: string;
  hiddenPlaceIds: string[];
  createdAt: number;
}

interface UserPlaceState {
  userId: string;
  placeId: string;
  hidden: boolean;
  favorite: boolean;
  updatedAt: number;
}

interface PlaceVotes {
  up: number;
  down: number;
}

interface Place {
  id: string;
  name: string;
  lat: number;
  lon: number;
  description: string;
  imagePath?: string;
  imageUrl: string;
  ownerId: string;
  ownerName: string;
  status: 'private' | 'pending' | 'approved' | 'rejected';
  category: 'normal' | 'hazard';
  hazardType: 'water' | 'slippery' | 'danger' | '';
  votes: PlaceVotes;
  voters: Record<string, number>;
  createdAt: number;
  updatedAt: number;
  sourcePlaceId?: string;
  sourceType?: 'system' | '';
  sourceKey?: string;
}

interface Feedback {
  id: string;
  placeId: string;
  userId: string;
  message: string;
  createdAt: number;
}

interface Message {
  id: string;
  userId: string;
  message: string;
  createdAt: number;
  placeId?: string;
  type?: 'manual' | 'approve' | 'reject' | 'delete' | 'feedback';
}

interface SystemOverride {
  sourceKey: string;
  name?: string;
  description?: string;
  imageUrl?: string;
  updatedAt: number;
}

interface MailRequest {
  to: string;
}

interface VerificationCode {
  id: string;
  userId: string;
  code: string;
  createdAt: number;
  expiresAt: number;
  email?: string;
  purpose?: 'bind' | 'reset';
}

interface DbData {
  users: User[];
  places: Place[];
  feedback: Feedback[];
  tokens: Record<string, string>;
  systemOverrides: SystemOverride[];
  messages: Message[];
  verificationCodes: VerificationCode[];
  userPlaceStates: UserPlaceState[];
}

const DB_PATH = fileURLToPath(new URL('../data/db.sqlite', import.meta.url));
const LEGACY_DB_PATH = fileURLToPath(new URL('../data/db.json', import.meta.url));
let dbInstance: Database.Database | null = null;
const PORT = 8080;
const UPLOAD_DIR = fileURLToPath(new URL('../data/uploads', import.meta.url));
const IMAGE_MIME_TO_EXT: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif'
};
const IMAGE_EXT_TO_MIME: Record<string, string> = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  gif: 'image/gif'
};
const MAX_IMAGE_SIZE = 10 * 1024 * 1024;

const MAX_MESSAGES_PER_USER = 200;

const MAIL_TRANSPORTER = nodemailer.createTransport({
  host: 'smtp.126.com',
  port: 465,
  secure: true,
  auth: {
    user: 'ygshgzhy@126.com',
    pass: 'FNwv3yUamYNBM3Mn'
  }
});

function ensureUploadDir(): void {
  if (!existsSync(UPLOAD_DIR)) {
    mkdirSync(UPLOAD_DIR, { recursive: true });
  }
}

function buildBaseUrl(req: http.IncomingMessage): string {
  const protoHeader = (req.headers['x-forwarded-proto'] || '') as string;
  const protocol = protoHeader || 'http';
  const host = req.headers.host || `localhost:${PORT}`;
  return `${protocol}://${host}`;
}

function resolveImageExtension(contentType: string, fileNameHint?: string): string {
  const normalized = contentType.split(';')[0].trim().toLowerCase();
  if (IMAGE_MIME_TO_EXT[normalized]) {
    return IMAGE_MIME_TO_EXT[normalized];
  }
  const hintExt = extname(fileNameHint || '').replace('.', '').toLowerCase();
  if (hintExt && IMAGE_EXT_TO_MIME[hintExt]) {
    return hintExt;
  }
  return '';
}

async function readBuffer(req: http.IncomingMessage): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

function saveImageBuffer(params: { buffer: Buffer; req: http.IncomingMessage; contentType: string; fileNameHint?: string }): { id: string; url: string; fileName: string } {
  if (params.buffer.length === 0) {
    throw new Error('Empty file');
  }
  if (params.buffer.length > MAX_IMAGE_SIZE) {
    throw new Error('File too large');
  }
  const ext = resolveImageExtension(params.contentType, params.fileNameHint);
  if (!ext) {
    throw new Error('Unsupported image type');
  }
  ensureUploadDir();
  const id = randomUUID();
  const fileName = `${id}.${ext}`;
  const filePath = join(UPLOAD_DIR, fileName);
  writeFileSync(filePath, params.buffer);
  const url = `${buildBaseUrl(params.req)}/images/${fileName}`;
  return { id, url, fileName };
}

function parseJson<T>(value: string | null | undefined, fallback: T): T {
  if (!value) return fallback;
  try {
    return JSON.parse(value) as T;
  } catch {
    return fallback;
  }
}

function normalizeLegacyDb(raw: string): DbData {
  const legacy = JSON.parse(raw) as Partial<Omit<DbData, 'verificationCodes' | 'messages'>> & {
    verificationCodes?: Array<{ account?: string; email?: string; code?: string; expiresAt?: number }>;
    messages?: Message[];
  };
  const users = (legacy.users || []).map((user) => ({
    id: user.id,
    username: user.username,
    password: user.password,
    isAdmin: user.isAdmin,
    hiddenPlaceIds: user.hiddenPlaceIds || [],
    createdAt: user.createdAt
  }));
  const usersByName = new Map(users.map((user) => [user.username, user]));
  const now = Date.now();
  const userPlaceStates: UserPlaceState[] = [];
  users.forEach((user) => {
    (user.hiddenPlaceIds || []).forEach((placeId) => {
      userPlaceStates.push({
        userId: user.id,
        placeId,
        hidden: true,
        favorite: false,
        updatedAt: now
      });
    });
  });
  const verificationCodes: VerificationCode[] = [];
  (legacy.verificationCodes || []).forEach((entry) => {
    const account = String(entry.account || '').trim();
    const code = String(entry.code || '').trim();
    const expiresAt = Number(entry.expiresAt || 0);
    if (!account || !code || !expiresAt) return;
    let user = usersByName.get(account);
    if (!user) {
      user = {
        id: randomUUID(),
        username: account,
        password: '',
        isAdmin: false,
        hiddenPlaceIds: [],
        createdAt: now
      };
      users.push(user);
      usersByName.set(account, user);
    }
    verificationCodes.push({
      id: randomUUID(),
      userId: user.id,
      code,
      createdAt: now,
      expiresAt
    });
  });
  return {
    users,
    places: legacy.places || [],
    feedback: legacy.feedback || [],
    tokens: legacy.tokens || {},
    systemOverrides: legacy.systemOverrides || [],
    messages: legacy.messages || [],
    verificationCodes
    ,
    userPlaceStates
  };
}

function getDb(): Database.Database {
  if (dbInstance) return dbInstance;
  const db = new Database(DB_PATH);
  db.exec(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      username TEXT NOT NULL,
      password TEXT NOT NULL,
      isAdmin INTEGER NOT NULL,
      email TEXT,
      hiddenPlaceIds TEXT NOT NULL,
      createdAt INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS places (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      lat REAL NOT NULL,
      lon REAL NOT NULL,
      description TEXT NOT NULL,
      imagePath TEXT,
      imageUrl TEXT NOT NULL,
      ownerId TEXT NOT NULL,
      ownerName TEXT NOT NULL,
      status TEXT NOT NULL,
      category TEXT NOT NULL,
      hazardType TEXT NOT NULL,
      votes TEXT NOT NULL,
      voters TEXT NOT NULL,
      createdAt INTEGER NOT NULL,
      updatedAt INTEGER NOT NULL,
      sourcePlaceId TEXT,
      sourceType TEXT,
      sourceKey TEXT
    );
    CREATE TABLE IF NOT EXISTS feedback (
      id TEXT PRIMARY KEY,
      placeId TEXT NOT NULL,
      userId TEXT NOT NULL,
      message TEXT NOT NULL,
      createdAt INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS tokens (
      token TEXT PRIMARY KEY,
      userId TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS system_overrides (
      sourceKey TEXT PRIMARY KEY,
      name TEXT,
      description TEXT,
      imageUrl TEXT,
      updatedAt INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      userId TEXT NOT NULL,
      message TEXT NOT NULL,
      createdAt INTEGER NOT NULL,
      placeId TEXT,
      type TEXT
    );
    CREATE TABLE IF NOT EXISTS verification_codes (
      id TEXT PRIMARY KEY,
      userId TEXT NOT NULL,
      code TEXT NOT NULL,
      createdAt INTEGER NOT NULL,
      expiresAt INTEGER NOT NULL,
      email TEXT,
      purpose TEXT
    );
    CREATE TABLE IF NOT EXISTS user_place_state (
      userId TEXT NOT NULL,
      placeId TEXT NOT NULL,
      hidden INTEGER NOT NULL DEFAULT 0,
      favorite INTEGER NOT NULL DEFAULT 0,
      updatedAt INTEGER NOT NULL,
      PRIMARY KEY (userId, placeId)
    );
  `);
  const messageColumns = db.prepare('PRAGMA table_info(messages)').all() as Array<{ name: string }>;
  const messageColumnNames = new Set(messageColumns.map((col) => col.name));
  if (!messageColumnNames.has('placeId')) {
    db.exec('ALTER TABLE messages ADD COLUMN placeId TEXT');
  }
  if (!messageColumnNames.has('type')) {
    db.exec('ALTER TABLE messages ADD COLUMN type TEXT');
  }
  const userColumns = db.prepare('PRAGMA table_info(users)').all() as Array<{ name: string }>;
  const userColumnNames = new Set(userColumns.map((col) => col.name));
  if (!userColumnNames.has('email')) {
    db.exec('ALTER TABLE users ADD COLUMN email TEXT');
  }

  const placeColumns = db.prepare('PRAGMA table_info(places)').all() as Array<{ name: string }>;
  const placeColumnNames = new Set(placeColumns.map((col) => col.name));
  if (!placeColumnNames.has('imagePath')) {
    db.exec('ALTER TABLE places ADD COLUMN imagePath TEXT');
  }
  const codeColumns = db.prepare('PRAGMA table_info(verification_codes)').all() as Array<{ name: string }>;
  const codeColumnNames = new Set(codeColumns.map((col) => col.name));
  if (!codeColumnNames.has('email')) {
    db.exec('ALTER TABLE verification_codes ADD COLUMN email TEXT');
  }
  if (!codeColumnNames.has('purpose')) {
    db.exec('ALTER TABLE verification_codes ADD COLUMN purpose TEXT');
  }
  const userCount = (db.prepare('SELECT COUNT(*) as count FROM users').get() as { count: number }).count;
  if (userCount === 0 && existsSync(LEGACY_DB_PATH)) {
    const raw = readFileSync(LEGACY_DB_PATH, 'utf-8');
    const legacy = normalizeLegacyDb(raw);
    writeDb(legacy, db);
  }
  dbInstance = db;
  return db;
}

function readDb(): DbData {
  const db = getDb();
  const users = db.prepare('SELECT * FROM users').all() as Array<Record<string, unknown>>;
  const places = db.prepare('SELECT * FROM places').all() as Array<Record<string, unknown>>;
  const feedback = db.prepare('SELECT * FROM feedback').all() as Array<Record<string, unknown>>;
  const tokensRows = db.prepare('SELECT * FROM tokens').all() as Array<Record<string, unknown>>;
  const overrides = db.prepare('SELECT * FROM system_overrides').all() as Array<Record<string, unknown>>;
  const messages = db.prepare('SELECT * FROM messages').all() as Array<Record<string, unknown>>;
  const codes = db.prepare('SELECT * FROM verification_codes').all() as Array<Record<string, unknown>>;
  const placeStates = db.prepare('SELECT * FROM user_place_state').all() as Array<Record<string, unknown>>;
  return {
    users: users.map((row) => ({
      id: String(row.id),
      username: String(row.username),
      password: String(row.password),
      isAdmin: Boolean(row.isAdmin),
      email: row.email ? String(row.email) : '',
      hiddenPlaceIds: parseJson(String(row.hiddenPlaceIds || ''), [] as string[]),
      createdAt: Number(row.createdAt)
    })),
    places: places.map((row) => ({
      id: String(row.id),
      name: String(row.name),
      lat: Number(row.lat),
      lon: Number(row.lon),
      description: String(row.description || ''),
      imagePath: row.imagePath ? String(row.imagePath) : undefined,
      imageUrl: String(row.imageUrl || ''),
      ownerId: String(row.ownerId),
      ownerName: String(row.ownerName),
      status: row.status as Place['status'],
      category: row.category as Place['category'],
      hazardType: row.hazardType as Place['hazardType'],
      votes: parseJson(String(row.votes || ''), { up: 0, down: 0 } as PlaceVotes),
      voters: parseJson(String(row.voters || ''), {} as Record<string, number>),
      createdAt: Number(row.createdAt),
      updatedAt: Number(row.updatedAt),
      sourcePlaceId: row.sourcePlaceId ? String(row.sourcePlaceId) : undefined,
      sourceType: row.sourceType ? String(row.sourceType) as 'system' : undefined,
      sourceKey: row.sourceKey ? String(row.sourceKey) : undefined
    })),
    feedback: feedback.map((row) => ({
      id: String(row.id),
      placeId: String(row.placeId),
      userId: String(row.userId),
      message: String(row.message),
      createdAt: Number(row.createdAt)
    })),
    messages: messages.map((row) => ({
      id: String(row.id),
      userId: String(row.userId),
      message: String(row.message),
      createdAt: Number(row.createdAt),
      placeId: row.placeId ? String(row.placeId) : undefined,
      type: row.type ? (String(row.type) as Message['type']) : undefined
    })),
    verificationCodes: codes.map((row) => ({
      id: String(row.id),
      userId: String(row.userId),
      code: String(row.code),
      createdAt: Number(row.createdAt),
      expiresAt: Number(row.expiresAt),
      email: row.email ? String(row.email) : undefined,
      purpose: row.purpose ? (String(row.purpose) as VerificationCode['purpose']) : undefined
    })),
    tokens: tokensRows.reduce<Record<string, string>>((acc, row) => {
      acc[String(row.token)] = String(row.userId);
      return acc;
    }, {}),
    systemOverrides: overrides.map((row) => ({
      sourceKey: String(row.sourceKey),
      name: row.name ? String(row.name) : undefined,
      description: row.description ? String(row.description) : undefined,
      imageUrl: row.imageUrl ? String(row.imageUrl) : undefined,
      updatedAt: Number(row.updatedAt)
    })),
    userPlaceStates: placeStates.map((row) => ({
      userId: String(row.userId),
      placeId: String(row.placeId),
      hidden: Boolean(row.hidden),
      favorite: Boolean(row.favorite),
      updatedAt: Number(row.updatedAt)
    }))
  };
}

function writeDb(data: DbData, dbInstanceOverride?: Database.Database): void {
  const db = dbInstanceOverride || getDb();
  const transaction = db.transaction(() => {
    db.exec('DELETE FROM users; DELETE FROM places; DELETE FROM feedback; DELETE FROM tokens; DELETE FROM system_overrides; DELETE FROM messages; DELETE FROM verification_codes; DELETE FROM user_place_state;');
    const insertUser = db.prepare('INSERT INTO users (id, username, password, isAdmin, email, hiddenPlaceIds, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?)');
    data.users.forEach((user) => {
      insertUser.run(
        user.id,
        user.username,
        user.password,
        user.isAdmin ? 1 : 0,
        user.email || null,
        JSON.stringify(user.hiddenPlaceIds || []),
        user.createdAt
      );
    });
    const insertPlace = db.prepare(`
      INSERT INTO places (
        id, name, lat, lon, description, imagePath, imageUrl, ownerId, ownerName, status, category, hazardType,
        votes, voters, createdAt, updatedAt, sourcePlaceId, sourceType, sourceKey
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    data.places.forEach((place) => {
      insertPlace.run(
        place.id,
        place.name,
        place.lat,
        place.lon,
        place.description || '',
        place.imagePath || null,
        place.imageUrl || '',
        place.ownerId,
        place.ownerName,
        place.status,
        place.category,
        place.hazardType,
        JSON.stringify(place.votes || { up: 0, down: 0 }),
        JSON.stringify(place.voters || {}),
        place.createdAt,
        place.updatedAt,
        place.sourcePlaceId || null,
        place.sourceType || null,
        place.sourceKey || null
      );
    });
    const insertFeedback = db.prepare('INSERT INTO feedback (id, placeId, userId, message, createdAt) VALUES (?, ?, ?, ?, ?)');
    data.feedback.forEach((entry) => {
      insertFeedback.run(entry.id, entry.placeId, entry.userId, entry.message, entry.createdAt);
    });
    const insertMessage = db.prepare('INSERT INTO messages (id, userId, message, createdAt, placeId, type) VALUES (?, ?, ?, ?, ?, ?)');
    data.messages.forEach((entry) => {
      insertMessage.run(entry.id, entry.userId, entry.message, entry.createdAt, entry.placeId || null, entry.type || null);
    });
    const insertCode = db.prepare('INSERT INTO verification_codes (id, userId, code, createdAt, expiresAt, email, purpose) VALUES (?, ?, ?, ?, ?, ?, ?)');
    data.verificationCodes.forEach((entry) => {
      insertCode.run(entry.id, entry.userId, entry.code, entry.createdAt, entry.expiresAt, entry.email || null, entry.purpose || null);
    });
    const insertToken = db.prepare('INSERT INTO tokens (token, userId) VALUES (?, ?)');
    Object.entries(data.tokens).forEach(([token, userId]) => {
      insertToken.run(token, userId);
    });
    const insertOverride = db.prepare('INSERT INTO system_overrides (sourceKey, name, description, imageUrl, updatedAt) VALUES (?, ?, ?, ?, ?)');
    data.systemOverrides.forEach((override) => {
      insertOverride.run(override.sourceKey, override.name || null, override.description || null, override.imageUrl || null, override.updatedAt);
    });

    const insertPlaceState = db.prepare('INSERT INTO user_place_state (userId, placeId, hidden, favorite, updatedAt) VALUES (?, ?, ?, ?, ?)');
    (data.userPlaceStates || []).forEach((entry) => {
      insertPlaceState.run(entry.userId, entry.placeId, entry.hidden ? 1 : 0, entry.favorite ? 1 : 0, entry.updatedAt);
    });
  });
  transaction();
}

async function readBody(req: http.IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    chunks.push(Buffer.from(chunk));
  }
  if (chunks.length === 0) {
    return {};
  }
  const text = Buffer.concat(chunks).toString('utf-8');
  return JSON.parse(text) as Record<string, unknown>;
}

function json(res: http.ServerResponse, status: number, payload: Record<string, unknown>): void {
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
  });
  res.end(JSON.stringify(payload));
}

function getToken(req: http.IncomingMessage): string {
  const auth = req.headers.authorization || '';
  if (auth.startsWith('Bearer ')) {
    return auth.slice(7);
  }
  return '';
}

function requireAuth(db: DbData, req: http.IncomingMessage, res: http.ServerResponse): User | null {
  const token = getToken(req);
  const userId = token ? db.tokens[token] : '';
  const user = db.users.find((u) => u.id === userId) || null;
  if (!user) {
    json(res, 401, { error: 'Unauthorized' });
    return null;
  }
  return user;
}

function ensureAdmin(user: User, res: http.ServerResponse): boolean {
  if (!user.isAdmin) {
    json(res, 403, { error: 'Admin only' });
    return false;
  }
  return true;
}

function resolvePlaceImageUrl(place: Place, baseUrl: string): string {
  if (place.imagePath) {
    return `${baseUrl}/images/${place.imagePath}`;
  }
  return place.imageUrl || '';
}

function toPlaceResponse(place: Place, baseUrl: string): Record<string, unknown> {
  return {
    id: place.id,
    name: place.name,
    lat: place.lat,
    lon: place.lon,
    description: place.description,
    imagePath: place.imagePath || '',
    imageUrl: resolvePlaceImageUrl(place, baseUrl),
    ownerId: place.ownerId,
    ownerName: place.ownerName,
    status: place.status,
    category: place.category,
    hazardType: place.hazardType,
    votes: place.votes,
    createdAt: place.createdAt,
    updatedAt: place.updatedAt,
    sourcePlaceId: place.sourcePlaceId || '',
    sourceType: place.sourceType || '',
    sourceKey: place.sourceKey || ''
  };
}

function buildPlaceFromBody(body: Record<string, unknown>, owner: User, statusOverride?: Place['status']): Place {
  const now = Date.now();
  const name = String(body.name || '').trim();
  const lat = Number(body.lat || 0);
  const lon = Number(body.lon || 0);
  const description = String(body.description || '');
  const imagePath = body.imagePath ? String(body.imagePath || '').trim() : '';
  const imageUrl = String(body.imageUrl || '');
  const category = (body.category === 'hazard' ? 'hazard' : 'normal') as Place['category'];
  const hazardTypeRaw = category === 'hazard' ? String(body.hazardType || '') : '';
  const hazardType = (hazardTypeRaw === 'water' || hazardTypeRaw === 'slippery' || hazardTypeRaw === 'danger') ? hazardTypeRaw : '';
  const statusBody = String(body.status || 'private') as Place['status'];
  const status = statusOverride || statusBody;
  return {
    id: randomUUID(),
    name,
    lat,
    lon,
    description,
    imagePath: imagePath || undefined,
    imageUrl,
    ownerId: owner.id,
    ownerName: owner.username,
    status,
    category,
    hazardType,
    votes: { up: 0, down: 0 },
    voters: {},
    createdAt: now,
    updatedAt: now,
    sourcePlaceId: body.sourcePlaceId ? String(body.sourcePlaceId) : undefined,
    sourceType: body.sourceType === 'system' ? 'system' : undefined,
    sourceKey: body.sourceKey ? String(body.sourceKey) : undefined
  };
}

function updatePlaceFromBody(place: Place, body: Record<string, unknown>, user: User): void {
  place.name = String(body.name || place.name);
  place.description = String(body.description || place.description || '');
  if (typeof body.imagePath === 'string') {
    const nextPath = body.imagePath.trim();
    place.imagePath = nextPath ? nextPath : undefined;
  }
  if (typeof body.imageUrl === 'string') {
    place.imageUrl = body.imageUrl;
  } else {
    place.imageUrl = String(place.imageUrl || '');
  }
  place.lat = Number(body.lat || place.lat);
  place.lon = Number(body.lon || place.lon);
  const category = body.category === 'hazard' ? 'hazard' : 'normal';
  place.category = category;
  if (category === 'hazard') {
    const hazardTypeRaw = String(body.hazardType || place.hazardType || '');
    place.hazardType = (hazardTypeRaw === 'water' || hazardTypeRaw === 'slippery' || hazardTypeRaw === 'danger') ? hazardTypeRaw : '';
  } else {
    place.hazardType = '';
  }
  if (user.isAdmin && body.status) {
    place.status = body.status as Place['status'];
  } else if (body.status === 'approved') {
    place.status = 'pending';
  }
  place.updatedAt = Date.now();
}

function setUserPlaceState(
  db: DbData,
  userId: string,
  placeId: string,
  patch: { hidden?: boolean; favorite?: boolean }
): void {
  db.userPlaceStates = db.userPlaceStates || [];
  const index = db.userPlaceStates.findIndex((entry) => entry.userId === userId && entry.placeId === placeId);
  const prev = index >= 0 ? db.userPlaceStates[index] : null;
  const next: UserPlaceState = {
    userId,
    placeId,
    hidden: patch.hidden ?? prev?.hidden ?? false,
    favorite: patch.favorite ?? prev?.favorite ?? false,
    updatedAt: Date.now()
  };
  if (!next.hidden && !next.favorite) {
    if (index >= 0) db.userPlaceStates.splice(index, 1);
    return;
  }
  if (index >= 0) {
    db.userPlaceStates[index] = next;
  } else {
    db.userPlaceStates.push(next);
  }
}

function getUserPlaceStates(db: DbData, userId: string): UserPlaceState[] {
  return (db.userPlaceStates || []).filter((entry) => entry.userId === userId);
}

function pruneMessagesForUser(db: DbData, userId: string, max: number): void {
  const messages = (db.messages || []).filter((entry) => entry.userId === userId);
  if (messages.length <= max) return;
  const sorted = messages.sort((a, b) => b.createdAt - a.createdAt);
  const keepIds = new Set(sorted.slice(0, max).map((entry) => entry.id));
  db.messages = (db.messages || []).filter((entry) => entry.userId !== userId || keepIds.has(entry.id));
}

async function sendHelloMail(to: string): Promise<void> {
  await MAIL_TRANSPORTER.sendMail({
    from: 'ygshgzhy@126.com',
    to,
    subject: 'Hello',
    text: 'hello'
  });
}

function pruneVerificationCodes(db: DbData): void {
  const now = Date.now();
  db.verificationCodes = (db.verificationCodes || []).filter((entry) => entry.expiresAt > now);
  // Remove placeholder users (empty password) after 5 minutes.
  // These accounts exist only during the pre-registration window and must never be permanent.
  const cutoff = now - 5 * 60 * 1000;
  db.users = (db.users || []).filter((u) => {
    if (u.isAdmin) return true;
    if (u.password !== '') return true;
    return Number(u.createdAt || 0) >= cutoff;
  });
}

function generateVerificationCode(): string {
  return String(Math.floor(100000 + Math.random() * 900000));
}

async function sendVerificationMail(to: string, code: string): Promise<void> {
  await MAIL_TRANSPORTER.sendMail({
    from: 'ygshgzhy@126.com',
    to,
    subject: 'Verification Code',
    text: `Your verification code is ${code}. It expires in 5 minutes.`
  });
}

function removeSystemMessagesForPlace(db: DbData, data: { userId: string; placeId: string; placeName: string }): void {
  const nameToken = `“${data.placeName}”`;
  db.messages = db.messages.filter((entry) => {
    if (entry.userId !== data.userId) return true;
    if (entry.placeId && entry.placeId !== data.placeId) return true;
    if (entry.placeId && entry.placeId === data.placeId) {
      return entry.type === 'delete' || entry.type === 'manual';
    }
    const isSystemText = entry.message.includes('通过审核') || entry.message.includes('未通过审核') || entry.message.includes('管理员删除');
    if (!isSystemText) return true;
    return !entry.message.includes(nameToken);
  });
}

function addMessage(db: DbData, data: { userId: string; message: string; placeId?: string; type?: Message['type']; id?: string; createdAt?: number }): void {
  const type = data.type || 'manual';
  const placeId = data.placeId;
  const message = data.message;
  if (type !== 'manual') {
    const exists = db.messages.some((entry) => {
      if (entry.userId !== data.userId) return false;
      if (placeId && entry.placeId === placeId && entry.type === type) return true;
      return entry.message === message;
    });
    if (exists) return;
  }
  db.messages.push({
    id: data.id || randomUUID(),
    userId: data.userId,
    message,
    createdAt: data.createdAt ?? Date.now(),
    placeId,
    type
  });
  pruneMessagesForUser(db, data.userId, MAX_MESSAGES_PER_USER);
}

ensureUploadDir();

const server = http.createServer(async (req: http.IncomingMessage, res: http.ServerResponse) => {
  const url = new URL(req.url || '/', 'http://localhost');
  const path = url.pathname;
  const method = req.method || 'GET';
  const db = readDb();

  if (method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    });
    res.end();
    return;
  }

  try {
    if (path.startsWith('/images/') && method === 'GET') {
      const fileName = path.slice('/images/'.length);
      if (!fileName || fileName.includes('..')) {
        res.writeHead(400, { 'Content-Type': 'text/plain', 'Access-Control-Allow-Origin': '*' });
        res.end('Bad Request');
        return;
      }
      const filePath = join(UPLOAD_DIR, fileName);
      if (!existsSync(filePath)) {
        res.writeHead(404, { 'Content-Type': 'text/plain', 'Access-Control-Allow-Origin': '*' });
        res.end('Not Found');
        return;
      }
      const ext = fileName.split('.').pop()?.toLowerCase() || '';
      const contentType = IMAGE_EXT_TO_MIME[ext] || 'application/octet-stream';
      res.writeHead(200, { 'Content-Type': contentType, 'Access-Control-Allow-Origin': '*' });
      createReadStream(filePath).pipe(res);
      return;
    }

    if (path === '/api/health') {
      return json(res, 200, { status: 'ok' });
    }

    if (path === '/api/register' && method === 'POST') {
      const body = await readBody(req);
      const username = String(body.username || '').trim();
      const password = String(body.password || '').trim();
      if (!username || !password) {
        return json(res, 400, { error: 'Invalid credentials' });
      }
      const existing = db.users.find((u) => u.username === username) || null;
      let user: User;
      if (existing) {
        // If a placeholder user exists (empty password), allow completing registration
        if (existing.password === '') {
          existing.password = password;
          existing.createdAt = existing.createdAt || Date.now();
          user = existing;
        } else {
          return json(res, 400, { error: 'User exists' });
        }
      } else {
        user = {
          id: randomUUID(),
          username,
          password,
          isAdmin: false,
          hiddenPlaceIds: [],
          createdAt: Date.now()
        };
        db.users.push(user);
      }
      const token = randomUUID();
      db.tokens[token] = user.id;
      writeDb(db);
      return json(res, 200, { token, user: { id: user.id, username: user.username, isAdmin: user.isAdmin, email: user.email } });
    }

    if (path === '/api/email/send' && method === 'POST') {
      const body = await readBody(req);
      const username = String(body.username || '').trim();
      const email = String(body.email || '').trim();
      const purpose = body.purpose === 'reset' ? 'reset' : 'bind';
      if (!username || !email) {
        return json(res, 400, { error: 'Username and email required' });
      }
      const user = db.users.find((u) => u.username === username) || null;
      if (!user) {
        return json(res, 404, { error: 'User not found' });
      }
      if (purpose === 'reset') {
        if (!user.email) {
          return json(res, 400, { error: 'No email bound to this account' });
        }
        if (user.email !== email) {
          return json(res, 400, { error: 'Provided email does not match the bound email' });
        }
      } else {
        if (user.email && user.email !== email) {
          return json(res, 400, { error: 'Account already bound to a different email' });
        }
      }
      pruneVerificationCodes(db);
      const code = generateVerificationCode();
      const now = Date.now();
      const expiresAt = now + 5 * 60 * 1000;
      db.verificationCodes = db.verificationCodes || [];
      db.verificationCodes.push({ id: randomUUID(), userId: user.id, code, createdAt: now, expiresAt, email, purpose });
      writeDb(db);
      try {
        await sendVerificationMail(email, code);
        return json(res, 200, { ok: true, code });
      } catch (error) {
        return json(res, 500, { error: `Failed to send mail: ${String(error)}` });
      }
    }

    if (path === '/api/email/bind' && method === 'POST') {
      const body = await readBody(req);
      const username = String(body.username || '').trim();
      const email = String(body.email || '').trim();
      const code = String(body.code || '').trim();
      if (!username || !email || !code) {
        return json(res, 400, { error: 'Username, email and code required' });
      }
      const user = db.users.find((u) => u.username === username) || null;
      if (!user) {
        return json(res, 404, { error: 'User not found' });
      }
      pruneVerificationCodes(db);
      const matchIndex = db.verificationCodes.findIndex(
        (entry) => entry.userId === user.id && entry.code === code && entry.purpose === 'bind' && entry.email === email
      );
      if (matchIndex === -1) {
        return json(res, 400, { error: 'Invalid or expired code' });
      }
      user.email = email;
      db.verificationCodes.splice(matchIndex, 1);
      writeDb(db);
      return json(res, 200, { ok: true });
    }

    if (path === '/api/password/reset' && method === 'POST') {
      const body = await readBody(req);
      const username = String(body.username || '').trim();
      const code = String(body.code || '').trim();
      const newPassword = String(body.newPassword || '').trim();
      if (!username || !code || !newPassword) {
        return json(res, 400, { error: 'Username, code and newPassword required' });
      }
      const user = db.users.find((u) => u.username === username) || null;
      if (!user) {
        return json(res, 404, { error: 'User not found' });
      }
      if (!user.email) {
        return json(res, 400, { error: 'Email not bound to this account' });
      }
      pruneVerificationCodes(db);
      const matchIndex = db.verificationCodes.findIndex(
        (entry) => entry.userId === user.id && entry.code === code && entry.purpose === 'reset' && entry.email === user.email
      );
      if (matchIndex === -1) {
        return json(res, 400, { error: 'Invalid or expired code' });
      }
      user.password = newPassword;
      db.verificationCodes.splice(matchIndex, 1);
      writeDb(db);
      return json(res, 200, { ok: true });
    }

    if (path === '/api/login' && method === 'POST') {
      const body = await readBody(req);
      const username = String(body.username || '').trim();
      const password = String(body.password || '').trim();
      const user = db.users.find((u) => u.username === username) || null;
      if (!user || user.password === '' || user.password !== password) {
        return json(res, 401, { error: 'Invalid credentials' });
      }
      const token = randomUUID();
      db.tokens[token] = user.id;
      writeDb(db);
      return json(res, 200, { token, user: { id: user.id, username: user.username, isAdmin: user.isAdmin, email: user.email } });
    }

    // Simple users API for frontend to list/create users directly (development use)
    if (path === '/api/users' && method === 'GET') {
      const users = db.users.map((u) => ({ id: u.id, username: u.username, isAdmin: u.isAdmin }));
      return json(res, 200, { users });
    }

    if (path === '/api/users' && method === 'POST') {
      const body = await readBody(req);
      const username = String(body.username || '').trim();
      const password = String(body.password || '').trim();
      if (!username || !password) {
        return json(res, 400, { error: 'Invalid credentials' });
      }
      if (db.users.some((u) => u.username === username)) {
        return json(res, 400, { error: 'User exists' });
      }
      const user: User = {
        id: randomUUID(),
        username,
        password,
        isAdmin: false,
        hiddenPlaceIds: [],
        createdAt: Date.now()
      };
      db.users.push(user);
      writeDb(db);
      return json(res, 200, { user: { id: user.id, username: user.username, isAdmin: user.isAdmin } });
    }

    // Pre-register: create a temporary placeholder user and generate verification code
    if (path === '/api/pre-register' && method === 'POST') {
      const body = await readBody(req);
      const account = String(body.username || '').trim();
      if (!account) {
        return json(res, 400, { error: 'username required' });
      }

      // Important: prune *before* creating/finding placeholder user.
      // Our prune function also removes placeholder users that have no active codes,
      // so calling it after creating a placeholder (but before inserting a new code)
      // would delete the user we just created.
      pruneVerificationCodes(db);

      let user = db.users.find((u) => u.username === account) || null;
      if (user) {
        if (user.password !== '') {
          return json(res, 400, { error: 'User exists' });
        }
        // existing placeholder: allow resending code
      } else {
        user = {
          id: randomUUID(),
          username: account,
          password: '',
          isAdmin: false,
          hiddenPlaceIds: [],
          createdAt: Date.now()
        };
        db.users.push(user);
      }
      const code = generateVerificationCode();
      const now = Date.now();
      const expiresAt = now + 5 * 60 * 1000;
      db.verificationCodes = db.verificationCodes || [];
      db.verificationCodes.push({ id: randomUUID(), userId: user.id, code, createdAt: now, expiresAt });
      writeDb(db);
      // Do not send email here; frontend handles email verification. Return code for development.
      return json(res, 200, { ok: true, code });
    }

    if (path === '/api/send-code' && method === 'POST') {
      const body = await readBody(req);
      const username = String(body.username || '').trim();
      const user = db.users.find((u) => u.username === username) || null;
      if (!user) {
        return json(res, 404, { error: 'User not found' });
      }
      const code = generateVerificationCode();
      const now = Date.now();
      const expiresAt = now + 5 * 60 * 1000;
      db.verificationCodes = db.verificationCodes || [];
      db.verificationCodes.push({ id: randomUUID(), userId: user.id, code, createdAt: now, expiresAt });
      writeDb(db);
      return json(res, 200, { ok: true, code });
    }

    if (path === '/api/login-code' && method === 'POST') {
      const body = await readBody(req);
      const username = String(body.username || '').trim();
      const code = String(body.code || '').trim();
      const user = db.users.find((u) => u.username === username) || null;
      if (!user) {
        return json(res, 404, { error: 'User not found' });
      }
      pruneVerificationCodes(db);
      const matchIndex = db.verificationCodes.findIndex((entry) => entry.userId === user.id && entry.code === code);
      if (matchIndex === -1) {
        return json(res, 401, { error: 'Invalid credentials' });
      }
      db.verificationCodes.splice(matchIndex, 1);
      writeDb(db);

      // Placeholder users (created via pre-register with empty password) are not allowed to log in.
      // Verification only confirms code ownership; the user must still complete registration.
      if (user.password === '') {
        return json(res, 200, { ok: true });
      }

      const token = randomUUID();
      db.tokens[token] = user.id;
      writeDb(db);
      return json(res, 200, { token, user: { id: user.id, username: user.username, isAdmin: user.isAdmin } });
    }

    if (path === '/api/me' && method === 'GET') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      return json(res, 200, { user: { id: user.id, username: user.username, isAdmin: user.isAdmin } });
    }

    if (path === '/api/images' && method === 'POST') {
      const buffer = await readBuffer(req);
      const contentType = typeof req.headers['content-type'] === 'string' ? req.headers['content-type'] : '';
      const fileNameHint = (req.headers['x-file-name'] as string) || url.searchParams.get('filename') || '';
      try {
        const result = saveImageBuffer({ buffer, req, contentType, fileNameHint });
        return json(res, 200, { id: result.id, url: result.url, fileName: result.fileName });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        const status = message === 'Empty file' || message === 'Unsupported image type' || message === 'File too large' ? 400 : 500;
        return json(res, status, { error: message });
      }
    }

    if (path === '/api/images/from-path' && method === 'POST') {
      const body = await readBody(req);
      const sourcePath = typeof body.path === 'string' ? body.path.trim() : '';
      const contentTypeHint = typeof body.contentType === 'string' ? body.contentType : '';
      const fileNameHint = typeof body.fileName === 'string' ? body.fileName : sourcePath;
      if (!sourcePath) {
        return json(res, 400, { error: 'path required' });
      }
      if (!existsSync(sourcePath)) {
        return json(res, 404, { error: 'File not found' });
      }
      const buffer = readFileSync(sourcePath);
      try {
        const result = saveImageBuffer({ buffer, req, contentType: contentTypeHint, fileNameHint });
        return json(res, 200, { id: result.id, url: result.url, fileName: result.fileName });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        const status = message === 'Empty file' || message === 'Unsupported image type' || message === 'File too large' ? 400 : 500;
        return json(res, status, { error: message });
      }
    }

    if (path === '/api/system-overrides' && method === 'GET') {
      return json(res, 200, { overrides: db.systemOverrides || [] });
    }

    if (path === '/api/places' && method === 'GET') {
      const baseUrl = buildBaseUrl(req);
      const scope = url.searchParams.get('scope') || 'public';
      if (scope === 'public') {
        const approved = db.places.filter((p) => p.status === 'approved');
        const hazards = approved.filter((p) => p.category === 'hazard');
        const places = approved.filter((p) => p.category !== 'hazard');
        return json(res, 200, {
          places: places.map((place) => toPlaceResponse(place, baseUrl)),
          hazards: hazards.map((place) => toPlaceResponse(place, baseUrl))
        });
      }

      const user = requireAuth(db, req, res);
      if (!user) return;

      if (scope === 'mine') {
        const mine = db.places.filter((p) => p.ownerId === user.id);
        const pending = mine.filter((p) => p.status === 'pending');
        const others = mine.filter((p) => p.status !== 'pending');
        return json(res, 200, {
          places: others.map((place) => toPlaceResponse(place, baseUrl)),
          pending: pending.map((place) => toPlaceResponse(place, baseUrl))
        });
      }

      if (scope === 'pending') {
        if (!ensureAdmin(user, res)) return;
        const pending = db.places.filter((p) => p.status === 'pending');
        return json(res, 200, { pending: pending.map((place) => toPlaceResponse(place, baseUrl)) });
      }
    }

    if (path === '/api/places' && method === 'POST') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      const baseUrl = buildBaseUrl(req);
      const body = await readBody(req);
      const status = user.isAdmin && body.status === 'approved' ? 'approved' : (body.status === 'pending' ? 'pending' : 'private');

      // Admin bulk upload: upsert system places by sourceKey to avoid duplicates.
      const sourceType = body.sourceType === 'system' ? 'system' : '';
      const sourceKey = typeof body.sourceKey === 'string' ? body.sourceKey.trim() : '';
      if (user.isAdmin && sourceType === 'system' && sourceKey) {
        const existing = db.places.find((p) => p.sourceType === 'system' && p.sourceKey === sourceKey);
        if (existing) {
          updatePlaceFromBody(existing, body, user);
          existing.sourceType = 'system';
          existing.sourceKey = sourceKey;
          if (status === 'approved') {
            existing.status = 'approved';
          }
          existing.updatedAt = Date.now();
          writeDb(db);
          return json(res, 200, { place: toPlaceResponse(existing, baseUrl) });
        }
      }
      const place = buildPlaceFromBody(body, user, status);
      if (!place.name) {
        return json(res, 400, { error: 'Name required' });
      }
      db.places.push(place);
      writeDb(db);
      return json(res, 200, { place: toPlaceResponse(place, baseUrl) });
    }

    if (path.startsWith('/api/places/') && method === 'PUT') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      const baseUrl = buildBaseUrl(req);
      const id = path.split('/')[3];
      const place = db.places.find((p) => p.id === id);
      if (!place) {
        return json(res, 404, { error: 'Not found' });
      }
      if (place.ownerId !== user.id && !user.isAdmin) {
        return json(res, 403, { error: 'Forbidden' });
      }
      const body = await readBody(req);

      // If a non-admin edits an approved place, create a pending update request
      // instead of taking the approved place offline.
      if (!user.isAdmin && place.status === 'approved') {
        const requestBody: Record<string, unknown> = {
          ...body,
          status: 'pending',
          sourcePlaceId: place.id,
          sourceType: place.sourceType || '',
          sourceKey: place.sourceKey || ''
        };
        const pending = buildPlaceFromBody(requestBody, user, 'pending');
        pending.sourcePlaceId = place.id;
        pending.sourceType = place.sourceType;
        pending.sourceKey = place.sourceKey;
        db.places.push(pending);
        writeDb(db);
        return json(res, 200, { place: toPlaceResponse(pending, baseUrl) });
      }

      updatePlaceFromBody(place, body, user);
      writeDb(db);
      return json(res, 200, { place: toPlaceResponse(place, baseUrl) });
    }

    if (path.startsWith('/api/places/') && method === 'DELETE') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      const id = path.split('/')[3];
      const index = db.places.findIndex((p) => p.id === id);
      if (index === -1) {
        return json(res, 404, { error: 'Not found' });
      }
      const place = db.places[index];
      if (place.ownerId !== user.id && !user.isAdmin) {
        return json(res, 403, { error: 'Forbidden' });
      }
      if (user.isAdmin && place.ownerId !== user.id) {
        removeSystemMessagesForPlace(db, { userId: place.ownerId, placeId: place.id, placeName: place.name });
        addMessage(db, {
          userId: place.ownerId,
          message: `你的地点“${place.name}”已被管理员删除。`,
          placeId: place.id,
          type: 'delete'
        });
      }
      db.places.splice(index, 1);
      writeDb(db);
      return json(res, 200, { ok: true });
    }

    if (path.endsWith('/publish') && method === 'POST') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      const baseUrl = buildBaseUrl(req);
      const id = path.split('/')[3];
      const place = db.places.find((p) => p.id === id);
      if (!place) {
        return json(res, 404, { error: 'Not found' });
      }
      if (place.ownerId !== user.id && !user.isAdmin) {
        return json(res, 403, { error: 'Forbidden' });
      }
      place.status = 'pending';
      place.updatedAt = Date.now();
      writeDb(db);
      return json(res, 200, { place: toPlaceResponse(place, baseUrl) });
    }

    if (path.endsWith('/vote') && method === 'POST') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      const baseUrl = buildBaseUrl(req);
      const id = path.split('/')[3];
      const place = db.places.find((p) => p.id === id);
      if (!place) {
        return json(res, 404, { error: 'Not found' });
      }
      const body = await readBody(req);
      const value = Number(body.value || 0);
      // value: 1 (up), -1 (down), 0 (cancel)
      if (value !== 1 && value !== -1 && value !== 0) {
        return json(res, 400, { error: 'Invalid vote' });
      }
      const prev = place.voters[user.id] || 0;
      if (prev === value) {
        return json(res, 200, { place: toPlaceResponse(place, baseUrl) });
      }
      if (prev === 1) place.votes.up -= 1;
      if (prev === -1) place.votes.down -= 1;
      if (value === 1) place.votes.up += 1;
      if (value === -1) place.votes.down += 1;
      if (value === 0) {
        delete place.voters[user.id];
      } else {
        place.voters[user.id] = value;
      }
      place.updatedAt = Date.now();
      writeDb(db);
      return json(res, 200, { place: toPlaceResponse(place, baseUrl) });
    }

    if (path.endsWith('/feedback') && method === 'POST') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      const id = path.split('/')[3];
      const place = db.places.find((p) => p.id === id);
      if (!place) {
        return json(res, 404, { error: 'Not found' });
      }
      const body = await readBody(req);
      const message = String(body.message || '').trim();
      if (!message) {
        return json(res, 400, { error: 'Message required' });
      }
      db.feedback.push({
        id: randomUUID(),
        placeId: place.id,
        userId: user.id,
        message,
        createdAt: Date.now()
      });

      // Notify all admins via messages.
      const admins = db.users.filter((u) => u.isAdmin);
      admins.forEach((admin) => {
        addMessage(db, {
          userId: admin.id,
          message: `收到地点“${place.name}”的反馈：${message}`,
          placeId: place.id,
          type: 'feedback'
        });
      });

      writeDb(db);
      return json(res, 200, { ok: true });
    }

    if (path.startsWith('/api/admin/places/') && path.endsWith('/approve') && method === 'POST') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      if (!ensureAdmin(user, res)) return;
      const baseUrl = buildBaseUrl(req);
      const id = path.split('/')[4];
      const place = db.places.find((p) => p.id === id);
      if (!place) {
        return json(res, 404, { error: 'Not found' });
      }

      // Pending update request: apply changes to base place and delete the request.
      if (place.sourcePlaceId) {
        const basePlace = db.places.find((p) => p.id === place.sourcePlaceId);
        if (basePlace) {
          const patch: Record<string, unknown> = {
            name: place.name,
            description: place.description,
            imagePath: place.imagePath || '',
            imageUrl: place.imageUrl,
            lat: place.lat,
            lon: place.lon,
            category: place.category,
            hazardType: place.hazardType,
            status: 'approved'
          };
          updatePlaceFromBody(basePlace, patch, user);
          basePlace.status = 'approved';
          basePlace.updatedAt = Date.now();

          addMessage(db, {
            userId: place.ownerId,
            message: `你提交的修改已通过审核，已应用到地点“${basePlace.name}”。`,
            placeId: basePlace.id,
            type: 'approve'
          });

          // Delete the pending request.
          db.places = db.places.filter((p) => p.id !== place.id);

          if (basePlace.sourceType === 'system' && basePlace.sourceKey) {
            const existing = db.systemOverrides.find((o) => o.sourceKey === basePlace.sourceKey);
            if (existing) {
              existing.name = basePlace.name;
              existing.description = basePlace.description;
              existing.imageUrl = basePlace.imageUrl;
              existing.updatedAt = Date.now();
            } else {
              db.systemOverrides.push({
                sourceKey: basePlace.sourceKey,
                name: basePlace.name,
                description: basePlace.description,
                imageUrl: basePlace.imageUrl,
                updatedAt: Date.now()
              });
            }
          }

          writeDb(db);
          return json(res, 200, { place: toPlaceResponse(basePlace, baseUrl) });
        }
      }

      place.status = 'approved';
      place.updatedAt = Date.now();
      addMessage(db, {
        userId: place.ownerId,
        message: `你的地点“${place.name}”已通过审核。`,
        placeId: place.id,
        type: 'approve'
      });
      if (place.sourceType === 'system' && place.sourceKey) {
        const existing = db.systemOverrides.find((o) => o.sourceKey === place.sourceKey);
        if (existing) {
          existing.name = place.name;
          existing.description = place.description;
          existing.imageUrl = place.imageUrl;
          existing.updatedAt = Date.now();
        } else {
          db.systemOverrides.push({
            sourceKey: place.sourceKey,
            name: place.name,
            description: place.description,
            imageUrl: place.imageUrl,
            updatedAt: Date.now()
          });
        }
      }
      writeDb(db);
      return json(res, 200, { place: toPlaceResponse(place, baseUrl) });
    }

    if (path.startsWith('/api/admin/places/') && path.endsWith('/reject') && method === 'POST') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      if (!ensureAdmin(user, res)) return;
      const baseUrl = buildBaseUrl(req);
      const id = path.split('/')[4];
      const place = db.places.find((p) => p.id === id);
      if (!place) {
        return json(res, 404, { error: 'Not found' });
      }
      place.status = 'rejected';
      place.updatedAt = Date.now();
      addMessage(db, {
        userId: place.ownerId,
        message: `你的地点“${place.name}”未通过审核。`,
        placeId: place.id,
        type: 'reject'
      });
      writeDb(db);
      return json(res, 200, { place: toPlaceResponse(place, baseUrl) });
    }

    if (path === '/api/admin/send-mail' && method === 'POST') {
      const caller = requireAuth(db, req, res);
      if (!caller) return;
      if (!caller.isAdmin) {
        return json(res, 403, { error: 'Admin only' });
      }
      const body = await readBody(req);
      const account = typeof body.account === 'string' ? body.account.trim() : '';
      const email = typeof body.email === 'string' ? body.email.trim() : '';
      if (!account || !email) {
        return json(res, 400, { error: 'Account and email required' });
      }
      const user = db.users.find((u) => u.username === account) || null;
      if (!user) {
        return json(res, 404, { error: 'User not found' });
      }
      pruneVerificationCodes(db);
      const code = generateVerificationCode();
      const expiresAt = Date.now() + 5 * 60 * 1000;
      db.verificationCodes.push({
        id: randomUUID(),
        userId: user.id,
        code,
        createdAt: Date.now(),
        expiresAt,
        email,
        purpose: 'bind'
      });
      writeDb(db);
      try {
        await sendVerificationMail(email, code);
        return json(res, 200, { ok: true, code });
      } catch (error) {
        return json(res, 500, { error: `Failed to send mail: ${String(error)}` });
      }
    }

    if (path === '/api/admin/verify-code' && method === 'POST') {
      const body = await readBody(req);
      const account = typeof body.account === 'string' ? body.account.trim() : '';
      const code = typeof body.code === 'string' ? body.code.trim() : '';
      if (!account || !code) {
        return json(res, 400, { error: 'Account and code required' });
      }
      const user = db.users.find((u) => u.username === account) || null;
      if (!user) {
        return json(res, 400, { error: 'Invalid or expired code' });
      }
      pruneVerificationCodes(db);
      const matchIndex = db.verificationCodes.findIndex((entry) => entry.userId === user.id && entry.code === code);
      if (matchIndex === -1) {
        return json(res, 400, { error: 'Invalid or expired code' });
      }
      db.verificationCodes.splice(matchIndex, 1);
      writeDb(db);
      return json(res, 200, { ok: true });
    }

    if (path === '/api/preferences' && method === 'GET') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      const states = getUserPlaceStates(db, user.id);
      const hidden = states.filter((entry) => entry.hidden).map((entry) => entry.placeId);
      const favorites = states.filter((entry) => entry.favorite).map((entry) => entry.placeId);
      const hiddenPlaceIds = Array.from(new Set([...(user.hiddenPlaceIds || []), ...hidden]));
      const placeStates = states.reduce<Record<string, { hidden: boolean; favorite: boolean; updatedAt: number }>>((acc, entry) => {
        acc[entry.placeId] = { hidden: entry.hidden, favorite: entry.favorite, updatedAt: entry.updatedAt };
        return acc;
      }, {});
      return json(res, 200, { hiddenPlaceIds, favoritePlaceIds: favorites, placeStates });
    }

    if (path === '/api/preferences/hide' && method === 'POST') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      const body = await readBody(req);
      const placeId = String(body.placeId || '');
      const hidden = Boolean(body.hidden);
      if (!placeId) {
        return json(res, 400, { error: 'placeId required' });
      }
      const set = new Set(user.hiddenPlaceIds || []);
      if (hidden) {
        set.add(placeId);
      } else {
        set.delete(placeId);
      }
      user.hiddenPlaceIds = Array.from(set);
      setUserPlaceState(db, user.id, placeId, { hidden });
      writeDb(db);
      return json(res, 200, { hiddenPlaceIds: user.hiddenPlaceIds });
    }

    if (path === '/api/preferences/favorite' && method === 'POST') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      const body = await readBody(req);
      const placeId = String(body.placeId || '');
      const favorite = Boolean(body.favorite);
      if (!placeId) {
        return json(res, 400, { error: 'placeId required' });
      }
      setUserPlaceState(db, user.id, placeId, { favorite });
      writeDb(db);
      const states = getUserPlaceStates(db, user.id);
      const favorites = states.filter((entry) => entry.favorite).map((entry) => entry.placeId);
      return json(res, 200, { favoritePlaceIds: favorites });
    }

    if (path === '/api/preferences/state' && method === 'POST') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      const body = await readBody(req);
      const placeId = String(body.placeId || '');
      if (!placeId) {
        return json(res, 400, { error: 'placeId required' });
      }
      const patch: { hidden?: boolean; favorite?: boolean } = {};
      if (typeof body.hidden === 'boolean') patch.hidden = body.hidden;
      if (typeof body.favorite === 'boolean') patch.favorite = body.favorite;
      if (patch.hidden === undefined && patch.favorite === undefined) {
        return json(res, 400, { error: 'hidden or favorite required' });
      }
      if (patch.hidden !== undefined) {
        const set = new Set(user.hiddenPlaceIds || []);
        if (patch.hidden) set.add(placeId);
        else set.delete(placeId);
        user.hiddenPlaceIds = Array.from(set);
      }
      setUserPlaceState(db, user.id, placeId, patch);
      writeDb(db);
      const states = getUserPlaceStates(db, user.id);
      const placeStates = states.reduce<Record<string, { hidden: boolean; favorite: boolean; updatedAt: number }>>((acc, entry) => {
        acc[entry.placeId] = { hidden: entry.hidden, favorite: entry.favorite, updatedAt: entry.updatedAt };
        return acc;
      }, {});
      return json(res, 200, { placeStates });
    }

    if (path === '/api/messages/history' && method === 'GET') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      const limitRaw = url.searchParams.get('limit') || '';
      const limit = Math.max(1, Math.min(500, Number(limitRaw || 50)));
      const messages = (db.messages || [])
        .filter((entry) => entry.userId === user.id)
        .sort((a, b) => b.createdAt - a.createdAt)
        .slice(0, limit)
        .map((entry) => entry.message);
      return json(res, 200, { messages });
    }

    // Client compatibility: mark all messages as read (no persistence needed).
    if (path === '/api/messages/read' && method === 'POST') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      return json(res, 200, { ok: true });
    }

    if (path === '/api/messages' && method === 'GET') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      const messages = db.messages
        .filter((entry) => entry.userId === user.id)
        .sort((a, b) => b.createdAt - a.createdAt)
        .map((entry) => ({
          id: entry.id,
          userId: entry.userId,
          message: entry.message,
          date: entry.createdAt,
          placeId: entry.placeId || '',
          type: entry.type || 'manual'
        }));
      return json(res, 200, { messages });
    }

    if (path === '/api/messages' && method === 'POST') {
      const user = requireAuth(db, req, res);
      if (!user) return;
      const body = await readBody(req);
      const message = String(body.message || '').trim();
      if (!message) {
        return json(res, 400, { error: 'Message required' });
      }
      const targetUserId = body.userId ? String(body.userId) : user.id;
      if (targetUserId !== user.id && !user.isAdmin) {
        return json(res, 403, { error: 'Admin only' });
      }
      const targetUser = db.users.find((entry) => entry.id === targetUserId);
      if (!targetUser) {
        return json(res, 404, { error: 'User not found' });
      }
      const createdAt = Number(body.date || Date.now());
      const entry: Message = {
        id: randomUUID(),
        userId: targetUserId,
        message,
        createdAt,
        placeId: body.placeId ? String(body.placeId) : undefined,
        type: 'manual'
      };
      addMessage(db, entry);
      writeDb(db);
      return json(res, 200, { message: { id: entry.id, userId: entry.userId, message: entry.message, date: entry.createdAt } });
    }

    json(res, 404, { error: 'Not found' });
  } catch (error) {
    json(res, 500, { error: String(error) });
  }
});

server.listen(PORT, '0.0.0.0', () => {
  // eslint-disable-next-line no-console
  console.log(`Server running on http://0.0.0.0:${PORT}`);
});
