// Sonar adaptation of lx-music-mobile for the JavaScriptCore WY/TX runtime.
// Modified distribution; see repository-root THIRD_PARTY_NOTICES.md and LICENSES/.
import defaultSetting from '@/config/defaultSetting'


interface InitState {
  setting: LX.AppSetting
}

const state: InitState = {
  setting: { ...defaultSetting },
}


export default state
