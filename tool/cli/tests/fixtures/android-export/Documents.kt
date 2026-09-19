package android.provider
object DocumentsContract {fun deleteDocument(r:android.content.ContentResolver,u:android.net.Uri):Boolean {r.deletes++;return r.deleteOK}}
