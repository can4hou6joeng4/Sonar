import { mkdir, writeFile, chmod } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'

const output = process.argv[2]
if (!output) {
  console.error('Usage: node scripts/generate-build-config.mjs <output.json>')
  process.exit(1)
}

// Optional values are supplied by the build environment, never by source control.
const config = {}
for (const [key, variable] of [['wyToken', 'SONAR_WY_TOKEN'], ['chkszKey', 'SONAR_CHKSZ_KEY']]) {
  const value = process.env[variable]?.trim()
  if (value) config[key] = value
}
const destination = resolve(output)
await mkdir(dirname(destination), { recursive: true })
await writeFile(destination, JSON.stringify(config), { mode: 0o600 })
await chmod(destination, 0o600)
console.log('Build configuration generated; values are not logged.')
