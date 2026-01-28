import common from '@ohos.app.ability.common';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import geoLocationManager from '@ohos.geoLocationManager';
import promptAction from '@ohos.promptAction';
import { MapCanvas } from '../components/MapCanvas';
import { LongPressHandler, MapEventBus, SizeHandler, TapHandler, TransformHandler } from '../services/MapEventBus';
import { AuthService } from '../services/AuthService';
import { MessagePlaceSnapshot, MessageService, UserMessage } from '../services/MessageService';
import { OsmParser } from '../services/OsmParser';
import { PlaceService, SaveDraftInput } from '../services/PlaceService';
import { RoutePlanner } from '../services/RoutePlanner';
import { clampZoom } from '../services/MapMath';
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

interface CenterOffset {
  offsetX: number;
  offsetY: number;
}

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

  private apiBase: string = 'http://121.36.80.168:8081';
  private osmParser: OsmParser = new OsmParser();
  private placeService: PlaceService = new PlaceService();
  private authService: AuthService = new AuthService();
  private messageService: MessageService = new MessageService();
  private routePlanner: RoutePlanner = new RoutePlanner();
  private renderData: RenderData = this.createEmptyRenderData();
  private labels: Array<MapLabel> = [];
  private startIndex: number = 0;
  private endIndex: number = 1;
  private useMockLocation: boolean = false;
  private locationUpdateIntervalId: number | null = null;
  private locationUpdateIntervalMs: number = 8000;

  private poiFallback: Array<MapLabel> = this.buildFallbackLabels();
  private savedFilter: PlaceFilter | null = null;
  private lastLocation: LatLon | null = null;
  private lastHazardAlertAt: number = 0;
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
  // business API moved to 8081
  this.apiBase = 'http://121.36.80.168:8081';
    this.placeService.enableRemote(this.apiBase);
    this.authService.enableRemote(this.apiBase);
    this.messageService.enableRemote(this.apiBase);
  // email service remains at 8080
  this.authService.enableEmailRemote('http://121.36.80.168:8080');
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
    return {
      bounds: { minLat: 34.029, maxLat: 34.034, minLon: 108.758, maxLon: 108.766 },
      roads: [],
      buildings: [],
      waters: [],
      areas: [],
      pitches: [],
      labels: []
    };
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
    if (this.dynamicNavActive && this.routeEnd) {
      this.routeStart = loc;
      this.routeStartLabel = '我的位置';
      this.planRoute();
    }
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
      const highPriority: geoLocationManager.LocationRequestPriority = 0 as geoLocationManager.LocationRequestPriority;
      const request: geoLocationManager.CurrentLocationRequest = {
        priority: highPriority,
        scenario: geoLocationManager.LocationRequestScenario.NAVIGATION,
        timeoutMs: 10000,
        maxAccuracy: 0
      };
      const location = await geoLocationManager.getCurrentLocation(request);
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

  private focusMapOnPlace(place: Place, returnPage: PageView, context: string): void {
    this.focusPlace = place;
    this.focusReturnPage = returnPage;
    this.focusContext = context;
    this.focusNavVisible = true;
    this.dynamicNavActive = false;
    const nextZoom = clampZoom(1.8);
    const offsets = this.computeCenterOffsets(place.lat, place.lon, nextZoom);
    this.zoom = nextZoom;
    this.offsetX = offsets.offsetX;
    this.offsetY = offsets.offsetY;
    this.currentPage = PageView.Map;
  }

  private exitFocusView(): void {
    if (this.focusReturnPage != null) {
      this.currentPage = this.focusReturnPage;
    }
    this.focusPlace = null;
    this.focusReturnPage = null;
    this.focusContext = '';
    this.focusReviewPlaceId = '';
    this.focusNavVisible = false;
    this.dynamicNavActive = false;
  }

  private toggleFocusNavOptions(): void {
    this.focusNavVisible = !this.focusNavVisible;
  }

  private navigateToFocusPlace(): void {
    if (!this.focusPlace) {
      return;
    }
    const dest: LatLon = { lat: this.focusPlace.lat, lon: this.focusPlace.lon };
    const start: LatLon | null = this.myLocation ? { lat: this.myLocation.lat, lon: this.myLocation.lon } : this.routeStart;
    if (start) {
      this.routeStart = start;
      this.routeEnd = dest;
      this.routeStartLabel = '我的位置';
      this.routeEndLabel = this.focusPlace.name;
      this.planRoute();
    } else {
      this.routeEnd = dest;
      this.routeEndLabel = this.focusPlace.name;
      this.invalidateRoute();
    }
    this.dynamicNavActive = true;
    this.focusNavVisible = false;
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
    this.updateHotPlaces();
  }

  private async loadMyPlaces(): Promise<void> {
    const session = this.authService.getSession();
    if (!session) {
      this.myPlaces = [];
      return;
    }
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
    if (!this.registerEmail || !this.registerCode) {
      this.authError = '请填写邮箱和验证码';
      return;
    }
    const verified = await this.authService.verifyEmailCode(this.username, this.registerCode);
    if (!verified) {
      this.authError = this.authService.getLastError() || '邮箱验证失败';
      return;
    }
    const session = await this.authService.register(this.username, this.password, this.registerEmail);
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
    const ok = await this.authService.sendEmailCode(this.username, this.registerEmail);
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
    const ok = await this.authService.sendEmailCode(this.username, this.resetEmail);
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
    const ok = await this.authService.sendEmailCode(session.username, this.bindEmail);
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
    const verified = await this.authService.verifyEmailCode(this.username, this.resetCode);
    if (!verified) {
      this.authError = this.authService.getLastError() || '验证码验证失败';
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
    const verified = await this.authService.verifyEmailCode(session.username, this.bindCode);
    if (!verified) {
      promptAction.showToast({ message: this.authService.getLastError() || '验证失败', duration: 1500 });
      return;
    }
    this.authService.setSessionEmail(this.bindEmail, false);
    this.bindingRequired = false;
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
    void this.loadMessagesForSession(session);
    void this.loadMyPlaces();
    this.refreshPlaces();
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
      if (!module || !module.getPhotoAccessHelper) {
        return '';
      }
      const helper = module.getPhotoAccessHelper(context);
      if (!helper || !helper.select) {
        return '';
      }
      const options: PhotoSelectOptions = { maxSelectNumber: 1 };
      const result = await helper.select(options);
      const uris: Array<string> = result && result.photoUris ? result.photoUris : [];
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
    const target = this.findPlaceById(placeId);
    const ownerName = target ? this.getPlaceOwnerName(target) : '';
    const snapshot = target ? this.buildMessageSnapshot(target) : null;
    const ok = await this.placeService.delete(placeId, session);
    if (!ok) {
      promptAction.showToast({ message: '删除失败，请检查权限或网络', duration: 1500 });
      return;
    }
    await this.refreshPlaces();
    if (session && session.isAdmin && ownerName && ownerName !== session.username && snapshot) {
      await this.pushMessage(ownerName, {
        id: `${ownerName}-${Date.now()}-delete`,
        username: ownerName,
        title: '推荐地点已被管理员删除',
        content: `你推荐的地点「${snapshot.name}」已被管理员删除，可重新提交审核。`,
        createdAt: Date.now(),
        unread: true,
        action: 'resubmit',
        place: snapshot
      });
    }
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
    const session = this.authService.getSession();
    if (this.placeService.hasVoted(placeId, session)) {
      promptAction.showToast({ message: '每个账号只能点赞/踩一次', duration: 1200 });
      return;
    }
    await this.placeService.vote(placeId, delta, session);
    await this.refreshPlaces();
    if (this.tapPlace && this.tapPlace.id === placeId) {
      const refreshed = this.findPlaceById(placeId);
      if (refreshed) {
        this.tapPlace = refreshed;
      }
    }
    if (this.detailPlace && this.detailPlace.id === placeId) {
      const refreshed = this.findPlaceById(placeId);
      if (refreshed) {
        this.detailPlace = refreshed;
      }
    }
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
    const session = this.authService.getSession();
    const target = this.findPlaceById(placeId);
    const ownerName = target ? this.getPlaceOwnerName(target) : '';
    await this.placeService.approve(placeId, session);
    await this.refreshPlaces();
    if (session && session.isAdmin && ownerName && ownerName !== session.username) {
      await this.pushMessage(ownerName, {
        id: `${ownerName}-${Date.now()}-approve`,
        username: ownerName,
        title: '推荐地点审核通过',
        content: `恭喜！你推荐的地点「${target ? target.name : ''}」已通过审核。`,
        createdAt: Date.now(),
        unread: true
      });
    }
  }

  private async handleReject(placeId: string): Promise<void> {
    const session = this.authService.getSession();
    const target = this.findPlaceById(placeId);
    const ownerName = target ? this.getPlaceOwnerName(target) : '';
    const snapshot = target ? this.buildMessageSnapshot(target) : null;
    await this.placeService.reject(placeId, session);
    await this.refreshPlaces();
    if (session && session.isAdmin && ownerName && ownerName !== session.username && snapshot) {
      await this.pushMessage(ownerName, {
        id: `${ownerName}-${Date.now()}-reject`,
        username: ownerName,
        title: '推荐地点未通过审核',
        content: `很遗憾，你推荐的地点「${snapshot.name}」未通过审核，可修改后重新提交。`,
        createdAt: Date.now(),
        unread: true,
        action: 'resubmit',
        place: snapshot
      });
    }
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

  private async loadMessagesForSession(session: UserSession | null): Promise<void> {
    if (!session || session.isAdmin) {
      this.messages = [];
      this.unreadCount = 0;
      this.showMessages = false;
      return;
    }
    const list = await this.messageService.list(session);
    const normalized: Array<UserMessage> = [];
    const readAt = this.lastMessageReadAt;
    list.forEach((msg) => {
      const raw = msg as RawUserMessage;
      const createdAt = typeof msg.createdAt === 'number'
        ? msg.createdAt
        : (typeof raw.date === 'number' ? raw.date : Date.now());
      const baseUnread = msg.unread === undefined ? true : msg.unread;
      const unread = baseUnread && createdAt > readAt;
      const title = msg.title || '消息提醒';
      const content = msg.content || raw.message || '';
      const username = msg.username || raw.userId || '';
      normalized.push({
        id: msg.id,
        username,
        title,
        content,
        createdAt,
        unread,
        action: msg.action,
        place: msg.place
      });
    });
    const limited: Array<UserMessage> = [];
    const max = this.messagePageSize;
    for (let i = 0; i < normalized.length && i < max; i += 1) {
      limited.push(normalized[i]);
    }
    this.messages = limited;
    this.unreadCount = normalized.filter((msg) => msg.unread).length;
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
    return this.getAdminAllPlaces().filter((place) => !place.ownerId);
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
      case 'pending':
        return list.filter((p) => p.status === 'pending');
      case 'approved':
        return list.filter((p) => p.status === 'approved' || p.status === 'published');
      default:
        return list;
    }
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
    if (this.route) {
      const startMarker: Marker = { lat: this.route.start.lat, lon: this.route.start.lon, label: '起点' };
      const endMarker: Marker = { lat: this.route.end.lat, lon: this.route.end.lon, label: '终点' };
      markers.push(startMarker);
      markers.push(endMarker);
    }
    if (this.routeStart) {
      markers.push({ lat: this.routeStart.lat, lon: this.routeStart.lon, label: '起点' });
    }
    if (this.routeEnd) {
      markers.push({ lat: this.routeEnd.lat, lon: this.routeEnd.lon, label: '终点' });
    }
    if (this.focusPlace) {
      markers.push({ lat: this.focusPlace.lat, lon: this.focusPlace.lon, label: '查看位置', kind: 'focus' });
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
  .backgroundColor(this.authService.getSession() ? this.colorPrimary : '#8a93a5')
    .borderRadius(20)
    .shadow({ radius: 10, color: 'rgba(30, 60, 120, 0.2)', offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.currentPage = this.getSession() ? PageView.Profile : PageView.Login;
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
        Stack() {
          Text('校园地图')
            .fontSize(16)
            .fontColor('#ffffff')
            .fontWeight(FontWeight.Bold);
        }
        .width(72)
        .height(72)
        .borderRadius(36)
        .backgroundColor(this.colorPrimary)
        .alignSelf(ItemAlign.Center)
        .margin({ bottom: 6 })
        .shadow({ radius: 12, color: 'rgba(108, 92, 231, 0.35)', offsetX: 0, offsetY: 6 });

        Text('登录后可保存自定义地点、参与投票与反馈')
          .fontSize(12)
          .fontColor('#7c8699')
          .textAlign(TextAlign.Center);

        Text('注册需要邮箱验证码，登录仅需账号密码')
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

        TextInput({ text: this.registerEmail, placeholder: '邮箱（用于接收验证码）' })
          .backgroundColor('#f5f6fa')
          .borderRadius(10)
          .padding({ left: 10, right: 10 })
          .onChange((value: string) => { this.registerEmail = value; });

        Row({ space: 8 }) {
          TextInput({ text: this.registerCode, placeholder: '邮箱验证码' })
            .backgroundColor('#f5f6fa')
            .borderRadius(10)
            .padding({ left: 10, right: 10 })
            .layoutWeight(1)
            .onChange((value: string) => { this.registerCode = value; });
          Button('发送验证码')
            .height(32)
            .fontSize(12)
            .backgroundColor(this.colorPrimary)
            .fontColor('#ffffff')
            .onClick(() => { this.sendRegisterCode(); });
        }

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
                  Button('热点')
                    .fontSize(12)
                    .width(64)
                    .height(32)
                    .backgroundColor(this.colorPrimary)
                    .fontColor('#ffffff')
                    .onClick(() => this.openHotPlaces());
                  Button(this.nightMode ? '日间' : '夜间')
                    .onClick(() => this.toggleNightMode())
                    .fontSize(12)
                    .width(64)
                    .height(32)
                    .backgroundColor(this.colorPrimary)
                    .fontColor('#ffffff');
                  Button('规划路线')
                    .fontSize(12)
                    .width(64)
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
                    Row() {
                      if (this.tapPlace.ownerId) {
                        Button('👍')
                          .backgroundColor(this.colorPrimary)
                          .fontColor('#ffffff')
                          .onClick(() => { this.handleVote(this.tapPlace!.id, 1); });
                        Button('👎')
                          .backgroundColor(this.colorPrimaryLight)
                          .fontColor(this.colorPrimary)
                          .onClick(() => { this.handleVote(this.tapPlace!.id, -1); });
                      }
                      if (this.isMinePlace(this.tapPlace)) {
                        Button('编辑')
                          .backgroundColor(this.colorPrimaryLight)
                          .fontColor(this.colorPrimary)
                          .onClick(() => { this.openEditPlace(this.tapPlace!, false); });
                        if (this.tapPlace.status === 'draft' || this.tapPlace.status === 'private' || this.tapPlace.status === 'rejected') {
                          Button(this.isAdmin() ? '确认修改并应用' : '提交审核')
                            .backgroundColor(this.colorPrimary)
                            .fontColor('#ffffff')
                            .onClick(() => { this.handleApply(this.tapPlace!.id); });
                        }
                        Button('删除')
                          .backgroundColor(this.colorPrimary)
                          .fontColor('#ffffff')
                          .onClick(() => { this.handleDelete(this.tapPlace!.id); });
                      } else {
                        Button('申请修改')
                          .backgroundColor(this.colorPrimaryLight)
                          .fontColor(this.colorPrimary)
                          .onClick(() => { this.openEditPlace(this.tapPlace!, true); });
                        Button('反馈')
                          .backgroundColor(this.colorPrimaryLight)
                          .fontColor(this.colorPrimary)
                          .onClick(() => { this.handleFeedback(this.tapPlace!.id); });
                      }
                      Button(this.isPlaceHidden(this.tapPlace.id) ? '显示' : '隐藏')
                        .backgroundColor(this.colorPrimaryLight)
                        .fontColor(this.colorPrimary)
                        .onClick(() => { this.handleToggleHidden(this.tapPlace!.id, !this.isPlaceHidden(this.tapPlace!.id)); });
                      if (this.isAdmin() && this.tapPlace.status === 'pending') {
                        Button('通过')
                          .backgroundColor(this.colorPrimary)
                          .fontColor('#ffffff')
                          .onClick(() => { this.handleApprove(this.tapPlace!.id); });
                        Button('拒绝')
                          .backgroundColor(this.colorPrimaryLight)
                          .fontColor(this.colorPrimary)
                          .onClick(() => { this.handleReject(this.tapPlace!.id); });
                      }
                    }
                    .justifyContent(FlexAlign.SpaceBetween)
                    .width('100%');
                  } else {
                    Text('该位置暂无自定义地点').fontSize(12).fontColor('#7c8699');
                    Button('添加自定义位置')
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
                    .onClick(() => this.toggleHazardMode())
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
            Text(this.getSession() ? (this.getSession()!.username) : '游客模式')
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
            .layoutWeight(1)
            .onClick(() => { this.currentPage = PageView.AdminPlaces; });
          Button('我的审核')
            .fontSize(12)
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
      TextInput({ text: this.profileOldPassword, placeholder: '旧密码' })
        .type(InputType.Password)
        .onChange((value: string) => { this.profileOldPassword = value; });
      TextInput({ text: this.profileNewPassword, placeholder: '新密码' })
        .type(InputType.Password)
        .onChange((value: string) => { this.profileNewPassword = value; });
      Button('保存资料')
        .onClick(() => { console.info('Profile saved locally'); })
        .margin({ bottom: 16 });

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
                if (place.status === 'private' || place.status === 'draft') {
                  Button('提交审核')
                    .fontSize(11)
                    .backgroundColor('#e8f7f1')
                    .fontColor(this.colorAccent)
                    .onClick(() => { void this.handleSubmitReview(place); });
                }
                if (place.status === 'approved' || place.status === 'published') {
                  Button(this.isPlaceHidden(place.id) ? '显示' : '隐藏')
                    .fontSize(11)
                    .backgroundColor('#f0f2f7')
                    .fontColor('#1d2a42')
                    .onClick(() => { void this.handleToggleHiddenFromMyPlaces(place); });
                }
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
          .onClick(() => { this.refreshPlaces(); });
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
                Button('👍')
                  .fontSize(11)
                  .backgroundColor('#ffffff')
                  .fontColor('#1aa168')
                  .onClick(() => { this.handleVote(place.id, 1); });
                Button('👎')
                  .fontSize(11)
                  .backgroundColor('#ffffff')
                  .fontColor('#d23f3f')
                  .onClick(() => { this.handleVote(place.id, -1); });
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
        if (this.detailPlace!.imageUrl) {
          Image(this.detailPlace!.imageUrl)
            .width('100%')
            .height(160)
            .borderRadius(12)
            .margin({ bottom: 8 });
        }
        Text(this.detailPlace!.name)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 6 });
        Text(this.detailPlace!.description || '暂无描述')
          .fontSize(12)
          .fontColor('#7c8699')
          .margin({ bottom: 10 });
        Row({ space: 10 }) {
          Button('👍')
            .fontSize(12)
            .backgroundColor('#ffffff')
            .fontColor('#1aa168')
            .onClick(() => { this.handleVote(this.detailPlace!.id, 1); });
          Button('👎')
            .fontSize(12)
            .backgroundColor('#ffffff')
            .fontColor('#d23f3f')
            .onClick(() => { this.handleVote(this.detailPlace!.id, -1); });
          Button('查看位置')
            .fontSize(12)
            .backgroundColor('#f1edff')
            .fontColor(this.colorPrimary)
            .onClick(() => { this.openPlaceOnMap(this.detailPlace!, PageView.PlaceDetail, 'detail'); });
        }
        .margin({ bottom: 12 });

        Text(`👍 ${this.detailPlace!.likes}  ·  👎 ${this.detailPlace!.dislikes}`)
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
        Text('我的审核')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 });
      }.margin({ bottom: 12 });

      Scroll() {
        Column({ space: 10 }) {
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
            .borderRadius(12);
          }, (place: Place) => `review-${place.id}`);
        }
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
    this.pickMode = MapPickMode.None;
    this.tapActionVisible = false;
    this.currentPage = PageView.AddPlace;
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

  private openHotPlaces(): void {
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
    await this.placeService.toggleHidden(place.id, !hidden, session);
    await this.refreshPlaces();
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