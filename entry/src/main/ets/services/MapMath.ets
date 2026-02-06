import { Bounds, LatLon, Point } from '../model/MapTypes';

export function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

export function project(lat: number, lon: number, bounds: Bounds, width: number, height: number, zoom: number, offsetX: number, offsetY: number): Point {
  const lonSpan = bounds.maxLon - bounds.minLon || 1;
  const latSpan = bounds.maxLat - bounds.minLat || 1;
  const baseScaleX = width / lonSpan;
  const baseScaleY = height / latSpan;
  const baseScale = Math.min(baseScaleX, baseScaleY) * 0.96;
  const scale = baseScale * zoom;

  const x = (lon - bounds.minLon) * scale + (width - lonSpan * scale) / 2 + offsetX;
  const y = (bounds.maxLat - lat) * scale + (height - latSpan * scale) / 2 + offsetY;
  return { x, y };
}

export function unproject(x: number, y: number, bounds: Bounds, width: number, height: number, zoom: number, offsetX: number, offsetY: number): LatLon {
  const lonSpan = bounds.maxLon - bounds.minLon || 1;
  const latSpan = bounds.maxLat - bounds.minLat || 1;
  const baseScaleX = width / lonSpan;
  const baseScaleY = height / latSpan;
  const baseScale = Math.min(baseScaleX, baseScaleY) * 0.96;
  const scale = baseScale * zoom;
  const originX = (width - lonSpan * scale) / 2 + offsetX;
  const originY = (height - latSpan * scale) / 2 + offsetY;
  const lon = bounds.minLon + (x - originX) / scale;
  const lat = bounds.maxLat - (y - originY) / scale;
  return { lat, lon };
}

export function distanceMeters(a: LatLon, b: LatLon): number {
  const rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad;
  const dLon = (b.lon - a.lon) * rad;
  const lat1 = a.lat * rad;
  const lat2 = b.lat * rad;
  const sinDLat = Math.sin(dLat / 2);
  const sinDLon = Math.sin(dLon / 2);
  const h = sinDLat * sinDLat + Math.cos(lat1) * Math.cos(lat2) * sinDLon * sinDLon;
  const c = 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
  return 6371000 * c;
}

export function clampZoom(zoom: number): number {
  return clamp(zoom, 0.6, 3.5);
}
