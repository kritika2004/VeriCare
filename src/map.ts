import type { Facility, MapConfig } from './types';

const MARKER_COLORS = {
  emergency: '#F43F5E',
  icu:       '#8B5CF6',
  government:'#10B981',
  default:   '#38BDF8',
};

function markerColor(f: Facility): string {
  if (f.has_emergency) return MARKER_COLORS.emergency;
  if (f.has_icu)       return MARKER_COLORS.icu;
  if (f.type === 'government') return MARKER_COLORS.government;
  return MARKER_COLORS.default;
}

function esc(s: string | null | undefined): string {
  if (!s) return '';
  return String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

export class FacilityMap {
  private map: L.Map;
  private layer: L.LayerGroup;

  constructor(containerId: string) {
    this.map = L.map(containerId, { zoomControl: true }).setView([20.5937, 78.9629], 5);

    L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
      attribution: '© <a href="https://carto.com/attributions" target="_blank">CARTO</a>',
      maxZoom: 18,
    }).addTo(this.map);

    this.layer = L.layerGroup().addTo(this.map);
  }

  invalidate(): void {
    this.map.invalidateSize();
  }

  update(facilities: Facility[], cfg: MapConfig): void {
    this.layer.clearLayers();

    if (!facilities.length) {
      this.map.flyTo([20.5937, 78.9629], 5, { duration: 1 });
      return;
    }

    for (const f of facilities) {
      const color = markerColor(f);

      const marker = L.circleMarker([f.lat, f.lng], {
        radius: 8,
        fillColor: color,
        color: '#0F172A',
        weight: 1.5,
        fillOpacity: 0.9,
      });

      const caps = [
        f.has_emergency ? '🚨 Emergency' : '',
        f.has_icu       ? '🏥 ICU'       : '',
        f.has_obg       ? '👶 OB/GYN'    : '',
        f.has_surgery   ? '🔪 Surgery'   : '',
      ].filter(Boolean).join(' · ');

      marker.bindPopup(`
        <div style="min-width:200px">
          <div class="vc-popup-name">${esc(f.name)}</div>
          <div class="vc-popup-addr">${esc(f.address)}</div>
          <div class="vc-popup-phone">📞 ${
            f.phone
              ? `<b>${esc(f.phone)}</b>`
              : '<span class="vc-no-phone">No phone listed</span>'
          }</div>
          ${caps ? `<div class="vc-popup-caps">${caps}</div>` : ''}
          <div class="vc-popup-type">${esc(f.type ?? 'facility')}</div>
        </div>
      `);

      this.layer.addLayer(marker);
    }

    const layers = this.layer.getLayers() as L.Layer[];
    if (facilities.length === 1) {
      this.map.flyTo(cfg.center, cfg.zoom, { duration: 1.2 });
    } else {
      const group = L.featureGroup(layers);
      this.map.flyToBounds(group.getBounds().pad(0.25), {
        duration: 1.2,
        maxZoom: cfg.zoom,
      });
    }
  }
}
