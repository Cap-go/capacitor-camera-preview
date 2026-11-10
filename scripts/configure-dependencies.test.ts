import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const root = resolve(import.meta.dir, '..');
const manifests = ['Package.swift', 'CapgoCameraPreview.podspec'];
const flag = 'CAPGO_CAMERA_PREVIEW_DISABLE_CALLKIT';
let fixture: string;
let originals: string[];

function contents() {
  return manifests.map((file) => readFileSync(join(fixture, file), 'utf8'));
}

function sync(config: unknown, platform = 'ios') {
  const env = { ...process.env, CAPACITOR_PLATFORM_NAME: platform };
  delete env.CAPACITOR_CONFIG;
  if (config !== undefined) env.CAPACITOR_CONFIG = typeof config === 'string' ? config : JSON.stringify(config);
  return spawnSync(process.execPath, [join(fixture, 'scripts/configure-dependencies.cjs')], {
    // The hook must locate its own package even when invoked from an app directory.
    cwd: tmpdir(),
    env,
    encoding: 'utf8',
  });
}

beforeEach(() => {
  fixture = mkdtempSync(join(tmpdir(), 'camera-callkit-'));
  mkdirSync(join(fixture, 'scripts'));
  for (const file of [...manifests, 'scripts/configure-dependencies.cjs']) {
    copyFileSync(join(root, file), join(fixture, file));
  }
  originals = contents();
});

afterEach(() => rmSync(fixture, { recursive: true, force: true }));

describe('CallKit sync configuration', () => {
  test('ships with CallKit disabled and keeps it disabled when the option is omitted', () => {
    expect(originals.every((content) => content.includes(flag))).toBe(true);
    expect(sync({}).status).toBe(0);
    expect(contents()).toEqual(originals);
    expect(sync({ plugins: { CameraPreview: {} } }).status).toBe(0);
    expect(contents()).toEqual(originals);
    expect(contents().every((content) => content.includes(flag))).toBe(true);
  });

  test('enables both package managers only on opt-in, is idempotent, and restores defaults', () => {
    const config = { plugins: { CameraPreview: { iosCallKit: true } } };
    expect(sync(config).status).toBe(0);
    const enabled = contents();
    expect(enabled.every((content) => !content.includes(flag))).toBe(true);
    expect(sync(config).status).toBe(0);
    expect(contents()).toEqual(enabled);
    expect(sync({ plugins: { CameraPreview: { iosCallKit: false } } }).status).toBe(0);
    expect(contents()).toEqual(originals);
    expect(sync(config).status).toBe(0);
    expect(sync({}).status).toBe(0);
    expect(contents()).toEqual(originals);
    expect(sync(config).status).toBe(0);
    expect(sync({ plugins: { CameraPreview: {} } }).status).toBe(0);
    expect(contents()).toEqual(originals);
  });

  test.each(['android', 'web'])('leaves iOS configuration unchanged for %s', (platform) => {
    expect(sync({ plugins: { CameraPreview: { iosCallKit: true } } }).status).toBe(0);
    const enabled = contents();
    expect(sync({}, platform).status).toBe(0);
    expect(contents()).toEqual(enabled);
  });

  test.each([undefined, '{invalid', { plugins: { CameraPreview: { iosCallKit: 'false' } } }])(
    'rejects missing or invalid configuration without changing native settings: %p',
    (config) => {
      expect(sync(config).status).not.toBe(0);
      expect(contents()).toEqual(originals);
    },
  );

  test('fails before changing either manifest if a marker is missing', () => {
    const podspec = join(fixture, manifests[1]);
    writeFileSync(podspec, readFileSync(podspec, 'utf8').replace('CameraPreview CallKit', 'Missing marker'));
    const before = contents();
    const result = sync({ plugins: { CameraPreview: { iosCallKit: false } } });
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain('Missing CallKit configuration marker');
    expect(contents()).toEqual(before);
  });
});
