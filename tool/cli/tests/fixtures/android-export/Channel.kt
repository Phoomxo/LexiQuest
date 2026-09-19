package io.flutter.plugin.common
class MethodCall(val method:String,val args:Map<String,Any?>) { @Suppress("UNCHECKED_CAST") fun <T> argument(k:String):T?=args[k] as T? }
class MethodChannel(messenger:Any,val name:String) {
 interface Result {fun success(value:Any?);fun error(code:String,message:String?,details:Any?);fun notImplemented()}
 companion object {val handlers=mutableMapOf<String,(MethodCall,Result)->Unit>()}
 fun setMethodCallHandler(handler:(MethodCall,Result)->Unit) {handlers[name]=handler}
}
