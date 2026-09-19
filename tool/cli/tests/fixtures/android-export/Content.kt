package android.content
import android.net.Uri
open class Context {
 companion object { const val MODE_PRIVATE=0 }
 val applicationContext: Context get()=this
 val contentResolver get()=ContentResolver.instance
 fun getSharedPreferences(name:String, mode:Int)=SharedPreferences()
}
class ActivityNotFoundException: RuntimeException()
class Intent(val action:String="") {
 companion object { const val ACTION_CREATE_DOCUMENT="create";const val CATEGORY_OPENABLE="open";const val EXTRA_TITLE="title";const val FLAG_GRANT_READ_URI_PERMISSION=1;const val FLAG_GRANT_WRITE_URI_PERMISSION=2;const val FLAG_GRANT_PERSISTABLE_URI_PERMISSION=64 }
 var type:String?=null;var data:Uri?=null;var flags:Int=3 or 64
 fun addCategory(s:String)=this
 fun putExtra(k:String,v:String)=this
 fun addFlags(f:Int):Intent {flags=flags or f;return this}
}
class SharedPreferences {
 companion object {
 val file=System.getenv("F02_PREFS")?.let{java.io.File(it)}
 val values=java.util.concurrent.ConcurrentHashMap<String,Set<String>>().apply {
  if(file?.exists()==true) {val p=java.util.Properties();file.inputStream().use{p.load(it)};p.forEach{k,v->put(k.toString(),v.toString().split("|").filter{it.isNotEmpty()}.toSet())}}
 }
}
 fun getStringSet(k:String,d:Set<String>?):Set<String>?=values[k] ?: d
 fun edit()=Editor()
 class Editor { private val changes=mutableMapOf<String,Set<String>>(); fun putStringSet(k:String,v:Set<String>):Editor {changes[k]=v.toSet();return this};fun commit():Boolean {values.putAll(changes);file?.let{f->val p=java.util.Properties();values.forEach{(k,v)->p[k]=v.joinToString("|")};f.outputStream().use{p.store(it,"")}};return true} }
}
class ContentResolver {
 companion object { val instance=ContentResolver() }
 var stream:java.io.OutputStream=java.io.ByteArrayOutputStream()
 var deletes=0;var deleteOK=true;var openedOn:String?=null
 fun openOutputStream(uri:Uri,mode:String):java.io.OutputStream {openedOn=Thread.currentThread().name;return stream}
 fun takePersistableUriPermission(uri:Uri,flags:Int) {}
 fun releasePersistableUriPermission(uri:Uri,flags:Int) {}
}
