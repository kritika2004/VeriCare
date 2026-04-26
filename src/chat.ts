import { marked } from 'marked';
import type { ChatResponse } from './types';

marked.use({ breaks: true, gfm: true });

export type ResponseHandler = (data: ChatResponse) => void;

function trustColor(score: number): string {
  if (score >= 85) return '#10B981';
  if (score >= 65) return '#F59E0B';
  return '#F43F5E';
}

export class Chat {
  private messagesEl: HTMLElement;
  private inputEl: HTMLTextAreaElement;
  private sendBtn: HTMLButtonElement;
  private emergencyBanner: HTMLElement;
  private mapOverlay: HTMLElement;
  private onResponse: ResponseHandler;

  constructor(onResponse: ResponseHandler) {
    this.messagesEl      = document.getElementById('vc-messages')!;
    this.inputEl         = document.getElementById('vc-input') as HTMLTextAreaElement;
    this.sendBtn         = document.getElementById('vc-send') as HTMLButtonElement;
    this.emergencyBanner = document.getElementById('vc-emergency')!;
    this.mapOverlay      = document.getElementById('vc-map-overlay')!;
    this.onResponse      = onResponse;
  }

  async send(question?: string): Promise<void> {
    const q = (question ?? this.inputEl.value).trim();
    if (!q) return;

    this.inputEl.value = '';
    this.autoResize();
    this.sendBtn.disabled = true;

    const suggestionsEl = document.getElementById('vc-suggestions');
    if (suggestionsEl) suggestionsEl.style.display = 'none';

    this.appendUserMessage(q);
    const typing = this.addTyping();

    try {
      const res = await fetch('/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ question: q }),
      });

      if (!res.ok) {
        const err = await res.json() as { detail?: string };
        throw new Error(err.detail ?? 'Server error');
      }

      const data = await res.json() as ChatResponse;
      typing.remove();

      this.emergencyBanner.style.display = data.is_emergency ? 'flex' : 'none';
      this.appendAgentMessage(data);

      if (data.result_count > 0) {
        this.mapOverlay.textContent = `${data.result_count} facilities found`;
        this.mapOverlay.classList.add('show');
        setTimeout(() => this.mapOverlay.classList.remove('show'), 4000);
      }

      this.onResponse(data);
    } catch (err: unknown) {
      typing.remove();
      const msg = err instanceof Error ? err.message : 'Unknown error';
      this.appendUserMessage(`⚠ ${msg}`, true);
    } finally {
      this.sendBtn.disabled = false;
      this.inputEl.focus();
    }
  }

  autoResize(): void {
    this.inputEl.style.height = '42px';
    this.inputEl.style.height = Math.min(this.inputEl.scrollHeight, 110) + 'px';
  }

  private appendUserMessage(text: string, isError = false): void {
    const wrap = document.createElement('div');
    wrap.className = `vc-msg vc-msg--${isError ? 'agent' : 'user'}`;

    const bubble = document.createElement('div');
    bubble.className = 'vc-bubble';
    bubble.textContent = text;
    wrap.appendChild(bubble);

    const meta = document.createElement('div');
    meta.className = 'vc-msg-meta';
    const time = document.createElement('span');
    time.className = 'vc-msg-time';
    time.textContent = now();
    meta.appendChild(time);
    wrap.appendChild(meta);

    this.messagesEl.appendChild(wrap);
    this.messagesEl.scrollTop = this.messagesEl.scrollHeight;
  }

  private appendAgentMessage(data: ChatResponse): void {
    const wrap = document.createElement('div');
    wrap.className = 'vc-msg vc-msg--agent';

    const bubble = document.createElement('div');
    bubble.className = 'vc-bubble vc-bubble--md' + (data.is_emergency ? ' vc-bubble--emergency' : '');
    bubble.innerHTML = marked.parse(data.answer) as string;
    wrap.appendChild(bubble);

    const meta = document.createElement('div');
    meta.className = 'vc-msg-meta';

    const time = document.createElement('span');
    time.className = 'vc-msg-time';
    time.textContent = now();
    meta.appendChild(time);

    if (data.result_count > 0) {
      const pill = document.createElement('span');
      pill.className = 'vc-pill';
      pill.textContent = `${data.result_count} facilities`;
      meta.appendChild(pill);
    }

    wrap.appendChild(meta);

    // Validation strip
    if (data.trust_score != null) {
      const color = trustColor(data.trust_score);
      const strip = document.createElement('div');
      strip.className = 'vc-validation';
      strip.innerHTML = `
        <span class="vc-val-icon" style="color:${color}">🛡</span>
        <span class="vc-val-text">
          Validated by <b>Llama 3.1 405B</b> · Trust score:
          <span style="color:${color};font-weight:700">${data.trust_score}%</span>
        </span>
        ${data.validation_note ? `<span class="vc-val-note">"${data.validation_note}"</span>` : ''}
      `;
      wrap.appendChild(strip);
    }
    this.messagesEl.appendChild(wrap);
    this.messagesEl.scrollTop = this.messagesEl.scrollHeight;
  }

  private addTyping(): HTMLElement {
    const wrap = document.createElement('div');
    wrap.className = 'vc-msg vc-msg--agent vc-typing';
    wrap.innerHTML = `
      <div class="vc-bubble">
        <span class="vc-dots"><span></span><span></span><span></span></span>
      </div>`;
    this.messagesEl.appendChild(wrap);
    this.messagesEl.scrollTop = this.messagesEl.scrollHeight;
    return wrap;
  }
}

function now(): string {
  return new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}
