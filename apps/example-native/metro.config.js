const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');
const path = require('path');

const root = path.resolve(__dirname, '../..');
const escapeRegExp = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * Metro configuration for monorepo
 * https://reactnative.dev/docs/metro
 *
 * @type {import('@react-native/metro-config').MetroConfig}
 */
// Dedicated port so we don't reuse another project's Metro on 8081 (e.g. Reader/Expo).
const METRO_PORT = 8191;

const config = {
  projectRoot: __dirname,
  watchFolders: [root],
  resolver: {
    nodeModulesPaths: [
      path.resolve(__dirname, 'node_modules'),
      path.resolve(root, 'node_modules'),
    ],
    extraNodeModules: {
      react: path.resolve(__dirname, 'node_modules/react'),
      'react-native': path.resolve(__dirname, 'node_modules/react-native'),
      'react-native-gesture-handler': path.resolve(__dirname, 'node_modules/react-native-gesture-handler'),
      'react-native-reanimated': path.resolve(__dirname, 'node_modules/react-native-reanimated'),
      'react-native-safe-area-context': path.resolve(__dirname, 'node_modules/react-native-safe-area-context'),
      'react-native-screens': path.resolve(__dirname, 'node_modules/react-native-screens'),
      'react-native-worklets': path.resolve(__dirname, 'node_modules/react-native-worklets'),
    },
    blockList: [
      new RegExp(`^${escapeRegExp(path.resolve(root, 'node_modules/react'))}(?:/|$)`),
      new RegExp(`^${escapeRegExp(path.resolve(root, 'node_modules/react-native'))}(?:/|$)`),
      new RegExp(`^${escapeRegExp(path.resolve(root, 'node_modules/react-native-gesture-handler'))}(?:/|$)`),
      new RegExp(`^${escapeRegExp(path.resolve(root, 'node_modules/react-native-reanimated'))}(?:/|$)`),
      new RegExp(`^${escapeRegExp(path.resolve(root, 'node_modules/react-native-safe-area-context'))}(?:/|$)`),
      new RegExp(`^${escapeRegExp(path.resolve(root, 'node_modules/react-native-screens'))}(?:/|$)`),
      new RegExp(`^${escapeRegExp(path.resolve(root, 'node_modules/react-native-worklets'))}(?:/|$)`),
    ],
  },
  server: {
    port: METRO_PORT,
  },

  transformer: {
    getTransformOptions: async () => ({
      transform: {
        experimentalImportSupport: false,
        inlineRequires: true,
      },
    }),
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
