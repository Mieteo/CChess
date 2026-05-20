module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
    "plugin:import/errors",
    "plugin:import/warnings",
    "plugin:import/typescript",
    "google",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["tsconfig.json"],
    sourceType: "module",
  },
  ignorePatterns: [
    "/lib/**/*",
    "/generated/**/*",
    ".eslintrc.js",
  ],
  plugins: [
    "@typescript-eslint",
    "import",
  ],
  rules: {
    "quotes": ["error", "single", { "avoidEscape": true }],
    "import/no-unresolved": 0,
    "indent": ["error", 2],
    "max-len": ["warn", { "code": 120 }],
    "object-curly-spacing": ["error", "always"],
    "require-jsdoc": "off",
    "valid-jsdoc": "off",
    "@typescript-eslint/no-explicit-any": "warn",
  },
};
