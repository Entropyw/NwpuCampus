import http from '@ohos.net.http';
import { UserSession } from '../model/MapTypes';
import { HttpClient, HttpRequestBody } from './HttpClient';

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

  constructor() {
    this.users.set('admin', { username: 'admin', password: 'admin123', isAdmin: true });
  }

  enableRemote(baseUrl: string): void {
    this.client = new HttpClient(baseUrl);
    this.useRemote = true;
  }

  async register(username: string, password: string): Promise<UserSession | null> {
    const trimmed = username.trim();
    if (!trimmed || this.users.has(trimmed)) {
      return null;
    }
    if (this.useRemote && this.client) {
      try {
  const payload: AuthRequest = new AuthRequest(trimmed, password);
  const responseText = await this.client.request(http.RequestMethod.POST, '/api/register', payload);
        const response = this.parseAuthResponse(responseText);
        if (response) {
          const session: UserSession = {
            token: response.token,
            username: response.user.username,
            isAdmin: response.user.isAdmin
          };
          this.session = session;
          return session;
        }
      } catch (e) {
        // fallback to local
      }
    }
    const record: UserRecord = { username: trimmed, password, isAdmin: false };
    this.users.set(trimmed, record);
    return await this.login(trimmed, password);
  }

  async login(username: string, password: string): Promise<UserSession | null> {
    const record = this.users.get(username.trim());
    if (this.useRemote && this.client) {
      try {
  const payload: AuthRequest = new AuthRequest(username.trim(), password);
  const responseText = await this.client.request(http.RequestMethod.POST, '/api/login', payload);
        const response = this.parseAuthResponse(responseText);
        if (response) {
          const session: UserSession = {
            token: response.token,
            username: response.user.username,
            isAdmin: response.user.isAdmin
          };
          this.session = session;
          return session;
        }
      } catch (e) {
        // fallback to local
      }
    }
    if (!record || record.password !== password) {
      return null;
    }
    const token = `${record.username}-${Date.now()}`;
    this.session = { token, username: record.username, isAdmin: record.isAdmin };
    return this.session;
  }

  logout(): void {
    this.session = null;
  }

  getSession(): UserSession | null {
    return this.session;
  }

  private parseAuthResponse(text: string): AuthResponse | null {
    try {
      const raw = JSON.parse(text) as AuthResponse;
      if (!raw || !raw.token || !raw.user) {
        return null;
      }
      return raw;
    } catch (e) {
      return null;
    }
  }
}
