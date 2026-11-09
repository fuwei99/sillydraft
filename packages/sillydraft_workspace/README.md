# sillydraft_workspace

SillyDraft 的 Android agent 运行时内核：文件即真相、挂载表即可见性、四个工具。

这个包不依赖 Flutter，也不依赖 Android SDK。它负责的是「agent 能看到什么、能改什么、改的时候怎么不把用户刚写的稿子覆盖掉」；UI、proot 二进制和前台服务在 Android 侧接。

## 路径模型

| 路径 | 来源 | 默认权限 |
| --- | --- | --- |
| `/workspace` | 应用私有目录 `files/workspace` | 可写，永远存在 |
| `/mnt/sillydraft` | `Documents/sillydraft` | 可写，新装默认唯一一行 |
| `/mnt/<name>` | 用户自己加的挂载 | 默认只读，用户可改可写 |

挂载表是**唯一**的可见性来源。没有行指向的宿主路径，在 rootfs 里根本不存在；`/sdcard`、`/storage`、`/data` 不在表里，模型 `ls` 它们只会得到 `No such file or directory`。

`MountTable` 会拒绝挂载 `/`、`/sdcard`、`/storage`、`/storage/emulated/0`、`/data`、`/system`、`/proc`、`/sys`、`/dev`，也会拒绝 `/mnt/` 之外的 guest 路径和重复挂载点。

## 四个工具

```dart
final tools = WorkspaceTools(
  files: WorkspaceFiles(table),
  shell: ProotShellRunner(...), // Android
);
```

| 工具 | 审批 | 行为 |
| --- | --- | --- |
| `read_file` | 否 | UTF-8 文本；图片按 MIME + base64 返回 |
| `write_file` | 否 | 整文件写，`base_hash` 不匹配就拒绝 |
| `edit_file` | 否 | `old_string` 必须唯一，找不到或不唯一都报错 |
| `shell` | 是 | `command` / `cwd` / `timeout` / `run_in_background` |

写操作是 `temp + rename` 的原子写；所有访问在解析后还会 `resolveSymbolicLinks()` 再比对一次挂载根，防止软链接逃逸。

## 提示词

`buildWorkspacePrompt(table)` 生成 `<workspace>` 块，挂载列表由表生成，不会和实际挂载漂移：

```text
路径：
- /workspace —— 你的工作区……（可写）
- /mnt/sillydraft —— 用户的 SillyDraft 数据……（可写）
- /mnt/refs —— 用户额外挂载的目录「refs」（只读）
```

## 本地验证

```sh
dart pub get
dart analyze
dart test

# 打印提示词
dart run bin/ws.dart --workspace /tmp/ws --data /tmp/Documents/sillydraft --prompt

# 在挂载表里跑命令（桌面用宿主 /bin/sh）
dart run bin/ws.dart --workspace /tmp/ws --data /tmp/Documents/sillydraft \
  --mount refs=/tmp/refs:ro --run 'ls -la /mnt/sillydraft'
```

48 个测试覆盖：挂载校验、最长前缀、越界与软链接逃逸、原子写、`base_hash` 冲突、唯一替换、超时与输出截断、proot 参数、提示词不泄漏宿主路径。

## Android 侧

见 [android/INTEGRATION.md](android/INTEGRATION.md)：`useLegacyPackaging`、`MANAGE_EXTERNAL_STORAGE`、jniLibs 里的 `libproot_exec.so` / `libproot_loader.so`、rootfs 下载、前台服务。
