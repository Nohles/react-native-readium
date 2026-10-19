/** @jest-environment node */
const withReadium = require('../withReadium');

async function runAndroidMod(name, modResults, options) {
  const config = withReadium(
    { name: 'Readium test', slug: 'readium-test' },
    options
  );
  const result = await config.mods.android[name]({
    modRequest: { platform: 'android' },
    modResults,
  });
  return result.modResults;
}

test('keeps the default Android network policy', async () => {
  const manifest = { $: {}, application: [{ $: {} }] };
  const result = await runAndroidMod('manifest', { manifest });
  expect(result.manifest).toEqual(manifest);
  expect(result.manifest.application[0].$).toEqual({});
});

test('enables sample HTTP URLs through plugin options and preserves manifest removals', async () => {
  const options = { android: { usesCleartextTraffic: true } };
  const manifest = {
    $: {},
    application: [{ $: { 'tools:remove': 'android:allowBackup' } }],
  };
  const result = await runAndroidMod('manifest', { manifest }, options);
  expect(result.manifest.application[0].$).toEqual({
    'android:usesCleartextTraffic': 'true',
    'tools:remove': 'android:allowBackup,android:networkSecurityConfig',
  });
  expect(await runAndroidMod('manifest', result, options)).toEqual(result);
});

test.each([
  "classpath('org.jetbrains.kotlin:kotlin-gradle-plugin')",
  'classpath(kotlinVersion ? "org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion" : "org.jetbrains.kotlin:kotlin-gradle-plugin")',
])('pins the Kotlin dependency in %s', async (dependency) => {
  const result = await runAndroidMod('projectBuildGradle', {
    language: 'groovy',
    contents: `buildscript { dependencies { ${dependency} } }`,
  });
  expect(result.contents).toContain(
    "classpath('org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.10')"
  );
  expect(await runAndroidMod('projectBuildGradle', result)).toEqual(result);
});

test('adds desugaring and updates an existing generated dependency', async () => {
  const result = await runAndroidMod('appBuildGradle', {
    language: 'groovy',
    contents: 'android {\n}\n\ndependencies {\n}\n',
  });
  expect(result.contents).toContain('coreLibraryDesugaringEnabled true');
  expect(result.contents).toContain('desugar_jdk_libs:2.1.5');
  expect(await runAndroidMod('appBuildGradle', result)).toEqual(result);
  const stale = {
    ...result,
    contents: result.contents.replace('2.1.5', '2.1.2'),
  };
  expect(await runAndroidMod('appBuildGradle', stale)).toEqual(result);
});
