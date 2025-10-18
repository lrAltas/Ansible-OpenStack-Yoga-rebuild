# Ansible-OpenStack-Yoga-rebuild

## 项目简介

**Ansible-OpenStack-Yoga-rebuild** 是一个基于 **Ansible 自动化框架** 编写的 OpenStack Yoga 版本自动化部署仓库。  
本项目旨在通过标准化的角色结构与模块化任务定义，实现 **从零构建 OpenStack 云计算平台的全流程自动化部署**，支持多节点、可重复执行与幂等化执行。

该项目以“**自维护、自验证、自恢复**”为核心设计理念，旨在让 OpenStack 的部署过程从传统的手动命令堆叠转变为可复用、可追溯、可演进的基础设施即代码（IaC）。

---

## 关于 OpenStack

**OpenStack** 是一个开源的云计算平台，用于构建公有云和私有云。  
它提供了计算（Nova）、存储（Cinder、Swift）、镜像（Glance）、身份认证（Keystone）、网络（Neutron）等核心组件，  
形成一个完整的 IaaS（Infrastructure as a Service，基础设施即服务）解决方案。

**OpenStack Yoga 版** 是 OpenStack 社区的第 25 个稳定版本，于 2022 年发布。  
该版本在性能优化、API 稳定性、安全性和多节点管理方面进行了大幅改进，为构建私有云环境提供了更现代化的基础。

---

## 仓库结构说明

项目采用标准化的 Ansible 目录层次，支持模块化扩展与角色复用。

```
Ansible-OpenStack-Yoga-rebuild/
├── .ansible/                # Ansible 本地缓存与执行环境
├── .vscode/                 # VSCode 工作区配置
├── .git/                    # Git 仓库管理目录
├── ansible.cfg              # 全局配置文件（控制日志、inventory、并发等）
├── collections/             # 已下载的 Ansible 集合（如 community.general 等）
├── requirements.yml          # 集合依赖定义文件
├── tools/                   # 实用脚本与辅助工具（如检测、清理、日志）
├── roles/                   # 核心角色定义（每个服务一个独立角色）
│   ├── env_init/            # 环境初始化（主机配置、依赖安装、时间同步）
│   ├── db_install/          # 数据库服务安装与配置（MariaDB / MySQL）
│   ├── rabbitmq/            # 消息队列服务配置
│   ├── memcache/            # 缓存服务配置
│   ├── keystone/            # 身份认证服务部署
│   ├── glance/              # 镜像服务部署
│   ├── placement/           # Placement 资源服务部署
│   ├── nova/                # 计算服务部署
│   ├── neutron/             # 网络服务部署
│   ├── cinder/              # 块存储服务部署
│   ├── dashboard/           # Horizon 仪表盘部署
│   └── tests/               # 各角色测试与验证任务
└── README.md                # 项目说明文档（本文件）
```

每个角色均采用标准的 Ansible 目录结构：

```
roles/<service>/
├── defaults/     # 默认变量
├── files/        # 静态文件（配置模板依赖文件）
├── handlers/     # 事件触发（如重启服务）
├── meta/         # 角色依赖与元信息
├── tasks/        # 主执行任务
├── templates/    # Jinja2 配置模板
├── tests/        # 测试任务
└── vars/         # 特定变量定义
```

---

## 部署逻辑概览

部署过程遵循自底向上的顺序执行逻辑：

1. **env_init**  
   环境初始化（主机名、NTP、包管理器、基础组件、标志文件机制）

2. **db_install + rabbitmq + memcache**  
   控制节点核心依赖服务部署

3. **keystone**  
   身份认证服务安装、初始化与 token 配置

4. **glance → placement → nova → neutron → cinder → dashboard**  
   各 OpenStack 组件依次部署与注册（包含数据库同步、Endpoint 创建、服务启停检测）

所有角色均内置幂等化逻辑与“标志文件机制（mark file）”，确保命令可重复执行而不破坏现有状态。

---

## 特性亮点

- **全自动部署**：从环境准备到服务启动，全流程无人值守。
- **模块化角色设计**：每个组件独立维护，方便版本更新与重构。
- **幂等执行机制**：任务可多次执行，无需清理环境。
- **安全输入与日志提示**：支持彩色日志与密码隐藏输入。
- **可拓展性强**：可平滑增加新组件或多节点部署逻辑。
- **与官方文档对齐**：严格遵循 [OpenStack Yoga 官方安装文档](https://docs.openstack.org/yoga/) 规范。

---

## 使用方式（示例）

```bash
# 克隆仓库
git clone https://github.com/<yourname>/Ansible-OpenStack-Yoga-rebuild.git
cd Ansible-OpenStack-Yoga-rebuild

# 安装依赖集合
ansible-galaxy collection install -r requirements.yml

# 执行初始化环境
ansible-playbook -i inventory/hosts.yaml roles/env_init/tasks/main.yml

# 部署 Keystone
ansible-playbook -i inventory/hosts.yaml roles/keystone/tasks/main.yml

# 执行完整部署流程
ansible-playbook -i inventory/hosts.yaml site.yml
```

---

## 后续计划

- 支持多节点控制平面部署（HA 模式）
- 增加 Ceph 存储后端自动化集成
- 引入 Prometheus + Grafana 监控角色
- 自动生成部署日志与健康检测报告
- 集成 CI/CD 流水线，实现持续交付与版本验证

---

## 许可证

本项目遵循 [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0) 开源协议。  
欢迎自由使用、修改与分享。

---

## 致谢

- OpenStack 官方社区与文档团队  
- Ansible 开发者与贡献者  
- 所有为云计算开源生态提供力量的技术爱好者

> “自动化不是为了偷懒，而是为了让重复劳动只做一次。”
