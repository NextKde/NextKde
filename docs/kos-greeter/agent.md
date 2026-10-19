# agent.md

用户指定的小写入口。完整规范唯一来源为 [AGENTS.md](AGENTS.md)。请阅读该文件及 [硬约束](constraints.md)，不要维护两套互相矛盾的指令。

每次任务完成后必须调用未参与该任务编写或实现的独立子代理审查；修复后复审，通过完成门槛才能关闭任务。具体要求以 [AGENTS.md](AGENTS.md) 和 [独立审查规则](REVIEW_POLICY.md) 为准。
