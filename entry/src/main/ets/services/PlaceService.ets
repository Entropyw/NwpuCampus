import http from '@ohos.net.http';
import { LatLon, MapLabel, Place, PlaceFilter, PlaceStatus, PlaceType, PlaceTypeFlags, UserSession } from '../model/MapTypes';
import { HttpClient, HttpRequestBody } from './HttpClient';

export interface SaveDraftInput {
  name: string;
  description: string;
  type: PlaceType;
  imageUrl?: string;
  point: LatLon;
  sourceKey?: string;
  sourceType?: string;
  sourcePlaceId?: string;
  status?: PlaceStatus;
}

export interface UpdatePlaceInput {
  name: string;
  description: string;
  type: PlaceType;
  imageUrl?: string;
  point: LatLon;
  status?: PlaceStatus;
}

interface PlaceVotes {
  up: number;
  down: number;
}

interface PlaceResponse {
  id: string;
  name: string;
  lat: number;
  lon: number;
  description: string;
  imageUrl: string;
  ownerId: string;
  ownerName: string;
  status: PlaceStatus;
  category: string;
  hazardType: string;
  votes: PlaceVotes;
  createdAt: number;
  updatedAt: number;
  sourceKey?: string;
  sourceType?: string;
}

interface PlaceWrapperResponse {
  place: PlaceResponse;
}

interface PlacesListResponse {
  places?: PlaceResponse[];
  hazards?: PlaceResponse[];
  pending?: PlaceResponse[];
}

interface PlaceStateRecord {
  hidden?: boolean;
  favorite?: boolean;
  updatedAt?: number;
}

interface PreferencesResponse {
  hiddenPlaceIds?: string[];
  favoritePlaceIds?: string[];
  placeStates?: Record<string, PlaceStateRecord>;
}

interface SystemOverrideRecord {
  sourceKey: string;
  name?: string;
  description?: string;
  imageUrl?: string;
}

interface SystemOverrideResponse {
  overrides?: SystemOverrideRecord[];
}

interface ErrorPayload {
  error?: string;
  message?: string;
}

class VoteRequest extends HttpRequestBody {
  constructor(value: number) {
    super();
    this.value = value;
  }
}

class HideRequest extends HttpRequestBody {
  constructor(placeId: string, hidden: boolean) {
    super();
    this.placeId = placeId;
    this.hidden = hidden;
  }
}

class FavoriteRequest extends HttpRequestBody {
  placeId: string;
  favorite: boolean;

  constructor(placeId: string, favorite: boolean) {
    super();
    this.placeId = placeId;
    this.favorite = favorite;
  }
}

class PlaceStateRequest extends HttpRequestBody {
  placeId: string;
  hidden?: boolean;
  favorite?: boolean;

  constructor(placeId: string, hidden?: boolean, favorite?: boolean) {
    super();
    this.placeId = placeId;
    if (hidden !== undefined) {
      this.hidden = hidden;
    }
    if (favorite !== undefined) {
      this.favorite = favorite;
    }
  }
}

class PlacePayload extends HttpRequestBody {
  constructor(input: SaveDraftInput) {
    super();
    this.name = input.name.trim() || '未命名地点';
    this.description = input.description;
    this.imageUrl = input.imageUrl || '';
    this.lat = input.point.lat;
    this.lon = input.point.lon;
    this.category = input.type === 'normal' ? 'normal' : 'hazard';
    this.hazardType = input.type === 'normal' ? '' : input.type;
    this.status = input.status ? input.status : 'private';
    this.sourceKey = input.sourceKey || '';
    this.sourceType = input.sourceType || '';
    this.sourcePlaceId = input.sourcePlaceId || '';
  }
}

export class PlaceService {
  private places: Array<Place> = [];
  private counter = 0;
  private client: HttpClient | null = null;
  private useRemote: boolean = false;
  private lastError: string = '';
  private hiddenByUser: Map<string, Set<string>> = new Map();
  private favoriteByUser: Map<string, Set<string>> = new Map();
  private prefLoadedFor: string = '';
  private prefLoadedAt: number = 0;
  private voteRecords: Map<string, Map<string, number>> = new Map();
  private seededSystemSyncedForAdmin: string = '';

  enableRemote(baseUrl: string): void {
    this.client = new HttpClient(baseUrl);
    this.useRemote = true;
    this.lastError = '';
  }

  makeSystemSourceKey(name: string, lat: number, lon: number): string {
    return this.makeSourceKey(name, lat, lon);
  }

  async syncRemote(session: UserSession | null): Promise<boolean> {
    this.lastError = '';
    if (!this.useRemote || !this.client) {
      this.lastError = '当前环境未配置远程服务';
      return false;
    }

    // If admin is logged in, ensure locally seeded system POIs (sys-*) are present
    // on the server so they can be deleted/voted on consistently.
    if (session && session.isAdmin) {
      await this.syncSeededSystemPlacesToServer(session);
    }

    const wideFilter: PlaceFilter = {
      showSystem: true,
      showPublic: true,
      showMine: true,
      types: { normal: true, water: true, slippery: true, danger: true },
      sortBy: 'time',
      avoidHazards: false
    };
    await this.fetchRemotePlaces(wideFilter, session);
    // Even if server returns empty list, sync is successful.
    return this.lastError.length === 0;
  }

  private replaceRemoteCache(remotePlaces: Array<Place>): void {
    // Keep locally-seeded OSM system POIs (sys-*), but drop any seeded POI that already
    // has a corresponding server-side system place (same sourceKey). This prevents the UI
    // from selecting the synthetic sys-* record (which cannot be deleted on server).
    const serverSystemKeys = new Set<string>();
    remotePlaces.forEach((p) => {
      if (p && p.sourceType === 'system' && p.sourceKey && p.id && p.id.indexOf('sys-') !== 0) {
        serverSystemKeys.add(p.sourceKey);
      }
    });
    const kept = this.places.filter((p) => {
      if (!p.id || p.id.indexOf('sys-') !== 0) {
        return false;
      }
      if (p.sourceType === 'system' && p.sourceKey && serverSystemKeys.has(p.sourceKey)) {
        return false;
      }
      return true;
    });
    this.places = kept;
    remotePlaces.forEach((place) => this.mergePlace(place));
  }

  hardReseedSystemPlaces(labels: Array<MapLabel>): void {
    // Mimic re-entering the page: clear local cache and re-seed the sys-* POIs.
    this.places = [];
    this.counter = 0;
    this.lastError = '';
    // Keep per-user UI state (hidden/favorite/votes) so button labels remain correct.
    this.seedSystemPlaces(labels);
  }

  getMyVoteValue(placeId: string, session: UserSession | null): number {
    if (!session) {
      return 0;
    }
    const record = this.voteRecords.get(session.username);
    if (!record) {
      return 0;
    }
    const place = this.places.find((p) => p.id === placeId);
    if (!place) {
      return record.get(placeId) || 0;
    }
    const resolved = this.resolveServerPlaceId(place);
    return record.get(resolved) || 0;
  }

  private async syncSeededSystemPlacesToServer(session: UserSession): Promise<void> {
    if (!session || !session.isAdmin || !session.token || !this.useRemote || !this.client) {
      return;
    }
    if (this.seededSystemSyncedForAdmin === session.username) {
      return;
    }

    const seeded = this.places.filter((p) => p.id && p.id.indexOf('sys-') === 0 && p.sourceType === 'system' && !!p.sourceKey);
    if (seeded.length === 0) {
      this.seededSystemSyncedForAdmin = session.username;
      return;
    }

    let hadError = false;

    for (const place of seeded) {
      // If already resolved to a server id, skip.
      const resolved = this.resolveServerPlaceId(place);
      if (resolved && resolved !== place.id) {
        continue;
      }
      try {
        const input: SaveDraftInput = {
          name: place.name,
          description: place.description || '系统地点',
          type: place.type,
          imageUrl: place.imageUrl,
          point: { lat: place.lat, lon: place.lon },
          sourceKey: place.sourceKey,
          sourceType: 'system',
          status: 'approved'
        };
        const payload = new PlacePayload(input);
        const resp = await this.client.requestWithStatus(http.RequestMethod.POST, '/api/places', payload, session.token);
        if (resp.status >= 200 && resp.status < 300) {
          const wrapper = this.parsePlaceWrapper(resp.body);
          const created = wrapper ? this.fromServerPlace(wrapper.place) : null;
          if (created) {
            this.mergePlace(created);
          }
        }
      } catch (e) {
        // Best-effort: don't block refresh; surface error once.
        hadError = true;
        if (!this.lastError) {
          this.lastError = `网络错误：${String(e)}`;
        }
      }
    }

    if (!hadError) {
      this.seededSystemSyncedForAdmin = session.username;
    }
  }

  getLastError(): string {
    return this.lastError;
  }

  private extractServerError(body: string): string {
    if (!body) {
      return '';
    }
    try {
      const parsed: ErrorPayload = JSON.parse(body) as ErrorPayload;
      const err: string | undefined = parsed ? parsed.error : undefined;
      const msg: string | undefined = parsed ? parsed.message : undefined;
      if (typeof err === 'string' && err.trim().length > 0) {
        return err.trim();
      }
      if (typeof msg === 'string' && msg.trim().length > 0) {
        return msg.trim();
      }
    } catch {
      // ignore
    }
    return '';
  }

  private formatHttpError(status: number, body: string): string {
    const server = this.extractServerError(body);
    if (server) {
      return server;
    }
    return status ? `请求失败（HTTP ${status}）` : '请求失败';
  }

  seedSystemPlaces(labels: Array<MapLabel>): void {
    if (this.places.some((place) => !place.ownerId)) {
      return;
    }
    labels.slice(0, 60).forEach((label) => {
      const sourceKey = this.makeSourceKey(label.name, label.lat, label.lon);
      const place: Place = {
        id: `sys-${this.counter++}`,
        name: label.name,
        description: '系统地点',
        lat: label.lat,
        lon: label.lon,
        type: 'normal',
        ownerId: undefined,
        status: 'published',
        createdAt: Date.now(),
        updatedAt: Date.now(),
        likes: 0,
        dislikes: 0,
        sourceKey,
        sourceType: 'system'
      };
      this.places.push(place);
    });
  }

  async list(filter: PlaceFilter, session: UserSession | null): Promise<Array<Place>> {
    await this.ensurePreferencesLoaded(session);
    await this.applySystemOverrides();
    if (this.useRemote && this.client) {
      const merged = await this.fetchRemotePlaces(filter, session);
      if (merged.length > 0) {
        // Use remote as source of truth for business data, but keep local OSM-derived
        // system POIs for rendering (they are static resources, not user data).
        const combined = this.filterPlaces(this.places, filter, session);
        return this.sortPlaces(combined, filter);
      }
    }
    const username = session ? session.username : '';
    const filtered = this.places.filter((place) => {
      if (this.isHiddenForUser(place.id, session) || place.hidden) {
        return false;
      }
      const isSystem = this.isSystemPlace(place);
      const isMine = place.ownerId && place.ownerId === username;
      if (isSystem && !filter.showSystem) {
        return false;
      }
      if (isMine && !filter.showMine) {
        return false;
      }
      if (!isSystem && !isMine && !filter.showPublic) {
        return false;
      }
      if (!this.isTypeEnabled(place.type, filter.types)) {
        return false;
      }
      if (place.status !== 'published' && place.status !== 'approved' && !isMine) {
        return false;
      }
      return true;
    });

    return this.sortPlaces(filtered, filter);
  }

  async saveDraft(input: SaveDraftInput, session: UserSession | null): Promise<Place | null> {
    if (!session) {
      this.lastError = '请先登录';
      return null;
    }
    if (this.useRemote && this.client && session.token) {
      try {
        const payload: PlacePayload = new PlacePayload(input);
        const responseText = await this.client.request(http.RequestMethod.POST, '/api/places', payload, session.token);
        const response = this.parsePlaceWrapper(responseText);
        const place = response ? this.fromServerPlace(response.place) : null;
        if (place) {
          this.mergePlace(place);
          return place;
        }
      } catch (e) {
        this.lastError = `网络错误：${String(e)}`;
        return null;
      }
    }
    this.lastError = '当前环境未配置远程服务';
    return null;
  }

  async updatePlace(placeId: string, input: UpdatePlaceInput, session: UserSession | null): Promise<Place | null> {
    if (!session) {
      this.lastError = '请先登录';
      return null;
    }
    if (this.useRemote && this.client && session.token) {
      try {
        const draftInput: SaveDraftInput = {
          name: input.name,
          description: input.description,
          type: input.type,
          imageUrl: input.imageUrl,
          point: input.point,
          status: input.status
        };
        const payload = new PlacePayload(draftInput);
        const responseText = await this.client.request(http.RequestMethod.PUT, `/api/places/${placeId}`, payload, session.token);
        const response = this.parsePlaceWrapper(responseText);
        const place = response ? this.fromServerPlace(response.place) : null;
        if (place) {
          this.mergePlace(place);
          return place;
        }
      } catch (e) {
        this.lastError = `网络错误：${String(e)}`;
        return null;
      }
    }
    this.lastError = '当前环境未配置远程服务';
    return null;
  }

  async publish(placeId: string, session: UserSession | null): Promise<boolean> {
    const place = this.places.find((item) => item.id === placeId);
    if (!place || !session || place.ownerId !== session.username) {
      return false;
    }
    if (this.useRemote && this.client && session.token) {
      try {
  const payload: HttpRequestBody = new HttpRequestBody();
  await this.client.request(http.RequestMethod.POST, `/api/places/${placeId}/publish`, payload, session.token);
        place.status = 'pending';
        return true;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  async approve(placeId: string, session: UserSession | null): Promise<boolean> {
    if (!session || !session.isAdmin) {
      return false;
    }
    const place = this.places.find((item) => item.id === placeId);
    if (!place) {
      return false;
    }
    if (this.useRemote && this.client && session.token) {
      try {
  const payload: HttpRequestBody = new HttpRequestBody();
  await this.client.request(http.RequestMethod.POST, `/api/admin/places/${placeId}/approve`, payload, session.token);
        place.status = 'approved';
        return true;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  async reject(placeId: string, session: UserSession | null): Promise<boolean> {
    if (!session || !session.isAdmin) {
      return false;
    }
    const place = this.places.find((item) => item.id === placeId);
    if (!place) {
      return false;
    }
    if (this.useRemote && this.client && session.token) {
      try {
  const payload: HttpRequestBody = new HttpRequestBody();
  await this.client.request(http.RequestMethod.POST, `/api/admin/places/${placeId}/reject`, payload, session.token);
        place.status = 'rejected';
        return true;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  async delete(placeId: string, session: UserSession | null): Promise<boolean> {
    const index = this.places.findIndex((item) => item.id === placeId);
    if (index < 0) {
      return false;
    }
    const place = this.places[index];
    if (!session || (place.ownerId !== session.username && !session.isAdmin)) {
      return false;
    }
    if (place.sourceType === 'system' && session.isAdmin) {
      if (!this.useRemote || !this.client || !session.token) {
        this.lastError = '当前环境未配置远程服务';
        return false;
      }
      const isSeeded = place.id && place.id.indexOf('sys-') === 0;
      const resolvedId = isSeeded ? this.resolveServerPlaceId(place) : place.id;
      if (!resolvedId) {
        this.lastError = '系统地点尚未同步到服务器，无法删除';
        return false;
      }
      try {
        const encodedId = encodeURIComponent(resolvedId);
        const resp = await this.client.requestWithStatus(http.RequestMethod.DELETE, `/api/places/${encodedId}`, undefined, session.token);
        if (resp.status < 200 || resp.status >= 300) {
          this.lastError = this.formatHttpError(resp.status, resp.body);
          return false;
        }
      } catch (e) {
        this.lastError = `网络错误：${String(e)}`;
        return false;
      }

      const sourceKey = place.sourceKey || '';
      this.places = this.places.filter((p) => {
        if (p.id === placeId || p.id === resolvedId) {
          return false;
        }
        if (sourceKey && p.sourceType === 'system' && p.sourceKey === sourceKey) {
          return false;
        }
        return true;
      });
      return true;
    }
    if (this.useRemote && this.client && session.token) {
      try {
        const encodedId = encodeURIComponent(placeId);
        const resp = await this.client.requestWithStatus(http.RequestMethod.DELETE, `/api/places/${encodedId}`, undefined, session.token);
        if (resp.status < 200 || resp.status >= 300) {
          this.lastError = this.formatHttpError(resp.status, resp.body);
          return false;
        }
        this.places.splice(index, 1);
        return true;
      } catch (e) {
        this.lastError = `网络错误：${String(e)}`;
        return false;
      }
    }
    return false;
  }

  async vote(placeId: string, delta: number, session: UserSession | null): Promise<boolean> {
    this.lastError = '';
    const place = this.places.find((item) => item.id === placeId);
    if (!place) {
      this.lastError = '地点不存在';
      return false;
    }
    if (!session || !session.token || !this.useRemote || !this.client) {
      this.lastError = '请先登录';
      return false;
    }
    const resolvedId = this.resolveServerPlaceId(place);
    if (!resolvedId) {
      this.lastError = '系统地点尚未同步到服务器';
      return false;
    }
    const record = this.voteRecords.get(session.username) || new Map<string, number>();
    const prev = record.get(resolvedId) || 0;
    const desired = prev === delta ? 0 : delta;
    if (this.useRemote && this.client && session.token) {
      try {
        const payload: VoteRequest = new VoteRequest(desired);
        const encodedId = encodeURIComponent(resolvedId);
        const resp = await this.client.requestWithStatus(http.RequestMethod.POST, `/api/places/${encodedId}/vote`, payload, session.token);
        if (resp.status < 200 || resp.status >= 300) {
          this.lastError = this.formatHttpError(resp.status, resp.body);
          return false;
        }
        const response = this.parsePlaceWrapper(resp.body);
        const updated = response ? this.fromServerPlace(response.place) : null;
        if (updated) {
          this.mergePlace(updated);
          if (desired === 0) {
            record.delete(resolvedId);
          } else {
            record.set(resolvedId, desired);
          }
          this.voteRecords.set(session.username, record);
          return true;
        }
        this.lastError = this.extractServerError(resp.body) || '服务端返回异常';
      } catch (e) {
        this.lastError = `网络错误：${String(e)}`;
        return false;
      }
    }
    return false;
  }

  hasVoted(placeId: string, session: UserSession | null): boolean {
    if (!session) {
      return false;
    }
    const record = this.voteRecords.get(session.username);
    if (!record) {
      return false;
    }
    const place = this.places.find((p) => p.id === placeId);
    if (!place) {
      return (record.get(placeId) || 0) !== 0;
    }
    const resolved = this.resolveServerPlaceId(place);
    return (record.get(resolved) || 0) !== 0;
  }

  async listMyPlaces(session: UserSession | null): Promise<Array<Place>> {
    if (!session) {
      return [];
    }
    if (this.useRemote && this.client && session.token) {
      try {
        const responseText = await this.client.request(http.RequestMethod.GET, '/api/places?scope=mine', undefined, session.token);
        const mineResp = this.parsePlacesResponse(responseText);
        const minePlaces = mineResp ? this.mapServerPlaces(mineResp.places) : [];
        const pending = mineResp ? this.mapServerPlaces(mineResp.pending) : [];
        const combined = [...minePlaces, ...pending];
        combined.forEach((place) => this.mergePlace(place));
        return combined;
      } catch (e) {
        // fallback to local
      }
    }
    return this.places.filter((item) => item.ownerId === session.username);
  }

  getCachedPlaces(): Array<Place> {
    return this.places.slice();
  }

  async toggleHidden(placeId: string, hidden: boolean, session: UserSession | null): Promise<boolean> {
    this.lastError = '';
    const place = this.places.find((item) => item.id === placeId);
    if (!place || !session) {
      this.lastError = '请先登录';
      return false;
    }
    if (!this.useRemote || !this.client || !session.token) {
      this.lastError = '当前环境未配置远程服务';
      return false;
    }
    try {
      const resolvedId = this.resolveServerPlaceId(place);
      const payload: PlaceStateRequest = new PlaceStateRequest(resolvedId, hidden, undefined);
      const resp = await this.client.requestWithStatus(http.RequestMethod.POST, '/api/preferences/state', payload, session.token);
      if (resp.status < 200 || resp.status >= 300) {
        this.lastError = this.formatHttpError(resp.status, resp.body);
        return false;
      }
      const key = session.username;
      const set = this.hiddenByUser.get(key) || new Set<string>();
      if (hidden) {
        set.add(resolvedId);
      } else {
        set.delete(resolvedId);
      }
      this.hiddenByUser.set(key, set);
      // force refresh next time
      this.prefLoadedAt = 0;
      return true;
    } catch (e) {
      this.lastError = `网络错误：${String(e)}`;
      return false;
    }
  }

  async toggleFavorite(placeId: string, favorite: boolean, session: UserSession | null): Promise<boolean> {
    this.lastError = '';
    const place = this.places.find((item) => item.id === placeId);
    if (!place || !session || !this.useRemote || !this.client || !session.token) {
      this.lastError = '请先登录';
      return false;
    }
    try {
      const resolvedId = this.resolveServerPlaceId(place);
      const payload: PlaceStateRequest = new PlaceStateRequest(resolvedId, undefined, favorite);
      const resp = await this.client.requestWithStatus(http.RequestMethod.POST, '/api/preferences/state', payload, session.token);
      if (resp.status < 200 || resp.status >= 300) {
        this.lastError = this.formatHttpError(resp.status, resp.body);
        return false;
      }
      const key = session.username;
      const set = this.favoriteByUser.get(key) || new Set<string>();
      if (favorite) {
        set.add(resolvedId);
      } else {
        set.delete(resolvedId);
      }
      this.favoriteByUser.set(key, set);
      this.prefLoadedAt = 0;
      return true;
    } catch (e) {
      this.lastError = `网络错误：${String(e)}`;
      return false;
    }
  }

  isPlaceFavorite(placeId: string, session: UserSession | null): boolean {
    if (!session) {
      return false;
    }
    const set = this.favoriteByUser.get(session.username);
    if (!set) {
      return false;
    }
    if (set.has(placeId)) {
      return true;
    }
    const place = this.places.find((p) => p.id === placeId);
    if (!place) {
      return false;
    }
    const resolved = this.resolveServerPlaceId(place);
    return resolved !== placeId ? set.has(resolved) : false;
  }

  getFavoritePlaceIds(session: UserSession | null): Array<string> {
    if (!session) {
      return [];
    }
    const set = this.favoriteByUser.get(session.username);
    return set ? Array.from(set) : [];
  }

  getHiddenPlaceIds(session: UserSession | null): Array<string> {
    if (!session) {
      return [];
    }
    const set = this.hiddenByUser.get(session.username);
    return set ? Array.from(set) : [];
  }

  async reportFeedback(placeId: string, message: string, session: UserSession | null): Promise<boolean> {
    this.lastError = '';
    if (!session || !this.client || !this.useRemote || !session.token) {
      this.lastError = '请先登录';
      return false;
    }
    const place = this.places.find((p) => p.id === placeId);
    if (!place) {
      this.lastError = '地点不存在';
      return false;
    }
    const resolvedId = this.resolveServerPlaceId(place);
    if (!resolvedId) {
      this.lastError = '系统地点尚未同步到服务器';
      return false;
    }
    try {
      const payload: HttpRequestBody = new HttpRequestBody();
      payload.message = message;
      const encodedId = encodeURIComponent(resolvedId);
      const resp = await this.client.requestWithStatus(http.RequestMethod.POST, `/api/places/${encodedId}/feedback`, payload, session.token);
      if (resp.status < 200 || resp.status >= 300) {
        this.lastError = this.formatHttpError(resp.status, resp.body);
        return false;
      }
      return true;
    } catch (e) {
      this.lastError = `网络错误：${String(e)}`;
      return false;
    }
  }

  async listPending(session: UserSession | null): Promise<Array<Place>> {
    if (!session || !session.isAdmin) {
      return [];
    }
    if (this.useRemote && this.client && session.token) {
      try {
        const responseText = await this.client.request(http.RequestMethod.GET, '/api/places?scope=pending', undefined, session.token);
        const response = this.parsePlacesResponse(responseText);
        const pending = response ? this.mapServerPlaces(response.pending) : [];
        if (pending.length > 0) {
          pending.forEach((place) => this.mergePlace(place));
          return pending;
        }
      } catch (e) {
        // fallback to local
      }
    }
    return this.places.filter((item) => item.status === 'pending');
  }

  private sortPlaces(list: Array<Place>, filter: PlaceFilter): Array<Place> {
    const sorted = list.slice();
    if (filter.sortBy === 'likes') {
      sorted.sort((a, b) => b.likes - a.likes);
    } else {
      sorted.sort((a, b) => b.createdAt - a.createdAt);
    }
    return sorted;
  }

  private async fetchRemotePlaces(filter: PlaceFilter, session: UserSession | null): Promise<Array<Place>> {
    if (!this.client) {
      return [];
    }
    const results: Array<Place> = [];
    try {
      const resp = await this.client.requestWithStatus(http.RequestMethod.GET, '/api/places?scope=public');
      if (resp.status < 200 || resp.status >= 300) {
        this.lastError = this.formatHttpError(resp.status, resp.body);
        return [];
      }
      const publicResp = this.parsePlacesResponse(resp.body);
      const publicPlaces = publicResp ? this.mapServerPlaces(publicResp.places) : [];
      const publicHazards = publicResp ? this.mapServerPlaces(publicResp.hazards) : [];
      results.push(...publicPlaces, ...publicHazards);
    } catch (e) {
      this.lastError = `网络错误：${String(e)}`;
      return [];
    }
    if (session && session.token) {
      try {
        const resp = await this.client.requestWithStatus(http.RequestMethod.GET, '/api/places?scope=mine', undefined, session.token);
        if (resp.status >= 200 && resp.status < 300) {
          const mineResp = this.parsePlacesResponse(resp.body);
          const minePlaces = mineResp ? this.mapServerPlaces(mineResp.places) : [];
          const pending = mineResp ? this.mapServerPlaces(mineResp.pending) : [];
          results.push(...minePlaces, ...pending);
        }
      } catch (e) {
        // ignore
      }
    }

    this.replaceRemoteCache(results);
    return this.filterPlaces(this.places, filter, session);
  }

  private filterPlaces(list: Array<Place>, filter: PlaceFilter, session: UserSession | null): Array<Place> {
    const username = session ? session.username : '';
    return list.filter((place) => {
      if (this.isHiddenForUser(place.id, session) || place.hidden) {
        return false;
      }
      const isSystem = this.isSystemPlace(place);
      const isMine = place.ownerId && place.ownerId === username;
      if (isSystem && !filter.showSystem) {
        return false;
      }
      if (isMine && !filter.showMine) {
        return false;
      }
      if (!isSystem && !isMine && !filter.showPublic) {
        return false;
      }
      if (!this.isTypeEnabled(place.type, filter.types)) {
        return false;
      }
      if (place.status !== 'approved' && place.status !== 'published' && !isMine) {
        return false;
      }
      return true;
    });
  }

  private mapServerPlaces(list: PlaceResponse[] | undefined): Array<Place> {
    if (!list) {
      return [];
    }
    const mapped: Array<Place> = [];
    for (const item of list) {
      const place = this.fromServerPlace(item);
      if (place) {
        mapped.push(place);
      }
    }
    return mapped;
  }

  private fromServerPlace(item: PlaceResponse): Place | null {
    if (!item) {
      return null;
    }
    const hazardType = item.hazardType || '';
    const category = item.category || 'normal';
    const type: PlaceType = category === 'hazard'
      ? (hazardType === 'water' || hazardType === 'slippery' || hazardType === 'danger' ? hazardType as PlaceType : 'danger')
      : 'normal';
    const likes = item.votes ? item.votes.up : 0;
    const dislikes = item.votes ? item.votes.down : 0;
    const sourceType = item.sourceType === 'system' ? 'system' : '';
    const place: Place = {
      id: item.id,
      name: item.name || '未命名地点',
      description: item.description || '',
      lat: item.lat,
      lon: item.lon,
      type,
      ownerId: item.ownerName ? item.ownerName : item.ownerId,
      ownerName: item.ownerName || '',
      status: item.status || 'approved',
      createdAt: item.createdAt || Date.now(),
      updatedAt: item.updatedAt || Date.now(),
      likes,
      dislikes,
      imageUrl: item.imageUrl || '',
      sourceKey: item.sourceKey || '',
      sourceType: this.normalizeSourceType(sourceType)
    };
    return place;
  }

  private isHiddenForUser(placeId: string, session: UserSession | null): boolean {
    if (!session) {
      return false;
    }
    const set = this.hiddenByUser.get(session.username);
    if (!set) {
      return false;
    }
    if (set.has(placeId)) {
      return true;
    }
    const place = this.places.find((p) => p.id === placeId);
    if (!place) {
      return false;
    }
    const resolved = this.resolveServerPlaceId(place);
    return resolved !== placeId ? set.has(resolved) : false;
  }

  isPlaceHidden(placeId: string, session: UserSession | null): boolean {
    return this.isHiddenForUser(placeId, session);
  }

  private async ensurePreferencesLoaded(session: UserSession | null): Promise<void> {
    if (!session || !this.useRemote || !this.client || !session.token) {
      return;
    }
    const now = Date.now();
    if (this.prefLoadedFor === session.username && now - this.prefLoadedAt < 8000) {
      return;
    }
    try {
      const responseText = await this.client.request(http.RequestMethod.GET, '/api/preferences', undefined, session.token);
      const response = JSON.parse(responseText) as PreferencesResponse;
      const hiddenIds = response.hiddenPlaceIds || [];
      const favoriteIds = response.favoritePlaceIds || [];
      const hiddenSet = new Set<string>(hiddenIds);
      const favoriteSet = new Set<string>(favoriteIds);

      // Merge in placeStates (preferred) if present
      const states = response.placeStates || {};
      Object.keys(states).forEach((placeId: string) => {
        const st = states[placeId];
        if (!st) {
          return;
        }
        if (st.hidden === true) {
          hiddenSet.add(placeId);
        } else if (st.hidden === false) {
          hiddenSet.delete(placeId);
        }
        if (st.favorite === true) {
          favoriteSet.add(placeId);
        } else if (st.favorite === false) {
          favoriteSet.delete(placeId);
        }
      });

      this.hiddenByUser.set(session.username, hiddenSet);
      this.favoriteByUser.set(session.username, favoriteSet);
      this.prefLoadedFor = session.username;
      this.prefLoadedAt = now;
    } catch (e) {
      // ignore
    }
  }

  private isSystemPlace(place: Place): boolean {
    return place.sourceType === 'system' || !place.ownerId;
  }

  private resolveServerPlaceId(place: Place): string {
    if (!place) {
      return '';
    }
    // Local system POIs are seeded with synthetic ids (sys-*) for rendering.
    // When the backend has a corresponding system place, it should share the same
    // sourceKey; resolve to the real server id before calling APIs.
    if (place.sourceType === 'system' && place.sourceKey && place.id && place.id.indexOf('sys-') === 0) {
      const match = this.places.find((p) => p.sourceKey === place.sourceKey && p.id && p.id.indexOf('sys-') !== 0);
      if (match) {
        return match.id;
      }
      return '';
    }
    return place.id;
  }

  private async applySystemOverrides(): Promise<void> {
    if (!this.useRemote || !this.client) {
      return;
    }
    try {
      const responseText = await this.client.request(http.RequestMethod.GET, '/api/system-overrides');
      const response = JSON.parse(responseText) as SystemOverrideResponse;
      const overrides = response.overrides || [];
      if (overrides.length === 0) {
        return;
      }
      overrides.forEach((override) => {
        const match = this.places.find((place) => place.sourceKey === override.sourceKey);
        if (match) {
          if (override.name) {
            match.name = override.name;
          }
          if (override.description) {
            match.description = override.description;
          }
          if (override.imageUrl) {
            match.imageUrl = override.imageUrl;
          }
          match.updatedAt = Date.now();
        }
      });
    } catch (e) {
      // ignore
    }
  }

  private makeSourceKey(name: string, lat: number, lon: number): string {
    return `${name}-${lat.toFixed(6)}-${lon.toFixed(6)}`;
  }

  private normalizeSourceType(value?: string): '' | 'system' {
    return value === 'system' ? 'system' : '';
  }

  private parsePlaceWrapper(text: string): PlaceWrapperResponse | null {
    try {
      const response = JSON.parse(text) as PlaceWrapperResponse;
      if (!response || !response.place) {
        return null;
      }
      return response;
    } catch (e) {
      return null;
    }
  }

  private parsePlacesResponse(text: string): PlacesListResponse | null {
    try {
      const response = JSON.parse(text) as PlacesListResponse;
      return response;
    } catch (e) {
      return null;
    }
  }

  private isTypeEnabled(type: PlaceType, flags: PlaceTypeFlags): boolean {
    switch (type) {
      case 'water':
        return flags.water;
      case 'slippery':
        return flags.slippery;
      case 'danger':
        return flags.danger;
      default:
        return flags.normal;
    }
  }

  private mergePlace(place: Place): void {
    const index = this.places.findIndex((item) => item.id === place.id);
    if (index >= 0) {
      this.places[index] = place;
    } else {
      this.places.push(place);
    }

    // If this looks like a server-side system place (or at least has a stable sourceKey),
    // sync vote counts into the locally seeded sys-* POI.
    if (place.sourceKey) {
      for (let i = 0; i < this.places.length; i++) {
        const local = this.places[i];
        if (local.id && local.id.indexOf('sys-') === 0 && local.sourceType === 'system' && local.sourceKey === place.sourceKey) {
          const synced: Place = {
            id: local.id,
            name: local.name,
            description: local.description,
            lat: local.lat,
            lon: local.lon,
            type: local.type,
            ownerId: local.ownerId,
            ownerName: local.ownerName,
            status: local.status,
            createdAt: local.createdAt,
            updatedAt: place.updatedAt,
            likes: place.likes,
            dislikes: place.dislikes,
            hidden: local.hidden,
            imageUrl: local.imageUrl,
            sourceKey: local.sourceKey,
            sourceType: local.sourceType,
            sourcePlaceId: local.sourcePlaceId
          };
          this.places[i] = synced;
        }
      }
    }
  }
}
