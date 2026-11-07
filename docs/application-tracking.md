# Tianji 应用统计

Flutter / Dart 项目通过已有 Dio 直接调用 [Tianji Application HTTP API](https://tianji.dev/docs/application/tracking)，无需新增 SDK 或原生依赖。服务地址 `https://app.tianji.dev` 和应用 ID `cmw6hum76e2tw9f84j684epi8` 集中在 `lib/app/tracking.dart`。

仅统计四类页面：`/shelf`、`/resources`、`/settings`、`/stories/[id]`。弹窗、详细编辑页面、工作区内部切换不单独上报；不发送路由参数。

| 事件 | 数据 |
| --- | --- |
| Story Created | source：blank、manuscript、card |
| Generation Finished | kind、status、duration（毫秒，包含排队时间） |
| Resource Imported | kind、count（每个成功导入的新资源为 1） |
| Story Exported | format：text、markdown、epub、backup |
| API Request | method（大写）、path（固定模板）、status、duration（毫秒） |
| App Error | type（异常类型）、source（flutter / platform） |

启动时识别系统与应用版本。项目没有登录流程，不创建账号身份。API 不发送域名、查询参数、请求体、请求头或真实资源 ID；未知路径记为 `/[endpoint]`，网络失败状态为 0，取消请求不计入。Dio 流式请求计时到消费结束；远程作品库的 HttpClient 请求计时到收到响应头。

版本获取期间事件先入队，发送前等待版本就绪，每个事件的 payload 都携带缓存版本，identify 数据也包含版本。获取失败、版本为空或超过 3 秒时跳过本次进程的统计，不阻塞应用启动；避免产生版本为 Unknown 的新会话。历史缺失版本的会话不会自动补齐。

不发送书名、正文、提示词、密钥、异常消息或堆栈。事件名最多 50 字符，字符串数据最多 500 字符。资源重复导入和编辑不计入新导入；示例、备份恢复和同步不计入创建作品。手机导出成功表示交给系统保存或分享，不保证接收方已保存。

事件使用独立 HTTP 客户端，200 毫秒批量发送，队列最多 100 条，后台切换时立即尝试刷新。网络失败丢弃该批，不持久化或重试，不阻塞应用。强制退出、离线、队列溢出或关闭作品库时可能丢失事件；原生进程崩溃不在 Flutter 异常捕获范围内。

## 验证

1. 执行 `flutter run -d macos`，切换作品、资源、设置并打开作品。
2. 创建作品、导入一个新资源、完成一次生成、导出作品。生成需要有效模型连接；无需为了验证调用付费模型。
3. 等待片刻或将应用切到后台，在 [Tianji 控制台](https://app.tianji.dev) 的 Applications 中打开上述应用 ID，查看页面与事件统计，时间范围选当前时段。

本次未做真机运行或线上控制台入库验证；代码接入与线上入库是不同验证范围。

## 改动文件

- 初始化与生命周期：`lib/main.dart`、`lib/app/app.dart`、`lib/app/tracking.dart`。
- 页面与创建入口：`lib/features/bookshelf/bookshelf_screen.dart`、`novel_dialog.dart`、`novel_start.dart`、`search_screen.dart`；`lib/features/branches/candidate_screen.dart`；`lib/features/resources/card_start_screen.dart`。
- 导出与工作区入口：`lib/features/transfer/transfer_screen.dart`、`restore_screen.dart`、`sync_screen.dart`。
- 核心上报：`packages/sillydraft_core/lib/sillydraft_core.dart`、`src/tracking/application_tracking.dart`、`src/tracking/api_tracking.dart`。
- 核心 API 调用方（相对 `packages/sillydraft_core/lib/src/`）：`providers/comfyui.dart`、`providers/novelai_image.dart`、`providers/openai_compatible.dart`、`providers/openai_image.dart`、`providers/remote_provider.dart`、`providers/usage_meter.dart`、`remote/remote_session.dart`、`remote/share.dart`、`transfer/project_sync.dart`、`update/update_check.dart`。
- 核心业务（同上）：`st/resource_library.dart`、`tasks/task_runner.dart`。
- 文档：`README.md`、`docs/application-tracking.md`。
