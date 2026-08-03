package com.nuevatel.controles

import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (no FlutterActivity) es requerido por local_auth
// para poder mostrar el dialogo de huella/Face ID.
class MainActivity : FlutterFragmentActivity() {
    private val canal = "app_controles/tonos"
    private val codigoSeleccionTono = 4242
    private var resultadoPendiente: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal).setMethodCallHandler { call, result ->
            when (call.method) {
                "elegirTonoAlarma" -> {
                    resultadoPendiente = result
                    val uriActual = call.argument<String>("uriActual")
                    val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                        putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                        putExtra(
                            RingtoneManager.EXTRA_RINGTONE_DEFAULT_URI,
                            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                        )
                        if (uriActual != null) {
                            putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(uriActual))
                        }
                    }
                    startActivityForResult(intent, codigoSeleccionTono)
                }
                "nombreTono" -> {
                    val uriTexto = call.argument<String>("uri")
                    if (uriTexto == null) {
                        result.success(null)
                    } else {
                        try {
                            val ringtone = RingtoneManager.getRingtone(this, Uri.parse(uriTexto))
                            result.success(ringtone?.getTitle(this))
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == codigoSeleccionTono) {
            @Suppress("DEPRECATION")
            val uri: Uri? = data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
            resultadoPendiente?.success(uri?.toString())
            resultadoPendiente = null
        }
    }
}
