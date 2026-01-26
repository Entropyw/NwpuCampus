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

interface HiddenPrefResponse {
  hiddenPlaceIds?: string[];
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
  private hiddenByUser: Map<string, Set<string>> = new Map();
  private hiddenLoadedFor: string = '';
  private hiddenLoadedAt: number = 0;

  enableRemote(baseUrl: string): void {
    this.client = new HttpClient(baseUrl);
    this.useRemote = true;
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
    await this.ensureHiddenLoaded(session);
    await this.applySystemOverrides();
    if (this.useRemote && this.client) {
      const merged = await this.fetchRemotePlaces(filter, session);
      if (merged.length > 0) {
        // Include local drafts/private places for current user even when remote data exists.
        const combined = this.filterPlaces(this.places, filter, session);
        return this.sortPlaces(combined, filter);
      }
    }
    const username = session ? session.username : '';
    const filtered = this.places.filter((place) => {
      if (this.isHiddenForUser(place.id, session) || place.hidden) {
        return false;
      }
      const isSystem = !place.ownerId;
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
        // fallback to local
      }
    }
    const status: PlaceStatus = input.status ? input.status : 'draft';
    const place: Place = {
      id: `p-${this.counter++}`,
      name: input.name.trim() || '未命名地点',
      description: input.description,
      lat: input.point.lat,
      lon: input.point.lon,
      type: input.type,
      ownerId: session.username,
      status,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      likes: 0,
      dislikes: 0,
      imageUrl: input.imageUrl,
      sourceKey: input.sourceKey || '',
      sourceType: this.normalizeSourceType(input.sourceType),
      sourcePlaceId: input.sourcePlaceId || ''
    };
    this.places.push(place);
    return place;
  }

  async updatePlace(placeId: string, input: UpdatePlaceInput, session: UserSession | null): Promise<Place | null> {
    if (!session) {
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
        // fallback to local
      }
    }
    const place = this.places.find((item) => item.id === placeId);
    if (!place) {
      return null;
    }
    place.name = input.name.trim() || place.name;
    place.description = input.description;
    place.lat = input.point.lat;
    place.lon = input.point.lon;
    place.type = input.type;
    place.imageUrl = input.imageUrl || '';
    if (input.status) {
      if (input.status === 'approved' && !session.isAdmin) {
        place.status = 'pending';
      } else {
        place.status = input.status;
      }
    }
    place.updatedAt = Date.now();
    return place;
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
      } catch (e) {
        // fallback to local
      }
    }
    place.status = 'pending';
    return true;
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
      } catch (e) {
        // fallback to local
      }
    }
    place.status = 'approved';
    return true;
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
      } catch (e) {
        // fallback to local
      }
    }
    place.status = 'rejected';
    return true;
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
    if (this.useRemote && this.client && session.token) {
      try {
        await this.client.request(http.RequestMethod.DELETE, `/api/places/${placeId}`, undefined, session.token);
      } catch (e) {
        // fallback to local
      }
    }
    this.places.splice(index, 1);
    return true;
  }

  async vote(placeId: string, delta: number, session: UserSession | null): Promise<boolean> {
    const place = this.places.find((item) => item.id === placeId);
    if (!place) {
      return false;
    }
    if (this.useRemote && this.client && session && session.token) {
      try {
  const payload: VoteRequest = new VoteRequest(delta);
  await this.client.request(http.RequestMethod.POST, `/api/places/${placeId}/vote`, payload, session.token);
      } catch (e) {
        // fallback to local
      }
    }
    if (delta > 0) {
      place.likes += 1;
    } else {
      place.dislikes += 1;
    }
    return true;
  }

  async toggleHidden(placeId: string, hidden: boolean, session: UserSession | null): Promise<boolean> {
    const place = this.places.find((item) => item.id === placeId);
    if (!place || !session) {
      return false;
    }
    if (this.useRemote && this.client && session.token) {
      try {
  const payload: HideRequest = new HideRequest(placeId, hidden);
  await this.client.request(http.RequestMethod.POST, '/api/preferences/hide', payload, session.token);
      } catch (e) {
        // fallback to local
      }
    }
    const key = session.username;
    const set = this.hiddenByUser.get(key) || new Set<string>();
    if (hidden) {
      set.add(placeId);
    } else {
      set.delete(placeId);
    }
    this.hiddenByUser.set(key, set);
    return true;
  }

  async reportFeedback(placeId: string, message: string, session: UserSession | null): Promise<boolean> {
    if (!session || !this.client || !this.useRemote || !session.token) {
      return false;
    }
    try {
  const payload: HttpRequestBody = new HttpRequestBody();
  payload.message = message;
      await this.client.request(http.RequestMethod.POST, `/api/places/${placeId}/feedback`, payload, session.token);
      return true;
    } catch (e) {
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
      const responseText = await this.client.request(http.RequestMethod.GET, '/api/places?scope=public');
      const publicResp = this.parsePlacesResponse(responseText);
      const publicPlaces = publicResp ? this.mapServerPlaces(publicResp.places) : [];
      const publicHazards = publicResp ? this.mapServerPlaces(publicResp.hazards) : [];
      results.push(...publicPlaces, ...publicHazards);
    } catch (e) {
      // ignore
    }
    if (session && session.token) {
      try {
        const responseText = await this.client.request(http.RequestMethod.GET, '/api/places?scope=mine', undefined, session.token);
        const mineResp = this.parsePlacesResponse(responseText);
        const minePlaces = mineResp ? this.mapServerPlaces(mineResp.places) : [];
        const pending = mineResp ? this.mapServerPlaces(mineResp.pending) : [];
        results.push(...minePlaces, ...pending);
      } catch (e) {
        // ignore
      }
    }

    if (results.length > 0) {
      results.forEach((place) => this.mergePlace(place));
      return this.filterPlaces(results, filter, session);
    }
    return [];
  }

  private filterPlaces(list: Array<Place>, filter: PlaceFilter, session: UserSession | null): Array<Place> {
    const username = session ? session.username : '';
    return list.filter((place) => {
      if (this.isHiddenForUser(place.id, session) || place.hidden) {
        return false;
      }
      const isSystem = !place.ownerId;
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
    return set ? set.has(placeId) : false;
  }

  isPlaceHidden(placeId: string, session: UserSession | null): boolean {
    return this.isHiddenForUser(placeId, session);
  }

  private async ensureHiddenLoaded(session: UserSession | null): Promise<void> {
    if (!session || !this.useRemote || !this.client || !session.token) {
      return;
    }
    const now = Date.now();
    if (this.hiddenLoadedFor === session.username && now - this.hiddenLoadedAt < 8000) {
      return;
    }
    try {
      const responseText = await this.client.request(http.RequestMethod.GET, '/api/preferences', undefined, session.token);
  const response = JSON.parse(responseText) as HiddenPrefResponse;
      const ids = response.hiddenPlaceIds || [];
      this.hiddenByUser.set(session.username, new Set(ids));
      this.hiddenLoadedFor = session.username;
      this.hiddenLoadedAt = now;
    } catch (e) {
      // ignore
    }
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
  }
}
