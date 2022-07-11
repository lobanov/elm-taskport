const path = require('path');

module.exports = {
  entry: './js/taskport.js',
  mode: 'production',
  output: {
    filename: 'taskport.min.js',
    path: path.resolve(__dirname, 'dist'),
  },
};
