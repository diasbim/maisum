export type CustomerFeatureFlagsDto = {
  customer_app_enabled: boolean;
  customer_redemption_enabled: boolean;
  customer_qr_enabled: boolean;
  customer_push_enabled: boolean;
  customer_deep_links_enabled: boolean;
};

export type CustomerRewardDto = {
  reward_id: string;
  name: string;
  description: string | null;
  points_required: number;
  confirmed_points: number;
  points_remaining: number;
  eligible: boolean;
  expires_at: number | null;
};

export type CustomerBusinessDto = {
  business_id: string;
  name: string;
  logo_url: string | null;
  address: string | null;
  phone: string | null;
  confirmed_points: number;
  last_visit_at: number | null;
  rewards: CustomerRewardDto[];
  next_reward: CustomerRewardDto | null;
};

export type CustomerActivityDto = {
  business_id: string;
  entry_id: string;
  type: 'SALE' | 'REDEMPTION';
  points_delta: number;
  occurred_at: number;
  reward_id: string | null;
};

export type CustomerPreferencesDto = {
  notifications_enabled: boolean;
  marketing_enabled: boolean;
  deep_links_enabled: boolean;
};

export type CustomerDeepLinksDto = {
  routes: string[];
  parameterized_routes: string[];
};
