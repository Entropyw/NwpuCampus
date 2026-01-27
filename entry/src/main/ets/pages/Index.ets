import common from '@ohos.app.ability.common';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import geoLocationManager from '@ohos.geoLocationManager';
import promptAction from '@ohos.promptAction';
import { MapCanvas } from '../components/MapCanvas';
import { LongPressHandler, MapEventBus, TapHandler, TransformHandler } from '../services/MapEventBus';
import { AuthService } from '../services/AuthService';
import { OsmParser } from '../services/OsmParser';
import { PlaceService, SaveDraftInput } from '../services/PlaceService';
import { RoutePlanner } from '../services/RoutePlanner';
import { LatLon, MapLabel, Marker, Place, PlaceFilter, PlaceType, PlaceTypeFlags, RenderData, RouteState, UserSession } from '../model/MapTypes';

interface PermissionRequestResult {
  authResults?: Array<number>;
}

interface AtManagerLike {
  requestPermissionsFromUser(ctx: common.UIAbilityContext, permissions: Array<string>): Promise<PermissionRequestResult | null>;
}

// Types for photo access helper (named interfaces to satisfy arkts linter)
interface PhotoSelectOptions {
  maxSelectNumber?: number;
}

interface PhotoSelectResult {
  photoUris?: Array<string>;
}

interface PhotoHelper {
  select?: (opts: PhotoSelectOptions) => Promise<PhotoSelectResult>;
}

interface PhotoAccessHelperModule {
  getPhotoAccessHelper?: (ctx: common.UIAbilityContext) => PhotoHelper;
}

// Use the shared SaveDraftInput from PlaceService to avoid structural-typing errors

interface FilterUpdate {
  showSystem?: boolean;
  showPublic?: boolean;
  showMine?: boolean;
  sortBy?: 'time' | 'likes';
  avoidHazards?: boolean;
}

class IndexTapHandler extends TapHandler {
  private host: Index;

  constructor(host: Index) {
    super();
    this.host = host;
  }

  onTap(point: LatLon): void {
    this.host.handleMapTap(point);
  }
}

class IndexTransformHandler extends TransformHandler {
  private host: Index;

  constructor(host: Index) {
    super();
    this.host = host;
  }

  onTransform(zoom: number, offsetX: number, offsetY: number): void {
    this.host.zoom = zoom;
    this.host.offsetX = offsetX;
    this.host.offsetY = offsetY;
  }
}

class IndexLongPressHandler extends LongPressHandler {
  private host: Index;

  constructor(host: Index) {
    super();
    this.host = host;
  }

  onLongPress(point: LatLon): void {
    this.host.handleMapLongPress(point);
  }
}

enum MapPickMode {
  None,
  Start,
  End
}

enum PageView {
  Map,
  SelectStart,
  SelectEnd,
  Profile,
  AddPlace
}

class LocationOption {
  name: string;
  lat: number;
  lon: number;
  source: string;
  placeId: string;
  status: string;
  likes: number;

  constructor(name: string, lat: number, lon: number, source: string, placeId: string, status: string, likes: number) {
    this.name = name;
    this.lat = lat;
    this.lon = lon;
    this.source = source;
    this.placeId = placeId;
    this.status = status;
    this.likes = likes;
  }
}

@Entry
@Component
struct Index {
  private startIndex: number = 0;
  private endIndex: number = 1;
  private useMockLocation: boolean = false;
  private locationUpdateIntervalId: number | null = null;
  private locationUpdateIntervalMs: number = 3000;

  private osmParser: OsmParser = new OsmParser();
  private placeService: PlaceService = new PlaceService();
  private authService: AuthService = new AuthService();
  private routePlanner: RoutePlanner = new RoutePlanner();
  private apiBase: string = 'http://121.36.80.168:8080';

  @State renderData: RenderData | null = null;
  @State labels: Array<MapLabel> = [];
  @State places: Array<Place> = [];
  @State pendingPlaces: Array<Place> = [];
  @State route: RouteState | null = null;
  @State selectedPoint: LatLon | null = null;
  @State myLocation: LatLon | null = null;
  @State zoom: number = 1;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State nightMode: boolean = false;
  @State hazardMode: boolean = false;
  @State currentPage: PageView = PageView.Map;
  @State selectionQuery: string = '';
  @State routeStart: LatLon | null = null;
  @State routeEnd: LatLon | null = null;
  @State routeStartLabel: string = '';
  @State routeEndLabel: string = '';
  @State pickMode: MapPickMode = MapPickMode.None;
  @State tapActionVisible: boolean = false;
  @State tapPlace: Place | null = null;
  @State tapLocation: LatLon | null = null;
  @State profileNickname: string = '';
  @State profileAvatarUrl: string = '';
  @State profileOldPassword: string = '';
  @State profileNewPassword: string = '';
  @State authStatus: string = '未登录';
  @State authError: string = '';
  @State username: string = '';
  @State password: string = '';
  @State placeName: string = '';
  @State placeDesc: string = '';
  @State placeImage: string = '';
  @State placeType: PlaceType = 'normal';
  @State filter: PlaceFilter = this.createDefaultFilter();
  @State editingPlaceId: string = '';
  @State editingSourceKey: string = '';
  @State editingSourceType: string = '';
  @State editingSourcePlaceId: string = '';
  @State showUi: boolean = true;
  @State routeVisible: boolean = false;

  private poiFallback: Array<MapLabel> = this.buildFallbackLabels();
  private savedFilter: PlaceFilter | null = null;
  private lastLocation: LatLon | null = null;
  private lastHazardAlertAt: number = 0;

  // handlers bound at runtime so we can unregister them cleanly
  private __mapTapHandler: TapHandler | null = null;
  private __mapTransformHandler: TransformHandler | null = null;
  private __mapLongPressHandler: LongPressHandler | null = null;

  aboutToAppear(): void {
    this.placeService.enableRemote(this.apiBase);
    this.authService.enableRemote(this.apiBase);
    this.loadMap();
    this.initMyLocation();
    this.startLocationUpdates();
    // register map event handlers
    this.__mapTapHandler = new IndexTapHandler(this);
    MapEventBus.registerTapHandler(this.__mapTapHandler);

    this.__mapTransformHandler = new IndexTransformHandler(this);
    MapEventBus.registerTransformHandler(this.__mapTransformHandler);

    this.__mapLongPressHandler = new IndexLongPressHandler(this);
    MapEventBus.registerLongPressHandler(this.__mapLongPressHandler);
  }

  aboutToDisappear(): void {
    this.stopLocationUpdates();
    // unregister map event handlers
    if (this.__mapTapHandler) {
      MapEventBus.unregisterTapHandler(this.__mapTapHandler);
      this.__mapTapHandler = null;
    }
    if (this.__mapTransformHandler) {
      MapEventBus.unregisterTransformHandler(this.__mapTransformHandler);
      this.__mapTransformHandler = null;
    }
    if (this.__mapLongPressHandler) {
      MapEventBus.unregisterLongPressHandler(this.__mapLongPressHandler);
      this.__mapLongPressHandler = null;
    }
  }

  private async loadMap(): Promise<void> {
    try {
      const context = this.getHostContext();
      const buffer: ArrayBuffer | Uint8Array | string = await context.resourceManager.getRawFileContent('map.osm');
      let osmText: string = '';
      if (typeof buffer === 'string') {
        osmText = buffer;
      } else if (buffer instanceof ArrayBuffer) {
        osmText = this.utf8ArrayToStr(new Uint8Array(buffer));
      } else if (buffer instanceof Uint8Array) {
        osmText = this.utf8ArrayToStr(buffer as Uint8Array);
      } else if (Array.isArray(buffer)) {
        osmText = this.utf8ArrayToStr(new Uint8Array(buffer as number[]));
      } else {
        osmText = String(buffer);
      }
      const parsed = this.osmParser.parse(osmText);
      this.renderData = parsed;
      this.labels = parsed.labels.length ? parsed.labels : this.poiFallback;
      if (!this.routeStartLabel && this.labels.length > 0) {
        this.routeStartLabel = this.labels[0].name;
      }
      if (!this.routeEndLabel && this.labels.length > 1) {
        this.routeEndLabel = this.labels[1].name;
      }
      this.placeService.seedSystemPlaces(this.labels);
      this.refreshPlaces();
    } catch (error) {
      console.error(`OSM 读取失败: ${String(error)}`);
    }
  }


  // UTF-8 decoder for ArrayBuffer/Uint8Array -> string (avoids depending on TextDecoder/util)
  private utf8ArrayToStr(bytes: Uint8Array): string {
    let out = '';
    let i = 0;
    while (i < bytes.length) {
      const c = bytes[i++];
      if (c < 0x80) {
        out += String.fromCharCode(c);
      } else if (c >= 0xc0 && c < 0xe0) {
        const c2 = bytes[i++];
        out += String.fromCharCode(((c & 0x1f) << 6) | (c2 & 0x3f));
      } else if (c >= 0xe0 && c < 0xf0) {
        const c2 = bytes[i++];
        const c3 = bytes[i++];
        out += String.fromCharCode(((c & 0x0f) << 12) | ((c2 & 0x3f) << 6) | (c3 & 0x3f));
      } else {
        // 4-byte UTF-8 -> surrogate pair
        const c2 = bytes[i++];
        const c3 = bytes[i++];
        const c4 = bytes[i++];
        let codepoint = ((c & 0x07) << 18) | ((c2 & 0x3f) << 12) | ((c3 & 0x3f) << 6) | (c4 & 0x3f);
        codepoint -= 0x10000;
        out += String.fromCharCode((codepoint >> 10) + 0xd800);
        out += String.fromCharCode((codepoint & 0x3ff) + 0xdc00);
      }
    }
    return out;
  }

  private cycleStart(): void {
    this.routeStart = null;
    const combined = this.getPoiCandidates();
    this.startIndex = (this.startIndex + 1) % combined.length;
    if (this.startIndex === this.endIndex) {
      this.endIndex = (this.endIndex + 1) % combined.length;
    }
    if (combined.length > 0) {
      const start = combined[this.startIndex] || combined[0];
      this.routeStartLabel = start ? start.name : '';
    }
    this.invalidateRoute();
  }

  private cycleEnd(): void {
    this.routeEnd = null;
    const combined = this.getPoiCandidates();
    this.endIndex = (this.endIndex + 1) % combined.length;
    if (this.endIndex === this.startIndex) {
      this.startIndex = (this.startIndex + 1) % combined.length;
    }
    if (combined.length > 0) {
      const end = combined[this.endIndex] || combined[1] || combined[0];
      this.routeEndLabel = end ? end.name : '';
    }
    this.invalidateRoute();
  }

  private getPoiCandidates(): Array<MapLabel> {
    if (this.labels.length) {
      return this.labels;
    }
    return this.poiFallback;
  }

  private sendMyLocation(lat: number, lon: number): void {
    const loc: LatLon = { lat, lon };
    this.myLocation = loc;
    this.checkHazardProximity(loc);
    this.lastLocation = loc;
  }

  private getCampusCenter(): LatLon {
    let sumLat = 0;
    let sumLon = 0;
    const list = this.getPoiCandidates();
    for (let i = 0; i < list.length; i++) {
      sumLat += list[i].lat;
      sumLon += list[i].lon;
    }
    const count = list.length > 0 ? list.length : 1;
    const center: LatLon = { lat: sumLat / count, lon: sumLon / count };
    return center;
  }

  private generateMockLocation(): LatLon {
    const center = this.getCampusCenter();
    const radiusMeters = 500;
    const angle = Math.random() * Math.PI * 2;
    const dist = Math.sqrt(Math.random()) * radiusMeters;
    const metersPerDegLat = 111320;
    const metersPerDegLon = metersPerDegLat * Math.cos(center.lat * Math.PI / 180);
    const deltaLat = (Math.cos(angle) * dist) / metersPerDegLat;
    const deltaLon = (Math.sin(angle) * dist) / metersPerDegLon;
    const mockLoc: LatLon = { lat: center.lat + deltaLat, lon: center.lon + deltaLon };
    return mockLoc;
  }

  private async requestLocationPermission(): Promise<boolean> {
    try {
      const context = this.getHostContext();
      const atManager = abilityAccessCtrl.createAtManager();
  // Use explicit types and a small adapter interface so we don't rely on any/unknown.
  const permissions: Array<string> = ['ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION'];
  const rawResult = await (atManager as AtManagerLike).requestPermissionsFromUser(context, permissions);
  const result: PermissionRequestResult | null = rawResult as PermissionRequestResult | null;
  const authResults: Array<number> = result && result.authResults ? result.authResults : [];
      if (authResults.length === 0) {
        return false;
      }
      for (let i = 0; i < authResults.length; i++) {
        if (authResults[i] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          return false;
        }
      }
      return true;
    } catch (error) {
      console.error(`请求定位权限失败: ${String(error)}`);
      return false;
    }
  }

  private async getRealLocation(): Promise<geoLocationManager.Location | null> {
    try {
      const location = await geoLocationManager.getCurrentLocation();
      return location as geoLocationManager.Location;
    } catch (error) {
      console.error(`获取真实定位失败: ${String(error)}`);
      return null;
    }
  }

  private async initMyLocation(): Promise<void> {
    if (this.useMockLocation) {
      const mock = this.generateMockLocation();
      this.sendMyLocation(mock.lat, mock.lon);
      return;
    }
    const granted = await this.requestLocationPermission();
    if (!granted) {
      console.warn('定位权限未授予，无法获取真实位置');
      return;
    }
    const real = await this.getRealLocation();
    if (real) {
      this.sendMyLocation(real.latitude, real.longitude);
    }
  }

  /**
   * Start periodic location updates. Uses mock generator in emulator mode,
   * or polls `getCurrentLocation()` when running on a real device.
   * This uses polling so it works even if the exact SDK location subscription API
   * differs across platform versions.
   */
  private startLocationUpdates(intervalMs?: number): void {
    if (this.locationUpdateIntervalId != null) {
      // already running
      return;
    }
    const ms = intervalMs && intervalMs > 0 ? intervalMs : this.locationUpdateIntervalMs;

    if (this.useMockLocation) {
      const sendMock = (): void => {
        try {
          const mock = this.generateMockLocation();
          this.sendMyLocation(mock.lat, mock.lon);
        } catch (e) {
          console.error('发送模拟位置失败', e);
        }
      };
      sendMock();
      this.locationUpdateIntervalId = Number(setInterval(() => sendMock(), ms));
      return;
    }

    // Real device: poll getCurrentLocation with async wrapper
    const pollOnce = async (): Promise<void> => {
      try {
        const granted = await this.requestLocationPermission();
        if (!granted) {
          console.warn('定位权限未授予，停止定位更新');
          this.stopLocationUpdates();
          return;
        }
        const real = await this.getRealLocation();
        if (real) {
          this.sendMyLocation(real.latitude, real.longitude);
        }
      } catch (e) {
        console.error('轮询位置失败', e);
      }
    };

    // run once immediately, then schedule
    pollOnce();
    this.locationUpdateIntervalId = Number(setInterval(() => { pollOnce(); }, ms));
  }

  private stopLocationUpdates(): void {
    if (this.locationUpdateIntervalId != null) {
      try {
        clearInterval(this.locationUpdateIntervalId as number);
      } catch (e) {
        // ignore
      }
      this.locationUpdateIntervalId = null;
    }
  }

  private invalidateRoute(): void {
    this.routeVisible = false;
    this.route = null;
  }

  private planRoute(): boolean {
    this.routeVisible = false;
    this.route = null;
    const combined = this.getPoiCandidates();
    let startPoint: LatLon | null = this.routeStart;
    let endPoint: LatLon | null = this.routeEnd;
    if (!startPoint) {
      const start = combined[this.startIndex] || combined[0];
      if (start) {
        startPoint = { lat: start.lat, lon: start.lon };
        this.routeStartLabel = this.routeStartLabel ? this.routeStartLabel : start.name;
      }
    }
    if (!endPoint) {
      const end = combined[this.endIndex] || combined[1] || combined[0];
      if (end) {
        endPoint = { lat: end.lat, lon: end.lon };
        this.routeEndLabel = this.routeEndLabel ? this.routeEndLabel : end.name;
      }
    }
    if (!startPoint || !endPoint) {
      return false;
    }
    const nextRoute = this.routePlanner.buildRoute(startPoint, endPoint, this.renderData);
    if (!nextRoute.path || nextRoute.path.length < 2) {
      // fallback: draw straight line to avoid false “invalid” when道路图缺失
      const fallback: RouteState = { start: startPoint, end: endPoint, path: [startPoint, endPoint] };
      this.route = fallback;
      this.routeVisible = true;
      return true;
    }
    this.route = nextRoute;
    this.routeVisible = true;
    return true;
  }

  private handlePlanRouteClick(): void {
    const ok = this.planRoute();
    if (!ok) {
      promptAction.showToast({ message: '请先选择有效的起终点', duration: 1300 });
    }
  }

  handleMapTap(point: LatLon): void {
    this.selectedPoint = point;
    if (this.currentPage !== PageView.Map) {
      return;
    }
    if (this.pickMode === MapPickMode.Start) {
      this.routeStart = point;
      this.routeStartLabel = '地图点';
      this.pickMode = MapPickMode.None;
      this.invalidateRoute();
      return;
    }
    if (this.pickMode === MapPickMode.End) {
      this.routeEnd = point;
      this.routeEndLabel = '地图点';
      this.pickMode = MapPickMode.None;
      this.invalidateRoute();
      return;
    }
    const place = this.findNearestPlace(point);
    if (!place) {
      this.tapActionVisible = false;
      return;
    }
    this.tapPlace = place;
    this.tapLocation = point;
    this.tapActionVisible = true;
  }

  handleMapLongPress(point: LatLon): void {
    this.selectedPoint = point;
    if (this.currentPage !== PageView.Map) {
      return;
    }
    const place = this.findNearestPlace(point);
    if (!place) {
      this.tapPlace = null;
      this.tapLocation = point;
      this.tapActionVisible = true;
      return;
    }
    this.tapPlace = place;
    this.tapLocation = point;
    this.tapActionVisible = true;
  }

  private normalizeText(text: string): string {
    return text.trim().toLowerCase();
  }

  private distanceMeters(a: LatLon, b: LatLon): number {
    const metersPerDegLat = 111320;
    const metersPerDegLon = metersPerDegLat * Math.cos(a.lat * Math.PI / 180);
    const dLat = (a.lat - b.lat) * metersPerDegLat;
    const dLon = (a.lon - b.lon) * metersPerDegLon;
    return Math.sqrt(dLat * dLat + dLon * dLon);
  }

  private checkHazardProximity(current: LatLon): void {
    if (!this.hazardMode && !this.filter.avoidHazards) {
      return;
    }
    const now = Date.now();
    if (now - this.lastHazardAlertAt < 5000) {
      return;
    }
    const metersPerDegLat = 111320;
    const metersPerDegLon = metersPerDegLat * Math.cos(current.lat * Math.PI / 180);
    const last = this.lastLocation;
    const moveX = last ? (current.lon - last.lon) * metersPerDegLon : 0;
    const moveY = last ? (current.lat - last.lat) * metersPerDegLat : 0;
    const hasDirection = Math.abs(moveX) + Math.abs(moveY) > 0.5;
    for (const place of this.places) {
      if (place.type !== 'water') {
        continue;
      }
      const dx = (place.lon - current.lon) * metersPerDegLon;
      const dy = (place.lat - current.lat) * metersPerDegLat;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist > 5) {
        continue;
      }
      if (hasDirection) {
        const dot = dx * moveX + dy * moveY;
        if (dot <= 0) {
          continue;
        }
      }
      this.lastHazardAlertAt = now;
      promptAction.showToast({ message: '前方5米内有水雷，请注意脚下', duration: 2000 });
      return;
    }
  }

  private findNearestPlace(point: LatLon): Place | null {
    let nearest: Place | null = null;
    let best = 999999;
    for (const place of this.places) {
      const dist = this.distanceMeters(point, { lat: place.lat, lon: place.lon });
      if (dist < best) {
        best = dist;
        nearest = place;
      }
    }
    // 30m threshold for a tap to be considered “on a place”
    if (best <= 30) {
      return nearest;
    }
    return null;
  }

  private closeTapAction(): void {
    this.tapActionVisible = false;
    this.tapPlace = null;
    this.tapLocation = null;
  }

  private openSelectionPage(mode: MapPickMode): void {
    this.selectionQuery = '';
    this.tapActionVisible = false;
    if (mode === MapPickMode.Start) {
      this.currentPage = PageView.SelectStart;
    } else {
      this.currentPage = PageView.SelectEnd;
    }
  }

  private isAdmin(): boolean {
    const session = this.getSession();
    return session ? session.isAdmin : false;
  }

  private isMinePlace(place: Place): boolean {
    const session = this.getSession();
    return session ? place.ownerId === session.username : false;
  }

  private clearEditingState(): void {
    this.editingPlaceId = '';
    this.editingSourceKey = '';
    this.editingSourceType = '';
    this.editingSourcePlaceId = '';
  }

  private buildSourceKey(name: string, lat: number, lon: number): string {
    return `${name}-${lat.toFixed(6)}-${lon.toFixed(6)}`;
  }

  private openEditPlace(place: Place, override: boolean): void {
    this.selectedPoint = { lat: place.lat, lon: place.lon };
    this.placeName = place.name;
    this.placeDesc = place.description || '';
    this.placeImage = place.imageUrl || '';
    this.placeType = place.type;
    if (override) {
      this.editingPlaceId = '';
      this.editingSourceKey = place.sourceKey || this.buildSourceKey(place.name, place.lat, place.lon);
      this.editingSourceType = place.sourceType === 'system' || !place.ownerId ? 'system' : 'place';
      this.editingSourcePlaceId = place.id;
    } else {
      this.editingPlaceId = place.id;
      this.editingSourceKey = '';
      this.editingSourceType = '';
      this.editingSourcePlaceId = '';
    }
    this.tapActionVisible = false;
    this.currentPage = PageView.AddPlace;
  }

  private isPlaceHidden(placeId: string): boolean {
    return this.placeService.isPlaceHidden(placeId, this.getSession());
  }

  private buildLocationOptions(): Array<LocationOption> {
    const list: Array<LocationOption> = [];
    for (const label of this.getPoiCandidates()) {
      list.push(new LocationOption(label.name, label.lat, label.lon, '系统地点', '', 'system', 0));
    }
    for (const place of this.places) {
      list.push(new LocationOption(place.name, place.lat, place.lon, '自定义', place.id, place.status, place.likes));
    }
    return list;
  }

  private filterLocationOptions(options: Array<LocationOption>, query: string): Array<LocationOption> {
    const target = this.normalizeText(query);
    if (!target) {
      return options;
    }
    return options.filter((item) => this.normalizeText(item.name).indexOf(target) >= 0);
  }

  private selectLocation(option: LocationOption): void {
    const point: LatLon = { lat: option.lat, lon: option.lon };
    if (this.currentPage === PageView.SelectStart) {
      this.routeStart = point;
      this.routeStartLabel = option.name;
    } else if (this.currentPage === PageView.SelectEnd) {
      this.routeEnd = point;
      this.routeEndLabel = option.name;
    }
    this.currentPage = PageView.Map;
    this.pickMode = MapPickMode.None;
    this.invalidateRoute();
  }

  private toggleNightMode(): void {
    this.nightMode = !this.nightMode;
  }

  private toggleHazardMode(): void {
    if (!this.hazardMode) {
      this.savedFilter = this.cloneFilter(this.filter);
      const nextTypes: PlaceTypeFlags = {
        normal: false,
        water: true,
        slippery: false,
        danger: false
      };
      const next: PlaceFilter = {
        showSystem: true,
        showPublic: true,
        showMine: true,
        types: nextTypes,
        sortBy: 'time',
        avoidHazards: false
      };
      this.filter = next;
      this.hazardMode = true;
    } else {
      if (this.savedFilter) {
        this.filter = this.savedFilter;
      }
      this.hazardMode = false;
    }
    this.refreshPlaces();
    this.invalidateRoute();
  }

  private cloneFilter(filter: PlaceFilter): PlaceFilter {
    const types: PlaceTypeFlags = this.cloneTypeFlags(filter.types);
    const next: PlaceFilter = {
      showSystem: filter.showSystem,
      showPublic: filter.showPublic,
      showMine: filter.showMine,
      types,
      sortBy: filter.sortBy,
      avoidHazards: filter.avoidHazards
    };
    return next;
  }

  private async refreshPlaces(): Promise<void> {
    const session = this.authService.getSession();
    this.places = await this.placeService.list(this.filter, session);
    this.pendingPlaces = await this.placeService.listPending(session);
  }

  private async handleLogin(): Promise<void> {
    const session = await this.authService.login(this.username, this.password);
    if (session) {
      this.authError = '';
      this.updateSessionStatus(session);
    } else {
      this.authError = this.authService.getLastError() || '登录失败';
      this.updateSessionStatus(null);
    }
  }

  private async handleRegister(): Promise<void> {
    const session = await this.authService.register(this.username, this.password);
    if (session) {
      this.authError = '';
      this.updateSessionStatus(session);
    } else {
      this.authError = this.authService.getLastError() || '注册失败';
      this.updateSessionStatus(null);
    }
  }

  private handleLogout(): void {
    this.authService.logout();
    this.authError = '';
    this.updateSessionStatus(null);
  }

  private updateSessionStatus(session: UserSession | null): void {
    if (session) {
      this.authStatus = `已登录：${session.username}` + (session.isAdmin ? '（管理员）' : '');
      this.profileNickname = session.username;
    } else {
      this.authStatus = '未登录';
      this.profileNickname = '';
      this.profileAvatarUrl = '';
    }
    this.refreshPlaces();
  }

  private cyclePlaceType(): void {
    const types: Array<PlaceType> = ['normal', 'water', 'slippery', 'danger'];
    const index = types.indexOf(this.placeType);
    const next = (index + 1) % types.length;
    this.placeType = types[next];
  }

  private async handleSavePlace(publish: boolean): Promise<void> {
    const session = this.authService.getSession();
    if (!session) {
      promptAction.showToast({ message: '请先登录再保存地点', duration: 1500 });
      return;
    }
    const point = this.selectedPoint || this.myLocation || this.getCampusCenter();
    const isAdmin = session ? session.isAdmin : false;
    if (this.editingPlaceId) {
      const status = publish ? (isAdmin ? 'approved' : 'approved') : 'private';
      await this.placeService.updatePlace(this.editingPlaceId, {
        name: this.placeName,
        description: this.placeDesc,
        type: this.placeType,
        imageUrl: this.placeImage,
        point,
        status
      }, session);
    } else {
      const status = publish
        ? (isAdmin && this.editingSourceType === 'system' ? 'pending' : (isAdmin ? 'approved' : 'private'))
        : 'private';
      const input: SaveDraftInput = {
        name: this.placeName,
        description: this.placeDesc,
        type: this.placeType,
        imageUrl: this.placeImage,
        point,
        sourceKey: this.editingSourceKey || undefined,
        sourceType: this.editingSourceType || undefined,
        sourcePlaceId: this.editingSourcePlaceId || undefined,
        status
      };
      const place = await this.placeService.saveDraft(input, session);
      if (place && publish) {
        if (isAdmin && this.editingSourceType === 'system') {
          await this.placeService.approve(place.id, session);
        } else if (!isAdmin) {
          await this.placeService.publish(place.id, session);
        }
      }
    }
    this.placeName = '';
    this.placeDesc = '';
    this.placeImage = '';
    this.clearEditingState();
    await this.refreshPlaces();
  }

  private async pickLocalImage(): Promise<void> {
    try {
      // Local photo picker is SDK-specific and may not be available on all
      // targets. For broad compatibility we provide no-op fallback here.
      // Implement a platform-specific picker when targeting newer SDKs.
      console.info('本平台不支持本地相册选择（占位），请在设备上使用 URL 或升级 SDK');
    } catch (error) {
      console.error('选择图片失败', error);
    }
  }

  private async handlePublish(placeId: string): Promise<void> {
    await this.placeService.publish(placeId, this.authService.getSession());
    await this.refreshPlaces();
  }

  private async handleDelete(placeId: string): Promise<void> {
    await this.placeService.delete(placeId, this.authService.getSession());
    await this.refreshPlaces();
  }

  private async handleToggleHidden(placeId: string, hidden: boolean): Promise<void> {
    const session = this.authService.getSession();
    if (!session) {
      promptAction.showToast({ message: '请先登录再隐藏地点', duration: 1500 });
      return;
    }
    await this.placeService.toggleHidden(placeId, hidden, session);
    await this.refreshPlaces();
  }

  private async handleVote(placeId: string, delta: number): Promise<void> {
    await this.placeService.vote(placeId, delta, this.authService.getSession());
    await this.refreshPlaces();
  }

  private async handleFeedback(placeId: string): Promise<void> {
    const session = this.authService.getSession();
    if (!session) {
      promptAction.showToast({ message: '请先登录再提交反馈', duration: 1500 });
      return;
    }
    const ok = await this.placeService.reportFeedback(placeId, '地点信息有误，请管理员核实', session);
    if (ok) {
      promptAction.showToast({ message: '已提交反馈', duration: 1500 });
    }
  }

  private async handleApprove(placeId: string): Promise<void> {
    await this.placeService.approve(placeId, this.authService.getSession());
    await this.refreshPlaces();
  }

  private async handleReject(placeId: string): Promise<void> {
    await this.placeService.reject(placeId, this.authService.getSession());
    await this.refreshPlaces();
  }

  private updateFilter(partial: FilterUpdate): void {
    const nextTypes = this.cloneTypeFlags(this.filter.types);
    const next: PlaceFilter = {
      showSystem: this.filter.showSystem,
      showPublic: this.filter.showPublic,
      showMine: this.filter.showMine,
      types: nextTypes,
      sortBy: this.filter.sortBy,
      avoidHazards: this.filter.avoidHazards
    };
    if (partial.showSystem !== undefined) {
      next.showSystem = partial.showSystem;
    }
    if (partial.showPublic !== undefined) {
      next.showPublic = partial.showPublic;
    }
    if (partial.showMine !== undefined) {
      next.showMine = partial.showMine;
    }
    if (partial.sortBy) {
      next.sortBy = partial.sortBy;
    }
    if (partial.avoidHazards !== undefined) {
      next.avoidHazards = partial.avoidHazards;
    }
    this.filter = next;
    this.refreshPlaces();
    if (partial.avoidHazards !== undefined) {
      this.invalidateRoute();
    }
  }

  private updateFilterType(type: PlaceType, value: boolean): void {
    const nextTypes = this.cloneTypeFlags(this.filter.types);
    switch (type) {
      case 'water':
        nextTypes.water = value;
        break;
      case 'slippery':
        nextTypes.slippery = value;
        break;
      case 'danger':
        nextTypes.danger = value;
        break;
      default:
        nextTypes.normal = value;
        break;
    }
    const next: PlaceFilter = {
      showSystem: this.filter.showSystem,
      showPublic: this.filter.showPublic,
      showMine: this.filter.showMine,
      types: nextTypes,
      sortBy: this.filter.sortBy,
      avoidHazards: this.filter.avoidHazards
    };
    this.filter = next;
    this.refreshPlaces();
    if (this.filter.avoidHazards) {
      this.invalidateRoute();
    }
  }

  private cloneTypeFlags(flags: PlaceTypeFlags): PlaceTypeFlags {
    const copy: PlaceTypeFlags = {
      normal: flags.normal,
      water: flags.water,
      slippery: flags.slippery,
      danger: flags.danger
    };
    return copy;
  }

  private createDefaultFilter(): PlaceFilter {
    const types: PlaceTypeFlags = { normal: true, water: true, slippery: true, danger: true };
    const filter: PlaceFilter = {
      showSystem: true,
      showPublic: true,
      showMine: true,
      types,
      sortBy: 'time',
      avoidHazards: false
    };
    return filter;
  }

  private buildFallbackLabels(): Array<MapLabel> {
    const list: Array<MapLabel> = [];
    list.push(this.createLabel('东门', 34.03204, 108.76465));
    list.push(this.createLabel('西门', 34.02023, 108.75439));
    list.push(this.createLabel('南门', 34.02519, 108.76427));
    list.push(this.createLabel('北门', 34.03922, 108.75466));
    list.push(this.createLabel('图书馆', 34.03169, 108.76358));
    list.push(this.createLabel('一号教学楼', 34.02969, 108.76369));
    list.push(this.createLabel('宿舍区', 34.02925, 108.76286));
    list.push(this.createLabel('体育场', 34.03299, 108.75783));
    return list;
  }

  private createLabel(name: string, lat: number, lon: number): MapLabel {
    const label: MapLabel = { name, lat, lon, priority: 1 };
    return label;
  }

  private getHostContext(): common.UIAbilityContext {
    // Use legacy getContext() for broader SDK compatibility (avoid getUIContext/getHostContext which require newer SDKs)
    return getContext() as common.UIAbilityContext;
  }

  // Helper to safely get current session (avoids declaring locals inside @Builder)
  private getSession(): UserSession | null {
    return this.authService.getSession();
  }

  private getMyPlaces(): Array<Place> {
    const s = this.getSession();
    if (!s) {
      return [];
    }
    return this.places.filter((p: Place) => p.ownerId === s.username && (p.status === 'approved' || p.status === 'published'));
  }

  private getSelectedPoint(): LatLon | null {
    return this.selectedPoint || this.myLocation || null;
  }

  private renderPlaceTypeLabel(type: PlaceType): string {
    switch (type) {
      case 'water':
        return '水雷';
      case 'slippery':
        return '易滑';
      case 'danger':
        return '危险';
      default:
        return '普通';
    }
  }

  private renderPlaceStatus(status: string): string {
    switch (status) {
      case 'pending':
        return '待审核';
      case 'approved':
      case 'published':
        return '已发布';
      case 'private':
      case 'draft':
        return '草稿';
      case 'rejected':
        return '已拒绝';
      default:
        return '未知';
    }
  }

  private buildRouteMarkers(): Array<Marker> {
    const markers: Array<Marker> = [];
    if (this.route) {
      const startMarker: Marker = { lat: this.route.start.lat, lon: this.route.start.lon, label: '起点' };
      const endMarker: Marker = { lat: this.route.end.lat, lon: this.route.end.lon, label: '终点' };
      markers.push(startMarker);
      markers.push(endMarker);
      return markers;
    }
    if (this.routeStart) {
      markers.push({ lat: this.routeStart.lat, lon: this.routeStart.lon, label: '起点' });
    }
    if (this.routeEnd) {
      markers.push({ lat: this.routeEnd.lat, lon: this.routeEnd.lon, label: '终点' });
    }
    return markers;
  }

  @Builder
  private buildSearchBar(title: string, value: string, isStart: boolean): void {
    Row() {
      Text(title).fontSize(12).fontColor(this.nightMode ? '#c7d2e6' : '#7c8699');
      Text(value ? value : (isStart ? '请选择起点' : '请选择终点'))
        .fontSize(15)
        .fontColor(this.nightMode ? '#ffffff' : '#222f3d')
        .margin({ left: 8 });
    }
    .padding(12)
    .backgroundColor(this.nightMode ? 'rgba(20, 32, 54, 0.85)' : 'rgba(255, 255, 255, 0.95)')
    .borderRadius(10)
    .width('100%')
    .onClick(() => {
      if (isStart) {
        this.openSelectionPage(MapPickMode.Start);
      } else {
        this.openSelectionPage(MapPickMode.End);
      }
    });
  }

  @Builder
  private buildAvatarButton(): void {
    Stack() {
      if (this.profileAvatarUrl) {
        Image(this.profileAvatarUrl).width('100%').height('100%').borderRadius(22);
      } else {
        Text(this.authService.getSession() ? '我' : '游客')
          .fontSize(13)
          .fontColor('#ffffff');
      }
    }
    .width(40)
    .height(40)
    .backgroundColor(this.authService.getSession() ? '#4f79ff' : '#8a93a5')
    .borderRadius(20)
    .onClick(() => {
      this.currentPage = PageView.Profile;
    });
  }

  @Builder
  private buildMapPage(): void {
    Stack() {
      MapCanvas({
        renderData: this.renderData,
        route: this.routeVisible ? this.route : null,
        markers: this.buildRouteMarkers(),
        places: this.places,
        currentUser: this.getSession() ? this.getSession()!.username : '',
        filter: this.filter,
        myLocation: this.myLocation,
        zoom: this.zoom,
        offsetX: this.offsetX,
        offsetY: this.offsetY,
        nightMode: this.nightMode
      })
        .width('100%')
        .height('100%');

        Column() {
          if (this.showUi) {
            Column({ space: 10 }) {
              Row() {
                Column({ space: 6 }) {
                  this.buildSearchBar('起点', this.routeStartLabel, true);
                  this.buildSearchBar('终点', this.routeEndLabel, false);
                }
                .layoutWeight(1)
                .margin({ right: 8 });

                Column({ space: 8 }) {
                  Button(this.nightMode ? '日间' : '夜间')
                    .onClick(() => this.toggleNightMode())
                    .fontSize(12)
                    .width(64)
                    .height(32);
                  Button('规划路线')
                    .fontSize(12)
                    .width(64)
                    .height(32)
                    .backgroundColor('#4f79ff')
                    .fontColor('#ffffff')
                    .onClick(() => this.handlePlanRouteClick());
                  this.buildAvatarButton();
                }
              }

              Column({ space: 6 }) {
                Row() {
                  Button(this.filter.showSystem ? '系统✓' : '系统')
                    .fontSize(11)
                    .height(26)
                    .onClick(() => this.updateFilter({ showSystem: !this.filter.showSystem }));
                  Button(this.filter.showPublic ? '公共✓' : '公共')
                    .fontSize(11)
                    .height(26)
                    .onClick(() => this.updateFilter({ showPublic: !this.filter.showPublic }));
                  Button(this.filter.showMine ? '我的✓' : '我的')
                    .fontSize(11)
                    .height(26)
                    .onClick(() => this.updateFilter({ showMine: !this.filter.showMine }));
                }
                .justifyContent(FlexAlign.SpaceBetween)
                .width('100%');

                Row() {
                  Button(this.filter.sortBy === 'time' ? '时间✓' : '时间')
                    .fontSize(11)
                    .height(26)
                    .onClick(() => this.updateFilter({ sortBy: 'time' }));
                  Button(this.filter.sortBy === 'likes' ? '点赞✓' : '点赞')
                    .fontSize(11)
                    .height(26)
                    .onClick(() => this.updateFilter({ sortBy: 'likes' }));
                  Button(this.filter.avoidHazards ? '避开水雷✓' : '避开水雷')
                    .fontSize(11)
                    .height(26)
                    .onClick(() => this.updateFilter({ avoidHazards: !this.filter.avoidHazards }));
                }
                .justifyContent(FlexAlign.SpaceBetween)
                .width('100%');
              }
            }
            .padding({ left: 12, right: 12, top: 12, bottom: 10 })
            .backgroundColor(this.nightMode ? 'rgba(12, 20, 36, 0.72)' : 'rgba(255, 255, 255, 0.9)')
            .borderRadius(12)
            .width('100%')
            .hitTestBehavior(HitTestMode.Default)
            .zIndex(3);
          }

          Column() {
              if (this.showUi && this.tapActionVisible) {
                Column() {
                  if (this.tapPlace) {
                    Text(this.tapPlace.name).fontSize(14).fontWeight(FontWeight.Bold);
                    Text(this.renderPlaceTypeLabel(this.tapPlace.type) + ' · ' + this.renderPlaceStatus(this.tapPlace.status))
                      .fontSize(11)
                      .fontColor('#7c8699');
                    Text('👍 ' + String(this.tapPlace.likes) + ' / 👎 ' + String(this.tapPlace.dislikes))
                      .fontSize(11)
                      .fontColor('#7c8699');
                    Row() {
                      if (this.tapPlace.ownerId) {
                        Button('👍').onClick(() => { this.handleVote(this.tapPlace!.id, 1); });
                        Button('👎').onClick(() => { this.handleVote(this.tapPlace!.id, -1); });
                      }
                      if (this.isMinePlace(this.tapPlace)) {
                        Button('编辑').onClick(() => { this.openEditPlace(this.tapPlace!, false); });
                        if (this.tapPlace.status === 'draft' || this.tapPlace.status === 'private' || this.tapPlace.status === 'rejected') {
                          Button('提交审核').onClick(() => { this.handlePublish(this.tapPlace!.id); });
                        }
                        Button('删除').onClick(() => { this.handleDelete(this.tapPlace!.id); });
                      } else {
                        Button('申请修改').onClick(() => { this.openEditPlace(this.tapPlace!, true); });
                        Button('反馈').onClick(() => { this.handleFeedback(this.tapPlace!.id); });
                      }
                      Button(this.isPlaceHidden(this.tapPlace.id) ? '显示' : '隐藏')
                        .onClick(() => { this.handleToggleHidden(this.tapPlace!.id, !this.isPlaceHidden(this.tapPlace!.id)); });
                      if (this.isAdmin() && this.tapPlace.status === 'pending') {
                        Button('通过').onClick(() => { this.handleApprove(this.tapPlace!.id); });
                        Button('拒绝').onClick(() => { this.handleReject(this.tapPlace!.id); });
                      }
                    }
                    .justifyContent(FlexAlign.SpaceBetween)
                    .width('100%');
                  } else {
                    Text('该位置暂无自定义地点').fontSize(12).fontColor('#7c8699');
                    Button('添加自定义位置').onClick(() => this.openAddPlaceFromTap());
                  }
                  Button('关闭').onClick(() => this.closeTapAction());
                }
                .padding(14)
                .width('94%')
                .backgroundColor(this.nightMode ? 'rgba(20, 32, 54, 0.94)' : 'rgba(255, 255, 255, 0.98)')
                .borderRadius(14)
                .alignSelf(ItemAlign.Center)
                .margin({ bottom: 96 })
                .hitTestBehavior(HitTestMode.Default)
                .zIndex(4);
              }

              Row() {
                if (this.showUi) {
                  Button(this.hazardMode ? '退出水雷' : '水雷排查')
                    .onClick(() => this.toggleHazardMode())
                    .fontSize(12)
                    .width(96)
                    .height(38)
                    .backgroundColor(this.hazardMode ? '#ffb347' : '#ffffff')
                    .fontColor('#1d2a42')
                    .borderRadius(12)
                    .hitTestBehavior(HitTestMode.Default)
                    .zIndex(3);
                } else {
                  Blank().width(96).height(38);
                }

                Column({ space: 8 }) {
                  Button(this.showUi ? '隐藏UI' : '显示UI')
                    .fontSize(12)
                    .width(96)
                    .height(32)
                    .backgroundColor('rgba(255, 255, 255, 0.2)')
                    .fontColor('#1d2a42')
                    .borderRadius(12)
                    .opacity(this.showUi ? 0.35 : 0.6)
                    .onClick(() => { this.showUi = !this.showUi; });

                  if (this.showUi) {
                    Column({ space: 6 }) {
                      Button() {
                        Text('＋')
                          .fontSize(18)
                          .fontColor('#1d2a42');
                      }
                      .width(44)
                      .height(44)
                      .backgroundColor('#ffffff')
                      .borderRadius(12)
                      .onClick(() => { this.zoom = this.zoom + 0.2; });
                      Button() {
                        Text('－')
                          .fontSize(18)
                          .fontColor('#1d2a42');
                      }
                      .width(44)
                      .height(44)
                      .backgroundColor('#ffffff')
                      .borderRadius(12)
                      .onClick(() => { this.zoom = this.zoom - 0.2; });
                    }
                    .backgroundColor(this.nightMode ? 'rgba(20, 32, 54, 0.85)' : 'rgba(255, 255, 255, 0.95)')
                    .borderRadius(14)
                    .padding(6)
                    .hitTestBehavior(HitTestMode.Default)
                    .zIndex(3);
                  }
                }
                .hitTestBehavior(HitTestMode.Default)
                .zIndex(3);
              }
              .padding({ left: 12, right: 12, bottom: 16 })
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
              .hitTestBehavior(HitTestMode.Default)
              .zIndex(3);
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.End);
          }
          .width('100%')
          .height('100%')
          .align(Alignment.TopStart)
          .hitTestBehavior(HitTestMode.Transparent);
        }
        .width('100%')
        .height('100%');
  }

  @Builder
  private buildSelectPage(): void {
    Column() {
      Row() {
        Button('返回').onClick(() => { this.currentPage = PageView.Map; });
        Text(this.currentPage === PageView.SelectStart ? '选择起点' : '选择终点')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 });
      }.margin({ bottom: 12 });

      TextInput({ text: this.selectionQuery, placeholder: '搜索地点' })
        .onChange((value: string) => { this.selectionQuery = value; });

      Row() {
        Button('地图点选')
          .onClick(() => {
            const mode = this.currentPage === PageView.SelectStart ? MapPickMode.Start : MapPickMode.End;
            this.currentPage = PageView.Map;
            this.pickMode = mode;
          });
      }
      .margin({ top: 8, bottom: 8 });

      Scroll() {
        Column() {
          ForEach(this.filterLocationOptions(this.buildLocationOptions(), this.selectionQuery), (item: LocationOption) => {
            Column() {
              Text(item.name).fontSize(13).fontWeight(FontWeight.Bold);
              Text(item.source).fontSize(11).fontColor('#7c8699');
            }
            .padding(10)
            .backgroundColor('#ffffff')
            .borderRadius(10)
            .margin({ bottom: 8 })
            .onClick(() => this.selectLocation(item));
          }, (item: LocationOption) => item.source + '-' + item.name + '-' + String(item.lat) + '-' + String(item.lon));
        }
      }
      .height('100%');
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor('#f5f6fa');
  }

  @Builder
  private buildProfilePage(): void {
    Column() {
      Row() {
        Button('返回').onClick(() => { this.currentPage = PageView.Map; });
        Text('个人中心').fontSize(16).fontWeight(FontWeight.Bold).margin({ left: 12 });
      }.margin({ bottom: 12 });

      if (!this.getSession()) {
        Text('游客模式').fontSize(12).fontColor('#7c8699').margin({ bottom: 12 });
      } else {
        Text('已登录：' + (this.getSession() ? this.getSession()!.username : ''))
          .fontSize(12)
          .fontColor('#4f79ff')
          .margin({ bottom: 12 });
      }

      TextInput({ text: this.username, placeholder: '用户名' })
        .onChange((value: string) => { this.username = value; });
      TextInput({ text: this.password, placeholder: '密码' })
        .type(InputType.Password)
        .onChange((value: string) => { this.password = value; });
      Row() {
        Button('登录').onClick(() => { this.handleLogin(); });
        Button('注册').onClick(() => { this.handleRegister(); });
        Button('退出').onClick(() => this.handleLogout());
      }.justifyContent(FlexAlign.SpaceBetween).width('100%').margin({ bottom: 6 });

      if (this.authError) {
        Text(this.authError)
          .fontSize(12)
          .fontColor('#ff4d4f')
          .margin({ bottom: 10 });
      }

      Divider().strokeWidth(1).color('#e1e6ef');
      Text('个人资料').fontSize(13).fontWeight(FontWeight.Bold);
      TextInput({ text: this.profileNickname, placeholder: '昵称' })
        .onChange((value: string) => { this.profileNickname = value; });
      TextInput({ text: this.profileAvatarUrl, placeholder: '头像 URL' })
        .onChange((value: string) => { this.profileAvatarUrl = value; });
      TextInput({ text: this.profileOldPassword, placeholder: '旧密码' })
        .type(InputType.Password)
        .onChange((value: string) => { this.profileOldPassword = value; });
      TextInput({ text: this.profileNewPassword, placeholder: '新密码' })
        .type(InputType.Password)
        .onChange((value: string) => { this.profileNewPassword = value; });
      Button('保存资料')
        .onClick(() => { console.info('Profile saved locally'); })
        .margin({ bottom: 16 });

      Divider().strokeWidth(1).color('#e1e6ef');
      Text('我的推荐地点').fontSize(13).fontWeight(FontWeight.Bold);
      ForEach(this.getMyPlaces(), (place: Place) => {
        Row() {
          Text(place.name).fontSize(12);
          Text('👍 ' + String(place.likes)).fontSize(11).fontColor('#7c8699');
        }.justifyContent(FlexAlign.SpaceBetween).width('100%').margin({ bottom: 6 });
      }, (place: Place) => 'mine-' + place.id);

      Divider().strokeWidth(1).color('#e1e6ef');
      Text('我的审核').fontSize(13).fontWeight(FontWeight.Bold);
      ForEach(this.pendingPlaces, (place: Place) => {
        Row() {
          Column() {
            Text(place.name).fontSize(12);
            Text(this.renderPlaceStatus(place.status)).fontSize(11).fontColor('#7c8699');
          }
          if (this.isAdmin()) {
            Row({ space: 6 }) {
              Button('接受')
                .fontSize(11)
                .onClick(() => { this.handleApprove(place.id); });
              Button('拒绝')
                .fontSize(11)
                .onClick(() => { this.handleReject(place.id); });
            }
          }
        }.justifyContent(FlexAlign.SpaceBetween).width('100%').margin({ bottom: 6 });
      }, (place: Place) => `pending-${place.id}`);
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff');
  }

  private openAddPlaceFromTap(): void {
    if (this.tapLocation) {
      this.selectedPoint = this.tapLocation;
    }
    this.placeName = '';
    this.placeDesc = '';
    this.placeImage = '';
    this.clearEditingState();
    this.pickMode = MapPickMode.None;
    this.tapActionVisible = false;
    this.currentPage = PageView.AddPlace;
  }

  @Builder
  private buildAddPlacePage(): void {
    
    Column() {
      Row() {
        Button('返回').onClick(() => { this.currentPage = PageView.Map; });
        Text(this.editingPlaceId ? '编辑地点' : (this.editingSourceKey ? '提交修改' : '添加自定义位置'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 });
      }.margin({ bottom: 12 });

      Text(this.getSelectedPoint() ? ('位置: ' + String(this.getSelectedPoint()!.lat.toFixed(5)) + ', ' + String(this.getSelectedPoint()!.lon.toFixed(5))) : '未选择位置')
        .fontSize(12)
        .fontColor('#7c8699');
      Button('重新选点')
        .onClick(() => { this.currentPage = PageView.Map; this.pickMode = MapPickMode.None; })
        .margin({ bottom: 12 });

      TextInput({ text: this.placeName, placeholder: '地点名称' })
        .onChange((value: string) => { this.placeName = value; });
      TextInput({ text: this.placeDesc, placeholder: '地点描述' })
        .onChange((value: string) => { this.placeDesc = value; });
      if (this.placeImage) {
        Image(this.placeImage)
          .width('100%')
          .height(160)
          .borderRadius(10)
          .margin({ bottom: 8 });
      }
      Button(this.placeImage ? '更换图片（可选）' : '选择图片（可选）')
        .onClick(() => { this.pickLocalImage(); })
        .margin({ bottom: 8 });
      Row() {
        Button('类型：' + this.renderPlaceTypeLabel(this.placeType)).onClick(() => this.cyclePlaceType());
        Button(this.editingPlaceId ? '保存修改' : '保存草稿').onClick(() => {
          this.handleSavePlace(false).then(() => { this.currentPage = PageView.Map; });
        });
      }.justifyContent(FlexAlign.SpaceBetween).width('100%');
      Button(this.editingPlaceId ? '提交审核' : (this.editingSourceKey ? '提交修改审核' : '提交审核'))
        .onClick(() => {
          this.handleSavePlace(true).then(() => { this.currentPage = PageView.Map; });
        })
        .margin({ top: 8 });
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff');
  }

  build() {
    Stack() {
      if (this.currentPage === PageView.Map) {
        this.buildMapPage();
      }
      if (this.currentPage === PageView.SelectStart || this.currentPage === PageView.SelectEnd) {
        this.buildSelectPage();
      }
      if (this.currentPage === PageView.Profile) {
        this.buildProfilePage();
      }
      if (this.currentPage === PageView.AddPlace) {
        this.buildAddPlacePage();
      }
    }
    .width('100%')
    .height('100%');
  }
}