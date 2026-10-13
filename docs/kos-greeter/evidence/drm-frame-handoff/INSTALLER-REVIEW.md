# 文件安装器独立复审

日期：2026-10-13。实施者：/root/complete_coordinator；独立只读审核：/root/review_frozen_handoff。

范围：tools/install-greeter-handoff.py、tools/install-greeter-handoff.sh、tools/test-greeter-handoff-install.py、apps/greeter/experimental/drm-handoff/systemd/INSTALL.md。

结论：文件安装范围通过，可交付无参数安装命令和--check。只安装/opt/kos-handoff，不替换/usr/bin，不启用或重启服务；不等于启用黑屏修复。

P2关闭：升级第一次rename后中断导致final缺失时，rollback可从可信previous恢复，仍拒绝覆盖displaced；隔离模拟测试通过。固定文件清单、SHA校验、root目录/锁、O_NOFOLLOW、私有库SONAME/RPATH、备份/卸载无开放阻断项。真实产物prepare/check及wrapper--check通过；没有执行宿主安装。

最终INSTALLER-SHA256.json SHA256：652cf80cc5a711b5927d871c584781a6a36707a7b6b2026912af48e4850a8b5f。

安装器Python SHA256：814bd8bef66632108f0c3ad77a8be6322b9a1d343ae4a27fd90928ef50bd8150。

安装器shell SHA256：82dd06ecbae7ac570250734eb4177232d17c57872978286a1e184037bfe0b654。

独立核验全部匹配。结论只覆盖文件安装，真实DRM/PAM/VT/宿主黑屏仍未验收。
