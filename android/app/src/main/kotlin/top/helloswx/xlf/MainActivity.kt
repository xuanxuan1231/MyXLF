package top.helloswx.xlf

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "top.helloswx.xlf/updater",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> installApk(call.argument<String>("path"), result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 调用系统安装程序安装已下载的 APK。
     *
     * Android 8.0+ 需要用户先授予「安装未知应用」权限；未授权时打开该应用的
     * 系统设置页并返回 permission_required，由 Flutter 侧提示用户授权后重试。
     */
    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("INVALID_PATH", "安装包路径为空", null)
            return
        }
        val file = File(path)
        if (!file.exists()) {
            result.error("FILE_NOT_FOUND", "安装包不存在，请重新下载", null)
            return
        }
        // 只允许安装缓存目录中的 APK（path_provider 的临时目录即 cacheDir）。
        val canonicalPath = try {
            file.canonicalPath
        } catch (_: Exception) {
            ""
        }
        val cacheRoot = try {
            cacheDir.canonicalPath + File.separator
        } catch (_: Exception) {
            cacheDir.path + File.separator
        }
        if (!canonicalPath.startsWith(cacheRoot)) {
            result.error("INVALID_PATH", "安装包路径不合法", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            try {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                        data = Uri.parse("package:$packageName")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    },
                )
            } catch (_: ActivityNotFoundException) {
                try {
                    startActivity(
                        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                } catch (e: Exception) {
                    result.error(
                        "PERMISSION_PAGE",
                        e.message ?: "无法打开「安装未知应用」设置",
                        null,
                    )
                    return
                }
            }
            result.success("permission_required")
            return
        }

        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            result.success("started")
        } catch (e: Exception) {
            result.error("INSTALL_FAILED", e.message ?: "无法启动系统安装程序", null)
        }
    }
}
