// The player's record, kept by the game (a client KVP on their machine, per server): their
// rating, games, rules, sound settings and the game in progress, so reopening picks it up again.

import type { Ruleset } from '@smashandclash/sdk';
import { post } from './bridge';
import { START_RATING } from './moves';

export type GameMode = 'house' | 'quick' | 'room' | 'friend' | 'table';

export interface ActiveGame {
  id: string;
  token: string;
  mode: GameMode;
  /** A house game's strength, which the rating moves against. */
  strength?: number;
}

export interface Profile {
  rating: number;
  played: number;
  won: number;
  ruleset: Ruleset;
  active: ActiveGame | null;
  music: number;
  effects: number;
  voices: boolean;
  reduceMotion: boolean;
}

export const DEFAULT_PROFILE: Profile = {
  rating: START_RATING,
  played: 0,
  won: 0,
  ruleset: 'mutators',
  active: null,
  music: 0.35,
  effects: 0.8,
  voices: true,
  reduceMotion: false,
};

export function readProfile(text: string | null | undefined): Profile {
  if (!text) return { ...DEFAULT_PROFILE };
  try {
    const p = JSON.parse(text) as Partial<Profile>;
    const out = { ...DEFAULT_PROFILE, ...p };
    if (out.ruleset !== 'classic') out.ruleset = 'mutators';
    if (!Number.isFinite(out.rating)) out.rating = START_RATING;
    out.music = clamp01(out.music);
    out.effects = clamp01(out.effects);
    return out;
  } catch {
    return { ...DEFAULT_PROFILE };
  }
}

const clamp01 = (n: unknown): number => (typeof n === 'number' && Number.isFinite(n) ? Math.max(0, Math.min(1, n)) : 0.5);

export function saveProfile(p: Profile): void {
  void post('saveProfile', { profile: JSON.stringify(p) }).catch(() => {});
}
