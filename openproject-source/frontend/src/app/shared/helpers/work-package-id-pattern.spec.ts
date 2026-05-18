import { formatWorkPackageId } from './work-package-id-pattern';

describe('formatWorkPackageId', () => {
  it('returns semantic identifiers as-is (no prefix)', () => {
    expect(formatWorkPackageId('PROJ-42')).toBe('PROJ-42');
  });

  it('prefixes numeric identifiers with #', () => {
    expect(formatWorkPackageId('42')).toBe('#42');
  });

  it('returns empty string for empty input', () => {
    expect(formatWorkPackageId('')).toBe('');
  });
});
