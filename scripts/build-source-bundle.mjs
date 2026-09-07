import { build } from 'esbuild'
import { mkdir, readFile } from 'node:fs/promises'

const licenseFiles = [
  'lx-music-mobile', 'NeteaseCloudMusicApi', 'base64-js', 'buffer',
  'ieee754', 'he', 'pako', 'pako-zlib', 'esbuild', 'lrc-file-parser', 'cc-by-sa-4.0',
]
const notices = [await readFile('THIRD_PARTY_NOTICES.md', 'utf8')]
for (const name of licenseFiles) {
  notices.push(`\n===== ${name} =====\n${await readFile(`LICENSES/${name}.txt`, 'utf8')}`)
}
const noticeText = notices.join('\n')
if (noticeText.includes('*/')) throw new Error('License notice contains an unsafe block-comment terminator')

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
  legalComments: 'inline',
  banner: { js: `/*!\n${noticeText}\n*/` },
})

console.log('Built Sonar/Resources/source-bundle.js')
