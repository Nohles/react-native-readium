const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const root = path.resolve(__dirname, '../..');
const escapeRegExp = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const config = getDefaultConfig(__dirname);

config.watchFolders = [root];
config.resolver.nodeModulesPaths = [
  path.resolve(__dirname, 'node_modules'),
  path.resolve(root, 'node_modules'),
];
config.resolver.extraNodeModules = {
  react: path.resolve(__dirname, 'node_modules/react'),
  'react-native': path.resolve(__dirname, 'node_modules/react-native'),
  'react-native-gesture-handler': path.resolve(__dirname, 'node_modules/react-native-gesture-handler'),
  'react-native-reanimated': path.resolve(__dirname, 'node_modules/react-native-reanimated'),
  'react-native-safe-area-context': path.resolve(__dirname, 'node_modules/react-native-safe-area-context'),
  'react-native-screens': path.resolve(__dirname, 'node_modules/react-native-screens'),
  'react-native-worklets': path.resolve(__dirname, 'node_modules/react-native-worklets'),
};
config.resolver.blockList = [
  new RegExp(`^${escapeRegExp(path.resolve(root, 'node_modules/react'))}(?:/|$)`),
  new RegExp(`^${escapeRegExp(path.resolve(root, 'node_modules/react-native'))}(?:/|$)`),
  new RegExp(`^${escapeRegExp(path.resolve(root, 'node_modules/react-native-gesture-handler'))}(?:/|$)`),
  new RegExp(`^${escapeRegExp(path.resolve(root, 'node_modules/react-native-reanimated'))}(?:/|$)`),
  new RegExp(`^${escapeRegExp(path.resolve(root, 'node_modules/react-native-safe-area-context'))}(?:/|$)`),
  new RegExp(`^${escapeRegExp(path.resolve(root, 'node_modules/react-native-screens'))}(?:/|$)`),
  new RegExp(`^${escapeRegExp(path.resolve(root, 'node_modules/react-native-worklets'))}(?:/|$)`),
];
config.resolver.assetExts.push('m4b', 'cbz');

module.exports = config;
