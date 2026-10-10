// Sonar adaptation of lx-music-mobile for the JavaScriptCore QQ Music runtime.
// Modified distribution; see repository-root THIRD_PARTY_NOTICES.md and LICENSES/.
import tx from './tx'
import { supportQuality } from './api-source'

export const init = async() => {
  if (tx.init) await tx.init()
}

export default {
  sources: [{ name: 'QQ音乐', id: 'tx' }],
  tx,
  init,
  supportQuality,
}
