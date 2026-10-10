// Sonar adaptation of lx-music-mobile for the JavaScriptCore QQ Music runtime.
// Modified distribution; see repository-root THIRD_PARTY_NOTICES.md and LICENSES/.
import { httpFetch } from '../../request'

const comm = {
  ct: '11', cv: '14090508', v: '14090508', tmeAppID: 'qqmusic',
  phonetype: 'EBG-AN10', deviceScore: '553.47', devicelevel: '50', newdevicelevel: '20',
  rom: 'HuaWei/EMOTION/EmotionUI_14.2.0', os_ver: '12', OpenUDID: '0', OpenUDID2: '0',
  QIMEI36: '0', udid: '0', chid: '0', aid: '0', oaid: '0', taid: '0', tid: '0', wid: '0',
  uid: '0', sid: '0', modeSwitch: '6', teenMode: '0', ui_mode: '2', nettype: '1020', v4ip: '',
}

export const request = async(module, method, param, failureMessage = 'QQ 歌手服务暂时不可用') => {
  const { statusCode, body } = await httpFetch('https://u.y.qq.com/cgi-bin/musicu.fcg', {
    method: 'post',
    headers: { 'User-Agent': 'QQMusic 14090508(android 12)' },
    body: { comm, req: { module, method, param } },
  }).promise
  const data = body?.req?.data
  if (statusCode !== 200 || body?.code !== 0 || body?.req?.code !== 0 || (data?.code != null && data.code !== 0)) {
    throw new Error(failureMessage)
  }
  if (!data || typeof data !== 'object') throw new Error(failureMessage)
  return data
}
