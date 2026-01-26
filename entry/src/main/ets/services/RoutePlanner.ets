import { LatLon, RenderData, RouteState } from '../model/MapTypes';

interface Point2D {
  x: number;
  y: number;
}

interface GraphEdge {
  to: number;
  w: number;
}

interface GraphNode {
  id: number;
  x: number;
  y: number;
  edges: Array<GraphEdge>;
}

export class RoutePlanner {
  buildRoute(start: LatLon, end: LatLon, renderData: RenderData | null): RouteState {
    if (!renderData || renderData.roads.length === 0) {
      return { start, end, path: [start, end] };
    }

    // Align with the working implementation from the reference branch: project lat/lon into a
    // fixed 2D plane, build a simple undirected graph, and run Dijkstra there.
    const lonSpan = renderData.bounds.maxLon - renderData.bounds.minLon;
    const latSpan = renderData.bounds.maxLat - renderData.bounds.minLat;
    if (lonSpan === 0 || latSpan === 0) {
      return { start, end, path: [start, end] };
    }

    const mapWidth = 2000;
    const mapHeight = mapWidth * (latSpan / lonSpan);

    const project = (lat: number, lon: number): Point2D => {
      const x = ((lon - renderData.bounds.minLon) / lonSpan) * mapWidth;
      const y = ((renderData.bounds.maxLat - lat) / latSpan) * mapHeight;
      return { x, y };
    };

    const unproject = (x: number, y: number): LatLon => {
      const lon = renderData.bounds.minLon + (x / mapWidth) * lonSpan;
      const lat = renderData.bounds.maxLat - (y / mapHeight) * latSpan;
      return { lat, lon };
    };

    const keyFor = (p: Point2D): string => {
      const rx = Math.round(p.x * 2) / 2;
      const ry = Math.round(p.y * 2) / 2;
      return `${rx},${ry}`;
    };

    const nodes: Array<GraphNode> = [];
    const keyMap = new Map<string, number>();

    const addNode = (p: Point2D): number => {
      const key = keyFor(p);
      const existing = keyMap.get(key);
      if (existing !== undefined) {
        return existing;
      }
      const id = nodes.length;
      nodes.push({ id, x: p.x, y: p.y, edges: [] });
      keyMap.set(key, id);
      return id;
    };

    const addEdge = (aIdx: number, bIdx: number, w: number): void => {
      if (aIdx === bIdx) return;
      const edgeAB: GraphEdge = { to: bIdx, w };
      const edgeBA: GraphEdge = { to: aIdx, w };
      nodes[aIdx].edges.push(edgeAB);
      nodes[bIdx].edges.push(edgeBA);
    };

    for (const road of renderData.roads) {
      const pts = road.points;
      for (let i = 1; i < pts.length; i++) {
        const a = project(pts[i - 1].lat, pts[i - 1].lon);
        const b = project(pts[i].lat, pts[i].lon);
        const aIdx = addNode(a);
        const bIdx = addNode(b);
        const dist = Math.hypot(a.x - b.x, a.y - b.y);
        addEdge(aIdx, bIdx, dist);
      }
    }

    if (nodes.length < 2) {
      return { start, end, path: [start, end] };
    }

    const nearestNodeIndex = (p: Point2D): number => {
      let best = -1;
      let bestDist = Number.POSITIVE_INFINITY;
      for (let i = 0; i < nodes.length; i++) {
        const n = nodes[i];
        const d = Math.hypot(n.x - p.x, n.y - p.y);
        if (d < bestDist) {
          bestDist = d;
          best = i;
        }
      }
      return best;
    };

    const startPt = project(start.lat, start.lon);
    const endPt = project(end.lat, end.lon);
    let startIdx = nearestNodeIndex(startPt);
    let endIdx = nearestNodeIndex(endPt);

    if (startIdx < 0 || endIdx < 0) {
      return { start, end, path: [start, end] };
    }

    if (startIdx === endIdx) {
      // pick a neighbor to avoid a 1-node path
      const edges = nodes[startIdx].edges;
      if (edges.length > 0) {
        edges.sort((a, b) => a.w - b.w);
        endIdx = edges[0].to;
      }
    }

    const pathIdx = this.dijkstra(nodes, startIdx, endIdx);
    if (pathIdx.length < 2) {
      return { start, end, path: [start, end] };
    }

    const path: Array<LatLon> = [];
    path.push(start);
    for (const idx of pathIdx) {
      const n = nodes[idx];
      path.push(unproject(n.x, n.y));
    }
    path.push(end);

    return { start, end, path };
  }

  private dijkstra(nodes: Array<GraphNode>, startIdx: number, endIdx: number): Array<number> {
    const n = nodes.length;
    const dist: Array<number> = new Array(n).fill(Number.POSITIVE_INFINITY);
    const prev: Array<number> = new Array(n).fill(-1);
    const visited: Array<boolean> = new Array(n).fill(false);

    dist[startIdx] = 0;

    for (let k = 0; k < n; k++) {
      let u = -1;
      let best = Number.POSITIVE_INFINITY;
      for (let i = 0; i < n; i++) {
        if (!visited[i] && dist[i] < best) {
          best = dist[i];
          u = i;
        }
      }
      if (u === -1) break;
      if (u === endIdx) break;
      visited[u] = true;
      for (const e of nodes[u].edges) {
        const alt = dist[u] + e.w;
        if (alt < dist[e.to]) {
          dist[e.to] = alt;
          prev[e.to] = u;
        }
      }
    }

    const path: Array<number> = [];
    let cur = endIdx;
    while (cur !== -1) {
      path.push(cur);
      cur = prev[cur];
    }
    path.reverse();
    if (path.length === 0 || path[0] !== startIdx) {
      return [];
    }
    return path;
  }
}
