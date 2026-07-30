# WorkManager creates its Room database implementation by reflection before
# Flutter starts. R8 can otherwise remove the zero-argument constructor and
# make an otherwise valid release APK crash in InitializationProvider.
-keep class androidx.work.impl.WorkDatabase_Impl {
    <init>();
}
