import http from '@ohos.net.http';
import { HttpClient, HttpRequestBody } from './HttpClient';
import { PlaceType, UserSession } from '../model/MapTypes';

export interface MessagePlaceSnapshot {
  name: string;
  description: string;
  lat: number;
  lon: number;
  type: PlaceType;
  imageUrl?: string;
  sourceKey?: string;
  sourceType?: string;
  sourcePlaceId?: string;
}

export interface UserMessage {
  id: string;
  username: string;
  title: string;
  content: string;
  createdAt: number;
  unread: boolean;
  action?: 'resubmit';
  place?: MessagePlaceSnapshot;
}

interface MessageListResponse {
  messages?: UserMessage[];
}

class MessageRequest extends HttpRequestBody {
  username: string;
  title: string;
  content: string;
  action?: string;
  place?: MessagePlaceSnapshot;

  constructor(username: string, title: string, content: string, action?: string, place?: MessagePlaceSnapshot) {
    super();
    this.username = username;
    this.title = title;
    this.content = content;
    if (action) {
      this.action = action;
    }
    if (place) {
      this.place = place;
    }
  }
}

export class MessageService {
  private client: HttpClient | null = null;
  private useRemote: boolean = false;

  enableRemote(baseUrl: string): void {
    this.client = new HttpClient(baseUrl);
    this.useRemote = true;
  }

  async list(session: UserSession | null): Promise<UserMessage[]> {
    if (!session || !this.useRemote || !this.client || !session.token) {
      return [];
    }
    try {
      const responseText = await this.client.request(http.RequestMethod.GET, '/api/messages', undefined, session.token);
      const response = JSON.parse(responseText) as MessageListResponse;
      return response.messages || [];
    } catch {
      return [];
    }
  }

  async pushMessage(username: string, message: UserMessage, session: UserSession | null): Promise<boolean> {
    if (!session || !this.useRemote || !this.client || !session.token) {
      return false;
    }
    try {
      const payload = new MessageRequest(username, message.title, message.content, message.action, message.place);
      await this.client.request(http.RequestMethod.POST, '/api/messages', payload, session.token);
      return true;
    } catch {
      return false;
    }
  }

  async markAllRead(session: UserSession | null): Promise<boolean> {
    if (!session || !this.useRemote || !this.client || !session.token) {
      return false;
    }
    try {
      const payload = new HttpRequestBody();
      await this.client.request(http.RequestMethod.POST, '/api/messages/read', payload, session.token);
      return true;
    } catch {
      return false;
    }
  }
}
