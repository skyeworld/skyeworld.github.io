# BGW简介

## 一 、P4

git 路径：https://git.ucloudadmin.com/vnpd

1. bfswitch，与管理平台对接, 主要用于上下线 P4 设备. 例如 P4 设备配置/获取Port、Pipeline、Online、BGP, VRF等配置信息

2. bf-sde， 转发面相关逻辑在此处处理，同时提供了grpc等接口给控制台调用实现读写流表等操作

3. gop4 , 直接根据bfruntime.json生成对应table的读写golang代码

4. fastreconfig， p4设备 fast reconfig 验证。（https://git.ucloudadmin.com/vnpd-vpc3/fastreconfig）

## 二、 BGW

git 路径：https://git.ucloudadmin.com/vnpd-vpc3?utf8=%E2%9C%93&filter=bgw

grafana 监控 ：http://172.27.227.95:3000/?orgId=1

主要功能为解决VPC 3.0首包时延问题，其中包含以下几个服务：

1. bfbgw：部署在P4设备， 主要功能为：  bgw 转发逻辑。
2. bgwmgr： 部署在kun上，每个pod对应一台P4， 故不支持扩缩容。主要功能为： 通过resource-service获取VPC控制面数据下发给P4
3. bgw-checktool : 部署在kun上，每个pod对应一个set，需要与物理网络打通，不支持扩缩容。主要功能为：验证bgw device  forward是否正常；p4设备表项查询。
4. bgw-fwdcheck： 部署在kun上，每个pod对应一个set，需要与物理网络打通，不支持扩缩容。主要功能为： 从resource service获取数据，构造remote_mirror报文发给bgw，接收报文后检查报文是否符合预期。
5. bgw-dbcheck：部署在kun上，每个pod对应一台P4，不支持扩容。主要功能为： 从resource service获取数据，与bgw转发面表项对账
