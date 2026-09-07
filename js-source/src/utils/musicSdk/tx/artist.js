// Sonar adaptation of lx-music-mobile for the JavaScriptCore WY/TX runtime.
// Modified distribution; see repository-root THIRD_PARTY_NOTICES.md and LICENSES/.
import { httpFetch } from '../../request'
import { sizeFormate, formatPlayTime } from '../../index'
import { formatSingerName } from '../utils'

const comm = {
  ct: '11', cv: '14090508', v: '14090508', tmeAppID: 'qqmusic',
  phonetype: 'EBG-AN10', deviceScore: '553.47', devicelevel: '50', newdevicelevel: '20',
  rom: 'HuaWei/EMOTION/EmotionUI_14.2.0', os_ver: '12', OpenUDID: '0', OpenUDID2: '0',
  QIMEI36: '0', udid: '0', chid: '0', aid: '0', oaid: '0', taid: '0', tid: '0', wid: '0',
  uid: '0', sid: '0', modeSwitch: '6', teenMode: '0', ui_mode: '2', nettype: '1020', v4ip: '',
}

const request = async(module, method, param) => {
  const { statusCode, body } = await httpFetch('https://u.y.qq.com/cgi-bin/musicu.fcg', {
    method: 'post',
    headers: { 'User-Agent': 'QQMusic 14090508(android 12)' },
    body: { comm, req: { module, method, param } },
  }).promise
  if (statusCode !== 200 || body?.code !== 0 || body?.req?.code !== 0) {
    throw new Error('QQ 歌手服务暂时不可用')
  }
  return body.req.data || {}
}

const httpsImage = value => typeof value === 'string' ? value.replace(/^http:\/\//i, 'https://') : ''
const singerImage = mid => mid ? `https://y.gtimg.cn/music/photo_new/T001R500x500M000${mid}.jpg` : ''
const albumImage = mid => mid ? `https://y.gtimg.cn/music/photo_new/T002R500x500M000${mid}.jpg` : ''
const releaseDate = value => {
  if (typeof value !== 'string') return ''
  const match = value.trim().match(/^(\d{4})[-./年](\d{1,2})[-./月](\d{1,2})/)
  if (!match) return ''
  return `${match[1]}-${match[2].padStart(2, '0')}-${match[3].padStart(2, '0')}`
}

const track = item => {
  const mid = item?.mid || item?.songmid
  const name = item?.name || item?.title
  if (!mid || !name) return null
  const album = item.album || {}
  const file = item.file || {}
  const types = []
  const typeMap = {}
  ;[['128k', file.size_128mp3], ['320k', file.size_320mp3], ['flac', file.size_flac], ['flac24bit', file.size_hires]].forEach(([type, size]) => {
    if (Number(size) > 0) {
      const formatted = sizeFormate(Number(size))
      types.push({ type, size: formatted })
      typeMap[type] = { size: formatted }
    }
  })
  if (types.length === 0) { types.push({ type: '128k', size: null }); typeMap['128k'] = { size: null } }
  return {
    source: 'tx',
    songmid: mid,
    songId: item.id,
    strMediaMid: file.media_mid || mid,
    name,
    singer: formatSingerName(item.singer || [], 'name'),
    albumName: album.name || '',
    albumId: album.mid || '',
    albumMid: album.mid || '',
    img: albumImage(album.mid) || singerImage(item.singer?.[0]?.mid),
    interval: Number(item.interval) > 0 ? formatPlayTime(Number(item.interval)) : null,
    types,
    _types: typeMap,
    typeUrl: {},
  }
}

const album = item => {
  const mid = item?.albumMid || item?.mid
  const name = item?.albumName || item?.name
  if (!mid || !name) return null
  return {
    id: String(mid),
    source: 'tx',
    name,
    artist: item.singerName || item.singer?.name || '',
    img: httpsImage(item.albumPic) || albumImage(mid),
    releaseDate: releaseDate(item.publishDate || item.publicTime),
    trackCount: item.songCount == null && item.totalSongNum == null && item.totalNum == null
      ? null
      : (Number(item.songCount ?? item.totalSongNum ?? item.totalNum) > 0
          ? Number(item.songCount ?? item.totalSongNum ?? item.totalNum)
          : null),
  }
}

export default {
  async search(keyword, page = 1, limit = 10) {
    const data = await request('music.search.SearchCgiService', 'DoSearchForQQMusicMobile', {
      search_type: 1, query: String(keyword), page_num: Number(page), num_per_page: Number(limit),
      highlight: 0, nqc_flag: 0, multi_zhida: 0, cat: 2, grp: 1, sin: 0, sem: 0,
    })
    const section = data.body?.singer || data.singer || {}
    const values = Array.isArray(section) ? section : (section.list || data.body?.singerList || [])
    return {
      list: values.map(item => {
        const mid = item.singerMID || item.singerMid || item.mid
        return {
          id: String(mid || ''), source: 'tx', name: item.singerName || item.name || '',
          img: httpsImage(item.singerPic || item.pic) || singerImage(mid),
          songCount: item.songNum == null && item.singerSongNum == null
            ? null
            : Number(item.songNum ?? item.singerSongNum),
          albumCount: item.albumNum == null && item.singerAlbumNum == null
            ? null
            : Number(item.albumNum ?? item.singerAlbumNum),
        }
      }).filter(item => item.id && item.name),
      total: Number(section.totalNum ?? section.sum ?? values.length), source: 'tx',
    }
  },

  async popular(artistId, limit = 100) {
    const data = await request('musichall.song_list_server', 'GetSingerSongList', {
      singerMid: String(artistId), begin: 0, num: Number(limit), order: 1,
    })
    return (data.songList || []).map(value => track(value.songInfo || value)).filter(Boolean)
  },

  async albums(artistId, page = 1, limit = 30) {
    const begin = Math.max(0, Number(page) - 1) * Number(limit)
    const data = await request('music.musichallAlbum.AlbumListServer', 'GetAlbumList', {
      singerMid: String(artistId), begin, num: Number(limit), order: 0,
    })
    const list = (data.albumList || []).map(album).filter(Boolean)
    return { list, total: Number(data.total ?? list.length), source: 'tx' }
  },

  async albumTracks(albumId, limit = 200) {
    const data = await request('music.musichallAlbum.AlbumSongList', 'GetAlbumSongList', {
      albumMid: String(albumId), begin: 0, num: Number(limit), order: 2,
    })
    return {
      info: album(data.albumInfo || data.album || { albumMid: albumId, albumName: '' }),
      list: (data.songList || []).map(value => track(value.songInfo || value)).filter(Boolean),
      source: 'tx',
    }
  },
}
