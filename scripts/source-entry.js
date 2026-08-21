import { Buffer } from 'buffer'
import musicSdk from '../js-source/src/utils/musicSdk/index.js'

globalThis.Buffer = Buffer

const normalizeSource = source => {
  if (source !== 'wy' && source !== 'tx') throw new Error(`Unsupported source: ${source}`)
  return source
}

const sdkFor = source => musicSdk[normalizeSource(source)]
const unwrapRequest = value => value && typeof value === 'object' && value.promise ? value.promise : value

globalThis.__source__ = Object.freeze({
  async init() {
    await musicSdk.init()
    return true
  },
  async search(source, keyword, page = 1, limit = 25) {
    const sdk = sdkFor(source)
    const result = await sdk.musicSearch.search(String(keyword), Number(page), Number(limit))
    if (!result || !Array.isArray(result.list)) throw new Error('音源返回搜索结果异常')
    return result
  },
  async lyric(source, songInfo) {
    const result = await unwrapRequest(sdkFor(source).getLyric(songInfo))
    if (!result || typeof result.lyric !== 'string') throw new Error('音源返回歌词异常')
    return result
  },
  async pic(source, songInfo) {
    const result = await unwrapRequest(sdkFor(source).getPic(songInfo))
    if (typeof result !== 'string' || !/^https?:/.test(result)) throw new Error('音源返回封面地址异常')
    return result
  },
  async tipSearch(keyword) {
    const sdk = sdkFor('wy')
    const value = String(keyword)
    try {
      const result = await sdk.tipSearch.search(value)
      if (Array.isArray(result) && result.length > 0) return result
    } catch {}

    const page = await sdk.musicSearch.search(value, 1, 10)
    if (!page || !Array.isArray(page.list)) throw new Error('音源返回联想结果异常')
    return [...new Set(page.list.map(track => {
      const artist = typeof track.singer === 'string' ? track.singer : ''
      return artist ? `${track.name} - ${artist}` : track.name
    }).filter(Boolean))]
  },
})
