import { LatLon } from '../model/MapTypes';

export class TapHandler {
  onTap(_point: LatLon): void {
    // override in subclass
  }
}

export class TransformHandler {
  onTransform(_zoom: number, _offsetX: number, _offsetY: number): void {
    // override in subclass
  }
}

export class LongPressHandler {
  onLongPress(_point: LatLon): void {
    // override in subclass
  }
}

export class MapEventBus {
  private static tapHandlers: Array<TapHandler> = [];
  private static transformHandlers: Array<TransformHandler> = [];
  private static longPressHandlers: Array<LongPressHandler> = [];

  static registerTapHandler(handler: TapHandler): void {
    if (!handler) {
      return;
    }
    MapEventBus.tapHandlers.push(handler);
  }

  static unregisterTapHandler(handler: TapHandler): void {
    const idx = MapEventBus.tapHandlers.indexOf(handler);
    if (idx >= 0) {
      MapEventBus.tapHandlers.splice(idx, 1);
    }
  }

  static emitTap(point: LatLon): void {
    for (const h of MapEventBus.tapHandlers) {
      try {
        h.onTap(point);
      } catch (e) {
        console.error('MapEventBus.tap handler error', e);
      }
    }
  }

  static registerLongPressHandler(handler: LongPressHandler): void {
    if (!handler) {
      return;
    }
    MapEventBus.longPressHandlers.push(handler);
  }

  static unregisterLongPressHandler(handler: LongPressHandler): void {
    const idx = MapEventBus.longPressHandlers.indexOf(handler);
    if (idx >= 0) {
      MapEventBus.longPressHandlers.splice(idx, 1);
    }
  }

  static emitLongPress(point: LatLon): void {
    for (const h of MapEventBus.longPressHandlers) {
      try {
        h.onLongPress(point);
      } catch (e) {
        console.error('MapEventBus.longPress handler error', e);
      }
    }
  }

  static registerTransformHandler(handler: TransformHandler): void {
    if (!handler) {
      return;
    }
    MapEventBus.transformHandlers.push(handler);
  }

  static unregisterTransformHandler(handler: TransformHandler): void {
    const idx = MapEventBus.transformHandlers.indexOf(handler);
    if (idx >= 0) {
      MapEventBus.transformHandlers.splice(idx, 1);
    }
  }

  static emitTransform(zoom: number, offsetX: number, offsetY: number): void {
    for (const h of MapEventBus.transformHandlers) {
      try {
        h.onTransform(zoom, offsetX, offsetY);
      } catch (e) {
        console.error('MapEventBus.transform handler error', e);
      }
    }
  }
}
