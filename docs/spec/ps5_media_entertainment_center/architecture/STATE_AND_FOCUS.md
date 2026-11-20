# 状态管理、焦点与导航恢复

## 1. 状态域

建议区分：
- App State：用户配置、当前媒体源、全局设置
- Navigation State：当前路由、页面栈、返回上下文
- Focus State：焦点 ID、焦点区域、输入模式、Overlay 栈
- Library State：筛选、排序、分页、滚动位置
- Detail State：媒体实体、关联内容、展开区状态
- Playback State：引擎状态、进度、音轨、字幕、队列
- UI State：临时弹窗、Toast、加载状态

不要把所有状态塞进一个全局 Store。按生命周期与所有权拆分。

## 2. 焦点 ID 规则

建议使用语义化且稳定的 ID：
- `home.hero.play`
- `home.shelf.continue.item.<mediaId>`
- `detail.primary.play`
- `detail.cast.person.<personId>`
- `player.controls.pause`
- `player.timeline`
- `control_center.audio`

避免用列表 index 作为唯一焦点标识；排序或分页后 index 会变化。

## 3. 空间导航

空间导航策略可按区域定制：
- Shelf：左右移动为主；上下切换相邻 Shelf。
- Grid：按几何距离和方向约束寻找目标。
- Detail：在 Hero 操作区、简介、季集、演职员之间建立明确的区域关系。
- Dialog：焦点限制在 Dialog 内。
- Player OSD：按控件语义设置方向导航，不完全依赖屏幕几何位置。

## 4. 页面恢复

离开页面时保存：
- route identity
- scroll offset
- focused item ID
- selected tab/filter/sort
- expanded/collapsed section
- relevant query state

返回时先恢复数据和布局，再恢复焦点；若焦点目标不存在，选择同一区域最近的有效项。

## 5. 状态与动画

动画应由状态变化驱动，但不能把动画控制器暴露给业务层。Focus Manager 只发出焦点变化，组件内部根据焦点状态执行对应动效。
