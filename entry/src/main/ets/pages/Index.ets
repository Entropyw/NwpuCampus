import common from '@ohos.app.ability.common';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import geoLocationManager from '@ohos.geoLocationManager';
import preferences from '@ohos.data.preferences';
import promptAction from '@ohos.promptAction';
import vibrator from '@ohos.vibrator';
import { MapCanvas } from '../components/MapCanvas';
import { LongPressHandler, MapEventBus, SizeHandler, TapHandler, TransformHandler } from '../services/MapEventBus';
import { AuthService } from '../services/AuthService';
import { MessagePlaceSnapshot, MessageService, UserMessage } from '../services/MessageService';
import { OsmParser } from '../services/OsmParser';
import { PlaceService, SaveDraftInput } from '../services/PlaceService';
import { RoutePlanner } from '../services/RoutePlanner';
import { clampZoom } from '../services/MapMath';
import { Bounds, LatLon, MapLabel, MapWay, Marker, Place, PlaceFilter, PlaceType, PlaceTypeFlags, RenderData, RouteState, UserSession } from '../model/MapTypes';

interface PermissionRequestResult {
  authResults?: Array<number>;
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

interface CenterOffset {
  offsetX: number;
  offsetY: number;
}

type ResourceStr = string;
declare function $r(resourceName: string): ResourceStr;

// Optional NAPI photo access loader (provided by runtime on device)
declare function requireNapi(name: string): PhotoAccessHelperModule | undefined;

interface FilterUpdate {
  showSystem?: boolean;
  showPublic?: boolean;
  showMine?: boolean;
  sortBy?: 'time' | 'likes';
  avoidHazards?: boolean;
}

interface RawMessageFields {
  userId?: string;
  message?: string;
  date?: number;
  placeId?: string;
  type?: string;
  read?: boolean;
  readAt?: number | null;
}

// ArkTS linter forbids intersection types. Use interface inheritance instead
interface RawUserMessage extends UserMessage, RawMessageFields {}

class LocationOption {
  name: string;
  lat: number;
  lon: number;
  source: string;
  id: string;
  status: string;
  likes: number;

  constructor(name: string, lat: number, lon: number, source: string, id: string, status: string, likes: number) {
    this.name = name;
    this.lat = lat;
    this.lon = lon;
    this.source = source;
    this.id = id;
    this.status = status;
    this.likes = likes;
  }
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
    this.host.handleExternalTransform(zoom, offsetX, offsetY);
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

class IndexSizeHandler extends SizeHandler {
  private host: Index;

  constructor(host: Index) {
    super();
    this.host = host;
  }

  onSize(width: number, height: number): void {
    this.host.handleMapSize(width, height);
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
  Login,
  Register,
  Profile,
  BindEmail,
  ResetPassword,
  MyPlaces,
  HotPlaces,
  PlaceDetail,
  AdminPlaces,
  AdminReview,
  AddPlace
}

@Entry
@Component
struct Index {
  @State myLocation: LatLon | null = null;
  @State myLocationStatusText: string = '定位未初始化';
  @State myLocationUpdatedAt: number = 0;
  @State isOffCampus: boolean = false;
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
  @State authStatus: string = '未登录';
  @State authError: string = '';
  @State username: string = '';
  @State password: string = '';
  @State rememberMe: boolean = false;
  @State registerEmail: string = '';
  @State registerCode: string = '';
  @State resetEmail: string = '';
  @State resetCode: string = '';
  @State resetNewPassword: string = '';
  @State bindEmail: string = '';
  @State bindCode: string = '';
  @State bindingRequired: boolean = false;
  @State messages: Array<UserMessage> = [];
  @State unreadCount: number = 0;
  @State lastMessageReadAt: number = 0;
  @State showMessages: boolean = false;
  @State myPlaces: Array<Place> = [];
  @State myPlacesTab: string = 'all';
  @State adminPlacesTab: string = 'system';
  @State hotPlaces: Array<Place> = [];
  @State detailPlace: Place | null = null;
  @State focusPlace: Place | null = null;
  @State focusReturnPage: PageView | null = null;
  @State focusNavVisible: boolean = false;
  @State focusContext: string = '';
  @State focusReviewPlaceId: string = '';
  @State dynamicNavActive: boolean = false;

  @State feedbackVisible: boolean = false;
  @State feedbackPlaceId: string = '';
  @State feedbackText: string = '';

  @State adminReviewTab: 'review' | 'feedback' = 'review';
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
  @State route: RouteState | null = null;
  @State places: Array<Place> = [];
  @State pendingPlaces: Array<Place> = [];
  @State codeCooldownUntil: number = 0;
  @State selectedPoint: LatLon | null = null;

  @State hazardWarningVisible: boolean = false;
  @State hazardWarningText: string = '';

  private hazardWarningToken: number = 0;

  private refreshInFlight: boolean = false;

  private apiBase: string = 'http://121.36.80.168:8080';
  private osmParser: OsmParser = new OsmParser();
  private placeService: PlaceService = new PlaceService();
  private authService: AuthService = new AuthService();
  private messageService: MessageService = new MessageService();
  private routePlanner: RoutePlanner = new RoutePlanner();
  private renderData: RenderData = this.createEmptyRenderData();
  private labels: Array<MapLabel> = [];
  private startIndex: number = 0;
  private endIndex: number = 1;
  private locationUpdateIntervalId: number | null = null;
  private locationUpdateIntervalMs: number = 2000;
  private activeLocationUpdateIntervalMs: number = 0;

  private locationPermissionRequested: boolean = false;
  private locationPermissionGranted: boolean = false;

  private hasCenteredOnMyLocation: boolean = false;
  private lastProgramCenterAt: number = 0;
  private lastUserTransformAt: number = 0;

  private navRecalcAt: number = 0;
  private navRecalcLoc: LatLon | null = null;

  private offCampusToastAt: number = 0;

  private poiFallback: Array<MapLabel> = this.buildFallbackLabels();
  private savedFilter: PlaceFilter | null = null;
  private lastLocation: LatLon | null = null;
  private lastHazardAlertAt: number = 0;
  private lastWaterMineDangerAt: number = 0;
  private messagePageSize: number = 20;

  private colorPrimary: string = '#7B7CF6';
  private colorPrimaryLight: string = '#f1edff';
  private colorAccent: string = '#2EC4B6';
  private colorWarn: string = '#F6C177';
  private colorDanger: string = '#F28482';
  private colorBg: string = '#F6F5FB';
  private colorSurface: string = '#FFFFFF';

  // handlers bound at runtime so we can unregister them cleanly
  private __mapTapHandler: TapHandler | null = null;
  private __mapTransformHandler: TransformHandler | null = null;
  private __mapLongPressHandler: LongPressHandler | null = null;
  private __mapSizeHandler: SizeHandler | null = null;

  private mapCanvasWidth: number = 0;
  private mapCanvasHeight: number = 0;

  aboutToAppear(): void {
    // business API follows the documented base
    this.apiBase = 'http://121.36.80.168:8080';
    this.placeService.enableRemote(this.apiBase);
    this.authService.enableRemote(this.apiBase);
    this.messageService.enableRemote(this.apiBase);
    this.authService.enableEmailRemote(this.apiBase);
    this.loadMap();
    this.locationPermissionRequested = false;
    this.locationPermissionGranted = false;
    this.hasCenteredOnMyLocation = false;
    void this.initMyLocation();
    this.startLocationUpdates();
    // register map event handlers
    this.__mapTapHandler = new IndexTapHandler(this);
    MapEventBus.registerTapHandler(this.__mapTapHandler);

    this.__mapTransformHandler = new IndexTransformHandler(this);
    MapEventBus.registerTransformHandler(this.__mapTransformHandler);

    this.__mapLongPressHandler = new IndexLongPressHandler(this);
    MapEventBus.registerLongPressHandler(this.__mapLongPressHandler);

    this.__mapSizeHandler = new IndexSizeHandler(this);
    MapEventBus.registerSizeHandler(this.__mapSizeHandler);
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
    if (this.__mapSizeHandler) {
      MapEventBus.unregisterSizeHandler(this.__mapSizeHandler);
      this.__mapSizeHandler = null;
    }
  }

  private createEmptyRenderData(): RenderData {
    const bounds: Bounds = { minLat: 34.029, maxLat: 34.034, minLon: 108.758, maxLon: 108.766 };
    const roads: Array<MapWay> = [];
    const buildings: Array<MapWay> = [];
    const waters: Array<MapWay> = [];
    const areas: Array<MapWay> = [];
    const pitches: Array<MapWay> = [];
    const labels: Array<MapLabel> = [];
    const data: RenderData = { bounds, roads, buildings, waters, areas, pitches, labels };
    return data;
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
      // Keep labels only as map metadata. Do NOT seed/display OSM-derived “system places”.
      this.labels = parsed.labels.length ? parsed.labels : [];
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
    if (combined.length === 0) {
      promptAction.showToast({ message: '暂无可选地点，请使用“地图点选”选择起点', duration: 1500 });
      return;
    }
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
    if (combined.length === 0) {
      promptAction.showToast({ message: '暂无可选地点，请使用“地图点选”选择终点', duration: 1500 });
      return;
    }
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
    const list: Array<MapLabel> = [];
    // Prefer real places (admin-added system places + user places) over OSM labels.
    for (const place of this.places) {
      // Keep route endpoints reasonable; allow hazards too if user really wants.
      if (place.hidden) {
        continue;
      }
      if (place.status !== 'approved' && place.status !== 'published') {
        continue;
      }
      list.push({
        name: place.name,
        lat: place.lat,
        lon: place.lon,
        priority: Math.max(0, place.likes || 0),
        kind: place.sourceType === 'system' ? 'system' : 'place'
      });
    }
    // Always keep a safe fallback so modulo math never breaks.
    if (list.length === 0) {
      const center = this.getCampusBoundsCenter();
      list.push({ name: '校园中心', lat: center.lat, lon: center.lon, priority: 0, kind: 'fallback' });
    }
    return list;
  }

  private sendMyLocation(lat: number, lon: number): void {
    const loc: LatLon = { lat, lon };
    this.myLocation = loc;
    this.myLocationUpdatedAt = Date.now();
    const inCampus = this.isInCampusBounds(lat, lon);
    this.isOffCampus = !inCampus;
    this.myLocationStatusText = `定位已更新: ${lat.toFixed(6)}, ${lon.toFixed(6)}` + (inCampus ? '' : '（不在学校范围内）');
    if (!inCampus) {
      const now = Date.now();
      if (now - this.offCampusToastAt > 15000) {
        this.offCampusToastAt = now;
        promptAction.showToast({ message: '您当前不在学校范围内，已为您保持显示校园地图', duration: 1800 });
      }
    }
    this.checkHazardProximity(loc);
    this.checkRouteHazardAhead(loc);
    this.lastLocation = loc;

    // Default route start to current location, and keep it synced while start is "我的位置".
    if (!this.routeStart || this.routeStartLabel === '我的位置') {
      this.routeStart = loc;
      this.routeStartLabel = '我的位置';
    }

    this.maybeReplanRouteWithMyLocation(loc);
    this.maybeAutoFollowMyLocation();
  }

  handleExternalTransform(zoom: number, offsetX: number, offsetY: number): void {
    this.zoom = zoom;
    this.offsetX = offsetX;
    this.offsetY = offsetY;
    const now = Date.now();
    if (now - this.lastProgramCenterAt > 250) {
      this.lastUserTransformAt = now;
    }
  }

  private maybeAutoFollowMyLocation(): void {
    if (!this.myLocation) {
      return;
    }
    if (this.currentPage !== PageView.Map) {
      return;
    }
    // Keep showing campus even when GPS is off-campus.
    if (this.isOffCampus) {
      return;
    }
    if (!this.hasCenteredOnMyLocation) {
      this.hasCenteredOnMyLocation = true;
      this.centerMapOnMyLocation();
      return;
    }
    const now = Date.now();
    if (now - this.lastUserTransformAt < 3000) {
      return;
    }
    this.centerMapOnMyLocation();
  }

  private maybeReplanRouteWithMyLocation(loc: LatLon): void {
    if (!this.dynamicNavActive || !this.routeEnd) {
      return;
    }
    const now = Date.now();
    if (now - this.navRecalcAt < 1500) {
      return;
    }
    if (this.navRecalcLoc) {
      const moved = this.distanceMeters(loc, this.navRecalcLoc);
      if (moved < 1.5) {
        return;
      }
    }
    this.navRecalcAt = now;
    this.navRecalcLoc = loc;

    this.routeStart = loc;
    this.routeStartLabel = '我的位置';
    this.planRoute();
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

  private async ensureLocationPermission(): Promise<boolean> {
    try {
      if (this.locationPermissionGranted) {
        return true;
      }
      // Avoid repeatedly popping permission dialogs during polling.
      if (this.locationPermissionRequested) {
        return false;
      }
      this.locationPermissionRequested = true;

      const context = this.getHostContext();
      const atManager = abilityAccessCtrl.createAtManager();
      // Request minimal permission to avoid SDK-compat issues across versions.
      type OhosPermission = 'ohos.permission.LOCATION' | 'ohos.permission.APPROXIMATELY_LOCATION';
      const permissions: Array<OhosPermission> = ['ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION'];
      const rawResult = await atManager.requestPermissionsFromUser(context, permissions);
      const result: PermissionRequestResult | null = rawResult as PermissionRequestResult | null;
      let authResults: Array<number> = [];
      if (result && result.authResults) {
        authResults = result.authResults;
      }
      if (authResults.length === 0) {
        return false;
      }
      for (let i = 0; i < authResults.length; i++) {
        if (authResults[i] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          return false;
        }
      }
      this.locationPermissionGranted = true;
      return true;
    } catch (error) {
      console.error(`请求定位权限失败: ${String(error)}`);
      return false;
    }
  }

  private async getRealLocation(): Promise<geoLocationManager.Location | null> {
    try {
      const request: geoLocationManager.CurrentLocationRequest = {
        scenario: geoLocationManager.LocationRequestScenario.NAVIGATION,
        timeoutMs: 12000
      } as geoLocationManager.CurrentLocationRequest;
      const location = await geoLocationManager.getCurrentLocation(request);
      return location as geoLocationManager.Location;
    } catch (error) {
      const detail = String(error);
      console.error(`获取真实定位失败: ${detail}`);
      this.myLocationStatusText = `获取真实定位失败: ${detail}`;
      return null;
    }
  }

  private async initMyLocation(): Promise<void> {
    this.myLocationStatusText = '正在获取真实定位...';
    const granted = await this.ensureLocationPermission();
    if (!granted) {
      console.warn('定位权限未授予，无法获取真实位置');
      this.myLocationStatusText = '定位权限未授予（请在系统设置中允许定位权限）';
      return;
    }
    const real = await this.getRealLocation();
    if (real) {
      this.sendMyLocation(real.latitude, real.longitude);
    } else {
      this.myLocationStatusText = '真实定位获取失败（请确认已打开系统定位开关/GPS）';
    }
  }

  /**
    * Start periodic location updates using system-provided location (device or simulator).
    * Uses polling so it works even if the exact SDK location subscription API differs across versions.
   */
  private startLocationUpdates(intervalMs?: number): void {
    const ms = intervalMs && intervalMs > 0 ? intervalMs : this.locationUpdateIntervalMs;
    if (this.locationUpdateIntervalId != null) {
      // already running; restart if interval differs
      if (this.activeLocationUpdateIntervalMs !== ms) {
        this.stopLocationUpdates();
      } else {
        return;
      }
    }

    this.activeLocationUpdateIntervalMs = ms;

    // Real device: poll getCurrentLocation with async wrapper
    const pollOnce = async (): Promise<void> => {
      try {
        const granted = this.locationPermissionGranted ? true : await this.ensureLocationPermission();
        if (!granted) {
          console.warn('定位权限未授予，停止定位更新');
          this.myLocationStatusText = '定位权限未授予，已停止自动定位更新';
          this.stopLocationUpdates();
          return;
        }
        const real = await this.getRealLocation();
        if (real) {
          this.sendMyLocation(real.latitude, real.longitude);
        } else {
          if (!this.myLocationStatusText) {
            this.myLocationStatusText = '真实定位获取失败（轮询中）';
          }
        }
      } catch (e) {
        console.error('轮询位置失败', e);
        this.myLocationStatusText = `轮询位置失败: ${String(e)}`;
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
    this.activeLocationUpdateIntervalMs = 0;
  }

  private showHazardWarning(text: string): void {
    this.hazardWarningToken += 1;
    const token = this.hazardWarningToken;
    this.hazardWarningText = text;
    this.hazardWarningVisible = true;
    // Auto hide after 3 seconds
    setTimeout(() => {
      // Only hide if no newer warning has been shown.
      if (this.hazardWarningToken !== token) {
        return;
      }
      this.hazardWarningVisible = false;
      this.hazardWarningText = '';
    }, 3000);
  }

  private bearingDegrees(from: LatLon, to: LatLon): number {
    // Bearing: 0° = North, 90° = East
    const lat1 = from.lat * Math.PI / 180;
    const lat2 = to.lat * Math.PI / 180;
    const dLon = (to.lon - from.lon) * Math.PI / 180;
    const y = Math.sin(dLon) * Math.cos(lat2);
    const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
    let brng = Math.atan2(y, x) * 180 / Math.PI;
    if (brng < 0) {
      brng += 360;
    }
    return brng;
  }

  private bearingArrow(degrees: number): string {
    const dirs = ['↑', '↗', '→', '↘', '↓', '↙', '←', '↖'];
    const idx = Math.round(degrees / 45) % 8;
    return dirs[idx];
  }

  private bearingText(degrees: number): string {
    const names = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    const idx = Math.round(degrees / 45) % 8;
    return names[idx];
  }

  private showNearestWaterMineInfo(): void {
    const current = this.myLocation;
    if (!current) {
      promptAction.showToast({ message: '请先开启定位，再进行水雷排查', duration: 1600 });
      return;
    }
    const allPlaces = this.placeService.getCachedPlaces();
    let bestDist = Number.POSITIVE_INFINITY;
    let bestPlace: Place | null = null;
    for (const place of allPlaces) {
      if (place.type !== 'water') {
        continue;
      }
      const dist = this.distanceMeters(current, { lat: place.lat, lon: place.lon });
      if (dist < bestDist) {
        bestDist = dist;
        bestPlace = place;
      }
    }
    if (!bestPlace || !isFinite(bestDist)) {
      const msg = '当前没有水雷标记';
      this.showHazardWarning(msg);
      promptAction.showToast({ message: msg, duration: 1600 });
      return;
    }
    const bearing = this.bearingDegrees(current, { lat: bestPlace.lat, lon: bestPlace.lon });
    const arrow = this.bearingArrow(bearing);
    const dirText = this.bearingText(bearing);
    const msg = `最近水雷：${bestDist.toFixed(1)}m 方向：${arrow}（${dirText}）`;
    this.showHazardWarning(msg);
    promptAction.showToast({ message: msg, duration: 2200 });
  }

  private checkRouteHazardAhead(current: LatLon): void {
    if (!this.dynamicNavActive || !this.routeVisible || !this.route || !this.route.path || this.route.path.length < 2) {
      return;
    }
    const now = Date.now();
    if (now - this.lastHazardAlertAt < 5000) {
      return;
    }

    // Find nearest route point index to current position.
    let currentIdx = 0;
    let best = Number.POSITIVE_INFINITY;
    for (let i = 0; i < this.route.path.length; i++) {
      const d = this.distanceMeters(current, this.route.path[i]);
      if (d < best) {
        best = d;
        currentIdx = i;
      }
    }

    for (const place of this.places) {
      const isHazard = place.type === 'water' || place.type === 'danger' || place.type === 'slippery';
      if (!isHazard) {
        continue;
      }
      // Find nearest route point index to hazard.
      let hazardIdx = 0;
      let hazardBest = Number.POSITIVE_INFINITY;
      for (let i = 0; i < this.route.path.length; i++) {
        const d = this.distanceMeters({ lat: place.lat, lon: place.lon }, this.route.path[i]);
        if (d < hazardBest) {
          hazardBest = d;
          hazardIdx = i;
        }
      }
      if (hazardIdx <= currentIdx) {
        continue;
      }
      // Must be close to route
      if (hazardBest > 8) {
        continue;
      }
      // Compute along-route distance from currentIdx to hazardIdx
      let along = 0;
      for (let i = currentIdx; i < hazardIdx; i++) {
        along += this.distanceMeters(this.route.path[i], this.route.path[i + 1]);
        if (along > 6) {
          break;
        }
      }
      if (along <= 5.0) {
        this.lastHazardAlertAt = now;
        const msg = place.type === 'water'
          ? '前方5米内有水雷，请注意脚下'
          : '前方5米内有危险地带，请注意安全';
        this.showHazardWarning(msg);
        promptAction.showToast({ message: msg, duration: 2000 });
        // Best-effort hooks: vibration + voice (will no-op if device lacks capability)
        void this.tryVibrateAndSpeak(msg);
        return;
      }
    }
  }

  private async tryVibrateAndSpeak(text: string): Promise<void> {
    // Vibration / TTS are device-dependent; keep best-effort and never crash.
    try {
      vibrator.vibrate(250);
    } catch (e) {
      // ignore
    }
    console.info('Hazard alert:', text);
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
    const startResolved: LatLon = startPoint as LatLon;
    const endResolved: LatLon = endPoint as LatLon;
    const nextRoute = this.routePlanner.buildRoute(startResolved, endResolved, this.renderData);
    if (!nextRoute.path || nextRoute.path.length < 2) {
      // fallback: draw straight line to avoid false “invalid” when道路图缺失
      const fallback: RouteState = { start: startResolved, end: endResolved, path: [startResolved, endResolved] };
      this.route = fallback;
      this.routeVisible = true;
      return true;
    }
    this.route = nextRoute;
    this.routeVisible = true;

    // When navigation is active, keep the camera focused on the start point.
    if (this.dynamicNavActive) {
      const nextZoom = clampZoom(2.2);
      const offsets = this.computeCenterOffsets(startResolved.lat, startResolved.lon, nextZoom);
      this.zoom = nextZoom;
      this.offsetX = offsets.offsetX;
      this.offsetY = offsets.offsetY;
    }
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
      if (this.routeStart && this.routeEnd) {
        this.planRoute();
      } else {
        this.invalidateRoute();
      }
      return;
    }
    if (this.pickMode === MapPickMode.End) {
      this.routeEnd = point;
      this.routeEndLabel = '地图点';
      this.pickMode = MapPickMode.None;
      if (this.routeStart && this.routeEnd) {
        this.planRoute();
      } else {
        this.invalidateRoute();
      }
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

  handleMapSize(width: number, height: number): void {
    if (width > 0 && height > 0) {
      this.mapCanvasWidth = width;
      this.mapCanvasHeight = height;
    }
  }

  private computeCenterOffsets(lat: number, lon: number, zoom: number): CenterOffset {
    const render = this.renderData;
    if (!render || this.mapCanvasWidth <= 0 || this.mapCanvasHeight <= 0) {
      const fallback: CenterOffset = { offsetX: 0, offsetY: 0 };
      return fallback;
    }
    const bounds = render.bounds;
    const width = this.mapCanvasWidth;
    const height = this.mapCanvasHeight;
    const lonSpan = bounds.maxLon - bounds.minLon || 1;
    const latSpan = bounds.maxLat - bounds.minLat || 1;
    const baseScaleX = width / lonSpan;
    const baseScaleY = height / latSpan;
    const baseScale = Math.min(baseScaleX, baseScaleY) * 0.96;
    const scale = baseScale * zoom;
    const offsetX = width / 2 - (lon - bounds.minLon) * scale - (width - lonSpan * scale) / 2;
    const offsetY = height / 2 - (bounds.maxLat - lat) * scale - (height - latSpan * scale) / 2;
    const offsets: CenterOffset = { offsetX, offsetY };
    return offsets;
  }

  private getCampusBoundsCenter(): LatLon {
    const b = this.renderData.bounds;
    const center: LatLon = { lat: (b.minLat + b.maxLat) / 2, lon: (b.minLon + b.maxLon) / 2 };
    return center;
  }

  private isInCampusBounds(lat: number, lon: number): boolean {
    const b = this.renderData.bounds;
    // Add a small margin so boundary jitter won't constantly flip state.
    const marginLat = 0.0015;
    const marginLon = 0.0015;
    if (lat < b.minLat - marginLat || lat > b.maxLat + marginLat) {
      return false;
    }
    if (lon < b.minLon - marginLon || lon > b.maxLon + marginLon) {
      return false;
    }
    return true;
  }

  private centerMapOnCampus(): void {
    this.lastProgramCenterAt = Date.now();
    const center = this.getCampusBoundsCenter();
    const nextZoom = clampZoom(1.8);
    const offsets = this.computeCenterOffsets(center.lat, center.lon, nextZoom);
    this.zoom = nextZoom;
    this.offsetX = offsets.offsetX;
    this.offsetY = offsets.offsetY;
    this.currentPage = PageView.Map;
  }

  private centerMapOnMyLocation(): void {
    if (!this.myLocation) {
      this.centerMapOnCampus();
      return;
    }
    if (!this.isInCampusBounds(this.myLocation.lat, this.myLocation.lon)) {
      this.centerMapOnCampus();
      return;
    }
    this.lastProgramCenterAt = Date.now();
    const nextZoom = clampZoom(this.zoom < 1.6 ? 1.8 : this.zoom);
    const offsets = this.computeCenterOffsets(this.myLocation.lat, this.myLocation.lon, nextZoom);
    this.zoom = nextZoom;
    this.offsetX = offsets.offsetX;
    this.offsetY = offsets.offsetY;
    this.currentPage = PageView.Map;
  }

  private focusMapOnPlace(place: Place, returnPage: PageView, context: string): void {
    this.focusPlace = place;
    this.focusReturnPage = returnPage;
    this.focusContext = context;
    this.focusNavVisible = true;
    // Viewing a place doesn't automatically start navigation.
    this.dynamicNavActive = false;
    const nextZoom = clampZoom(1.8);
    const offsets = this.computeCenterOffsets(place.lat, place.lon, nextZoom);
    this.zoom = nextZoom;
    this.offsetX = offsets.offsetX;
    this.offsetY = offsets.offsetY;
    this.currentPage = PageView.Map;
  }

  private clearFocusViewState(): void {
    this.focusPlace = null;
    this.focusReturnPage = null;
    this.focusContext = '';
    this.focusReviewPlaceId = '';
    this.focusNavVisible = false;
  }

  // “返回”：回到进入查看位置前的页面
  private exitFocusView(): void {
    if (this.focusReturnPage != null) {
      this.currentPage = this.focusReturnPage;
    } else {
      this.currentPage = PageView.Map;
    }
    this.clearFocusViewState();
  }

  // “取消”：留在地图主页，仅关闭查看位置浮层
  private cancelFocusView(): void {
    this.currentPage = PageView.Map;
    this.clearFocusViewState();
  }

  private toggleFocusNavOptions(): void {
    this.focusNavVisible = !this.focusNavVisible;
  }

  private navigateToFocusPlace(): void {
    if (!this.focusPlace) {
      return;
    }
    const dest: LatLon = { lat: this.focusPlace.lat, lon: this.focusPlace.lon };
    const start: LatLon = this.myLocation
      ? { lat: this.myLocation.lat, lon: this.myLocation.lon }
      : (this.routeStart || this.selectedPoint || this.getCampusCenter());

    this.routeStart = start;
    this.routeEnd = dest;
    this.routeStartLabel = this.myLocation ? '我的位置' : (this.routeStartLabel || '起点');
    this.routeEndLabel = this.focusPlace.name;

    this.dynamicNavActive = true;
    this.invalidateRoute();
    this.planRoute();
    // Make navigation real-time: poll location more frequently while navigating.
    this.startLocationUpdates(1000);
    this.cancelFocusView();
  }

  private stopNavigation(): void {
    this.dynamicNavActive = false;
    this.invalidateRoute();
    this.startLocationUpdates(this.locationUpdateIntervalMs);
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
    // Always-on: if a watermine is within 3m, show a UI warning.
    const now = Date.now();
    if (now - this.lastWaterMineDangerAt >= 2000) {
      let nearest = Number.POSITIVE_INFINITY;
      const allPlaces = this.placeService.getCachedPlaces();
      for (const place of allPlaces) {
        if (place.type !== 'water') {
          continue;
        }
        const dist = this.distanceMeters(current, { lat: place.lat, lon: place.lon });
        if (dist < nearest) {
          nearest = dist;
        }
      }
      if (nearest < 3.0) {
        this.lastWaterMineDangerAt = now;
        const msg = `危险：3米内有水雷（约 ${nearest.toFixed(1)}m）`;
        this.showHazardWarning(msg);
        void this.tryVibrateAndSpeak(msg);
      }
    }

    // Optional: directional 5m warning when hazard mode / avoidHazards is enabled.
    if (!this.hazardMode && !this.filter.avoidHazards) {
      return;
    }
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

  private isPlaceFavorite(placeId: string): boolean {
    return this.placeService.isPlaceFavorite(placeId, this.getSession());
  }

  private buildLocationOptions(): Array<LocationOption> {
    const list: Array<LocationOption> = [];
    if (this.myLocation) {
      list.push(new LocationOption('我的位置', this.myLocation.lat, this.myLocation.lon, '当前位置', '', 'gps', 0));
    }
    for (const place of this.places) {
      const source = place.sourceType === 'system' ? '系统地点' : '自定义';
      list.push(new LocationOption(place.name, place.lat, place.lon, source, place.id, place.status, place.likes));
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
    if (this.routeStart && this.routeEnd) {
      this.planRoute();
    } else {
      this.invalidateRoute();
    }
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
    void this.refreshPlaces();
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
    if (this.refreshInFlight) {
      return;
    }
    this.refreshInFlight = true;
    try {
      const session = this.authService.getSession();

      // Apply the "re-enter page" behavior: clear UI selection and rebuild place cache
      // so both auto/manual refresh reflect server changes immediately.
      this.tapActionVisible = false;
      this.tapPlace = null;
      this.tapLocation = null;
      this.focusPlace = null;

      // Force a remote sync first so manual/auto refresh always pulls latest.
      // If remote fails, still fall back to cached/local but show the error.
      await this.placeService.syncRemote(session);
      const syncErr = this.placeService.getLastError();
      if (syncErr) {
        promptAction.showToast({ message: syncErr, duration: 1500 });
      }
      this.places = await this.placeService.list(this.filter, session);
      this.pendingPlaces = await this.placeService.listPending(session);
      this.updateHotPlaces();
    } finally {
      this.refreshInFlight = false;
    }
  }

  private getVoteValue(placeId: string): number {
    const session = this.getSession();
    return this.placeService.getMyVoteValue(placeId, session);
  }

  private voteButtonLabel(placeId: string, delta: number): string {
    const value = this.getVoteValue(placeId);
    if (delta === 1) {
      return value === 1 ? '取消点赞' : '👍 赞';
    }
    return value === -1 ? '取消踩' : '👎 踩';
  }

  private async loadMyPlaces(): Promise<void> {
    const session = this.authService.getSession();
    if (!session) {
      this.myPlaces = [];
      return;
    }
    // Ensure we have latest places + preferences (hidden/favorite) from server.
    await this.refreshPlaces();
    const list = await this.placeService.listMyPlaces(session);
    this.myPlaces = list;
  }

  private updateHotPlaces(): void {
    const all = this.placeService.getCachedPlaces();
    const visible = all.filter((place) => place.status === 'approved' || place.status === 'published');
  const sorted = visible.slice().sort((a: Place, b: Place) => b.likes - a.likes);
    this.hotPlaces = sorted;
  }

  private async handleLogin(): Promise<void> {
    const session = await this.authService.login(this.username, this.password);
    if (session) {
      this.authError = '';
      this.updateSessionStatus(session);
      if (session.requireEmailBind) {
        this.bindingRequired = true;
        this.bindEmail = session.email || '';
        promptAction.showToast({ message: '请先绑定邮箱再进入系统', duration: 1500 });
        this.currentPage = PageView.BindEmail;
      } else {
        promptAction.showToast({ message: '登录成功', duration: 1200 });
        this.currentPage = PageView.Profile;
      }
    } else {
      this.authError = this.authService.getLastError() || '登录失败';
      this.updateSessionStatus(null);
    }
  }

  private async handleRegister(): Promise<void> {
    if (!this.username || !this.password) {
      this.authError = '请填写账号和密码';
      return;
    }
    const session = await this.authService.register(this.username, this.password);
    if (session) {
      this.authError = '';
      this.updateSessionStatus(session);
      promptAction.showToast({ message: '注册成功', duration: 1200 });
      if (session.requireEmailBind) {
        this.bindingRequired = true;
        this.bindEmail = session.email || this.registerEmail;
        this.currentPage = PageView.BindEmail;
      } else {
        this.currentPage = PageView.Profile;
      }
    } else {
      this.authError = this.authService.getLastError() || '注册失败';
      this.updateSessionStatus(null);
    }
  }

  private async sendRegisterCode(): Promise<void> {
    const now = Date.now();
    if (now < this.codeCooldownUntil) {
      const remaining = Math.ceil((this.codeCooldownUntil - now) / 1000);
      promptAction.showToast({ message: `请${remaining}秒后再试`, duration: 1200 });
      return;
    }
    if (!this.username || !this.registerEmail) {
      promptAction.showToast({ message: '请输入账号和邮箱', duration: 1500 });
      return;
    }
    const ok = await this.authService.sendEmailCode(this.username, this.registerEmail, 'bind');
    if (ok) {
      this.codeCooldownUntil = Date.now() + 30000;
      promptAction.showToast({ message: '验证码已发送', duration: 1200 });
    } else {
      promptAction.showToast({ message: this.authService.getLastError() || '发送失败', duration: 1500 });
    }
  }

  private async sendResetCode(): Promise<void> {
    const now = Date.now();
    if (now < this.codeCooldownUntil) {
      const remaining = Math.ceil((this.codeCooldownUntil - now) / 1000);
      promptAction.showToast({ message: `请${remaining}秒后再试`, duration: 1200 });
      return;
    }
    if (!this.username || !this.resetEmail) {
      promptAction.showToast({ message: '请输入账号和邮箱', duration: 1500 });
      return;
    }
    if (this.username.trim().toLowerCase() === 'admin') {
      promptAction.showToast({ message: '管理员账户不支持找回密码', duration: 1500 });
      return;
    }
    const ok = await this.authService.sendEmailCode(this.username, this.resetEmail, 'reset');
    if (ok) {
      this.codeCooldownUntil = Date.now() + 30000;
      promptAction.showToast({ message: '验证码已发送', duration: 1200 });
    } else {
      promptAction.showToast({ message: this.authService.getLastError() || '发送失败', duration: 1500 });
    }
  }

  private async sendBindCode(): Promise<void> {
    const now = Date.now();
    if (now < this.codeCooldownUntil) {
      const remaining = Math.ceil((this.codeCooldownUntil - now) / 1000);
      promptAction.showToast({ message: `请${remaining}秒后再试`, duration: 1200 });
      return;
    }
    const session = this.getSession();
    if (!session || !this.bindEmail) {
      promptAction.showToast({ message: '请输入绑定邮箱', duration: 1500 });
      return;
    }
    const ok = await this.authService.sendEmailCode(session.username, this.bindEmail, 'bind');
    if (ok) {
      this.codeCooldownUntil = Date.now() + 30000;
      promptAction.showToast({ message: '验证码已发送', duration: 1200 });
    } else {
      promptAction.showToast({ message: this.authService.getLastError() || '发送失败', duration: 1500 });
    }
  }

  private async handleResetPassword(): Promise<void> {
    if (this.username.trim().toLowerCase() === 'admin') {
      this.authError = '管理员账户不支持找回密码';
      return;
    }
    if (!this.username || !this.resetEmail || !this.resetCode || !this.resetNewPassword) {
      this.authError = '请填写完整的找回信息';
      return;
    }
    const ok = await this.authService.resetPassword(this.username, this.resetCode, this.resetNewPassword);
    if (ok) {
      this.authError = '';
      promptAction.showToast({ message: '密码已重置，请使用新密码登录', duration: 1500 });
      this.currentPage = PageView.Login;
    } else {
      this.authError = this.authService.getLastError() || '重置失败';
    }
  }

  private async handleBindEmail(): Promise<void> {
    const session = this.getSession();
    if (!session || !this.bindEmail || !this.bindCode) {
      promptAction.showToast({ message: '请输入邮箱和验证码', duration: 1500 });
      return;
    }
    const ok = await this.authService.bindEmail(session.username, this.bindEmail, this.bindCode);
    if (!ok) {
      promptAction.showToast({ message: this.authService.getLastError() || '绑定失败', duration: 1500 });
      return;
    }
    this.authService.setSessionEmail(this.bindEmail, false);
    // 同步本地状态，保证 UI 立即刷新且找回密码使用最新邮箱
    const refreshed = this.authService.getSession();
    if (refreshed) {
      const refreshedSession: UserSession = {
        token: refreshed.token,
        username: refreshed.username,
        isAdmin: refreshed.isAdmin,
        email: this.bindEmail,
        requireEmailBind: false
      };
      this.updateSessionStatus(refreshedSession);
    }
    this.bindingRequired = false;
    this.resetEmail = this.bindEmail;
    promptAction.showToast({ message: '邮箱绑定成功', duration: 1200 });
    this.currentPage = PageView.Profile;
  }

  private handleLogout(): void {
    this.authService.logout();
    this.authError = '';
    this.updateSessionStatus(null);
    this.currentPage = PageView.Login;
  }

  private updateSessionStatus(session: UserSession | null): void {
    if (session) {
      this.authStatus = `已登录：${session.username}` + (session.isAdmin ? '（管理员）' : '');
      this.profileNickname = session.username;
    } else {
      this.authStatus = '未登录';
      this.profileNickname = '';
      this.profileAvatarUrl = '';
      this.bindingRequired = false;
      this.bindEmail = '';
      this.bindCode = '';
    }
    void this.onSessionChanged(session);
  }

  private getMessageReadAtStorageKey(username: string): string {
    return 'lastMessageReadAt_' + username;
  }

  private async loadPersistedMessageReadAt(username: string): Promise<number> {
    try {
      const ctx = this.getHostContext();
      const store = await preferences.getPreferences(ctx, 'nwpu-campus');
      const key = this.getMessageReadAtStorageKey(username);
      const raw = await store.get(key, 0);
      const asNum = typeof raw === 'number'
        ? raw
        : (typeof raw === 'string' ? Number(raw) : 0);
      if (typeof asNum === 'number' && Number.isFinite(asNum) && asNum > 0) {
        return asNum;
      }
      return 0;
    } catch {
      return 0;
    }
  }

  private async persistMessageReadAt(username: string, ts: number): Promise<void> {
    try {
      const ctx = this.getHostContext();
      const store = await preferences.getPreferences(ctx, 'nwpu-campus');
      const key = this.getMessageReadAtStorageKey(username);
      await store.put(key, ts);
      await store.flush();
    } catch {
      // ignore
    }
  }

  private async onSessionChanged(session: UserSession | null): Promise<void> {
    if (session && !session.isAdmin) {
      this.lastMessageReadAt = await this.loadPersistedMessageReadAt(session.username);
    } else {
      this.lastMessageReadAt = 0;
    }
    await this.loadMessagesForSession(session);
    await this.loadMyPlaces();
    void this.refreshPlaces();
  }

  private cyclePlaceType(): void {
    const types: Array<PlaceType> = ['normal', 'slippery', 'danger'];
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

    // Admin-created places are treated as system places (blue) and are visible immediately.
    const isAdminAddingNew = isAdmin && !this.editingPlaceId && !this.editingSourceKey;
    if (isAdminAddingNew) {
      this.editingSourceType = 'system';
    }

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
      const computedSourceType = this.editingSourceType;
      const shouldAutoApprove = isAdmin && computedSourceType === 'system' && !this.editingSourceKey;
      const status = shouldAutoApprove
        ? 'approved'
        : (publish
          ? (isAdmin && computedSourceType === 'system' ? 'pending' : (isAdmin ? 'approved' : 'private'))
          : 'private');

      let sourceKeyValue: string = this.editingSourceKey;
      if (!sourceKeyValue && computedSourceType === 'system') {
        sourceKeyValue = this.placeService.makeSystemSourceKey(this.placeName || '系统地点', point.lat, point.lon);
      }
      const input: SaveDraftInput = {
        name: this.placeName,
        description: this.placeDesc,
        type: this.placeType,
        imageUrl: this.placeImage,
        point,
        sourceKey: sourceKeyValue || undefined,
        sourceType: computedSourceType || undefined,
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
      const uri = await this.selectLocalPhoto();
      if (uri) {
        this.placeImage = uri;
      } else {
        promptAction.showToast({ message: '未选择图片或设备不支持', duration: 1200 });
      }
    } catch (error) {
      console.error('选择图片失败', error);
    }
  }

  private async pickAvatarImage(): Promise<void> {
    try {
      const uri = await this.selectLocalPhoto();
      if (uri) {
        this.profileAvatarUrl = uri;
      } else {
        promptAction.showToast({ message: '未选择头像或设备不支持', duration: 1200 });
      }
    } catch (error) {
      console.error('选择头像失败', error);
    }
  }

  private async selectLocalPhoto(): Promise<string> {
    try {
      const context = this.getHostContext();
      if (typeof requireNapi !== 'function') {
        return '';
      }
      const module = requireNapi('photoAccessHelper');
      if (!module) {
        return '';
      }
      const getHelper = module.getPhotoAccessHelper;
      if (!getHelper) {
        return '';
      }
      const helper = getHelper(context);
      if (!helper) {
        return '';
      }
      const selectFn = helper.select;
      if (!selectFn) {
        return '';
      }
      const options: PhotoSelectOptions = { maxSelectNumber: 1 };
      const result: PhotoSelectResult = await selectFn(options);
      const uris: Array<string> = result.photoUris ? result.photoUris : [];
      const uri = uris.length > 0 ? uris[0] : '';
      return uri || '';
    } catch (error) {
      console.error('选择本地图片失败', error);
      return '';
    }
  }

  private async handlePublish(placeId: string): Promise<void> {
    await this.placeService.publish(placeId, this.authService.getSession());
    await this.refreshPlaces();
  }

  private async handleApply(placeId: string): Promise<void> {
    const session = this.authService.getSession();
    if (session && session.isAdmin) {
      await this.placeService.approve(placeId, session);
    } else {
      await this.placeService.publish(placeId, session);
    }
    await this.refreshPlaces();
  }

  private async handleDelete(placeId: string): Promise<void> {
    const session = this.authService.getSession();
    const ok = await this.placeService.delete(placeId, session);
    if (!ok) {
      promptAction.showToast({ message: this.placeService.getLastError() || '删除失败，请检查权限或网络', duration: 1500 });
      return;
    }
    await this.refreshPlaces();
  }

  private async handleToggleHidden(placeId: string, hidden: boolean): Promise<void> {
    const session = this.authService.getSession();
    if (!session) {
      promptAction.showToast({ message: '请先登录再隐藏地点', duration: 1500 });
      return;
    }
    const ok = await this.placeService.toggleHidden(placeId, hidden, session);
    if (!ok) {
      promptAction.showToast({ message: this.placeService.getLastError() || '操作失败，请检查网络或登录状态', duration: 1500 });
    }
    await this.refreshPlaces();
  }

  private async handleToggleFavorite(placeId: string, favorite: boolean): Promise<void> {
    const session = this.authService.getSession();
    if (!session) {
      promptAction.showToast({ message: '请先登录再收藏地点', duration: 1500 });
      return;
    }
    const ok = await this.placeService.toggleFavorite(placeId, favorite, session);
    if (!ok) {
      promptAction.showToast({ message: this.placeService.getLastError() || '操作失败，请检查网络或登录状态', duration: 1500 });
    }
    await this.refreshPlaces();
  }

  private async handleVote(placeId: string, delta: number): Promise<void> {
    const session = this.authService.getSession();
    if (!session) {
      promptAction.showToast({ message: '请先登录再点赞/踩', duration: 1500 });
      return;
    }
    const ok = await this.placeService.vote(placeId, delta, session);
    if (!ok) {
      promptAction.showToast({ message: this.placeService.getLastError() || '点赞失败，请检查网络或权限', duration: 1500 });
      return;
    }
    this.patchUiPlace(placeId);
    this.updateHotPlaces();
  }

  private async handleFeedback(placeId: string): Promise<void> {
    const session = this.authService.getSession();
    if (!session) {
      promptAction.showToast({ message: '请先登录再提交反馈', duration: 1500 });
      return;
    }
    this.feedbackPlaceId = placeId;
    this.feedbackText = '';
    this.feedbackVisible = true;
  }

  private closeFeedbackDialog(): void {
    this.feedbackVisible = false;
    this.feedbackPlaceId = '';
    this.feedbackText = '';
  }

  private async submitFeedback(): Promise<void> {
    const session = this.getSession();
    if (!session) {
      promptAction.showToast({ message: '请先登录再提交反馈', duration: 1500 });
      return;
    }
    const msg = (this.feedbackText || '').trim();
    if (!msg) {
      promptAction.showToast({ message: '请输入反馈内容', duration: 1500 });
      return;
    }
    const placeId = this.feedbackPlaceId;
    if (!placeId) {
      promptAction.showToast({ message: '反馈对象为空', duration: 1500 });
      return;
    }
    const ok = await this.placeService.reportFeedback(placeId, msg, session);
    if (!ok) {
      promptAction.showToast({ message: this.placeService.getLastError() || '提交失败，请检查网络或权限', duration: 1700 });
      return;
    }
    this.closeFeedbackDialog();
    promptAction.showToast({ message: '已提交反馈', duration: 1500 });
  }

  private async handleApprove(placeId: string): Promise<void> {
    const session = this.authService.getSession();
    const ok = await this.placeService.approve(placeId, session);
    if (!ok) {
      const msg = this.placeService.getLastError() || '操作失败，请检查网络或权限';
      promptAction.showToast({ message: msg, duration: 1700 });
      return;
    }
    await this.refreshPlaces();
  }

  private async handleReject(placeId: string): Promise<void> {
    const session = this.authService.getSession();
    const ok = await this.placeService.reject(placeId, session);
    if (!ok) {
      const msg = this.placeService.getLastError() || '操作失败，请检查网络或权限';
      promptAction.showToast({ message: msg, duration: 1700 });
      return;
    }
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

  private getSessionUsername(): string {
    const session = this.getSession();
    return session ? session.username : '';
  }

  private getSessionEmail(): string {
    const session = this.getSession();
    return session && session.email ? session.email : '';
  }

  private getSelectedPointText(): string {
    const point = this.getSelectedPoint();
    if (!point) {
      return '未选择位置';
    }
    return '位置: ' + String(point.lat.toFixed(5)) + ', ' + String(point.lon.toFixed(5));
  }

  private async loadMessagesForSession(session: UserSession | null): Promise<void> {
    if (!session) {
      this.messages = [];
      this.unreadCount = 0;
      this.showMessages = false;
      return;
    }
    const list = await this.messageService.list(session);
    const normalized: Array<UserMessage> = [];
    const localReadAt = this.lastMessageReadAt;
    let maxReadAt = localReadAt;
    list.forEach((msg) => {
      const raw = msg as RawUserMessage;
      const createdAt = typeof msg.createdAt === 'number'
        ? msg.createdAt
        : (typeof raw.date === 'number' ? raw.date : Date.now());

      // Prefer server persistence fields when present.
      const serverRead = typeof raw.read === 'boolean'
        ? raw.read
        : (typeof msg.read === 'boolean' ? msg.read : undefined);
      const serverReadAt = typeof raw.readAt === 'number'
        ? raw.readAt
        : (typeof msg.readAt === 'number' ? msg.readAt : 0);
      if (typeof serverReadAt === 'number' && Number.isFinite(serverReadAt) && serverReadAt > maxReadAt) {
        maxReadAt = serverReadAt;
      }

      const baseUnread = typeof serverRead === 'boolean'
        ? (!serverRead)
        : (msg.unread === undefined ? true : msg.unread);
      const effectiveReadAt = Math.max(localReadAt, (typeof serverReadAt === 'number' ? serverReadAt : 0));
      const unread = baseUnread && createdAt > effectiveReadAt;
      const type = raw.type || '';
      const title = msg.title || (type === 'feedback'
        ? '地点反馈'
        : (type === 'approve'
          ? '审核通过'
          : (type === 'reject'
            ? '审核未通过'
            : (type === 'delete'
              ? '地点已删除'
              : '消息提醒'))));
      const content = msg.content || raw.message || '';
      const username = msg.username || raw.userId || '';
      let placeSnapshot = msg.place;
      if (!placeSnapshot && raw.placeId) {
        const found = this.findPlaceById(String(raw.placeId));
        if (found) {
          placeSnapshot = this.buildMessageSnapshot(found);
        }
      }
      normalized.push({
        id: msg.id,
        username,
        title,
        content,
        createdAt,
        unread,
        action: msg.action,
        place: placeSnapshot
      });
    });
    const limited: Array<UserMessage> = [];
    const max = this.messagePageSize;
    for (let i = 0; i < normalized.length && i < max; i += 1) {
      limited.push(normalized[i]);
    }
    this.messages = limited;
    this.unreadCount = session.isAdmin ? 0 : normalized.filter((msg) => msg.unread).length;

    // If server reports a newer readAt than local cache, persist it locally too.
    if (!session.isAdmin && maxReadAt > this.lastMessageReadAt) {
      this.lastMessageReadAt = maxReadAt;
      await this.persistMessageReadAt(session.username, this.lastMessageReadAt);
    }
  }

  private async pushMessage(username: string, message: UserMessage): Promise<void> {
    const session = this.getSession();
    if (!session) {
      return;
    }
    await this.messageService.pushMessage(username, message, session);
    if (!session.isAdmin && session.username === username) {
      const list: Array<UserMessage> = [message];
      this.messages.forEach((msg) => list.push(msg));
      this.messages = list;
      this.unreadCount = list.filter((msg) => msg.unread).length;
    }
  }

  private async markAllMessagesRead(): Promise<void> {
    const session = this.getSession();
    if (!session || session.isAdmin) {
      return;
    }
    await this.messageService.markAllRead(session);
    this.lastMessageReadAt = Date.now();
    await this.persistMessageReadAt(session.username, this.lastMessageReadAt);
    const list: Array<UserMessage> = [];
    this.messages.forEach((msg) => {
      msg.unread = false;
      list.push(msg);
    });
    this.messages = list.slice();
    this.unreadCount = 0;
  }

  private async toggleMessagesPanel(): Promise<void> {
    this.showMessages = !this.showMessages;
    if (!this.showMessages) {
      return;
    }
    const session = this.getSession();
    if (session) {
      await this.loadMessagesForSession(session);
      // Opening the panel is treated as "read".
      if (!session.isAdmin && this.unreadCount > 0) {
        await this.markAllMessagesRead();
      }
    }
  }

  private formatMessageTime(ts: number): string {
    if (!Number.isFinite(ts)) {
      return '';
    }
    const date = new Date(ts);
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    const hh = String(date.getHours()).padStart(2, '0');
    const mm = String(date.getMinutes()).padStart(2, '0');
    return `${y}-${m}-${d} ${hh}:${mm}`;
  }

  private buildMessageSnapshot(place: Place): MessagePlaceSnapshot {
    return {
      name: place.name,
      description: place.description || '',
      lat: place.lat,
      lon: place.lon,
      type: place.type,
      imageUrl: place.imageUrl || '',
      sourceKey: place.sourceKey || '',
      sourceType: place.sourceType || '',
      sourcePlaceId: place.sourcePlaceId || ''
    };
  }

  private findPlaceById(placeId: string): Place | null {
    const found = this.places.find((place) => place.id === placeId);
    if (found) {
      return found;
    }
    const pending = this.pendingPlaces.find((place) => place.id === placeId);
    return pending || null;
  }

  private findCachedPlaceByIdOrSourceKey(placeId: string): Place | null {
    const cached = this.placeService.getCachedPlaces();
    const direct = cached.find((p) => p.id === placeId);
    if (direct) {
      return direct;
    }
    const current = this.findPlaceById(placeId);
    const sourceKey = current ? (current.sourceKey || '') : '';
    if (sourceKey) {
      const byKey = cached.find((p) => (p.sourceType === 'system' || p.sourceKey) && p.sourceKey === sourceKey);
      return byKey || null;
    }
    return null;
  }

  private patchUiPlace(placeId: string): void {
    const updated = this.findCachedPlaceByIdOrSourceKey(placeId);
    if (!updated) {
      return;
    }
    const sourceKey = updated.sourceKey || '';
    const match = (p: Place): boolean => {
      if (p.id === placeId || p.id === updated.id) {
        return true;
      }
      return !!sourceKey && p.sourceKey === sourceKey;
    };

    this.places = this.places.map((p) => match(p) ? updated : p);
    this.pendingPlaces = this.pendingPlaces.map((p) => match(p) ? updated : p);
    this.myPlaces = this.myPlaces.map((p) => match(p) ? updated : p);
    this.hotPlaces = this.hotPlaces.map((p) => match(p) ? updated : p);
    if (this.tapPlace && match(this.tapPlace)) {
      this.tapPlace = updated;
    }
    if (this.detailPlace && match(this.detailPlace)) {
      this.detailPlace = updated;
    }
  }

  private getPlaceOwnerName(place: Place): string {
    if (place.ownerName) {
      return place.ownerName;
    }
    if (place.ownerId) {
      return place.ownerId;
    }
    return '';
  }

  private handleResubmitMessage(message: UserMessage): void {
    if (!message.place) {
      return;
    }
    this.placeName = message.place.name;
    this.placeDesc = message.place.description || '';
    this.placeImage = message.place.imageUrl || '';
    this.placeType = message.place.type;
    this.selectedPoint = { lat: message.place.lat, lon: message.place.lon };
    this.editingPlaceId = '';
    this.editingSourceKey = message.place.sourceKey || '';
    this.editingSourceType = message.place.sourceType || '';
    this.editingSourcePlaceId = message.place.sourcePlaceId || '';
    this.showMessages = false;
    this.currentPage = PageView.AddPlace;
  }

  private getAdminAllPlaces(): Array<Place> {
    const map = new Map<string, Place>();
    this.places.forEach((place) => map.set(place.id, place));
    this.pendingPlaces.forEach((place) => map.set(place.id, place));
  return Array.from(map.values()).sort((a: Place, b: Place) => (b.updatedAt || b.createdAt) - (a.updatedAt || a.createdAt));
  }

  private getAdminSystemPlaces(): Array<Place> {
    return this.getAdminAllPlaces().filter((place) => place.sourceType === 'system' || !place.ownerId);
  }

  private getAdminDraftPlaces(): Array<Place> {
    const session = this.getSession();
    if (!session) {
      return [];
    }
    return this.getAdminAllPlaces().filter((place) => place.ownerId === session.username && (place.status === 'draft' || place.status === 'private'));
  }

  private getAdminUserPlaces(): Array<Place> {
    const session = this.getSession();
    const adminName = session ? session.username : '';
    return this.getAdminAllPlaces().filter((place) => place.ownerId && place.ownerId !== adminName);
  }

  private getMyPlaces(): Array<Place> {
    const s = this.getSession();
    if (!s) {
      return [];
    }
    return this.places.filter((p: Place) => p.ownerId === s.username && (p.status === 'approved' || p.status === 'published'));
  }

  private getMyPendingCount(): number {
    const s = this.getSession();
    if (!s) {
      return 0;
    }
    return this.places.filter((p: Place) => p.ownerId === s.username && p.status === 'pending').length;
  }

  private getMyPlacesByTab(): Array<Place> {
    if (!this.getSession()) {
      return [];
    }
    const list = this.myPlaces.slice();
    switch (this.myPlacesTab) {
      case 'favorite':
        return this.getFavoritePlacesFromCache();
      case 'hidden':
        return this.getHiddenPlacesFromCache();
      case 'pending':
        return list.filter((p) => p.status === 'pending');
      case 'approved':
        return list.filter((p) => p.status === 'approved' || p.status === 'published');
      default:
        return list;
    }
  }

  private getKnownPlacesMap(): Map<string, Place> {
    const map = new Map<string, Place>();
    const cached = this.placeService.getCachedPlaces();
    for (const p of cached) {
      map.set(p.id, p);
    }
    for (const p of this.myPlaces) {
      map.set(p.id, p);
    }
    return map;
  }

  private getFavoritePlacesFromCache(): Array<Place> {
    const session = this.getSession();
    if (!session) {
      return [];
    }
    const ids = this.placeService.getFavoritePlaceIds(session);
    const map = this.getKnownPlacesMap();
    const out: Array<Place> = [];
    for (const id of ids) {
      const p = map.get(id);
      if (p) {
        out.push(p);
      }
    }
    return out;
  }

  private getHiddenPlacesFromCache(): Array<Place> {
    const session = this.getSession();
    if (!session) {
      return [];
    }
    const ids = this.placeService.getHiddenPlaceIds(session);
    const map = this.getKnownPlacesMap();
    const out: Array<Place> = [];
    for (const id of ids) {
      const p = map.get(id);
      if (p) {
        out.push(p);
      }
    }
    return out;
  }

  private getHotTop(count: number): Array<Place> {
    return this.hotPlaces.slice(0, count);
  }

  private async handleAdminApply(place: Place): Promise<void> {
    const session = this.getSession();
    if (!session || !session.isAdmin) {
      return;
    }
    await this.placeService.updatePlace(place.id, {
      name: place.name,
      description: place.description || '',
      type: place.type,
      imageUrl: place.imageUrl || '',
      point: { lat: place.lat, lon: place.lon },
      status: 'approved'
    }, session);
    await this.refreshPlaces();
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
    const startPoint = this.route ? this.route.start : this.routeStart;
    const endPoint = this.route ? this.route.end : this.routeEnd;
    if (startPoint) {
      markers.push({ lat: startPoint.lat, lon: startPoint.lon, label: '起', kind: 'start' });
    }
    if (endPoint) {
      markers.push({ lat: endPoint.lat, lon: endPoint.lon, label: '终', kind: 'end' });
    }
    if (this.focusPlace) {
      markers.push({ lat: this.focusPlace.lat, lon: this.focusPlace.lon, label: '查看位置', kind: 'focus' });
    }
    return markers;
  }

  @Builder
  private buildSearchBar(title: string, value: string, isStart: boolean): void {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(11)
        .fontColor(this.nightMode ? '#c7d2e6' : '#7c8699');
      Text(value ? value : (isStart ? '请选择起点' : '请选择终点'))
        .fontSize(14)
        .fontColor(this.nightMode ? '#ffffff' : '#222f3d')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
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
  .backgroundColor(this.authService.getSession() ? this.colorPrimary : '#8a93a5')
    .borderRadius(20)
    .shadow({ radius: 10, color: 'rgba(30, 60, 120, 0.2)', offsetX: 0, offsetY: 4 })
    .onClick(() => {
      const session = this.getSession();
      this.currentPage = session ? PageView.Profile : PageView.Login;
      if (session) {
        void this.loadMessagesForSession(session);
        void this.loadMyPlaces();
        void this.refreshPlaces();
      }
    });
  }

  @Builder
  private buildLoginPage(): void {
    Column() {
      Row() {
        Button('返回').onClick(() => { this.currentPage = PageView.Map; });
        Text('登录 / 注册')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 });
      }.margin({ bottom: 16 });

      Column({ space: 12 }) {
        Image($r('app.media.campus_banner'))
          .width('100%')
          .height(150)
          .borderRadius(12)
          .margin({ bottom: 16 })
          .shadow({ radius: 14, color: 'rgba(0, 0, 0, 0.15)', offsetX: 0, offsetY: 8 });

        Text('登录后可保存自定义地点、参与投票与反馈')
          .fontSize(12)
          .fontColor('#7c8699')
          .textAlign(TextAlign.Center);

        Text('注册仅需账号密码，邮箱可在个人中心绑定')
          .fontSize(11)
          .fontColor('#98a2b3')
          .textAlign(TextAlign.Center);

        TextInput({ text: this.username, placeholder: '用户名' })
          .backgroundColor('#f5f6fa')
          .borderRadius(10)
          .padding({ left: 10, right: 10 })
          .onChange((value: string) => { this.username = value; });
        TextInput({ text: this.password, placeholder: '密码' })
          .type(InputType.Password)
          .backgroundColor('#f5f6fa')
          .borderRadius(10)
          .padding({ left: 10, right: 10 })
          .onChange((value: string) => { this.password = value; });

        // Login page only contains username/password and links to register/reset

        Row({ space: 8 }) {
          Button(this.rememberMe ? '✓ 记住我' : '记住我')
            .height(28)
            .fontSize(11)
            .backgroundColor(this.rememberMe ? this.colorPrimary : this.colorPrimaryLight)
            .fontColor(this.rememberMe ? '#ffffff' : this.colorPrimary)
            .onClick(() => { this.rememberMe = !this.rememberMe; });
          Blank().layoutWeight(1);
          Text('忘记密码?')
            .fontSize(11)
            .fontColor('#7c8699')
            .onClick(() => {
              this.resetEmail = this.username;
              this.resetCode = '';
              this.resetNewPassword = '';
              this.currentPage = PageView.ResetPassword;
            });
        }

        Row({ space: 12 }) {
          Button('登录')
            .backgroundColor(this.colorPrimary)
            .fontColor('#ffffff')
            .layoutWeight(1)
            .onClick(() => { this.handleLogin(); });
        }

        Row({ space: 4 }) {
          Text('没有账号？')
            .fontSize(12)
            .fontColor('#7c8699');
          Text('去注册')
            .fontSize(12)
            .fontColor(this.colorPrimary)
            .onClick(() => { this.currentPage = PageView.Register; });
        }

        if (this.authError) {
          Text(this.authError)
            .fontSize(12)
            .fontColor('#ff4d4f')
            .margin({ top: 4 });
        }
      }
      .padding(16)
      .backgroundColor(this.colorSurface)
      .borderRadius(16)
      .shadow({ radius: 12, color: 'rgba(15, 25, 45, 0.08)', offsetX: 0, offsetY: 6 });
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor(this.colorBg);
  }

    @Builder
    private buildRegisterPage(): void {
      Column({ space: 12 }) {
        Row() {
          Button('返回')
            .backgroundColor(this.colorPrimaryLight)
            .fontColor(this.colorPrimary)
            .onClick(() => { this.currentPage = PageView.Login; });
          Text('注册')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .margin({ left: 12 });
        }.margin({ bottom: 12 });

        TextInput({ text: this.username, placeholder: '用户名' })
          .backgroundColor('#f5f6fa')
          .borderRadius(10)
          .padding({ left: 10, right: 10 })
          .onChange((value: string) => { this.username = value; });

        TextInput({ text: this.password, placeholder: '密码' })
          .type(InputType.Password)
          .backgroundColor('#f5f6fa')
          .borderRadius(10)
          .padding({ left: 10, right: 10 })
          .onChange((value: string) => { this.password = value; });

        Button('注册')
          .backgroundColor(this.colorPrimary)
          .fontColor('#ffffff')
          .onClick(() => { this.handleRegister(); });

        Row() {
          Text('已有账号？')
            .fontSize(12)
            .fontColor('#7c8699');
          Text('去登录')
            .fontSize(12)
            .fontColor(this.colorPrimary)
            .onClick(() => { this.currentPage = PageView.Login; });
        }
      }
      .padding(16)
      .width('100%')
      .height('100%')
      .backgroundColor(this.colorBg);
    }

  @Builder
  private buildBindEmailPage(): void {
    Column({ space: 12 }) {
      Row() {
        Button('返回')
          .backgroundColor(this.colorPrimaryLight)
          .fontColor(this.colorPrimary)
          .onClick(() => {
          if (this.bindingRequired) {
            this.authService.logout();
            this.updateSessionStatus(null);
            this.currentPage = PageView.Login;
          } else {
            this.currentPage = PageView.Profile;
          }
        });
        Text('绑定邮箱')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 });
      }.margin({ bottom: 12 });

      Text('为保障账号安全，请先绑定邮箱')
        .fontSize(12)
        .fontColor('#7c8699');
      if (this.bindingRequired) {
        Text('该账号尚未绑定邮箱，请先完成绑定')
          .fontSize(11)
          .fontColor('#ff4d4f');
      }

      TextInput({ text: this.bindEmail, placeholder: '邮箱' })
        .backgroundColor('#f5f6fa')
        .borderRadius(10)
        .padding({ left: 10, right: 10 })
        .onChange((value: string) => { this.bindEmail = value; });

      Row({ space: 8 }) {
        TextInput({ text: this.bindCode, placeholder: '邮箱验证码' })
          .backgroundColor('#f5f6fa')
          .borderRadius(10)
          .padding({ left: 10, right: 10 })
          .layoutWeight(1)
          .onChange((value: string) => { this.bindCode = value; });
        Button('发送验证码')
          .height(32)
          .fontSize(12)
          .backgroundColor(this.colorPrimary)
          .fontColor('#ffffff')
          .onClick(() => { this.sendBindCode(); });
      }

      Button('确认绑定')
        .backgroundColor(this.colorPrimary)
        .fontColor('#ffffff')
        .onClick(() => { this.handleBindEmail(); });
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor(this.colorBg);
  }

  @Builder
  private buildResetPasswordPage(): void {
    Column({ space: 12 }) {
      Row() {
        Button('返回')
          .backgroundColor(this.colorPrimaryLight)
          .fontColor(this.colorPrimary)
          .onClick(() => { this.currentPage = PageView.Login; });
        Text('找回密码')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 });
      }.margin({ bottom: 12 });

      TextInput({ text: this.username, placeholder: '账号' })
        .backgroundColor('#f5f6fa')
        .borderRadius(10)
        .padding({ left: 10, right: 10 })
        .onChange((value: string) => { this.username = value; });

      TextInput({ text: this.resetEmail, placeholder: '绑定邮箱' })
        .backgroundColor('#f5f6fa')
        .borderRadius(10)
        .padding({ left: 10, right: 10 })
        .onChange((value: string) => { this.resetEmail = value; });

      Row({ space: 8 }) {
        TextInput({ text: this.resetCode, placeholder: '邮箱验证码' })
          .backgroundColor('#f5f6fa')
          .borderRadius(10)
          .padding({ left: 10, right: 10 })
          .layoutWeight(1)
          .onChange((value: string) => { this.resetCode = value; });
        Button('发送验证码')
          .height(32)
          .fontSize(12)
          .backgroundColor(this.colorPrimary)
          .fontColor('#ffffff')
          .onClick(() => { this.sendResetCode(); });
      }

      TextInput({ text: this.resetNewPassword, placeholder: '新密码' })
        .type(InputType.Password)
        .backgroundColor('#f5f6fa')
        .borderRadius(10)
        .padding({ left: 10, right: 10 })
        .onChange((value: string) => { this.resetNewPassword = value; });

      Button('重置密码')
        .backgroundColor(this.colorPrimary)
        .fontColor('#ffffff')
        .onClick(() => { this.handleResetPassword(); });
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor(this.colorBg);
  }

  @Builder
  private buildMapPage(): void {
    Stack() {
      MapCanvas({
        renderData: this.renderData,
        route: this.routeVisible ? this.route : null,
        markers: this.buildRouteMarkers(),
        places: this.places,
        currentUser: this.getSessionUsername(),
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
              if (this.isOffCampus) {
                Row() {
                  Text('📍 您当前不在学校范围内')
                    .fontSize(12)
                    .fontColor('#ffffff');
                }
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .backgroundColor('#f59e0b')
                .borderRadius(10)
                .width('100%');
              }
              if (this.hazardWarningVisible && this.hazardWarningText) {
                Row() {
                  Text('⚠ ' + this.hazardWarningText)
                    .fontSize(12)
                    .fontColor('#ffffff');
                }
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .backgroundColor('#ef4444')
                .borderRadius(10)
                .width('100%');
              }
              Row() {
                Column({ space: 6 }) {
                  this.buildSearchBar('起点', this.routeStartLabel, true);
                  this.buildSearchBar('终点', this.routeEndLabel, false);
                }
                .layoutWeight(1)
                .margin({ right: 8 });

                Column({ space: 8 }) {
                  Button('热点')
                    .fontSize(12)
                    .width(64)
                    .height(32)
                    .backgroundColor(this.colorPrimary)
                    .fontColor('#ffffff')
                    .onClick(() => { void this.openHotPlaces(); });
                  Button('刷新')
                    .fontSize(12)
                    .width(64)
                    .height(32)
                    .backgroundColor(this.colorPrimaryLight)
                    .fontColor(this.colorPrimary)
                    .onClick(() => { void this.refreshPlaces(); });
                  Button('定位')
                    .fontSize(12)
                    .width(64)
                    .height(32)
                    .backgroundColor(this.colorPrimary)
                    .fontColor('#ffffff')
                    .onClick(() => {
                      this.centerMapOnMyLocation();
                    });
                  if (this.dynamicNavActive) {
                    Button('停止')
                      .fontSize(12)
                      .width(64)
                      .height(32)
                      .backgroundColor('#ffecec')
                      .fontColor(this.colorDanger)
                      .onClick(() => this.stopNavigation());
                  }
                  Button(this.nightMode ? '日间' : '夜间')
                    .onClick(() => this.toggleNightMode())
                    .fontSize(12)
                    .width(64)
                    .height(32)
                    .backgroundColor(this.colorPrimary)
                    .fontColor('#ffffff');
                  Button('规划路线')
                    .fontSize(12)
                    .width(88)
                    .height(32)
                    .backgroundColor(this.colorPrimary)
                    .fontColor('#ffffff')
                    .onClick(() => this.handlePlanRouteClick());
                  this.buildAvatarButton();
                }
              }

            }
            .padding({ left: 12, right: 12, top: 12, bottom: 10 })
            .backgroundColor(this.nightMode ? 'rgba(12, 20, 36, 0.72)' : 'rgba(255, 255, 255, 0.9)')
            .borderRadius(12)
            .width('100%')
            .hitTestBehavior(HitTestMode.Default)
            .zIndex(3);
          }

          // Focus view overlay: when user taps "查看位置" from lists/details
          if (this.focusPlace) {
            Row({ space: 10 }) {
              Button('返回')
                .height(34)
                .fontSize(12)
                .backgroundColor(this.colorPrimary)
                .fontColor('#ffffff')
                .onClick(() => this.exitFocusView());
              Column() {
                Text('查看位置')
                  .fontSize(12)
                  .fontColor(this.nightMode ? '#c7d2e6' : '#7c8699');
                Text(this.focusPlace.name)
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.nightMode ? '#ffffff' : '#1d2a42');
              }
              .layoutWeight(1);
            }
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(this.nightMode ? 'rgba(12, 20, 36, 0.72)' : 'rgba(255, 255, 255, 0.92)')
            .borderRadius(12)
            .width('100%')
            .margin({ left: 12, right: 12, top: 10 })
            .zIndex(4);

            Column() {
              Row({ space: 12 }) {
                Button('导航前往')
                  .layoutWeight(1)
                  .height(40)
                  .backgroundColor(this.colorPrimary)
                  .fontColor('#ffffff')
                  .onClick(() => this.navigateToFocusPlace());
                Button('取消')
                  .layoutWeight(1)
                  .height(40)
                  .backgroundColor(this.colorPrimaryLight)
                  .fontColor(this.colorPrimary)
                  .onClick(() => this.cancelFocusView());
              }
            }
            .padding(14)
            .width('94%')
            .backgroundColor(this.nightMode ? 'rgba(20, 32, 54, 0.94)' : 'rgba(255, 255, 255, 0.98)')
            .borderRadius(14)
            .alignSelf(ItemAlign.Center)
            .margin({ bottom: 96, top: 0 })
            .zIndex(4);
          }

          Column() {
              if (this.showUi && this.tapActionVisible) {
                Column() {
                  if (this.tapPlace) {
                    Text(this.tapPlace.name).fontSize(14).fontWeight(FontWeight.Bold);
                    Text(this.renderPlaceTypeLabel(this.tapPlace.type) + ' · ' + this.renderPlaceStatus(this.tapPlace.status))
                      .fontSize(11)
                      .fontColor('#7c8699');
                    Row({ space: 12 }) {
                      Text('赞 ' + String(this.tapPlace.likes))
                        .fontSize(11)
                        .fontColor(this.colorAccent);
                      Text('踩 ' + String(this.tapPlace.dislikes))
                        .fontSize(11)
                        .fontColor(this.colorDanger);
                    }
                    Column({ space: 8 }) {
                      if (this.getSession()) {
                        Row({ space: 8 }) {
                              Button(this.voteButtonLabel(this.tapPlace.id, 1))
                            .layoutWeight(1)
                            .height(34)
                            .fontSize(12)
                            .backgroundColor(this.colorPrimary)
                            .fontColor('#ffffff')
                                .onClick(() => {
                                  const place = this.tapPlace;
                                  if (place) {
                                    void this.handleVote(place.id, 1);
                                  }
                                });
                              Button(this.voteButtonLabel(this.tapPlace.id, -1))
                            .layoutWeight(1)
                            .height(34)
                            .fontSize(12)
                            .backgroundColor(this.colorPrimaryLight)
                            .fontColor(this.colorPrimary)
                                .onClick(() => {
                                  const place = this.tapPlace;
                                  if (place) {
                                    void this.handleVote(place.id, -1);
                                  }
                                });
                        }
                        .width('100%');
                      } else {
                        Text('登录后可点赞/收藏/隐藏')
                          .fontSize(11)
                          .fontColor('#7c8699');
                      }

                      Row({ space: 8 }) {
                        Button(this.isPlaceFavorite(this.tapPlace.id) ? '取消收藏' : '收藏')
                          .layoutWeight(1)
                          .height(34)
                          .fontSize(12)
                          .backgroundColor(this.colorPrimaryLight)
                          .fontColor(this.colorPrimary)
                          .onClick(() => {
                            const place = this.tapPlace;
                            if (place) {
                              void this.handleToggleFavorite(place.id, !this.isPlaceFavorite(place.id));
                            }
                          });
                        Button(this.isPlaceHidden(this.tapPlace.id) ? '显示' : '隐藏')
                          .layoutWeight(1)
                          .height(34)
                          .fontSize(12)
                          .backgroundColor(this.colorPrimaryLight)
                          .fontColor(this.colorPrimary)
                          .onClick(() => {
                            const place = this.tapPlace;
                            if (place) {
                              void this.handleToggleHidden(place.id, !this.isPlaceHidden(place.id));
                            }
                          });
                      }
                      .width('100%');

                      if (this.isMinePlace(this.tapPlace)) {
                        Row({ space: 8 }) {
                          Button('编辑')
                            .layoutWeight(1)
                            .height(34)
                            .fontSize(12)
                            .backgroundColor('#f0f2f7')
                            .fontColor('#1d2a42')
                            .onClick(() => {
                              const place = this.tapPlace;
                              if (place) {
                                this.openEditPlace(place, false);
                              }
                            });
                          if (this.tapPlace.status === 'draft' || this.tapPlace.status === 'private' || this.tapPlace.status === 'rejected') {
                            Button(this.isAdmin() ? '确认修改并应用' : '提交审核')
                              .layoutWeight(1)
                              .height(34)
                              .fontSize(12)
                              .backgroundColor(this.colorPrimary)
                              .fontColor('#ffffff')
                              .onClick(() => {
                                const place = this.tapPlace;
                                if (place) {
                                  void this.handleApply(place.id);
                                }
                              });
                          }
                          Button('删除')
                            .layoutWeight(1)
                            .height(34)
                            .fontSize(12)
                            .backgroundColor('#ffecec')
                            .fontColor(this.colorDanger)
                            .onClick(() => {
                              const place = this.tapPlace;
                              if (place) {
                                this.handleDelete(place.id);
                              }
                            });
                        }
                        .width('100%');
                      } else {
                        Row({ space: 8 }) {
                          Button(this.isAdmin() ? '修改' : '申请修改')
                            .layoutWeight(1)
                            .height(34)
                            .fontSize(12)
                            .backgroundColor('#f0f2f7')
                            .fontColor('#1d2a42')
                            .onClick(() => {
                              const place = this.tapPlace;
                              if (place) {
                                this.openEditPlace(place, true);
                              }
                            });
                          Button('反馈')
                            .layoutWeight(1)
                            .height(34)
                            .fontSize(12)
                            .backgroundColor('#f0f2f7')
                            .fontColor('#1d2a42')
                            .onClick(() => {
                              const place = this.tapPlace;
                              if (place) {
                                void this.handleFeedback(place.id);
                              }
                            });
                        }
                        .width('100%');

                        if (this.isAdmin()) {
                          Row({ space: 8 }) {
                            Button('删除')
                              .layoutWeight(1)
                              .height(34)
                              .fontSize(12)
                              .backgroundColor('#ffecec')
                              .fontColor(this.colorDanger)
                              .onClick(() => {
                                const place = this.tapPlace;
                                if (place) {
                                  this.handleDelete(place.id);
                                }
                              });
                          }
                          .width('100%');
                        }
                      }

                      if (this.isAdmin() && this.tapPlace.status === 'pending') {
                        Row({ space: 8 }) {
                          Button('通过')
                            .layoutWeight(1)
                            .height(34)
                            .fontSize(12)
                            .backgroundColor('#e8f7f1')
                            .fontColor(this.colorAccent)
                            .onClick(() => {
                              const place = this.tapPlace;
                              if (place) {
                                void this.handleApprove(place.id);
                              }
                            });
                          Button('拒绝')
                            .layoutWeight(1)
                            .height(34)
                            .fontSize(12)
                            .backgroundColor('#ffecec')
                            .fontColor(this.colorDanger)
                            .onClick(() => {
                              const place = this.tapPlace;
                              if (place) {
                                void this.handleReject(place.id);
                              }
                            });
                        }
                        .width('100%');
                      }
                    }
                    .width('100%');
                  } else {
                    Text('该位置暂无地点').fontSize(12).fontColor('#7c8699');
                    Button('添加地点')
                      .backgroundColor(this.colorPrimary)
                      .fontColor('#ffffff')
                      .onClick(() => this.openAddPlaceFromTap());
                    Button('标记为水雷')
                      .backgroundColor(this.colorPrimaryLight)
                      .fontColor(this.colorPrimary)
                      .onClick(() => { void this.handleMarkWaterMine(); });
                  }
                  Button('关闭')
                    .backgroundColor(this.colorPrimaryLight)
                    .fontColor(this.colorPrimary)
                    .onClick(() => this.closeTapAction());
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
                    .onClick(() => {
                      this.showNearestWaterMineInfo();
                      this.toggleHazardMode();
                    })
                    .fontSize(12)
                    .width(96)
                    .height(38)
                    .backgroundColor(this.hazardMode ? this.colorPrimary : this.colorPrimaryLight)
                    .fontColor(this.hazardMode ? '#ffffff' : this.colorPrimary)
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
                    .backgroundColor(this.colorPrimaryLight)
                    .fontColor(this.colorPrimary)
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
                      .backgroundColor(this.colorPrimaryLight)
                      .borderRadius(12)
                      .onClick(() => { this.zoom = this.zoom + 0.2; });
                      Button() {
                        Text('－')
                          .fontSize(18)
                          .fontColor('#1d2a42');
                      }
                      .width(44)
                      .height(44)
                      .backgroundColor(this.colorPrimaryLight)
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

          if (this.feedbackVisible) {
            Stack() {
              Column() {}
                .width('100%')
                .height('100%')
                .backgroundColor('rgba(0,0,0,0.35)')
                .onClick(() => { this.closeFeedbackDialog(); });

              Column({ space: 10 }) {
                Text('提交反馈')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.nightMode ? '#ffffff' : '#1d2a42');
                Text('请描述该地点的问题或建议')
                  .fontSize(11)
                  .fontColor(this.nightMode ? '#c7d2e6' : '#7c8699');
                TextInput({ text: this.feedbackText, placeholder: '例如：位置偏移、名称错误、描述不准确…' })
                  .onChange((v: string) => { this.feedbackText = v; })
                  .backgroundColor(this.nightMode ? '#0f172a' : '#f5f6fa')
                  .fontColor(this.nightMode ? '#ffffff' : '#1d2a42')
                  .borderRadius(10)
                  .padding({ left: 10, right: 10 })
                  .height(44);
                Row({ space: 10 }) {
                  Button('取消')
                    .layoutWeight(1)
                    .height(36)
                    .backgroundColor(this.colorPrimaryLight)
                    .fontColor(this.colorPrimary)
                    .onClick(() => { this.closeFeedbackDialog(); });
                  Button('提交')
                    .layoutWeight(1)
                    .height(36)
                    .backgroundColor(this.colorPrimary)
                    .fontColor('#ffffff')
                    .onClick(() => { void this.submitFeedback(); });
                }
                .width('100%');
              }
              .padding(14)
              .width('92%')
              .backgroundColor(this.nightMode ? 'rgba(20, 32, 54, 0.96)' : 'rgba(255, 255, 255, 0.98)')
              .borderRadius(14)
              .alignSelf(ItemAlign.Center);
            }
            .width('100%')
            .height('100%')
            .zIndex(10);
          }
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
    .backgroundColor(this.colorBg);
  }

  @Builder
  private buildProfilePage(): void {
    Scroll() {
      Column() {
      Row() {
        Button('返回').onClick(() => { this.currentPage = PageView.Map; });
        Text('个人中心').fontSize(16).fontWeight(FontWeight.Bold).margin({ left: 12 });
        Blank().layoutWeight(1);
        if (this.getSession() && !this.isAdmin()) {
          Stack() {
            Text('🔔')
              .fontSize(16)
              .fontColor('#1d2a42');
            if (this.unreadCount > 0) {
              Text(String(this.unreadCount))
                .fontSize(10)
                .fontColor('#ffffff')
                .backgroundColor(this.colorDanger)
                .borderRadius(9)
                .padding({ left: 4, right: 4 })
                .position({ x: 12, y: -6 });
            }
          }
          .width(28)
          .height(28)
          .backgroundColor('#ffffff')
          .borderRadius(14)
          .shadow({ radius: 6, color: 'rgba(15, 25, 45, 0.12)', offsetX: 0, offsetY: 2 })
          .onClick(() => {
            void this.toggleMessagesPanel();
          });
        }
      }.margin({ bottom: 12 });

      Column({ space: 10 }) {
        Row({ space: 12 }) {
          Stack() {
            if (this.profileAvatarUrl) {
              Image(this.profileAvatarUrl).width('100%').height('100%').borderRadius(26);
            } else {
              Text(this.getSession() ? '我' : '游客')
                .fontSize(14)
                .fontColor('#ffffff');
            }
          }
          .width(52)
          .height(52)
          .backgroundColor(this.getSession() ? this.colorPrimary : '#8a93a5')
          .borderRadius(26);

          Column({ space: 4 }) {
            Text(this.getSession() ? this.getSessionUsername() : '游客模式')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1d2a42');
            Text(this.getSession() ? '欢迎回来，查看你的地点与审核' : '登录后可保存地点与参与互动')
              .fontSize(12)
              .fontColor('#7c8699');
          }
        }

        if (!this.getSession()) {
          Button('去登录')
            .backgroundColor(this.colorPrimary)
            .fontColor('#ffffff')
            .onClick(() => { this.currentPage = PageView.Login; });
        } else {
          Button('退出登录')
            .backgroundColor(this.colorPrimaryLight)
            .fontColor(this.colorPrimary)
            .onClick(() => this.handleLogout());
        }
      }
      .padding(14)
      .backgroundColor(this.colorSurface)
      .borderRadius(14)
      .shadow({ radius: 10, color: 'rgba(15, 25, 45, 0.06)', offsetX: 0, offsetY: 4 })
      .margin({ bottom: 12 });

      if (this.getSession()) {
        Column({ space: 10 }) {
          Row() {
            Text('邮箱绑定')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1d2a42');
            Blank().layoutWeight(1);
            if (this.getSessionEmail()) {
              Text('已绑定: ' + this.getSessionEmail())
                .fontSize(11)
                .fontColor('#7c8699');
            } else {
              Text('未绑定')
                .fontSize(11)
                .fontColor('#ff4d4f');
            }
          }

          TextInput({ text: this.bindEmail, placeholder: '请输入邮箱' })
            .backgroundColor('#f5f6fa')
            .borderRadius(10)
            .padding({ left: 10, right: 10 })
            .onChange((value: string) => { this.bindEmail = value; });

          Row({ space: 8 }) {
            TextInput({ text: this.bindCode, placeholder: '验证码' })
              .backgroundColor('#f5f6fa')
              .borderRadius(10)
              .padding({ left: 10, right: 10 })
              .layoutWeight(1)
              .onChange((value: string) => { this.bindCode = value; });
            Button('发送验证码')
              .height(32)
              .fontSize(12)
              .backgroundColor(this.colorPrimary)
              .fontColor('#ffffff')
              .onClick(() => { void this.sendBindCode(); });
          }

          Button('确认绑定')
            .backgroundColor(this.colorPrimary)
            .fontColor('#ffffff')
            .onClick(() => { void this.handleBindEmail(); });
        }
        .padding(14)
        .backgroundColor(this.colorSurface)
        .borderRadius(14)
        .shadow({ radius: 10, color: 'rgba(15, 25, 45, 0.06)', offsetX: 0, offsetY: 4 })
        .margin({ bottom: 12 });
      }

      Column({ space: 8 }) {
        Text('我的数据')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1d2a42');
        Row() {
          Column() {
            Text(String(this.getMyPlaces().length))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.colorPrimary);
            Text('投稿数').fontSize(11).fontColor('#7c8699');
          }.layoutWeight(1);
          Column() {
            Text(String(this.getMyPendingCount()))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.colorAccent);
            Text('审核中').fontSize(11).fontColor('#7c8699');
          }.layoutWeight(1);
          Column() {
            Text(String(this.pendingPlaces.length))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.colorWarn);
            Text('待处理').fontSize(11).fontColor('#7c8699');
          }.layoutWeight(1);
        }
      }
      .padding(14)
      .backgroundColor(this.colorSurface)
      .borderRadius(14)
      .shadow({ radius: 10, color: 'rgba(15, 25, 45, 0.06)', offsetX: 0, offsetY: 4 })
      .margin({ bottom: 12 });

      Column({ space: 10 }) {
        Text('定位状态')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1d2a42');

        Row({ space: 8 }) {
          Button('立即更新')
            .fontSize(11)
            .backgroundColor('#f0f2f7')
            .fontColor('#1d2a42')
            .onClick(() => { void this.initMyLocation(); });

          Button('定位到我')
            .fontSize(11)
            .backgroundColor('#f0f2f7')
            .fontColor('#1d2a42')
            .enabled(this.myLocation !== null)
            .onClick(() => { this.centerMapOnMyLocation(); });
        }

        Text(this.myLocationStatusText)
          .fontSize(11)
          .fontColor('#56657a');

        if (this.myLocation) {
          Text(`我的位置: ${this.myLocation.lat.toFixed(6)}, ${this.myLocation.lon.toFixed(6)}`)
            .fontSize(11)
            .fontColor('#1d2a42');
        }
      }
      .padding(14)
      .backgroundColor(this.colorSurface)
      .borderRadius(14)
      .shadow({ radius: 10, color: 'rgba(15, 25, 45, 0.06)', offsetX: 0, offsetY: 4 })
      .margin({ bottom: 12 });

      if (this.getSession()) {
        Button('我的地点')
          .backgroundColor(this.colorPrimaryLight)
          .fontColor(this.colorPrimary)
          .onClick(() => { this.currentPage = PageView.MyPlaces; void this.loadMyPlaces(); })
          .margin({ bottom: 12 });
      }

      if (this.showMessages && this.getSession() && !this.isAdmin()) {
        Column({ space: 8 }) {
          Row() {
            Text('消息提醒')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1d2a42');
            Blank().layoutWeight(1);
            Button('全部已读')
              .fontSize(10)
              .height(26)
              .backgroundColor('#f1edff')
              .fontColor(this.colorPrimary)
              .margin({ right: 6 })
              .onClick(() => { void this.markAllMessagesRead(); });
            Button('刷新')
              .fontSize(10)
              .height(26)
              .backgroundColor('#f0f2f7')
              .fontColor('#39465c')
              .onClick(() => {
                const session = this.getSession();
                if (session) {
                  void this.loadMessagesForSession(session);
                }
              });
          }
          if (this.messages.length === 0) {
            Text('暂无新消息')
              .fontSize(12)
              .fontColor('#7c8699');
          }
          ForEach(this.messages, (msg: UserMessage) => {
            Column({ space: 6 }) {
              Row() {
                Text(msg.title)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(msg.unread ? this.colorPrimary : '#1d2a42');
                Blank().layoutWeight(1);
                Text(this.formatMessageTime(msg.createdAt))
                  .fontSize(10)
                  .fontColor('#9aa4b2');
              }
              Text(msg.content)
                .fontSize(11)
                .fontColor(msg.unread ? '#51607a' : '#9aa4b2');
              if (msg.action === 'resubmit' && msg.place) {
                Button('重新提交')
                  .fontSize(11)
                  .backgroundColor(this.colorPrimary)
                  .fontColor('#ffffff')
                  .onClick(() => { this.handleResubmitMessage(msg); });
              }
            }
            .padding(10)
            .backgroundColor(msg.unread ? '#eef4ff' : '#f7f8fc')
            .borderRadius(10);
          }, (msg: UserMessage) => msg.id);
        }
        .padding(14)
        .backgroundColor(this.colorSurface)
        .borderRadius(14)
        .shadow({ radius: 10, color: 'rgba(15, 25, 45, 0.06)', offsetX: 0, offsetY: 4 })
        .margin({ bottom: 12 });
      }

      if (this.isAdmin()) {
        Row({ space: 10 }) {
          Button('所有地点')
            .fontSize(12)
            .backgroundColor(this.colorPrimary)
            .fontColor('#ffffff')
            .height(36)
            .layoutWeight(1)
            .onClick(() => { this.currentPage = PageView.AdminPlaces; });
          Button('审核与反馈')
            .fontSize(12)
            .backgroundColor(this.colorPrimary)
            .fontColor('#ffffff')
            .height(36)
            .layoutWeight(1)
            .onClick(() => { this.currentPage = PageView.AdminReview; });
        }
        .margin({ bottom: 12 });
      }

      Divider().strokeWidth(1).color('#e1e6ef');
      Text('个人资料').fontSize(13).fontWeight(FontWeight.Bold);
      TextInput({ text: this.profileNickname, placeholder: '昵称' })
        .onChange((value: string) => { this.profileNickname = value; });
      Row({ space: 8 }) {
        Button('选择头像')
          .fontSize(11)
          .backgroundColor('#f0f2f7')
          .fontColor('#1d2a42')
          .onClick(() => { void this.pickAvatarImage(); });
        TextInput({ text: this.profileAvatarUrl, placeholder: '头像地址（可选）' })
          .layoutWeight(1)
          .onChange((value: string) => { this.profileAvatarUrl = value; });
      }
      Button('保存资料')
        .onClick(() => { console.info('Profile saved locally'); })
        .margin({ bottom: 16 });

      }
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor(this.colorBg);
  }

  @Builder
  private buildMyPlacesPage(): void {
    Column() {
      Row() {
        Button('返回').onClick(() => { this.currentPage = PageView.Profile; });
        Text('我的地点')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 });
        Blank().layoutWeight(1);
        Button('刷新')
          .fontSize(11)
          .height(28)
          .backgroundColor('#f0f2f7')
          .fontColor('#1d2a42')
          .onClick(() => { void this.loadMyPlaces(); });
      }.margin({ bottom: 12 });

      Row({ space: 8 }) {
        Button('全部')
          .fontSize(11)
          .backgroundColor(this.myPlacesTab === 'all' ? this.colorPrimary : '#f0f2f7')
          .fontColor(this.myPlacesTab === 'all' ? '#ffffff' : '#1d2a42')
          .onClick(() => { this.myPlacesTab = 'all'; });
        Button('待审核')
          .fontSize(11)
          .backgroundColor(this.myPlacesTab === 'pending' ? this.colorPrimary : '#f0f2f7')
          .fontColor(this.myPlacesTab === 'pending' ? '#ffffff' : '#1d2a42')
          .onClick(() => { this.myPlacesTab = 'pending'; });
        Button('已通过')
          .fontSize(11)
          .backgroundColor(this.myPlacesTab === 'approved' ? this.colorPrimary : '#f0f2f7')
          .fontColor(this.myPlacesTab === 'approved' ? '#ffffff' : '#1d2a42')
          .onClick(() => { this.myPlacesTab = 'approved'; });
        Button('收藏')
          .fontSize(11)
          .backgroundColor(this.myPlacesTab === 'favorite' ? this.colorPrimary : '#f0f2f7')
          .fontColor(this.myPlacesTab === 'favorite' ? '#ffffff' : '#1d2a42')
          .onClick(() => { this.myPlacesTab = 'favorite'; });
        Button('隐藏')
          .fontSize(11)
          .backgroundColor(this.myPlacesTab === 'hidden' ? this.colorPrimary : '#f0f2f7')
          .fontColor(this.myPlacesTab === 'hidden' ? '#ffffff' : '#1d2a42')
          .onClick(() => { this.myPlacesTab = 'hidden'; });
      }
      .margin({ bottom: 12 });

      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.getMyPlacesByTab(), (place: Place) => {
            Column({ space: 6 }) {
              Row() {
                Text(place.name)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold);
                Blank().layoutWeight(1);
                Text(this.renderPlaceStatus(place.status))
                  .fontSize(10)
                  .fontColor('#7c8699');
              }
              if (this.isPlaceHidden(place.id)) {
                Text('已隐藏（地图不显示）')
                  .fontSize(10)
                  .fontColor('#9aa4b2');
              }
              Text(this.renderPlaceTypeLabel(place.type) + ' · ' + (place.description || '无描述'))
                .fontSize(11)
                .fontColor('#7c8699');
              Row({ space: 8 }) {
                Button('查看位置')
                  .fontSize(11)
                  .backgroundColor('#f1edff')
                  .fontColor(this.colorPrimary)
                  .onClick(() => { this.openPlaceOnMap(place, PageView.MyPlaces, 'my'); });
                Button(this.isPlaceFavorite(place.id) ? '取消收藏' : '收藏')
                  .fontSize(11)
                  .backgroundColor('#f0f2f7')
                  .fontColor('#1d2a42')
                  .onClick(() => { void this.handleToggleFavorite(place.id, !this.isPlaceFavorite(place.id)); });
                if (place.status === 'private' || place.status === 'draft') {
                  Button('提交审核')
                    .fontSize(11)
                    .backgroundColor('#e8f7f1')
                    .fontColor(this.colorAccent)
                    .onClick(() => { void this.handleSubmitReview(place); });
                }
                Button(this.isPlaceHidden(place.id) ? '显示' : '隐藏')
                  .fontSize(11)
                  .backgroundColor('#f0f2f7')
                  .fontColor('#1d2a42')
                  .onClick(() => { void this.handleToggleHiddenFromMyPlaces(place); });
                Button('删除')
                  .fontSize(11)
                  .backgroundColor('#ffecec')
                  .fontColor(this.colorDanger)
                  .onClick(() => { this.handleDelete(place.id); });
              }
            }
            .padding(10)
            .backgroundColor(this.colorSurface)
            .borderRadius(12);
          }, (place: Place) => `my-${place.id}`);
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start);
      }
      .height('100%');
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor(this.colorBg);
  }

  @Builder
  private buildHotPlacesPage(): void {
    Column() {
      Row() {
        Button('返回').onClick(() => { this.currentPage = PageView.Map; });
        Text('热点地点')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 });
        Blank().layoutWeight(1);
        Button('刷新')
          .fontSize(11)
          .height(28)
          .backgroundColor('#f0f2f7')
          .fontColor('#1d2a42')
          .onClick(() => { void this.refreshPlaces(); });
      }.margin({ bottom: 12 });

      Text('人气 Top 5')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1d2a42')
        .margin({ bottom: 8 });

      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.getHotTop(5), (place: Place) => {
            Column() {
              if (place.imageUrl) {
                Image(place.imageUrl)
                  .width('100%')
                  .height(120)
                  .borderRadius(12);
              } else {
                Stack() {
                  Text(place.name)
                    .fontSize(14)
                    .fontColor('#ffffff')
                    .fontWeight(FontWeight.Bold);
                }
                .width('100%')
                .height(120)
                .backgroundColor('#6aa1ff')
                .borderRadius(12);
              }
              Row({ space: 8 }) {
                Text(place.name)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold);
                Blank().layoutWeight(1);
                Text(`👍 ${place.likes}`)
                  .fontSize(11)
                  .fontColor('#7c8699');
              }
            }
            .onClick(() => { this.openPlaceDetail(place); });
          }, (place: Place) => `hot5-${place.id}`);
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start);
      }
      .height(260)
      .margin({ bottom: 12 });

      Text('人气 Top 10')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1d2a42')
        .margin({ bottom: 8 });

      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.getHotTop(10), (place: Place) => {
            Column({ space: 6 }) {
              Row() {
                Text(place.name)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold);
                Blank().layoutWeight(1);
                Text(`👍 ${place.likes}`)
                  .fontSize(11)
                  .fontColor('#7c8699');
              }
              Row({ space: 8 }) {
                Button(this.voteButtonLabel(place.id, 1))
                  .fontSize(11)
                  .backgroundColor('#ffffff')
                  .fontColor('#1aa168')
                  .onClick(() => { void this.handleVote(place.id, 1); });
                Button(this.voteButtonLabel(place.id, -1))
                  .fontSize(11)
                  .backgroundColor('#ffffff')
                  .fontColor('#d23f3f')
                  .onClick(() => { void this.handleVote(place.id, -1); });
                Button('查看位置')
                  .fontSize(11)
                  .backgroundColor('#f1edff')
                  .fontColor(this.colorPrimary)
                  .onClick(() => { this.openPlaceOnMap(place, PageView.HotPlaces, 'hot'); });
              }
            }
            .padding(10)
            .backgroundColor(this.colorSurface)
            .borderRadius(12);
          }, (place: Place) => `hot10-${place.id}`);
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start);
      }
      .height('100%');
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor(this.colorBg);
  }

  @Builder
  private buildPlaceDetailPage(): void {
    Column() {
      Row() {
        Button('返回').onClick(() => { this.currentPage = PageView.HotPlaces; });
        Text('地点详情')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 });
      }.margin({ bottom: 12 });

      if (this.detailPlace) {
        if (this.detailPlace.imageUrl) {
          Image(this.detailPlace.imageUrl)
            .width('100%')
            .height(160)
            .borderRadius(12)
            .margin({ bottom: 8 });
        }
        Text(this.detailPlace.name)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 6 });
        Text(this.detailPlace.description || '暂无描述')
          .fontSize(12)
          .fontColor('#7c8699')
          .margin({ bottom: 10 });
        Row({ space: 10 }) {
          Button(this.voteButtonLabel(this.detailPlace.id, 1))
            .fontSize(12)
            .backgroundColor('#ffffff')
            .fontColor('#1aa168')
            .onClick(() => {
              const place = this.detailPlace;
              if (place) {
                void this.handleVote(place.id, 1);
              }
            });
          Button(this.voteButtonLabel(this.detailPlace.id, -1))
            .fontSize(12)
            .backgroundColor('#ffffff')
            .fontColor('#d23f3f')
            .onClick(() => {
              const place = this.detailPlace;
              if (place) {
                void this.handleVote(place.id, -1);
              }
            });
          Button(this.isPlaceFavorite(this.detailPlace.id) ? '取消收藏' : '收藏')
            .fontSize(12)
            .backgroundColor('#f0f2f7')
            .fontColor('#1d2a42')
            .onClick(() => {
              const place = this.detailPlace;
              if (place) {
                void this.handleToggleFavorite(place.id, !this.isPlaceFavorite(place.id));
              }
            });
          Button(this.isPlaceHidden(this.detailPlace.id) ? '显示' : '隐藏')
            .fontSize(12)
            .backgroundColor('#f0f2f7')
            .fontColor('#1d2a42')
            .onClick(() => {
              const place = this.detailPlace;
              if (place) {
                void this.handleToggleHidden(place.id, !this.isPlaceHidden(place.id));
              }
            });
          Button('查看位置')
            .fontSize(12)
            .backgroundColor('#f1edff')
            .fontColor(this.colorPrimary)
            .onClick(() => {
              const place = this.detailPlace;
              if (place) {
                this.openPlaceOnMap(place, PageView.PlaceDetail, 'detail');
              }
            });
        }
        .margin({ bottom: 12 });

        Text(`👍 ${this.detailPlace.likes}  ·  👎 ${this.detailPlace.dislikes}`)
          .fontSize(12)
          .fontColor('#7c8699');
      } else {
        Text('暂无详情')
          .fontSize(12)
          .fontColor('#7c8699');
      }
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor(this.colorBg);
  }

  @Builder
  private buildAdminPlacesPage(): void {
    Column() {
      Row() {
        Button('返回').onClick(() => { this.currentPage = PageView.Profile; });
        Text('所有地点')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 });
      }.margin({ bottom: 12 });

      Row({ space: 8 }) {
        Button('系统地点')
          .fontSize(11)
          .backgroundColor(this.adminPlacesTab === 'system' ? this.colorPrimary : '#f0f2f7')
          .fontColor(this.adminPlacesTab === 'system' ? '#ffffff' : '#1d2a42')
          .onClick(() => { this.adminPlacesTab = 'system'; });
        Button('用户提交')
          .fontSize(11)
          .backgroundColor(this.adminPlacesTab === 'user' ? this.colorPrimary : '#f0f2f7')
          .fontColor(this.adminPlacesTab === 'user' ? '#ffffff' : '#1d2a42')
          .onClick(() => { this.adminPlacesTab = 'user'; });
      }
      .margin({ bottom: 12 });

      Scroll() {
        Column({ space: 12 }) {
          if (this.adminPlacesTab === 'system') {
            Column({ space: 10 }) {
              Text('系统地点')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1d2a42');
              Row({ space: 8 }) {
                Button('刷新')
                  .fontSize(11)
                  .backgroundColor('#f1edff')
                  .fontColor(this.colorPrimary)
                  .onClick(() => { void this.refreshPlaces(); });
              }
              ForEach(this.getAdminSystemPlaces(), (place: Place) => {
                Column({ space: 6 }) {
                  Text(place.name).fontSize(12).fontWeight(FontWeight.Bold);
                  Text('系统地点').fontSize(11).fontColor('#7c8699');
                  Row({ space: 8 }) {
                    Button('查看位置')
                      .fontSize(11)
                      .backgroundColor('#f1edff')
                      .fontColor(this.colorPrimary)
                      .onClick(() => { this.openPlaceOnMap(place, PageView.AdminPlaces, 'admin'); });
                    Button('编辑')
                      .fontSize(11)
                      .onClick(() => { this.openEditPlace(place, true); });
                    Button('删除')
                      .fontSize(11)
                      .backgroundColor('#ffecec')
                      .fontColor(this.colorDanger)
                      .onClick(() => { this.handleDelete(place.id); });
                  }
                }
                .padding(10)
                .backgroundColor(this.colorSurface)
                .borderRadius(12);
              }, (place: Place) => `sys-${place.id}`);
            }
            .padding(12)
            .backgroundColor(this.colorSurface)
            .borderRadius(16)
            .shadow({ radius: 10, color: 'rgba(15, 25, 45, 0.06)', offsetX: 0, offsetY: 4 });

            Column({ space: 10 }) {
              Text('管理员草稿')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1d2a42');
              ForEach(this.getAdminDraftPlaces(), (place: Place) => {
                Column({ space: 6 }) {
                  Text(place.name).fontSize(12).fontWeight(FontWeight.Bold);
                  Text('草稿 · ' + this.renderPlaceStatus(place.status))
                    .fontSize(11)
                    .fontColor('#7c8699');
                  Row({ space: 8 }) {
                    Button('查看位置')
                      .fontSize(11)
                      .backgroundColor('#f1edff')
                      .fontColor(this.colorPrimary)
                      .onClick(() => { this.openPlaceOnMap(place, PageView.AdminPlaces, 'admin'); });
                    Button('编辑')
                      .fontSize(11)
                      .onClick(() => { this.openEditPlace(place, false); });
                    Button('应用')
                      .fontSize(11)
                      .backgroundColor('#f1edff')
                      .fontColor(this.colorPrimary)
                      .onClick(() => { this.handleAdminApply(place); });
                    Button('删除')
                      .fontSize(11)
                      .backgroundColor('#ffecec')
                      .fontColor(this.colorDanger)
                      .onClick(() => { this.handleDelete(place.id); });
                  }
                }
                .padding(10)
                .backgroundColor('#f7f8fc')
                .borderRadius(12);
              }, (place: Place) => `draft-${place.id}`);
            }
            .padding(12)
            .backgroundColor(this.colorSurface)
            .borderRadius(16)
            .shadow({ radius: 10, color: 'rgba(15, 25, 45, 0.06)', offsetX: 0, offsetY: 4 });
          }

          if (this.adminPlacesTab === 'user') {
            Column({ space: 10 }) {
              Text('用户推荐')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1d2a42');
              ForEach(this.getAdminUserPlaces(), (place: Place) => {
                Column({ space: 6 }) {
                  Text(place.name).fontSize(12).fontWeight(FontWeight.Bold);
                  Text('来自 ' + (place.ownerName || place.ownerId || '未知用户') + ' · ' + this.renderPlaceStatus(place.status))
                    .fontSize(11)
                    .fontColor('#7c8699');
                  Row({ space: 8 }) {
                    Button('查看位置')
                      .fontSize(11)
                      .backgroundColor('#f1edff')
                      .fontColor(this.colorPrimary)
                      .onClick(() => { this.openPlaceOnMap(place, PageView.AdminPlaces, 'admin'); });
                    Button('删除')
                      .fontSize(11)
                      .backgroundColor('#ffecec')
                      .fontColor(this.colorDanger)
                      .onClick(() => { this.handleDelete(place.id); });
                  }
                }
                .padding(10)
                .backgroundColor('#f7f8fc')
                .borderRadius(12);
              }, (place: Place) => `user-${place.id}`);
            }
            .padding(12)
            .backgroundColor(this.colorSurface)
            .borderRadius(16)
            .shadow({ radius: 10, color: 'rgba(15, 25, 45, 0.06)', offsetX: 0, offsetY: 4 });
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start);
      }
      .height('100%');
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor(this.colorBg);
  }

  @Builder
  private buildAdminReviewPage(): void {
    Column() {
      Row() {
        Button('返回').onClick(() => { this.currentPage = PageView.Profile; });
        Text('审核与反馈')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 });
      }.margin({ bottom: 12 });

      Row({ space: 8 }) {
        Button('待审核')
          .fontSize(11)
          .backgroundColor(this.adminReviewTab === 'review' ? this.colorPrimary : '#f0f2f7')
          .fontColor(this.adminReviewTab === 'review' ? '#ffffff' : '#1d2a42')
          .onClick(() => { this.adminReviewTab = 'review'; });
        Button('反馈')
          .fontSize(11)
          .backgroundColor(this.adminReviewTab === 'feedback' ? this.colorPrimary : '#f0f2f7')
          .fontColor(this.adminReviewTab === 'feedback' ? '#ffffff' : '#1d2a42')
          .onClick(() => {
            this.adminReviewTab = 'feedback';
            const session = this.getSession();
            if (session) {
              void this.loadMessagesForSession(session);
            }
          });
        Blank().layoutWeight(1);
        Button('刷新')
          .fontSize(11)
          .height(28)
          .backgroundColor('#f0f2f7')
          .fontColor('#1d2a42')
          .onClick(() => {
            const session = this.getSession();
            if (session) {
              void this.loadMessagesForSession(session);
            }
          });
      }
      .margin({ bottom: 12 });

      Scroll() {
        Column({ space: 10 }) {
          if (this.adminReviewTab === 'review') {
            if (this.pendingPlaces.length === 0) {
              Text('暂无待审核地点')
                .fontSize(12)
                .fontColor('#7c8699');
            }
            ForEach(this.pendingPlaces, (place: Place) => {
              Column({ space: 6 }) {
                Text(place.name)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold);
                Text((place.ownerName || place.ownerId || '用户') + ' · ' + this.renderPlaceStatus(place.status))
                  .fontSize(11)
                  .fontColor('#7c8699');
                Row({ space: 8 }) {
                  Button('查看位置')
                    .fontSize(11)
                    .backgroundColor('#f1edff')
                    .fontColor(this.colorPrimary)
                    .onClick(() => { this.openPlaceOnMap(place, PageView.AdminReview, 'review'); });
                  Button('通过')
                    .fontSize(11)
                    .backgroundColor('#e8f7f1')
                    .fontColor(this.colorAccent)
                    .onClick(() => { this.handleApprove(place.id); });
                  Button('拒绝')
                    .fontSize(11)
                    .backgroundColor('#ffecec')
                    .fontColor(this.colorDanger)
                    .onClick(() => { this.handleReject(place.id); });
                }
              }
              .padding(10)
              .backgroundColor(this.colorSurface)
              .borderRadius(12)
              .width('100%');
            }, (place: Place) => `review-${place.id}`);
          }

          if (this.adminReviewTab === 'feedback') {
            if (this.messages.length === 0) {
              Text('暂无反馈')
                .fontSize(12)
                .fontColor('#7c8699');
            }
            ForEach(this.messages, (msg: UserMessage) => {
              Column({ space: 6 }) {
                Row() {
                  Text(msg.title || '反馈')
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold);
                  Blank().layoutWeight(1);
                  Text(this.formatMessageTime(msg.createdAt))
                    .fontSize(10)
                    .fontColor('#9aa4b2');
                }
                Text(msg.content)
                  .fontSize(11)
                  .fontColor('#51607a');
                if (msg.place) {
                  Button('查看位置')
                    .fontSize(11)
                    .backgroundColor('#f1edff')
                    .fontColor(this.colorPrimary)
                    .onClick(() => {
                      const snap = msg.place;
                      if (!snap) {
                        return;
                      }
                      const snapSourceType: '' | 'system' = snap.sourceType === 'system' ? 'system' : '';
                      const p: Place = {
                        id: snap.sourcePlaceId ? snap.sourcePlaceId : `fb-${msg.id}`,
                        name: snap.name,
                        description: snap.description || '',
                        lat: snap.lat,
                        lon: snap.lon,
                        type: snap.type,
                        ownerId: '',
                        ownerName: '',
                        status: 'approved',
                        createdAt: msg.createdAt,
                        updatedAt: msg.createdAt,
                        likes: 0,
                        dislikes: 0,
                        imageUrl: snap.imageUrl || '',
                        sourceKey: snap.sourceKey || '',
                        sourceType: snapSourceType
                      };
                      this.openPlaceOnMap(p, PageView.AdminReview, 'feedback');
                    });
                }
              }
              .padding(10)
              .backgroundColor(this.colorSurface)
              .borderRadius(12)
              .width('100%');
            }, (msg: UserMessage) => `fb-${msg.id}`);
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start);
      }
      .height('100%');
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor(this.colorBg);
  }

  private openAddPlaceFromTap(): void {
    if (this.tapLocation) {
      this.selectedPoint = this.tapLocation;
    }
    this.placeName = '';
    this.placeDesc = '';
    this.placeImage = '';
    this.clearEditingState();
    const session = this.getSession();
    if (session && session.isAdmin) {
      this.editingSourceType = 'system';
    }
    this.pickMode = MapPickMode.None;
    this.tapActionVisible = false;
    this.currentPage = PageView.AddPlace;
  }

  private async handleUploadAllSystemLabels(): Promise<void> {
    promptAction.showToast({ message: '已停用：不再支持从地图节点批量生成系统地点，请改为管理员手动添加', duration: 2200 });
  }

  private async handleMarkWaterMine(): Promise<void> {
    const session = this.getSession();
    if (!session) {
      promptAction.showToast({ message: '请先登录再标记水雷', duration: 1500 });
      return;
    }
    if (!this.tapLocation && !this.selectedPoint) {
      return;
    }
    const point = this.tapLocation || this.selectedPoint;
    if (!point) {
      return;
    }
    const input: SaveDraftInput = {
      name: '水雷标记',
      description: '用户标记的水雷位置',
      type: 'water',
      imageUrl: this.placeImage || '',
      point,
      status: 'private'
    };
    await this.placeService.saveDraft(input, session);
    this.tapActionVisible = false;
    await this.refreshPlaces();
  }

  private async openHotPlaces(): Promise<void> {
    await this.refreshPlaces();
    this.updateHotPlaces();
    this.currentPage = PageView.HotPlaces;
  }

  private openPlaceDetail(place: Place): void {
    this.detailPlace = place;
    this.currentPage = PageView.PlaceDetail;
  }

  private openPlaceOnMap(place: Place, returnPage: PageView, context: string): void {
    if (context === 'review') {
      this.focusReviewPlaceId = place.id;
    } else {
      this.focusReviewPlaceId = '';
    }
    this.focusMapOnPlace(place, returnPage, context);
  }

  private async handleFocusApprove(): Promise<void> {
    if (!this.focusReviewPlaceId) {
      return;
    }
    await this.handleApprove(this.focusReviewPlaceId);
    this.exitFocusView();
  }

  private async handleFocusReject(): Promise<void> {
    if (!this.focusReviewPlaceId) {
      return;
    }
    await this.handleReject(this.focusReviewPlaceId);
    this.exitFocusView();
  }

  private async handleSubmitReview(place: Place): Promise<void> {
    if (!this.getSession()) {
      return;
    }
    await this.handleApply(place.id);
    await this.loadMyPlaces();
  }

  private async handleToggleHiddenFromMyPlaces(place: Place): Promise<void> {
    const session = this.getSession();
    if (!session) {
      return;
    }
    const hidden = this.isPlaceHidden(place.id);
    const ok = await this.placeService.toggleHidden(place.id, !hidden, session);
    if (!ok) {
      promptAction.showToast({ message: '操作失败，请检查网络或登录状态', duration: 1500 });
    }
    await this.refreshPlaces();
  }

  @Builder
  private buildAddPlacePage(): void {
    
    Column() {
      Row() {
        Button('返回').onClick(() => { this.currentPage = PageView.Map; });
        Text(this.editingPlaceId ? '编辑地点' : (this.editingSourceKey ? '提交修改' : '添加地点'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 });
      }.margin({ bottom: 12 });

      Text(this.getSelectedPointText())
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
        Button(this.editingPlaceId ? '保存修改' : '添加到我的地点').onClick(() => {
          this.handleSavePlace(false).then(() => { this.currentPage = PageView.Map; });
        });
      }.justifyContent(FlexAlign.SpaceBetween).width('100%');
      Button(this.isAdmin() ? '确认修改并应用' : (this.editingSourceKey ? '提交修改审核' : '提交审核'))
        .onClick(() => {
          this.handleSavePlace(true).then(() => { this.currentPage = PageView.Map; });
        })
        .backgroundColor(this.colorPrimary)
        .fontColor('#ffffff')
        .margin({ top: 8 });
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor(this.colorSurface);
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
      if (this.currentPage === PageView.Login) {
        this.buildLoginPage();
      }
      if (this.currentPage === PageView.Register) {
        this.buildRegisterPage();
      }
      if (this.currentPage === PageView.BindEmail) {
        this.buildBindEmailPage();
      }
      if (this.currentPage === PageView.ResetPassword) {
        this.buildResetPasswordPage();
      }
      if (this.currentPage === PageView.MyPlaces) {
        this.buildMyPlacesPage();
      }
      if (this.currentPage === PageView.HotPlaces) {
        this.buildHotPlacesPage();
      }
      if (this.currentPage === PageView.PlaceDetail) {
        this.buildPlaceDetailPage();
      }
      if (this.currentPage === PageView.AdminPlaces) {
        this.buildAdminPlacesPage();
      }
      if (this.currentPage === PageView.AdminReview) {
        this.buildAdminReviewPage();
      }
      if (this.currentPage === PageView.AddPlace) {
        this.buildAddPlacePage();
      }
    }
    .width('100%')
    .height('100%');
  }
}