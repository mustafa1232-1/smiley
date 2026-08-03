import { describe, expect, it } from 'vitest';

import {
  eidsInGregorianYear,
  gregorianToHijri,
  gregorianToJDN,
  islamicToJDN,
  jdnToGregorian,
  jdnToIslamic
} from './hijri.js';

describe('hijri calendar (tabular)', () => {
  it('anchors the Islamic epoch', () => {
    expect(islamicToJDN(1, 1, 1)).toBe(1948440);
  });

  it('round-trips Gregorian <-> JDN', () => {
    for (const date of [
      { year: 2000, month: 1, day: 1 },
      { year: 2026, month: 8, day: 3 },
      { year: 1999, month: 12, day: 31 }
    ]) {
      const jdn = gregorianToJDN(date.year, date.month, date.day);
      expect(jdnToGregorian(jdn)).toEqual(date);
    }
  });

  it('round-trips Hijri <-> JDN', () => {
    for (const date of [
      { year: 1447, month: 10, day: 1 },
      { year: 1447, month: 12, day: 10 },
      { year: 1400, month: 1, day: 1 }
    ]) {
      const jdn = islamicToJDN(date.year, date.month, date.day);
      expect(jdnToIslamic(jdn)).toEqual(date);
    }
  });

  it('places 1 Jan 2026 inside Hijri year 1447', () => {
    expect(gregorianToHijri(2026, 1, 1).year).toBe(1447);
  });

  it('computes both 2026 Eids in the expected months', () => {
    const eids = eidsInGregorianYear(2026);
    expect(eids.map((e) => e.key)).toEqual(['eid_al_fitr', 'eid_al_adha']);

    const fitr = eids[0];
    const adha = eids[1];
    expect(fitr.date.year).toBe(2026);
    expect(fitr.date.month).toBe(3); // spring 2026 (approximate)
    expect(adha.date.month).toBe(5);

    // 1 Shawwal -> 10 Dhu al-Hijjah is always 68 tabular days apart.
    const gap =
      gregorianToJDN(adha.date.year, adha.date.month, adha.date.day) -
      gregorianToJDN(fitr.date.year, fitr.date.month, fitr.date.day);
    expect(gap).toBe(68);

    expect(fitr.approximate).toBe(true);
  });
});
