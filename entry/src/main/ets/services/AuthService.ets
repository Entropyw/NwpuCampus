import http from '@ohos.net.http';
import { UserSession } from '../model/MapTypes';
import { HttpClient, HttpRequestBody, HttpResponse } from './HttpClient';

interface UserRecord {
  username: string;
  password: string;
  isAdmin: boolean;
}

interface AuthUserInfo {
  id: string;
  username: string;
  isAdmin: boolean;
}

interface AuthResponse {
  token: string;
  user: AuthUserInfo;
}

interface ErrorResponse {
  error?: string;
}

class AuthRequest extends HttpRequestBody {
  constructor(username: string, password: string) {
    super();
    this.username = username;
    this.password = password;
  }
}

export class AuthService {
  private users: Map<string, UserRecord> = new Map();
  private session: UserSession | null = null;
  private client: HttpClient | null = null;
  private useRemote: boolean = false;
  private lastError: string = '';

  constructor() {
    this.users.set('admin', { username: 'admin', password: 'admin123', isAdmin: true });
  }

  enableRemote(baseUrl: string): void {
    this.client = new HttpClient(baseUrl);
    this.useRemote = true;
    this.lastError = '';
  }

  async register(username: string, password: string): Promise<UserSession | null> {
    const trimmed = username.trim();
    this.lastError = '';
    if (!trimmed) {
      this.lastError = '用户名不能为空';
      return null;
    }
    if (this.users.has(trimmed)) {
      this.lastError = '用户已存在';
      return null;
    }
    if (this.useRemote && this.client) {
      try {
        const payload: AuthRequest = new AuthRequest(trimmed, password);
        const resp: HttpResponse = await this.client.requestWithStatus(http.RequestMethod.POST, '/api/register', payload);
        if (resp.status === 401) {
          this.lastError = this.extractErrorMessage(resp.body) || '用户名或密码错误';
          return null;
        }
        const response = this.parseAuthResponse(resp.body);
        if (response) {
          const session: UserSession = {
            token: response.token,
            username: response.user.username,
            isAdmin: response.user.isAdmin
          };
          this.session = session;
          return session;
        }
        if (resp.status >= 200 && resp.status < 300) {
          this.lastError = this.extractErrorMessage(resp.body) || '注册失败';
        } else {
          this.lastError = this.extractErrorMessage(resp.body) || `注册失败，状态码${resp.status}`;
        }
        return null;
      } catch (e) {
        this.lastError = `网络错误：${String(e)}`;
        return null;
      }
    }
    const record: UserRecord = { username: trimmed, password, isAdmin: false };
    this.users.set(trimmed, record);
    return await this.login(trimmed, password);
  }

  async login(username: string, password: string): Promise<UserSession | null> {
    const trimmed = username.trim();
    this.lastError = '';
    const record = this.users.get(trimmed);
    if (this.useRemote && this.client) {
      try {
        const payload: AuthRequest = new AuthRequest(trimmed, password);
        const resp: HttpResponse = await this.client.requestWithStatus(http.RequestMethod.POST, '/api/login', payload);
        if (resp.status === 401) {
          this.lastError = this.extractErrorMessage(resp.body) || '用户名或密码错误';
          return null;
        }
        const response = this.parseAuthResponse(resp.body);
        if (response) {
          const session: UserSession = {
            token: response.token,
            username: response.user.username,
            isAdmin: response.user.isAdmin
          };
          this.session = session;
          return session;
        }
        if (resp.status >= 200 && resp.status < 300) {
          this.lastError = this.extractErrorMessage(resp.body) || '登录失败';
        } else {
          this.lastError = this.extractErrorMessage(resp.body) || `登录失败，状态码${resp.status}`;
        }
        return null;
      } catch (e) {
        this.lastError = `网络错误：${String(e)}`;
        return null;
      }
    }
    if (!record || record.password !== password) {
      this.lastError = '用户名或密码错误';
      return null;
    }
    const token = `${record.username}-${Date.now()}`;
    this.session = { token, username: record.username, isAdmin: record.isAdmin };
    return this.session;
  }

  logout(): void {
    this.session = null;
    this.lastError = '';
  }

  getSession(): UserSession | null {
    return this.session;
  }

  getLastError(): string {
    return this.lastError;
  }

  private parseAuthResponse(text: string): AuthResponse | null {
    try {
      const raw: AuthResponse = JSON.parse(text) as AuthResponse;
      if (!raw || !raw.token || !raw.user) {
        return null;
      }
      return raw;
    } catch {
      return null;
    }
  }

  private extractErrorMessage(text: string): string {
    try {
      const raw: ErrorResponse = JSON.parse(text) as ErrorResponse;
      const errMsg: string | undefined = raw ? raw.error : undefined;
      if (typeof errMsg === 'string' && errMsg.length > 0) {
        return errMsg;
      }
    } catch {
      // ignore parse error
    }
    return '';
  }
}
