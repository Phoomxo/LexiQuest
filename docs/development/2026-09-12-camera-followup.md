# Camera model follow-up — 2026-09-12

## Decision

**คง MobileNet baseline ที่แอป pin อยู่ ไม่เปลี่ยนเป็นโมเดลทดลองสี่คลาสในตอนนี้** Pilot ให้ผลดีขึ้นบนสี่คลาสเดิม แต่ไม่มี unknown class และเกณฑ์ confidence ปัจจุบัน0.15ไม่สามารถปฏิเสธผลของsoftmaxสี่คลาสได้: ความน่าจะเป็นสูงสุดต้องไม่น้อยกว่า0.25เมื่อผลรวมเป็น1 การปรับthresholdต้องมีvalidation unknownที่เป็นอิสระ ไม่ใช้test40ภาพปรับเกณฑ์

Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`. อ่าน AGENTS, priority7–12 checkpoint, camera-pilot plan และ runtime preprocessing/manifest/benchmarkจริงแล้ว ไม่แก้โมเดลหรือruntime ไม่ใช้ADB ไม่รันFlutter/build ไม่ดาวน์โหลดหรือtrainใหม่ ไม่มีpaidservice/ข้อมูลวิจัยจริง

## Frozen inputs and comparison

ใช้ชุดเดิม `build/verification/priority-12-openimages-20260911/manifest.json` SHA256 `7f451af57c765663dd6a25fcbead663b01a616c4a063350348fd752b35ab6be0`: 175ภาพ, train100/validation35/test40, test10ต่อbook/bottle/chair/cup. โหลดTFLiteเดิมจาก `build/verification/priority-12-training-20260911`:

| Model | bytes | SHA256 |
| --- | ---: | --- |
| pinned baseline, uint8 output1,001classes | 4,287,874 | d3949e8a3556c79739cb675e0be7476503bcce76938031c6a1048e13e0cb7d8b |
| unshipped pilot, float32 output4classes | 12,821,512 | eb39555e38ecb012c43a16b4300fbe323dfde84c939d22e4f80121fae473798a |

รอบนี้รันโมเดลจริงบนRGBbytesเดียวกันต่อคู่โมเดล ใช้Pillow EXIF orientation/RGB/bilinear224ทั้งคู่ สองpreprocessing: annotation objectcrop และfullframeที่cropสี่เหลี่ยมตรงกลาง ไม่อ้างว่าPillowbit-identicalกับDart `image.copyResizeCropSquare` จึงไม่รวมคะแนนกับDartรอบเก่า36/40. Baselineใช้canonicalsynonymsเดิมจากtrain scriptเช่น water bottle→bottle, coffee mug→cup, folding chair→chair ก่อนรัน ไม่เปลี่ยนmappingเพื่อไล่คะแนนหลังเห็นผล และไม่ใช้exactmapped-word2/40จากรอบเก่าเป็นbaselinevisionaccuracy

| Paired evaluation | Baseline | Pilot |
| --- | ---: | ---: |
| objectcrop,40held-out | 18/40 (45%) | 37/40 (92.5%) |
| fullframe center-crop,40held-out | 14/40 (35%) | 35/40 (87.5%) |
| fullframe recall book/bottle/chair/cup | 40/30/30/40% | 80/90/80/100% |

เป็นclosed-setสี่คลาสและtop1canonical ไม่ใช่accuracyทั้ง1,000ImageNetclassesหรือความแม่นยำกล้องvivo ภาพfullframeอาจมีวัตถุหลายชนิดและgroundtruthมาจากtargetboxเดิม ชื่อsubclassที่ไม่ได้อยู่ในmappingตายตัวอาจเสียคะแนนแม้มีความเกี่ยวข้อง ไม่มีstatistical significance/production accuracy claim และtestถูกใช้อ่านซ้ำจากการทดลองเดิม จึงไม่ใช่ชุดunseenใหม่

## Leakage and out-of-class limits

ตรวจsource IDs/group IDsไม่มีซ้ำ175รายการ, ไม่มีgroupข้ามsplit และตรวจSHAทุกimageตรงmanifest; cross-splitexactimagehashไม่ซ้ำ ไม่ได้train/tune/selectโมเดลใหม่ในรอบนี้ อย่างไรก็ตามgroupเดิมใช้sourceimageID จึงยังพิสูจน์near-duplicate scene independenceไม่ได้ และImageNetpretraining overlapกับOpenImagesไม่ทราบ **ไม่มีหลักฐานรับรองว่าไม่รั่วไหลทุกระดับ** มีเพียงการแยกsplit/ไฟล์ที่ตรวจยืนยันได้

ไม่มีnatural-photoout-of-four-classชุดที่ติดป้ายและแยกsplitอยู่ในpilotเดิม ใช้goldenUIสองภาพที่มีอยู่ในrepoและผู้ตรวจเปิดดูแล้วไม่มีวัตถุสี่ชนิด เป็นdiagnosticแยกจาก40test ไม่ใช่ตัวแทนภาพวัตถุจริง:

| Existing golden | Baseline raw label/confidence | Pilot label/confidence |
| --- | --- | --- |
| host_timeout_thai | web site /0.3203 | chair /0.4215 |
| host_result_thai_measured | web site /0.4766 | book /0.5971 |

Pilotตอบผิดเป็นknownclassทั้ง2/2และผ่าน0.15ทั้งหมด Baselineเลือกlabelนอกสี่คลาสทั้ง2 แต่ก็ผ่านconfidenceเช่นกัน ไม่แปลว่าbaselineมีunknownrejectionที่สมบูรณ์ การแยกOODด้วยcanonicalotherเป็นการให้คะแนนoffline ไม่ได้เพิ่มrejectbehaviorให้แอป

## Host latency and memory

รันPython3.12.14/TensorFlow2.20.0/NumPy2.5.3/Pillow12.3.0 ในenvที่มีอยู่ `C:/Users/Phet/.cache/lq12-20260911` บนWindows, interpreterthreads2, default CPU XNNPACK, inputเดียวกัน, warmup5/invoke50 ไม่มีการควบคุมโหลดงานอื่น/thermalและลำดับรันbaselineก่อนpilot จึงเป็นdescriptivehosttimingเท่านั้น

| Metric | Baseline | Pilot |
| --- | ---: | ---: |
| invoke-only median | 25.13ms | 14.42ms |
| invoke-only p90 | 30.78ms | 17.07ms |
| invoke-only p95 | 31.73ms | 18.51ms |
| fresh-process load+allocate | 10.74ms | 13.58ms |
| fresh-process first invoke | 22.72ms | 15.86ms |
| sampled RSS delta after allocation | 12,816,384B | 35,741,696B |
| sampled RSS delta peak after invokes | 13,160,448B | 36,925,440B |

Memoryวัดแยกfreshprocessต่อโมเดลหลังimportTensorFlowด้วยWindowsGetProcessMemoryInfo เป็นwholeprocessRSSsamples ไม่ใช่AndroidPSS/modelarenaหรือpeakต่อเนื่อง Pilotไฟล์ใหญ่ประมาณ2.99เท่า และRSSdeltaสูงกว่าในhostนี้ ข้อได้เปรียบความเร็วบนWindowsไม่ได้พิสูจน์vivoเร็วกว่า

## vivo benchmark handoff

Scratch `build/verification/system-followup-20260912/camera/vivo_benchmark.dart` เป็นฟังก์ชันharnessใช้runtimeจริงที่มีอยู่ ตรวจPlatformAndroid, modelSHA/bytesและRGBSHAก่อนload; บันทึกload+allocate, first run, warmup5/measured50 median/p90/min/max, sampledRSSก่อน/หลังload/หลังfirst/peak/หลังclose, top1,delegate,OSและdevice description. รองรับmanifestbaselineเดิมและlocalPilotManifestที่backgroundnull/outputfloat32. **ยังไม่compileหรือexecuteบนdevice**; rootต้องvalidateintegrationก่อนเรียก ไม่แสดงผลนี้เป็นdeviceevidenceล่วงหน้า

ขั้นตอนให้rootรันเมื่อเครื่องพร้อม:

1. ใช้integration/diagnosticentryแยกจากappreleaseผ่านscratchharnessนี้ ไม่แทนที่manifestหลัก ตรวจเครื่องvivo/Androidversion, appcommit/buildmode, modelSHA, fixtureSHA,threads2; บันทึกbattery/thermalและโหมดประหยัดพลังงานตามจริง ห้ามใช้เลขserial/PIIในผลสาธารณะ
2. ใช้rawRGBfixtureเดิมจาก `priority-12-training-20260911/native-fixtures.json` และไฟล์validation-book/bottle/chair/cup.rgbทั้งสองโมเดล **performancefixturesมาจากvalidation ไม่อ้างheld-outaccuracy**; checksumแต่ละไฟล์อยู่manifestนั้น หากวัดfullpipelineเพิ่มให้ใช้encodedtest40ภาพเดียวกันทั้งโมเดลและDartImagePreprocessorจริง แยกdecode/preprocess/inference/labelmappingออกจากเวลาเปิดcamera
3. เปิดโมเดลทีละตัวในfreshappprocess โดยสลับลำดับA/Bแล้วB/Aอย่างน้อยสามคู่ วัดCPUและXNNPACKแยกกัน อย่าโหลดสองโมเดลพร้อมกันขณะวัดmemory;harnessเรียกหนึ่งmodel/delegate/fixtureต่อครั้ง เก็บJSONreturnลงไฟล์evidenceของroot ปิดruntimeในfinallyทุกครั้ง
4. ต่อคู่model/delegateรันfixtureทั้ง4ด้วยwarmup5/measured50 บันทึกfirst-loadและfirst-runแยกจากwarm;รายงานmedian/p90และRSSdeltaพร้อมbaselineRSS การอ่านRSSหลังcloseไม่ใช่หลักฐานไม่มีleak;ใช้repeatedopen/closeและtrendประกอบ
5. ตรวจcrash/invalidtensor/nonfinite/label0ถูกตัดผิด;เปิดscannerปกติอีกครั้งเพื่อยืนยันbaselineยังเป็นตัวหลัก แยกcapture/lighting/backpressure/UI responsiveness testsที่ต้องมีกล้องจริงและวัตถุจริง ไม่ใช้goldenUIผ่านจอแทนphysicalacceptance

เงื่อนไขก่อนพิจารณาเปลี่ยน: representativeknown/unknown natural-image validation/testที่แยกcapturegroups, threshold/rejectdesignที่เลือกจากvalidation, labelcontractครบproductscope, pairedphysicalvivoaccuracyภายใต้หลายแสง/ระยะ/มุม, latency/memoryตามbudgetที่rootกำหนดก่อนรับผล และrollback/versionedrolloutที่ได้รับอนุญาต Pilotปัจจุบันมีเพียง4คำจึงลดcoverageหากแทนbaselineโดยตรง ไม่เสนอpermanentruntime/tools/modelchangesในรอบนี้; หากจะเพิ่มunknownheadหรือfallbackroutingต้องเสนอdesignและacceptanceก่อนแก้

## Evidence and verification

Scratchไฟล์: evaluate.py/results.json, memory_probe.py/memory-baseline.json/memory-candidate.json, vivo_benchmark.dart, validate_evidence.py. Resultsมีpairedpredictions82preprocessingcasesจาก40testimages+2OODgoldens, rawlabels/confidence/inputhashesและartifactprovenanceครบ

รันด้วยenvข้างต้น: evaluate.py; memory_probe.py baseline; memory_probe.py candidate แล้วรัน validate_evidence.py เพื่อตรวจcounts/scorearithmetic/model+manifestidentity ปัญหาเริ่มต้นimporttrain CLIมีsys.argv sideeffect แก้เฉพาะscratchโดยคัดcanonicalmappingเดิม ไม่รันtraining ไม่เปลี่ยนpermanenttool. TensorFlowแจ้งInterpreterdeprecation; ไม่เปลี่ยนdependencyในงานนี้

Rootขอminimalmanualbutton entryเพิ่มเติม: `benchmarkStagedCameraModel` รับstagedDirectory/candidate/delegate/deviceDescription แล้วอ่านapp-privateไฟล์ baseline.tfliteหรือcandidate.tflite และvalidation-book.rgbก่อนตรวจhash ฟังก์ชันคืนMapให้rootjsonEncodeแสดง/บันทึกเอง ไม่เขียนdevicefilesystemหรือเปลี่ยนmanifest หลัก actualrepoใช้flutter_litert3.7.0 จึงreuseLiteRtImageClassifierแทนเพิ่มtflite_flutterdependency ไฟล์RGB150,528bytes SHA256 `ff711f5c5752447ed2cfe0cab02700bf774ab73c827b9f6188ea30e259237129` ตรวจfreshแล้วตรงmanifestเดิม

Final validation: PASS82pairedcases/40distincttestimages, arithmeticและmodel/manifest identitiesตรง; documentdiffcheckไม่มีwhitespaceerror มีเพียงLF/CRLFadvisory. results.json SHA256 `1dc14bd4d7e3c4bb5f8a36cd0574b1476e240c486429ab95d86caec62488f769`; vivo_benchmark.dart SHA256 `9de32bd55e0376dd08942a40334bbeaa22d5944d485e443edeb4eb508d9805b2`.

งานนี้ไม่มีADB/Flutter/build/train/downloadprocessค้าง ไม่มีphysicalcamera/lighting/vivoผลใหม่ และไม่มีshippedmodel/runtimeแก้ การตัดสินคงbaselineเป็นข้อสรุปปัจจุบันจากหลักฐานและช่องว่างที่ระบุ ไม่ใช่การยืนยันbaselineสมบูรณ์แบบ

## ผล vivo ที่ root วัดหลัง handoff

ข้อความส่วนก่อนหน้าเป็นสถานะตอน agent ส่งงาน; root ต่อ benchmark บน V2041/API33
ด้วย manual R13 version22 แล้วสำเร็จ **12 fresh processes**, CPU/default และ
explicit XNNPACK อย่างละ 3 ครั้งต่อโมเดล สลับลำดับ A/B, B/A, A/B.
แต่ละ process ตรวจ model/input SHA ก่อนเปิด ใช้ validation-book RGB224 เดียวกัน,
warmup5 และ measured50. ทุกครั้งไม่มี AndroidRuntime/flutter error.
Raw evidence `build/verification/system-followup-20260912/camera/vivo-01.json`
ถึง `vivo-12.json`; aggregate `vivo-summary.json` ตรวจ counts/identities/finite
metrics และ hashes ของทุก raw record แล้ว. บันทึก thermal/battery/power-save
ก่อนแต่ละรอบ; power-save เป็น 0 ทั้งหมด.

ค่ากลางของแต่ละตัวเลขจาก 3 process:

| โมเดล/วิธี | โหลด ms | ครั้งแรก ms | warm median ms | warm p90 ms | sampled RSS เพิ่ม MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| baseline/default CPU | 61.300 | 135.148 | 25.607 | 27.715 | 9.03 |
| pilot/default CPU | 59.967 | 485.787 | 99.766 | 128.327 | 39.19 |
| baseline/explicit XNNPACK | 98.350 | 67.393 | 36.405 | 37.166 | 18.51 |
| pilot/explicit XNNPACK | 75.115 | 53.677 | 21.282 | 23.434 | 38.41 |

CPU/default หมายถึงไม่ได้แนบ delegate เอง ไม่ได้พิสูจน์ว่า native backend ปิด
XNNPACK ภายใน. Debug/runtime timing รวม tensor copying แต่ไม่รวม camera capture
หรือ preprocessing; RSS เป็น whole-process sampled growth ไม่ใช่ model-only หรือ
continuous peak. Pilot CPU p90 ต่างระหว่าง process 108.995–300.457ms จึงไม่ควร
รายงานค่ากลางอย่างเดียวเป็น latency guarantee. ไม่มีการนับภาพ book ซ้ำเป็น
independent accuracy sample และไม่มี physical object/lighting acceptance.

**คง baseline**: pilot มีประโยชน์ด้านความเร็วเมื่อใช้ explicit XNNPACK และแม่นกว่า
ในชุดภาพ 4 คลาสเดิม แต่ default CPU ช้ากว่า ใช้ไฟล์/หน่วยความจำมากกว่า ลด coverage
และยังไม่มี unknown rejection ที่ใช้ได้. ไม่มีการเปลี่ยน shipped manifest/runtime
หรือปรับค่าตาม test set. R14 แก้ Pair replay timestamp เท่านั้น; benchmark/model
runtime/helper bytes ต้องตรวจเทียบ source pins ก่อนอ้างความเกี่ยวข้องกับ R14.

ข้อผิดพลาดเครื่องมือรอบแรก: uiautomator dump ยังไม่พร้อมหลัง cold launch 3s,
ยังไม่ได้กด benchmark และไม่มี result file. Root ตรวจ process/staged files แล้ว
ปรับช่วงรอเริ่มต้นเป็น 6s; รัน sequence01 ใหม่สำเร็จ ไม่มีการส่งซ้ำ benchmark ที่
ผลลัพธ์ไม่แน่นอนหรือแก้กฎการตรวจ model hash.
