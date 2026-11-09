# Android 接入清单

这个包只做纯逻辑。下面是把 Android 侧接起来需要的全部东西，按顺序做。

## 1. 打包 proot

`android/app/src/main/jniLibs/arm64-v8a/` 放两个文件，文件名必须是 `lib*.so`，Gradle 才会原样打进 APK：

```
libproot_exec.so     # proot 本体，静态链接
libproot_loader.so   # 用户态 ELF loader
```

`android/app/build.gradle.kts`：

```kotlin
android {
    packaging {
        jniLibs {
            // 必须开。否则 .so 留在 APK 里 mmap 加载，nativeLibraryDir 下没有可执行文件。
            useLegacyPackaging = true
        }
    }
}
```

`targetSdk` 不用降。PRoot 通过 `PROOT_LOADER` 让 guest 二进制在用户态加载，不触发 SELinux 对「应用私有目录 execve」的拦截。

## 2. 权限

```xml
<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"
    tools:ignore="ScopedStorage" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
```

首次进入工作区前检查：

```kotlin
if (!Environment.isExternalStorageManager()) {
    startActivity(Intent(
        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
        Uri.parse("package:$packageName")))
}
```

没有这个权限，`Documents` 只有 SAF 的 tree URI，proot 拿不到路径，文件工具也落不了地。UI 上要明确提示，别让模型对着一堆 `EACCES` 瞎猜。

## 3. MethodChannel

Dart 侧需要三个宿主值：

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sillydraft/workspace")
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "nativeLibraryDir" -> result.success(context.applicationInfo.nativeLibraryDir)
            "documentsRoot" -> result.success(
                File(Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOCUMENTS), "sillydraft").absolutePath)
            "filesDir" -> result.success(context.filesDir.absolutePath)
            "hasAllFilesAccess" -> result.success(Environment.isExternalStorageManager())
            else -> result.notImplemented()
        }
    }
```

## 4. rootfs

运行时下载，解压到 `files/rootfs`（不要放 `Documents`，`/sdcard` 是 `noexec`）：

```
https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-arm64.tar.gz
```

解压后补 `etc/resolv.conf`、`etc/hosts`、`etc/hostname`、`etc/default/locale`，并 `mkdir -p tmp`。首次安装给下载/解压进度，几万个小文件在手机上要几十秒。

## 5. 组装

```dart
final table = MountTable.standard(
  workspaceHost: '$filesDir/workspace',
  dataHost: '$documentsRoot',
);
final builder = ProotCommandBuilder(
  rootfsDir: '$filesDir/rootfs',
  prootExecutable: '$nativeLibraryDir/libproot_exec.so',
  loaderPath: '$nativeLibraryDir/libproot_loader.so',
  tempDir: '$cacheDir',
  hostWorkingDirectory: filesDir,
);
final command = builder.build(
  table: table,
  command: 'ls -la /mnt/sillydraft',
  cwd: '/workspace',
);
await Process.start(command.executable, command.args,
    environment: command.environment,
    workingDirectory: command.workingDirectory);
```

`ProotCommandBuilder` 已经包含：

- `--root-id --link2symlink --kill-on-exit`
- `-r <rootfs> -w <guest cwd>`
- 每个挂载行一条 `-b host:guest`
- `/dev`、`/proc`、`/sys`（存在才挂）
- `PROOT_LOADER`、`PROOT_TMP_DIR`、`TMPDIR`
- 命令通过位置参数传入，`cd -- "$1" && eval "$2"`，不经过二次转义

## 6. 前台服务

`shell` 的 `run_in_background` 需要 `ForegroundService`：

- `foregroundServiceType="dataSync"`（长任务再加 `specialUse`）
- 日志写 rootfs 的 `/tmp/sillydraft/background/<id>.log`
- PID 文件 + `--kill-on-exit`
- 超时或取消时杀整个进程组，不要只杀 shell
- Android 15 的 `dataSync` 有每日时长限制，长任务要引导用户加电池白名单

## 7. 文件系统坑

`/sdcard` 是 FUSE：

- 没有硬链接，`--link2symlink` 必须开；
- `chmod` 是假的，脚本不能靠它；
- 小文件 IO 慢，git 的 loose object 多时会卡；真卡就把 `.git` 放 `files/`，用 `GIT_DIR` + `--work-tree` 指到 `/mnt/sillydraft`；
- `FileObserver` 会漏事件，外部编辑要靠 onResume 扫 mtime/hash 兜底；
- **SQLite 不要放 `/mnt/sillydraft`**，锁语义和 mmap 在 FUSE 上不可靠。索引放 `files/index.sqlite`，可删可重建。

## 8. 还没做的

- Flutter 的挂载表管理 UI（列表、SAF 选目录、`getTreeDocumentId` 转真实路径、ro/rw 开关）
- 把现有 SQLite 书库迁移成 `books/<书名>/chapters/*.md`
- 后台 shell 的 `shell_output` / `shell_kill` 两个工具
- 挂载表持久化（`MountTable.toJson()` / `fromJson()` 已就绪）
