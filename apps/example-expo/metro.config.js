const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const root = path.resolve(__dirname, '../..');
const config = getDefaultConfig(__dirname);

config.watchFolders = [root];
config.resolver.assetExts.push('m4b', 'cbz');

module.exports = config;
