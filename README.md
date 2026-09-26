# RXPCombatHide

> 战斗时自动淡化或隐藏 RestedXP 指南窗口，脱战后恢复显示。

无需设置，不修改 RXPGuides 本体。支持多档透明度和淡入淡出速度，可通过 `/rxphide` 命令随时调整。

---

## 目录

- [功能特性](#功能特性)
- [安装](#安装)
- [使用说明](#使用说明)
- [命令一览](#命令一览)
- [透明度档位](#透明度档位)
- [淡入淡出速度](#淡入淡出速度)
- [工作原理](#工作原理)
- [兼容性](#兼容性)
- [常见问题](#常见问题)
- [更新日志](#更新日志)

---

## 功能特性

| 特性 | 说明 |
|---|---|
| **进战自动隐藏** | 进入战斗（`PLAYER_REGEN_DISABLED`）时按当前档位把指南窗口变淡或隐藏 |
| **脱战平滑恢复** | 脱离战斗（`PLAYER_REGEN_ENABLED`）后渐显回完全不透明，不是硬切 |
| **4 档透明度** | 完全隐藏 `0.00` / 几乎透明 `0.12` / 半透明 `0.40` / 稍微透明 `0.70` |
| **3 档速度** | 快 / 标准 / 慢，分别控制淡出与淡入时长 |
| **只动你启用的窗口** | 通过 RXP 自己的 `IsFeatureEnabled()` 逐个查询，不会把"活动物品""活动目标"等你没开的窗口一起放出来 |
| **受保护框架合规** | 战斗锁定期间跳过所有 `IsForbidden()` / `IsProtected()` 框架，不会污染 UI、不会导致技能按不出来 |
| **切场景自动归位** | 战斗中重载界面或切换地图，直接按档位归位，不经过"全亮"的中间态 |
| **状态可自检** | 一条命令打印 RXP 版本、`showEnabled`、各窗口开关状态，排查不用猜 |
| **一条命令复位** | 窗口状态错乱时 `/rxphide reset` 把显示状态对齐回 RXP 自己的设置 |

---

## 安装

### 方法一：下载 ZIP（推荐）

1. 在本页面点右上角 **`Code` → `Download ZIP`**
2. 解压出 `RXPCombatHide` 文件夹
3. 把整个 `RXPCombatHide` 文件夹放进：

   ```
   你的魔兽世界目录\_anniversary_\Interface\AddOns\
   ```

   最终路径应该是：

   ```
   ...\Interface\AddOns\RXPCombatHide\RXPCombatHide.toc
   ...\Interface\AddOns\RXPCombatHide\CombatHide.lua
   ```

4. **完全退出游戏**再重新启动（不是 `/reload`——`Interface\AddOns` 只在游戏启动时扫描）
5. 在角色选择界面的「插件」列表里确认 **RestedXP 战斗中隐藏** 已勾选

### 方法二：git clone

```bash
cd "你的魔兽世界目录/_anniversary_/Interface/AddOns"
git clone https://github.com/SoloWaltz/RXPCombatHide.git
```

### 前置要求

需要已安装 **RestedXP Guides（RXPGuides）**。它是可选依赖（`OptionalDeps`）——
没装 RXPGuides 的话插件会正常加载，但会在登录时提示"等不到 RXPGuides 就绪"，功能自然也不生效。

---

## 使用说明

装好之后**不需要任何设置**，默认就是启用状态，默认档位是「完全隐藏」+「标准」速度。

进一次战斗就能看到效果。如果想先预览，不用真的打怪：

```
/rxphide test
```

窗口会立刻按当前档位淡下去；再执行 `/rxphide show` 恢复。

### 命令

主命令是 **`/rxphide`**，也可以写成 **`/rxpch`** 或 **`/rxpcombathide`**（三个完全等价）。

**直接输入 `/rxphide`（不带参数）就是"主界面"**，会打印当前状态和诊断信息。

---

## 命令一览

| 命令 | 作用 |
|---|---|
| `/rxphide` | 查看状态与当前档位（不带参数时默认执行） |
| `/rxphide mode` | 换一档透明度（循环切换 4 档） |
| `/rxphide speed` | 换一档淡入淡出快慢（循环切换 3 档） |
| `/rxphide on` | 启用本插件 |
| `/rxphide off` | 停用本插件（窗口会立刻恢复正常显示） |
| `/rxphide test` | 手动模拟"进入战斗"，用来确认效果 |
| `/rxphide show` | 手动模拟"脱离战斗"，恢复显示 |
| `/rxphide reset` | 窗口状态错乱时复位回 RXP 自己的设置 |
| `/rxphide status` | 状态 + 完整诊断（RXP 版本、各窗口开关情况） |
| `/rxphide tips` | 开关登录时的那行提示 |
| `/rxphide debug` | 开关详细日志（排查问题时再开） |
| `/rxphide help` | 显示全部命令 |

**简写别名**（少打几个字）：

| 简写 | 等价于 |
|---|---|
| `alpha` | `mode` |
| `state` | `status` |
| `fix` | `reset` |
| `?` | `help` |

命令**不区分大小写，也不区分空格**——`/rxphide MODE`、`/rxphide  mode` 都能用。

### 典型用法

**我只想让它别挡视线，但战斗中还要能看到当前步骤：**

```
/rxphide mode
```

按到「半透明」或「几乎透明」档即可。每按一次会打印当前档位和 alpha 值。

**我想让它慢慢淡出，不要突兀：**

```
/rxphide speed
```

按到「慢」档（淡出 0.35s / 淡入 0.80s）。

**窗口显示状态乱了（比如某个窗口一直不消失）：**

```
/rxphide reset
```

会把所有窗口的显示状态重新对齐回 RXP 自己的"功能是否启用"设置，并报告修复了几个。

**怀疑插件没生效：**

```
/rxphide status
```

会打印 RXPGuides 的版本、`showEnabled`、`isHidden`，以及每个窗口是"开"还是"关"。
如果第一行提示"没取到 RXPGuides 插件对象"，说明 RXPGuides 没装或没启用。

---

## 透明度档位

战斗中窗口降到哪个 alpha，由档位决定。**脱战一律回到 `1.00`。**

| 档位 | alpha | 效果 |
|---|---|---|
| 完全隐藏 | `0.00` | 战斗中完全看不见窗口 |
| 几乎透明 | `0.12` | 只剩一点影子，能瞄一眼当前步骤 |
| 半透明 | `0.40` | 看得清，但明显退到背景里 |
| 稍微透明 | `0.70` | 基本正常显示，只是不抢视线 |

> **注意**：「完全隐藏」档不只是把 alpha 降到 0——它会连同 RXP 自己的总开关一起关掉
> （原因见[工作原理](#工作原理)）。这是必要操作，不是 bug；插件用 `weHid` 标志记住
> "这次是我们关的"，重载界面后会正确还原，不会把你手动关掉的界面重新打开。

---

## 淡入淡出速度

| 档位 | 淡出时长 | 淡入时长 |
|---|---|---|
| 快 | `0.08s` | `0.30s` |
| 标准 | `0.18s` | `0.45s` |
| 慢 | `0.35s` | `0.80s` |

**为什么淡入总比淡出慢？** 因为脱战瞬间玩家正在重新关注界面，突变会显得刺眼；
而进战斗是"让路"，快一点更符合直觉。这个不对称是刻意的。

时长还会按 alpha 跨度缩放——从 0.7 淡到 0.4 比从 1.0 淡到 0.0 快得多，符合视觉直觉。
跨度过小时有 0.10s 保底，否则几帧就走完，看着像瞬切。

---

## 工作原理

这一节写给想改代码或做同类插件的人。

### 1. 复用 RXP 自己的总开关

插件不去逐个猜测 RXP 的框架结构，而是直接复用 RXPGuides 自己的总开关：

```lua
addon.settings.profile.showEnabled
```

它对应官方 `SettingsPanel.lua` 里的 `ToggleActive`。RXP 的所有显示判断都读这个字段，
翻一个值就能覆盖全部窗口——比逐个 `Hide()` 可靠得多，也不会漏掉新版本的窗口。

**注意**：`_G.RXPGuides` 只是挂指南注册函数的命名空间（`RXPGuides.lua:158-160`），
**不是插件对象**，里面没有 `settings` / `enabledFrames`。真正的对象要从 AceAddon 注册表取，
并且用 `obj.settings` 验明正身：

```lua
local ace = LibStub and LibStub("AceAddon-3.0", true)
local obj = ace:GetAddon("RXPGuides", true)
if type(obj) == "table" and obj.settings then ... end
```

### 2. 逻辑与视觉分离

`showEnabled` / `isHidden` **立即切换**——RXP 的任务自动化、地图更新、步骤推进每帧都在读它们，
不能停在中间态。alpha 则独立做动画。两者互不干扰：

```
进战斗 → 立刻置位 showEnabled/isHidden → 同时启动 alpha 动画
```

### 3. 战斗锁定期间不碰受保护框架

这是合规红线。部分 RXP 框架是 `SecureActionButtonTemplate`，此时 `IsForbidden()` 为真，
对它 `Show` / `Hide` 会污染 UI，严重时玩家连技能都按不出来。
（官方 `RXPGuides.lua` 的 `HideInRaid` 同样先判 `IsForbidden`。）

```lua
local function IsFrameOffLimits(frame)
    if frame.IsForbidden and frame:IsForbidden() then return true end
    if frame.IsProtected and frame:IsProtected() and InCombatLockdown() then return true end
    return false
end
```

`SetAlpha` 不在受保护方法之列，所以动画层照常工作。

### 4. 显示时必须逐个查询"功能是否启用"

官方 `ToggleActive` 的写法是：

```lua
if not (isSecure and InCombatLockdown()) and shown then SetShown(...) end
```

无脑 `Show` 会把用户**没开**的窗口（活动物品、活动目标等）一起放出来。所以插件对每个
框架都调 `IsFeatureEnabled()`，只有 `shown == true` 的才恢复显示。

### 5. `SetIgnoreParentAlpha` 必须一起归零

RXP 的箭头框架平时是 `SetIgnoreParentAlpha(true)`——**父框架再怎么透明，它都照常显示**。
不把它一并归零的话，「完全隐藏」档位会漏出一根箭头。

### 6. 防"闪一下"

`alpha = 0` 不等于不可见：如果框架已经被藏起来了，这段渐变在屏幕上根本看不见，
等它自己 `Show` 出来的那一帧就是"闪一下"。所以渐变前先 `Show`，渐变结束后再真正 `Hide`：

```lua
FadeTo(0, false, animate, HideFramesAfterFade)   -- 淡到 0 之后再隐藏
```

### 7. 其他几个容易踩的坑

- **存档引用不能缓存**：`_G` 里的 table 可能在文件执行之后被游戏整体替换，所以 `DB` 不缓存引用，每次读写前重新绑定；设置也要等本插件的 `ADDON_LOADED` 再读。
- **切场景会重建框架**：缓存"要淡化的框架列表"时，指纹带上主窗口对象（`tostring(rxp.RXPFrame) .. "#" .. size`），只比数量会留下失效引用。
- **`weHid` 标志**：「完全隐藏」档会把 `showEnabled` 设成 `false`，这是插件自己的副作用而非用户意图。存进 DB，重载后据此还原；否则光看 `showEnabled` 分不清是谁关的，会永远不恢复。
- **命令名注册**：`SLASH_<组名><槽位>` 里的组名必须**全大写**，且只有 `1..3` 三个槽位有效。写成小写（`SLASH_rxpcombathide1`）不会被采纳，玩家一敲回车就会因为 `SlashCmdList[nil]` 弹 Lua 错误。
- **`/rxp`、`/rxpg`、`/rxpguides` 已被 RXPGuides 本体占用**（`SettingsPanel.lua:269-271`，经 AceConsole 动态注册，源码里搜不到字面量），所以主命令取 `/rxphide`。

---

## 兼容性

| 项目 | 值 |
|---|---|
| 支持客户端 | 燃烧的远征经典版 `2.5.6` / `2.5.5`，经典旧世 `1.15.8` |
| `## Interface` | `20506, 20505, 11508` |
| 前置插件 | RXPGuides（可选依赖） |
| 存档变量 | `RXPCombatHideDB` |
| 版本 | `4.4.0` |

理论上任何有 RXPGuides 的客户端都能用，`## Interface` 只影响客户端是否标记"过期"。

---

## 常见问题

**Q：装完之后完全没有反应？**

先确认两件事：

1. **是否完全退出游戏后重启过？**（`/reload` 不够，`Interface\AddOns` 只在启动时扫描）
2. 输入 `/rxphide status`。如果提示"没取到 RXPGuides 插件对象"，说明 RXPGuides 没装或没启用。

**Q：进战斗窗口没变化？**

检查是不是档位已经在「稍微透明」（`0.70`）——这个档位变化很轻微，容易看不出来。
用 `/rxphide test` 手动模拟一次进战斗，看有没有淡出动作。

**Q：脱战后窗口没回来？**

执行 `/rxphide reset` 复位。如果经常出现，请开 `/rxphide debug` 后把日志发我。

**Q：会不会影响 RXP 的任务自动化？**

不会。插件复用 RXP 自己的 `showEnabled` 字段，走的是官方 `ToggleActive` 的同一套语义，
RXP 的步骤推进和地图更新逻辑不受影响。

**Q：会不会和其他插件冲突？**

只注册了三个斜杠命令（`/rxphide`、`/rxpch`、`/rxpcombathide`），不 hook 任何全局函数，
不注册任何事件之外的框架。登录时会自动检测命令是否被占用，被占用会提示你改用备用命令。

**Q：这个插件会修改 RXPGuides 的文件吗？**

不会。它是完全独立的插件目录，**不改动 RXPGuides 的任何文件**。
卸载时直接删掉 `RXPCombatHide` 文件夹即可，不留残留（除了 `RXPCombatHideDB` 存档）。

---

## 更新日志

### 4.4.0

- 修复淡化期间 `IgnoreParentAlpha` 被永久改写的问题，恢复时还原原设置
- 修复战斗中重新启用插件时不立即生效的问题
- 修复切换地图后完全隐藏档位可能导致窗口不恢复的问题

### 4.3.0

- 撤除图形设置面板，全部功能改由斜杠命令驱动（更轻，也不依赖任何界面文件）
- 新增 4 档透明度与 3 档速度
- 新增 `test` / `show` 手动模拟进战与脱战
- 新增 `reset` 复位窗口显示状态
- 显示恢复时逐个查询 `IsFeatureEnabled()`，不再把用户未启用的窗口一起放出来
- 修复 `SetIgnoreParentAlpha` 未归零导致「完全隐藏」档漏出箭头的问题
- 修复淡入前未先 `Show` 导致的"闪一下"

---

## 许可

MIT License —— 随便用，出问题别找我。

---

**作者**：西瓜烧鱼 ｜ **问题反馈**：请在本仓库开 [Issue](https://github.com/SoloWaltz/RXPCombatHide/issues)
