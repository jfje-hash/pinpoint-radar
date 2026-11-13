#!/usr/bin/env bash
# 핀포인트 레이더 안드로이드 앱(APK) 만들기
# 같은 폴더의 웹 화면(index.html 등)을 앱 안에 넣고 안드로이드 프로젝트를 만든 뒤 빌드한다.
# GitHub Actions(.github/workflows/app.yml)가 자동으로 실행한다. 노트북에서 직접 돌리려면 JDK 17, Gradle 8.7, Android SDK가 필요하다.
set -euo pipefail
cd "$(dirname "$0")"
for f in index.html manifest.webmanifest icon-maskable-512.png; do
  [ -f "$f" ] || { echo "::error::$f 파일이 저장소 맨 위에 없어요. 웹 파일을 먼저 올려 주세요."; exit 1; }
done

A=android
rm -rf "$A"
mkdir -p "$A/app/src/main/java/com/pinpoint/radar" "$A/app/src/main/assets/www" \
         "$A/app/src/main/res/values" "$A/app/src/main/res/mipmap-anydpi-v26" "$A/app/src/main/res/drawable-nodpi"

# 1) 웹 화면(감시 에이전트)을 앱 안에 넣는다
cp index.html manifest.webmanifest icon-*.png "$A/app/src/main/assets/www/"
cp icon-maskable-512.png "$A/app/src/main/res/drawable-nodpi/ic_launcher_fg.png"

# 2) 빌드 설정(Android Gradle Plugin 8.5.2 · Gradle 8.7 · JDK 17)
cat > "$A/settings.gradle" <<'EOF_SETTINGS'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = 'PinpointRadar'
include ':app'
EOF_SETTINGS

cat > "$A/build.gradle" <<'EOF_ROOT'
plugins {
    id 'com.android.application' version '8.5.2' apply false
}
EOF_ROOT

cat > "$A/gradle.properties" <<'EOF_PROPS'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.nonTransitiveRClass=true
EOF_PROPS

cat > "$A/app/build.gradle" <<'EOF_APP'
plugins {
    id 'com.android.application'
}

def buildNo = (System.getenv('GITHUB_RUN_NUMBER') ?: '1').toInteger()   // GitHub 빌드 번호 = 앱 버전(새 버전을 덮어 설치할 수 있게)

android {
    namespace 'com.pinpoint.radar'
    compileSdk 34

    defaultConfig {
        applicationId 'com.pinpoint.radar'
        minSdk 26
        targetSdk 34
        versionCode buildNo
        versionName "1.${buildNo}"
    }

    signingConfigs {
        release {
            storeFile file('pinpoint.jks')
            storePassword 'pinpoint-radar'
            keyAlias 'pinpoint'
            keyPassword 'pinpoint-radar'
        }
    }

    buildTypes {
        release {
            minifyEnabled false
            signingConfig signingConfigs.release
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }

    lint {
        checkReleaseBuilds false
        abortOnError false
    }
}
EOF_APP

# 3) 앱 정보: 권한(카메라·인터넷·진동), 화면 방향이 바뀌어도 감시가 끊기지 않게
cat > "$A/app/src/main/AndroidManifest.xml" <<'EOF_MANIFEST'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.VIBRATE" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />

    <queries>
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE" />
        </intent>
    </queries>

    <application
        android:label="@string/app_name"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher"
        android:theme="@style/AppTheme"
        android:allowBackup="false"
        android:hardwareAccelerated="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTask"
            android:configChanges="orientation|screenSize|screenLayout|smallestScreenSize|keyboard|keyboardHidden|navigation|uiMode|density"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF_MANIFEST

cat > "$A/app/src/main/res/values/strings.xml" <<'EOF_STRINGS'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">핀포인트 레이더</string>
</resources>
EOF_STRINGS

cat > "$A/app/src/main/res/values/styles.xml" <<'EOF_STYLES'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme" parent="android:Theme.Material.NoActionBar">
        <item name="android:windowBackground">@android:color/black</item>
        <item name="android:statusBarColor">@android:color/black</item>
        <item name="android:navigationBarColor">@android:color/black</item>
        <item name="android:colorAccent">#FFD447</item>
    </style>
</resources>
EOF_STYLES

cat > "$A/app/src/main/res/values/colors.xml" <<'EOF_COLORS'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="icon_bg">#000000</color>
</resources>
EOF_COLORS

cat > "$A/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml" <<'EOF_ICON'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/icon_bg" />
    <foreground android:drawable="@drawable/ic_launcher_fg" />
</adaptive-icon>
EOF_ICON

# 4) 앱 코드: 웹 화면을 띄우고 카메라 권한·파일 고르기·음성·진동·사진 저장을 휴대폰 기능으로 연결
cat > "$A/app/src/main/java/com/pinpoint/radar/MainActivity.java" <<'EOF_JAVA'
package com.pinpoint.radar;

import android.Manifest;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.provider.MediaStore;
import android.speech.tts.TextToSpeech;
import android.util.Base64;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * 핀포인트 레이더 안드로이드 앱.
 * 감시 에이전트(웹 화면 www/index.html)를 앱 안에 넣어 두고 WebView로 띄운다.
 * - 앱 안의 파일을 https://appassets.androidplatform.net/ 주소로 열어 카메라(보안 연결 필요)를 쓸 수 있게 한다.
 * - 카메라 권한, 영상 파일 고르기, 음성 안내(휴대폰 TTS), 진동, 사진 저장, 화면 꺼짐 방지를 휴대폰 기능으로 연결한다.
 * - AI 모델은 처음 실행할 때 인터넷에서 받아 휴대폰에 캐시한다. 영상은 휴대폰 밖으로 보내지 않는다.
 */
public class MainActivity extends Activity {
    private static final String HOST = "appassets.androidplatform.net";
    private static final String START = "https://" + HOST + "/www/index.html";
    private static final int REQ_CAMERA = 1;
    private static final int REQ_FILE = 2;

    private WebView web;
    private PermissionRequest pendingPermission;
    private ValueCallback<Uri[]> fileCallback;
    private TextToSpeech tts;
    private boolean ttsReady;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);   // 감시 중 화면 꺼짐 방지
        WebView.setWebContentsDebuggingEnabled(true);   // 노트북 크롬(chrome://inspect)에서 문제를 볼 수 있게
        web = new WebView(this);
        web.setBackgroundColor(0xFF000000);
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);                    // 대상·설정·등록 인물 저장
        s.setMediaPlaybackRequiresUserGesture(false);    // 카메라 영상·경보음 자동 재생
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(true);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);        // AI 모델을 한 번 받으면 캐시에서 다시 쓴다

        web.addJavascriptInterface(new Bridge(), "PinpointNative");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                Uri u = request.getUrl();
                if (!HOST.equals(u.getHost())) return null;   // 그 밖의 주소(AI 모델 CDN 등)는 인터넷에서
                String path = u.getPath();
                if (path == null || path.equals("/") || path.isEmpty()) path = "/www/index.html";
                Map<String, String> headers = new HashMap<>();
                headers.put("Cache-Control", "no-cache");
                headers.put("Access-Control-Allow-Origin", "*");
                try {
                    InputStream in = getAssets().open(path.substring(1));
                    String type = mime(path);
                    return new WebResourceResponse(type, type.startsWith("text/") ? "utf-8" : null, 200, "OK", headers, in);
                } catch (IOException e) {
                    return new WebResourceResponse("text/plain", "utf-8", 404, "Not Found", headers, null);
                }
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri u = request.getUrl();
                if (HOST.equals(u.getHost())) return false;
                try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (ActivityNotFoundException e) { /* 열 앱이 없으면 무시 */ }
                return true;   // 바깥 링크는 브라우저로
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                runOnUiThread(() -> handlePermission(request));
            }

            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (fileCallback != null) fileCallback.onReceiveValue(null);
                fileCallback = callback;
                // 웹 화면이 원하는 종류(영상·사진)대로, '여러 장 고르기'면 여러 장을 고를 수 있게(사진으로 인물 등록)
                String[] types = mimeTypes(params == null ? null : params.getAcceptTypes());
                Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType(types.length == 1 ? types[0] : "*/*");
                if (types.length > 1) i.putExtra(Intent.EXTRA_MIME_TYPES, types);
                if (params != null && params.getMode() == FileChooserParams.MODE_OPEN_MULTIPLE) i.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
                try {
                    startActivityForResult(i, REQ_FILE);
                } catch (ActivityNotFoundException e) {
                    fileCallback = null;
                    return false;
                }
                return true;
            }
        });

        tts = new TextToSpeech(this, status -> {
            ttsReady = status == TextToSpeech.SUCCESS;
            if (ttsReady) tts.setLanguage(Locale.KOREAN);
        });

        web.loadUrl(START);
    }

    private static String[] mimeTypes(String[] accept) {   // "image/*,video/*" 같은 accept 값 → 종류 목록
        ArrayList<String> out = new ArrayList<>();
        if (accept != null) for (String a : accept) {
            if (a == null) continue;
            for (String t : a.split(",")) { t = t.trim(); if (t.contains("/")) out.add(t); }
        }
        if (out.isEmpty()) { out.add("video/*"); out.add("image/*"); }
        return out.toArray(new String[0]);
    }

    private static String mime(String path) {
        String p = path.toLowerCase(Locale.ROOT);
        if (p.endsWith(".html")) return "text/html";
        if (p.endsWith(".js") || p.endsWith(".mjs")) return "text/javascript";
        if (p.endsWith(".css")) return "text/css";
        if (p.endsWith(".json") || p.endsWith(".webmanifest")) return "application/json";
        if (p.endsWith(".png")) return "image/png";
        if (p.endsWith(".svg")) return "image/svg+xml";
        if (p.endsWith(".wasm")) return "application/wasm";
        return "application/octet-stream";
    }

    // 웹 화면이 카메라를 달라고 하면: 앱 카메라 권한이 있으면 바로 허용, 없으면 휴대폰 권한 창을 띄운다
    private void handlePermission(PermissionRequest request) {
        boolean wantsCamera = false;
        for (String r : request.getResources()) {
            if (PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(r)) wantsCamera = true;
        }
        if (!wantsCamera || request.getOrigin() == null || !HOST.equals(request.getOrigin().getHost())) {
            request.deny();
            return;
        }
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            request.grant(new String[]{PermissionRequest.RESOURCE_VIDEO_CAPTURE});
        } else {
            if (pendingPermission != null) pendingPermission.deny();
            pendingPermission = request;
            requestPermissions(new String[]{Manifest.permission.CAMERA}, REQ_CAMERA);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (requestCode != REQ_CAMERA || pendingPermission == null) return;
        if (results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) {
            pendingPermission.grant(new String[]{PermissionRequest.RESOURCE_VIDEO_CAPTURE});
        } else {
            pendingPermission.deny();
            Toast.makeText(this, "카메라 권한이 있어야 감시할 수 있어요. 설정 → 애플리케이션 → 핀포인트 레이더 → 권한에서 켜 주세요.", Toast.LENGTH_LONG).show();
        }
        pendingPermission = null;
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQ_FILE && fileCallback != null) {
            Uri[] picked = null;
            if (resultCode == RESULT_OK && data != null) {
                ClipData clip = data.getClipData();   // 여러 장을 골랐으면 ClipData에 담겨 온다
                if (clip != null && clip.getItemCount() > 0) {
                    picked = new Uri[clip.getItemCount()];
                    for (int k = 0; k < picked.length; k++) picked[k] = clip.getItemAt(k).getUri();
                } else if (data.getData() != null) {
                    picked = new Uri[]{data.getData()};
                }
            }
            fileCallback.onReceiveValue(picked);
            fileCallback = null;
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    // 뒤로 가기: 열린 창(대상·설정·사진)이 있으면 닫고, 없으면 앱을 나간다
    @Override
    public void onBackPressed() {
        web.evaluateJavascript(
            "(function(){var o=document.querySelector('.sheet.open')||document.querySelector('#viewer:not([hidden])');"
                + "if(o){document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));return true}return false})()",
            value -> { if (!"true".equals(value)) super.onBackPressed(); });
    }

    @Override
    protected void onPause() {
        super.onPause();
        web.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        web.onResume();
    }

    @Override
    protected void onDestroy() {
        if (tts != null) tts.shutdown();
        if (web != null) web.destroy();
        super.onDestroy();
    }

    private void toast(final String text) {
        runOnUiThread(() -> Toast.makeText(MainActivity.this, text, Toast.LENGTH_SHORT).show());
    }

    /** 웹 화면에서 window.PinpointNative 로 부르는 휴대폰 기능 */
    private class Bridge {
        @JavascriptInterface
        public boolean isApp() {
            return true;
        }

        @JavascriptInterface
        public void speak(String text) {   // 음성 안내: 휴대폰의 한국어 음성 엔진
            if (ttsReady && text != null) tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "pinpoint");
        }

        @JavascriptInterface
        public void vibrate(String pattern) {   // 웹의 진동 패턴 [켜짐, 꺼짐, 켜짐 …] 그대로
            try {
                Vibrator v = (Vibrator) getSystemService(VIBRATOR_SERVICE);
                if (v == null || !v.hasVibrator() || pattern == null) return;
                String[] parts = pattern.replaceAll("[\\[\\]\\s]", "").split(",");
                long[] timings = new long[parts.length + 1];   // 안드로이드는 '처음 기다림'부터 센다
                for (int i = 0; i < parts.length; i++) timings[i + 1] = Math.max(0L, Math.round(Double.parseDouble(parts[i])));
                v.vibrate(VibrationEffect.createWaveform(timings, -1));
            } catch (Exception e) {
                // 잘못된 패턴은 무시
            }
        }

        @JavascriptInterface
        public void saveImage(String dataUrl, String name) {   // 경보 사진을 사진첩(Pictures/Pinpoint)에 저장
            if (Build.VERSION.SDK_INT < 29) {
                toast("안드로이드 10 이상에서 저장할 수 있어요");
                return;
            }
            try {
                byte[] bytes = Base64.decode(dataUrl.substring(dataUrl.indexOf(',') + 1), Base64.DEFAULT);
                ContentValues cv = new ContentValues();
                cv.put(MediaStore.Images.Media.DISPLAY_NAME, name == null || name.isEmpty() ? "pinpoint.jpg" : name);
                cv.put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg");
                cv.put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Pinpoint");
                Uri uri = getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cv);
                if (uri == null) throw new IOException("저장 위치를 만들지 못함");
                try (OutputStream out = getContentResolver().openOutputStream(uri)) {
                    if (out == null) throw new IOException("파일을 열지 못함");
                    out.write(bytes);
                }
                toast("사진첩(Pictures/Pinpoint)에 저장했어요");
            } catch (Exception e) {
                toast("사진을 저장하지 못했어요");
            }
        }
    }
}
EOF_JAVA

# 5) 서명 열쇠(고정): 새 버전을 지우지 않고 덮어 설치할 수 있게 항상 같은 열쇠로 서명한다
base64 -d > "$A/app/pinpoint.jks" <<'EOF_KEY'
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
EOF_KEY

# 6) 빌드
(cd "$A" && gradle --no-daemon --stacktrace assembleRelease)
cp "$A/app/build/outputs/apk/release/app-release.apk" pinpoint-radar.apk
echo "완성: pinpoint-radar.apk ($(du -h pinpoint-radar.apk | cut -f1))"
