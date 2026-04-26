import { FacilityMap } from './map';
import { Chat } from './chat';

let facilityMap: FacilityMap;
let chat: Chat;

function initTabs(): void {
  document.querySelectorAll<HTMLElement>('[data-tab]').forEach(btn => {
    btn.addEventListener('click', () => {
      const tab = btn.dataset.tab!;

      document.querySelectorAll('[data-tab]').forEach(b => b.classList.remove('active'));
      document.querySelectorAll<HTMLElement>('.vc-view').forEach(v => {
        v.style.display = 'none';
      });

      btn.classList.add('active');
      const view = document.getElementById(`vc-view-${tab}`);
      if (view) view.style.display = 'flex';

      if (tab === 'pulse') {
        setTimeout(() => facilityMap.invalidate(), 60);
      }
    });
  });
}

document.addEventListener('DOMContentLoaded', () => {
  facilityMap = new FacilityMap('vc-map');

  chat = new Chat(data => {
    facilityMap.update(data.facilities, data.map);
  });

  initTabs();

  // Wire up DOM event handlers
  const input = document.getElementById('vc-input') as HTMLTextAreaElement;
  input.addEventListener('keydown', (e: KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      chat.send();
    }
  });
  input.addEventListener('input', () => chat.autoResize());

  document.getElementById('vc-send')!.addEventListener('click', () => chat.send());

  document.querySelectorAll<HTMLElement>('.vc-chip').forEach(chip => {
    chip.addEventListener('click', () => chat.send(chip.textContent ?? ''));
  });
});
