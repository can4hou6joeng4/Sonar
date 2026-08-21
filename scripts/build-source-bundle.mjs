import { build } from 'esbuild'
import { mkdir } from 'node:fs/promises'

await mkdir('Sonar/Resources', { recursive: true })

await build({
  entryPoints: ['scripts/source-entry.js'],
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: 'es2020',
  outfile: 'Sonar/Resources/source-bundle.js',
  define: {
    'process.versions.app': '"1.0.0-ios"',
  },
  alias: {
    'react-native-background-timer': './scripts/js-shims/background-timer.js',
    'react-native-quick-md5': './scripts/js-shims/quick-md5.js',
    'react-native-quick-base64': './scripts/js-shims/quick-base64.js',
    '@/utils/nativeModules/crypto': './scripts/js-shims/crypto.js',
    '@/store/setting/state': './js-source/src/store/setting/state.ts',
    '@/config/defaultSetting': './js-source/src/config/defaultSetting.ts',
    '@/utils/simplify-chinese-main': './js-source/src/utils/simplify-chinese-main/index.js',
  },
  loader: { '.ts': 'ts' },
  sourcemap: false,
  legalComments: 'none',
})

console.log('Built Sonar/Resources/source-bundle.js')
