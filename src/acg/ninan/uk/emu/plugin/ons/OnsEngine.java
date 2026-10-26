/*
 * ONS 插件的 Java 侧：SAF 文件访问与视频播放回调。
 * 改自 OnscripterYuri 的 ONScripter.java（GPL-2.0 或更新版本），整个插件按 GPL 分发，
 * 完整对应源码见本目录与上游提交 08f744b31cc1907b66a15f0402e62321a131ed81。
 */
package acg.ninan.uk.emu.plugin.ons;

import acg.ninan.uk.emu.EmuEngine;
import acg.ninan.uk.emu.EmuOnsBackend;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;
import android.view.KeyEvent;

import androidx.core.content.FileProvider;
import androidx.documentfile.provider.DocumentFile;

import java.io.File;
import java.nio.charset.StandardCharsets;

public class OnsEngine implements EmuEngine, EmuOnsBackend {
    private static final String TAG = "## onsyuri_android";
    private static final String EXTRA_GAME_URI = "gameuri";

    private Activity activity;
    /** 非空表示游戏目录经 SAF 授权；为空则走普通文件路径。 */
    private DocumentFile onsBase;

    @Override
    public void onCreate(Activity activity, Bundle args) {
        this.activity = activity;
        String uriStr = args.getString(EXTRA_GAME_URI);
        onsBase = uriStr == null ? null : DocumentFile.fromTreeUri(activity, Uri.parse(uriStr));
    }

    @Override
    public int getFd(byte[] pathBytes, int mode) {
        if (onsBase == null) return -1;
        String path = new String(pathBytes, StandardCharsets.UTF_8);
        return SafFile.getFdSaf(activity, onsBase, path, mode == 0 ? "r" : "w");
    }

    @Override
    public int mkdir(byte[] pathBytes) {
        if (onsBase == null) return -1;
        String path = new String(pathBytes, StandardCharsets.UTF_8);
        return SafFile.mkdirsSaf(onsBase, path) == null ? -1 : 0;
    }

    @Override
    public void playVideo(byte[] pathBytes) {
        String path = new String(pathBytes, StandardCharsets.UTF_8);
        try {
            Uri uri;
            path = path.replace('\\', '/');
            if (onsBase == null) {
                // scoped storage：经宿主的 FileProvider 暴露文件
                uri = FileProvider.getUriForFile(activity,
                        activity.getPackageName() + ".emu_fileprovider", new File(path));
            } else {
                uri = Uri.parse(onsBase.getUri() + "%2F" + Uri.encode(path));
            }
            Log.i(TAG, "playVideo " + uri);
            invokeSystemPlayer(uri);
        } catch (Exception e) {
            Log.e(TAG, "playVideo error:  " + e.getClass().getName() + " " + e.getMessage());
        }
    }

    private void invokeSystemPlayer(final Uri uri) {
        final AlertDialog.Builder builder = new AlertDialog.Builder(activity);
        builder.setTitle("Playing game video");
        builder.setMessage("playVideo: " + uri + "\nPlease select a video app to play ! ");
        builder.setCancelable(false);
        builder.setPositiveButton("Yes", new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int which) {
                dialog.dismiss();
                Intent intent = new Intent("android.intent.action.VIEW");
                intent.setDataAndType(uri, "video/*");
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                activity.startActivityForResult(intent, -1);
            }
        });
        builder.setNegativeButton("No", new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int which) {
                dialog.dismiss();
            }
        });
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                builder.create().show();
            }
        });
    }

    // EmuEngine 的其余回调：ONS 的生命周期由 SDL 壳处理，这里不需要
    @Override public void onStart() { }
    @Override public void onResume() { }
    @Override public void onPause() { }
    @Override public void onStop() { }
    @Override public void onDestroy() { activity = null; onsBase = null; }
    @Override public void onWindowFocusChanged(boolean hasFocus) { }
    @Override public boolean onKeyDown(int keyCode, KeyEvent event) { return false; }
    @Override public boolean onKeyUp(int keyCode, KeyEvent event) { return false; }
    @Override public boolean onBackPressed() { return false; }
}
