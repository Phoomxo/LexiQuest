package android.system
class ErrnoException(val functionName:String,val errno:Int):Exception()
object OsConstants { const val ENOSPC=28 }
