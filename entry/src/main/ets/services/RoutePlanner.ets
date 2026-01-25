import { LatLon, MapWay, RenderData, RouteState } from '../model/MapTypes';
import { distanceMeters } from './MapMath';

interface GraphEdge {
  to: string;
  weight: number;
}

interface GraphNode {
  id: string;
  lat: number;
  lon: number;
  edges: Array<GraphEdge>;
}

interface QueueNode {
  id: string;
  dist: number;
}

export class RoutePlanner {
  buildRoute(start: LatLon, end: LatLon, renderData: RenderData | null, avoidPoints: Array<LatLon>): RouteState {
    if (!renderData || renderData.roads.length === 0) {
      const direct: RouteState = { start, end, path: [start, end] };
      return direct;
    }
  const graph = this.buildGraph(renderData);
    const nodes = Array.from(graph.values());
    let startNode = this.findNearestNode(nodes, start, avoidPoints);
    let endNode = this.findNearestNode(nodes, end, avoidPoints);
    if (!startNode || !endNode) {
      // fall back to nearest nodes without avoid filtering
      startNode = this.findNearestNode(nodes, start, []);
      endNode = this.findNearestNode(nodes, end, []);
    }
    if (!startNode || !endNode) {
      const direct: RouteState = { start, end, path: [start, end] };
      return direct;
    }
    const startDist = distanceMeters(start, { lat: startNode.lat, lon: startNode.lon });
    const endDist = distanceMeters(end, { lat: endNode.lat, lon: endNode.lon });
    let startId = startNode.id;
    let endId = endNode.id;
    if (startId === endId) {
      const altEnd = this.findSecondNearestNode(nodes, end, avoidPoints, startId);
      if (altEnd) {
        endId = altEnd.id;
      }
    }
    let pathIds = this.dijkstra(graph, startId, endId, avoidPoints);
    if (pathIds.length < 2 && avoidPoints.length > 0) {
      // Retry without avoid filters if they block all routes.
      pathIds = this.dijkstra(graph, startId, endId, []);
    }
    if (pathIds.length < 2) {
      // If no path exists, return empty path (do not draw straight line).
      const route: RouteState = { start, end, path: [] };
      return route;
    }
    const path: Array<LatLon> = [];
    for (let i = 0; i < pathIds.length; i++) {
      const node = graph.get(pathIds[i]) as GraphNode;
      const point: LatLon = { lat: node.lat, lon: node.lon };
      path.push(point);
    }
    const route: RouteState = { start, end, path };
    return route;
  }

  private buildGraph(renderData: RenderData): Map<string, GraphNode> {
    const graph = new Map<string, GraphNode>();
    for (const road of renderData.roads) {
      for (let i = 0; i < road.points.length; i++) {
        const point = road.points[i];
        const id = this.nodeId(point.lat, point.lon);
        if (!graph.has(id)) {
          graph.set(id, this.createNode(point.lat, point.lon));
        }
        if (i > 0) {
          const prev = road.points[i - 1];
          const prevId = this.nodeId(prev.lat, prev.lon);
          if (!graph.has(prevId)) {
            graph.set(prevId, this.createNode(prev.lat, prev.lon));
          }
          if (!this.edgeCrossesWater(prev, point, renderData.waters)) {
            const weight = distanceMeters({ lat: point.lat, lon: point.lon }, { lat: prev.lat, lon: prev.lon });
            this.addEdge(graph, id, prevId, weight);
            this.addEdge(graph, prevId, id, weight);
          }
        }
      }
    }
    this.connectNearbyNodes(graph, 18, renderData.waters);
    return graph;
  }

  private addEdge(graph: Map<string, GraphNode>, from: string, to: string, weight: number): void {
    const node = graph.get(from);
    if (!node) {
      return;
    }
    const existing = node.edges.find((edge) => edge.to === to);
    if (existing) {
      if (weight < existing.weight) {
        existing.weight = weight;
      }
      return;
    }
    const edge: GraphEdge = { to, weight };
    node.edges.push(edge);
  }

  private connectNearbyNodes(graph: Map<string, GraphNode>, maxMeters: number, waters: Array<MapWay>): void {
    const nodes = Array.from(graph.values());
    if (nodes.length < 2) {
      return;
    }
    const metersPerDegLat = 111320;
    let sumLat = 0;
    for (const node of nodes) {
      sumLat += node.lat;
    }
    const meanLat = sumLat / nodes.length;
    const lonScale = metersPerDegLat * Math.cos(meanLat * Math.PI / 180);
    const latCell = maxMeters / metersPerDegLat;
    const lonCell = maxMeters / (lonScale || metersPerDegLat);
    const buckets = new Map<string, Array<GraphNode>>();

    const bucketKey = (lat: number, lon: number): string => {
      const x = Math.floor(lat / latCell);
      const y = Math.floor(lon / lonCell);
      return `${x},${y}`;
    };

    for (const node of nodes) {
      const key = bucketKey(node.lat, node.lon);
      const bucket = buckets.get(key);
      if (bucket) {
        bucket.push(node);
      } else {
        buckets.set(key, [node]);
      }
    }

    for (const node of nodes) {
      const baseX = Math.floor(node.lat / latCell);
      const baseY = Math.floor(node.lon / lonCell);
      for (let dx = -1; dx <= 1; dx++) {
        for (let dy = -1; dy <= 1; dy++) {
          const key = `${baseX + dx},${baseY + dy}`;
          const bucket = buckets.get(key);
          if (!bucket) {
            continue;
          }
          for (const other of bucket) {
            if (other.id === node.id) {
              continue;
            }
            const dist = distanceMeters({ lat: node.lat, lon: node.lon }, { lat: other.lat, lon: other.lon });
            if (dist <= maxMeters) {
              if (!this.edgeCrossesWater(this.toLatLon(node), this.toLatLon(other), waters)) {
                this.addEdge(graph, node.id, other.id, dist);
                this.addEdge(graph, other.id, node.id, dist);
              }
            }
          }
        }
      }
    }
  }

  private edgeCrossesWater(a: LatLon, b: LatLon, waters: Array<MapWay>): boolean {
    if (!waters || waters.length === 0) {
      return false;
    }
    const mid: LatLon = { lat: (a.lat + b.lat) / 2, lon: (a.lon + b.lon) / 2 };
    for (const water of waters) {
      if (this.pointInPolygon(mid, water.points)) {
        return true;
      }
    }
    return false;
  }

  private toLatLon(node: GraphNode): LatLon {
    const point: LatLon = { lat: node.lat, lon: node.lon };
    return point;
  }

  private pointInPolygon(point: LatLon, polygon: Array<LatLon>): boolean {
    if (polygon.length < 3) {
      return false;
    }
    let inside = false;
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      const xi = polygon[i].lon;
      const yi = polygon[i].lat;
      const xj = polygon[j].lon;
      const yj = polygon[j].lat;
      const intersects = ((yi > point.lat) !== (yj > point.lat))
        && (point.lon < (xj - xi) * (point.lat - yi) / (yj - yi + 1e-12) + xi);
      if (intersects) {
        inside = !inside;
      }
    }
    return inside;
  }

  private findNearestNode(nodes: Array<GraphNode>, target: LatLon, avoidPoints: Array<LatLon>): GraphNode | null {
    let minDist = Number.MAX_VALUE;
    let selected: GraphNode | null = null;
    for (const node of nodes) {
      if (this.isAvoided(node, avoidPoints)) {
        continue;
      }
      const dist = distanceMeters({ lat: node.lat, lon: node.lon }, target);
      if (dist < minDist) {
        minDist = dist;
        selected = node;
      }
    }
    return selected;
  }

  private findSecondNearestNode(nodes: Array<GraphNode>, target: LatLon, avoidPoints: Array<LatLon>, excludeId: string): GraphNode | null {
    let minDist = Number.MAX_VALUE;
    let selected: GraphNode | null = null;
    for (const node of nodes) {
      if (node.id === excludeId) {
        continue;
      }
      if (this.isAvoided(node, avoidPoints)) {
        continue;
      }
      const dist = distanceMeters({ lat: node.lat, lon: node.lon }, target);
      if (dist < minDist) {
        minDist = dist;
        selected = node;
      }
    }
    return selected;
  }

  private dijkstra(graph: Map<string, GraphNode>, startId: string, endId: string, avoidPoints: Array<LatLon>): Array<string> {
    const distances = new Map<string, number>();
    const prev = new Map<string, string | null>();
    const visited = new Set<string>();
  const queue: Array<QueueNode> = [];

    graph.forEach((_, id) => {
      distances.set(id, Number.MAX_VALUE);
      prev.set(id, null);
    });
    distances.set(startId, 0);
  const startItem: QueueNode = { id: startId, dist: 0 };
  queue.push(startItem);

    while (queue.length > 0) {
      queue.sort((a, b) => a.dist - b.dist);
      const current = queue.shift();
      if (!current) {
        break;
      }
      if (visited.has(current.id)) {
        continue;
      }
      if (current.id === endId) {
        break;
      }
      visited.add(current.id);
      const node = graph.get(current.id);
      if (!node || this.isAvoided(node, avoidPoints)) {
        continue;
      }
      for (const edge of node.edges) {
        const nextNode = graph.get(edge.to);
        if (!nextNode || this.isAvoided(nextNode, avoidPoints)) {
          continue;
        }
        const alt = (distances.get(node.id) || Number.MAX_VALUE) + edge.weight;
        if (alt < (distances.get(edge.to) || Number.MAX_VALUE)) {
          distances.set(edge.to, alt);
          prev.set(edge.to, node.id);
          const nextItem: QueueNode = { id: edge.to, dist: alt };
          queue.push(nextItem);
        }
      }
    }

    return this.reconstructPath(prev, startId, endId);
  }

  private reconstructPath(prev: Map<string, string | null>, startId: string, endId: string): Array<string> {
    const path: Array<string> = [];
    let current: string | null = endId;
    while (current) {
      path.unshift(current);
      if (current === startId) {
        break;
      }
      current = prev.get(current) || null;
    }
    if (path.length === 0 || path[0] !== startId) {
      return [];
    }
    return path;
  }

  private nodeId(lat: number, lon: number): string {
    return `${lat.toFixed(6)},${lon.toFixed(6)}`;
  }

  private createNode(lat: number, lon: number): GraphNode {
    const node: GraphNode = { id: this.nodeId(lat, lon), lat, lon, edges: [] };
    return node;
  }

  private isAvoided(node: GraphNode, avoidPoints: Array<LatLon>): boolean {
    if (!avoidPoints || avoidPoints.length === 0) {
      return false;
    }
    for (const point of avoidPoints) {
      const dist = distanceMeters({ lat: node.lat, lon: node.lon }, point);
      if (dist < 12) {
        return true;
      }
    }
    return false;
  }
}
