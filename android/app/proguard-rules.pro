# R8 / ProGuard keep rules.
#
# Added 2026-08-24 for google_mlkit_text_recognition. Without these the release
# build FAILS — not warns — at :app:minifyReleaseWithR8:
#
#   Missing class com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
#
# The Flutter plugin's Android side references the recognizer options for every
# script ML Kit supports — Chinese, Devanagari, Japanese, Korean — and picks one
# at runtime from the MethodCall. Only the Latin recognizer is on the classpath,
# because only `com.google.mlkit:text-recognition` is pulled in, so R8 sees
# references it cannot resolve and refuses to finish.
#
# -dontwarn is the correct response, not a workaround: those code paths are
# genuinely unreachable here. The alternative — adding the four script-specific
# ML Kit artifacts to satisfy R8 — would bundle four OCR models this app never
# invokes, on an APK that is already 82.6 MB.
#
# ⚠ If a future version of the plugin adds a script, this list goes stale and
# the release build breaks again with the same error naming the new class. The
# fix is to add it here; AGP regenerates the exact lines needed at
# build/app/outputs/mapping/release/missing_rules.txt.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
