import http from '@ohos.net.http';

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

export class HttpClient {
  private baseUrl: string;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
  }

  setBaseUrl(baseUrl: string): void {
    this.baseUrl = baseUrl.replace(/\/$/, '');
  }

  async request(method: http.RequestMethod, path: string, body?: HttpRequestBody, token?: string): Promise<string> {
    const url = `${this.baseUrl}${path}`;
    const request = http.createHttp();
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };
    if (token) {
      headers.Authorization = `Bearer ${token}`;
    }

    return new Promise<string>((resolve, reject) => {
      request.request(url, {
        method,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        extraData: body ? JSON.stringify(body) : undefined,
        connectTimeout: 6000,
        readTimeout: 6000
      }, (err, data) => {
        request.destroy();
        if (err) {
          reject(err);
          return;
        }
        const resultText = (data.result ? String(data.result) : '{}');
        try {
          resolve(resultText);
        } catch (parseError) {
          reject(parseError);
        }
      });
    });
  }
}
