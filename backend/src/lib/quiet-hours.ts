// Quiet-hours evaluation. Kept as pure, timezone-aware helpers so notification
// suppression matches the user's local clock rather than server UTC.

export function minutesFromClock(value: string): number {
  const [hours, minutes] = value.split(':').map(Number);
  return ((hours % 24) * 60 + (minutes % 60) + 1440) % 1440;
}

/**
 * True when `currentMinutes` (minutes since local midnight) falls inside the
 * [quietFrom, quietTo) window, correctly handling windows that wrap past
 * midnight (e.g. 22:00 -> 07:00).
 */
export function isWithinQuietWindow(
  currentMinutes: number,
  quietFrom: string,
  quietTo: string
): boolean {
  const from = minutesFromClock(quietFrom);
  const to = minutesFromClock(quietTo);
  if (from === to) return false;
  if (from < to) return currentMinutes >= from && currentMinutes < to;
  return currentMinutes >= from || currentMinutes < to;
}

/** Minutes since midnight in the given IANA timezone (falls back to UTC). */
export function currentMinutesInTimeZone(
  timeZone: string | undefined,
  now: Date = new Date()
): number {
  try {
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: timeZone && timeZone.trim() ? timeZone : 'UTC',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    });
    const parts = formatter.formatToParts(now);
    const hour = Number(parts.find((part) => part.type === 'hour')?.value ?? '0');
    const minute = Number(parts.find((part) => part.type === 'minute')?.value ?? '0');
    return (hour % 24) * 60 + minute;
  } catch {
    // Invalid/unknown timezone: fall back to UTC rather than throwing.
    return now.getUTCHours() * 60 + now.getUTCMinutes();
  }
}

export function isNowInsideQuietHours(
  quietFrom: string,
  quietTo: string,
  timeZone?: string
): boolean {
  return isWithinQuietWindow(currentMinutesInTimeZone(timeZone), quietFrom, quietTo);
}
