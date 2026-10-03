// kos-music-lx-source-host — LX 音源宿主的启动器：真正的协议实现在
// kos-music-lx-source-host.js（Node 版，CMake 同目录 COPYONLY 安装）。
// 历史上的 QJSEngine 版桥（LxBridge/SourceHost，约 400 行）从未在 main
// 的任何路径上被构造过（两条路径都直接 exec node / 返回 127），已于
// 代码审查时删除——协议的唯一实现以 Node 脚本为准。
#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QDir>

#include <cstdio>

#include <unistd.h>

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    const QString nodeHost = QDir(QCoreApplication::applicationDirPath())
                                 .filePath(QStringLiteral("kos-music-lx-source-host.js"));
    if (!QFileInfo::exists(nodeHost)) {
        std::fprintf(stderr, "LX source runtime is missing: %s\n",
                     qPrintable(nodeHost));
        return 127;
    }
    const QByteArray encodedPath = QFile::encodeName(nodeHost);
    execlp("node", "node", encodedPath.constData(), static_cast<char *>(nullptr));
    std::perror("Unable to start the Node.js LX source runtime");
    return 127;
}
