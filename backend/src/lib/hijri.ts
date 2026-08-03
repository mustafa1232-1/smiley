// Tabular (arithmetic) Islamic calendar conversion. This is an APPROXIMATION:
// the civil tabular calendar can differ from the officially announced,
// moon-sighting-based dates by 1-2 days, and the actual date varies by country.
// Callers must therefore allow a manual override for announced Eid dates.

export type GregorianDate = { year: number; month: number; day: number };
export type HijriDate = { year: number; month: number; day: number };

const ISLAMIC_EPOCH_JDN = 1948440; // JDN of 1 Muharram 1 AH (civil/tabular)

export function gregorianToJDN(year: number, month: number, day: number): number {
  const a = Math.floor((14 - month) / 12);
  const y = year + 4800 - a;
  const m = month + 12 * a - 3;
  return (
    day +
    Math.floor((153 * m + 2) / 5) +
    365 * y +
    Math.floor(y / 4) -
    Math.floor(y / 100) +
    Math.floor(y / 400) -
    32045
  );
}

export function jdnToGregorian(jdn: number): GregorianDate {
  const a = jdn + 32044;
  const b = Math.floor((4 * a + 3) / 146097);
  const c = a - Math.floor((146097 * b) / 4);
  const d = Math.floor((4 * c + 3) / 1461);
  const e = c - Math.floor((1461 * d) / 4);
  const m = Math.floor((5 * e + 2) / 153);
  return {
    day: e - Math.floor((153 * m + 2) / 5) + 1,
    month: m + 3 - 12 * Math.floor(m / 10),
    year: 100 * b + d - 4800 + Math.floor(m / 10)
  };
}

export function islamicToJDN(year: number, month: number, day: number): number {
  return (
    day +
    Math.ceil(29.5 * (month - 1)) +
    (year - 1) * 354 +
    Math.floor((3 + 11 * year) / 30) +
    ISLAMIC_EPOCH_JDN -
    1
  );
}

export function jdnToIslamic(jdn: number): HijriDate {
  let year = Math.floor((30 * (jdn - ISLAMIC_EPOCH_JDN) + 10646) / 10631);

  // Correct any off-by-one from the linear year estimate.
  if (jdn < islamicToJDN(year, 1, 1)) {
    year -= 1;
  } else if (jdn >= islamicToJDN(year + 1, 1, 1)) {
    year += 1;
  }

  let month = 1;
  while (month < 12 && islamicToJDN(year, month + 1, 1) <= jdn) {
    month += 1;
  }
  const day = jdn - islamicToJDN(year, month, 1) + 1;
  return { year, month, day };
}

export function hijriToGregorian(year: number, month: number, day: number): GregorianDate {
  return jdnToGregorian(islamicToJDN(year, month, day));
}

export function gregorianToHijri(year: number, month: number, day: number): HijriDate {
  return jdnToIslamic(gregorianToJDN(year, month, day));
}

export type EidOccurrence = {
  key: 'eid_al_fitr' | 'eid_al_adha';
  hijriYear: number;
  date: GregorianDate;
  approximate: true;
};

// Eid al-Fitr = 1 Shawwal (month 10); Eid al-Adha = 10 Dhu al-Hijjah (month 12).
const EID_DEFS: Array<{ key: EidOccurrence['key']; month: number; day: number }> = [
  { key: 'eid_al_fitr', month: 10, day: 1 },
  { key: 'eid_al_adha', month: 12, day: 10 }
];

/**
 * Returns the (approximate, tabular) Eid dates that fall within the given
 * Gregorian year. Because the Hijri year drifts ~11 days earlier each year, a
 * Gregorian year can contain Eids from two different Hijri years.
 */
export function eidsInGregorianYear(gregorianYear: number): EidOccurrence[] {
  const startHijriYear = gregorianToHijri(gregorianYear, 1, 1).year;
  const occurrences: EidOccurrence[] = [];

  for (const hijriYear of [startHijriYear, startHijriYear + 1]) {
    for (const def of EID_DEFS) {
      const date = hijriToGregorian(hijriYear, def.month, def.day);
      if (date.year === gregorianYear) {
        occurrences.push({ key: def.key, hijriYear, date, approximate: true });
      }
    }
  }

  occurrences.sort((a, b) =>
    a.date.month === b.date.month ? a.date.day - b.date.day : a.date.month - b.date.month
  );
  return occurrences;
}
