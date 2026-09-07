// Sonar adaptation of lx-music-mobile for the JavaScriptCore WY/TX runtime.
// Modified distribution; see repository-root THIRD_PARTY_NOTICES.md and LICENSES/.
import { httpFetch } from '../../request'
import { sizeFormate, formatPlayTime } from '../../index'
import { formatSingerName } from '../utils'

const requestJSON = async(url, options) => {
  const { statusCode, body } = await httpFetch(url, options).promise
  if (statusCode !== 200 || !body || (body.code != null && body.code !== 200)) {
    throw new Error('网易云歌手服务暂时不可用')
  }
  return body
}

const track = item => {
  const id = item?.id
  const name = item?.name
  if (id == null || typeof name !== 'string' || name.length === 0) return null
  const album = item.al || item.album || {}
  const artists = item.ar || item.artists || []
  const duration = Number(item.dt ?? item.duration ?? 0)

  const types = []
  const _types = {}
  let size

  const privilege = item.privilege || {}
  const maxBrLevel = String(privilege.maxBrLevel || '').toLowerCase()
  const maxbr = Number(privilege.maxbr || 0)

  if (maxBrLevel === 'hires' || item.hr) {
    size = item.hr?.size ? sizeFormate(item.hr.size) : null
    types.push({ type: 'flac24bit', size })
    _types.flac24bit = { size }
  }
  if (maxBrLevel === 'lossless' || maxbr >= 999000 || item.sq) {
    size = item.sq?.size ? sizeFormate(item.sq.size) : null
    types.push({ type: 'flac', size })
    _types.flac = { size }
  }
  if (item.h || maxbr >= 320000) {
    size = item.h?.size ? sizeFormate(item.h.size) : null
    types.push({ type: '320k', size })
    _types['320k'] = { size }
  }
  if (item.l || item.m || maxbr >= 128000 || types.length === 0) {
    const lowItem = item.l || item.m
    size = lowItem?.size ? sizeFormate(lowItem.size) : null
    types.push({ type: '128k', size })
    _types['128k'] = { size }
  }

  types.reverse()

  return {
    source: 'wy',
    songmid: id,
    name,
    singer: formatSingerName(artists, 'name'),
    albumName: album.name || '',
    albumId: album.id,
    img: album.picUrl || '',
    interval: duration > 0 ? formatPlayTime(duration / 1000) : null,
    types,
    _types,
    typeUrl: {},
  }
}

const album = item => {
  const id = item?.id
  const name = item?.name
  if (id == null || typeof name !== 'string' || name.length === 0) return null
  return {
    id: String(id),
    source: 'wy',
    name,
    artist: item.artist?.name || formatSingerName(item.artists || [], 'name'),
    img: item.picUrl || item.blurPicUrl || '',
    releaseDate: item.publishTime ? new Date(item.publishTime).toISOString().slice(0, 10) : '',
    trackCount: item.size == null ? null : Number(item.size),
  }
}

export default {
  async search(keyword, page = 1, limit = 10) {
    const offset = Math.max(0, Number(page) - 1) * Number(limit)
    const query = `s=${encodeURIComponent(String(keyword))}&type=100&limit=${Number(limit)}&offset=${offset}`
    const body = await requestJSON(`https://music.163.com/api/search/get?${query}`)
    const values = body.result?.artists || []
    return {
      list: values.map(item => ({
        id: String(item.id),
        source: 'wy',
        name: item.name,
        img: item.picUrl || item.img1v1Url || '',
        songCount: item.musicSize == null ? null : Number(item.musicSize),
        albumCount: item.albumSize == null ? null : Number(item.albumSize),
      })).filter(item => item.id && item.name),
      total: Number(body.result?.artistCount ?? values.length),
      source: 'wy',
    }
  },

  async popular(artistId) {
    const body = await requestJSON(`https://music.163.com/api/artist/top/song?id=${encodeURIComponent(artistId)}`)
    return (body.songs || []).map(track).filter(Boolean)
  },

  async albums(artistId, page = 1, limit = 30) {
    const offset = Math.max(0, Number(page) - 1) * Number(limit)
    const body = await requestJSON(`https://music.163.com/api/artist/albums/${encodeURIComponent(artistId)}?limit=${limit}&offset=${offset}`)
    const list = (body.hotAlbums || []).map(album).filter(Boolean)
    return { list, total: Number(body.artist?.albumSize ?? list.length), source: 'wy' }
  },

  async albumTracks(albumId) {
    const body = await requestJSON(`https://music.163.com/api/album/${encodeURIComponent(albumId)}`)
    return {
      info: album(body.album || { id: albumId, name: '' }),
      list: (body.songs || body.album?.songs || []).map(track).filter(Boolean),
      source: 'wy',
    }
  },
}
