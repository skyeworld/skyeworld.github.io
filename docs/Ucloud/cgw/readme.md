# CGW简介

## 一 、P4

git 路径：https://git.ucloudadmin.com/vnpd

1. bfswitch，与管理平台对接, 主要用于上下线 P4 设备. 例如 P4 设备配置/获取Port、Pipeline、Online、BGP, VRF等配置信息

2. bf-sde， 转发面相关逻辑在此处处理，同时提供了grpc等接口给控制台调用实现读写流表等操作

3. gop4 , 直接根据bfruntime.json生成对应table的读写golang代码

4. fastreconfig， p4设备 fast reconfig 验证。（https://git.ucloudadmin.com/vnpd-vpc3/fastreconfig）

## 二 、cgw

 git 路径：https://git.ucloudadmin.com/vnpd-vpc3?utf8=%E2%9C%93&filter=cgw

 grafana 监控 ：http://172.27.227.95:3000/?orgId=1

实现一致性Hash和重定向功能，其中包含一下几个服务：

1. bfcgw：部署在P4设备，主要功能为：  cgw 转发逻辑。
2. cgw-service：部署在kun上，支持扩缩容。主要功能为：接收管理平台对本地域 cgw 进行管理. 其中包含 VIP、SET、分片集 群、ECMP 集群、device 等. cgw-service 将接收到的请求持久化在 DB 的同时，将事件写入 resource-service 。
3. cgwmgr： 部署在kun上，每个pod对应一个pipeline，不支持扩缩容。主要功能为：watch resource-service 接收 cgw-service 的配置变更后，通过调 用 bf-sde 的 grpc 接口下发表项给对应 cgw 设备 。
4. cgw-checktool： 部署在kun上，需要与物理网络打通，不支持扩缩容。主要功能为： 验证cgw device bgp 连通性；验证cgw灰度功能；根据cgw device中表项获取ECMP Cluster、Redirect Cluster数据。
5. cgw-fwdcheck：部署在kun上，每个pod对应一个set，需要与物理网络打通，，不支持扩缩容。主要功能为： 通过调用cgw-service接口获取database数据, 构造remote_mirror报文发送给cgw，接收报文后检验报文是否符合预期。
6. cgw-dbcheck：部署在kun上，每个pod对应一个pipeline，不支持扩缩容。主要功能为： 通过调用cgw-service接口获取database数据，与各cgw设备表项进行对账。
7. cgw-monior：部署在kun上，单点服务。主要功能为：收到 cgw-rr 的 BGP 变更后同步给 cgw-service。无ECMP集群时，暂可不上上线。
8. cgw-rr： 部署在kun上，不支持扩缩容。主要功能为：与 ECMP 集群的业务设备建立 BGP， 并将 BGP 状态同步给 cgw-monitor 。无ECMP集群时，暂可不上上线
