package android.app
open class Activity : android.content.Context() {
 companion object { const val RESULT_OK = -1 }
 var launched: android.content.Intent? = null
 open fun startActivityForResult(intent: android.content.Intent, request: Int) { launched=intent }
 open fun onActivityResult(request: Int, result: Int, data: android.content.Intent?) {}
 open fun onDestroy() {}
 fun runOnUiThread(action: Runnable) { android.os.Handler().post(action) }
}
