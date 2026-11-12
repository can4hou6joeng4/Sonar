package cn.bobochang.sonar

import android.app.Application
import cn.bobochang.sonar.di.AppContainer

class SonarApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
