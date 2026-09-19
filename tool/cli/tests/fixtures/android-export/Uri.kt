package android.net
data class Uri(val value:String) { companion object { fun parse(s:String)=Uri(s) };override fun toString()=value }
