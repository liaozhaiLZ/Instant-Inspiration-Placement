package com.lingan.quicknote;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.KeyEvent;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.Charset;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Date;
import java.util.Locale;

/**
 * 灵感速记 · 手机版
 *
 * 单个 Activity + 一个 WebView 装载 assets/index.html（同一份手机版网页），
 * 通过 LinganNative 这个 JS 桥把「灵感库」落到真实的 .txt 文件上：
 *   <应用外部私有目录>/files/灵感库/20261022-1240 标题.txt
 * 用系统分享面板可以把单条灵感发到微信 / 备忘录 / 邮件等任何地方。
 */
public class MainActivity extends Activity {

    private static final int REQ_PICK = 1001;

    private WebView web;
    private File dir;
    private ValueCallback<Uri[]> fileCallback;

    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        File base = getExternalFilesDir(null);
        if (base == null) {
            // 没有外部存储权限 / 未挂载时退回应用内部目录，保证仍然能写盘
            base = getFilesDir();
        }
        dir = new File(base, "灵感库");
        if (!dir.exists()) {
            //noinspection ResultOfMethodCallIgnored
            dir.mkdirs();
        }

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setTextZoom(100);
        web.setBackgroundColor(0xFF121317);
        web.setWebViewClient(new WebViewClient());
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                // 页面里的「打开文件」用的是 <input type="file">，
                // WebView 默认不会弹选择器，这里接到系统的文件选择界面
                if (fileCallback != null) {
                    fileCallback.onReceiveValue(null);
                }
                fileCallback = callback;
                boolean wantImage = false;
                String[] accept = params == null ? null : params.getAcceptTypes();
                if (accept != null) {
                    for (String a : accept) {
                        if (a != null && a.indexOf("image") >= 0) { wantImage = true; break; }
                    }
                }
                Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType(wantImage ? "image/*" : "text/plain");
                if (!wantImage) { i.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true); }
                try {
                    startActivityForResult(Intent.createChooser(i, wantImage ? "选择背景图片" : "选择要打开的 txt"), REQ_PICK);
                } catch (Exception e) {
                    fileCallback = null;
                    return false;
                }
                return true;
            }
        });
        web.addJavascriptInterface(new Bridge(), "LinganNative");
        setContentView(web);
        web.loadUrl("file:///android_asset/index.html");
    }

    @Override
    public void onBackPressed() {
        if (web == null) { super.onBackPressed(); return; }
        web.evaluateJavascript("(window.linganBack?window.linganBack():'exit')", new ValueCallback<String>() {
            @Override
            public void onReceiveValue(String value) {
                if (value != null && value.indexOf("exit") >= 0) {
                    finish();
                }
            }
        });
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        if (req == REQ_PICK) {
            Uri[] picked = null;
            if (res == RESULT_OK && data != null) {
                if (data.getClipData() != null) {
                    int n = data.getClipData().getItemCount();
                    picked = new Uri[n];
                    for (int k = 0; k < n; k++) {
                        picked[k] = data.getClipData().getItemAt(k).getUri();
                    }
                } else if (data.getData() != null) {
                    picked = new Uri[] { data.getData() };
                }
            }
            if (fileCallback != null) {
                fileCallback.onReceiveValue(picked);
                fileCallback = null;
            }
            return;
        }
        super.onActivityResult(req, res, data);
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK && web != null && web.canGoBack()) {
            web.goBack();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    // ---------- file helpers ----------

    private String safeName(String name) {
        String n = name == null ? "" : name.replaceAll("[\\\\/:*?\"<>|\\r\\n]", "_").trim();
        if (n.length() == 0) {
            n = "无标题";
        }
        if (!n.toLowerCase(Locale.US).endsWith(".txt")) {
            n = n + ".txt";
        }
        return n;
    }

    private File fileOf(String name) {
        return new File(dir, safeName(name));
    }

    private String titleOf(String fileName) {
        String t = fileName.replaceFirst("^\\d{8}-\\d{4}\\s*", "");
        if (t.toLowerCase(Locale.US).endsWith(".txt")) {
            t = t.substring(0, t.length() - 4);
        }
        return t.trim().length() == 0 ? "无标题" : t.trim();
    }

    private String sizeOf(long bytes) {
        if (bytes < 1024) {
            return bytes + " B";
        }
        return String.format(Locale.US, "%.1f KB", bytes / 1024.0);
    }

    private String read(File f) {
        StringBuilder sb = new StringBuilder();
        BufferedReader reader = null;
        try {
            reader = new BufferedReader(new InputStreamReader(new FileInputStream(f), Charset.forName("UTF-8")));
            char[] buf = new char[4096];
            int n;
            while ((n = reader.read(buf)) > 0) {
                sb.append(buf, 0, n);
            }
        } catch (Exception ignored) {
        } finally {
            try {
                if (reader != null) {
                    reader.close();
                }
            } catch (Exception ignored) {
            }
        }
        return sb.toString();
    }

    private void write(File f, String text) {
        OutputStreamWriter w = null;
        try {
            w = new OutputStreamWriter(new FileOutputStream(f, false), Charset.forName("UTF-8"));
            w.write(text == null ? "" : text);
        } catch (Exception ignored) {
        } finally {
            try {
                if (w != null) {
                    w.close();
                }
            } catch (Exception ignored) {
            }
        }
    }

    private void shareText(final String title, final String body) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                Intent i = new Intent(Intent.ACTION_SEND);
                i.setType("text/plain");
                i.putExtra(Intent.EXTRA_SUBJECT, title);
                i.putExtra(Intent.EXTRA_TEXT, body);
                startActivity(Intent.createChooser(i, "分享灵感"));
            }
        });
    }

    // ---------- JS bridge ----------

    public class Bridge {

        @JavascriptInterface
        public void exitApp() {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    finish();
                }
            });
        }

        @JavascriptInterface
        public String notesDir() {
            return dir.getAbsolutePath();
        }

        @JavascriptInterface
        public String listNotes() {
            JSONArray arr = new JSONArray();
            File[] files = dir.listFiles();
            if (files == null) {
                files = new File[0];
            }
            Arrays.sort(files, new Comparator<File>() {
                @Override
                public int compare(File a, File b) {
                    return Long.compare(b.lastModified(), a.lastModified());
                }
            });
            for (File f : files) {
                if (!f.isFile() || !f.getName().toLowerCase(Locale.US).endsWith(".txt")) {
                    continue;
                }
                try {
                    JSONObject o = new JSONObject();
                    o.put("name", f.getName());
                    o.put("title", titleOf(f.getName()));
                    o.put("mtime", f.lastModified());
                    o.put("size", sizeOf(f.length()));
                    arr.put(o);
                } catch (Exception ignored) {
                }
            }
            return arr.toString();
        }

        @JavascriptInterface
        public String readNote(String name) {
            return read(fileOf(name));
        }

        @JavascriptInterface
        public String saveNote(String name, String content) {
            File f = fileOf(name);
            write(f, content);
            return f.getName();
        }

        @JavascriptInterface
        public boolean renameNote(String oldName, String newName) {
            File from = fileOf(oldName);
            File to = fileOf(newName);
            if (from.equals(to)) {
                return true;
            }
            if (to.exists()) {
                // 同名文件已存在：直接覆盖旧的，避免产生重复条目
                //noinspection ResultOfMethodCallIgnored
                to.delete();
            }
            return from.renameTo(to);
        }

        @JavascriptInterface
        public boolean deleteNote(String name) {
            File f = fileOf(name);
            return f.exists() && f.delete();
        }

        @JavascriptInterface
        public void shareNote(String name) {
            File f = fileOf(name);
            shareText(titleOf(f.getName()), read(f));
        }

        @JavascriptInterface
        public void exportAll() {
            File[] files = dir.listFiles();
            if (files == null) {
                files = new File[0];
            }
            Arrays.sort(files, new Comparator<File>() {
                @Override
                public int compare(File a, File b) {
                    return Long.compare(b.lastModified(), a.lastModified());
                }
            });
            StringBuilder sb = new StringBuilder();
            SimpleDateFormat fmt = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.CHINA);
            for (File f : files) {
                if (!f.isFile() || !f.getName().toLowerCase(Locale.US).endsWith(".txt")) {
                    continue;
                }
                sb.append("===== ").append(titleOf(f.getName())).append(" =====\n");
                sb.append("修改时间：").append(fmt.format(new Date(f.lastModified()))).append("\n");
                sb.append("文件名：").append(f.getName()).append("\n\n");
                sb.append(read(f)).append("\n\n");
            }
            String stamp = new SimpleDateFormat("yyyyMMdd-HHmm", Locale.CHINA).format(new Date());
            shareText("灵感库-导出-" + stamp, sb.toString());
        }
    }
}
