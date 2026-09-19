package fixture
import com.lexiquest.app.MainActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.*
import android.content.*
import android.net.Uri
import android.os.Handler
class Reply:MethodChannel.Result {var count=0;var code:String?=null;var value:Any?=null;override fun success(value:Any?){check(Thread.currentThread().name=="main");count++;this.value=value};override fun error(code:String,message:String?,details:Any?){check(Thread.currentThread().name=="main");count++;this.code=code};override fun notImplemented(){count++;code="NOT_IMPLEMENTED"}}
fun call(name:String,args:Map<String,Any?> = emptyMap()):Reply {val r=Reply();MethodChannel.handlers.getValue("com.lexiquest.app/export")(MethodCall(name,args),r);return r}
fun activity():MainActivity {val a=MainActivity();a.configureFlutterEngine(FlutterEngine());pump();return a}
fun pump(){repeat(40){Handler.drain();Thread.sleep(2)}}
fun save(bytes:ByteArray=byteArrayOf(1,2,3)):Reply { val r=call("saveExportFile",mapOf("suggestedName" to "a.csv","mimeType" to "text/csv","bytes" to bytes,"operationId" to "test-op"));pump();return r}
fun picked(a:MainActivity){a.onActivityResult(4172,-1,Intent().apply{data=Uri.parse("content://test/export")})}
fun main(args:Array<String>) {
 try {
  if(args[0]=="restart-denied") ContentResolver.instance.deleteOK=false
  val a=if(args[0]=="restart-picker") MainActivity().apply{configureFlutterEngine(FlutterEngine())} else activity()
  when(args[0]) {
   "positive" -> {val r=save();picked(a);pump();check(r.value=="content://test/export" && r.count==1);val f=call("finishExportFile",mapOf("location" to r.value,"discard" to false));pump();check(f.count==1 && f.code==null);check(ContentResolver.instance.deletes==0);check(SharedPreferences.values["uncommitted"].isNullOrEmpty());picked(a);pump();check(ContentResolver.instance.deletes==0){"duplicate result must not delete committed export"}}
   "picker-cancel" -> {val r=save();a.onActivityResult(4172,0,null);pump();check(r.count==1 && r.value==null && r.code==null);check(ContentResolver.instance.deletes==0)}
   "close-error", "cleanup-error" -> {ContentResolver.instance.deleteOK=args[0]!="cleanup-error";ContentResolver.instance.stream=object:java.io.ByteArrayOutputStream(){override fun close(){throw java.io.IOException("close failed")}};val r=save();picked(a);pump();check(r.count==1 && r.code==if(args[0]=="cleanup-error") "CLEANUP_FAILED" else "WRITE_FAILED");check(ContentResolver.instance.deletes==1);if(args[0]=="cleanup-error"){check("content://test/export" in SharedPreferences.values.getValue("uncommitted"));val again=save();check(again.code=="CLEANUP_FAILED")}}
   "slow-write", "slow-flush", "slow-close" -> {
    val entered=java.util.concurrent.CountDownLatch(1);val release=java.util.concurrent.CountDownLatch(1)
    fun block(stage:String){if(args[0]=="slow-"+stage){entered.countDown();check(release.await(5,java.util.concurrent.TimeUnit.SECONDS))}}
    ContentResolver.instance.stream=object:java.io.ByteArrayOutputStream(){override fun write(b:ByteArray,o:Int,n:Int){block("write");super.write(b,o,n)};override fun flush(){block("flush")};override fun close(){block("close")}}
    val r=save();picked(a);check(entered.await(2,java.util.concurrent.TimeUnit.SECONDS));check(r.count==0){"must not acknowledge before close"}
    val cancel=call("cancelExportFile",mapOf("operationId" to "test-op"));check(cancel.count==1)
    Handler.fireTimers();check(r.count==1 && r.code=="CLEANUP_FAILED"){"blocked provider timeout must report unresolved cleanup"}
    val again=save();check(again.code=="UNAVAILABLE"){"blocked provider must retain admission slot"}
    release.countDown();pump();check(ContentResolver.instance.deletes==1);check(r.count==1){"late completion must not reply twice"};check(SharedPreferences.values["uncommitted"].isNullOrEmpty())
   }
   "cancel-write", "destroy-write" -> {
    val entered=java.util.concurrent.CountDownLatch(1);val release=java.util.concurrent.CountDownLatch(1)
    ContentResolver.instance.stream=object:java.io.ByteArrayOutputStream(){override fun write(b:ByteArray,o:Int,n:Int){entered.countDown();check(release.await(5,java.util.concurrent.TimeUnit.SECONDS));super.write(b,o,n)}}
    val r=save();picked(a);check(entered.await(2,java.util.concurrent.TimeUnit.SECONDS));if(args[0]=="destroy-write") {a.onDestroy();activity()} else call("cancelExportFile",mapOf("operationId" to "test-op"));release.countDown();pump();check(r.code=="CANCELLED" && r.count==1);check(ContentResolver.instance.deletes==1)
   }
   "destroy-ready" -> {val r=save();picked(a);pump();check(r.value!=null);a.onDestroy();pump();val b=activity();val finish=call("finishExportFile",mapOf("location" to r.value,"discard" to false));check(finish.code=="CLEANUP_FAILED");check(ContentResolver.instance.deletes==1);check(SharedPreferences.values["uncommitted"].isNullOrEmpty())}
   "prepare-restart" -> {val r=save();picked(a);pump();check(r.value!=null);check("content://test/export" in SharedPreferences.values.getValue("uncommitted"))}
   "restart-denied" -> {check(ContentResolver.instance.deletes==1);check("content://test/export" in SharedPreferences.values.getValue("uncommitted"));check(save().code=="CLEANUP_FAILED")}
   "chunks" -> {val sizes=mutableListOf<Int>();ContentResolver.instance.stream=object:java.io.OutputStream(){override fun write(b:Int){error("single-byte fallback")};override fun write(b:ByteArray,o:Int,n:Int){sizes.add(n)}};val r=save(ByteArray(131073));picked(a);pump();check(sizes==listOf(65536,65536,1));check(r.value!=null)}
   "limit" -> {val r=save(ByteArray(16*1024*1024));check(a.launched!=null && r.count==0);a.onActivityResult(4172,0,null);pump();check(r.count==1 && r.code==null)}
   "foreign-cancel" -> {val r=save();call("cancelExportFile",mapOf("operationId" to "other-op"));picked(a);pump();check(r.code==null && r.value!=null)}
   "restart" -> {check(ContentResolver.instance.deletes==1){"fresh process must reconcile uncommitted URI"};check(SharedPreferences.values["uncommitted"].isNullOrEmpty());check(save().code==null)}
   "prepare-picker" -> {save();check("pending-picker" in SharedPreferences.values.getValue("uncommitted"))}
   "restart-picker" -> {picked(a);pump();check(ContentResolver.instance.deletes==1){"callback racing startup recovery must clean orphan URI"};check(SharedPreferences.values["uncommitted"].isNullOrEmpty())}
   "destroy" -> {val r=save();a.onDestroy();pump();check(r.count==1 && r.code=="CANCELLED") {"destroy must settle surviving result as CANCELLED, got ${r.count}/${r.code}"};val b=activity();picked(b);pump();check(ContentResolver.instance.deletes==1){"late picker document must be discarded"}}
   "oversize" -> {val r=save(ByteArray(16*1024*1024+1));pump();check(r.code=="PAYLOAD_TOO_LARGE" && a.launched==null){"oversize must be rejected before picker, got ${r.code}"}}
   "worker" -> {val r=save();picked(a);pump();check(ContentResolver.instance.openedOn!="main"){"provider opened synchronously on UI callback"};check(r.count==1 && r.code==null){"write did not complete"}}
  }
  println("PASS ${args[0]}");kotlin.system.exitProcess(0)
 } catch(t:Throwable){t.printStackTrace();kotlin.system.exitProcess(1)}
}
