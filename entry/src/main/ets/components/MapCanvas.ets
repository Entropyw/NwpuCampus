import { Bounds, LatLon, Marker, Place, PlaceFilter, RenderData, RouteState } from '../model/MapTypes';
import { clampZoom, project, unproject } from '../services/MapMath';
import { MapEventBus } from '../services/MapEventBus';

interface CanvasSize {
  width: number;
  height: number;
}

interface TouchPoint {
  x: number;
  y: number;
}

interface CanvasContextSizeInfo {
  width?: number;
  height?: number;
}

@Component
export struct MapCanvas {
  @Watch('handlePropChange')
  @Prop renderData: RenderData | null;
  @Watch('handlePropChange')
  @Prop route: RouteState | null;
  @Watch('handlePropChange')
  @Prop markers: Array<Marker>;
  @Watch('handlePropChange')
  @Prop places: Array<Place>;
  @Watch('handlePropChange')
  @Prop currentUser: string;
  @Prop filter: PlaceFilter;
  @Watch('handlePropChange')
  @Prop myLocation: LatLon | null;
  @Watch('handlePropChange')
  @Prop zoom: number;
  @Watch('handlePropChange')
  @Prop offsetX: number;
  @Watch('handlePropChange')
  @Prop offsetY: number;
  @Watch('handlePropChange')
  @Prop nightMode: boolean;
  // Do NOT accept function values as @Prop (ArkUI disallows function typed props).
  // Map events are emitted via MapEventBus; parent pages should register handlers there.

  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private ctx: CanvasRenderingContext2D | null = null;
  private canvasSize: CanvasSize = { width: 0, height: 0 };
  private lastPanPoint: TouchPoint | null = null;
  private lastPinchDistance: number = 0;
  private moved: boolean = false;
  private longPressTimerId: number | null = null;
  private longPressTriggered: boolean = false;
  private pendingPressPoint: TouchPoint | null = null;

  private draw(): void {
    if (!this.ctx || !this.renderData || this.canvasSize.width === 0 || this.canvasSize.height === 0) {
      return;
    }
    const ctx = this.ctx;
    const bounds = this.renderData.bounds;
    const width = this.canvasSize.width;
    const height = this.canvasSize.height;

  const isNight = this.nightMode;
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = isNight ? '#0f1726' : '#f7f5f2';
  ctx.fillRect(0, 0, width, height);

  this.drawAreas(ctx, bounds, isNight ? '#1b2538' : '#d9e4d9');
  this.drawWaters(ctx, bounds, isNight ? '#20344f' : '#b8d9f0');
  this.drawPitches(ctx, bounds, isNight ? '#1f2f2b' : '#c9e6d4');
  this.drawBuildings(ctx, bounds, isNight ? '#2b2f3a' : '#e8dcca');
  this.drawRoads(ctx, bounds, isNight ? '#5f6b7a' : '#aab3c4');
  this.drawRoute(ctx, bounds, isNight ? '#6aa1ff' : '#1866ff');
    this.drawPlaces(ctx, bounds);
    this.drawMarkers(ctx, bounds);
    this.drawMyLocation(ctx, bounds);
  }

  private drawPath(ctx: CanvasRenderingContext2D, bounds: Bounds, points: Array<LatLon>, closePath: boolean): void {
    if (points.length < 2) {
      return;
    }
  const width = this.canvasSize.width;
  const height = this.canvasSize.height;
    const zoom = clampZoom(this.zoom);

    const first = project(points[0].lat, points[0].lon, bounds, width, height, zoom, this.offsetX, this.offsetY);
    ctx.beginPath();
    ctx.moveTo(first.x, first.y);
    for (let i = 1; i < points.length; i++) {
      const p = project(points[i].lat, points[i].lon, bounds, width, height, zoom, this.offsetX, this.offsetY);
      ctx.lineTo(p.x, p.y);
    }
    if (closePath) {
      ctx.closePath();
    }
  }

  private drawAreas(ctx: CanvasRenderingContext2D, bounds: Bounds, fill: string): void {
    ctx.fillStyle = fill;
    for (const area of this.renderData ? this.renderData.areas : []) {
      this.drawPath(ctx, bounds, area.points, true);
      ctx.fill();
    }
  }

  private drawWaters(ctx: CanvasRenderingContext2D, bounds: Bounds, fill: string): void {
    ctx.fillStyle = fill;
    for (const water of this.renderData ? this.renderData.waters : []) {
      this.drawPath(ctx, bounds, water.points, true);
      ctx.fill();
    }
  }

  private drawPitches(ctx: CanvasRenderingContext2D, bounds: Bounds, fill: string): void {
    ctx.fillStyle = fill;
    for (const pitch of this.renderData ? this.renderData.pitches : []) {
      this.drawPath(ctx, bounds, pitch.points, true);
      ctx.fill();
    }
  }

  private drawBuildings(ctx: CanvasRenderingContext2D, bounds: Bounds, fill: string): void {
    ctx.fillStyle = fill;
    for (const building of this.renderData ? this.renderData.buildings : []) {
      this.drawPath(ctx, bounds, building.points, true);
      ctx.fill();
    }
  }

  private drawRoads(ctx: CanvasRenderingContext2D, bounds: Bounds, stroke: string): void {
    ctx.strokeStyle = stroke;
    ctx.lineWidth = 1.2;
    for (const road of this.renderData ? this.renderData.roads : []) {
      this.drawPath(ctx, bounds, road.points, false);
      ctx.stroke();
    }
  }

  private drawRoute(ctx: CanvasRenderingContext2D, bounds: Bounds, stroke: string): void {
    if (!this.route || this.route.path.length < 2) {
      return;
    }
    ctx.strokeStyle = stroke;
    ctx.lineWidth = this.scaleStroke(3);
    this.drawPath(ctx, bounds, this.route.path, false);
    ctx.stroke();
  }

  private drawPlaces(ctx: CanvasRenderingContext2D, bounds: Bounds): void {
    for (const place of this.places) {
      if (place.type === 'water') {
        this.drawWaterMine(ctx, bounds, place.lat, place.lon, this.placeColor(place), place.name);
      } else {
        this.drawMarker(ctx, bounds, place.lat, place.lon, this.placeColor(place), place.name);
      }
    }
  }

  private drawWaterMine(ctx: CanvasRenderingContext2D, bounds: Bounds, lat: number, lon: number, color: string, label: string): void {
    const width = this.canvasSize.width;
    const height = this.canvasSize.height;
    const zoom = clampZoom(this.zoom);
    const point = project(lat, lon, bounds, width, height, zoom, this.offsetX, this.offsetY);
    const size = this.scaleMarker(9);
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(point.x, point.y, size, 0, Math.PI * 2);
    ctx.fill();
    const spike = size * 0.6;
    ctx.beginPath();
    ctx.moveTo(point.x, point.y - size - spike);
    ctx.lineTo(point.x - spike * 0.35, point.y - size * 0.2);
    ctx.lineTo(point.x + spike * 0.35, point.y - size * 0.2);
    ctx.closePath();
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(point.x, point.y + size + spike);
    ctx.lineTo(point.x - spike * 0.35, point.y + size * 0.2);
    ctx.lineTo(point.x + spike * 0.35, point.y + size * 0.2);
    ctx.closePath();
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(point.x - size - spike, point.y);
    ctx.lineTo(point.x - size * 0.2, point.y - spike * 0.35);
    ctx.lineTo(point.x - size * 0.2, point.y + spike * 0.35);
    ctx.closePath();
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(point.x + size + spike, point.y);
    ctx.lineTo(point.x + size * 0.2, point.y - spike * 0.35);
    ctx.lineTo(point.x + size * 0.2, point.y + spike * 0.35);
    ctx.closePath();
    ctx.fill();
    if (label) {
      ctx.fillStyle = this.nightMode ? '#e7edf7' : '#1d2a42';
      ctx.font = `${this.scaleFont(14)}px sans-serif`;
      ctx.fillText(label, point.x + size + 2, point.y - size * 0.6);
    }
  }

  private drawMarkers(ctx: CanvasRenderingContext2D, bounds: Bounds): void {
    for (const marker of this.markers) {
      if (marker.kind === 'focus') {
        this.drawFocusMarker(ctx, bounds, marker.lat, marker.lon, marker.label || '');
      } else {
        this.drawMarker(ctx, bounds, marker.lat, marker.lon, '#4f79ff', marker.label || '');
      }
    }
  }

  private drawMyLocation(ctx: CanvasRenderingContext2D, bounds: Bounds): void {
    if (!this.myLocation) {
      return;
    }
    this.drawMarker(ctx, bounds, this.myLocation.lat, this.myLocation.lon, '#0fbc7a', '我');
  }

  private drawMarker(ctx: CanvasRenderingContext2D, bounds: Bounds, lat: number, lon: number, color: string, label: string): void {
  const width = this.canvasSize.width;
  const height = this.canvasSize.height;
    const zoom = clampZoom(this.zoom);
    const point = project(lat, lon, bounds, width, height, zoom, this.offsetX, this.offsetY);
  const radius = this.scaleMarker(5);
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(point.x, point.y, radius, 0, Math.PI * 2);
    ctx.fill();
    if (label) {
      ctx.fillStyle = this.nightMode ? '#e7edf7' : '#1d2a42';
  ctx.font = `${this.scaleFont(15)}px sans-serif`;
      ctx.fillText(label, point.x + radius + 2, point.y - radius - 1);
    }
  }

  private drawFocusMarker(ctx: CanvasRenderingContext2D, bounds: Bounds, lat: number, lon: number, label: string): void {
    const width = this.canvasSize.width;
    const height = this.canvasSize.height;
    const zoom = clampZoom(this.zoom);
    const point = project(lat, lon, bounds, width, height, zoom, this.offsetX, this.offsetY);
    const size = this.scaleMarker(10);
    ctx.fillStyle = '#ffb703';
    ctx.beginPath();
    ctx.moveTo(point.x, point.y - size);
    ctx.lineTo(point.x - size * 0.6, point.y + size * 0.6);
    ctx.lineTo(point.x + size * 0.6, point.y + size * 0.6);
    ctx.closePath();
    ctx.fill();
    if (label) {
      ctx.fillStyle = this.nightMode ? '#f8fafc' : '#1d2a42';
      ctx.font = `${this.scaleFont(15)}px sans-serif`;
      ctx.fillText(label, point.x + size + 4, point.y - size * 0.6);
    }
  }

  private scaleMarker(base: number): number {
    const zoom = clampZoom(this.zoom);
    const size = base * Math.pow(zoom, 0.7);
    if (size < 3) {
      return 3;
    }
    if (size > 18) {
      return 18;
    }
    return size;
  }

  private scaleStroke(base: number): number {
    const zoom = clampZoom(this.zoom);
    const size = base * Math.pow(zoom, 0.2);
    if (size < 1) {
      return 1;
    }
    if (size > 6) {
      return 6;
    }
    return size;
  }

  private scaleFont(base: number): number {
    const zoom = clampZoom(this.zoom);
    const size = base * Math.pow(zoom, 0.75);
    if (size < 12) {
      return 12;
    }
    if (size > 32) {
      return 32;
    }
    return size;
  }

  private placeColor(place: Place): string {
    const isMine = place.ownerId && this.currentUser && place.ownerId === this.currentUser;
    switch (place.type) {
      case 'water':
        return isMine ? '#24a3ff' : '#4cb3ff';
      case 'slippery':
        return isMine ? '#b995ff' : '#9c7cff';
      case 'danger':
        return isMine ? '#ff8b81' : '#ff6f61';
      default:
        return isMine ? '#22c55e' : '#2f7df6';
    }
  }

  private handleReady(): void {
    this.ctx = this.canvasContext;
    // try to capture canvas intrinsic size if available (avoid onSizeChange API to preserve older SDK compatibility)
    try {
      // CanvasRenderingContext2D may expose width/height on some SDKs
      const info = this.canvasContext as CanvasContextSizeInfo;
      const w = info.width;
      const h = info.height;
      if (typeof w === 'number' && typeof h === 'number') {
        this.canvasSize = { width: w, height: h };
        MapEventBus.emitSize(w, h);
      }
    } catch (e) {
      // ignore
    }
    this.draw();
  }

  private handlePropChange(): void {
    this.draw();
  }

  private handleSizeChange(width: number, height: number): void {
    this.canvasSize = { width, height };
    this.draw();
  }

  private handleTouch(event: TouchEvent): void {
    if (!this.renderData) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.moved = false;
      this.longPressTriggered = false;
      if (event.touches.length === 1) {
        const point = event.touches[0];
        this.lastPanPoint = { x: point.x, y: point.y };
        this.pendingPressPoint = { x: point.x, y: point.y };
        this.startLongPressTimer();
      } else if (event.touches.length === 2) {
        this.lastPinchDistance = this.distance(event.touches[0], event.touches[1]);
        this.clearLongPressTimer();
      }
    }

    if (event.type === TouchType.Move) {
      if (event.touches.length === 1 && this.lastPanPoint) {
        const point = event.touches[0];
        const dx = point.x - this.lastPanPoint.x;
        const dy = point.y - this.lastPanPoint.y;
        if (Math.abs(dx) > 2 || Math.abs(dy) > 2) {
          this.moved = true;
          this.clearLongPressTimer();
        }
        this.lastPanPoint = { x: point.x, y: point.y };
        // emit transform events to any registered handlers
        MapEventBus.emitTransform(this.zoom, this.offsetX + dx, this.offsetY + dy);
      } else if (event.touches.length === 2) {
        const dist = this.distance(event.touches[0], event.touches[1]);
        if (this.lastPinchDistance > 0) {
          const scale = dist / this.lastPinchDistance;
          const nextZoom = clampZoom(this.zoom * scale);
          this.lastPinchDistance = dist;
          this.moved = true;
          this.clearLongPressTimer();
          // emit transform events
          MapEventBus.emitTransform(nextZoom, this.offsetX, this.offsetY);
        }
      }
    }

    if (event.type === TouchType.Up) {
      this.clearLongPressTimer();
      if (this.longPressTriggered) {
        this.longPressTriggered = false;
        this.pendingPressPoint = null;
        this.lastPanPoint = null;
        this.lastPinchDistance = 0;
        return;
      }
      if (!this.moved && event.touches.length > 0) {
        const point = event.touches[0];
        const location = unproject(point.x, point.y, this.renderData.bounds, this.canvasSize.width, this.canvasSize.height, clampZoom(this.zoom), this.offsetX, this.offsetY);
        // emit tap event
        MapEventBus.emitTap(location);
      }
      this.lastPanPoint = null;
      this.lastPinchDistance = 0;
      this.pendingPressPoint = null;
    }
  }

  private startLongPressTimer(): void {
    this.clearLongPressTimer();
    this.longPressTimerId = Number(setTimeout(() => {
      if (!this.pendingPressPoint || !this.renderData) {
        return;
      }
      const point = this.pendingPressPoint;
      const location = unproject(point.x, point.y, this.renderData.bounds, this.canvasSize.width, this.canvasSize.height, clampZoom(this.zoom), this.offsetX, this.offsetY);
      this.longPressTriggered = true;
      MapEventBus.emitLongPress(location);
    }, 450));
  }

  private clearLongPressTimer(): void {
    if (this.longPressTimerId != null) {
      try {
        clearTimeout(this.longPressTimerId as number);
      } catch (e) {
        // ignore
      }
      this.longPressTimerId = null;
    }
  }

  private distance(a: TouchObject, b: TouchObject): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return Math.sqrt(dx * dx + dy * dy);
  }

  build() {
    Canvas(this.canvasContext)
      .onReady(() => {
        this.handleReady();
      })
      .onTouch((event: TouchEvent) => {
        this.handleTouch(event);
        this.draw();
      });
  }
}
