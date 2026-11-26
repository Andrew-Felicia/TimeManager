package app.flowtime.android

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import app.flowtime.android.data.FlowtimeStore
import app.flowtime.android.ui.FlowtimeApp
import app.flowtime.android.ui.FlowtimeTheme

class MainActivity : ComponentActivity() {
    private val store: FlowtimeStore by viewModels()
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleIntent(intent)
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        setContent {
            FlowtimeTheme(darkTheme = store.darkTheme) {
                FlowtimeApp(store)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        store.reconcileTimer()
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_STOP_ALARM, false) == true) {
            store.stopAlarm()
            intent.removeExtra(EXTRA_STOP_ALARM)
        }
    }

    companion object {
        const val EXTRA_STOP_ALARM = "flowtime.stop.alarm"
    }
}
