# 寻乐游戏与工坊整合：实施记录

## 2026-10-31 恢复核对：保留已验候选，交互设置单独绑定

隔夜新增的游戏网页交互设置已与另一任务的[五项 WebKit 验证](./evidence/native-game-interaction-switches-20261031.json)逐文件核同：默认关闭回弹与非编辑区长按，可按游戏保存选择。独立源码比较确认 ready、资源缓存、账号隔离、房间恢复与 WebContent 重试核心未变；现有五项验证覆盖本次增量，无需重复已过的 17 项、性能六十样本或双游戏 N10。共享 iPhone 18 Pro 上已验正常构建的四项二进制／目录摘要仍与昨天一致；旧二十房和性能证据继续绑定旧候选，不改标为新增设置源码的现网实测。未手点新菜单或真机长按的限制保留。[恢复后的源码与安装版本核对](./evidence/native-game-discovery/recovery-20261029/resumed-source-binding-20261031.json)。

新后端离房修复的源码、镜像及发布／回滚脚本摘要保持一致，尚未上传或发布；恢复目标本身不等同于该新增生产变更的授权。4.2／4.3／5.1 仍等待原故障房权威收尾及修复分支的正常 UI 复验，其余已过证据不重复执行。

## 2026-10-30 当前收口：有效新房各十轮，末位离房修复待生产验证

M0.1 基线记录与 M3.3 性能对照已通过。性能结果绑定固定 `6ff97db…`／`a7011d9f…` 输入，采用用户确认后的标准：保留星纸三秒开场，报告实际收益，不再统一以降低 30% 阻断验收。准备后 P50 五子棋改善 25.45%、星纸 8.87%，冷资源 P90 分别改善 17.98%、6.98%；历史 9ba 未达初始目标、926 受限记录和 b251 冷 P90 失败均保留。[最终性能指标](./evidence/native-game-discovery/recovery-20261029/m3-final-a701-metrics.json)、[M0 基线汇总](./evidence/native-game-discovery/recovery-20261029/m0-baseline-consolidated-20261030.json)、[五子棋联机补充](./evidence/native-game-discovery/recovery-20261029/m0-gomoku-online-addendum-20261030.json)。

根代理已确认五子棋 G01–G10、飞行棋 F05–F11 与 F13–F15 各 10 个有效新房；新增五轮飞行棋的独立复核已通过，正常离房和连接关闭均有对应证据。真实恢复覆盖冷邀请、短断网、前后台、App 重启及 WebContent 退出；各轮只证明其记录的类别，不把每房描述为全部故障重测，也不把等待期间的托管推进计成人工输入。F01–F04 与 F12 不计入，拒绝尝试及观察限制保留。[G05](./evidence/native-game-discovery/recovery-20261029/g05-native-foreground-recovery-20261030.json)、[G06–G10](./evidence/native-game-discovery/recovery-20261029/g06-g10-native-foreground-recovery-20261030.json)、[飞行棋新增五轮](./evidence/native-game-discovery/recovery-20261029/f10-f15-native-foreground-recovery-20261030.json)。当前正常原生候选、已安装二进制与 a701 目录的对应关系另有[只读指纹盘点](./evidence/native-game-discovery/recovery-20261029/final-native-candidate-inventory-20261030.json)；[可体验候选截图](./evidence/native-game-discovery/recovery-20261029/native-games-final-preview-20261030.png)不代替这些行为证据。

当前仍有必须闭环的真实缺陷：现网后端 `7723ae8…` 的末位房主已经不在游戏席位、仅观战时，正常离房出现五次 `INVALID_COMMAND／消息格式无效`。原 772 的本地红测试复现删除最后成员后访问空数组 `userId` 的 TypeError，不将本地堆栈冒称生产捕获。F12 最初误开反馈且未提交是独立的操作者导航失误，不算正常离房或产品离房失败；后续真实拒绝另行保留，原 F12 永不回补为干净 N10。probe 页已关闭、B 页显示离开且无 WebSocket，以及 health 的 0／0／0 都不能证明该房权威收尾完成。

最小修复以 772 为底，只改 `RoomService.#leave` 并新增三个回归；原版红测为 2 通过／1 失败，候选定向 39／39、源码检查、生产 Dockerfile 构建及无外网只读 amd64 镜像业务流程通过。候选 tree `38f267f3…` 不是发布 commit，补丁与源码／镜像归档已冻结，尚未提交、推送或生产发布，仍待新增修复授权及发布后正常 UI 离房／权威状态复验。原依赖假设及构建前失败保留，不将本地测试当成现网修复。[脱敏本地候选与待验回执](./evidence/native-game-discovery/recovery-20261029/last-owner-observer-local-candidate-20261030.json)。

| 任务 | 当前关闭判断 |
| --- | --- |
| M0.1、M3.3 | 已通过，各自版本和测量边界保持 |
| M4.1 | 按[分层范围审计](./evidence/native-game-discovery/recovery-20261029/final-scope-audit-20261030.json)单项关闭；不宣称所有分支均为生产 UI 实测 |
| M4.2 | 创房／加入／幂等与既有边界通过；新增正常离房和成员状态缺陷未闭环，保留未完成 |
| M4.3 | 两游戏有效 N10 各十轮已确认；F12 正常离房及修复后权威收尾仍待完成 |
| M5.1 | 核心 17／17 与页面、云居、AI 旅程可复用；待上述生产回归及最终交付汇总，保持未完成 |

历史范围审计对 4.2 的关闭建议早于本次新缺陷，原文件与旧检查点不改写。M4／M5 整体及目标尚未完成，M6 不在本次工作内。当前生产仍为 Web `6ff97db…`／a701 与后端 772，本地候选身份不替代生产身份。

> 下方按各次观测时点保留原文；其中旧房间计数、M0.1／M3 未验、锁屏或部署阻塞描述均是历史检查点，不覆盖本节当前结论。

## 2026-10-30 云居游戏与帮助导航实走

正常账号 A 从星纸详情免费获取后，界面由「获取」变为「打开／已加入云居」，云居出现星纸图标。实际从云居进入自由练习、收起后从寻乐「继续游戏」恢复、按住加速 500 ms，再从云居重新打开，保存截图的倒计时持续由 2:19、2:17 推进至 2:02；帮助页「前往工坊」也实际到达工坊。UI 继续入口、倒计时和已通过的 Runtime 映射测试共同支持这条功能链，不声称采样了同一 WKWebView 指针。星纸是本轮正常获取的受控前置数据，不把历史仅保留的「今天来做菜」当成既有游戏库或升级验收；旧 Play 聚合入口继续保留自身兼容路径，不强求与单款游戏共享 profile。截图只是竖向设备外壳内的 App 横向内容，不计系统横屏旋转通过。完整 5.1 仍待联机 N10 收口，本段不改变计数或整体勾选。[云居游戏与帮助真实旅程](./evidence/native-game-discovery/recovery-20261029/m5-home-game-and-help-journey-20261030.json)。

## 2026-10-30 当前验收：M0 基线记录已通过

M0.1 已按既定记录范围验收：三游戏的现有入口、加载／联机就绪事件、首次／缓存后／会话恢复类别已有可复核证据；32 项汇总引用及 11 项五子棋联机补充引用的路径、字节数与 SHA 均核对一致。受控 a701 性能、历史存活会话、正常 HTTPS 教程与房间观察分开记录，自然缓存及缺失计时保持未知，历史 b251 原生房间证据不改标为 a701。[基线汇总](./evidence/native-game-discovery/recovery-20261029/m0-baseline-consolidated-20261030.json)、[五子棋联机补充](./evidence/native-game-discovery/recovery-20261029/m0-gomoku-online-addendum-20261030.json)。本次只关闭基线记录任务；下方历史未验结论保留，M4 每款十轮目标、既有计数及 M5 待验状态均未改变。

## 2026-10-30 15:49 解锁续验：AI 导航修复与教程真实输入

Mac 已由实际桌面观察确认解锁。旧两个失败 fixture 已按原 XCTest 所有权精确清理：唯一维护测试 1 / 1 通过、无失败或跳过，执行前 2 个、执行后 0 个；测试前已恢复 `9ef` 源码，正常旧 a701 四指纹核同后恢复。临时编译副本经归档逐成员复核后回收，原 15 / 2 失败及随后完整 17 / 17 记录均保留，不重复跑已通过的完整组。[精确清理与回收](./evidence/native-game-discovery/recovery-20261029/m5-old-two-fixture-store-cleanup.json)。

真实同应用对照确认 AI 卡片导航问题：工坊普通卡片立即显示「今天来做菜」详情；AI 卡片点击后仍显示 AI，按返回才看到详情。只把 AI 卡片改为直接详情目的地，新正常构建成功后从已保存的同一真实回复复验：一次点击立即显示详情，一次返回同六卡回复，再次返回工坊。没有获取应用、删除数据或重发 AI 请求；当前正常 App PID72102，目录仍为 a701，Runtime／Controller 保持 `b61f`／`e6d`。新二进制另留指纹，不把旧固定六十样本改标为新构建性能。[修复、构建与真实返回链](./evidence/native-game-discovery/recovery-20261029/m5-ai-card-navigation-fix-validation.json)。

星纸从原生互动教程入口实际启动，保留三秒倒计时并渲染游戏；左右转向、加速、连续发射、齐射分别推进至 2 / 8、3 / 8、4 / 8、5 / 8，未宣称完整八步教程完成。既有原生日志记录该次教程 ready 为 8400.48 ms，这是自然缓存的单次 HTTPS 功能观察，不是 N10，也不与工具观察时钟相减归因。切回 A 后原 G／F 历史保留，C 新教程记录未混入 A。[真实输入与身份隔离](./evidence/native-game-discovery/recovery-20261029/m5-unlocked-real-journey-20261030.json)。该检查点有效新房为五子棋 4 / 10、飞行棋 0 / 10；后续 F05 见下，0.1、M4 与完整 5.1 保持待验。

两次新增飞行棋房间的创建已分开记录邀请码控件与同 socket 的 player／精确房间快照：权威观察上界分别 2639.84、1847.04 ms。实际原生加入的既有 Native room-connected 日志分别为 23993.90、16599.48 ms，仍需阶段定位；工具侧成员确认上界包含 UI／IPC／轮询，首轮还包含后续人为间隔，不能直接称网络耗时。两轮完整 game ready 还含等候玩家准备，不能当作页面加载时间。[F03 基线与收尾](./evidence/native-game-discovery/recovery-20261029/f03-native-room-baseline-and-cleanup-20261030.json)。

F04 在权威当前席位上真实确认了 A、B 各一次手动掷骰；之后工具／模型间隔已使 A 超时托管。实际 B 断网约 2048.39 ms 后，旧 socket 关闭、新 socket 明确 player，再收到同码双人房间与同 game session／有序席位的完整快照；最新状态包含托管推进，因此后续助手正确拒绝把自动操作当作人工续局。两轮均不计 N10，双方正常离开并确认连接关闭，当前没有待收尾房间。另发现 Cua 导出原始游标未随闭包更新，部分阶段 floor 保留旧值；原数据和限制已留存，下一轮必须取每次真实 read 返回的 cursor，且把游戏时限内的全部步骤放在同一连续调用中。[F04 恢复片段与收尾](./evidence/native-game-discovery/recovery-20261029/f04-native-recovery-fragment-and-cleanup-20261030.json)。

F05 随后完成首轮完整飞行棋恢复：所有时限内步骤在一次约 10.94 秒的实际 UI 调用中完成，A、B 在恢复前后各有服务端确认的真实输入；原生 A 第四架飞机起飞 -1→0，并在恢复后实际前进 0→5，包含真正的棋盘外目标操作。B 实际断网约 2032.41 ms，旧连接关闭，新连接明确 player 后收到同房、同 game session、相同有序席位和相同状态的完整快照；测量窗口内所需状态均无托管。双方正常离房、连接关闭，独立只读复核通过，当前有效计数为五子棋 4 / 10、飞行棋 1 / 10。全局 CDP 历史存在未标阶段的截断提示，因此仅确认 F05 必需正向证据链齐全，不声称所有历史帧完整；F01–F04 原样排除。[F05 完整证据](./evidence/native-game-discovery/recovery-20261029/f05-first-valid-native-flight-recovery-20261030.json)。

飞行棋计时复核另纠正了一处观察标签：F02 的 790.85 ms 只证明邀请码控件出现，当次未收到匹配 room.snapshot；首个权威快照观察上界约 18,117.01 ms，含人为／工具间隔与配置动作，不能作为加载或连接性能基线。原字段和原字节备份保留，新增限定说明，不勾 0.1；后续采集必须先匹配实际房间快照与 player connection.ready，再记录权威就绪时间。[计时限定审计](./evidence/native-game-discovery/recovery-20261029/f02-create-timing-qualification.json)。

## 2026-10-30 锁屏续验：等候房与验证资源已收尾

F02 因系统锁屏始终未由原生加入，不能计为有效 N10。独立只读 SDK 观战核对曾确认该房仍处于等待、仅有离线测试房主，不能用 health 的零在线数代替具体成员已清理。随后用同一现有房主测试身份的独立正常 SDK 会话，仅加入指定自有等候房，核对唯一房主且未开始对局，再发送一次支持的 room.leave；收到同房 room.left / reason=left 与连接关闭，随后仅撤销本次临时会话并回收 worker／socket。既有创建证据及其他轮次未改，F02 标记中止、未通过、不计数、已收尾。[精确收尾回执](./evidence/native-game-discovery/recovery-20261029/f02-owned-sdk-membership-cleanup-20261030.json)。当前仍为五子棋 4 / 10、飞行棋 0 / 10。

三个已完成任务的独立 SDK 会话均正常撤销并退出；本地 Universal Link 与 serve-sim 辅助服务已正常停止，18147／3200／9223 均无监听，必要源码保留供解锁后重新启动。正常 a701 App PID42494 仍运行，共享模拟器及其他任务设备未改。新回归编译副本已在保存、重读并逐成员校验小型源码／实际测试二进制归档后回收，任务 allocated 净减少约 149.06 MiB；同期文件系统可用空间快照为 -140 KiB，不能冒称同等物理空间增加。[编译产物回收](./evidence/native-game-discovery/recovery-20261029/m5-fixture-lifecycle-artifact-retirement.json)。

本轮已两次直接核对桌面，仍为系统锁屏；人工解锁请求待答复。0.1、M4、M5 保持未勾选，下一步仍是实际原生新房、教程／基线、卡片跳转对照及旧两个测试数据仓库的精确缺席核验；旧测试清理补丁仍只准备、未运行。[当前证据与未完成项](./evidence/native-game-discovery/recovery-20261029/locked-round2-remaining-work-checkpoint.json)。

## 2026-10-30 当前续验：核心回归全过，原生新房待解锁

原生夹具现记录实际 browser／WKWebView／配置 store 的弱引用及账号／应用到 UUID 的对应关系，在终止运行会话前停止并移除自有页面，结束临时 UIKit 引用后回收测试存储。仍保持原 30 秒有界删除及失败断言，并在每次删除后用 WebKit 枚举确认缺席；不要求 store 包装对象必须立即释放，也不把 `owners=[]` 当作存储已释放。产品 Runtime `b61f007a…`、Controller `e6d22106…` 均未变。先前两失败定向一次 2 / 2 通过，随后同产物完整一次 17 / 17 通过、无跳过；定向九个与全量三十一个自有 UUID 不相交、共四十个均确认缺席。原 15 / 2 失败证据保留，旧轮两个失败 UUID 的单独缺席核验尚待执行。[夹具修正与完整回归](./evidence/native-game-discovery/recovery-20261029/m5-fixture-lifecycle-final-validation.json)。

真实正常原生旅程新增：A→D→A 后各账号游戏历史及房间引用隔离，切回 A 恢复五子棋／飞行棋列表；工坊查询 AI 命中四条、隐藏推荐，清除后恢复推荐；游戏分类显示五条且能清除。A 的非会员提示符合现有门槛；现有会员 C 经正常原生密码登录，从工坊 AI 发送一次预设问题，实际服务完整返回六张应用卡片，正常返回工坊，个人工坊及作品管理显示专用空账号的正常状态。A 云居前后均为零；这不替代非空真实用户库的保留证明。AI 卡片激活未观察到详情跳转，静态与日志覆盖不足，继续保留未定位，不算详情旅程通过。[真实原生检查点](./evidence/native-game-discovery/recovery-20261029/m5-real-native-journey-checkpoint.json)。

文档两条既有导航坏链已精确修正，五十四个配置引用和一百七十九个 Markdown 本地引用全部有效；完整隔离构建通过，任务缓存与输出已回收，共享目录未变。[文档验证](./evidence/native-game-discovery/recovery-20261029/final-docs-navigation-fix-validation.json)。M0.1 仍需飞行棋真实创建／加入至房间确认的同钟观察，以及当前教程真实入口／就绪记录；五子棋与星纸本地既有同构建基线可复用，不重复整批性能测量。

飞行棋下一等待房 F02 已由实际浏览器 UI 创建，关闭空余阵营，创建提交至邀请码控件观察约 790.85 ms；该次读取未取得匹配权威快照，不能称房间 ready。后续首个匹配权威快照的同钟观察上界为 18,117.01 ms，其中含操作间隔和房间配置动作，不能当作独立连接性能基线。原生尚未加入时 Mac 再次锁屏，系统阻止继续操作；已请求用户人工解锁，现网授权无需重复确认。F02 继续标待收尾且不计成功，当前有效计数仍为五子棋 4 / 10、飞行棋 0 / 10。M0–M5 整体尚未完成，M4 与其余真实 M5 旅程继续保留待验。

## 2026-10-30 03:26 续验：完整资源版本性能通过

固定生产 `6ff97db…` / 目录 `a7011d9…` 的完整快照先完成 N1，再只执行一次正式六十样本；六组各 N10 均真实可操作，星纸三十样本均 playing 且 renderer ready。完整正式 byte 窗口 2969 条序列化请求全 200，零坏行／未冻结路径；保留预检、正式及收尾各自窗口，不把总日志 4105 与正式 2969 混用。四条版本／源码／产品指纹前后不变，独立只读复核 627 / 627、零问题。[正式指标与原始样本映射](./evidence/native-game-discovery/recovery-20261029/m3-final-a701-metrics.json)、[独立复核](./evidence/native-game-discovery/recovery-20261029/m3-final-a701-independent-review.json)。

| 同构建回环、模拟器测量 | 旧首页→详情→模式 P50 / P90 | 直达冷资源 P50 / P90 | 准备后直达 P50 / P90 |
| --- | --- | --- | --- |
| 五子棋电脑对手 | 1118.37 / 1867.59 ms | 881.24 / 1531.85 ms | 833.71 / 1451.34 ms |
| 星纸本地 | 4268.49 / 4403.84 ms | 3909.46 / 4096.26 ms | 3889.93 / 4012.51 ms |

准备后相对旧入口 P50 分别改善 25.45%、8.87%；冷资源 P90 分别改善 17.98%、6.98%，满足用户调整后的 3.3 标准。准备本身相对直接冷资源 P50 的额外收益分别约 5.39%、0.50%，不把入口缩短的全部收益归因静态缓存。星纸三秒倒计时保持；文档资源时钟与原生点击时钟分列，完整未知资源等待不作跨时钟减算。该结果仅为固定输入的模拟器／回环对照，不代表现网网络、真机、飞行棋 ready 或联机 SLA；旧 b251 冷 P90 失败及日志限制全部保留。M0.1、M4、M5 仍未全部完成，当前继续实际双客户端新房和真实核心旅程。

## 2026-10-30 03:15 续验：最终原生两种重启恢复

03:23 补验已完成两款各两条超时终态：飞行棋首组实际 ERROR 524；五子棋恢复回执记录断网 121,173 ms 后实际 ERROR 524（相邻控制台观察为 121,174 ms），两者均显示预约过期中文提示；两款各自也实际走到 SDK 重试耗尽，显示对应中文提示。四项均清空旧棋盘、正常返回大厅，独立房主均正常离房，所有浏览器网络覆盖恢复，临时页关闭；当时 health 的连接／在线玩家／在线房间均为零。4003 是 SDK 内部 onLeave 原因，依据实际唯一提示和精确源码映射确认，不冒称收到 WebSocket ERROR 4003 帧。[最终四分支证据](./evidence/native-game-discovery/recovery-20261029/production-final-reconnect-terminals.json)。第二组五子棋先耗尽重试的分支未覆盖目标524，单独保留，第三组使用固定时点补齐，未修改SDK重试规则或服务端窗口。

旧 b251 服务日志的独立复核更正了请求总数口径：测量 byte 窗口内 2609 条单行 JSON 可解析，另有并发写入串接、空行和服务器异常文本，不能称为完整请求数或完整“零异常”。连续 JSON 恢复所得 2854 个对象也不是完整总数；旧 3612 同样不能据逐行解析单独证明完整日志。六十样本原始附件与各组 P50 / P90 已逐值复核一致，冷 P90 失败结论保持。本轮固定 a701 服务已采用互斥日志写入，并对完整窗口强制逐行解析及零异常门禁；N1 六样本 1136 请求全 200、零无效行，正式六十样本仍在进行。

最终无探针 `e6d22106…` / `b61f007a…` 新增 G03、G04 两轮通过。G03 真实终止并普通重启原生 App，再从持久“返回上次房间”进入；G04 只读映射唯一可见 WKWebView，成功退出调试器后精准终止该 WebContent，实际错误页仅点击一次“重新加载”。两轮均确认同房、同一 game session、双方席位与原两子摘要保持，随后两名真人各落一子到四子，双方正常离开、浏览器收到 room.left 并关闭连接。G04 初始页面曾短暂处于房间等待展示，未据此宣称恢复失败或通过，完整快照与实际棋盘呈现后才记录恢复。

当前有效新房计数为五子棋 4 / 10、飞行棋 0 / 10；F01 的冷邀请功能片段继续保留且排除干净 N10，M4 未完成。[本轮脱敏检查点](./evidence/native-game-discovery/recovery-20261029/final-native-checkpoint-20261030-0315.json)。G03 首次未核验字段值的输入尝试不能归因产品；后续已保存实际输入值及成功加入证据，新的房间输入助手先核验真实值再提交。

实际生产目前为其他任务的后继 `6ff97db…`、EdgeOne `dpwj1wku1mh3`，目录 `a7011d9…`。七个关键契约／资源导出文件与本次 `0e6c137…` 修复逐字一致，261 个资源与三模式 HTML 的必需脚本／样式闭包一致；[最终发布收据](./evidence/native-game-discovery/recovery-20261029/web-publication-6ff97db.json)保留实际来源与 CI 因预算未启动的限制。已冻结该版本的完整本地输入，正在做 N1 后一次正式 60 样本，旧 b251 冷资源 P90 超标不改写。

两款超窗互补回归仍在进行：第一组五子棋实际走到重试耗尽，飞行棋实际收到协议 ERROR 524；各自均显示对应中文终态并清空旧棋盘、能返回大厅。首组独立房主离房时，飞行棋 SDK 命令遭真实 revision conflict；刷新权威状态后正常离房成功，原失败回执保留。还需补齐另一游戏对应分支，不据这两个局部结果宣称四项全过。

## 2026-10-30 02:50 续验：真实冷邀请与联机静态闭包

最终无探针原生源码 `e6d22106…` 的新房续验目前有五子棋两轮通过：G01 先正常结束 App，再在实际 iOS Safari 点击普通 HTTPS 邀请锚点，由 OS 冷启回到同一房间、同一 game session、相同两名玩家席位和两子摘要；双方继续落子至四子并正常离房。G02 对独立浏览器 B 实际断网 14,978 ms，恢复后出现新的连接、权威席位与原两子保持，双方新落子至四子后正常离房。这验证的是 B 的网络中断，不冒称原生 A 自身断网。

飞行棋 F01 也完成上述真实 Safari 冷启动邀请、同房同局与恢复后的真实飞机输入，但自动化等待触发了游戏内超时与托管，因此只保留功能片段、排除最终干净 N10 计数；两端均已按游戏支持的离房确认收尾。当前计数为五子棋 2 / 10、飞行棋 0 / 10，G03 仍在验收，不宣称 M4 完成。[当前脱敏检查点](./evidence/native-game-discovery/recovery-20261029/final-native-checkpoint-20261030.json)。

超窗复验又覆盖实际握手拒绝分支：B 断网 141,261 ms 后恢复，两款收到协议 ERROR 524 `seat reservation expired.`，旧房间／棋局已清空且有返回入口，但提示仍为英文。该失败保留；客户端已独立修复该已知码的中文提示，与先前重试耗尽的 4003 分支分别回归，43 项测试、类型检查与 lint 通过。两个原始负例均正常返回大厅，独立房主正常离房，浏览器网络覆盖已恢复；两条修复分支仍待最终现网 UI 复验。

在线资源清单已补上通过导航进入的通用房间静态闭包，不递归纳入其他游戏的动态渲染器，也不缓存凭据、房间接口或权威状态。资源与 524 提示两项修复以 `0e6c137…` 正常推送，EdgeOne 生产部署 `dp0dyj5a4l1s` 成功；随后其他任务发布了直接后继 `d60d7b9…`，生产部署 `dpusmr2h81ri` 成功。后者保留本次修复并增加飞行棋／弹珠主题与沉浸样式，不能把两次目录生成当作同版本重建。正在按最新实际生产 `1a4e2b31…` 重新冻结完整性能输入；旧 b251 的冷资源 P90 未通过事实保持，后续阶段诊断与新静态清单均不替代最终性能验收。

## 2026-10-30 最新续验：原生重试修复与最终采样

原生错误页现以当前 URL、当前历史项 URL、初始 URL 的顺序选择目的地，发起一次忽略本地 HTTP 缓存的文档请求。真实生产对照中，旧行为在 WebContent 退出后完成了 404 导航，却得到空 head / body；菜单再次载入则得到可挂载实体。缓存绕过候选首次点击即恢复同房、同局、原两子和两名玩家席位，双方继续正常落子至四子后均已正常离房。尚未细分 WebKit、条件响应与 CDN 的具体贡献，不把它写成服务端发空正文的确定结论。

另有独立的真实 SPA 路径红测试，证明旧重试会回到最初入口；修复后通过。普通 404 / ETag / 304 回环夹具在修复前也能正确挂载，不能称为生产白屏的红测试。最终已移除诊断环及额外 DOM 观察，源码 `e6d22106…`、测试源码 `51c02dd4…`，9 项导航回归全过且无跳过；已正常安装并校验最终构建，独立静态复核无可操作发现。[修复与分层验证证据](./evidence/native-game-discovery/recovery-20261029/native-retry-fix-validation.json)。候选生产对照不计为最终无探针 N10。

最终 926 的首次同构建两款、三路径、各 N10 已执行完成，共 60 个真实可操作样本，测试命令通过；但服务日志发现五类本地缺失资产，随后正常 HTTPS 确认现网均为 200，说明本地夹具依赖闭包不完整。首次 60 个原始样本保留为受限结果，不能据此勾选 M3；正在补齐精确依赖、先做 N1 预检，再重跑正式 N10。原生检查器已关闭；正常启动、资源准备、数据仓库、星纸三秒倒计时规则保持原行为。

独立生产边界房已补齐并收尾：真实非成员 spectator 连接前后成员数均为二、席位与 revision 不变，独立房主 sync 再次确认；加入第三名普通成员后正常轮换席位，外部 spectator 未进入成员或玩家池。随后该观众正常退出再显式作为成员加入，四个独立账号占满标准房，第五个原生账号显示“房间已有4名成员”，权威成员数保持四且未含第五账号。最后对 B 浏览器局部断网，独立房主确认其 offline 后正常移除；B 恢网实际收到协议 ERROR 525、中文移除终态、无新房间快照，后续 150 秒无重连尝试并能正常返回大厅。C / D / E 均通过支持的离房协议收尾，health 三项容量回到零。该房不计为游戏 N10，也不代表超保护期的有效对局恢复已验证。[角色、容量与离线移除生产证据](./evidence/native-game-discovery/recovery-20261029/production-role-capacity-offline-removal.json)。

后续并行现网 Web 已出现新目录 `b25149ae…`，模式、URL、发布状态及协议字段未变，仅生成时间和版本摘要改变；此次服务端发布没有修改 Web。M3 已选择固定完整的 b251 / ed7 构建快照，同步原生 bundled JSON 后增量构建，先完成两款三阶段 N1 的六个真实可操作样本，1002 个静态请求均为 200、无夹具漏项，再进行正式 N10；不将旧 926 受限样本冒称为 b251 结果，也不据远端 Git HEAD 推断实际部署提交。

超保护期负例新增真实失败：五子棋、飞行棋均先进入有效对局，B 实际断网约 176 秒，超过 120 秒传输重连窗口。SDK 已耗尽 28 次重试，页面透出 `No more retries. Reconnection failed.` 并保留旧棋局，未给出清楚中文关闭终态；房主权威状态已移除该离线玩家。飞行棋此负例含默认两个机器人，不计为后续无机器人 N10。网络覆盖均已恢复、两个浏览器正常回大厅、房主通过支持的离房协议收尾，容量回零。[超窗失败与收尾证据](./evidence/native-game-discovery/recovery-20261029/production-over-window-terminal-failure.json)。正在隔离工作树准备最小客户端修复，保护已通过的有效短重连、主动离房与 525 移除分支；M4 仍未完成。

## 2026-10-30 00:35 续验：772 服务端已部署

过期观战准入修复 `7723ae87194def2c1aff137497456cce53ebdcc1` 已于 00:25:02–00:25:13 CST 替换原服务，并于 00:26:26–00:26:32 完成归档冻结；生产 Web 仍为 b0、目录仍为 926。独立读回确认新容器健康、实际运行的三份编译文件摘要匹配，分别固定 OCI index、amd64 manifest 和 config，部署清单摘要由 `682f771f…` 变为 `808a8497…`。原环境与发布门禁保持，55 / 36 / b0 / 772 的八份源码和镜像恢复归档逐项校验通过，未实际执行回滚恢复。

匿名 HTTP 八类边界全部取得有效结果：首轮 7/8，一项在收到 HTTP 响应前出现 URLError，仅对相同 URL / headers 正常 TLS 复验一次后通过，共 9 个请求；原失败保留。此发布报告不包含原生验收、过期观战的生产 UI 复验或完整 269 项重跑。[脱敏发布与独立读回证据](./evidence/native-game-discovery/recovery-20261029/server-deployment-7723ae8.json)的 19 个私有证据摘要已由主代理逐项重新核对。原生首次重试仍在真实双账号导航诊断，最终 N10 及 926 的同构建 60 个性能样本仍未完成。

发布后的独立 UI 续验已完成同一 owned 过期房的玩家 / 观战两条真实路径：均显示“房间已过期”，实际 WebSocket 收到 ERROR 协议消息、错误码 400 后关闭，未收到 JOIN_ROOM、connection.ready 或房间 / 对局快照。matchmaking 本身返回 HTTP 200 reservation，不能把上述协议错误码写成 HTTP 400。两个拒绝连接及本轮诊断房正常收尾后，health 的连接 / 在线玩家 / 在线房间三项均为零。[过期准入修复生产复验](./evidence/native-game-discovery/recovery-20261029/production-expired-roles-after-772.json)。

另建 owned 等待房，通过正常“更换邀请码”轮换，当前 URL 和权威快照保留同一内部房间并采用新码；独立页面访问实际旧码，显示“邀请码不存在或已失效”，matchmaking 以 HTTP 400 / 数字错误码 400 拒绝，没有发起 WebSocket。该分支与过期房分别验收，确认不再把错误正文误当 seat reservation 后显示英文错误。随后第二账号经正常原生输入新码加入，权威快照确认同一内部房间、两名成员及两席均在线；该房继续用于原生重试修复复验，尚未收尾。[旧轮换邀请码生产复验](./evidence/native-game-discovery/recovery-20261029/production-rotated-old-invite-after-772.json)。

## 2026-10-30 00:16 续验：首次重试仍未修复

保留星纸三秒倒计时的用户决定已落实到当前工程目标。旧 9ba 的 60 个可操作样本及其资源正文仍可读、可重新核算，但 Nuxt / Pixi 版本与最终 926 不同，不能直接标记为最终 926 性能验收；正在准备同一最终 public 的复测。

原生重试先改为优先 `reload()`、URL 为空时回退初始 URL，7 项定向测试通过；简单回环页面未复现真实 Nuxt 空 DOM，不能用这些结果证明现网修复。安装指纹确认该源码后，新建双账号五子棋房，双方各落一子；只读确认唯一可见 WKWebView 的实际进程、调试器退出后精准 SIGKILL，随后仅点一次错误页“重新加载”，仍持续白屏。重新连接真实 WebKit 目标确认 URL 正确而 head / body 为空。该轮首次重试失败、不计为最终 N10。随后正常菜单重新载入恢复相同房间、game session、两名成员席位和两子摘要，双方新落子至四子，最终双方正常离房且浏览器收到 room.left 后连接关闭。[脱敏复验摘要](./evidence/native-game-discovery/recovery-20261029/native-first-retry-still-fails.json)。正在继续根因诊断，未把优先 reload 的尝试称为闭环修复。

772 服务端修复的源码、镜像和两份发布脚本已通过官方文件管理器上传。首次加载脚本在校验归档普通文件 / root 属主 / 0600 的组合条件时拒绝，尚未执行镜像加载、探针或应用重启；正在只读核查上传文件属性，保留原始失败回执，不绕过校验。

## 2026-10-29 23:50 续验：重启恢复与 WebContent 重试失败

用户已明确选择保留星纸三秒倒计时，按实际性能报告调整工程目标。当前需求、设计、任务 3.3 与产品计划已改为同条件至少 N10、准备后可操作 P50 优于旧入口、冷资源 P90 退化不超过 10%，分别披露倒计时与资源等待；旧 30% 目标及当时未达的历史结果保留。任务 3.3 尚未勾选，仍需核对最终候选绑定和资源等待证据。

本机于 23:10:43 CST 重启，旧 `/tmp/yunle-native-production.08darurg/` 已不存在。下方 b0 检查点的私有原始链接现不可访问，既有公开脱敏证据和本文阶段结果仍保留；不按历史 SHA 重造丢失的原始回执。已从 Git 对象恢复精确 Play `7723ae87194def2c1aff137497456cce53ebdcc1`，独立工作树和原 Play 未提交改动分别保护；恢复后的真实 SDK 准入回归 12/12、typecheck 通过，首次缺少依赖声明产物的失败另行保留。[恢复报告](./evidence/native-game-discovery/recovery-20261029/play-7723ae8-recovery.json)。772 的两行修复拒绝已过期房间的新观战连接；产物已完成隔离 HTTP / WS 验证，尚未部署。[产物摘要](./evidence/native-game-discovery/recovery-20261029/play-7723ae8-artifact-summary.json)。

已通过已登录官方控制台只读恢复远端 b0 发布脚本和小回执，原字节摘要一致；当前运行容器仍为 b0、健康。23:50 CST 的正常 TLS、禁止重定向公开 GET 确认目录仍为 926、4561 字节和原 SHA，health 200，当时容量三项为零；这不是重新完成 249 项静态资源检查。

新的真实双账号复现中，精准识别并退出唯一可见 WebContent 后，原生显示错误入口；第一次点“重新加载”仍出现白屏。重新连接调试目标后读到空的 head / body，此轮不计为 N10 通过。随后同一容器菜单“重新载入”恢复同房、同局、两名玩家席位及两子状态，双方继续落子至四子，最终双方正常离房、连接关闭。两条路径分别调用 `load(URLRequest)` 与 `reload()`；正在据此准备最小修复和回归，尚未将该差异写成已证实根因或修复闭环。新的原始证据已保存至仓库外持久私有目录，不再依赖旧临时目录。

## 2026-10-29 当前续验：b0 已上线，最终 N10 进行中

此前的兼容契约部署阻塞已解除。当前生产 Web 与后端均为 `b0f63be5b0780272d56f16d603eacb5afd2a58e8`：EdgeOne 生产部署 `dprefwc3xyr2` 于 21:18:02 CST 成功，后端部署于 21:44:54–21:45:05 CST 成功；后端运行配置、环境及既有发布门禁保持，未增加门禁。当前生产目录为 `9263452a8a0666c437d926ee09476d0a700e58cd3dffbacd6a2f73b46cb966a6`，正文 SHA256 为 `55eef13791c2a9069b4becad8583118f89b37ec578a75e5fd82ae30de65006df`。参与本轮真实验收的原生候选已安装、关闭 preview，并使用该生产目录，不再是早期“仅构建成功、尚未安装”的状态。

本次 Web 采用相对验收：655 条声明、249 个去重资源中，仅对新增或内容变化的 3 项重新发起生产 GET，字节数 / SHA / MIME / 原生公共缓存策略均通过；其余 246 项完整声明未变，离线重新核对保留正文的字节与 SHA，复用上一轮 `e3ef` 的 HTTP 证据，没有将其写成 b0 全量重新 HTTP 验收。4 个原生 JSON 保持 `max-age=60, must-revalidate`，9 个 HTML 与 `builds/latest.json` 保持 `max-age=0, must-revalidate`；9 个页面的 11 个基线公开配置字段逐项一致，无新增公开字段，联机开启、星纸在线仍关闭。AASA 源站字节与源码及上一轮一致；目录另补一次正常 TLS、明确 HTTP 200 / 原 URL 且禁止重定向的 GET，正文与已冻结目录一致，保留首次回执未记录 status / geturl 的事实。

后端发布后的一轮 8 项真实匿名 HTTP 边界检查全部通过：health 200；可信来源的无凭据创房 POST 返回 401，保留精确 ACAO、credentials、含 `Idempotency-Key` / `X-Request-Id` 的允许头与 `Vary: Origin`；恶意来源的创房 403、session 401 和无 Origin 的 health 200 均不返回 CORS 授权头，并保留 `Vary: Origin`。可信 / 恶意 / 无 Origin 的创房预检及可信 matchmaking 预检均符合策略。此前 36 版本实际观察到的恶意 Origin 反射和无 Origin 星号头失败保留，b0 已通过对应复验。该轮没有凭据、Cookie 或成功的创房响应；容量只是当时观察，不要求验收期间全站始终为零。

最终新房 N10 仍在执行。本次所读阶段记录中，五子棋 G01–G03 和飞行棋 F01 已通过，四房均已记录双方正常离开、连接关闭 / 原生终态及不再待清理；这只是五子棋 3 轮、飞行棋 1 轮的中间检查点，不代表各 10 轮完成。

| b0 真实房间 | 本检查点已确认的恢复与操作 |
| --- | --- |
| G01 · 五子棋 | 实际外部 Safari 锚点经 OS 冷启原生；恢复同房、同局、两名成员和席位，保留两子并接受恢复后的新落子；独立只读审计通过 |
| G02 · 五子棋 | 独立浏览器真实局部断网后 Colyseus 重连；同房同局，恢复后双方新操作继续被权威状态接受 |
| G03 · 五子棋 | 实际原生进程终止 / 重启后，经持久“返回上次房间”重新核验同房同局，恢复后接受新落子 |
| F01 · 飞行棋 | 实际 Home 后按图标回前台；同房同局、原有棋子保留，恢复后新的真人掷骰 / 移动被接受 |

本轮仍按五子棋、飞行棋各 10 个有效新房的既定计划继续；每轮记录真实创建、双账号加入、游戏操作、一种恢复及正常收尾，四类恢复分配覆盖，不要求每房重复所有故障与角色边界。观战、过期等剩余分支和后续修复结果另行验收，不归入上述 b0 通过事实。M4 尚未完成，M0–M5 整体仍未完成。M3 的点击至可操作 P50 降低 30% 门槛也未达到：既有同条件 N10 为五子棋改善 21.4%、星纸 8.0%；原三秒开场规则和原目标保留，新的联机 N10 不替代加载性能对照。

本检查点证据暂存于任务私有目录 `/tmp/yunle-native-production.08darurg/final-release-b0f63be/`：`edgeone-deployment-ui.json`、`backend-deployed-ui.txt`、`web-current/relative-audit-20261029T133541Z/final-summary.json`（SHA256 `c42f8d22516381d44f9c054a56f54e96f7d82d7f764576c9a44e0be4e46e77d6`）、`postdeploy-anonymous-20261029T134917Z/summary.json`（SHA256 `1ed959fa42bc315b1834f2a83c6308cb9cb4e14da27c92c83b888d6a85b13458`）、`g01-independent-cold-os-audit.json` 及持续追加的 `final-n10-ledger.json`。动态 ledger 含真实房间引用，本段只记录房间代号及已确认结果，不将其正文复制到公开报告。

> 以下保留历次检查点与失败原文；其中“未部署”“等待兼容环境”“未安装”及旧候选状态均对应当时观测，不能作为当前阻塞结论。当前上线状态和未完成范围以上述 b0 续验段为准。

## 历史检查点：2026-10-29 早期部署与最终修复候选之前的真实 M4

用户已授权发布生产兼容契约与星纸同源素材修复。后端 `55fe0e7d7c4c7f3c76579b1b2298eba8d37e90b6` 已部署健康；15:21:12 CST 再次匿名 GET / OPTIONS 全部通过，capacity 为 ok、0 连接 / 0 房间，星纸在线仍关闭，可信 Play 来源允许 `Idempotency-Key`。原运行配置和既有发布门禁保留。源码与 OCI 镜像归档已校验，部署清单以 CAS 更新，旧回滚输入保留；`restoreLoadTestPerformed=false`，尚未执行恢复演练。

最终 Web 为 `db02e67b2ebdffcdf575c3cfef44b6c826147ebd`，EdgeOne 生产发布 `dpjtxqxadmgw` 成功，与后端使用不同 commit。完整匿名复验中，655 次资源引用的 249 个去重 URL 全部字节数 / SHA / MIME / 原生公共缓存策略通过，249 项均为一年 immutable 缓存。4 个原生 JSON 保持 `max-age=60, must-revalidate`；9 个 HTML 与 `builds/latest.json` 保持 `max-age=0, must-revalidate`，没有被 immutable 规则误覆盖。11 个公开运行配置字段保持，联机开启、星纸在线关闭。

首次 Web `55fe0e7` / EdgeOne `dpnex6v8yt4k` 虽发布成功、249 项字节 / SHA 正确，但其中 16 个 Nuxt JS / CSS 的 `max-age=0` 导致原生缓存策略及整体 HTTP 检查失败；该轮原始证据与失败路径完整保留。后续 `db02e67` 补头发布解决了这 16 项，最终 `HTTPChecksPass=true`，没有将首轮失败追记为通过。AASA 源文件未变化，源站仍匹配；复用此前单次 Apple CDN 字节一致证据，没有重复 GET Apple CDN，也没有据此宣称 OS 冷启动投递通过。

独立匿名 in-app browser 已实际看到星纸 sprite，canvas 为 `is-ready`、opacity 1，菜单暂停 / 恢复正常，左右触控将教程从第 1 步推进至第 2 步；本轮采样 alert / warning / error 均为 0。没有登录、创房或完成完整教程，这次浏览器实测不替代原生 WKWebView 验收。[匿名实测 JSON](./evidence/native-game-discovery/production-star-browser-smoke.json)、[教程操作截图](./evidence/native-game-discovery/production-star-steering-accepted.jpg)、[生产发布截图](./evidence/native-game-discovery/production-edgeone-db02e67.jpg)。

Apps 当前源码和新构建内目录的 `catalogVersion` 均为 `9e76246e…`，与最终生产目录身份一致；[原生构建指纹](./evidence/native-game-discovery/native-build-sim-fingerprint.json)确认构建成功、构建时源码与 bundle 目录字节一致。新 Web 重建的 `generatedAt` 已变化，不能把最终 HTTP 正文与该构建快照称为逐字节相同。在该构建检查点，新候选尚未安装 / 启动，运行中的原生 App 仍是此前 preview 版本；构建成功不代表生产原生运行验收。

用户解锁后已继续真实生产验收，以下为最终修复候选安装前的不可变阶段检查点：生产 Web 仍为 `db02e67`，后端仍为 `55fe0e7`，原生已关闭 preview、正常访问生产；前述“新候选未安装 / 仍运行旧 preview”只描述更早的构建时刻。真实链路已取得下表结果，但两项新失败尚未闭环，最终候选的 20 个新房 N10 尚未运行，早期房间不计入该轮。M4 不勾选完成；M3 的 P50 降低 30% 目标仍未达到，M0–M5 整体保持未完成。

[脱敏 M4 阶段检查点](./evidence/native-game-discovery/production-m4-checkpoint-20261029.json)以原始检查点 SHA 固定 25 条事件；动态 live ledger 未修改，原始 UID、邀请码 / 房间链接、账号配置、私有数据库查询与网络正文未复制到仓库。

| 真实生产旅程 | 本检查点结果与边界 |
| --- | --- |
| 原生与独立浏览器登录 | A 的正常原生账号登录、Play 登录态及 B 的独立浏览器 SSO 已确认；根代理另已观察 C / D / E 正常原生登录，三个补充登录不冒称均记录在该 25 事件文件中。两端真实操作在服务端权威棋盘可见 |
| OS 冷启动 / 热重复邀请 | 原生已停止后，从实际 Safari 锚点触摸由 OS 投递并冷启，恢复账号、重新校验并加入同一房；随后热邀请回到同一进程 / 房间，成员仍为两个，后续落子接受。冷邀请准备期间旧席位已过期、服务端已重置等待局，未声称保留此前四子；稀疏 UI 观察时间不作首屏性能 |
| 冷 App 的持久房间继续 | 普通 App 重启且没有新邀请，寻乐“返回上次房间”恢复账号隔离的引用，校验原房 / 席位、保留两子，双方继续新操作 |
| Home 前后台 / 真实短断网 | 实际 Home 后按 App 图标返回保留棋盘、双方继续操作；B 端 CDP 短断网使真实传输关闭，再连接新的 WebSocket，原四子与角色保留、双方新操作接受，网络覆盖已恢复 |
| 实际 WebContent 退出恢复 | 只读识别唯一可见 WKWebView 的进程后实际 SIGKILL 该 WebContent；宿主 PID 保持，显示“游戏暂时无法加载”，点“重新加载”后校验同房、保留六子，双方均再接受新操作。这不是代理回调模拟；[错误 UI 原图](./evidence/native-game-discovery/production-m4-webcontent-termination-error.jpg)已持久保存 |
| 创房已提交但响应丢失 | 正常 UI 重试原请求，两次 POST 均为 201、同 key / 同返回 room ID；精确 creator + 创建时间窗口的只读数据库审计仅匹配一个 owned 创建文档。[数据库脱敏摘要](./evidence/native-game-discovery/production-m4-idempotency-db-audit-20261029.json)保留前四次投影参数失败和后两次成功；仅验证该操作窗口，不是全库无重复证明 |
| 成员 / 观战与移除换码 | 已是成员的账号请求观战被中文拒绝，成员数保持两个；在线 C 被正常移除、连接关闭并显示终态，邀请码轮换成功。不是永久封禁结论；旧码后续错误表现见下文 |
| owned 资源收尾 | 两个早期 owned 房间均通过正常离开 / 移除流程清理，待清理数为 0，未删除数据库。新增两个普通测试身份均 ready、实际余额 / 基线为 0、会员无记录，未增加角色 / 会员 / 云币，原三项凭据保留；[创建脱敏回执](./evidence/native-game-discovery/production-m4-managed-test-accounts-20261029.json)、[ready 列表](./evidence/native-game-discovery/production-m4-managed-accounts-ready.png)、[无会员截图](./evidence/native-game-discovery/production-m4-managed-account-no-membership.png)。两身份保留供受控验收，凭据仅在仓库外 0600 文件 |

新增失败均保留，不能用前述局部通过覆盖：

- 原生 generic room 已离开、收起后，继续列表不再显示它，但旧 `sessions[play]` 仍阻挡另一邀请码，实际提示“云乐坊间仍在运行”。[失败原图](./evidence/native-game-discovery/production-m4-closed-room-blocks-next-invite.jpg)。源码已最小修复，四项新回归均通过；保护活跃 / 可恢复不同房和普通 Play 页、同房 profile、旧回调及 legacy 单游戏数据。本检查点仍未安装修复候选完成真实复验。
- 已轮换的旧码在生产 matchmake 返回 HTTP 200，正文只有 `INVALID_INVITE_CODE` 和“邀请码不存在或已失效”；SDK 将其当作 seat reservation 后尝试 WebSocket，界面反而显示英文 `seat reservation expired.`。[确证脱敏 JSON](./evidence/native-game-discovery/production-m4-invalid-invite-transport-failure-20261029.json)。后端数字错误映射修复正在进行，生产尚未采用。

原生 `NativeGameRuntimeTests` 首轮 17 项为 **14 通过 / 3 失败 / 0 跳过**，三项失败均记录为 fixture WebKit store cleanup（network process 占用，另有一个 owned store 清理超时），不是 17 项全绿。四项新增修复回归逐项通过；随后只针对四个精确 owned UUID 的独立清理用例 **1 通过 / 0 失败 / 0 跳过**，不回写首轮结果。本检查点尚未纳入后续五项复测结果。[只读 xcresult 导出摘要](./evidence/native-game-discovery/production-m4-native-regression-20261029.json)、[截图索引与 SHA](./evidence/native-game-discovery/production-m4-screenshots-20261029.json)。

本地 Web E2E 保留三轮独立口径，未修改断言或超时：

| 运行条件 | 桌面 Chromium | 移动 Chromium | 总计 |
| --- | --- | --- | --- |
| 真实生产公开配置，全 190 项 | 76 通过、9 失败、1 主动跳过、9 串行未执行 | 77 通过、6 失败、3 主动跳过、9 串行未执行 | 153 通过、15 失败、4 主动跳过、18 未执行 |
| 仓库默认配置与静态 CDN 放行，定向 36 项 | 15 通过、3 失败 | 16 通过、2 失败 | 31 通过、5 失败 |
| 精确旧源码 `d57358d` 同条件对照 8 项 | 1 通过、3 失败 | 2 通过、2 失败 | 3 通过、同 5 项失败 |

默认配置定向轮中，完整 2.5D 串行组、星纸教程 / 合作夹具、发布门禁和本地蛇均通过。剩余五项弹珠机失败为三次 60 秒超时和两次 48 枚吐币计数断言，在旧源码中按 project / test 逐项复现，未发现这组失败由本次变更新增的回归；这不是全量 190 项通过的结论。E2E 的 API / SSO 外网均阻断，后两轮只放行静态 CDN；真实账号与生产联机仍由 M4 实测决定。

[本轮脱敏部署与验收证据](./evidence/native-game-discovery/production-deployment-20261029.json)保留两轮发布、旧 16 项失败、最终完整复验摘要、E2E 与构建边界。原始大正文和日志仍在任务私有目录，未将公开配置 access key、账号密码、Cookie 或 token 写入文档。两个任务独占容器上下文回收 3,837,952 B 已分配文件字节；旧 Web 对照目录另回收 56,356,864 B（约 53.7 MiB），保留各自口径，不合称整盘空间释放。源码归档、镜像、release 工作树 / 依赖及原生 DerivedData 保留。

> 下方为此前实施与验收记录，保留历史原文及失败证据。其“未部署”“六处 404”“等待兼容环境”和旧候选状态属于当时观测；截至本轮的生产状态以上述续验段为准。静态缓存头发布检查已通过，真实 M4 与 M3 目标仍未完成。

更新：2026-10-29。M0–M5 尚未全部验收；本轮本地收尾完成，剩余真实联调等待兼容环境。[专项计划](../product/native-game-discovery.md)和仓库中的 `specs/native-game-discovery/tasks.md`区分源码、本地验证与发布验收。相同部署阻塞已在连续三轮及本轮复核中存在，可独立完成的本地工作已完成；[阻塞审计](./evidence/native-game-discovery/goal-blocked-eligibility-audit.json)保留回合、现网证据及未完成门槛，不将目标标为完成。

最新续验状态见[旧主程序真实目录入口续验摘要](./evidence/native-game-discovery/legacy-native-ui-followup-summary.json)。它接续[旧原生 HTTPS 与纹理诊断总摘要](./evidence/native-game-discovery/historical-native-followup-summary.json)、[启动与持续游戏诊断总摘要](./evidence/native-game-discovery/startup-gameplay-acceptance-summary.json)、[逐项完成审计](./evidence/native-game-discovery/startup-gameplay-completion-audit.json)和[容量回收摘要](./evidence/native-game-discovery/reclamation-acceptance-summary.json)；历史结果及失败记录保留。

## 已实现

- 四个 Tab 保持「云居、寻乐、工坊、我」。工坊承接官方精选、随手发现、有效运营推荐 / 周榜、搜索、分类和 AI 找应用；搜索时突出结果，个人工坊、作品、成员管理路径保留。只读推荐接口未发布时使用诚实的目录分组，不伪造周榜。
- 寻乐提供五子棋、飞行棋、星纸的原生目录、模式入口、继续游玩、最近记录、房间输入 / 分享。模式使用发布状态；本地目录关闭的联机模式保留「在 Play 查看玩法」兼容入口，这不代表线上全局联机停用。
- 按模式直达复用 Play 权威游戏和授权。启动操作绑定 origin、launch ID、游戏、模式与账号；engine-ready 与 room-ready 分别计时，仅真正 engine-ready 写最近记录。市场 UUID 与游戏 slug 复用一个会话；已有 active / retained 游戏 profile 优先保留，新游戏使用显式 Play 身份作用域。
- 游戏资源准备包含清单、真实字节 / SHA256 / MIME 校验、25 MB 单款 / 200 MB 总额限制、Wi-Fi 选项、取消、HTTP 缓存清理。实际游戏和准备过程使用同一个命名 WebKit 数据仓库；不缓存账号接口和房间状态，不用首页归档启动游戏。共享空间清理会解释对其他游戏资源的影响，保留 Cookie 和存档。
- 邀请仅保存账号隔离的房间引用，恢复时重新查询 Play；原生登录续接防止取消、迟到证明、重复消费和账号变化造成误跳转。延迟动作同时绑定账号和选择代次，已有 Play 快照时后台刷新不阻塞续接；退出或失败的房间重入采用新操作并保留原 profile，换码导航保留启动上下文。分享 / 复制 / 浏览器打开统一输出 canonical URL，不带启动标识或登录返回参数。
- 游戏容器支持模式方向、收起 / 恢复；网络失败或 Web 进程终止显示重试与返回入口。没有市场条目的游戏不展示失效详情 / 评分，游戏菜单不进入通用应用归档缓存。

Play 配套源码位于相邻 `YunLeFun/play` 仓库：单一游戏目录、原生 JSON / 资源清单、模式准备页、真实 lifecycle、房间状态、登录返回、AASA 和静态头配置。当前候选目录为 `9ba070328a0cce53691378e6a631c0239b5a7f9f926ad61504e8c1da4e4f0405`，已同步原生 bundled snapshot；上一轮 `48b468ef…` 与中间 `934733dc…` 只作历史记录。

## 本地验证

| 检查 | 结果与边界 |
| --- | --- |
| 原生 `build-for-testing` | 通过；Xcode 27.1，Simulator SDK 27.1，保留 iOS 16 安装下限，不等于最低系统实跑 |
| 原生目录 / lifecycle / 登录 / 资源策略 / 既有 profile 回归 | 集成轮次 72 / 72 通过；后续会话 / 身份 / 链接检查 22 / 22 通过；前轮账号 / 延迟启动 / 房间重入回归 42 / 42 通过（含 1 条登录取消 UI） |
| 本轮账号 / 缓存 | 92 / 92 执行项通过，另 9 项要求关闭 preview 的容器用例明确跳过；其中初始恢复 18 项全部通过。随后关闭 preview 补跑容器 10 / 10，通过且无跳过；不是把跳过算成功 |
| WebKit 实际资源缓存 | 首轮 214 项验证保留；本轮真实五子棋 215 项在准备后、503、错误摘要及取消后均逐字节 / SHA cache-only 验证通过，资源回执 B 为 216 项。补测真实 IndexedDB 后故障流程再次通过；实际活跃棋局继续落子，HTTP 清理后新 runtime 联网启动且三类网站数据均保留 |
| 旧数据与身份保护补验 | 82 / 82，无跳过：HomeLibrary 25、NativeRuntimeSession 21、LegacyImport 19、WebProfileRepository 17，覆盖排序 / Dock、旧导入、真实 Cookie / localStorage / IndexedDB、账号隔离、仓库重建和结束 / 收起；37 个独占 WebKit store 均经 API 确认移除 |
| 核心原生 UI | 游戏入口与无效邀请码、工坊 AI 进入 / 返回 / 搜索、帮助导航通过；客态房间登录取消首次遇到 AX 坐标失败，固定测试设备竖屏后单项重跑通过。本轮 4 条旅程再次全部通过；组合轮次同时有 2 项容器 fixture 清理失败，已保留记录，后续独立容器 10 项全过，不把失败组合轮次改写成全绿 |
| 本地实际游戏启动 | 最终候选真实可操作口径 60 / 60 样本完成；星纸 30 次均为 `phase=playing` 且渲染器完成。两款准备后 P50 分别改善 21.4% / 8.0%，未达 30% 工程目标；直达冷资源 P90 均改善 |
| 最大动态字号 | 寻乐 / 工坊在 AX XXXL 下五类自动语义审计均零问题；修复搜索提示截断，不缩小用户字体。此结果不等于完整 VoiceOver 手势旅程 |
| VoiceOver 与减少动态效果 | 系统设置真实 0→1→0，UIKit 确认启用期间完成 90 条焦点 / 朗读事件和定向操作：模式、邀请错误 / 取消、进游戏 / 收起 / 继续、工坊 AI / 返回。最终 1 / 1 通过，VoiceOver 恢复关闭；不是无坐标盲用或游戏内容完整读屏验收 |
| 保留会话恢复 N10 | 两款各 10 次，20 / 20 完成；严格保留 WebView / profile / launch、原 Document / 根元素引用和单次 ready，恢复后可见且真实游戏 handler 接受输入。最终独立用例通过，原时钟断言失败轮次保留 |
| 会话容量与内存回收 | 三种实际容器用例 3 / 3 通过、无跳过：容量超限、有前台时通知、全部暂停时通知；最近记录和三类网站数据保留，重开使用同 profile 的新 WebView / launch，旧回调被拒绝，旧对象弱引用最终释放。通知为进程内模型，不代表实际 OS 压力或 WebContent 退出 |
| 启动分段诊断 | 三轮各两款 N3、各 1 项测试通过；九阶段诊断与同轮资源 / 服务器关联均有 6 样本。多数等待在 `web.load` 返回之后；不是新的 N10 或 30% 达标结果 |
| 空白页预初始化机制实验 | 五子棋两条件各 N3，执行用例 1 / 1 通过，但未见可信启动收益；含初始化的中位成本 1426.47 ms，高于普通路径 749.37 ms，未采用产品改动。实验代码已精确移除，原始样本和复现 patch 保留 |
| 精确旧 native / 现网 HTTPS | 旧 `e68ed57d…` Debug 构建与安装通过；五子棋两条件各 N10，独立用例 1 / 1 通过，均实际落黑子并收到电脑白子。首次双游戏 N1 整轮、星纸渲染诊断及独立纹理 CORS 用例各失败 1 项，均保留，不能记为全部通过；Star 与完整历史基线仍未完成 |
| 旧主程序真实目录入口 | 正常旧主程序、无运行中的测试 harness，实际工坊→游戏分类→公开「云乐坊间」→详情「试用」→Play 首页→菜单结束返回详情已走通。自动登录面板仅取消空字段；不代表登录成功、游戏 ready、性能计时或完整 M0.1 |
| 星纸持续交互与内存诊断 | 原生模拟器独立用例 1 / 1 通过；同一真实 local 游戏两轮约 10 秒，记录 1219 个 rAF 间隔及分列的宿主 / 关联 WebContent RSS。合成输入被真实 handler 捕获，tick 与累计开火推进；仅为 Simulator / Debug 诊断，不是 GPU 呈现 FPS、泄漏结论或真机性能 |
| 本地联机协议 | 三款各 10 轮，30 / 30 通过；五子棋 / 飞行棋双客户端，星纸四客户端，真实 HTTP 创房 / ticket、Colyseus SDK / WebSocket、权威操作、主动断线与同局恢复。使用内存数据和测试身份，不代表原生 SSO 或生产端到端验收 |
| 工坊只读接口 | 4 项 TypeScript 测试与限定 ESLint 通过 |
| 最终 Play 配套 | 58 条预渲染路由、独立 vue-tsc、host / renderer / 换码 34 项、catalog 3 项、export 4 项与限定 ESLint 通过 |
| 产品 / 实施文档 | VitePress 完整构建通过；使用已安装的本地二进制，未绕过包管理器信任检查，任务输出已回收；[前轮记录](./evidence/native-game-discovery/final-docs-build.json)、[补验构建](./evidence/native-game-discovery/reclamation-docs-build.json)、[启动诊断报告构建](./evidence/native-game-discovery/startup-gameplay-docs-build.json)、[历史 N10 报告构建](./evidence/native-game-discovery/historical-native-docs-build.json)、[本轮构建记录](./evidence/native-game-discovery/legacy-native-ui-docs-build.json) |

原始样本：[启动 N10](./evidence/native-game-discovery/startup-n10.json)、[预检](./evidence/native-game-discovery/startup-preflight.json)、[30 轮协议](./evidence/native-game-discovery/local-room-recovery.json)、[分轮测试摘要及失败记录](./evidence/native-game-discovery/validation-summary.json)、[最大字号断网重试](./evidence/native-game-discovery/manual-loading-retry.json)。

## 最终候选启动测量

目录 `9ba07032…` 在同一 public、同一命名 profile、固定 iPhone 18 Pro / iOS 27.0 和回环 HTTP 下，完成两款游戏、三种路径各 10 次，共 60 次。星纸保留三秒开场规则，30 次均在真实 `phase=playing`、渲染器完成后才收到宿主 ready。[完整样本](./evidence/native-game-discovery/operable-final-n10.json)、[计算结果](./evidence/native-game-discovery/operable-final-metrics.json)、[测试摘要](./evidence/native-game-discovery/operable-final-test-summary.json)。

| 游戏 / 模式 | 同构建旧路径冷资源 P50 / P90 | 直达冷资源 P50 / P90 | 准备后直达 P50 / P90 | 准备后 P50 相对旧路径 |
| --- | --- | --- | --- | --- |
| 五子棋 / 电脑对手 | 1055 / 1719 ms | 838 / 1424 ms | 829 / 1458 ms | 缩短 21.4% |
| 星纸 / 本地练习 | 4193 / 4311 ms | 3865 / 3923 ms | 3859 / 3954 ms | 缩短 8.0% |

结论：30% 初始工程目标未满足，任务 3.3 保持未完成。直达冷资源 P90 分别改善 17.2% / 9.0%，满足不退化超过 10% 的门槛。星纸渲染器观察的文档时钟中位数为旧路径 714 ms、直达冷资源 410 ms、准备后 366 ms；该时钟与原生点击计时不同，不能直接相减。固定开场倒计时仍占总启动时间的大部分，不通过提前发 ready 或改变规则来宣称提速。

针对本测星纸旧路径 P50 4192.96 ms，降低 30% 所需阈值为 2935.07 ms，已经低于新开局必须经过的三秒规则；即使理想化消除技术加载开销，仅靠加载优化也不能达到该总耗时阈值。这是当前基线与启动规则的约束，不是通用硬件性能下限。[源码与计算审计](./evidence/native-game-discovery/startup-countdown-constraint-audit.json)。已向用户请求选择「保留规则，另评技术加载与总启动」或「允许调整本地开场体验」；尚未收到答复，继续保留原规则、原 30% 目标和任务未完成状态，没有自行缩小验收范围。

P50 / P90 使用 nearest-rank，N10 分别取排序后的第 5 / 9 个值。每次创建新 WKWebView，冷组仅清理 HTTP 内存 / 磁盘缓存；不重置系统或 WebKit 进程。目录和账号预先就绪，关闭 UIKit 动画，旧路径每 20 ms 点击已显示的真实链接。这是同构建路径对照，不是历史原生提交、真实用户思考时间、公网或真机性能基线。Resource Timing 仅覆盖各主文档的已完成请求，未完整覆盖 pending / Worker 请求，零 transferSize 也不能单独证明缓存命中；缓存完整性另有逐项 SHA 证据。

### 同一原生时钟的启动分段

后续使用同一 `ProcessInfo.systemUptime` 记录调用入口、present 进入、初始 loader、`web.load` 返回、呈现完成和真实 ready。首轮两款各 N3，6 / 6 完成，[原始阶段](./evidence/native-game-discovery/startup-native-phase-first.json)、[测试摘要](./evidence/native-game-discovery/startup-native-phase-first-summary.json)。源码和记录均未显示等待呈现完成才发起 load 的固定串行门槛，多数等待发生在 `web.load` 返回后。

第二轮在独立 content world 加入被动 document-start / DOMContentLoaded / window.load 消息，并校验同一 WebView、controller、主 frame、origin、精确路径和随机 nonce；各阶段仍只用原生收信时钟。两款各 N3 再次完成，六份均确认同一准备 profile；星纸三份均为 `phase=playing`、rendererReady=true。[九阶段原始数据](./evidence/native-game-discovery/startup-document-phase-n3.json)、[通过摘要](./evidence/native-game-discovery/startup-document-phase-summary.json)、[核对与中位数](./evidence/native-game-discovery/startup-document-phase-metrics.json)。

| 游戏 / 模式 | 调用至呈现完成范围 | load 返回至 document-start 收信范围 | document-start 收信至真实 ready 范围 |
| --- | --- | --- | --- |
| 五子棋 / 电脑对手 | 29–139 ms | 560–1115 ms | 148–582 ms |
| 星纸 / 本地练习 | 48–51 ms | 544–1120 ms | 3158–3175 ms |

UIKit 配置和呈现主要为数十毫秒，五子棋首样本呈现完成为 139 ms；仍有约 0.54–1.12 秒落在 load 返回至文档消息收信之间。这个区间包含 WebKit 导航、调度、IPC 和额外观察开销，尚不能单独归因于网络、HTTP 缓存或新进程。星纸在文档消息后仍等待约 3.16–3.18 秒，与保留的三秒开场规则一致；没有提前 ready 或缩短倒计时。此处为预置账号 / 目录、关闭 UIKit 动画、回环来源的新 WebView 诊断；N3 不能替换前述 N10，不能用于宣称性能改善或 30% 达标。文档阶段是原生收信时间而非精确 JS 执行时间，也没有与文档时钟直接相减。

第三轮在同一次两款各 N3 的诊断中取回既有 collector 于真实 ready 冻结的主文档 Resource Timing，并用启动 UUID 的 SHA256 前 16 位关联本地服务器请求；哈希只用于匹配样本，不转换时钟。六份 HTML 请求均唯一匹配，服务器 request 至 finish 为 0.60–2.85 ms，文档时钟的 navigation responseEnd 为 4–10 ms，同时原生 `web.load` 返回至 document-start 收信仍为 522–1107 ms。[6 样本原始记录](./evidence/native-game-discovery/startup-resource-phase-v3.json)、[测试摘要](./evidence/native-game-discovery/startup-resource-phase-v3-summary.json)、[逐样本关联与边界](./evidence/native-game-discovery/startup-resource-phase-v3-analysis.json)、[同轮服务器追踪](./evidence/native-game-discovery/startup-request-trace-v3.json)。

这六份记录不支持将原生长区间直接归因为主 HTML 的服务器处理缓慢，也不能证明全部延迟来自 WebKit 新进程。三个时钟只计算各自内部差值，不能互相相减来分摊剩余时间；服务器 finish 不包含客户端收取、导航或脚本执行。资源快照只覆盖截止点前完成的主文档请求，未穷尽 pending / Worker 流量；并行时长相加不等于墙钟等待，零 transferSize 也不能单独证明缓存命中。N3 和追踪观察开销均保留，没有替换 N10、宣布 30% 达标或据此采用产品优化。

### 未采用的空白页预初始化实验

针对 load 后等待另做一次有明确边界的机制实验：同一已准备 named store 内，交替执行五子棋普通 fresh WebView 与额外保留 inert `about:blank` 的条件，各 N3，共六样本。资源只共用准备一次，条件间不清 HTTP 缓存，也不重置 WebKit / 系统；普通条件表示没有额外 blank，不是 OS 冷启动。[预先范围](./evidence/native-game-discovery/blank-warmup-experiment-scope.json)、[原始六样本](./evidence/native-game-discovery/blank-warmup-phase-n3.json)、[执行摘要](./evidence/native-game-discovery/blank-warmup-phase-summary.json)、[逐样本分析](./evidence/native-game-discovery/blank-warmup-phase-analysis.json)。

| 条件 / N3 中位数 | 原游戏启动调用至真实 ready | 本轮开始至真实 ready，含 blank 初始化 |
| --- | --- | --- |
| 普通，无额外 blank | 748.21 ms | 749.37 ms |
| held blank | 768.08 ms | 1426.47 ms |

共用资源准备另行记录，不包含在表中本轮成本。三次 blank 初始化为 612.8–656.8 ms，均核对 `about:blank`、零已观察资源及同 profile，并持有至真实游戏 ready；三次随后弱引用对象均在有界等待内释放。RSS 按本次宿主日志关联、进程 basename 与起始时间核对后分 PID 记录；窗口短且部分普通条件没有 WebContent 样本，缺样本不表示没有进程，也不据时间先后把 PID 指定为 blank 或游戏，更不将 RSS 相加称为独占内存。[RSS 原始记录](./evidence/native-game-discovery/blank-warmup-phase-rss.json)。对象释放不证明 WebContent 退出或 RSS 释放，SDK 也不承诺独立 blank 与游戏复用同一进程。

本次小样本没有可信的点击收益，计入初始化后成本更高，因此没有采用产品改动；结论仅针对此范围，不宣称所有预热方案都无价值，不替代 N10、30% 门槛或真实账号代次验收。新增 227 行实验块已精确移除，主仓库测试源码恢复至 SHA256 `31549f9da304677682671eb937156f9f99ff022193796b243eda4e060cafbd0c`；输入、实验 SHA、完整 patch 与 runner 条件已[归档复现](./evidence/native-game-discovery/blank-warmup-phase-inputs.json)。星纸倒计时、原目标和未完成状态保持。

### 存活会话恢复

同一 `9ba` 本地候选另测实际收起后继续，各 10 次。计时从原生 `resumeGame` 调用前开始，第一终点是容器已呈现、同一页面连续两帧可见且真实模式可操作；第二终点再确认原游戏 handler 接受输入。没有重新发送 engine-ready，也没有以历史 ready 直接结束计时。[20 次原始样本](./evidence/native-game-discovery/retained-resume-final-n10.json)、[通过摘要](./evidence/native-game-discovery/retained-resume-final-summary.json)。

| 游戏 / 模式 | 可见可操作帧 P50 / P90 | 真实 handler 接受输入 P50 / P90 |
| --- | --- | --- |
| 五子棋 / 同屏双人 | 95 / 116 ms | 117 / 141 ms |
| 星纸 / 本地练习 | 95 / 193 ms | 369 / 395 ms |

20 / 20 保留同一 WebView、named profile、launch、随机 marker 以及原 Document / 根元素对象的严格 `===`，ready 回调始终为一次。五子棋每次实际多一颗棋子，星纸每次 fireSequence 与 tick 推进，阶段始终为 playing 且 rendererReady 为 true。原生观察每 50 ms 轮询，JS 回传每 20 ms；fixture 关闭 UIKit 动画，数值是观察上界，输入是调用真实 handler 的合成点击 / Space。`documentHasFocus=false` 已原样记录，不宣称物理触控或键盘焦点。此处测同进程存活会话，不能代替 OS 挂起、进程回收、App 重启或线上房间恢复；五子棋此表为同屏模式，也不能与前表电脑模式直接计算提速。它不使 30% 新启动目标达标。

首次 N10 虽收齐 20 样本，但一项 `performance.timeOrigin` 精确相等断言出现 1 ms 差值，整轮仍按失败保存。最终改用直接保留的 Document / 根元素引用验证身份，没有增加浮点容差；每次时钟初值、观察值及原始差值仍保留。最终 20 次差值均为零。[全部尝试及失败记录](./evidence/native-game-discovery/followup-validation-history.json)。

### 持续交互与进程内存诊断

仓库中 `specs/native-game-discovery/design.md` 第 7 节要求星纸记录帧时间、卡顿与内存。此前证据未覆盖持续游戏采样，现以当前 `9ba` 的真实 local 游戏补齐原生模拟器诊断：独立用例 1 / 1 通过，同一 WebView / profile / launch / Document 连续两轮，ready 始终一次；CSS canvas 为 874 × 210，`document.hasFocus=false`。Space 与交替方向键是合成 KeyboardEvent，真实 window handler 的捕获已核对，tick 两轮为 91→399、400→705，累计 fireSequence 为 -1→39→79；这证明持续处理与实际开火推进，不代表每个按键都射击。[原始两轮](./evidence/native-game-discovery/paper-star-frame-memory-n2.json)、[测试摘要](./evidence/native-game-discovery/paper-star-frame-memory-summary.json)、[计算与边界](./evidence/native-game-discovery/paper-star-frame-memory-analysis.json)、[复现输入](./evidence/native-game-discovery/paper-star-frame-memory-inputs.json)。

| 轮次 / 原生观察时长 | rAF 间隔数 | 间隔 P50 / P90 / P99 | 最大间隔 | >33.333 / >50 / >100 ms |
| --- | --- | --- | --- | --- |
| 1 / 10.47 s | 610 | 17 / 17 / 18 ms | 28 ms | 0 / 0 / 0 |
| 2 / 10.19 s | 609 | 17 / 17 / 23 ms | 29 ms | 0 / 0 / 0 |

两轮采集均未因上限丢弃间隔（droppedIntervals=0），分位数按各轮原始数组 nearest-rank 计算。rAF 间隔描述 JS / 主线程回调交付，不是 GPU 呈现帧率或物理屏幕 FPS；上述长间隔阈值是诊断定义，没有把零计数当通用卡顿验收标准。记录包含 Simulator / Debug、合成输入、观察器及 JSON 开销，fixture 关闭 UIKit 动画，不能外推其他分辨率、场景、联机或真机。

游戏窗口内通过外部 `ps` 每约 0.5 秒记录进程 RSS，宿主和 WebContent 各有 39 个样本：宿主 PID 23030 为 423632–440208 KiB，包含 XCTest；本次宿主日志明确关联的 WebContent PID 23288 为 353072–400464 KiB，窗口末为 375824 KiB。关联另核对 executable basename 与稳定的进程起始时间，按日志中 BEGIN / END 的观察时间划分窗口，保留日志交付与轮询误差。[RSS 原始记录](./evidence/native-game-discovery/paper-star-frame-memory-rss.json)。两类 RSS 分列、不合计，也不称独占游戏内存、physical footprint 或 JS heap；短期增长不能推断泄漏，亦不能证明内存稳定或无泄漏，GPU / Networking 进程未计入。此处补齐设计要求的模拟器诊断记录，真机性能仍按计划后续单列，M3 / M4 / M5 的未完成门槛不因此通过。

## 历史启动测量（旧星纸事件口径，不能作为 R4 达标证据）

最新对照使用目录 `48b468ef…`、同一静态构建和同一命名 profile，固定 iPhone 18 Pro / iOS 27.0 模拟器、回环 HTTP。五子棋电脑对手、星纸本地练习分别跑旧首页→详情→模式、直达冷资源、准备后直达各 10 次，共 60 次，全部收到当时的引擎回调。[完整样本及资源时序](./evidence/native-game-discovery/entry-comparison-n10.json)、[构建目录](./evidence/native-game-discovery/entry-comparison-catalog.json)。

| 游戏 / 模式 | 同构建旧路径冷资源 P50 / P90 | 直达冷资源 P50 / P90 | 准备后直达 P50 / P90 | 准备后 P50 相对旧路径 |
| --- | --- | --- | --- | --- |
| 五子棋 / 电脑对手 | 1082 / 1638 ms | 936 / 1455 ms | 882 / 1552 ms | 缩短约 18.5% |
| 星纸 / 本地练习 | 1572 / 1999 ms | 1569 / 2071 ms | 1096 / 1406 ms | 缩短约 30.3% |

后续源码审查发现星纸旧 ready 只等渲染器，三秒倒计时中物理尚未推进，射击仍被拒绝；本表因此不能证明 R4「可操作」或 30% 门槛已达到。旧测量的其直达冷资源 P90 相对旧路径增加约 3.6%，五子棋则下降，均在 10% 范围内。该结果接近阈值，仍需在更真实的网络与候选 UI 上复核，不宣称公网或历史旧版本达到相同收益。此前只比较直达冷资源 / 准备后的 40 次样本仍保留在[首轮原始数据](./evidence/native-game-discovery/startup-n10.json)和[对应目录](./evidence/native-game-discovery/startup-n10-catalog.json)，不能拿其中单次预检代替 N10。

条件与局限：

- 每次新 runtime，冷组仅清理该 profile 的 HTTP 内存 / 磁盘缓存；不重置 WebKit 进程、系统缓存或模拟器。账号与目录在 fixture 中预先就绪，不包含 App 初次恢复 / 首次目录等待。
- 原生 uptime 记录容器发起至真实 engine-ready，fixture 关闭 UIKit 动画。旧路径按 20 ms 轮询尽快点击可见真实链接，可能经历 SPA 或完整文档跳转，不模拟人类思考时间；它是当前同版本的路径对照，不是旧提交历史基线。
- 各文档在导航点击前或真实 ready 时冻结 Resource Timing，同一文档取最新截止点。点击后到 unload 之间的 pending 请求、Worker 请求未完整覆盖；并行资源耗时之和不是墙钟等待，零 transferSize 不能单独证明缓存命中。
- 观测到星纸直达组主文档资源传输中位数约 3.41 MB → 12.6 KB；缓存另有同 profile 的 cache-only / 摘要校验证据。记录包含导航自动化与时序观察开销，不作为硬件性能数据。
- 早期浏览器对照统一了外部资源 CORS 响应，只说明导航路径差异，不能证明真实 CDN、原生加速或生产可用性。

### 精确旧 native / 现网 HTTPS：五子棋 N10 与星纸失败

已从精确 commit `e68ed57d523997a1bc669a5586f925d79c352fb0` 提取 `apps/ios` 与其实际共用的 `apps/mobile/ios/App/App`，共 279 个文件、3,334,807 字节；不复制当前未提交修改、依赖或构建输出。[逐文件输入清单](./evidence/native-game-discovery/historical-native-source-input.json)。归档副本完成独占构建身份隔离：App ID `fun.yunle.apps.native-legacy-01a182f1`、app group `group.fun.yunle.apps.native-legacy-01a182f1`、URL scheme `yunlefun-legacy-01a182f1`，测试与扩展使用各自独占 ID；Debug `-Onone` 构建、安装已通过，不用旧 Benchmark `-O`。[打包补丁与 SHA](./evidence/native-game-discovery/historical-native-packaging-patch.json)、[配置核对](./evidence/native-game-discovery/historical-native-verified-build-settings.json)。后者是构建前的冻结记录，实际构建 / 测试状态另见[本轮总摘要](./evidence/native-game-discovery/historical-native-followup-summary.json)。

观测 harness 仅追加在归档旧测试文件，原文件前缀逐字节一致，保留旧 `NativeWebRuntime.open`、旧缓存分支与原始 WebView 加载流程，没有回移新 Game model、runtime 或 ready。其独占访客 fixture 打开正常 `https://play.yunle.fun/`，滚动至可见并点击真实 mounted 首页→详情→模式链接。[完整测试追加补丁与 runner](./evidence/native-game-discovery/historical-native-harness-inputs.json)、[实际编译输入核对](./evidence/native-game-discovery/historical-native-compiled-inputs.json)。计时从旧 runtime.open 前开始，到原生收到公开 DOM 观察结果；不包含更早的原生目录 / 详情选择，不是物理触控计时，也没有旧版本不存在的 native-ready 信号。首次正常旧主界面尝试搜索 ASCII `play` 未显示对应应用，中文输入遇到工具失败；旧搜索匹配名称 / 标签等内容、不匹配网址或 ID，这次结果不能证明 portal 缺失。[原尝试与失败索引](./evidence/native-game-discovery/historical-native-evidence-index.json)保留，真实目录入口另按下段补验。

后续对原 CatalogService 的匿名正常 TLS 查询返回真实公开且获批的 Play 条目：`app_55d184f8cda84547a18e41848faf0084`，名称「云乐坊间」，地址 `https://play.yunle.fun/`，未要求付费或会员。[公开目录定位](./evidence/native-game-discovery/legacy-native-public-play-catalog-lookup.json)、[公开详情](./evidence/native-game-discovery/legacy-native-public-play-detail-lookup.json)。据此只重建归档旧主程序，Debug / -Onone、约 29 秒构建通过，未编译或运行该旅程的测试 harness。实际界面完成「工坊→分类：游戏→真实条目→详情：试用」；没有点击「获取」、伪造行或以直接 URL 启动替代目录。旧 runtime 打开后自动出现原生登录面板，仅取消空字段，没有输入凭据、验证码或授予授权；随后实际 Play 首页视觉呈现「云上相聚／坊间开局」及选游戏入口，更多菜单显示 canonical `https://play.yunle.fun`，原生菜单「结束」返回真实详情。[完整实际旅程](./evidence/native-game-discovery/legacy-native-real-catalog-ui-journey.json)、[截图与 SHA](./evidence/native-game-discovery/legacy-native-real-ui-screenshots.json)。这补齐此前目录→详情→portal 的功能证据，不代表原生登录成功、游戏可操作、房间操作或性能计时，不改变上述 N10 的起止定义及完整 M0.1 未完成状态。

首次双游戏 N1 中五子棋实际落黑子、电脑回白子成功，但星纸未达条件，整轮仍为失败：[五子棋组件](./evidence/native-game-discovery/historical-native-gomoku-preflight-n1.json)、[星纸失败](./evidence/native-game-discovery/historical-native-star-preflight-failure.json)、[整轮失败摘要](./evidence/native-game-discovery/historical-native-https-preflight-test-summary.json)。随后五子棋独立 N10 用例通过 1 / 1，无跳过，共保留 21 行：一个明确的普通 prime，之后交替进行 HTTP 缓存清理与自然缓存 fresh-view 各 10 次。prime 不纳入两条件分位数，没有删除原始行。[N10 原始数据](./evidence/native-game-discovery/historical-native-gomoku-https-n10.json)、[计算与边界](./evidence/native-game-discovery/historical-native-gomoku-https-metrics.json)、[通过摘要](./evidence/native-game-discovery/historical-native-gomoku-n10-test-summary.json)。

| 五子棋 / 电脑对手，各 N10 | 可落子控件观察 P50 / P90 | 真实黑子观察 P50 / P90 | 电脑白子观察 P50 / P90 |
| --- | --- | --- | --- |
| HTTP 内存 / 磁盘缓存清理后 | 3249 / 3504 ms | 3388 / 3632 ms | 3702 / 3944 ms |
| 随后自然缓存、新 WebView | 2423 / 2583 ms | 2466 / 2626 ms | 2707 / 3053 ms |

控件可落子不是 Worker 初始化完成的证明，黑子验证真实输入接受，白子端点还包含电脑思考规则。本表使用各条件 10 次完成行的 `(N−1)q` 线性插值分位数，与前述 current-build 表的 nearest-rank 方法分开记录。旧默认竖屏 WebView 为 402 × 758，UIKit 动画开启；自然缓存条件固定跟在对应清理条件之后，可能续用进程、DNS、TLS 等状态。清理只证明指定 HTTP 内存 / 磁盘缓存 API 回调完成，不代表 OS 冷启动或缓存必为零；没有准备下载、额外 keeper、修改游戏或清理 Cookie / localStorage / IndexedDB。原始 `cookiesLocalStorageIndexedDBPreserved=true` 仅表示删除类型排除了它们，未做 marker 读回；fixture 清理记录为真实回调和空 failedID 列表，没有再经枚举 API 确认不存在，不能扩写成此前 82 项或缓存故障专项的存储验证。

星纸随后独立渲染诊断仍失败：页面明确显示 world-sprites.png `TypeError: Load failed` 的 alert，虽有 canvas，祖先 `.paper-star-canvas` opacity 为 0 且未进入 `is-ready`；此时 phase=playing、tick 仍可推进，不能单凭 canvas 存在或逻辑状态算可玩。[渲染失败原始数据](./evidence/native-game-discovery/historical-native-star-renderer-failure.json)、[失败摘要](./evidence/native-game-discovery/historical-native-star-diagnostic-test-summary.json)。从同一旧 WKWebView 的原 HTTPS 首页发起独立 `mode=cors / credentials=omit` 纹理探测，planes 成功取得 200、956,518 字节及 SHA，world-sprites 返回 TypeError，本次监听未收到 CSP violation；该独立用例也按失败保留，未作为游戏通过。[CORS 原始结果](./evidence/native-game-discovery/historical-native-texture-cors-failure.json)、[失败摘要](./evidence/native-game-discovery/historical-native-cdn-diagnostic-test-summary.json)。

正常严格 TLS、带实际游戏 Origin 的匿名 GET 取得两份有效 PNG：planes 响应有 `Access-Control-Allow-Origin: *`，world-sprites 虽为 200、775,328 字节且 SHA 正确，却没有该头，与原 WKWebView 的跨域读取失败和渲染 alert 一致。[精确 live renderer URL / PNG / 头证据](./evidence/native-game-discovery/historical-native-star-cdn-readiness.json)；首次无效文件名预检也[原样保留](./evidence/native-game-discovery/historical-native-star-cdn-preflight-invalid-path.json)，不纳入真实必要资源的因果分析。三层证据一致，但不证明唯一根因或整个 CDN 故障，[综合分析](./evidence/native-game-discovery/historical-native-analysis.json)保留边界。当前 `9ba` 源码已将相同字节 / SHA 的必要 PNG 改为同源资源并完成本地验证，但尚未部署；本轮未修改 CDN、放宽 CORS / CSP、安装 CA或绕过 TLS。因此 Star 现网离线基线仍受必要素材可读性阻断，不能重复超时后记为通过。

本轮实际取得了现网公开 HTML 和静态资源的字节 SHA，但生产 Play 部署 Git 仍未知，[观测版本指纹](./evidence/native-game-discovery/historical-native-https-readiness.json)不证明它与 `540e8e34…` 或 `9ba` 一致。旧 native＋该生产观测与当前 `9ba` 回环的来源、事件、动画、方向和统计方法不同，不能直接计算 30% 提升，也不能称为完整固定旧 native / Play 源码的全部模式基线。M0.1、M3.3、M4 与 M5.1 的未完成门槛保持。

旧 Portal 的自动登录提示另做了只读源码核对：新有效 native 直达通过布局隐藏 Header，五子棋本页不请求会话，原生也只对 `requiresLogin` 模式发起登录。但当前 `9ba` 关闭联机且缺少 CloudBase 运行配置，Header 的自动 refresh 另受配置门禁阻止；因此 preview 没弹登录，不能证明完整 SSO 配置下不会请求宿主授权。授权若实际到达原生，访客仍会显示登录。旧 Portal 的提示不单独构成新直达回归证据，完整配置下的渲染行为仍需在兼容环境中验收。[源码及候选边界审计](./evidence/native-game-discovery/native-guest-authorization-source-audit.json)。

## 已修复且保留记录的问题

- 初版星纸 manifest 包含 `?webgl=1`，不符合原生清单的无 query 策略，准备被明确拒绝；一次真实启动还在等待渲染器时超时。另只读 GET 发现纹理 CDN 缓存缺少跨域头，不能仅凭 HUD 就声称可操作。
- 当前候选构建将两张必要 PNG 和一张已登记 CSS AVIF 以已核验的原字节 / 摘要路径作为同源静态资源打包；没有转码或修改线上 CDN；该轮未改 ready，后续单独查出并修正了事件门槛。导出测试验证实际 public 文件和原生 URL 约束，修正后两款本地预检与 N10 全部通过。未登记的装饰性网络资源仍可能在线获取，不宣称整站离线。
- 初次同版本入口对照曾错误要求全程 SPA；真实页面会完整跳转，因此整轮失败。修正为逐文档采样后，6 样本预检及 60 样本正式对照通过，没有强行改变导航或伪造 ready。
- 首次 runtime fixture 断言完成后有 3 个独占 WebKit store 删除失败，结果被中断，不能作为通过证据。修正强引用生命周期及有界删除重试后 22 项通过；3 个旧 UUID 通过白名单专项清理确认不存在。专项清理最初触发 WebKit 未初始化枚举崩溃，先以无网络 nonPersistent WebView 初始化后重跑通过；没有清空模拟器或用户数据。

## 本轮新增验证与待完成验收

星纸短横屏已完成整改并在最终 `9ba07032…` 的实际原生 WKWebView 再次验证 tutorial / local / pve 三模式：874 × 324 视口，CSS 安全区域 62 / 62 / 20 与 UIKit 一致；教程场景高 166 px，本地 / PVE 为 210 px，五个触控及菜单均在安全区内且至少 44 pt。指引展开暂停输入，关闭后焦点回到指引入口并恢复控制。[最终布局原始数据](./evidence/native-game-discovery/operable-final-native-layout.json)；中间目录的[历史布局](./evidence/native-game-discovery/compact-native-layout.json)仍保留。

寻乐和工坊在最大 AX XXXL 下完成 sufficientElementDescription、trait、textClipped、dynamicType、hitRegion 审计，未过滤问题，最终两屏均为零问题。首次发现原生搜索提示被系统截断，现按辅助功能字号改为简短的「搜索游戏」，不限制用户字体大小。[寻乐审计](./evidence/native-game-discovery/maximum-text-games-audit.json)、[工坊审计](./evidence/native-game-discovery/maximum-text-workshop-audit.json)、[最终测试摘要](./evidence/native-game-discovery/maximum-text-final-summary.json)。

随后使用 Xcode 27 的 [XCUIVoiceOverService](https://developer.apple.com/documentation/xcuiautomation/xcuivoiceoverservice) 实际驱动焦点和读取朗读输出，在系统减少动态效果真正开启、UIKit 确认为 true 时完成原生旅程，共 90 条事件。邀请取消回到「寻乐 标题」，一次 next 到「加入房间」；AI 返回直接落在「AI 找应用」。切 Tab 后旁白保留标签栏焦点，测试显式触探可见的工坊标题，再朗读页面。控件以 XCTest 定向双击，文本注入旁白已选择的输入框；这是真实读屏状态下的程序化 UI 验证，不宣称无坐标盲手势或游戏场景内容完整读屏。首批游戏的音频 / 触觉和三维内容读屏仍未专项验收，未声明新增原生能力。[真实旅程](./evidence/native-game-discovery/voiceover-reduce-motion-journey.json)、[测试摘要](./evidence/native-game-discovery/voiceover-reduce-motion-summary.json)。

系统减少动态效果由实际设置控件读取原值 0、开启为 1，结束后恢复 0；VoiceOver 原先关闭，结束后也恢复关闭。[原值](./evidence/native-game-discovery/reduce-motion-before-accessibility.txt)、[启用](./evidence/native-game-discovery/reduce-motion-enabled-accessibility.txt)、[恢复](./evidence/native-game-discovery/reduce-motion-restored-accessibility.txt)。前几轮对「必须零次导航回发起按钮」的额外断言过严，另有 XCTest 点击位置、朗读名称和设置行 / 子开关的驱动修正；均保留为失败。未奏效的焦点代码已撤回，GamesView 与本轮前候选逐字节一致，没有叠加延迟抢焦点。

中间版本又完成 60 样本对照：五子棋旧入口 / 直达 / 准备后 P50 为 1190 / 853 / 831 ms；星纸为 1485 / 1193 / 1181 ms。星纸仍是旧 renderer-ready 口径，其约 20.4% 的数字也不能被上一轮 30.3% 覆盖。[中间版本原始数据](./evidence/native-game-discovery/compact-renderer-ready-n10.json)。可操作事件已在 `9ba07032…` 修复，最终原生重测结果见上表。

最终候选的 ready 改为渲染器完成、真实状态进入 `phase=playing` 后的下一帧，只发送一次；保留三秒开场规则。6 项定向事件测试及其它相关检查合计 64 项通过，58 路由构建通过；[新静态输出的 18 组浏览器布局与状态检查](./evidence/native-game-discovery/candidate-operable-browser-layout.json)全部通过，17 次明确观察到渲染器已就绪但倒计时中未发送宿主 ready，另一次渲染较晚。浏览器检查仍不替代最终原生计时。

本轮还修复了两处缓存问题：Nuxt 合法的 base64url 文件名可由 `-` 开头；资源准备页退出与下一游戏页面创建之间，需要由 runtime 保活当前 principal 的同一 named store。保活仅持有仓库对象，切换身份同步释放，不持有 WebView、不复制登录或存档。[真实故障验收](./evidence/native-game-discovery/resource-fault-acceptance.json)未启用额外诊断 keeper：四次 215 / 215、更新回执 216 / 216 均完整通过。[逐项摘要证据](./evidence/native-game-discovery/resource-cache-probes/baseline-after-preparation.json)保留状态码、字节和 SHA；资源 B 仅为追加测试二进制的回执迁移机制，HTTP 清理仅模拟回收，均不冒称新游戏包跨版或系统实际驱逐。

初始失败与诊断轮次保留在[失败历史](./evidence/native-game-discovery/cache-cold-failure-history.json)。测试 fixture 已停止历史页面加载、复用无网络初始化 keeper、记录系统真实删除回调，失败保留仓库所有权。后补容器 10 / 10 通过；19 次回调中一次返回 in-use，重试后成功，最长回调约 58 ms，[没有把超时当成成功](./evidence/native-game-discovery/runtime-cleanup-callbacks.json)。

补上真实 IndexedDB marker 后，完整缓存故障流程再次通过：准备后、503、错误摘要、取消四份均为 215 / 215；回执 B 为 216 / 216，逐项状态码、字节、SHA 全部正确。每个故障、回执切换及清理 HTTP 后的新游戏页面均真实读回 Cookie / localStorage / IndexedDB，三者仍为 keep；活跃棋局从 2 子到 4 子且同 launch、ready 一次，清理后新开局实际联网获取 42 个资源。[最新故障流程](./evidence/native-game-discovery/resource-cache-probes-idb/native-game-resource-faults.json)、[清理前完整字节校验](./evidence/native-game-discovery/resource-cache-probes-idb/native-game-cache-only-baseline-after-preparation.json)、[测试摘要](./evidence/native-game-discovery/resource-fault-idb-summary.json)。仍未启用额外 store keeper，B 和 HTTP 回收仍是上述明确范围的测试模型。

旧数据保护在当前候选补跑 82 / 82，无跳过，包含 HomeLibrary 25、NativeRuntimeSession 21、LegacyImport 19、WebProfileRepository 17。覆盖云居排序 / Dock 与账号分区、旧契约导入 / 重启保留、真实 Cookie / localStorage / IndexedDB 和仓库重建 / 访客续接，没有以真实账号凭据替代测试身份。[摘要](./evidence/native-game-discovery/storage-upgrade-final-summary.json)、[逐项结果](./evidence/native-game-discovery/storage-upgrade-final-tests.json)。两类存储 fixture 在创建时记录自己的 UUID，释放页面后只移除这些仓库；54 次真实回调包含 17 次暂拒，最终 37 个 UUID 全部成功并再次经 API 确认不存在。[回收记录](./evidence/native-game-discovery/storage-upgrade-cleanup-callbacks.json)。

会话回收补验采用真实 NativeWebRuntime / WKWebView、来源绑定的模拟文档和 lifecycle，容量自动策略在本次进程算得上限 5。容量超限移除最早暂停的五子棋，保护当前星纸；发送 `UIApplication.didReceiveMemoryWarningNotification` 时，有前台则移除暂停游戏，无前台则保留最近暂停的星纸，且直到显式继续才呈现。三项均通过、无跳过，补齐任务 2.3 的本地会话策略验收。[测试摘要](./evidence/native-game-discovery/session-reclamation-summary.json)、[逐项结果](./evidence/native-game-discovery/session-reclamation-tests.json)、[容量场景](./evidence/native-game-discovery/session-reclamation/native-game-session-reclamation-capacity.json)、[有前台通知](./evidence/native-game-discovery/session-reclamation/native-game-session-reclamation-memoryWarning.json)、[全部暂停通知](./evidence/native-game-discovery/session-reclamation/native-game-session-reclamation-memoryWarningWhilePaused.json)。

三项均确认被回收游戏不再作为运行会话，旧「继续」动作不重建页面，最近记录保留；从最近记录重开获得新 WebView / launch，仍使用原 profile，实际 Cookie / localStorage / IndexedDB 均读回 keep。旧 browser 回调和经新 WebKit 通道发来的旧 launch 均不改变新状态，只有新 launch 的合法 ready 被接受。测试结束强持有旧页的回调验证后，旧 browser / WKWebView 弱引用在三项中均释放：[容量](./evidence/native-game-discovery/session-reclamation/native-game-discarded-object-release-capacity.json)、[有前台通知](./evidence/native-game-discovery/session-reclamation/native-game-discarded-object-release-memoryWarning.json)、[全部暂停通知](./evidence/native-game-discovery/session-reclamation/native-game-discarded-object-release-memoryWarningWhilePaused.json)。通知为进程内发送，不等同真实 OS 内存压力、WebContent 终止或 App 重启；对象释放也不证明系统 RAM 回收量。fixture 仅清理自己登记的 7 个仓库，12 次回调中 5 次暂拒，重试后均成功，[清理记录](./evidence/native-game-discovery/session-reclamation-cleanup.json)。

正常主程序另走通五子棋电脑模式 → 原生更多菜单「结束」→ 寻乐最近记录重开 → 实际棋盘 → 收起，画面确认「继续游戏」保留；最后再次结束并留在寻乐。MCP 语义快照遗漏该可见继续行，因此只按截图确认该步，不从这次手动旅程推断存储、对象身份或 ready 耗时。[操作及快照](./evidence/native-game-discovery/manual-native-end-reopen.json)；这些更强断言仍以专项自动验收为准。

另尝试拆分 Header / SSO 加载边界并构建 `41614f57…`。静态 SSR 仍预载 Header / Reka，mode HTML modulepreload 23→25，三款准备清单反而各增加 3 项 / 741,590 B；没有新 N10，不能声称变快。两处改动和对应加载策略测试已精确撤回，`9ba` public / 主流程保持；实验版本仅保留复现输入、图与清单证据。[未采用实验](./evidence/native-game-discovery/startup-load-boundary-experiment.json)。后续已完成上述同一原生时钟的分段诊断，不能把两个不同时钟相减后直接改流程，仍需进一步区分 load 后的等待来源。

创房重试已加入按账号 / 参数隔离的幂等键，服务端原子不存在创建、冲突拒绝，浏览器跨刷新保留同一操作引用；不保存凭据。55 项服务端、5 项客户端及类型检查通过。[幂等验证](./evidence/native-game-discovery/room-creation-idempotency-20261029.json)。按 CloudBase 代码审查技能复核真实安装的 Node SDK 3.18.5 / database 1.4.3，确认事务返回、get 数据形状和 set 参数兼容，未发现源码阻塞；这仍不是线上事务、ACL 或真实冲突恢复验收。[只读审查记录](./evidence/native-game-discovery/cloudbase-final-code-review.json)。

按用户授权，现网普通 SSO 登录、单个自建飞行棋房间、机器人开局和刷新恢复已实测；服务端 rev 持续推进，刷新保持同局。另用同一账号请求观战，发现现网会静默转成玩家并显示托管操作。源码现已改为明确角色冲突并保留原玩家，前端以权威角色限制控制，4 项真实回环及 3 项前端状态测试通过，随后[完整房间 31 项回归](./evidence/native-game-discovery/spectator-role-full-regression.json)也全部通过，尚未部署到现网。[角色验证](./evidence/native-game-discovery/spectator-role-20261029.json)。本轮测试连接已通过游戏内双次确认离开，页面确认「已经离开这间房／当前连接已安全关闭」；未永久删除生产数据。同账号双标签不能算双账号联机验收。

2026-10-29 04:12 CST 再次匿名只读核对：Play 两处 AASA、`/native/catalog-v1.json` 与三款资源清单均返回 404；API health 200、协议版本 3，无凭据 session 返回 401；生产 CORS 允许头尚无新的 `Idempotency-Key`。需要先部署兼容后端，再发布新 Play 静态契约和客户端创房逻辑。因此不能声称生产 Universal Link 或新资源清单已可用。[逐请求证据](./evidence/native-game-discovery/production-final-readiness.json)。

05:28 CST 按同一匿名方法再次检查，结果未变：六处 AASA / 目录 / 清单仍为 404，新幂等请求头仍未被 CORS 允许。[本轮现网前置复核](./evidence/native-game-discovery/production-followup-readiness.json)。本轮没有新增房间或其他生产写入。

06:43 CST 再次匿名只读检查，结果仍未变：六处 AASA / 目录 / 清单 404，health 200 且协议 3，无凭据 session 401；房间 CORS 允许来源与 credentials，但仍未允许 `Idempotency-Key`。[启动诊断后前置复核](./evidence/native-game-discovery/production-startup-followup-readiness.json)。仅发送普通 TLS 的 GET / OPTIONS，没有凭据、Cookie、创房、生产部署或 TestFlight。

08:21 CST 匿名只读续查结果未变：六处 AASA / 原生目录 / 清单最终仍为 404，其中飞行棋清单首次 URLError 后仅作一次有界重试；health 200、协议 3，无凭据 session 401，幂等请求头仍未被 CORS 允许。world-sprites 本轮为 200 且无 ACAO，planes 为 200 且有 `*`；这次 PNG 仅读取 16 字节前缀，不替代前轮完整 SHA 或真实渲染诊断。[逐请求续查及重试](./evidence/native-game-discovery/external-blocker-recheck-1.json)。没有新增生产写入。

现网浏览器测试的[步骤和清理证据](./evidence/native-game-discovery/production-browser-smoke.json)已保存。仍需真实账号的原生登录 / Play 会话联调，冷启动邀请、失效邀请、满员 / 移除、断网 / 回前台 / Web 进程回收 / App 重启的实际对局恢复，以及更多已开放模式旅程。冷启动早到邀请已改为 App 初始化时同步预约账号恢复边界，后续异步 task 消费同一代次；手动切号、取消和新登录仍作废旧意图。结束恢复时按当前代次重新读取权威 overview，修复同账号重选时旧封禁 / 过期回复引起的 Store 与 Session 不一致，同时保护 guest 登录凭证的原子发布。18 项初始恢复测试、完整账号 / 登录及延迟动作回归已通过，但真实 OS 冷启动 Universal Link 仍须发布 AASA 后验收。源码中的失败重试界面和本地协议重连不能替代这些验收。M6 Web 四 Tab 与其他平台仍留作后续；没有生产部署、TestFlight 上传、提交或推送。

## 当前候选与剩余门槛

候选已安装在下述共享模拟器，补验后以正常主程序重新启动并停在寻乐，保留最近游玩，可选择当前开放玩法。预览仅显式开启 DEBUG 回环来源，真实账号入口仍走现有账号服务。[前轮产品指纹](./evidence/native-game-discovery/final-candidate-fingerprints.json)、[上一轮指纹](./evidence/native-game-discovery/followup-candidate-fingerprints.json)、[容量回收候选指纹](./evidence/native-game-discovery/reclamation-candidate-fingerprints.json)、[启动 / 持续游戏候选指纹](./evidence/native-game-discovery/startup-gameplay-candidate-fingerprints.json)、[历史 N10 续验候选与源码指纹](./evidence/native-game-discovery/historical-native-current-candidate.json)、[本轮入口与候选状态](./evidence/native-game-discovery/legacy-native-ui-followup-summary.json)、[原生入口 / 收起 / 恢复记录](./evidence/native-game-discovery/manual-native-candidate-entry.json)。当前主程序 PID 55221，未开启故障 / 追踪开关；云居的「今天来做菜」仅观察到保留，未打开或修改。当前可执行文件为重新构建的指纹，所核对的关键产品源码均与前轮一致，不能称二进制逐字节相同。本轮没有保留实验性的产品源码改动，新增的是定向验收和 fixture 回收。关闭预览环境开关即可回到生产来源；清理准备资源只移除 HTTP 缓存，不删除身份或存档。本轮没有生产变更可回滚。[逐项完成审计](./evidence/native-game-discovery/historical-native-completion-audit.json)中的整体未完成结论保留，旧目录入口缺口由本轮功能旅程补齐。

- 已通过：缓存校验 / 失败保留 / 取消 / 回执迁移及三类网站数据保留、初始账号恢复与早到邀请代次回归、当前开放离线模式的真实 ready、存活会话恢复 N10、容量 / 内存通知三种会话回收策略、82 项旧数据保护回归、短横屏、核心 UI、最大字号语义审计及系统减少动态效果下的实际原生 VoiceOver 定向旅程；另补齐星纸持续 rAF / 长间隔与分进程 RSS 的模拟器诊断记录。
- 未达标：任务 3.3 的 P50 降低 30%；任务 0.1 虽补齐旧 native 五子棋 HTTPS 两条件 N10 及真实目录→详情→portal 功能入口，星纸、完整模式与联机基线仍未完成。
- 待环境具备后验收：原生真实 SSO、OS Universal Link 冷启动、两个真实账号及完整故障恢复、线上 CloudBase 幂等事务。现网缺新静态契约 / AASA / CORS，不能用本地替身或同账号双标签宣称通过。
- 新确认的现网阻断：星纸必要 world-sprites PNG 的跨域读取失败，旧 native 实际渲染与独立探测均失败；源码中的同源素材修复尚未上线，不以 HTTP 200、有效 PNG 字节或 canvas 存在代替可玩验收。
- 覆盖限制仍需保留：VoiceOver 定向操作不等于无坐标盲用或游戏内容完整读屏；容量 / 通知回收已覆盖实际容器策略，但真实 OS 内存压力 / WebContent 退出和更完整的最低系统 / 硬件覆盖不能由这些模拟器数据推断。

## 构建与实验产物

固定复用模拟器 `4502D5E9-9630-4AF0-9050-3C9109139FD0`，未创建、擦除或删除设备；未干扰其他在用模拟器，测试均显式关闭并行克隆。[前轮核对](./evidence/native-game-discovery/final-simulator-audit.json)、[设置恢复](./evidence/native-game-discovery/followup-simulator-audit.json)、[容量续验设备核对](./evidence/native-game-discovery/reclamation-simulator-audit.json)、[启动 / 持续游戏设备核对](./evidence/native-game-discovery/startup-gameplay-simulator-audit.json)、[最新设备核对](./evidence/native-game-discovery/historical-native-simulator-audit.json)。

任务独占目录 `/tmp/yunle-native-games.uGZuY9` 的 DerivedData 和最终 Play public 仍用于当前目标的增量构建、对照测量与本地预览。DEBUG 仅在显式 `YUNLEFUN_PLAY_PREVIEW=1` 时使用固定回环端口 18146，独立 profile / 历史 / 目录缓存；Release 不接受预览来源。

历史测量结束后仅卸载任务独占旧 App，数据目录查询确认不存在，并回收其独占 HistoricalNativeDerivedData；按这些目录的已分配字节口径共回收 588,484,608 B，约 561.2 MiB，不冒称整盘可用空间变化或 keychain 全面清理。旧源码快照、harness / 打包补丁、四份 xcresult、原始 JSON、日志与公开产物指纹保留；当前主程序的 SPM 缓存、DerivedData 和 `9ba` public 继续使用。[精确退役记录](./evidence/native-game-discovery/historical-native-retirement.json)。

真实目录 UI 旅程完成后，又仅停止并卸载本次重新创建的独占旧 App，确认数据容器不存在，删除独占 HistoricalNativeUIBaselineDerivedData；本轮按目录已分配字节口径回收 498,475,008 B，约 475.4 MiB，与前述历史测试构建回收不重叠。原始快照、当前 SPM 缓存和既有结果保留，没有创建、擦除或删除模拟器。[本轮主程序构建与退役记录](./evidence/native-game-discovery/legacy-native-real-ui-build-retirement.json)。

已回收导出证据后的冗余 sysdiagnose 约 198.61 MiB；Play 三轮中间产物及两份旧 public 按无重复历史口径合计约 140.5 MiB；换码构建另回收无重复中间产物约 31.48 MiB；f72c 旧 public 扣除退役证据净回收 16,326,711 字节（约 15.57 MiB）；两轮文档构建输出合计回收 20,082,823 字节（约 19.15 MiB）。旧 public 删除前已归档契约、版本、大小和 SHA，最新 public 保持在用。目标验收后再导出最终证据并回收仍需使用的可重建产物，保护源码、依赖、存档及已归档报告。

本次收尾另将旧 `48b` public 压缩并逐文件校验后移除目录，净回收 5,784,115 字节；[归档用途及回收条件](./evidence/native-game-discovery/historical-static-baseline-archive.json)已记录。`934` 中间输出被最终真实 ready 测量和布局替代，保留清单、脚本、文件 SHA 与原始报告后净回收 16,304,846 字节，[退役记录](./evidence/native-game-discovery/retired-934-static-output.json)。测试遗留仓库按精确 UUID 白名单确认不存在，仅删除所有权摘要一致的临时目录 / 偏好，共回收 2,441 字节；没有清理其他 WebKit store。[最终故障 fixture 回收](./evidence/native-game-discovery/owned-fixture-final-recovery.json)、[早期 fixture 回收](./evidence/native-game-discovery/owned-early-fixture-recovery.json)。当前 `9ba` public 和增量 DerivedData 保持在用。

本轮未采用的 `416` public 和中间产物在保留输入 / 清单 / 哈希后净回收 49,135,876 B；[实验回收记录](./evidence/native-game-discovery/startup-load-boundary-cleanup.json)。MCP 自动导出的两份已被当前 DerivedData 构建替代的测试产品，仅按本任务精确目录回收，扣除保留元数据与日志后净移除 316,261,058 B 文件；[产品回收记录](./evidence/native-game-discovery/followup-mcp-products-cleanup.json)。缓存故障测试结束已关闭本地故障控制并恢复正常 `9ba` 预览，未停用其他任务设备或服务。
