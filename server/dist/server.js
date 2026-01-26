import http from 'node:http';
import { readFileSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { URL } from 'node:url';
const DB_PATH = new URL('../data/db.json', import.meta.url);
function readDb() {
    const raw = readFileSync(DB_PATH, 'utf-8');
    const data = JSON.parse(raw);
    if (!data.systemOverrides) {
        data.systemOverrides = [];
    }
    return data;
}
function writeDb(db) {
    writeFileSync(DB_PATH, JSON.stringify(db, null, 2));
}
async function readBody(req) {
    const chunks = [];
    for await (const chunk of req) {
        chunks.push(Buffer.from(chunk));
    }
    if (chunks.length === 0) {
        return {};
    }
    const text = Buffer.concat(chunks).toString('utf-8');
    return JSON.parse(text);
}
function json(res, status, payload) {
    res.writeHead(status, {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    });
    res.end(JSON.stringify(payload));
}
function getToken(req) {
    const auth = req.headers.authorization || '';
    if (auth.startsWith('Bearer ')) {
        return auth.slice(7);
    }
    return '';
}
function requireAuth(db, req, res) {
    const token = getToken(req);
    const userId = token ? db.tokens[token] : '';
    const user = db.users.find((u) => u.id === userId) || null;
    if (!user) {
        json(res, 401, { error: 'Unauthorized' });
        return null;
    }
    return user;
}
function ensureAdmin(user, res) {
    if (!user.isAdmin) {
        json(res, 403, { error: 'Admin only' });
        return false;
    }
    return true;
}
function toPlaceResponse(place) {
    return {
        id: place.id,
        name: place.name,
        lat: place.lat,
        lon: place.lon,
        description: place.description,
        imageUrl: place.imageUrl,
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
function buildPlaceFromBody(body, owner, statusOverride) {
    const now = Date.now();
    const name = String(body.name || '').trim();
    const lat = Number(body.lat || 0);
    const lon = Number(body.lon || 0);
    const description = String(body.description || '');
    const imageUrl = String(body.imageUrl || '');
    const category = (body.category === 'hazard' ? 'hazard' : 'normal');
    const hazardTypeRaw = category === 'hazard' ? String(body.hazardType || '') : '';
    const hazardType = (hazardTypeRaw === 'water' || hazardTypeRaw === 'slippery' || hazardTypeRaw === 'danger') ? hazardTypeRaw : '';
    const statusBody = String(body.status || 'private');
    const status = statusOverride || statusBody;
    return {
        id: randomUUID(),
        name,
        lat,
        lon,
        description,
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
function updatePlaceFromBody(place, body, user) {
    place.name = String(body.name || place.name);
    place.description = String(body.description || place.description || '');
    place.imageUrl = String(body.imageUrl || place.imageUrl || '');
    place.lat = Number(body.lat || place.lat);
    place.lon = Number(body.lon || place.lon);
    const category = body.category === 'hazard' ? 'hazard' : 'normal';
    place.category = category;
    if (category === 'hazard') {
        const hazardTypeRaw = String(body.hazardType || place.hazardType || '');
        place.hazardType = (hazardTypeRaw === 'water' || hazardTypeRaw === 'slippery' || hazardTypeRaw === 'danger') ? hazardTypeRaw : '';
    }
    else {
        place.hazardType = '';
    }
    if (user.isAdmin && body.status) {
        place.status = body.status;
    }
    else if (body.status === 'approved') {
        place.status = 'pending';
    }
    place.updatedAt = Date.now();
}
const server = http.createServer(async (req, res) => {
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
            if (db.users.some((u) => u.username === username)) {
                return json(res, 400, { error: 'User exists' });
            }
            const user = {
                id: randomUUID(),
                username,
                password,
                isAdmin: false,
                hiddenPlaceIds: [],
                createdAt: Date.now()
            };
            db.users.push(user);
            const token = randomUUID();
            db.tokens[token] = user.id;
            writeDb(db);
            return json(res, 200, { token, user: { id: user.id, username: user.username, isAdmin: user.isAdmin } });
        }
        if (path === '/api/login' && method === 'POST') {
            const body = await readBody(req);
            const username = String(body.username || '').trim();
            const password = String(body.password || '').trim();
            const user = db.users.find((u) => u.username === username && u.password === password);
            if (!user) {
                return json(res, 401, { error: 'Invalid credentials' });
            }
            const token = randomUUID();
            db.tokens[token] = user.id;
            writeDb(db);
            return json(res, 200, { token, user: { id: user.id, username: user.username, isAdmin: user.isAdmin } });
        }
        if (path === '/api/me' && method === 'GET') {
            const user = requireAuth(db, req, res);
            if (!user)
                return;
            return json(res, 200, { user: { id: user.id, username: user.username, isAdmin: user.isAdmin } });
        }
        if (path === '/api/system-overrides' && method === 'GET') {
            return json(res, 200, { overrides: db.systemOverrides || [] });
        }
        if (path === '/api/places' && method === 'GET') {
            const scope = url.searchParams.get('scope') || 'public';
            if (scope === 'public') {
                const approved = db.places.filter((p) => p.status === 'approved');
                const hazards = approved.filter((p) => p.category === 'hazard');
                const places = approved.filter((p) => p.category !== 'hazard');
                return json(res, 200, {
                    places: places.map(toPlaceResponse),
                    hazards: hazards.map(toPlaceResponse)
                });
            }
            const user = requireAuth(db, req, res);
            if (!user)
                return;
            if (scope === 'mine') {
                const mine = db.places.filter((p) => p.ownerId === user.id);
                const pending = mine.filter((p) => p.status === 'pending');
                const others = mine.filter((p) => p.status !== 'pending');
                return json(res, 200, {
                    places: others.map(toPlaceResponse),
                    pending: pending.map(toPlaceResponse)
                });
            }
            if (scope === 'pending') {
                if (!ensureAdmin(user, res))
                    return;
                const pending = db.places.filter((p) => p.status === 'pending');
                return json(res, 200, { pending: pending.map(toPlaceResponse) });
            }
        }
        if (path === '/api/places' && method === 'POST') {
            const user = requireAuth(db, req, res);
            if (!user)
                return;
            const body = await readBody(req);
            const status = user.isAdmin && body.status === 'approved' ? 'approved' : (body.status === 'pending' ? 'pending' : 'private');
            const place = buildPlaceFromBody(body, user, status);
            if (!place.name) {
                return json(res, 400, { error: 'Name required' });
            }
            db.places.push(place);
            writeDb(db);
            return json(res, 200, { place: toPlaceResponse(place) });
        }
        if (path.startsWith('/api/places/') && method === 'PUT') {
            const user = requireAuth(db, req, res);
            if (!user)
                return;
            const id = path.split('/')[3];
            const place = db.places.find((p) => p.id === id);
            if (!place) {
                return json(res, 404, { error: 'Not found' });
            }
            if (place.ownerId !== user.id && !user.isAdmin) {
                return json(res, 403, { error: 'Forbidden' });
            }
            const body = await readBody(req);
            updatePlaceFromBody(place, body, user);
            if (!user.isAdmin && place.status === 'approved') {
                place.status = 'pending';
            }
            writeDb(db);
            return json(res, 200, { place: toPlaceResponse(place) });
        }
        if (path.startsWith('/api/places/') && method === 'DELETE') {
            const user = requireAuth(db, req, res);
            if (!user)
                return;
            const id = path.split('/')[3];
            const index = db.places.findIndex((p) => p.id === id);
            if (index === -1) {
                return json(res, 404, { error: 'Not found' });
            }
            const place = db.places[index];
            if (place.ownerId !== user.id && !user.isAdmin) {
                return json(res, 403, { error: 'Forbidden' });
            }
            db.places.splice(index, 1);
            writeDb(db);
            return json(res, 200, { ok: true });
        }
        if (path.endsWith('/publish') && method === 'POST') {
            const user = requireAuth(db, req, res);
            if (!user)
                return;
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
            return json(res, 200, { place: toPlaceResponse(place) });
        }
        if (path.endsWith('/vote') && method === 'POST') {
            const user = requireAuth(db, req, res);
            if (!user)
                return;
            const id = path.split('/')[3];
            const place = db.places.find((p) => p.id === id);
            if (!place) {
                return json(res, 404, { error: 'Not found' });
            }
            const body = await readBody(req);
            const value = Number(body.value || 0);
            if (value !== 1 && value !== -1) {
                return json(res, 400, { error: 'Invalid vote' });
            }
            const prev = place.voters[user.id] || 0;
            if (prev === value) {
                return json(res, 200, { place: toPlaceResponse(place) });
            }
            if (prev === 1)
                place.votes.up -= 1;
            if (prev === -1)
                place.votes.down -= 1;
            if (value === 1)
                place.votes.up += 1;
            if (value === -1)
                place.votes.down += 1;
            place.voters[user.id] = value;
            place.updatedAt = Date.now();
            writeDb(db);
            return json(res, 200, { place: toPlaceResponse(place) });
        }
        if (path.endsWith('/feedback') && method === 'POST') {
            const user = requireAuth(db, req, res);
            if (!user)
                return;
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
            writeDb(db);
            return json(res, 200, { ok: true });
        }
        if (path.startsWith('/api/admin/places/') && path.endsWith('/approve') && method === 'POST') {
            const user = requireAuth(db, req, res);
            if (!user)
                return;
            if (!ensureAdmin(user, res))
                return;
            const id = path.split('/')[4];
            const place = db.places.find((p) => p.id === id);
            if (!place) {
                return json(res, 404, { error: 'Not found' });
            }
            place.status = 'approved';
            place.updatedAt = Date.now();
            if (place.sourceType === 'system' && place.sourceKey) {
                const existing = db.systemOverrides.find((o) => o.sourceKey === place.sourceKey);
                if (existing) {
                    existing.name = place.name;
                    existing.description = place.description;
                    existing.imageUrl = place.imageUrl;
                    existing.updatedAt = Date.now();
                }
                else {
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
            return json(res, 200, { place: toPlaceResponse(place) });
        }
        if (path.startsWith('/api/admin/places/') && path.endsWith('/reject') && method === 'POST') {
            const user = requireAuth(db, req, res);
            if (!user)
                return;
            if (!ensureAdmin(user, res))
                return;
            const id = path.split('/')[4];
            const place = db.places.find((p) => p.id === id);
            if (!place) {
                return json(res, 404, { error: 'Not found' });
            }
            place.status = 'rejected';
            place.updatedAt = Date.now();
            writeDb(db);
            return json(res, 200, { place: toPlaceResponse(place) });
        }
        if (path === '/api/preferences' && method === 'GET') {
            const user = requireAuth(db, req, res);
            if (!user)
                return;
            return json(res, 200, { hiddenPlaceIds: user.hiddenPlaceIds || [] });
        }
        if (path === '/api/preferences/hide' && method === 'POST') {
            const user = requireAuth(db, req, res);
            if (!user)
                return;
            const body = await readBody(req);
            const placeId = String(body.placeId || '');
            const hidden = Boolean(body.hidden);
            if (!placeId) {
                return json(res, 400, { error: 'placeId required' });
            }
            const set = new Set(user.hiddenPlaceIds || []);
            if (hidden) {
                set.add(placeId);
            }
            else {
                set.delete(placeId);
            }
            user.hiddenPlaceIds = Array.from(set);
            writeDb(db);
            return json(res, 200, { hiddenPlaceIds: user.hiddenPlaceIds });
        }
        json(res, 404, { error: 'Not found' });
    }
    catch (error) {
        json(res, 500, { error: String(error) });
    }
});
const PORT = 8080;
server.listen(PORT, '0.0.0.0', () => {
    // eslint-disable-next-line no-console
    console.log(`Server running on http://0.0.0.0:${PORT}`);
});
