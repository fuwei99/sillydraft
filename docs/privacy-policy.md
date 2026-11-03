# SillyDraft 隐私政策 / Privacy Policy

更新及生效日期：2026 年 11 月 4 日。适用于 SillyDraft 0.6.0 的现有功能。

SillyDraft 由 [moonrailgun](https://github.com/moonrailgun) 维护，是本地优先的小说写作与阅读工具。本政策说明应用处理哪些信息、何时联网，以及如何管理数据。隐私问题请通过[项目 Issues](https://github.com/moonrailgun/sillydraft/issues) 联系维护者。Issues 是公开页面，请不要提交 API 密钥、密码、完整作品、身份证明或其他私密资料；可先描述不含个人信息的问题，请求合适的后续处理方式。

## 1. 本地作品与凭据

基本写作和阅读不要求注册 SillyDraft 账号。作品正文、历史版本、人物与世界设定、插画、导入资源、任务记录、用量记录及偏好保存在本机作品库中；若主动连接远程作品库，则相应内容保存在所连接的设备上，并可能在本机缓存。

模型 API 密钥、同步认证信息和本机资源密钥保存在应用数据目录的本机凭据文件中，当前版本使用 `secrets.json`，不是统一存入系统钥匙串。应用提供的作品备份、同步和正文导出不复制这个凭据文件。用户导入的原始资源本身可能含有敏感信息，原始资源可能随作品备份一同保存。操作系统、设备迁移和系统备份另受设备设置及相应服务政策约束。

维护者不运营默认作品托管服务器。仅在本地使用普通写作和阅读功能，不会把作品自动上传给维护者。应用未集成广告、广告追踪或行为分析上报服务；这不代表下列可选网络功能的接收方不处理数据。

## 2. 自选 AI 与模型服务

连接测试、获取模型列表、写作、编辑、对话、插画及相关模型操作会向你配置的服务地址发起请求。按功能和上下文配置，请求可能包含提示词、正文片段、人物与世界资料、聊天记录、参考图片、模型参数及认证凭据。服务也会接收到建立连接所需的 IP 地址和常规请求信息。部分服务的模型列表同时用于本地费用估算。

这些请求用于完成你使用的模型功能。SillyDraft 不附赠模型账户或额度，也不把你的作品收集到维护者的训练数据库。接收方是否保留请求、用于训练、与其账号关联或向下游提供方转发，取决于你选择的提供方及其政策。使用前请核对服务地址、提交内容及提供方的数据规则；避免向不信任的端点发送敏感内容。删除 SillyDraft 中的连接不会撤销提供方签发的密钥；如需撤销，应在提供方后台操作。

## 3. 远程作品库、执行器、分享与同步

这些功能由你配置或发起。连接远程作品库时，作品内容、资源与操作会在设备和所连接的主机之间传输；远程执行器会接收执行任务所需的请求，并可能继续发送给配置的模型服务。相应服务器或设备由其操作者控制，数据留存和访问权限也由其管理。

作品备份使用口令加密；HTTP/WebDAV 同步把加密的作品备份传到你选择的地址。服务器仍可看到连接信息、对象大小和访问时间等。导出文件、分享链接、配对码和连接分享可能包含作品或访问凭据，请只交给预期的接收者。维护者无法恢复遗失的备份口令，也无法代你删除自选服务器、收件人设备或历史备份中的副本。

## 4. 导入 HTML 与外部资源

导入内容中的 HTML 前端可在隔离网页视图中运行脚本并访问 HTTPS/WSS 资源；兼容前端也会从 jsDelivr 加载部分脚本、样式和字体。资源提供方可以收到 IP 地址、请求路径及浏览器请求信息。前端脚本可以接触应用接口向该页面提供的内容与变量，并可能将这些数据发送给其访问的服务器，因此网页视图隔离不等于禁止联网或保证内容不会外传。

请只加载你信任的资源。可在设置中关闭 HTML 渲染；关闭不会撤回已经发送的请求。SillyDraft 提供加载和创作工具，不提供第三方小说或社区资源的集中内容库。导入、处理或分享资源时，应确保你有相应使用权限。

## 5. 设备权限、更新和外部网页

- 相机用于扫描配对、分享二维码。扫码界面解析二维码内容，不由维护者接收相机画面；拒绝相机权限后可使用粘贴链接等方式。
- 局域网用于访问你选择的同网段设备、作品库或服务。文件导入、导出及分享通过相应系统界面完成。无需这些功能的本地写作和阅读不依赖相关权限。
- iOS 版本不使用应用内 GitHub 更新检查；其他支持该功能的平台可访问 GitHub Releases 获取版本信息，可在设置中关闭自动检查。
- 打开本政策、项目支持页面或其他外部链接时，相应网站按自己的政策处理访问数据。向 GitHub Issues 主动提交的内容会公开显示，并由 GitHub 存储和处理。

## 6. 保存、删除与安全

本地内容在作品库中保留，供你继续创作和恢复历史。编辑当前正文不会自动清除历史版本；归档也不是删除。在书架删除作品会删除其关联的分支、历史与任务记录，但共用资料库资源需单独管理，未再引用的素材文件会在后续启动时清理。可另行删除连接、导出文件和备份；清除应用数据前请确认需要保留的内容已经备份。

远端副本、提供方日志、系统备份和公开 Issue 不会随着本地删除自动消失。请向相应服务或设备的管理者请求查看、删除或更正。维护者能处理的是自身可访问的信息，例如你主动提交的支持反馈，不能访问或删除未提供给维护者的本地作品。隐私请求可从不包含敏感资料的公开 Issue 开始；处理时可能需要核实请求与你所指信息的关系。

请保护设备、凭据和备份口令。作品备份加密不代表所有本机文件或所有可配置网络连接都采用同样的保护；自行配置未加密服务会影响传输安全。

## 7. 政策更新

功能或数据处理方式变化时，我们会更新本文件及顶部日期；仓库历史保留修订记录。适用法律要求额外通知或同意时，应依要求处理。使用第三方服务还应查阅该提供方的政策。

---

## English

**Effective and last updated: November 4, 2026.** This policy describes the existing features of SillyDraft 0.6.0, a local-first writing and reading tool maintained by [moonrailgun](https://github.com/moonrailgun). Contact the maintainer through [GitHub Issues](https://github.com/moonrailgun/sillydraft/issues). Issues are public: do not post credentials, full manuscripts, identity documents or other private information. Start with a non-sensitive description and request an appropriate follow-up channel when needed.

**Local data.** Ordinary writing and reading require no SillyDraft account. Manuscripts, revisions, story notes, images, imported resources, task and usage records, and settings are stored in your library. When you choose a remote library, data is stored on that host and may be cached locally. Credentials currently reside in a local application-data file, `secrets.json`, rather than uniformly in the system keychain. SillyDraft's work backups, sync and manuscript exports exclude that credentials file. Imported original resources can themselves contain sensitive information and may be included in work backups. Operating-system backups and migration follow your device and provider settings.

**Developer services.** The maintainer operates no default manuscript-hosting service. Ordinary local writing and reading do not automatically upload manuscripts to the maintainer. The app integrates no advertising, ad-tracking or behavioral analytics reporting service. Optional network recipients described below may nevertheless process data.

**AI services.** Connection tests, model discovery, writing, editing, conversations and illustration requests contact endpoints you configure. Depending on the operation and selected context, they can transmit prompts, manuscript excerpts, story notes, conversations, reference images, model settings and authentication credentials. Recipients also receive IP addresses and normal request information. Some model lists supply prices for local cost estimates. The requests serve the requested model function. SillyDraft provides no model account or credits and does not collect your manuscripts into a maintainer-operated training dataset. Retention, training, account association and forwarding to downstream providers depend on the service you select. Review its address and policy before use. Removing a connection locally does not revoke its provider-issued key.

**Remote libraries, runners, sharing and sync.** Features you configure or initiate transmit data to the chosen host, runner, recipient or storage service. A runner may forward task requests to its configured model provider. These operators control access and retention. Work backups are passphrase-encrypted; HTTP/WebDAV sync transfers the encrypted backup to your chosen location. Network information, object size and access times remain visible to the server. Exports, pairing codes and connection shares may contain content or access credentials. Share them only with intended recipients. The maintainer cannot recover lost backup passphrases or remove copies held by other devices or services.

**Imported HTML.** HTML frontends can execute scripts and contact HTTPS/WSS resources within an isolated web view. Compatibility frontends also load some libraries, styles and fonts from jsDelivr. Hosts can receive IP addresses, request paths and browser request information. Scripts may access content and variables exposed to their page and transmit them to external servers. Web-view isolation is not a promise that content cannot leave the device. Use trusted resources; HTML rendering can be disabled in settings. Disabling it does not undo previous requests. SillyDraft supplies the tool, not a centralized third-party book or community-resource catalog. Use and share content only with appropriate permission.

**Permissions and websites.** The camera scans pairing/sharing QR codes; the maintainer does not receive the camera feed. Pasting a link is an alternative. Local-network access connects to selected nearby services. Imports, exports and sharing use system interfaces. Basic local writing and reading do not depend on these permissions. iOS does not perform the app's GitHub update check; other supported platforms can contact GitHub Releases and offer a setting to disable automatic checks. Opening policy/support links contacts the respective website. Issues you submit are publicly visible and handled by GitHub under its policies.

**Retention and control.** Data remains in your library for continued work and revision recovery. Editing text does not erase older revisions; archiving is not deletion. Deleting a work removes its associated branches, history and tasks, while shared library resources need separate management; unreferenced asset files are cleaned on a later launch. Manage connections, exports and backups separately. Back up wanted content before clearing app data. Local deletion does not remove remote copies, provider logs, system backups or public Issues: contact the relevant operator. The maintainer can address information it actually holds, such as support feedback, but cannot access or erase unshared local manuscripts. Privacy requests may begin with a non-sensitive Issue and may require verification of your relationship to the information involved. Protect devices, credentials and passphrases; encrypted work backups do not mean every local file or configurable connection is equally protected.

**Changes.** Updates appear in this document with a revised date and repository history. Additional notice or consent must be handled when required by applicable law. Consult each external provider's policy for its own processing.
