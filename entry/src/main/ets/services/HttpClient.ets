import http from '@ohos.net.http';
import { BusinessError } from '@ohos.base';

export class HttpRequestBody {
  username?: string;
  password?: string;
  name?: string;
  description?: string;
  imageUrl?: string;
  lat?: number;
  lon?: number;
  category?: string;
  hazardType?: string;
  status?: string;
  value?: number;
  placeId?: string;
  hidden?: boolean;
  sourceKey?: string;
  sourceType?: string;
  sourcePlaceId?: string;
  message?: string;
  email?: string;
  code?: string;
  purpose?: string;
  newPassword?: string;
}

export interface HttpResponse {
  status: number;
  body: string;
}

export class HttpClient {
  private baseUrl: string;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
  }

  setBaseUrl(baseUrl: string): void {
    this.baseUrl = baseUrl.replace(/\/$/, '');
  }

  async request(method: http.RequestMethod, path: string, body?: HttpRequestBody, token?: string): Promise<string> {
    const resp = await this.requestWithStatus(method, path, body, token);
    return resp.body;
  }

  async requestWithStatus(method: http.RequestMethod, path: string, body?: HttpRequestBody, token?: string): Promise<HttpResponse> {
    const url = `${this.baseUrl}${path}`;
    const request = http.createHttp();
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };
    if (token) {
      headers.Authorization = `Bearer ${token}`;
    }

    const connectTimeoutMs = 8000;
    const readTimeoutMs = 15000;
    const hardTimeoutMs = connectTimeoutMs + readTimeoutMs + 2000;

    return new Promise<HttpResponse>((resolve, reject) => {
      let settled = false;
      const timerId = setTimeout(() => {
        if (settled) {
          return;
        }
        settled = true;
        try {
          request.destroy();
        } catch {
          // ignore
        }
        reject(new Error('Request timeout'));
      }, hardTimeoutMs);

      request.request(url, {
        method,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        extraData: body ? JSON.stringify(body) : undefined,
        connectTimeout: connectTimeoutMs,
        readTimeout: readTimeoutMs
      }, (err: BusinessError | null, data: http.HttpResponse) => {
        if (settled) {
          try {
            request.destroy();
          } catch {
            // ignore
          }
          return;
        }
        settled = true;
        try {
          clearTimeout(timerId);
        } catch {
          // ignore
        }
        request.destroy();
        if (err) {
          reject(err);
          return;
        }
        const statusCode: number = typeof data.responseCode === 'number' ? data.responseCode : 0;
        const resultText: string = data && data.result !== undefined ? String(data.result) : '{}';
        resolve({ status: statusCode, body: resultText });
      });
    });
  }
}
