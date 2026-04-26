export interface Facility {
  facility_id: string;
  name: string;
  address: string;
  city: string | null;
  phone: string | null;
  type: string | null;
  has_emergency: boolean;
  has_icu: boolean;
  has_obg: boolean;
  has_surgery: boolean;
  lat: number;
  lng: number;
}

export interface MapConfig {
  center: [number, number];
  zoom: number;
}

export interface ChatResponse {
  answer: string;
  facilities: Facility[];
  map: MapConfig;
  is_emergency: boolean;
  sql_used: string;
  result_count: number;
  trust_score: number;
  validation_note: string;
}
