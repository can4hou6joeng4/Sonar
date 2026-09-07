import WidgetKit
import SwiftUI

@main
struct SonarWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        QuickShuffleWidget()
    }
}
