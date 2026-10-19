const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);
config.resolver.assetExts.push('epub', 'cbz', 'm4b');

module.exports = config;
