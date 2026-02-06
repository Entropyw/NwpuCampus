import { Bounds, LatLon, MapLabel, MapWay, RenderData } from '../model/MapTypes';

interface ParsedNode {
  id: string;
  lat: number;
  lon: number;
  name?: string;
  tags: Record<string, string>;
}

export class OsmParser {
  parse(osmText: string): RenderData {
    const nodes = new Map<string, ParsedNode>();
    const labels: Array<MapLabel> = [];

    const bounds = this.parseBounds(osmText);

    const nodeRegex = /<node\b([^>]*?)(?:\/>|>([\s\S]*?)<\/node>)/g;
    let nodeMatch: RegExpExecArray | null = null;
    while ((nodeMatch = nodeRegex.exec(osmText)) !== null) {
      const attrsText = nodeMatch[1] || '';
      const bodyText = nodeMatch[2] || '';
      const attrs = this.parseAttrs(attrsText);
      const id = attrs.id || '';
      const lat = parseFloat(attrs.lat || '0');
      const lon = parseFloat(attrs.lon || '0');
      if (!id || Number.isNaN(lat) || Number.isNaN(lon)) {
        continue;
      }
      const tags = this.parseTags(bodyText);
      const name = tags.name;
      nodes.set(id, { id, lat, lon, name, tags });
      if (name) {
        labels.push({ name, lat, lon, priority: 2, kind: tags.amenity || tags.highway || tags.building });
      }
    }

    const roads: Array<MapWay> = [];
    const buildings: Array<MapWay> = [];
    const waters: Array<MapWay> = [];
    const areas: Array<MapWay> = [];
    const pitches: Array<MapWay> = [];

    const wayRegex = /<way\b([^>]*?)>([\s\S]*?)<\/way>/g;
    let wayMatch: RegExpExecArray | null = null;
    while ((wayMatch = wayRegex.exec(osmText)) !== null) {
      const body = wayMatch[2] || '';
      const tags = this.parseTags(body);
      const ndRefs = this.parseNdRefs(body);
      const points = this.resolveWayPoints(nodes, ndRefs);
      if (points.length < 2) {
        continue;
      }
      const name = tags.name || '';
      if (tags.highway) {
        roads.push({ points, type: tags.highway, name });
      } else if (tags.building) {
        buildings.push({ points, type: 'building', name });
      } else if (tags.natural === 'water' || tags.waterway || tags.landuse === 'reservoir') {
        waters.push({ points, type: 'water', name });
      } else if (tags.leisure || tags.landuse) {
        areas.push({ points, type: tags.leisure || tags.landuse, name });
      } else if (tags.sport) {
        pitches.push({ points, type: tags.sport, name });
      }

      if (name) {
        const center = this.computeCentroid(points);
        labels.push({ name, lat: center.lat, lon: center.lon, priority: 1, kind: tags.highway || tags.building || tags.leisure || tags.landuse });
      }
    }

    const resolvedBounds = bounds || this.computeBounds(nodes);
    return {
      bounds: resolvedBounds,
      roads,
      buildings,
      waters,
      areas,
      pitches,
      labels
    };
  }

  private parseBounds(text: string): Bounds | null {
    const match = /<bounds\b([^>]*?)\/>/.exec(text);
    if (!match) {
      return null;
    }
    const attrs = this.parseAttrs(match[1]);
    const minLat = parseFloat(attrs.minlat || '0');
    const maxLat = parseFloat(attrs.maxlat || '0');
    const minLon = parseFloat(attrs.minlon || '0');
    const maxLon = parseFloat(attrs.maxlon || '0');
    if ([minLat, maxLat, minLon, maxLon].some((v) => Number.isNaN(v))) {
      return null;
    }
    return { minLat, maxLat, minLon, maxLon };
  }

  private parseAttrs(text: string): Record<string, string> {
    const attrs: Record<string, string> = {};
    const attrRegex = /(\w+)="([^"]*)"/g;
    let match: RegExpExecArray | null = null;
    while ((match = attrRegex.exec(text)) !== null) {
      attrs[match[1]] = match[2];
    }
    return attrs;
  }

  private parseTags(text: string): Record<string, string> {
    const tags: Record<string, string> = {};
    const tagRegex = /<tag\b[^>]*?k="([^"]*)"[^>]*?v="([^"]*)"[^>]*?\/>/g;
    let match: RegExpExecArray | null = null;
    while ((match = tagRegex.exec(text)) !== null) {
      tags[match[1]] = match[2];
    }
    return tags;
  }

  private parseNdRefs(text: string): Array<string> {
    const refs: Array<string> = [];
    const ndRegex = /<nd\b[^>]*?ref="([^"]*)"[^>]*?\/>/g;
    let match: RegExpExecArray | null = null;
    while ((match = ndRegex.exec(text)) !== null) {
      refs.push(match[1]);
    }
    return refs;
  }

  private resolveWayPoints(nodes: Map<string, ParsedNode>, refs: Array<string>): Array<LatLon> {
    const points: Array<LatLon> = [];
    for (let i = 0; i < refs.length; i++) {
      const node = nodes.get(refs[i]);
      if (node) {
        points.push({ lat: node.lat, lon: node.lon });
      }
    }
    return points;
  }

  private computeBounds(nodes: Map<string, ParsedNode>): Bounds {
    let minLat = 90;
    let maxLat = -90;
    let minLon = 180;
    let maxLon = -180;
    for (const node of nodes.values()) {
      minLat = Math.min(minLat, node.lat);
      maxLat = Math.max(maxLat, node.lat);
      minLon = Math.min(minLon, node.lon);
      maxLon = Math.max(maxLon, node.lon);
    }
    if (!nodes.size) {
      minLat = 34.029;
      maxLat = 34.034;
      minLon = 108.758;
      maxLon = 108.766;
    }
    return { minLat, maxLat, minLon, maxLon };
  }

  private computeCentroid(points: Array<LatLon>): LatLon {
    let sumLat = 0;
    let sumLon = 0;
    for (const point of points) {
      sumLat += point.lat;
      sumLon += point.lon;
    }
    const count = points.length || 1;
    return { lat: sumLat / count, lon: sumLon / count };
  }
}
