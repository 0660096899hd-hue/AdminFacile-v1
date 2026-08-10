# AdminFacile utilise exclusivement TextRecognitionScript.latin.
# Le plugin Flutter contient des branches optionnelles vers ces modules ML Kit
# non embarqués ; R8 doit donc ignorer leurs types absents.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# Firebase ComponentDiscovery instancie les registrars ML Kit par réflexion via
# leur constructeur public sans argument. La règle consumer ML Kit conserve le
# nom des classes, mais R8 peut supprimer ces constructeurs en release.
-keepclassmembers class * implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
