import { describe, expect, it } from 'vitest';

import {
  currentMinutesInTimeZone,
  isWithinQuietWindow,
  minutesFromClock
} from './quiet-hours.js';

describe('quiet hours', () => {
  it('parses clock strings to minutes since midnight', () => {
    expect(minutesFromClock('00:00')).toBe(0);
    expect(minutesFromClock('07:30')).toBe(450);
    expect(minutesFromClock('23:59')).toBe(1439);
  });

  it('matches a same-day window', () => {
    // 09:00 -> 17:00
    expect(isWithinQuietWindow(minutesFromClock('12:00'), '09:00', '17:00')).toBe(true);
    expect(isWithinQuietWindow(minutesFromClock('08:59'), '09:00', '17:00')).toBe(false);
    expect(isWithinQuietWindow(minutesFromClock('17:00'), '09:00', '17:00')).toBe(false);
  });

  it('matches an overnight window that wraps past midnight', () => {
    // 22:00 -> 07:00
    expect(isWithinQuietWindow(minutesFromClock('23:30'), '22:00', '07:00')).toBe(true);
    expect(isWithinQuietWindow(minutesFromClock('03:00'), '22:00', '07:00')).toBe(true);
    expect(isWithinQuietWindow(minutesFromClock('07:00'), '22:00', '07:00')).toBe(false);
    expect(isWithinQuietWindow(minutesFromClock('12:00'), '22:00', '07:00')).toBe(false);
  });

  it('treats an empty window as never quiet', () => {
    expect(isWithinQuietWindow(600, '10:00', '10:00')).toBe(false);
  });

  it('computes local minutes using the timezone offset', () => {
    const instant = new Date('2026-08-03T00:00:00.000Z');
    const utc = currentMinutesInTimeZone('UTC', instant);
    const plus3 = currentMinutesInTimeZone('Etc/GMT-3', instant); // UTC+3
    expect(utc).toBe(0);
    expect(plus3).toBe(180);
  });

  it('falls back to UTC for an invalid timezone', () => {
    const instant = new Date('2026-08-03T05:15:00.000Z');
    expect(currentMinutesInTimeZone('Not/AZone', instant)).toBe(5 * 60 + 15);
  });
});
