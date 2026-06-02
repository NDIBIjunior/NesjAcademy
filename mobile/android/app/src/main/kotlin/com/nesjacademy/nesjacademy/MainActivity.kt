package com.nesjacademy.nesjacademy

import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val canal = "nesjacademy/concentration"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Pont natif pour le mode concentration : active/désactive le
        // « Ne pas déranger » (DND) du téléphone via le filtre d'interruption.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal)
            .setMethodCallHandler { appel, resultat ->
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val supporte = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M

                when (appel.method) {
                    // L'utilisateur a-t-il accordé l'accès "Ne pas déranger" ?
                    "accesAccorde" ->
                        resultat.success(supporte && nm.isNotificationPolicyAccessGranted)

                    // Active le silence total (aucune notification/son ne dérange).
                    "activer" -> {
                        if (supporte && nm.isNotificationPolicyAccessGranted) {
                            nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
                            resultat.success(true)
                        } else {
                            resultat.success(false)
                        }
                    }

                    // Rétablit le mode normal (toutes les notifications repassent).
                    "desactiver" -> {
                        if (supporte && nm.isNotificationPolicyAccessGranted) {
                            nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
                            resultat.success(true)
                        } else {
                            resultat.success(false)
                        }
                    }

                    else -> resultat.notImplemented()
                }
            }
    }
}
