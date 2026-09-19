package android.os
class StatFs(path:String) {val availableBytes=100000L}
class Looper {companion object {fun getMainLooper()=Looper()}}
class Handler(looper:Looper=Looper()) {
 companion object { val queue=java.util.concurrent.ConcurrentLinkedQueue<Runnable>();val timers=java.util.concurrent.ConcurrentLinkedQueue<Runnable>();fun drain(){while(true){(queue.poll() ?: break).run()}};fun fireTimers(){val copy=timers.toList();timers.clear();copy.forEach{it.run()}} }
 fun post(r:Runnable):Boolean {queue.add(r);return true}
 fun postDelayed(r:Runnable,ms:Long):Boolean {timers.add(r);return true}
 fun removeCallbacks(r:Runnable) {timers.remove(r)}
}
