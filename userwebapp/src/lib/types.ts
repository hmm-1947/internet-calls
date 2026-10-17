export interface BadgeTag { id: number; name: string; color: string }

export interface Listener {
  id: number;
  name: string;
  is_online: boolean;
  presence_online: boolean;
  is_in_call: boolean;
  video_call_enabled: boolean;
  tags: string[];
  avg_rating: number | null;
  rating_count: number;
  photo_url: string | null;
  age: number | null;
  occupation: string | null;
  badge_tag: BadgeTag | null;
  last_interacted_at: string | null;
  about?: string | null;
  languages?: string[];
  created_at?: string | null;
}

export interface Me {
  id: number;
  name: string;
  username: string | null;
  email: string | null;
  phone: string | null;
  email_verified: boolean;
  phone_verified: boolean;
  is_google_account: boolean;
  username_cooldown_seconds: number;
  email_cooldown_seconds: number;
  phone_cooldown_seconds: number;
  coins: number;
  chat_message_coin_cost: number;
  bio: string | null;
  photo_url: string | null;
  video_call_enabled: boolean;
  video_call_disabled_by_admin: boolean;
}

export interface Thread {
  user_id: number;
  user_name: string;
  listener_id: number;
  listener_name: string;
  last_message: string;
  last_message_at: string;
  last_message_type: string;
  last_call_type: string | null;
  last_call_status: string | null;
  last_call_duration_seconds: number | null;
  unread_count: number;
  is_pinned: boolean;
  is_archived: boolean;
  is_muted: boolean;
  is_online: boolean;
  presence_online?: boolean;
  last_seen: string | null;
  photo_url: string | null;
  badge_tag?: BadgeTag | null;
}

export interface ChatMsg {
  id: number | null;
  client_id: string | null;
  user_id: number;
  listener_id: number;
  sender_type: "user" | "listener";
  message: string;
  message_type: string | null;
  audio_url: string | null;
  audio_duration: number | null;
  gift_id: number | null;
  gift_name: string | null;
  gift_icon: string | null;
  gift_coins: number | null;
  call_id: number | null;
  call_type: string | null;
  call_status: string | null;
  call_duration_seconds: number | null;
  status: string;
  is_read: boolean;
  delivered_at: string | null;
  read_at: string | null;
  edited_at: string | null;
  is_deleted: boolean;
  created_at: string;
  pending?: boolean;
  failed?: boolean;
}

export interface Plan {
  id: number;
  name: string;
  price: number;
  coins: number;
  icon: string;
  is_featured: boolean;
}

export interface Gift { id: number; name: string; coins: number; icon: string | null }

export interface CallHistoryItem {
  id: number;
  listener_id: number;
  listener_name: string;
  call_type: string;
  status: string;
  duration_seconds: number | null;
  coins_deducted: number | null;
  created_at: string;
  connected_at: string | null;
  other_party_photo_url: string | null;
  badge_tag: BadgeTag | null;
}

export interface CallSummary {
  call_id: number;
  listener_id: number;
  listener_name: string;
  listener_photo_url: string | null;
  duration_seconds: number | null;
  coins_deducted: number | null;
  existing_rating: number | null;
  existing_review: string | null;
  badge_tag: BadgeTag | null;
}

export interface Purchase {
  id: number;
  plan_id: number;
  plan_name: string;
  price_paid: number;
  coins_purchased: number;
  status: string;
  created_at: string;
}

export interface AuthResponse { token: string; id: number; name: string }
