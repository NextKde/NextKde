#pragma once
#include <QString>

// 通用缓存目录维护服务:目录超过阈值时,按文件 mtime 从旧到新删除(LRU),
// 直到回到阈值内。以后 kos 新增的磁盘缓存(缩略图、字体、导出文件等)都
// 从这里走,不要各自手写清理。
//
// 约束:
// - 全程在全局线程池执行,绝不阻塞/触碰 UI 线程;扫描本身也是惰性的——
//   每次应用启动调度一次,阈值内直接返回,不做任何写操作。
// - 同一时刻只允许一个清理任务(全局串行),重复调度被吞掉。
// - 只删 dir 内的普通文件,不递归、不删目录本身。
namespace CacheMaintenance {

// 例:schedule(thumbDir, 64 * 1024 * 1024, 500)
void schedule(const QString &dir, qint64 maxBytes, int maxFiles);

} // namespace CacheMaintenance
