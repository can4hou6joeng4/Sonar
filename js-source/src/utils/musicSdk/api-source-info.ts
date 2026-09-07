// Sonar adaptation of lx-music-mobile for the JavaScriptCore WY/TX runtime.
// Modified distribution; see repository-root THIRD_PARTY_NOTICES.md and LICENSES/.
// Support qualitys: 128k 320k flac wav

const sources: Array<{
  id: string
  name: string
  disabled: boolean
  supportQualitys: Partial<Record<LX.OnlineSource, LX.Quality[]>>
}> = [
]

export default sources
