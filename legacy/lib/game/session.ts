/**
 * Session management - handles user identity persistence
 */

const STORAGE_KEY = 'slippington_user_id';

export function getUserId(): string {
  if (typeof window === 'undefined') {
    return `server_${Date.now()}`;
  }

  const stored = localStorage.getItem(STORAGE_KEY);
  if (stored) return stored;

  const newId = `user_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  localStorage.setItem(STORAGE_KEY, newId);
  return newId;
}

export function clearSession(): void {
  if (typeof window !== 'undefined') {
    localStorage.removeItem(STORAGE_KEY);
  }
}

