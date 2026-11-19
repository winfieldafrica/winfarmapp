import js from '@eslint/js';
import prettier from 'eslint-config-prettier';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    ignores: [
      '**/node_modules/**',
      '**/dist/**',
      '**/.next/**',
      '**/.expo/**',
      '**/next-env.d.ts',
      'database/**',
      'docs/**',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.strict,
  {
    languageOptions: { globals: { ...globals.node } },
    rules: {
      '@typescript-eslint/consistent-type-imports': ['error', { fixStyle: 'inline-type-imports' }],
    },
  },
  {
    files: ['apps/api/**/*.ts'],
    rules: { '@typescript-eslint/no-extraneous-class': ['error', { allowWithDecorator: true }] },
  },
  {
    files: ['apps/console/**/*.{ts,tsx}', 'apps/mobile/**/*.{ts,tsx}'],
    languageOptions: { globals: { ...globals.browser } },
  },
  {
    // Master prompt rule 5: packages/rules is pure. No I/O, no clock, no randomness.
    files: ['packages/rules/src/**/*.ts'],
    languageOptions: { globals: {} },
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: [
                'node:*',
                'fs',
                'path',
                'http',
                'https',
                'net',
                'child_process',
                'pg',
                'kysely',
                'ioredis',
                'bullmq',
              ],
              message: 'packages/rules must be pure: no I/O.',
            },
          ],
        },
      ],
      'no-restricted-globals': [
        'error',
        { name: 'process', message: 'packages/rules must be pure.' },
        { name: 'fetch', message: 'packages/rules must be pure: no I/O.' },
        { name: 'setTimeout', message: 'packages/rules must be pure: no timers.' },
        { name: 'setInterval', message: 'packages/rules must be pure: no timers.' },
        { name: 'crypto', message: 'packages/rules must be pure: no randomness.' },
      ],
      'no-restricted-syntax': [
        'error',
        {
          selector: "CallExpression[callee.object.name='Date'][callee.property.name='now']",
          message: 'Pass time in; never read the clock.',
        },
        {
          selector: "NewExpression[callee.name='Date'][arguments.length=0]",
          message: 'Pass time in; never read the clock.',
        },
        {
          selector: "CallExpression[callee.object.name='Math'][callee.property.name='random']",
          message: 'No randomness in packages/rules.',
        },
        {
          selector: "CallExpression[callee.object.name='performance'][callee.property.name='now']",
          message: 'Pass time in; never read the clock.',
        },
      ],
    },
  },
  {
    files: ['packages/rules/src/**/*.test.ts'],
    rules: { 'no-restricted-imports': 'off' },
  },
  prettier,
);
