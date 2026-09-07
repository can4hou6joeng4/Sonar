import { Buffer } from 'buffer'
import musicSdk from '../js-source/src/utils/musicSdk/index.js'
import txMusicInfo from '../js-source/src/utils/musicSdk/tx/musicInfo.js'
import wyMusicDetail from '../js-source/src/utils/musicSdk/wy/musicDetail.js'

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
  async hotSearch(source) {
    const result = await unwrapRequest(sdkFor(source).hotSearch.getList())
    if (!result || result.source !== source || !Array.isArray(result.list)) throw new Error('音源返回热门搜索异常')
    return [...new Set(result.list.map(value => String(value).trim()).filter(Boolean))]
  },
  async playlistCatalog(source, sortId, tagId, page = 1) {
    const sdk = sdkFor(source)
    const result = await unwrapRequest(sdk.songList.getList(sortId, tagId, Number(page)))
    if (!result || !Array.isArray(result.list)) throw new Error('音源返回歌单广场异常')
    return result
  },
  async playlistDetail(source, id, page = 1) {
    const sdk = sdkFor(source)
    // QQ 的第二个参数是重试次数，不是页码；传入 page 会让首次请求直接被当成重试。
    const request = source === 'tx'
      ? sdk.songList.getListDetail(String(id))
      : sdk.songList.getListDetail(String(id), Number(page))
    const result = await unwrapRequest(request)
    if (!result || !Array.isArray(result.list)) throw new Error('音源返回歌单详情异常')
    return result
  },
  async artistSearch(source, keyword, page = 1, limit = 10) {
    const normalizedPage = Math.max(1, Number(page))
    const normalizedLimit = Math.max(1, Number(limit))
    const result = await sdkFor(source).artist.search(String(keyword), normalizedPage, normalizedLimit)
    if (!result || !Array.isArray(result.list)) throw new Error('音源返回歌手搜索结果异常')
    return {
      ...result,
      page: normalizedPage,
      limit: normalizedLimit,
      hasMore: result.hasMore == null
        ? result.list.length > 0 && normalizedPage * normalizedLimit < Number(result.total || 0)
        : Boolean(result.hasMore),
    }
  },
  async artistPopular(source, artistId) {
    const result = await sdkFor(source).artist.popular(String(artistId))
    if (!Array.isArray(result)) throw new Error('音源返回热门歌曲异常')
    return result
  },
  async artistAlbums(source, artistId, page = 1, limit = 30) {
    const result = await sdkFor(source).artist.albums(String(artistId), Number(page), Number(limit))
    if (!result || !Array.isArray(result.list)) throw new Error('音源返回歌手专辑异常')
    return result
  },
  async albumTracks(source, albumId) {
    const result = await sdkFor(source).artist.albumTracks(String(albumId))
    if (!result || !Array.isArray(result.list)) throw new Error('音源返回专辑曲目异常')
    return result
  },
  async musicInfo(source, songmid) {
    const normalized = normalizeSource(source)
    const mid = String(songmid)
    if (normalized === 'tx') {
      const result = await unwrapRequest(txMusicInfo(mid))
      if (!result) throw new Error('音源返回曲目信息异常')
      return result
    } else if (normalized === 'wy') {
      const result = await unwrapRequest(wyMusicDetail.getList([mid]))
      if (!result || !Array.isArray(result.list) || result.list.length === 0) throw new Error('音源返回曲目信息异常')
      return result.list[0]
    }
    throw new Error(`Unsupported source: ${source}`)
  },
})
