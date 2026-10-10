// The game's own music, effects, announcer and character voices, from the SDK's kit
// (the kit the resource ships, kit/kit.json). Music follows the screen; voices play one at a time, the most important
// line winning (a capture over a hurt line over a place line).

import type { Assets } from '@smashandclash/sdk';

export type Mood = 'menu' | 'matchmaking' | 'battle' | 'victory' | 'defeat';
type Kit = NonNullable<Assets['audio']>;
type VoiceKind = 'place' | 'capture' | 'chain' | 'blocked' | 'hurt' | 'win';

const VOICE_RANK: Record<VoiceKind, number> = { place: 1, blocked: 1, hurt: 2, chain: 3, capture: 3, win: 4 };
const LOOPS: Record<Mood, boolean> = { menu: true, matchmaking: true, battle: true, victory: false, defeat: false };

const pick = <T>(x: T | T[] | undefined): T | undefined => (Array.isArray(x) ? x[Math.floor(Math.random() * x.length)] : x);

export interface Levels {
  music: number;
  effects: number;
  voices: boolean;
}

export class Sound {
  private kit: Kit | null = null;
  private track: HTMLAudioElement | null = null;
  private mood: Mood | null = null;
  private wanted: Mood | null = null;
  private voice: { el: HTMLAudioElement; rank: number } | null = null;
  private muted = false;

  constructor(private levels: () => Levels) {
    // a browser may refuse sound until the first click: start the music then
    const unlock = () => {
      if (this.wanted && (!this.track || this.track.paused)) this.play(this.wanted, true);
    };
    window.addEventListener('pointerdown', unlock);
    window.addEventListener('keydown', unlock);
  }

  setKit(kit: Kit | null): void {
    this.kit = kit;
    if (this.wanted) this.play(this.wanted, true);
  }

  /** The screen's music. The same mood keeps its track playing. */
  play(mood: Mood | null, restart = false): void {
    this.wanted = mood;
    if (!restart && mood === this.mood && this.track && !this.track.paused) return;
    this.stopTrack();
    this.mood = mood;
    if (!mood || !this.kit || this.muted) return;
    const url = pick(this.kit.music[mood]);
    if (!url) return;
    const el = new Audio(url);
    el.loop = LOOPS[mood];
    el.volume = this.levels().music;
    this.track = el;
    el.play().catch(() => {});
  }

  /** Silence while the tablet is put away; back on when it comes out. */
  setMuted(muted: boolean): void {
    this.muted = muted;
    if (muted) {
      this.stopTrack();
      this.voice?.el.pause();
      this.voice = null;
    } else if (this.wanted) this.play(this.wanted, true);
  }

  /** Volume changes take effect on what is playing. */
  refresh(): void {
    if (this.track) this.track.volume = this.levels().music;
  }

  sfx(name: string): void {
    if (this.muted || !this.kit) return;
    const url = pick(this.kit.sfx[name]);
    if (url) this.shot(url, this.levels().effects);
  }

  announcer(name: string): void {
    if (this.muted || !this.kit) return;
    const url = pick(this.kit.announcer[name]);
    if (url) this.shot(url, this.levels().effects);
  }

  /** A character's line. `n` picks a capture or chain line by count. */
  line(cardId: number, kind: VoiceKind, n?: number): void {
    if (this.muted || !this.kit || !this.levels().voices) return;
    const lines = this.kit.voices[String(cardId)] as Record<string, string[] | Record<string, string[]>> | undefined;
    const set = lines?.[kind];
    if (!set) return;
    const list = Array.isArray(set) ? set : set[String(Math.max(1, Math.min(4, n ?? 1)))] ?? set['2'];
    const url = pick(list);
    if (!url) return;
    const rank = VOICE_RANK[kind];
    if (this.voice && !this.voice.el.ended && !this.voice.el.paused && this.voice.rank > rank) return;
    this.voice?.el.pause();
    const el = this.shot(url, Math.min(1, this.levels().effects * 1.1));
    this.voice = { el, rank };
  }

  private shot(url: string, volume: number): HTMLAudioElement {
    const el = new Audio(url);
    el.volume = volume;
    el.play().catch(() => {});
    return el;
  }

  private stopTrack(): void {
    if (!this.track) return;
    const el = this.track;
    this.track = null;
    // a short fade, so a screen change never clicks
    const start = el.volume;
    const t0 = performance.now();
    const step = () => {
      const k = Math.min(1, (performance.now() - t0) / 350);
      el.volume = start * (1 - k);
      if (k < 1) requestAnimationFrame(step);
      else el.pause();
    };
    requestAnimationFrame(step);
  }
}
