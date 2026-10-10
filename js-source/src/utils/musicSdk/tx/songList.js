// Sonar adaptation of lx-music-mobile for the JavaScriptCore QQ Music runtime.
// Modified distribution; see repository-root THIRD_PARTY_NOTICES.md and LICENSES/.
import { httpFetch } from '../../request'
import { request } from './request'
import { decodeName, formatPlayTime, sizeFormate, dateFormat, formatPlayCount } from '../../index'
import { formatSingerName } from '../utils'

export default {
  _requestObj_tags: null,
  _requestObj_hotTags: null,
  _requestObj_list: null,
  limit_list: 36,
  limit_song: 1000,
  successCode: 0,
  sortList: [
    {
      name: '最热',
      tid: 'hot',
      id: 5,
    },
    {
      name: '最新',
      tid: 'new',
      id: 2,
    },
  ],
  regExps: {
    hotTagHtml: /class="c_bg_link js_tag_item" data-id="\w+">.+?<\/a>/g,
    hotTag: /data-id="(\w+)">(.+?)<\/a>/,

    // https://y.qq.com/n/yqq/playlist/7217720898.html
    // https://i.y.qq.com/n2/m/share/details/taoge.html?platform=11&appshare=android_qq&appversion=9050006&id=7217720898&ADTAG=qfshare
    listDetailLink: /\/playlist\/(\d+)/,
    listDetailLink2: /id=(\d+)/,
  },
  tagsUrl: 'https://u.y.qq.com/cgi-bin/musicu.fcg?loginUin=0&hostUin=0&format=json&inCharset=utf-8&outCharset=utf-8&notice=0&platform=wk_v15.json&needNewCode=0&data=%7B%22tags%22%3A%7B%22method%22%3A%22get_all_categories%22%2C%22param%22%3A%7B%22qq%22%3A%22%22%7D%2C%22module%22%3A%22playlist.PlaylistAllCategoriesServer%22%7D%7D',
  hotTagUrl: 'https://c.y.qq.com/node/pc/wk_v15/category_playlist.html',
  getListUrl(sortId, id, page) {
    if (id) {
      id = parseInt(id)
      return `https://u.y.qq.com/cgi-bin/musicu.fcg?loginUin=0&hostUin=0&format=json&inCharset=utf-8&outCharset=utf-8&notice=0&platform=wk_v15.json&needNewCode=0&data=${encodeURIComponent(JSON.stringify({
        comm: { cv: 1602, ct: 20 },
        playlist: {
          method: 'get_category_content',
          param: {
            titleid: id,
            caller: '0',
            category_id: id,
            size: this.limit_list,
            page: page - 1,
            use_page: 1,
          },
          module: 'playlist.PlayListCategoryServer',
        },
        }))}`
    }
    return `https://u.y.qq.com/cgi-bin/musicu.fcg?loginUin=0&hostUin=0&format=json&inCharset=utf-8&outCharset=utf-8&notice=0&platform=wk_v15.json&needNewCode=0&data=${encodeURIComponent(JSON.stringify({
          comm: { cv: 1602, ct: 20 },
          playlist: {
            method: 'get_playlist_by_tag',
            param: { id: 10000000, sin: this.limit_list * (page - 1), size: this.limit_list, order: sortId, cur_page: page },
            module: 'playlist.PlayListPlazaServer',
          },
      }))}`
  },

  // 获取标签
  getTag(tryNum = 0) {
    if (this._requestObj_tags) this._requestObj_tags.cancelHttp()
    if (tryNum > 2) return Promise.reject(new Error('try max num'))
    this._requestObj_tags = httpFetch(this.tagsUrl)
    return this._requestObj_tags.promise.then(({ body }) => {
      if (body.code !== this.successCode) return this.getTag(++tryNum)
      return this.filterTagInfo(body.tags.data.v_group)
    })
  },
  // 获取标签
  getHotTag(tryNum = 0) {
    if (this._requestObj_hotTags) this._requestObj_hotTags.cancelHttp()
    if (tryNum > 2) return Promise.reject(new Error('try max num'))
    this._requestObj_hotTags = httpFetch(this.hotTagUrl)
    return this._requestObj_hotTags.promise.then(({ statusCode, body }) => {
      if (statusCode !== 200) return this.getHotTag(++tryNum)
      return this.filterInfoHotTag(body)
    })
  },
  filterInfoHotTag(html) {
    let hotTag = html.match(this.regExps.hotTagHtml)
    const hotTags = []
    if (!hotTag) return hotTags

    hotTag.forEach(tagHtml => {
      let result = tagHtml.match(this.regExps.hotTag)
      if (!result) return
      hotTags.push({
        id: parseInt(result[1]),
        name: result[2],
        source: 'tx',
      })
    })
    return hotTags
  },
  filterTagInfo(rawList) {
    return rawList.map(type => ({
      name: type.group_name,
      list: type.v_item.map(item => ({
        parent_id: type.group_id,
        parent_name: type.group_name,
        id: item.id,
        name: item.name,
        source: 'tx',
      })),
    }))
  },

  // 获取列表数据
  getList(sortId, tagId, page, tryNum = 0) {
    if (this._requestObj_list) this._requestObj_list.cancelHttp()
    if (tryNum > 2) return Promise.reject(new Error('try max num'))
    this._requestObj_list = httpFetch(
      this.getListUrl(sortId, tagId, page),
    )
    // console.log(this.getListUrl(sortId, tagId, page))
    return this._requestObj_list.promise.then(({ body }) => {
      if (body.code !== this.successCode) return this.getList(sortId, tagId, page, ++tryNum)
      return tagId ? this.filterList2(body.playlist.data, page) : this.filterList(body.playlist.data, page)
    })
  },

  filterList(data, page) {
    return {
      list: data.v_playlist.map(item => ({
        play_count: formatPlayCount(item.access_num),
        id: String(item.tid),
        author: item.creator_info.nick,
        name: item.title,
        time: item.modify_time ? dateFormat(item.modify_time * 1000, 'Y-M-D') : '',
        img: item.cover_url_medium,
        // grade: item.favorcnt / 10,
        total: item.song_ids?.length,
        desc: decodeName(item.desc).replace(/<br>/g, '\n'),
        source: 'tx',
      })),
      total: data.total,
      page,
      limit: this.limit_list,
      source: 'tx',
    }
  },
  filterList2({ content }, page) {
    // console.log(content.v_item)
    return {
      list: content.v_item.map(({ basic }) => ({
        play_count: formatPlayCount(basic.play_cnt),
        id: String(basic.tid),
        author: basic.creator.nick,
        name: basic.title,
        // time: basic.publish_time,
        img: basic.cover.medium_url || basic.cover.default_url,
        // grade: basic.favorcnt / 10,
        desc: decodeName(basic.desc).replace(/<br>/g, '\n'),
        source: 'tx',
      })),
      total: content.total_cnt,
      page,
      limit: this.limit_list,
      source: 'tx',
    }
  },

  async handleParseId(link, retryNum = 0) {
    if (retryNum > 2) return Promise.reject(new Error('link try max num'))

    const requestObj_listDetailLink = httpFetch(link)
    const { url, statusCode } = await requestObj_listDetailLink.promise
    // console.log(headers)
    if (statusCode > 400) return this.handleParseId(link, ++retryNum)
    return url
  },

  async getListId(id) {
    if ((/[?&:/]/.test(id))) {
      if (!this.regExps.listDetailLink.test(id)) {
        id = await this.handleParseId(id)
      }
      let result = this.regExps.listDetailLink.exec(id)
      if (!result) {
        result = this.regExps.listDetailLink2.exec(id)
        if (!result) throw new Error('failed')
      }
      id = result[1]
      // console.log(id)
    }
    return id
  },
  // 获取歌曲列表内的音乐
  async getListDetail(id, page = 1) {
    id = await this.getListId(id)
    const normalizedPage = Math.max(1, Number(page))
    const data = await request('music.srfDissInfo.aiDissInfo', 'uniform_get_Dissinfo', {
      disstid: Number(id),
      song_begin: (normalizedPage - 1) * this.limit_song,
      song_num: this.limit_song,
      userinfo: 1,
      order: 0,
      onlysong: 0,
      tag: 1,
      enc_hostuin: '',
    }, 'QQ 歌单详情暂时不可用')
    if (!Array.isArray(data.songlist) || !data.dirinfo) throw new Error('QQ 歌单详情返回数据异常')
    const info = data.dirinfo
    return {
      list: this.filterListDetail(data.songlist),
      page: normalizedPage,
      limit: this.limit_song,
      total: Number(data.total_song_num ?? info.songnum ?? data.songlist.length),
      source: 'tx',
      info: {
        name: decodeName(info.title || ''),
        img: String(info.picurl || '').replace(/^http:\/\//i, 'https://'),
        desc: decodeName(info.desc || '').replace(/<br\s*\/?\s*>/gi, '\n'),
        author: decodeName(info.host_nick || info.creator?.nick || ''),
        play_count: formatPlayCount(info.listennum || 0),
      },
    }
  },
  filterListDetail(rawList) {
    // console.log(rawList)
    return rawList.map(item => {
      let types = []
      let _types = {}
      if (item.file.size_128mp3 !== 0) {
        let size = sizeFormate(item.file.size_128mp3)
        types.push({ type: '128k', size })
        _types['128k'] = {
          size,
        }
      }
      if (item.file.size_320mp3 !== 0) {
        let size = sizeFormate(item.file.size_320mp3)
        types.push({ type: '320k', size })
        _types['320k'] = {
          size,
        }
      }
      if (item.file.size_flac !== 0) {
        let size = sizeFormate(item.file.size_flac)
        types.push({ type: 'flac', size })
        _types.flac = {
          size,
        }
      }
      if (item.file.size_hires !== 0) {
        let size = sizeFormate(item.file.size_hires)
        types.push({ type: 'flac24bit', size })
        _types.flac24bit = {
          size,
        }
      }
      // types.reverse()
      return {
        singer: formatSingerName(item.singer, 'name'),
        name: item.title,
        albumName: item.album.name,
        albumId: item.album.mid,
        source: 'tx',
        interval: formatPlayTime(item.interval),
        songId: item.id,
        albumMid: item.album.mid,
        strMediaMid: item.file.media_mid,
        songmid: item.mid,
        img: (item.album.name === '' || item.album.name === '空')
          ? item.singer?.length ? `https://y.gtimg.cn/music/photo_new/T001R500x500M000${item.singer[0].mid}.jpg` : ''
          : `https://y.gtimg.cn/music/photo_new/T002R500x500M000${item.album.mid}.jpg`,
        lrc: null,
        otherSource: null,
        types,
        _types,
        typeUrl: {},
      }
    })
  },
  getTags() {
    return Promise.all([this.getTag(), this.getHotTag()]).then(([tags, hotTag]) => ({ tags, hotTag, source: 'tx' }))
  },

  async getDetailPageUrl(id) {
    id = await this.getListId(id)

    return `https://y.qq.com/n/ryqq/playlist/${id}`
  },

  async search(text, page = 1, limit = 20) {
    const data = await request('music.search.SearchCgiService', 'DoSearchForQQMusicMobile', {
      search_type: 3,
      query: String(text),
      page_num: Number(page),
      num_per_page: Number(limit),
      highlight: 0,
      nqc_flag: 0,
      multi_zhida: 0,
      cat: 2,
      grp: 1,
      sin: 0,
      sem: 0,
    }, 'QQ 歌单搜索暂时不可用')
    const items = data.body?.item_songlist
    if (!Array.isArray(items)) throw new Error('QQ 歌单搜索返回数据异常')
    return {
      list: items.filter(item => item.dissid != null && item.dissname).map(item => ({
        play_count: item.listennum_str || formatPlayCount(item.listennum || 0),
        id: String(item.dissid),
        author: decodeName(item.nickname || ''),
        name: decodeName(item.dissname).replace(/<[^>]*>/g, ''),
        time: item.createtime || '',
        img: String(item.logo || '').replace(/^http:\/\//i, 'https://'),
        total: Number(item.songnum || 0),
        desc: decodeName(item.subhead || '').replace(/<br\s*\/?\s*>/gi, '\n'),
        source: 'tx',
      })),
      page: Number(page),
      limit: Number(limit),
      total: Number(data.meta?.sum ?? data.meta?.estimate_sum ?? items.length),
      source: 'tx',
    }
  },
}

// getList
// getTags
// getListDetail
