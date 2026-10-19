const path = require('path');

module.exports = {
  dependencies: {
    // Resolve the workspace alias to its real path for Android resource tasks.
    'react-native-readium': {
      root: path.resolve(__dirname, '../..'),
    },
  },
};
