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

    return new Promise<HttpResponse>((resolve, reject) => {
      request.request(url, {
        method,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        extraData: body ? JSON.stringify(body) : undefined,
        connectTimeout: 6000,
        readTimeout: 6000
      }, (err: BusinessError | null, data: http.HttpResponse) => {
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
