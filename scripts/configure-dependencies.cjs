#!/usr/bin/env node

// Like Social Login, configure native compilation before Capacitor sync resolves dependencies.
const fs = require('node:fs');
const path = require('node:path');

function main() {
  const platform = process.env.CAPACITOR_PLATFORM_NAME;
  if (platform && platform !== 'ios') return;

  if (!process.env.CAPACITOR_CONFIG) {
    throw new Error('CAPACITOR_CONFIG is missing. Run this hook through cap sync ios.');
  }
  const config = JSON.parse(process.env.CAPACITOR_CONFIG);
  const option = config.plugins?.CameraPreview?.iosCallKit;
  if (option !== undefined && typeof option !== 'boolean') {
    throw new Error('CameraPreview.iosCallKit must be a boolean.');
  }
  const disabled = option !== true;
  const flag = 'CAPGO_CAMERA_PREVIEW_DISABLE_CALLKIT';
  const root = path.resolve(__dirname, '..');
  const replacements = [
    {
      file: 'Package.swift',
      pattern: /^([ \t]*)swiftSettings: \[.*\] \/\/ CameraPreview CallKit \(configured by sync hook\)$/m,
      line: `swiftSettings: [${disabled ? `.define("${flag}")` : ''}] // CameraPreview CallKit (configured by sync hook)`,
    },
    {
      file: 'CapgoCameraPreview.podspec',
      pattern: /^([ \t]*)s\.pod_target_xcconfig = .* # CameraPreview CallKit \(configured by sync hook\)$/m,
      line: `s.pod_target_xcconfig = { 'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited)${disabled ? ` ${flag}` : ''}' } # CameraPreview CallKit (configured by sync hook)`,
    },
  ];

  // Validate both manifests before changing either one; never silently leave CallKit enabled.
  const updates = replacements.map(({ file, pattern, line }) => {
    const target = path.join(root, file);
    const current = fs.readFileSync(target, 'utf8');
    if (!pattern.test(current)) throw new Error(`Missing CallKit configuration marker in ${file}.`);
    return { target, current, updated: current.replace(pattern, (_, indent) => indent + line) };
  });
  for (const { target, current, updated } of updates) {
    if (current !== updated) fs.writeFileSync(target, updated);
  }
  console.log(`[CameraPreview] iOS CallKit ${disabled ? 'excluded from' : 'included in'} native compilation.`);
}

try {
  main();
} catch (error) {
  console.error(`[CameraPreview] ${error.message}`);
  process.exitCode = 1;
}
