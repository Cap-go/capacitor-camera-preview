const ionic = require('@ionic/eslint-config/recommended');

module.exports = [
  {
    ignores: ['build', 'dist', 'example-app', 'docs', 'www', 'lib', 'examples', 'android', 'ios', 'scripts'],
  },
  ...ionic,
];
