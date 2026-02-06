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
  email?: string;
  requireEmailBind?: boolean;
}

interface AuthResponse {
  token: string;
  user: AuthUserInfo;
}

interface ErrorResponse {
  error?: string;
  message?: string;
}

class AuthRequest extends HttpRequestBody {
  username: string;
  password: string;
  email?: string;

  constructor(username: string, password: string, email?: string) {
    super();
    this.username = username;
    this.password = password;
    if (email) {
      this.email = email;
    }
  }
}

class EmailRequest extends HttpRequestBody {
  username: string;
  email: string;
  purpose: 'bind' | 'reset';

  constructor(username: string, email: string, purpose: 'bind' | 'reset') {
    super();
    this.username = username;
    this.email = email;
    this.purpose = purpose;
  }
}

class BindEmailRequest extends HttpRequestBody {
  username: string;
  email: string;
  code: string;

  constructor(username: string, email: string, code: string) {
    super();
    this.username = username;
    this.email = email;
    this.code = code;
  }
}

class ResetPasswordRequest extends HttpRequestBody {
  username: string;
  code: string;
  newPassword: string;

  constructor(username: string, code: string, newPassword: string) {
    super();
    this.username = username;
    this.code = code;
    this.newPassword = newPassword;
  }
}

export class AuthService {
  private users: Map<string, UserRecord> = new Map();
  private session: UserSession | null = null;
  private client: HttpClient | null = null;
  private emailClient: HttpClient | null = null;
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

  enableEmailRemote(emailBaseUrl: string): void {
    this.emailClient = new HttpClient(emailBaseUrl);
  }

  async register(username: string, password: string, email?: string): Promise<UserSession | null> {
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
        const payload: AuthRequest = new AuthRequest(trimmed, password, email);
        const resp: HttpResponse = await this.client.requestWithStatus(http.RequestMethod.POST, '/api/register', payload);
        if (resp.status === 401 || resp.status === 400) {
          this.lastError = this.extractErrorMessage(resp.body) || '用户名或密码错误';
          return null;
        }
        const response = this.parseAuthResponse(resp.body);
        if (response) {
          const session: UserSession = {
            token: response.token,
            username: response.user.username,
            isAdmin: response.user.isAdmin,
            email: response.user.email,
            requireEmailBind: response.user.requireEmailBind
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
        const payload: AuthRequest = new AuthRequest(trimmed, password, undefined);
        const resp: HttpResponse = await this.client.requestWithStatus(http.RequestMethod.POST, '/api/login', payload);
        if (resp.status === 401 || resp.status === 400) {
          this.lastError = this.extractErrorMessage(resp.body) || '用户名或密码错误';
          return null;
        }
        const response = this.parseAuthResponse(resp.body);
        if (response) {
          const session: UserSession = {
            token: response.token,
            username: response.user.username,
            isAdmin: response.user.isAdmin,
            email: response.user.email,
            requireEmailBind: response.user.requireEmailBind
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

  setSessionEmail(email: string, requireEmailBind?: boolean): void {
    if (this.session) {
      this.session.email = email;
      if (requireEmailBind !== undefined) {
        this.session.requireEmailBind = requireEmailBind;
      }
    }
  }

  async sendEmailCode(account: string, email: string, purpose: 'bind' | 'reset'): Promise<boolean> {
    const trimmed = account.trim();
    const target = email.trim();
    this.lastError = '';
    if (!trimmed || !target) {
      this.lastError = '账号或邮箱不能为空';
      return false;
    }
    if (this.useRemote && this.client) {
      try {
        const payload: EmailRequest = new EmailRequest(trimmed, target, purpose);
        const resp = this.emailClient
          ? await this.emailClient.requestWithStatus(http.RequestMethod.POST, '/api/email/send', payload)
          : await this.client.requestWithStatus(http.RequestMethod.POST, '/api/email/send', payload);
        if (resp.status >= 200 && resp.status < 300) {
          return true;
        }
        // Prefer structured error message, otherwise fall back to raw body text
        const parsed = this.extractErrorMessage(resp.body);
        this.lastError = parsed || (typeof resp.body === 'string' && resp.body.length > 0 ? String(resp.body) : `发送失败，状态码${resp.status}`);
        return false;
      } catch (e) {
        this.lastError = `网络错误：${String(e)}`;
        return false;
      }
    }
    this.lastError = '当前环境未配置远程服务';
    return false;
  }

  async bindEmail(account: string, email: string, code: string): Promise<boolean> {
    const trimmed = account.trim();
    const target = email.trim();
    const trimmedCode = code.trim();
    this.lastError = '';
    if (!trimmed || !target || !trimmedCode) {
      this.lastError = '账号、邮箱或验证码不能为空';
      return false;
    }
    if (this.useRemote && this.client) {
      try {
        const payload: BindEmailRequest = new BindEmailRequest(trimmed, target, trimmedCode);
        const resp = this.emailClient
          ? await this.emailClient.requestWithStatus(http.RequestMethod.POST, '/api/email/bind', payload)
          : await this.client.requestWithStatus(http.RequestMethod.POST, '/api/email/bind', payload);
        if (resp.status >= 200 && resp.status < 300) {
          return true;
        }
        const parsed = this.extractErrorMessage(resp.body);
        this.lastError = parsed || (typeof resp.body === 'string' && resp.body.length > 0 ? String(resp.body) : `绑定失败，状态码${resp.status}`);
        return false;
      } catch (e) {
        this.lastError = `网络错误：${String(e)}`;
        return false;
      }
    }
    this.lastError = '当前环境未配置远程服务';
    return false;
  }

  async resetPassword(account: string, code: string, newPassword: string): Promise<boolean> {
    const trimmed = account.trim();
    const trimmedCode = code.trim();
    const nextPassword = newPassword.trim();
    this.lastError = '';
    if (!trimmed || !trimmedCode || !nextPassword) {
      this.lastError = '账号、验证码或新密码不能为空';
      return false;
    }
    if (this.useRemote && this.client) {
      try {
        const payload: ResetPasswordRequest = new ResetPasswordRequest(trimmed, trimmedCode, nextPassword);
        const resp = this.emailClient
          ? await this.emailClient.requestWithStatus(http.RequestMethod.POST, '/api/password/reset', payload)
          : await this.client.requestWithStatus(http.RequestMethod.POST, '/api/password/reset', payload);
        if (resp.status >= 200 && resp.status < 300) {
          return true;
        }
        const parsed = this.extractErrorMessage(resp.body);
        this.lastError = parsed || (typeof resp.body === 'string' && resp.body.length > 0 ? String(resp.body) : `重置失败，状态码${resp.status}`);
        return false;
      } catch (e) {
        this.lastError = `网络错误：${String(e)}`;
        return false;
      }
    }
    this.lastError = '当前环境未配置远程服务';
    return false;
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
    const normalize = (msg: string): string => {
      const trimmed = msg.trim();
      const lower = trimmed.toLowerCase();
      if (!trimmed) {
        return '';
      }
      if (lower.includes('invalid credentials')) {
        return '用户名或密码错误';
      }
      if (lower.includes('user exists')) {
        return '用户已存在';
      }
      if (lower.includes('name required')) {
        return '请填写必填信息';
      }
      return trimmed;
    };

    try {
      const raw: ErrorResponse = JSON.parse(text) as ErrorResponse;
      const errMsg: string | undefined = raw ? raw.error : undefined;
      const message: string | undefined = raw ? raw.message : undefined;
      if (typeof errMsg === 'string' && errMsg.length > 0) {
        return normalize(errMsg);
      }
      if (typeof message === 'string' && message.length > 0) {
        return normalize(message);
      }
    } catch {
      // ignore parse error
    }
    return '';
  }
}
