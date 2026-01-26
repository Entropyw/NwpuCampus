export interface LatLon {
  lat: number;
  lon: number;
}

export interface Point {
  x: number;
  y: number;
}

export interface Bounds {
  minLat: number;
  maxLat: number;
  minLon: number;
  maxLon: number;
}

export interface MapLabel {
  name: string;
  lat: number;
  lon: number;
  priority: number;
  kind?: string;
}

export interface MapWay {
  points: Array<LatLon>;
  type: string;
  name: string;
}

export interface RenderData {
  bounds: Bounds;
  roads: Array<MapWay>;
  buildings: Array<MapWay>;
  waters: Array<MapWay>;
  areas: Array<MapWay>;
  pitches: Array<MapWay>;
  labels: Array<MapLabel>;
}

export type PlaceType = 'normal' | 'water' | 'slippery' | 'danger';
export type PlaceStatus = 'draft' | 'private' | 'pending' | 'approved' | 'rejected' | 'published';
export interface Place {
  id: string;
  name: string;
  description?: string;
  lat: number;
  lon: number;
  type: PlaceType;
  ownerId?: string;
  ownerName?: string;
  status: PlaceStatus;
  createdAt: number;
  updatedAt?: number;
  likes: number;
  dislikes: number;
  hidden?: boolean;
  imageUrl?: string;
  sourceKey?: string;
  sourceType?: 'system' | '';
  sourcePlaceId?: string;
}

export interface UserSession {
  token: string;
  username: string;
  isAdmin: boolean;
}

export interface PlaceTypeFlags {
  normal: boolean;
  water: boolean;
  slippery: boolean;
  danger: boolean;
}

export interface PlaceFilter {
  showSystem: boolean;
  showPublic: boolean;
  showMine: boolean;
  types: PlaceTypeFlags;
  sortBy: 'time' | 'likes';
  avoidHazards: boolean;
}

export interface RouteState {
  start: LatLon;
  end: LatLon;
  path: Array<LatLon>;
}

export interface Marker {
  lat: number;
  lon: number;
  label?: string;
  kind?: string;
}
