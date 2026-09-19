"""Run real MainActivity dispatch with JVM Android/Flutter boundary fixtures, offline."""
from pathlib import Path
import subprocess,os,json,hashlib,uuid,sys
root=Path(__file__).resolve().parents[3]
cache=Path.home()/'.gradle/caches/modules-2/files-2.1'
def jar(group,artifact,version):
 matches=list((cache/group/artifact/version).glob('*/*.jar'))
 if len(matches)!=1:raise RuntimeError(f'Expected one cached {artifact} {version}, got {len(matches)}')
 return matches[0]
compiler=jar('org.jetbrains.kotlin','kotlin-compiler-embeddable','2.2.20')
stdlib=jar('org.jetbrains.kotlin','kotlin-stdlib','2.2.20')
cp=[compiler,stdlib,jar('org.jetbrains.kotlin','kotlin-script-runtime','2.2.20'),jar('org.jetbrains.kotlin','kotlin-reflect','1.6.10'),jar('org.jetbrains.kotlinx','kotlinx-coroutines-core-jvm','1.8.0'),jar('org.jetbrains','annotations','13.0')]
output=root/'build/f02-native'/uuid.uuid4().hex;output.mkdir(parents=True)
fixtures=Path(__file__).parent/'fixtures/android-export'
sources=list(fixtures.glob('*.kt'))+list((root/'android/app/src/main/kotlin/com/lexiquest/app').glob('*.kt'))
cmd=['java','-cp',os.pathsep.join(map(str,cp)),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-classpath',os.pathsep.join(map(str,[stdlib,cp[-1]])),'-d',str(output/'classes'),*map(str,sources)]
r=subprocess.run(cmd,capture_output=True,timeout=90)
(output/'compile.stdout').write_bytes(r.stdout);(output/'compile.stderr').write_bytes(r.stderr)
if r.returncode:print(r.stderr.decode(errors='replace'));sys.exit(r.returncode)
# Compile production against installed real SDK/Flutter APIs as well; no Gradle,
# APK packaging, device execution, downloads or full Android build.
android=Path(os.environ['LOCALAPPDATA'])/'Android/Sdk/platforms/android-36/android.jar'
flutter=Path(os.environ['LOCALAPPDATA'])/'Programs/flutter/bin/cache/artifacts/engine/android-arm64/flutter.jar'
api_cp=[stdlib,cp[-1],android,flutter]
api_cp.append(jar('androidx.lifecycle','lifecycle-common','2.7.0'))
production=list((root/'android/app/src/main/kotlin/com/lexiquest/app').glob('*.kt'))
api_cmd=cmd[:cmd.index('-classpath')]+['-classpath',os.pathsep.join(map(str,api_cp)),'-d',str(output/'api-classes'),*map(str,production)]
api=subprocess.run(api_cmd,capture_output=True,timeout=90)
(output/'api.stdout').write_bytes(api.stdout);(output/'api.stderr').write_bytes(api.stderr)
if api.returncode:print(api.stderr.decode(errors='replace'));sys.exit(api.returncode)
failed=[]
for case in ['destroy','oversize','worker','positive','picker-cancel','close-error','cleanup-error','slow-write','slow-flush','slow-close','cancel-write','destroy-write','chunks','limit','foreign-cancel','destroy-ready','prepare-restart','restart-denied','restart','prepare-picker','restart-picker']:
 env=dict(os.environ)
 if case in ['prepare-restart','restart-denied','restart','prepare-picker','restart-picker']:env['F02_PREFS']=str(output/('picker.properties' if 'picker' in case else 'restart.properties'))
 r=subprocess.run(['java','-cp',os.pathsep.join(map(str,[output/'classes',stdlib])),'fixture.ExportHarnessKt',case],capture_output=True,timeout=15,env=env)
 (output/(case+'.stdout')).write_bytes(r.stdout);(output/(case+'.stderr')).write_bytes(r.stderr)
 print(r.stdout.decode(errors='replace'),r.stderr.decode(errors='replace'))
 if r.returncode:failed.append(case)
(output/'result.json').write_text(json.dumps({'failed':failed,'toolchainHashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in cp+api_cp},'sourceHashes':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}},indent=2))
print('Native evidence: '+str(output));sys.exit(bool(failed))

